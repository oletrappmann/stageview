import SwiftUI
import UIKit

/// Storyboard eines Videos von Mux (storyboard.vtt plus ein Bild mit allen Kacheln), wie auf der Videoseite (projekt.html,
/// lichtLaden). Einmal pro Video geladen und gemerkt, die Kacheln werden klein gerechnet, damit das Licht weich und billig bleibt.
@MainActor
@Observable
final class Storyboard {
    struct Tile { let start: Double; let end: Double; let rect: CGRect }

    private(set) var tiles: [Tile] = []
    private(set) var failed = false
    @ObservationIgnored private var sheet: CGImage?
    @ObservationIgnored private var small: [Int: UIImage] = [:]

    private static var all: [String: Storyboard] = [:]

    static func of(_ playbackID: String) -> Storyboard {
        if let board = all[playbackID] { return board }
        let board = Storyboard()
        all[playbackID] = board
        Task { await board.load(playbackID) }
        return board
    }

    /// Kachel zur Zeit t (nach dem Ende die letzte)
    func index(at t: Double) -> Int? {
        guard !tiles.isEmpty else { return nil }
        return tiles.firstIndex { t >= $0.start && t < $0.end } ?? tiles.count - 1
    }

    /// Kachel als kleines Bild (48 pt breit), weich genug für das Licht
    func image(_ i: Int) -> UIImage? {
        if let cached = small[i] { return cached }
        guard let sheet, tiles.indices.contains(i), let tile = sheet.cropping(to: tiles[i].rect) else { return nil }
        let width: CGFloat = 48, height = max(1, (width * CGFloat(tile.height) / CGFloat(max(tile.width, 1))).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            UIImage(cgImage: tile).draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        small[i] = image
        return image
    }

    private func load(_ playbackID: String) async {
        do {
            guard let url = URL(string: "https://image.mux.com/\(playbackID)/storyboard.vtt") else { throw URLError(.badURL) }
            let (data, _) = try await URLSession.shared.data(from: url)
            let text = String(decoding: data, as: UTF8.self)
            let pattern = try Regex(#"([\d:.]+) --> ([\d:.]+)\s+(\S+?)#xywh=(\d+),(\d+),(\d+),(\d+)"#)
            var found: [Tile] = []
            var imageURL: URL?
            for match in text.matches(of: pattern) {
                let part = { (i: Int) in match.output[i].substring.map(String.init) ?? "" }
                guard let x = Double(part(4)), let y = Double(part(5)), let w = Double(part(6)), let h = Double(part(7)) else { continue }
                found.append(Tile(start: Self.seconds(part(1)), end: Self.seconds(part(2)), rect: CGRect(x: x, y: y, width: w, height: h)))
                if imageURL == nil { imageURL = URL(string: part(3)) }
            }
            guard let imageURL, !found.isEmpty else { throw URLError(.cannotParseResponse) }
            let (imageData, _) = try await URLSession.shared.data(from: imageURL)
            guard let image = UIImage(data: imageData)?.cgImage else { throw URLError(.cannotDecodeContentData) }
            sheet = image
            tiles = found
        } catch {
            failed = true
        }
    }

    private static func seconds(_ text: String) -> Double {
        text.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }
}

/// Licht wie bei YouTube und auf der Videoseite: eine weiche, größere Kopie der aktuellen Stelle hinter dem Video (1,25 fach,
/// stark weichgezeichnet, satter, halbe Deckkraft). Wechselt höchstens alle 1,2 s und blendet dabei 1,2 s über, nach dem Spulen
/// sofort. Ohne Storyboard nimmt es das Standbild.
struct AmbientLight: View {
    let video: Video
    /// Laufende Zeit des aktiven Videos, nil für die Nachbarn (zeigen den Anfang)
    let time: Double?
    let size: CGSize

    @State private var shownIndex = -1
    @State private var shown: UIImage?
    @State private var lastSwap = Date.distantPast
    @State private var lastTime: Double = 0

    private var board: Storyboard? { video.playbackID.map(Storyboard.of) }

    var body: some View {
        let width = size.width * 1.25, height = size.height * 1.25
        ZStack {
            if let shown {
                Image(uiImage: shown)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: width, height: height)
                    .id(shownIndex)
                    .transition(.opacity)
            } else if board?.failed == true {
                RemoteImage(url: video.thumbnail(width: 160), placeholder: .clear)
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .blur(radius: 34)
        .saturation(1.25)
        .opacity(0.5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { update(force: true) }
        .onChange(of: board?.tiles.count ?? 0) { _, _ in update(force: true) }
        .onChange(of: time) { _, _ in update(force: false) }
    }

    private func update(force: Bool) {
        let t = time ?? min(2, video.duration / 2)
        // Gespult (Sprung über 2 s): gleich die neue Stelle, sonst ruhig alle 1,2 s
        let jumped = abs(t - lastTime) > 2
        lastTime = t
        guard let board, let i = board.index(at: t), i != shownIndex else { return }
        if !force && !jumped && Date().timeIntervalSince(lastSwap) < 1.2 { return }
        lastSwap = Date()
        let image = board.image(i)
        if shown == nil {
            shownIndex = i
            withAnimation(.easeOut(duration: 0.6)) { shown = image }
        } else {
            withAnimation(.easeInOut(duration: 1.2)) {
                shownIndex = i
                shown = image
            }
        }
    }
}
