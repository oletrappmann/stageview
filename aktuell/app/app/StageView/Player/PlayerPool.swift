import AVFoundation
import AVKit
import SwiftUI

/// Wiedergabe im Player: ein AVPlayer pro Video, gehalten werden nur das aktuelle und seine beiden Nachbarn. Die Nachbarn laden
/// schon die ersten Sekunden, so steht beim Wischen sofort ein Bild da und das Video läuft ohne Warten los. Mux liefert HLS
/// (stream.mux.com), AVPlayer wählt die Qualität selbst passend zur Verbindung.
@MainActor
@Observable
final class PlayerPool {
    private(set) var players: [String: AVPlayer] = [:]
    private(set) var activeID: String?

    // Zustand des aktiven Videos
    var playing = false
    var buffering = false
    var time: Double = 0
    var duration: Double = 0
    var ended = false
    /// Pausiert auf einen Kommentar gesprungen: großen Play Knopf nicht zeigen (Ole, 23.11.2026), bis wieder abgespielt oder
    /// selbst angehalten wird oder ein anderes Video kommt
    var quietPause = false
    /// Endlosschleife (Ole, 23.11.2026: „bei Einstellungen eine Endlosschleife, standardmäßig nicht aktiviert“): am Ende von vorn,
    /// pro Gerät gemerkt, gilt für jedes Video und auch im Vollbild
    static let loopKey = "sv.schleife"
    var loops: Bool = UserDefaults.standard.bool(forKey: PlayerPool.loopKey) {
        didSet { UserDefaults.standard.set(loops, forKey: Self.loopKey) }
    }
    var speed: Float = 1 { didSet { applySpeed() } }
    var muted = false { didSet { players.values.forEach { $0.isMuted = muted } } }
    /// Qualität wie im Zahnrad der Videoseite: nil = Auto, sonst höchstens diese Stufe (kurze Seite in Pixeln, 1080 = 1080p)
    var quality: Int? { didSet { applyQuality() } }
    /// Stufe, die bei Auto gerade läuft (für „Auto · 1080p“)
    var currentHeight: Int?
    /// Stufen pro Video aus der HLS Liste von Mux
    private var renditions: [String: [Int]] = [:]
    private var videosByID: [String: Video] = [:]

    static let speeds: [Float] = [0.75, 1, 1.25, 1.5, 2]
    static func speedText(_ rate: Float) -> String { rate == 1 ? "Normal" : rate.formatted(.number.precision(.fractionLength(0...2))) + "×" }
    static func qualityText(_ height: Int) -> String { height >= 2160 ? "4K" : height >= 1440 ? "1440p" : "\(height)p" }

    /// Letzte Stelle pro Video, damit man beim Zurückwischen dort weiterschaut
    private var positions: [String: Double] = [:]
    private var timeObserver: Any?
    private weak var observed: AVPlayer?
    private var observations: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func player(for video: Video) -> AVPlayer? {
        if let player = players[video.id] { return player }
        guard let url = video.hlsURL else { return nil }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 6
        videosByID[video.id] = video
        limit(item, aspect: video.aspect)
        if renditions[video.id] == nil { Task { await loadRenditions(video) } }
        let player = AVPlayer(playerItem: item)
        player.isMuted = muted
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .pause
        players[video.id] = player
        return player
    }

    /// Nur diese Videos halten (aktuelles und Nachbarn), alle anderen geben ihren Speicher frei
    func keep(_ videos: [Video]) {
        let ids = Set(videos.map(\.id))
        for (id, player) in players where !ids.contains(id) {
            positions[id] = player.currentTime().seconds.isFinite ? player.currentTime().seconds : positions[id]
            player.pause()
            player.replaceCurrentItem(with: nil)
            players[id] = nil
        }
        for video in videos { _ = player(for: video) }
    }

