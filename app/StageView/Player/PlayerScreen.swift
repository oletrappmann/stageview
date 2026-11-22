import AVKit
import SwiftUI

/// Welches Video der Player öffnen soll (von der Liste, der Projektseite oder einem Kommentar)
struct PlayerRequest: Identifiable, Equatable {
    let id = UUID()
    var projectKey: String
    var videoID: String
    var time: Double?
    /// Vorschaubild, aus dem der Player herauswächst (zoom), nil ohne Übergang
    var sourceID: String?
    /// Angetippter Kommentar: Blatt offen, Kommentar hervorgehoben, Video steht an der Stelle
    var comment: Int?
}

/// Stufen des Blatts unter dem Video, wie auf der Videoseite am Handy (projekt.html, BLATT): zu = nur Steuerung (Video am größten),
/// mitte = dazu das einzeilige Kommentarfeld (Standard), offen = Freigabe, Kommentare und „Mehr aus“.
enum SheetStop: CaseIterable { case zu, mitte, offen }

/// Der Player der App, aufgebaut wie die Videoseite am Handy (Ole, 22.11.2026: „so wie beim Web, das Element, das man hochziehen
/// kann und das wieder größer wird, mit dem Licht im Hintergrund“): oben das Video mit Ambient Licht, darunter ein Blatt mit Griff
/// in drei Stufen. Seitlich wischen auf dem Video wechselt das Video, die Nachbarn sind schon geladen. Quer gedreht: Apples Player.
struct PlayerScreen: View {
    let request: PlayerRequest

    @State private var store = Store.shared
    @State private var pool = PlayerPool()
    @State private var currentID: String?
    @State private var started = false
    @State private var scrubbing = false
    @State private var draft = ""
    @State private var attachTime = true
    @State private var draftTime: Double = 0
    @State private var replyTo: Comment?
    @State private var editing: Comment?
    @State private var deleting: Comment?
    @State private var renaming: Video?
    @State private var renameText = ""
    @State private var removing: Video?
    @State private var fullscreen = false
    /// Zahnrad Menü wie im Web (offen für dieses Video), Drehung des Zahnrads und wo es steht
    @State private var settingsVideo: Video?
    @State private var gearTurns: Double = 0
    @State private var gearFrame: CGRect = .zero
    @State private var sending = false
    @State private var commentFilter = CommentFilter.all
    /// Kommentar, mit dem der Player geöffnet wurde (Ole, 22.11.2026: „Kommentar antippen: der Kommentar geht auf und ist hervorgehoben“)
    @State private var focusComment: Int?
    // Blatt
    @State private var stop: SheetStop = .mitte
    @State private var dragBase: CGFloat?
    @State private var dragY: CGFloat = 0
    @State private var dragSideways = false
    @State private var headHeight: CGFloat = 96
    /// Zuletzt berechnete Stufen, für das Ziehen über die Zeitleiste
    @State private var stopsBox = StopsBox()
    @State private var fieldHeight: CGFloat = 50
    @FocusState private var composing: Bool
    @Environment(\.dismiss) private var dismiss

    private static let headerHeight: CGFloat = 56
    private static let viewer = Color(UIColor(hex: 0x050505))
    private static let panel = Color(UIColor(hex: 0x1E1E1C))
    private static let panel2 = Color(UIColor(hex: 0x2A2A27))
    /// Federkurve des Blatts, nah an Apples Blättern (Web: cubic-bezier(.32,.72,0,1) in 0,52 s)
    private static let sheetSpring = Animation.spring(response: 0.5, dampingFraction: 0.88)

    private var project: Project? { store.project(request.projectKey) }
    private var videos: [Video] { project?.videos ?? [] }
    private var current: Video? { videos.first { $0.id == currentID } ?? videos.first }
    private var index: Int { videos.firstIndex { $0.id == current?.id } ?? 0 }
    private var review: ReviewStore? { project?.code.map(ReviewStore.of) }

    enum CommentFilter: String, CaseIterable { case all = "Alle", open = "Offen", done = "Erledigt" }

