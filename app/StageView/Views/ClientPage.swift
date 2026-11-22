import SwiftUI

/// Sortierung der Kundenansicht wie auf der Videoseite (projekt.html, SORTIERUNG), gemerkt pro Gerät
enum ClientSort: String, CaseIterable {
    case posting, neu, name, freigabe
    var title: String {
        switch self {
        case .posting: "Posting Datum"
        case .neu: "Zuletzt hinzugefügt"
        case .name: "Name"
        case .freigabe: "Freigabe"
        }
    }
    var help: String {
        switch self {
        case .posting: "So, wie die Videos rausgehen"
        case .neu: "Neue Videos zuerst"
        case .name: "Von A bis Z"
        case .freigabe: "Offene zuerst, Freigegebene am Ende"
        }
    }
}

/// Kundenansicht eines Links, so wie der Kunde videos.stagecraft.media/<code> sieht (Ole, 22.11.2026: „Projektlinks mit mehreren
/// Videos in der App in der Client View öffnen, nicht nur in der Admin View, auch wenn man den Link aus dem Web öffnet“).
/// Aufbau wie die Übersicht im Web (projekt.html, uebersichtZeichnen, references/seite.md): grüner Verlauf, Kunde · Firma, Titel
/// groß, Freigabe als Striche, Hinweis, Sortierung, Kacheln 3:4 (nur Querformat: 16:9, eine pro Reihe), Kategorien als Abschnitte
/// zum Einklappen, Darstellung „YouTube“ mit Langvideo groß und Shorts zum Wischen. Tipp auf eine Kachel öffnet den Player.
/// Oben rechts Teilen und Verwalten (die Seite des Links für das Team).
struct ClientPage: View {
    let key: String
    @Binding var path: [Route]
    @State private var store = Store.shared
    @State private var layouts = ClientLayouts.shared
    @State private var closed: Set<String> = []
    @AppStorage("sv.kunde.sortierung") private var sortRaw = ClientSort.posting.rawValue
    @Environment(\.zoomSpace) private var zoom

    private var project: Project? { store.project(key) }
    private var review: ReviewStore? { project?.code.map(ReviewStore.of) }
    private var layout: ClientLayout { project?.code.flatMap(layouts.layout) ?? ClientLayout() }
    private var sort: ClientSort { ClientSort(rawValue: sortRaw) ?? .posting }

    private enum Kind { case normal, wide, main, short }

    var body: some View {
        Group {
            if let project {
                content(project)
            } else {
                Text("Dieser Link ist nicht mehr da.")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { StageViewWordmark(height: 13) }
            if let project {
                ToolbarItem(placement: .topBarTrailing) { shareMenu(project) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.select()
                        path.append(.project(key))
                    } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Verwalten")
                        .accessibilityIdentifier("kunde-verwalten")
                }
            }
        }
        .task(id: project?.code) { if let code = project?.code { await layouts.load(code) } }
        .onAppear { review?.watch() }
        .onDisappear { review?.unwatch() }
    }

    // MARK: Teilen