    /// Dieses Video wird das aktive: die anderen halten an, dieses läuft (wenn gewünscht) los
    func activate(_ video: Video, autoplay: Bool, at start: Double? = nil) {
        guard let player = player(for: video) else { return }
        if activeID != video.id {
            for (id, other) in players where id != video.id { other.pause() }
            observe(player)
            activeID = video.id
            duration = video.duration
            ended = false
            quietPause = false
            if let start { seek(to: start) } else if let saved = positions[video.id], saved > 1, saved < video.duration - 1 { seek(to: saved) }
        } else if let start {
            seek(to: start)
        }
        if autoplay { play() }
    }

    func play() {
        quietPause = false
        guard let player = activePlayer else { return }
        if ended || (duration > 0 && time >= duration - 0.25) { player.seek(to: .zero); ended = false }
        player.defaultRate = currentRate
        player.play()
    }

    /// Bildrate des laufenden Videos (nil = unbekannt)
    var activeFPS: Double? { activeID.flatMap { videosByID[$0]?.fps } }

    /// Anhalten genau auf einem ganzen Bild (Ole, 23.11.2026: „genauer, wenn man Pause drückt“): die Zeit ist dann genau das Bild,
    /// das man sieht, und so landet auch der Kommentar
    func pause() {
        quietPause = false
        guard let player = activePlayer else { return }
        player.pause()
        // Läuft gerade ein genauer Sprung (Tipp auf einen Kommentar, Spulen), liegt sein Ziel schon auf einem ganzen Bild. Dann nicht
        // die alte Stelle lesen und zurückspringen (23.11.2026, Ole: Tipp auf einen Kommentar ging nicht an seine Zeit)
        if seekBusy || seekNext != nil { return }
        let now = player.currentTime().seconds
        guard now.isFinite, activeFPS != nil else { return }
        let target = Timecode.snap(now, fps: activeFPS)
        time = target
        preciseSeek(player, to: target)
    }

    /// Spulen im Pausenzustand: jedes Mal genau aufs Bild, aber nie mehr als ein Sprung gleichzeitig (der nächste wartet), so bleibt
    /// die Vorschau flüssig und man kann einzelne Bilder treffen
    private var seekBusy = false
    private var seekNext: Double?

    private func preciseSeek(_ player: AVPlayer, to target: Double) {
        if seekBusy { seekNext = target; return }
        seekBusy = true
        player.seek(to: CMTime(seconds: target, preferredTimescale: 120_000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.seekBusy = false
                if let next = self.seekNext {
                    self.seekNext = nil
                    self.preciseSeek(player, to: next)
                }
            }
        }
    }

    func toggle() { playing ? pause() : play() }