    var body: some View {
        GeometryReader { geo in
            let stops = sheetStops(total: geo.size.height)
            let sheetHeight = liveHeight(stops)
            let _ = updateStops(stops)
            VStack(spacing: 0) {
                header
                    .frame(height: Self.headerHeight)
                    .zIndex(2)
                if videos.isEmpty {
                    empty.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    pager(width: geo.size.width, height: max(90, geo.size.height - Self.headerHeight - sheetHeight))
                        .zIndex(0)
                    sheet(height: sheetHeight, stops: stops)
                        .zIndex(3)
                }
            }
        }
        .background(Self.viewer.ignoresSafeArea())
        // Teilen Fenster über dem Player
        .overlay {
            if let request = store.share {
                ShareDialog(request: request) { store.share = nil }
            }
        }
        .overlay {
            if let video = settingsVideo { settingsLayer(video) }
        }
        // Hinweise (kopiert, Fehler beim Senden) auch im Player, MainView zeigt sie nur ohne Player
        .overlay(alignment: .top) {
            if let notice = store.notice {
                NoticeCapsule(notice: notice)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { store.notice = nil } }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.notice?.id)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .onAppear(perform: start)
        .onDisappear {
            // Apples Vollbild Player legt sich über die Seite, dann meldet SwiftUI sie als verschwunden: dabei nichts freigeben
            guard !fullscreen else { return }
            pool.stopAll()
            review?.unwatch()
        }
        .onChange(of: currentID) { old, new in
            settingsVideo = nil
            guard old != nil, let video = videos.first(where: { $0.id == new }) else { return }
            Haptics.swap()
            replyTo = nil
            focusComment = nil
            // Neues Video: offenes Blatt zurück auf die Mitte, zu bleibt zu (wie auf der Videoseite)
            if stop == .offen { withAnimation(Self.sheetSpring) { stop = .mitte } }
            show(video, autoplay: true)
        }
        .onChange(of: composing) { _, now in
            // Beim Schreiben hält das Video an, die Zeit bleibt die, an der man angefangen hat. Zugeklappt geht das Blatt auf die Mitte
            if now {
                draftTime = pool.time
                pool.pause()
                if stop == .zu { withAnimation(Self.sheetSpring) { stop = .mitte } }
            }
        }
        // iPhone quer gedreht: Apples Player im Vollbild (die App selbst bleibt hochkant)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            if UIDevice.current.orientation.isLandscape { openFullscreen() }
        }
        .alert("Titel ändern", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Titel", text: $renameText)
            Button("Abbrechen", role: .cancel) {}
            Button("Speichern") {
                guard let video = renaming, let project else { return }
                Task { await store.renameVideo(project, video, to: renameText) }
            }
        }
        .centerConfirm("Kommentar löschen?", item: $deleting, action: "Löschen",
                       message: { _ in "Der Kommentar und seine Antworten verschwinden für alle." }) { comment in
            guard let review else { return }
            Haptics.cancel()
            Task { await review.delete(comment) }
        }
        .centerConfirm("Von der Seite nehmen?", item: $removing, action: "Von der Seite nehmen", symbol: "rectangle.badge.minus",
                       message: { video in
                           "„\(video.title)“ verschwindet von der Seite. Das Video im Drive, bei Mux und alle Kommentare bleiben, die Nummer wird nie neu vergeben."
                       }) { video in
            guard let project else { return }
            Haptics.cancel()
            Task {
                if await store.removeVideo(project, video) { if videos.count <= 1 { dismiss() } }
            }
        }
        #if DEBUG
        .task {
            // Vorführung: Blatt in einer bestimmten Stufe (SV_BLATT = zu, mitte, offen)
            switch ProcessInfo.processInfo.environment["SV_BLATT"] {
            case "zu": stop = .zu
            case "offen": stop = .offen
            default: break
            }
        }
        #endif
    }

    // MARK: Start und Wechsel

    private func start() {
        guard !started else { return }
        started = true
        let first = videos.first { $0.id == request.videoID } ?? videos.first
        currentID = nil
        if let comment = request.comment {
            // Von einem Kommentar aus: Blatt offen, alle Kommentare, das Video steht an der Stelle
            focusComment = comment
            commentFilter = .all
            stop = .offen
        }
        if let first {
            show(first, autoplay: request.comment == nil, at: request.time)
            DispatchQueue.main.async { currentID = first.id }
        }
        review?.watch()
    }

    /// Aktuelles Video spielen, Nachbarn vorladen, alles andere freigeben
    private func show(_ video: Video, autoplay: Bool, at time: Double? = nil) {
        guard let i = videos.firstIndex(of: video) else { return }
        let neighbours = [i - 1, i, i + 1].filter { videos.indices.contains($0) }.map { videos[$0] }
        pool.keep(neighbours)
        pool.activate(video, autoplay: autoplay, at: time)
    }

    private func close() {
        Haptics.select()
        pool.pause()
        dismiss()
    }

    private func go(to video: Video) {
        withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.4)) { currentID = video.id }
    }

    // MARK: Kopf (wie die Videoseite: zurück, Titel, Link, mehr)

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: close) { GlassCircle(symbol: "chevron.left", size: 42, symbolSize: 16, tint: .white) }
                .buttonStyle(.plain)
                .accessibilityLabel("Schließen")
                .accessibilityIdentifier("player-schliessen")
            Spacer(minLength: 0)
            linkMenu
            moreMenu
        }
        .overlay {
            VStack(spacing: 1) {
                Text(current?.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                if let video = current {
                    // „2 von 14 · Zur Freigabe · 3 offen“: Stand des Videos auch bei zugeklapptem Blatt (Review 22.11.2026)
                    let status = review?.status(of: video) ?? video.status
                    let open = review.map { r in r.threads(for: video.id).filter { !$0.root.done }.count } ?? video.open
                    HStack(spacing: 5) {
                        if videos.count > 1 { Text("\(index + 1) von \(videos.count) ·") }
                        Circle().fill(dot(status)).frame(width: 6, height: 6)
                        Text(status.title)
                        if open > 0 { Text("· \(open) offen") }
                    }
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 62)
            .padding(.trailing, 50)
            .animation(.easeOut(duration: 0.2), value: currentID)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("player-titel")
        }
        .padding(.horizontal, 14)
    }

    /// Link Knopf wie auf der Videoseite (Ole, 22.11.2026: „wie im Web das Popup“): öffnet das Teilen Fenster mit dem Link zum
    /// Video, auf Wunsch ab der Stelle. Das Video hält dabei an und bleibt danach angehalten
    private var linkMenu: some View {
        Button {
            guard let project, let video = current, let link = project.videoLink(video) else { return }
            Haptics.select()
            pool.pause()
            store.share = ShareRequest(title: "Video teilen", subtitle: video.title, url: link, time: Int(pool.time))
        } label: {
            GlassCircle(symbol: "link", size: 42, symbolSize: 16, tint: .white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Video teilen")
        .accessibilityIdentifier("player-link")
    }

    private var moreMenu: some View {
        Menu {
            if let video = current {
                Section {
                    // Aus dem Player zur Seite des Links (Kundenansicht), etwa wenn man von einem Kommentar kam
                    Button {
                        Haptics.select()
                        let key = request.projectKey
                        pool.pause()
                        store.playing = nil
                        store.jump = [.client(key)]
                    } label: { Label("Zum Projekt", systemImage: "rectangle.grid.2x2") }
                    if let project, let page = project.link {
                        Button {
                            UIPasteboard.general.url = page
                            store.show("Link zur ganzen Seite kopiert", symbol: "doc.on.doc")
                        } label: { Label("Link zur ganzen Seite kopieren", systemImage: "doc.on.doc") }
                    }
                    if let project, let link = project.videoLink(video) {
                        Link(destination: link) { Label("In Safari öffnen", systemImage: "safari") }
                    }
                }
                Section {
                    if let drive = video.driveURL { Link(destination: drive) { Label("Original im Drive", systemImage: "arrow.down.circle") } }
                    Button {
                        renameText = video.title
                        renaming = video
                    } label: { Label("Titel ändern", systemImage: "pencil") }
                }
                Section {
                    Button(role: .destructive) { removing = video } label: { Label("Von der Seite nehmen", systemImage: "rectangle.badge.minus") }
                }
            }
        } label: {
            GlassCircle(symbol: "ellipsis", size: 42, symbolSize: 17, tint: .white)
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.select() })
        .accessibilityLabel("Mehr")
        .accessibilityIdentifier("player-mehr")
    }

    // MARK: Video oben: seitlich wischen wechselt das Video

    private func pager(width: CGFloat, height: CGFloat) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(videos) { video in
                    stagePage(video, area: CGSize(width: width, height: height))
                        .containerRelativeFrame(.horizontal)
                        .id(video.id)
                }
            }
            .scrollTargetLayout()
        }
        .frame(height: height)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        // Das Licht läuft nach oben unter den Kopf und nach unten unter das Blatt (seitlich schneidet jede Seite selbst ab)
        .scrollClipDisabled()
        .scrollDisabled(scrubbing || composing || dragBase != nil)
        .accessibilityIdentifier("player-seiten")
    }

    /// Eine Seite: Video so groß wie möglich (Rand 6 oben, 14 seitlich, 16 unten wie auf der Videoseite), dahinter das Licht
    private func stagePage(_ video: Video, area: CGSize) -> some View {
        let active = video.id == current?.id
        let box = CGSize(width: max(area.width - 28, 1), height: max(area.height - 22, 1))
        let scale = min(box.width / video.aspect, box.height) // Höhe des Videos
        let size = CGSize(width: scale * video.aspect, height: scale)
        return ZStack {
            AmbientLight(video: video, time: active ? pool.time : nil, size: size)
            Stage(video: video, active: active, pool: pool, size: size, next: next(after: video), go: go)
        }
        .offset(y: -5)
        .frame(width: area.width, height: area.height)
        .mask(Rectangle().padding(.vertical, -320))
    }

    private func next(after video: Video) -> Video? {
        guard let i = videos.firstIndex(of: video), i + 1 < videos.count else { return nil }
        return videos[i + 1]
    }

    // MARK: Blatt

    /// Höhen der drei Stufen aus dem, was gerade drin steht (Web: blattMessen). Offen lässt dem Video mindestens 30 % oder 150 pt.
    private func sheetStops(total: CGFloat) -> [SheetStop: CGFloat] {
        let room = total - Self.headerHeight
        let zu = headHeight
        let mitte = headHeight + fieldHeight
        let offen = min(room - 90, max(mitte + 140, room - max(150, room * 0.3)))
        return [.zu: zu, .mitte: mitte, .offen: max(offen, mitte)]
    }

    /// Über die Grenzen hinaus gibt das Blatt nur noch zäh nach (wie bei iOS, Web: gummi)
    private func liveHeight(_ stops: [SheetStop: CGFloat]) -> CGFloat {
        guard let base = dragBase else { return stops[stop] ?? 0 }
        let h = base - dragY
        let low = stops[.zu] ?? 0, high = stops[.offen] ?? 0
        let rubber = { (d: CGFloat) in 90 * (1 - 1 / (d / 90 * 0.55 + 1)) }
        return h > high ? high + rubber(h - high) : h < low ? low - rubber(low - h) : h
    }

    private func sheetDrag(_ stops: [SheetStop: CGFloat]) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                if dragBase == nil {
                    guard !dragSideways else { return }
                    // Erst klar senkrecht wird gezogen, seitlich gehört der Finger der Zeitleiste oder dem Wischen
                    guard abs(value.translation.height) > abs(value.translation.width) else { dragSideways = true; return }
                }
                sheetDragChanged(value.translation.height, stops: stops)
            }
            .onEnded { value in
                dragSideways = false
                sheetDragEnded(value.translation.height, value.velocity.height, stops: stops)
            }
    }

    private func sheetDragChanged(_ dy: CGFloat, stops: [SheetStop: CGFloat]) {
        if dragBase == nil {
            if composing { composing = false }
            dragBase = stops[stop]
        }
        dragY = dy
    }

    /// Mit Schwung gerechnet zur nächsten Stufe (Web: blattLoslassen, 220 ms)
    private func sheetDragEnded(_ dy: CGFloat, _ vy: CGFloat, stops: [SheetStop: CGFloat]) {
        guard let base = dragBase else { return }
        let target = base - dy - vy * 0.22
        let best = SheetStop.allCases.min { abs((stops[$0] ?? 0) - target) < abs((stops[$1] ?? 0) - target) } ?? stop
        if best != stop { Haptics.select() }
        withAnimation(Self.sheetSpring) {
            stop = best
            dragBase = nil
            dragY = 0
        }
    }

    private var lastStops: [SheetStop: CGFloat] { stopsBox.value }
    private func updateStops(_ stops: [SheetStop: CGFloat]) { stopsBox.value = stops }

    private func toggleSheet() {
        Haptics.select()
        // Wie im Web (griffTippen): von der Mitte auf, sonst zurück auf die Mitte
        withAnimation(Self.sheetSpring) { stop = stop == .mitte ? .offen : .mitte }
    }

    private func sheet(height: CGFloat, stops: [SheetStop: CGFloat]) -> some View {
        let zu = stops[.zu] ?? 0, mitte = stops[.mitte] ?? 0
        // Feld und Liste blenden mit der Höhe ein, wie im Web (zu: kein Feld, mitte: keine Liste)
        let fieldShown = composing ? 1 : min(max((height - zu) / max(mitte - zu, 1), 0), 1)
        let listShown = min(max((height - mitte - 10) / 70, 0), 1)
        return VStack(spacing: 0) {
            sheetHead
                .contentShape(Rectangle())
                .gesture(sheetDrag(stops))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headHeight = $0 }
            composer
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fieldHeight = $0 }
                .opacity(fieldShown)
                .allowsHitTesting(fieldShown > 0.5)
            if let video = current {
                sheetList(video)
                    .frame(maxHeight: .infinity)
                    .opacity(listShown)
                    .allowsHitTesting(listShown > 0.5)
            }
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        // Unsichtbarer Streifen über der Kante: der Daumen trifft das Blatt auch knapp darüber (Ole, 22.11.2026)
        .overlay(alignment: .top) {
            Color.clear
                .frame(height: 18)
                .contentShape(Rectangle())
                .gesture(sheetDrag(stops))
                .onTapGesture(perform: toggleSheet)
                .offset(y: -18)
                .accessibilityHidden(true)
        }
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
                .fill(Self.panel)
                .shadow(color: .black.opacity(0.22), radius: 16, y: -6)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Griff, Zeitleiste und Steuerung: daran zieht man das Blatt
    private var sheetHead: some View {
        VStack(spacing: 0) {
            // Griff höher und leichter zu treffen (Ole, 22.11.2026: „die Fläche zum Hochziehen leicht größer, für den Daumen“):
            // 28 pt Streifen, dazu 16 pt über der Kante des Blatts
            Capsule()
                .fill(Color.white.opacity(dragBase != nil ? 0.4 : 0.24))
                .frame(width: dragBase != nil ? 50 : 42, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 13)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggleSheet)
                .animation(.easeOut(duration: 0.2), value: dragBase != nil)
                .accessibilityElement()
                .accessibilityLabel("Kommentare auf oder zu klappen")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { toggleSheet() }
                .accessibilityIdentifier("griff")
            if let video = current { controls(video) }
        }
    }

    // MARK: Steuerung (wie im Web: Zeitleiste, Abspielen, Ton, Zeit, Zahnrad, Vollbild)

    private func controls(_ video: Video) -> some View {
        let threads = review?.threads(for: video.id) ?? []
        let duration = pool.duration > 0 ? pool.duration : video.duration
        return VStack(spacing: 0) {
            Scrubber(time: pool.time, duration: duration,
                     markers: threads.compactMap { t in t.root.time.map { ($0, !t.root.done) } },
                     video: video,
                     seek: { t, exact in pool.seek(to: t, exact: exact) },
                     scrubbing: $scrubbing,
                     vertical: { dy, vy, ended in
                         ended ? sheetDragEnded(dy, vy, stops: lastStops) : sheetDragChanged(dy, stops: lastStops)
                     })
            HStack(spacing: 2) {
                Button {
                    Haptics.select()
                    pool.toggle()
                } label: {
                    Image(systemName: pool.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(pool.playing ? "Anhalten" : "Abspielen")
                .accessibilityIdentifier("abspielen")
                Button {
                    Haptics.select()
                    pool.muted.toggle()
                } label: {
                    Image(systemName: pool.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 17, weight: .medium))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 42, height: 44)
                }
                .accessibilityLabel(pool.muted ? "Ton an" : "Ton aus")
                Text("\(Clock.text(pool.time)) / \(Clock.text(duration))")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.leading, 4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                settingsMenu(video)
                Button {
                    Haptics.select()
                    openFullscreen()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 42, height: 44)
                }
                .accessibilityLabel("Vollbild")
                .accessibilityIdentifier("vollbild")
            }
            .foregroundStyle(.white)
            .buttonStyle(PressStyle(scale: 0.88))
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 16)
    }

    /// Zahnrad wie auf der Videoseite: öffnet das eigene Menü (SettingsPanel), dreht sich bei jedem Drücken ein Stück weiter
    /// mit leichtem Nachfedern (Web: 120 Grad, das Rad hat sechs Zähne)
    private func settingsMenu(_ video: Video) -> some View {
        Button {
            Haptics.select()
            withAnimation(.spring(response: 0.62, dampingFraction: 0.62)) { gearTurns += 1 }
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.2)) { settingsVideo = settingsVideo == nil ? video : nil }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .medium))
                    .rotationEffect(.degrees(gearTurns * 120))
                    .frame(width: 42, height: 44)
                if pool.speed != 1 {
                    Text(PlayerPool.speedText(pool.speed))
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Palette.stage)
                        .padding(.horizontal, 3)
                        .background(Palette.approved, in: Capsule())
                        .offset(x: 2, y: 6)
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { gearFrame = $0 }
        .accessibilityLabel("Einstellungen")
        .accessibilityIdentifier("einstellungen")
    }

    /// Das offene Menü über dem Zahnrad, dahinter abgedunkelt (Tipp daneben schließt)
    private func settingsLayer(_ video: Video) -> some View {
        GeometryReader { g in
            let origin = g.frame(in: .global).origin
            let right = g.size.width - 12  // rechts 12 Punkte vom Rand wie im Web (right: 12px)
            let bottom = gearFrame.minY - origin.y - 6
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.28)
                    .contentShape(Rectangle())
                    .onTapGesture { closeSettings() }
                    .accessibilityHidden(true)
                SettingsPanel(pool: pool, video: video)
                    .frame(width: min(300, g.size.width - 24))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: right, height: max(bottom, 0), alignment: .bottomTrailing)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottomTrailing)).combined(with: .offset(y: 8)))
            }
        }
        .ignoresSafeArea()
    }

    private func closeSettings() {
        Haptics.select()
        withAnimation(.easeOut(duration: 0.16)) { settingsVideo = nil }
    }

    /// Vollbild über Apples eigenen Player (Ole, 22.11.2026), auch wenn man das iPhone quer dreht
    private func openFullscreen() {
        guard !fullscreen, let player = pool.activePlayer else { return }
        fullscreen = true
        Fullscreen.present(player) { fullscreen = false }
    }

    // MARK: Kommentarfeld (Web seit 17.11.2026: eine Zeile, angetippt groß mit Zeitmarke und Senden)

    private var composerOpen: Bool { composing || replyTo != nil || editing != nil || !draft.isEmpty }
    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let editing {
                HStack(spacing: 6) {
                    Image(systemName: "pencil").font(.system(size: 11, weight: .bold))
                    Text("Kommentar von \(editing.name) bearbeiten").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button {
                        Haptics.select()
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.editing = nil
                            draft = ""
                            composing = false
                        }
                    } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 24) }
                        .accessibilityLabel("Bearbeiten abbrechen")
                }
                .foregroundStyle(Color.white.opacity(0.65))
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
            if let replyTo {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 11))
                    Text("Antwort an \(replyTo.name)").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button {
                        Haptics.select()
                        withAnimation(.easeOut(duration: 0.2)) { self.replyTo = nil }
                    } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 24) }
                        .accessibilityLabel("Antwort abbrechen")
                }
                .foregroundStyle(Color.white.opacity(0.65))
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
            VStack(alignment: .leading, spacing: 4) {
                TextField("", text: $draft, prompt: Text(replyTo == nil ? "Kommentar schreiben …" : "Antwort schreiben …")
                    .foregroundStyle(Color.white.opacity(0.42)), axis: .vertical)
                    .lineLimit(composerOpen ? 1...6 : 1...1)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .focused($composing)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(minHeight: 40)
                    .accessibilityIdentifier("kommentar-feld")
                if composerOpen {
                    HStack {
                        if replyTo == nil && editing == nil { timeChip }
                        Spacer()
                        sendButton
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                    .transition(.opacity)
                }
            }
            .background(Self.panel2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if composerOpen && editing == nil {
                // Kommentare aus dem Team stehen auch beim Kunden (Review 22.11.2026)
                Text(replyTo == nil ? "Sieht auch der Kunde. Pausier an der Stelle, die du meinst, die Zeit geht mit." : "Sieht auch der Kunde.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: composerOpen)
        .animation(.easeOut(duration: 0.2), value: replyTo)
        .animation(.easeOut(duration: 0.2), value: editing)
    }

    private var timeChip: some View {
        Button {
            Haptics.select()
            attachTime.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "timer").font(.system(size: 12, weight: .semibold))
                Text(Clock.text(composing ? draftTime : pool.time)).font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(attachTime ? Palette.stage : Color.white.opacity(0.6))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(attachTime ? Palette.pending : Color.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(attachTime ? "Zeit wird angehängt" : "Ohne Zeit")
        .accessibilityIdentifier("zeit-chip")
    }

    private var sendButton: some View {
        Button(action: send) {
            ZStack {
                if sending { ProgressView().tint(.white) } else {
                    Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: 36, height: 36)
            .background(Palette.forest.opacity(canSend ? 1 : 0.35), in: Circle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .disabled(!canSend)
        .accessibilityLabel("Senden")
        .accessibilityIdentifier("senden")
    }

    private func send() {
        guard let review, let video = current, canSend else { return }
        let text = draft
        sending = true
        if let comment = editing {
            Task {
                let ok = await review.edit(comment, text: text)
                sending = false
                if ok {
                    Haptics.sent()
                    draft = ""
                    editing = nil
                    composing = false
                } else {
                    Haptics.error()
                }
            }
            return
        }
        Task {
            let ok = await review.add(video: video.id, text: text, time: attachTime ? draftTime : nil, replyTo: replyTo?.id)
            sending = false
            if ok {
                Haptics.sent()
                draft = ""
                replyTo = nil
                composing = false
            } else {
                Haptics.error()
            }
        }
    }

    // MARK: Aufgezogen: Freigabe, Kommentare, Mehr aus

    private func sheetList(_ video: Video) -> some View {
        let threads = review?.threads(for: video.id) ?? []
        let shown = threads.filter { t in
            switch commentFilter {
            case .all: true
            case .open: !t.root.done
            case .done: t.root.done
            }
        }
        let activeThread = highlighted(in: threads.filter { !$0.root.done })
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Freigabe als Zeile mit dem Stand als Pille
                    HStack {
                        Text("Freigabe").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        if let review {
                            StatusMenu(status: review.status(of: video), entry: review.statusEntry(of: video)) { status in
                                status == .approved ? Haptics.check() : Haptics.select()
                                Task { await review.setStatus(status, for: video) }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) { line }
                    .overlay(alignment: .bottom) { line }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    // Kommentare mit Filter Alle, Offen, Erledigt
                    HStack {
                        Text("Kommentare").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        filterSwitch
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                    if shown.isEmpty {
                        Text(review?.loaded == false ? "Kommentare laden …"
                             : threads.isEmpty ? "Noch keine Kommentare.\nPausier an der Stelle, die du ändern willst, und schreib es oben rein. Die Zeit wird mitgeschickt."
                             : commentFilter == .open ? "Alles erledigt." : "Noch nichts erledigt.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .padding(.horizontal, 18)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                            .padding(.horizontal, 16)
                    }
                    VStack(spacing: 8) {
                        ForEach(shown) { thread in
                            let focused = focusThread(in: shown) == thread.id
                            threadView(thread, highlighted: thread.id == activeThread)
                                .background(focused ? Palette.approved.opacity(0.16) : Self.panel2,
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Palette.approved.opacity(focused ? 0.75 : 0), lineWidth: 1.5))
                                .animation(.easeOut(duration: 0.3), value: focused)
                                .id(thread.id)
                                .accessibilityAddTraits(focused ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 12)

                    moreFrom(video)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: activeThread) { _, id in
                guard let id, !composing, stop == .offen, focusComment == nil else { return }
                withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
            }
            // Angetippter Kommentar: hinscrollen, sobald das Blatt offen und die Kommentare da sind
            .task(id: "\(focusThread(in: shown) ?? -1)-\(review?.loaded ?? false)") {
                guard let target = focusThread(in: shown) else { return }
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeOut(duration: 0.4)) { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }

    private var line: some View { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }

    private var filterSwitch: some View {
        HStack(spacing: 2) {
            ForEach(CommentFilter.allCases, id: \.self) { filter in
                let chosen = commentFilter == filter
                Button {
                    Haptics.select()
                    withAnimation(.easeOut(duration: 0.2)) { commentFilter = filter }
                } label: {
                    Text(filter.rawValue)
                        .font(.system(size: 13, weight: chosen ? .semibold : .medium))
                        .foregroundStyle(chosen ? Color.white : Color.white.opacity(0.55))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(chosen ? Color.white.opacity(0.14) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("kommentare-\(filter.rawValue.lowercased())")
            }
        }
        .padding(3)
        .background(Self.panel2, in: Capsule())
    }

    /// „Mehr aus …“: die übrigen Videos ab dem nächsten, das erste mit „Als Nächstes“ (wie auf der Videoseite)
    @ViewBuilder
    private func moreFrom(_ video: Video) -> some View {
        let i = videos.firstIndex(of: video) ?? 0
        let others = Array(videos[(i + 1)...] + videos[..<i])
        if !others.isEmpty, let project {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mehr aus \(project.title)").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), alignment: .leading, spacing: 14) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { n, other in
                        Button {
                            Haptics.press()
                            go(to: other)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Color.clear
                                    .aspectRatio(3 / 4, contentMode: .fit)
                                    .overlay { RemoteImage(url: other.thumbnail(width: 360), placeholder: Self.panel2) }
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(alignment: .topLeading) {
                                        if n == 0 {
                                            Text("Als Nächstes").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.white)
                                                .padding(.horizontal, 7).frame(height: 20)
                                                .background(.black.opacity(0.55), in: Capsule())
                                                .padding(6)
                                        }
                                    }
                                HStack(alignment: .top, spacing: 5) {
                                    Circle().fill(dot(other.status)).frame(width: 7, height: 7).padding(.top, 5)
                                    Text(other.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.85))
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.96))
                        .accessibilityIdentifier("mehr-\(other.nr)")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
        }
    }

    private func dot(_ status: ReviewStatus) -> Color {
        switch status {
        case .pending: Palette.pending
        case .changes: Palette.changes
        case .approved: Palette.approved
        }
    }

    /// Faden des angetippten Kommentars (er kann auch eine Antwort sein)
    private func focusThread(in threads: [CommentThread]) -> Int? {
        guard let focusComment else { return nil }
        return threads.first { $0.root.id == focusComment || $0.replies.contains { $0.id == focusComment } }?.id
    }

    /// Der Kommentar, an dessen Stelle das Video gerade läuft (bis 4 s danach hervorgehoben, wie auf der Videoseite)
    private func highlighted(in threads: [CommentThread]) -> Int? {
        threads.last { t in guard let s = t.root.time else { return false }; return pool.time >= s - 0.2 && pool.time < s + 4 }?.id
    }

    private func threadView(_ thread: CommentThread, highlighted: Bool) -> some View {
        ThreadView(thread: thread, highlighted: highlighted,
                   jump: { time in pool.seek(to: time); pool.pause() },
                   reply: { comment in replyTo = comment; composing = true },
                   toggleDone: { comment in
                       comment.done ? Haptics.select() : Haptics.check()
                       Task { await review?.setDone(comment, !comment.done) }
                   },
                   edit: { comment in
                       // Bearbeiten im selben Feld wie Antworten (Review 22.11.2026: vorher ein einzeiliges Systemfenster)
                       replyTo = nil
                       editing = comment
                       draft = comment.text
                       composing = true
                   },
                   delete: { comment in deleting = comment })
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Text("Hier gibt es noch keine Videos").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            Button(action: close) { CapsuleButtonLabel(title: "Schließen").frame(width: 160) }.buttonStyle(PressStyle())
        }
    }
}

// MARK: Bühne

/// Das Video mit Standbild davor, bis das erste Bild da ist, runde Ecken wie auf der Videoseite. Tippen hält an oder spielt,
/// am Ende kommt der Knopf zum nächsten Video.
private struct Stage: View {
    let video: Video
    let active: Bool
    let pool: PlayerPool
    let size: CGSize
    let next: Video?
    let go: (Video) -> Void

    @State private var ready = false
    @State private var flash: String?

    var body: some View {
        ZStack {
            RemoteImage(url: video.thumbnail(width: 480), placeholder: Color.white.opacity(0.05))
                .opacity(ready ? 0 : 1)
            VideoSurface(player: pool.players[video.id]) { now in
                withAnimation(.easeOut(duration: 0.2)) { ready = now }
            }
            if active {
                overlays
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard active else { return }
            Haptics.select()
            pool.toggle()
            flash(pool.playing ? "pause.fill" : "play.fill")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(video.title)
        .accessibilityIdentifier("buehne-\(video.nr)")
    }

    @ViewBuilder
    private var overlays: some View {
        if !pool.playing && !pool.ended && ready {
            PlayDisc(size: 56).allowsHitTesting(false).transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
        if pool.buffering && pool.playing {
            ProgressView().controlSize(.large).tint(.white).allowsHitTesting(false)
        }
        if let flash {
            Image(systemName: flash)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .glassEffect(.regular, in: .circle)
                .transition(.opacity.combined(with: .scale(scale: 1.2)))
                .allowsHitTesting(false)
        }
        if pool.ended, let next {
            Button {
                Haptics.press()
                go(next)
            } label: {
                HStack(spacing: 10) {
                    RemoteImage(url: next.thumbnail(width: 240), placeholder: Color.white.opacity(0.1))
                        .frame(width: next.portrait ? 30 : 48, height: next.portrait ? 48 : 27)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Als Nächstes").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.6))
                        Text(next.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                }
                .padding(.leading, 8)
                .padding(.trailing, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(PressStyle())
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 14)
            .padding(.horizontal, 10)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityIdentifier("als-naechstes")
        }
    }

    private func flash(_ symbol: String) {
        withAnimation(.easeOut(duration: 0.12)) { flash = symbol }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.3)) { flash = nil }
        }
    }
}

/// Ablage der Stufen ohne neues Zeichnen (eine Klasse, SwiftUI beobachtet sie nicht)
final class StopsBox { var value: [SheetStop: CGFloat] = [:] }
