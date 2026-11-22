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
}

/// Der Player der App, für Ole optimiert: öffnet direkt mit Bild (Standbild aus dem Speicher, dann das Video), läuft sofort los,
/// seitlich wischen wechselt das Video (wie am Handy auf der Videoseite), Nachbarn sind schon geladen. Darunter Freigabe und
/// Kommentare wie auf videos.stagecraft.media, nur als Stagecraft. Quer gehalten füllt das Video den Bildschirm.
struct PlayerScreen: View {
    let request: PlayerRequest

    @State private var store = Store.shared
    @State private var pool = PlayerPool()
    @State private var currentID: String?
    @State private var started = false
    @State private var bigStage = false
    @State private var scrubbing = false
    @State private var draft = ""
    @State private var attachTime = true
    @State private var draftTime: Double = 0
    @State private var replyTo: Comment?
    @State private var editing: Comment?
    @State private var editText = ""
    @State private var deleting: Comment?
    @State private var renaming: Video?
    @State private var renameText = ""
    @State private var removing: Video?
    @State private var systemPlayer = false
    @State private var showDone = false
    @State private var sending = false
    @FocusState private var composing: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSize

    private var project: Project? { store.project(request.projectKey) }
    private var videos: [Video] { project?.videos ?? [] }
    private var current: Video? { videos.first { $0.id == currentID } ?? videos.first }
    private var index: Int { videos.firstIndex { $0.id == current?.id } ?? 0 }
    private var review: ReviewStore? { project?.code.map(ReviewStore.of) }
    private var landscape: Bool { verticalSize == .compact }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Palette.stage.ignoresSafeArea()
                if videos.isEmpty {
                    empty
                } else if landscape, let current {
                    LandscapeStage(video: current, pool: pool, close: close)
                } else {
                    VStack(spacing: 0) {
                        header
                        pager(height: geo.size.height, width: geo.size.width)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !landscape, current != nil, review != nil { composer }
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .statusBarHidden(landscape)
        .persistentSystemOverlays(landscape ? .hidden : .automatic)
        .onAppear(perform: start)
        .onDisappear {
            pool.stopAll()
            review?.unwatch()
        }
        .onChange(of: currentID) { old, new in
            guard old != nil, let video = videos.first(where: { $0.id == new }) else { return }
            Haptics.swap()
            replyTo = nil
            show(video, autoplay: true)
        }
        .fullScreenCover(isPresented: $systemPlayer) {
            if let player = pool.activePlayer { SystemPlayer(player: player).ignoresSafeArea() }
        }
        .alert("Titel ändern", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Titel", text: $renameText)
            Button("Abbrechen", role: .cancel) {}
            Button("Speichern") {
                guard let video = renaming, let project else { return }
                Task { await store.renameVideo(project, video, to: renameText) }
            }
        }
        .alert("Kommentar bearbeiten", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Text", text: $editText, axis: .vertical)
            Button("Abbrechen", role: .cancel) {}
            Button("Speichern") {
                guard let comment = editing, let review else { return }
                Task { _ = await review.edit(comment, text: editText) }
            }
        }
        .confirmationDialog("Kommentar löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                guard let comment = deleting, let review else { return }
                Haptics.cancel()
                Task { await review.delete(comment) }
            }
        } message: {
            Text("Der Kommentar und seine Antworten verschwinden für alle.")
        }
        .confirmationDialog("Von der Seite nehmen?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Von der Seite nehmen", role: .destructive) {
                guard let video = removing, let project else { return }
                Haptics.cancel()
                Task {
                    if await store.removeVideo(project, video) { if videos.count <= 1 { dismiss() } }
                }
            }
        } message: {
            Text("„\(removing?.title ?? "")“ verschwindet von der Seite. Das Video im Drive, bei Mux und alle Kommentare bleiben, die Nummer wird nie neu vergeben.")
        }
    }

    // MARK: Start und Wechsel

    private func start() {
        guard !started else { return }
        started = true
        let first = videos.first { $0.id == request.videoID } ?? videos.first
        currentID = nil
        if let first {
            show(first, autoplay: true, at: request.time)
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

    // MARK: Kopf

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: close) { GlassCircle(symbol: "xmark", size: 42, symbolSize: 16, tint: .white) }
                .buttonStyle(.plain)
                .accessibilityLabel("Schließen")
                .accessibilityIdentifier("player-schliessen")
            VStack(spacing: 1) {
                Text(current?.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Text([videos.count > 1 ? "\(index + 1) von \(videos.count)" : "", project?.title == current?.title ? "" : project?.title ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.2), value: currentID)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("player-titel")
            moreMenu
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var moreMenu: some View {
        Menu {
            if let project, let video = current, let link = project.videoLink(video) {
                Section {
                    Button {
                        UIPasteboard.general.url = link
                        store.show("Link zum Video kopiert", symbol: "doc.on.doc")
                    } label: { Label("Link kopieren", systemImage: "doc.on.doc") }
                    ShareLink(item: link) { Label("Teilen", systemImage: "square.and.arrow.up") }
                    Link(destination: link) { Label("In Safari öffnen", systemImage: "safari") }
                    if let drive = video.driveURL { Link(destination: drive) { Label("Im Drive öffnen", systemImage: "externaldrive") } }
                }
                Section {
                    Button {
                        renameText = video.title
                        renaming = video
                    } label: { Label("Titel ändern", systemImage: "pencil") }
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

    // MARK: Seiten zum Wischen

    private func pager(height: CGFloat, width: CGFloat) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(videos) { video in
                    page(video, height: height, width: width)
                        .containerRelativeFrame(.horizontal)
                        .id(video.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .scrollDisabled(scrubbing || composing)
        .accessibilityIdentifier("player-seiten")
    }

    private func page(_ video: Video, height: CGFloat, width: CGFloat) -> some View {
        let active = video.id == current?.id
        let threads = review?.threads(for: video.id) ?? []
        // Höchstens 46 % der Höhe (groß 72 %), aber nie höher als das Video selbst: Querformat ohne schwarzen Rand
        let stageHeight = min(height * (bigStage ? 0.72 : 0.46), (width - 24) / video.aspect)
        return VStack(spacing: 0) {
            Stage(video: video, active: active, pool: pool, height: stageHeight, next: next(after: video), go: go)
                .padding(.horizontal, 12)
            controls(video, active: active, threads: threads)
            comments(video, threads: threads)
        }
    }

    private func next(after video: Video) -> Video? {
        guard let i = videos.firstIndex(of: video), i + 1 < videos.count else { return nil }
        return videos[i + 1]
    }

    // MARK: Steuerung

    private func controls(_ video: Video, active: Bool, threads: [CommentThread]) -> some View {
        let time = active ? pool.time : 0
        let duration = active && pool.duration > 0 ? pool.duration : video.duration
        return VStack(spacing: 4) {
            Scrubber(time: time, duration: duration,
                     markers: threads.compactMap { t in t.root.time.map { ($0, !t.root.done) } },
                     video: video,
                     seek: { t, exact in pool.seek(to: t, exact: exact) },
                     scrubbing: $scrubbing)
                .disabled(!active)
            HStack(spacing: 2) {
                Button {
                    Haptics.select()
                    pool.toggle()
                } label: {
                    Image(systemName: active && pool.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(active && pool.playing ? "Anhalten" : "Abspielen")
                .accessibilityIdentifier("abspielen")
                Button { Haptics.select(); pool.skip(-10) } label: {
                    Image(systemName: "gobackward.10").font(.system(size: 18, weight: .medium)).frame(width: 40, height: 44)
                }
                .accessibilityLabel("10 Sekunden zurück")
                Button { Haptics.select(); pool.skip(10) } label: {
                    Image(systemName: "goforward.10").font(.system(size: 18, weight: .medium)).frame(width: 40, height: 44)
                }
                .accessibilityLabel("10 Sekunden vor")
                Text("\(Clock.text(time)) / \(Clock.text(duration))")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.leading, 4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                speedMenu
                Button {
                    Haptics.select()
                    pool.muted.toggle()
                } label: {
                    Image(systemName: pool.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 16, weight: .medium))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 40, height: 44)
                }
                .accessibilityLabel(pool.muted ? "Ton an" : "Ton aus")
                Button {
                    Haptics.select()
                    if video.portrait {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { bigStage.toggle() }
                    } else {
                        systemPlayer = true
                    }
                } label: {
                    Image(systemName: video.portrait ? (bigStage ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                          : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 44)
                }
                .accessibilityLabel(video.portrait ? (bigStage ? "Video kleiner" : "Video größer") : "Vollbild")
                .accessibilityIdentifier("groesse")
            }
            .foregroundStyle(.white)
            .buttonStyle(PressStyle(scale: 0.88))
            .disabled(!active)
            .opacity(active ? 1 : 0.4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var speedMenu: some View {
        Menu {
            Picker("Tempo", selection: Binding(get: { pool.speed }, set: { pool.speed = $0; Haptics.select() })) {
                ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { rate in
                    Text(rate == 1 ? "Normal" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))×").tag(rate)
                }
            }
        } label: {
            Text(pool.speed == 1 ? "1×" : "\(pool.speed.formatted(.number.precision(.fractionLength(0...2))))×")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(pool.speed == 1 ? Color.white.opacity(0.8) : Palette.approved)
                .frame(minWidth: 40, minHeight: 30)
                .padding(.horizontal, 4)
                .background(Color.white.opacity(0.1), in: Capsule())
        }
        .accessibilityLabel("Tempo")
        .accessibilityIdentifier("tempo")
    }

    // MARK: Kommentare

    private func comments(_ video: Video, threads: [CommentThread]) -> some View {
        let open = threads.filter { !$0.root.done }
        let done = threads.filter(\.root.done)
        let activeThread = video.id == current?.id ? highlighted(in: open) : nil
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        if let review {
                            StatusMenu(status: review.status(of: video), entry: review.statusEntry(of: video)) { status in
                                status == .approved ? Haptics.check() : Haptics.select()
                                Task { await review.setStatus(status, for: video) }
                            }
                        }
                        Spacer()
                        Text(open.isEmpty ? (threads.isEmpty ? "Keine Kommentare" : "Alles erledigt") : Plural.count(open.count, "offen", "offen"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)

                    if threads.isEmpty {
                        Text(review?.loaded == false ? "Kommentare laden …" : "Noch keine Kommentare. Halte an der Stelle an, die du ändern willst, und schreib es unten rein. Die Zeit geht mit.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 14)
                    }
                    ForEach(open) { thread in
                        threadView(thread, highlighted: thread.id == activeThread).id(thread.id)
                    }
                    if !done.isEmpty {
                        Button {
                            Haptics.select()
                            withAnimation(.easeOut(duration: 0.25)) { showDone.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .rotationEffect(.degrees(showDone ? 90 : 0))
                                Text("Erledigt \(done.count)").font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(Color.white.opacity(0.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("erledigte")
                        if showDone {
                            ForEach(done) { thread in threadView(thread, highlighted: false).id(thread.id) }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: activeThread) { _, id in
                guard let id, !composing else { return }
                withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
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
                   edit: { comment in editText = comment.text; editing = comment },
                   delete: { comment in deleting = comment })
    }

    // MARK: Eingabe unten

    private var composer: some View {
        VStack(spacing: 6) {
            if let replyTo {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 11))
                    Text("Antwort an \(replyTo.name)").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button {
                        Haptics.select()
                        withAnimation(.easeOut(duration: 0.2)) { self.replyTo = nil }
                    } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 28) }
                        .accessibilityLabel("Antwort abbrechen")
                }
                .foregroundStyle(Color.white.opacity(0.65))
                .padding(.horizontal, 18)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(alignment: .bottom, spacing: 8) {
                if replyTo == nil {
                    Button {
                        Haptics.select()
                        attachTime.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "timer").font(.system(size: 12, weight: .semibold))
                            Text(Clock.text(composing ? draftTime : pool.time)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                        }
                        .foregroundStyle(attachTime ? Palette.stage : Color.white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(attachTime ? Palette.pending : Color.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .padding(.bottom, 6)
                    .accessibilityLabel(attachTime ? "Zeit wird angehängt" : "Ohne Zeit")
                    .accessibilityIdentifier("zeit-chip")
                }
                TextField("", text: $draft, prompt: Text(replyTo == nil ? "Kommentar schreiben …" : "Antwort schreiben …")
                    .foregroundStyle(Color.white.opacity(0.45)), axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .focused($composing)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("kommentar-feld")
                Button(action: send) {
                    ZStack {
                        if sending { ProgressView().tint(.white) } else {
                            Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(Palette.forest.opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1), in: Circle())
                }
                .buttonStyle(PressStyle(scale: 0.9))
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                .padding(.bottom, 4)
                .accessibilityLabel("Senden")
                .accessibilityIdentifier("senden")
            }
            .padding(.leading, replyTo == nil ? 8 : 18)
            .padding(.trailing, 6)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .padding(.top, 6)
        .background(alignment: .bottom) { BottomEdge(color: Palette.stage, height: 110) }
        .animation(.easeOut(duration: 0.2), value: replyTo)
        .onChange(of: composing) { _, now in
            // Beim Schreiben hält das Video an, die Zeit bleibt die, an der man angefangen hat (wie Frame.io)
            if now { draftTime = pool.time; pool.pause() }
        }
    }

    private func send() {
        guard let review, let video = current, !sending else { return }
        let text = draft
        sending = true
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

    private var empty: some View {
        VStack(spacing: 14) {
            Text("Hier gibt es noch keine Videos").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            Button(action: close) { CapsuleButtonLabel(title: "Schließen").frame(width: 160) }.buttonStyle(PressStyle())
        }
    }
}

// MARK: Bühne

/// Das Video mit Standbild davor, bis das erste Bild da ist. Tippen hält an oder spielt, gedrückt halten spielt doppelt so schnell,
/// am Ende kommt der Knopf zum nächsten Video.
private struct Stage: View {
    let video: Video
    let active: Bool
    let pool: PlayerPool
    let height: CGFloat
    let next: Video?
    let go: (Video) -> Void

    @State private var ready = false
    @State private var flash: String?

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, height * video.aspect)
            let size = CGSize(width: width, height: width / video.aspect)
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
            .contentShape(Rectangle())
            .onTapGesture {
                guard active else { return }
                Haptics.select()
                pool.toggle()
                flash(pool.playing ? "pause.fill" : "play.fill")
            }
            .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 14) {
                guard active, pool.playing else { return }
                Haptics.press()
                withAnimation(.easeOut(duration: 0.15)) { pool.boost = true }
            } onPressingChanged: { pressing in
                if !pressing, pool.boost { withAnimation(.easeOut(duration: 0.15)) { pool.boost = false } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(video.title)
        .accessibilityIdentifier("buehne-\(video.nr)")
    }

    @ViewBuilder
    private var overlays: some View {
        if !pool.playing && !pool.ended && ready {
            PlayDisc(size: 62).allowsHitTesting(false).transition(.opacity.combined(with: .scale(scale: 0.85)))
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
        if pool.boost {
            Label("2×", systemImage: "forward.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .glassEffect(.regular, in: .capsule)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 12)
                .allowsHitTesting(false)
                .transition(.opacity)
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

// MARK: Quer

/// Quer gehalten: nur das Video, groß. Tippen zeigt oder versteckt Zeitleiste und Knöpfe, beim Abspielen verschwinden sie nach 3 s.
private struct LandscapeStage: View {
    let video: Video
    let pool: PlayerPool
    let close: () -> Void

    @State private var chrome = true
    @State private var scrubbing = false
    @State private var hide: Task<Void, Never>?

    var body: some View {
        ZStack {
            VideoSurface(player: pool.players[video.id])
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { chrome.toggle() }
                    autoHide()
                }
            if chrome {
                VStack {
                    HStack {
                        Button(action: close) { GlassCircle(symbol: "xmark", size: 42, symbolSize: 16, tint: .white) }.buttonStyle(.plain)
                        Text(video.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Spacer()
                    }
                    Spacer()
                    HStack(spacing: 14) {
                        Button {
                            Haptics.select()
                            pool.toggle()
                            autoHide()
                        } label: {
                            Image(systemName: pool.playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .buttonStyle(.plain)
                        Scrubber(time: pool.time, duration: pool.duration > 0 ? pool.duration : video.duration, markers: [], video: video,
                                 seek: { t, exact in pool.seek(to: t, exact: exact) }, scrubbing: $scrubbing)
                        Text("\(Clock.text(pool.time)) / \(Clock.text(pool.duration))")
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .transition(.opacity)
            }
        }
        .onAppear(perform: autoHide)
        .onChange(of: scrubbing) { _, now in if !now { autoHide() } }
    }

    private func autoHide() {
        hide?.cancel()
        hide = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, pool.playing, !scrubbing else { return }
            withAnimation(.easeOut(duration: 0.35)) { chrome = false }
        }
    }
}