    func seek(to seconds: Double, exact: Bool = true) {
        guard let player = activePlayer else { return }
        let target = max(0, min(seconds, duration > 0 ? duration - 0.05 : seconds))
        time = target
        ended = false
        // Genau: aufs Bild gelegt. Beim Spulen ohne Abspielen ebenfalls genau, damit man einzelne Bilder treffen kann
        if exact || !playing {
            let snapped = activeFPS != nil ? Timecode.snap(target, fps: activeFPS) : target
            time = snapped
            preciseSeek(player, to: snapped)
            return
        }
        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    func skip(_ delta: Double) { seek(to: time + delta) }

    func stopAll() {
        for player in players.values { player.pause(); player.replaceCurrentItem(with: nil) }
        players = [:]
        unobserve()
        activeID = nil
    }

    var activePlayer: AVPlayer? { activeID.flatMap { players[$0] } }

    private var currentRate: Float { speed }

    /// Stufen fürs Zahnrad (höchstens vier, ab 360p, wie auf der Videoseite)
    func qualities(for video: Video) -> [Int] { Array((renditions[video.id] ?? []).filter { $0 >= 360 }.prefix(4)) }

    private func loadRenditions(_ video: Video) async {
        guard let url = video.hlsURL, let (data, _) = try? await URLSession.shared.data(from: url), let text = String(data: data, encoding: .utf8) else { return }
        let sizes = text.matches(of: /RESOLUTION=(\d+)x(\d+)/).compactMap { m -> Int? in
            guard let w = Int(m.1), let h = Int(m.2) else { return nil }
            return min(w, h)
        }
        renditions[video.id] = Array(Set(sizes)).sorted(by: >)
    }

    private func applyQuality() {
        for (id, player) in players { if let item = player.currentItem { limit(item, aspect: videosByID[id]?.aspect ?? 0.5625) } }
    }

    /// Obergrenze der Auflösung: kurze Seite höchstens `quality` (Auto ohne Grenze)
    private func limit(_ item: AVPlayerItem, aspect: Double) {
        guard let q = quality else { item.preferredMaximumResolution = .zero; return }
        let short = CGFloat(q) + 1
        item.preferredMaximumResolution = aspect >= 1 ? CGSize(width: short * aspect + 1, height: short) : CGSize(width: short, height: short / aspect + 1)
    }

    private func applySpeed() {
        guard let player = activePlayer else { return }
        player.defaultRate = currentRate
        if playing { player.rate = currentRate }
    }

    // MARK: Beobachten

    private func observe(_ player: AVPlayer) {
        unobserve()
        observed = player
        player.defaultRate = currentRate
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.observed === player else { return }
                // Während eines genauen Sprungs meldet AVPlayer noch die alte Stelle, die Anzeige bleibt dann beim Ziel
                if t.seconds.isFinite, !self.seekBusy { self.time = t.seconds }
                if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { self.duration = d }
                if let size = player.currentItem?.presentationSize, size.width > 0 { self.currentHeight = Int(min(size.width, size.height)) }
            }
        }
        observations = [
            player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
                Task { @MainActor in
                    guard let self, self.observed === p else { return }
                    self.playing = p.timeControlStatus != .paused
                    if self.playing { self.quietPause = false }
                    self.buffering = p.timeControlStatus == .waitingToPlayAtSpecifiedRate
                }
            },
        ]
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.observed === player else { return }
                self.ended = true
                // Schleife: gleich wieder von vorn (play() legt bei ended auf den Anfang), kein „Als Nächstes“
                if self.loops { self.play(); return }
                self.playing = false
            }
        }
        playing = player.timeControlStatus != .paused
        time = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
    }

    private func unobserve() {
        if let timeObserver, let observed { observed.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observations.forEach { $0.invalidate() }
        observations = []
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let observed, let id = activeID { positions[id] = observed.currentTime().seconds }
        observed = nil
    }
}

/// Bildfläche für einen AVPlayer (AVPlayerLayer). Meldet, sobald das erste Bild da ist, dann blendet das Standbild aus.
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer?
    var fill = false
    var ready: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.backgroundColor = .clear
        view.onReady = ready
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        view.onReady = ready
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var onReady: (Bool) -> Void = { _ in }
        private var watch: NSKeyValueObservation?

        override init(frame: CGRect) {
            super.init(frame: frame)
            watch = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                let ready = layer.isReadyForDisplay
                DispatchQueue.main.async { self?.onReady(ready) }
            }
        }

        required init?(coder: NSCoder) { fatalError() }
    }
}

/// Vollbild über Apples eigenen Player (Ole, 22.11.2026: „beim Vollbild einfach den normalen Apple Player“). Derselbe AVPlayer,
/// es läuft an derselben Stelle weiter. Nur solange er offen ist, darf sich die App drehen, danach wieder hochkant.
@MainActor
enum Fullscreen {
    static func present(_ player: AVPlayer, closed: @escaping () -> Void) {
        guard let top = topController() else { return closed() }
        AppDelegate.orientations = .allButUpsideDown
        let controller = ClosingPlayerController()
        controller.player = player
        controller.closed = closed
        controller.allowsPictureInPicturePlayback = true
        controller.modalPresentationStyle = .fullScreen
        top.present(controller, animated: true) { player.play() }
    }

    static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

final class ClosingPlayerController: AVPlayerViewController {
    var closed: () -> Void = {}

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard presentingViewController == nil || isBeingDismissed else { return }
        AppDelegate.orientations = .portrait
        if let scene = Fullscreen.topController()?.view.window?.windowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            Fullscreen.topController()?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        closed()
    }
}