    private func shareMenu(_ project: Project) -> some View {
        Menu {
            if let link = project.link {
                Button {
                    UIPasteboard.general.url = link
                    store.show("Link kopiert", symbol: "doc.on.doc")
                } label: { Label("Link kopieren", systemImage: "doc.on.doc") }
                ShareLink(item: link) { Label("Teilen …", systemImage: "square.and.arrow.up") }
                Link(destination: link) { Label("In Safari öffnen", systemImage: "safari") }
            }
        } label: {
            Label("Teilen", systemImage: "link").labelStyle(.titleAndIcon)
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.select() })
        .accessibilityIdentifier("kunde-teilen")
    }

    // MARK: Seite

    private func content(_ project: Project) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                hero(project)
                sortBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                grid(project)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                MadeByStagecraft().padding(.top, 34).padding(.bottom, 40)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .refreshable {
            await store.refresh(quiet: false)
            if let code = project.code { await layouts.load(code) }
            await review?.load()
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: closed)
        .animation(.easeOut(duration: 0.25), value: sortRaw)
    }

    /// Kopf: Verlauf im Stagecraft Grün, Kunde · Firma, Titel, Freigabe als Striche, Hinweis
    private func hero(_ project: Project) -> some View {
        let changes = project.videos.filter { status($0) == .changes }.count
        let approved = project.videos.filter { status($0) == .approved }.count
        let hint = !project.note.isEmpty ? project.note : !layout.hint.isEmpty ? layout.hint
            : "Tippe auf ein Video, um es anzusehen. Was geändert werden soll, schreibst du direkt an die Stelle im Video."
        return VStack(spacing: 0) {
            Text([project.customerName, project.company].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.muted)
            Text(project.title)
                .font(.system(size: 38, weight: .semibold))
                .tracking(-1.3)
                .foregroundStyle(Palette.text)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("kunde-seite-titel")
            HStack(spacing: 3) {
                ForEach(project.videos) { video in
                    Capsule().fill(color(status(video), track: true)).frame(height: 4)
                }
            }
            .frame(maxWidth: 320)
            .padding(.horizontal, 30)
            .padding(.top, 22)
            .animation(.easeOut(duration: 0.3), value: approved)
            Text("\(approved) von \(project.videos.count) freigegeben" + (changes > 0 ? " · \(changes) mit Änderung" : ""))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Palette.muted)
                .padding(.top, 9)
            Text(hint)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.faint)
                .frame(maxWidth: 440)
                .padding(.top, 18)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { HeroGlow().frame(height: 440).offset(y: -150) }
    }

    private var sortBar: some View {
        HStack {
            Spacer()
            Menu {
                ForEach(ClientSort.allCases, id: \.self) { option in
                    Button {
                        Haptics.select()
                        sortRaw = option.rawValue
                    } label: {
                        if option == sort {
                            Label { Text(option.title); Text(option.help) } icon: { Image(systemName: "checkmark") }
                        } else {
                            Text(option.title)
                            Text(option.help)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Sortiert nach").foregroundStyle(Palette.muted)
                    Text(sort.title).foregroundStyle(Palette.text)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.muted).padding(.leading, 2)
                }
                .font(.system(size: 14, weight: .medium))
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .frame(height: 38)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .menuOrder(.fixed)
            .simultaneousGesture(TapGesture().onEnded { Haptics.select() })
            .accessibilityIdentifier("kunde-sortierung")
        }
    }

    // MARK: Raster und Abschnitte

    private func sorted(_ videos: [Video]) -> [Video] {
        // Die Reihenfolge der Übersicht ist das Posting Datum, bei Gleichstand bleibt sie die zweite Regel
        switch sort {
        case .posting: videos
        case .neu: videos.sorted { $0.nr > $1.nr }
        case .name: videos.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .freigabe: videos.sorted { order(status($0)) < order(status($1)) }
        }
    }

    private func order(_ s: ReviewStatus) -> Int {
        switch s {
        case .pending: 0
        case .changes: 1
        case .approved: 2
        }
    }

    @ViewBuilder
    private func grid(_ project: Project) -> some View {
        let videos = sorted(project.videos)
        let groups = layout.groups.filter { g in videos.contains { layout.groupOf[$0.id] == g } }
        if groups.isEmpty && !layout.youtube {
            tiles(videos, project: project, wide: project.allLandscape)
        } else {
            let loose = videos.filter { !groups.contains(layout.groupOf[$0.id] ?? "") }
            VStack(alignment: .leading, spacing: 30) {
                if !loose.isEmpty { section(nil, loose, project: project) }
                ForEach(groups, id: \.self) { group in
                    section(group, videos.filter { layout.groupOf[$0.id] == group }, project: project)
                }
            }
        }
    }

    private func tiles(_ videos: [Video], project: Project, wide: Bool) -> some View {
        LazyVGrid(columns: wide ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                  alignment: .leading, spacing: wide ? 22 : 20) {
            ForEach(videos) { tile($0, project: project, kind: wide ? .wide : .normal) }
        }
    }

    /// Abschnitt einer Kategorie: Überschrift zum Einklappen, „x von y freigegeben“, darunter das Raster bzw. YouTube Video und Shorts
    private func section(_ name: String?, _ videos: [Video], project: Project) -> some View {
        let isClosed = name.map(closed.contains) ?? false
        let long = layout.youtube ? videos.filter { !$0.portrait } : []
        let shorts = long.isEmpty ? videos : videos.filter(\.portrait)
        let youtube = !long.isEmpty && !shorts.isEmpty
        let approved = videos.filter { status($0) == .approved }.count
        return VStack(alignment: .leading, spacing: 14) {
            if let name {
                Button {
                    Haptics.select()
                    if isClosed { closed.remove(name) } else { closed.insert(name) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.muted)
                            .rotationEffect(.degrees(isClosed ? -90 : 0))
                        Text(name)
                            .font(.system(size: 19, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(Palette.text)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 10)
                        Text("\(approved) von \(videos.count) freigegeben")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.bottom, 12)
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(isClosed ? "zugeklappt" : "aufgeklappt")
                .accessibilityIdentifier("kategorie-\(name)")
            }
            if !isClosed {
                Group {
                    if youtube {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 10) {
                                label(long.count == 1 ? "YouTube Video" : "\(long.count) YouTube Videos")
                                VStack(spacing: 22) { ForEach(long) { tile($0, project: project, kind: .main) } }
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                label(shorts.count == 1 ? "1 Short" : "\(shorts.count) Shorts")
                                ScrollView(.horizontal) {
                                    HStack(alignment: .top, spacing: 10) {
                                        ForEach(shorts) { tile($0, project: project, kind: .short).frame(width: 128) }
                                    }
                                    .scrollTargetLayout()
                                }
                                .scrollTargetBehavior(.viewAligned)
                                .scrollIndicators(.hidden)
                                .contentMargins(.horizontal, 16, for: .scrollContent)
                                .padding(.horizontal, -16)
                            }
                        }
                    } else {
                        tiles(videos, project: project, wide: project.allLandscape)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.muted)
    }

    // MARK: Kachel

    private func tile(_ video: Video, project: Project, kind: Kind) -> some View {
        let ratio: CGFloat = switch kind {
        case .normal: 3 / 4
        case .wide, .main: 16 / 9
        case .short: 9 / 16
        }
        let open = openCount(video)
        let s = status(video)
        return Button {
            Haptics.press()
            store.play(project, video, source: "kunde-\(video.id)")
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .aspectRatio(ratio, contentMode: .fit)
                    .overlay {
                        if kind == .normal && !video.portrait {
                            // Querformat in der Hochkant Kachel: das ganze Bild, dahinter dasselbe groß und weich
                            GeometryReader { g in
                                ZStack {
                                    RemoteImage(url: video.thumbnail(width: 160), placeholder: Palette.surface)
                                        .blur(radius: 22)
                                        .saturation(1.3)
                                        .brightness(-0.25)
                                        .scaleEffect(1.25)
                                    // Das scharfe Bild bekommt genau das Seitenverhältnis des Videos, so ist es ganz zu sehen
                                    RemoteImage(url: video.thumbnail(width: 480), placeholder: .clear)
                                        .frame(width: g.size.width, height: g.size.width / video.aspect)
                                }
                                .frame(width: g.size.width, height: g.size.height)
                            }
                        } else {
                            RemoteImage(url: video.thumbnail(width: kind == .short ? 320 : 640), placeholder: Palette.surface)
                        }
                    }
                    .overlay {
                        if kind == .main {
                            Image(systemName: "play.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(x: 1.5)
                                .frame(width: 54, height: 54)
                                .glassEffect(.regular, in: .circle)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        badge(Text(Clock.text(video.duration)).monospacedDigit()).padding(8)
                    }
                    .overlay(alignment: .topTrailing) {
                        if open > 0 {
                            badge(HStack(spacing: 4) {
                                Image(systemName: "text.bubble").font(.system(size: 11, weight: .semibold))
                                Text("\(open)")
                            })
                            .padding(8)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: kind == .short ? 14 : 16, style: .continuous))
                    .zoomSource("kunde-\(video.id)", zoom)
                Text(video.title)
                    .font(.system(size: kind == .main ? 16.5 : kind == .short ? 13.5 : 14.5, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 10)
                    .padding(.horizontal, 2)
                HStack(spacing: 6) {
                    Circle().fill(color(s, track: false)).frame(width: 7, height: 7)
                    Text(s.title + (PostingDay.text(video.posting).map { " · " + $0 } ?? ""))
                        .lineLimit(1)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.muted)
                .padding(.top, 2)
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("kachel-\(video.nr)")
    }

    private func badge<V: View>(_ content: V) -> some View {
        content
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
            .background(Color(UIColor(hex: 0x121211)).opacity(0.45), in: Capsule())
            .environment(\.colorScheme, .dark)
    }

    // MARK: Freigabe und Kommentare (live aus dem ReviewStore, sonst aus der Übersicht)

    private func status(_ video: Video) -> ReviewStatus { review?.status(of: video) ?? video.status }

    private func openCount(_ video: Video) -> Int {
        guard let review, review.loaded else { return video.open }
        return review.threads(for: video.id).filter { !$0.root.done }.count
    }

    private func color(_ s: ReviewStatus, track: Bool) -> Color {
        switch s {
        case .pending: track ? Color.white.opacity(0.14) : Palette.pending
        case .changes: Palette.changes
        case .approved: Palette.approved
        }
    }
}

/// Verlauf oben im Stagecraft Grün wie auf der Videoseite (.held .ambient): drei weiche Flecken Salbei und Waldgrün, stark
/// weichgezeichnet und satter, läuft nach unten aus
struct HeroGlow: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: [Color(UIColor(hex: 0x48514A)).opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: w * 0.6))
                    .frame(width: w * 1.3, height: h * 1.1)
                    .position(x: w * 0.5, y: h * 0.3)
                Ellipse()
                    .fill(RadialGradient(colors: [Color(red: 72 / 255, green: 96 / 255, blue: 78 / 255), .clear], center: .center, startRadius: 0, endRadius: w * 0.36))
                    .frame(width: w * 0.8, height: h * 0.8)
                    .position(x: w * 0.68, y: h * 0.38)
                Ellipse()
                    .fill(RadialGradient(colors: [Color(UIColor(hex: 0x93AA98)).opacity(0.95), .clear], center: .center, startRadius: 0, endRadius: w * 0.3))
                    .frame(width: w * 0.7, height: h * 0.7)
                    .position(x: w * 0.34, y: h * 0.44)
            }
            .blur(radius: 50)
            .saturation(2.2)
            .opacity(0.85)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.3), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Posting Tag wie auf der Videoseite (tag): „Mo 24.11.“
enum PostingDay {
    private static let days = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]

    static func text(_ iso: String?) -> String? {
        guard let date = When.date(iso) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let c = calendar.dateComponents([.weekday, .day, .month], from: date)
        guard let weekday = c.weekday, let day = c.day, let month = c.month else { return nil }
        return String(format: "%@ %02d.%02d.", days[weekday - 1], day, month)
    }
}
