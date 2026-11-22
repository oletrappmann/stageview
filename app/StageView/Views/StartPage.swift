import SwiftUI

/// Startseite (Ole, 22.11.2026): drei Seiten Links, Kommentare, Kunden, unten eine Leiste wie in iOS zum Antippen, dazwischen
/// wischen wie in der TESS App. Links nach Konzept 2 „Eingang“: die neuesten ganz oben, kompakte Zeilen, keine großen Kacheln.
/// Apples TabView kann nicht wischen, deshalb eigener Blätterer (wie TESS ContentView.pager) und eigene Leiste im gleichen Glas.

/// Seiten der Startseite, in der Leiste unten
enum StartSection: String, CaseIterable, Identifiable, Hashable {
    case links, kommentare, kunden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .links: "Links"
        case .kommentare: "Kommentare"
        case .kunden: "Kunden"
        }
    }
    var symbol: String {
        switch self {
        case .links: "play.rectangle.on.rectangle"
        case .kommentare: "text.bubble"
        case .kunden: "person.2"
        }
    }
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// Blätterstand: 0 Links, 1 Kommentare, 2 Kunden. Nur die Leiste liest ihn, so zeichnet beim Wischen nicht alles neu.
@Observable
final class PageSlide {
    var progress: CGFloat = 0
}

/// Aktionen, die jede Liste braucht
struct StartActions {
    var open: (Project) -> Void
    var play: (Project, Video, String) -> Void
    var newLink: (String?) -> Void
    var customer: (Customer) -> Void
    var delete: (Project) -> Void
    var manageCustomers: () -> Void = {}
    var client: (Project) -> Void = { _ in }
}

/// Startseite: Kopf, drei Seiten zum Wischen, Leiste unten, Fenster und Rückfragen
struct StartPage: View {
    @Binding var path: [Route]
    @State private var store = Store.shared
    @State private var searching = false
    @State private var newLink: NewLinkStart?
    @State private var customersOpen = false
    @State private var deleting: Project?
    @State private var page: StartSection? = .links
    @State private var slide = PageSlide()

    private var actions: StartActions {
        StartActions(open: { path.append(.project($0.key)) },
                     play: { project, video, source in store.play(project, video, source: source) },
                     newLink: { newLink = NewLinkStart(customerID: $0) },
                     customer: { path.append(.customer($0.id)) },
                     delete: { deleting = $0 },
                     manageCustomers: { customersOpen = true },
                     client: { path.append(.client($0.key)) })
    }

    var body: some View {
        Group {
            if store.overview == nil { loading } else { pager }
        }
        .safeAreaBar(edge: .top) {
            StartTopBar(searching: $searching, customers: { customersOpen = true })
        }
        .safeAreaBar(edge: .bottom) { bottomBar }
        .background(Palette.canvas.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .linkDeletion($deleting)
        .sheet(isPresented: $customersOpen) { CustomersSheet() }
        .sheet(item: $newLink) { start in NewLinkSheet(start: start, path: $path) }
        // Suchen gilt den Links: dorthin blättern
        .onChange(of: searching) { _, now in if now, page != .links { withAnimation(.smooth(duration: 0.35)) { page = .links } } }
        // Kurzer Tick bei jedem Seitenwechsel, gewischt oder getippt (wie TESS)
        .onChange(of: page) { _, _ in Haptics.select() }
        #if DEBUG
        .onAppear {
            if Demo.sheet == "kunden" { customersOpen = true }
            if Demo.sheet?.hasPrefix("neu") == true { newLink = NewLinkStart() }
            if store.search.isEmpty == false { searching = true }
        }
        .task {
            guard let value = ProcessInfo.processInfo.environment["SV_BEREICH"], let s = StartSection(rawValue: value) else { return }
            try? await Task.sleep(for: .milliseconds(300))
            page = s
        }
        #endif
    }

    private func startNewLink() { newLink = NewLinkStart(customerID: store.customerID) }

    /// Alle drei Seiten nebeneinander, blättern per Wischen, rastet seitenweise ein
    private var pager: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(StartSection.allCases) { s in
                    StartScroll { feed(s) }
                        .containerRelativeFrame(.horizontal)
                        .id(s)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.width > 0 ? geometry.contentOffset.x / geometry.containerSize.width : 0
        } action: { _, progress in
            slide.progress = progress
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    @ViewBuilder
    private func feed(_ s: StartSection) -> some View {
        switch s {
        case .links:
            if store.search.isEmpty {
                StartWidgets(actions: actions, go: { target in withAnimation(.smooth(duration: 0.35)) { page = target } })
            }
            FeedLine()
            LinkFeed(projects: store.newestProjects, actions: actions)
        case .kommentare: CommentFeed()
        case .kunden: CustomerFeed(actions: actions)
        }
    }

    /// Leiste unten, rechts daneben das Plus für einen neuen Link (Ole, 22.11.2026: Vorschlag 1, wie die Suche neben Apples Tab
    /// Leiste). Sitzt etwas tiefer als der sichere Bereich, wie Apples Tab Leiste.
    private var bottomBar: some View {
        HStack(spacing: 10) {
            StageTabBar(page: $page, slide: slide)
            PlusButton(size: 60, action: startNewLink)
        }
        .padding(.horizontal, 20)
        .offset(y: 10)
        .background(alignment: .bottom) { BottomEdge(height: 150) }
    }

    private var loading: some View {
        VStack(spacing: 10) {
            if Connection.shared.online { ProgressView() }
            Text(store.loadError ?? (Connection.shared.online ? "Links laden …" : "Ohne Verbindung gibt es hier noch nichts."))
                .font(.system(size: 15))
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Leiste unten wie Apples Tab Leiste aus Glas: Zeichen und Name je Seite, die gewählte hinterlegt. Die Hinterlegung gleitet
/// beim Wischen mit, Zahl offener Kommentare als Marke.
struct StageTabBar: View {
    @Binding var page: StartSection?
    let slide: PageSlide
    @State private var store = Store.shared

    var body: some View {
        let count = StartSection.allCases.count
        let progress = min(max(slide.progress, 0), CGFloat(count - 1))
        let current = Int(progress.rounded())
        HStack(spacing: 0) {
            ForEach(StartSection.allCases) { s in
                item(s, chosen: s.index == current)
            }
        }
        .padding(4)
        .background(alignment: .leading) {
            GeometryReader { g in
                let width = (g.size.width - 8) / CGFloat(count)
                Capsule()
                    .fill(Palette.text.opacity(0.12))
                    .frame(width: width, height: g.size.height - 8)
                    .offset(x: 4 + width * progress, y: 4)
            }
        }
        .frame(height: 62)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func item(_ s: StartSection, chosen: Bool) -> some View {
        let open = s == .kommentare ? store.totals.openComments : 0
        return Button {
            withAnimation(.smooth(duration: 0.35)) { page = s }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: chosen ? s.symbol + ".fill" : s.symbol)
                    .font(.system(size: 19, weight: .medium))
                    .frame(height: 25)
                    .overlay(alignment: .topTrailing) {
                        if open > 0 {
                            Text("\(open)").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                                .background(Palette.changes, in: Capsule())
                                .fixedSize()
                                .offset(x: 13, y: -5)
                        }
                    }
                Text(s.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(chosen ? Palette.approved : Palette.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(open > 0 ? "\(s.title), \(open) offen" : s.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("leiste-\(s.rawValue)")
    }
}

/// Plus für einen neuen Link: grünes Glas, rund
struct PlusButton: View {
    var size: CGFloat = 60
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.press()
            action()
        } label: { GlassCircle(symbol: "plus", size: size, symbolSize: size * 0.36, active: true) }
            .buttonStyle(.plain)
            .accessibilityLabel("Neuer Link")
            .accessibilityIdentifier("neuer-link")
    }
}

/// Senkrechte Liste einer Seite mit Ziehen zum Aktualisieren und „Made by Stagecraft“ am Ende
struct StartScroll<Content: View>: View {
    var bottom: CGFloat = 24
    @ViewBuilder let content: Content
    @State private var store = Store.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
                MadeByStagecraft().padding(.top, 36)
            }
            .padding(.top, 6)
            .padding(.bottom, bottom)
            .animation(.easeOut(duration: 0.2), value: store.filter)
            .animation(.easeOut(duration: 0.2), value: store.customerID)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .refreshable { await store.refresh(quiet: false) }
    }
}

/// Leer: nichts gefunden oder nichts in dieser Ansicht
struct StartEmpty: View {
    var text: String?
    @State private var store = Store.shared
    var body: some View {
        VStack(spacing: 6) {
            Text(text ?? (store.projects.isEmpty ? "Noch keine Links" : !store.search.isEmpty ? "Nichts gefunden" : "Hier ist gerade nichts"))
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
            if text == nil {
                Text(store.projects.isEmpty ? "Das Plus legt den ersten an." : !store.search.isEmpty ? "Such nach Titel, Kunde oder Code." : "In dieser Ansicht gibt es keinen Link.")
                    .font(.system(size: 15)).foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Seite eines Kunden

/// Ein Kunde mit allen Links, gleich kompakt wie die Startseite: Kopf mit Zahlen, Neuer Link für ihn, Bearbeiten
struct CustomerPage: View {
    let id: String
    @Binding var path: [Route]
    @State private var store = Store.shared
    @State private var editing = false
    @State private var newLink: NewLinkStart?
    @State private var deleting: Project?

    private var customer: Customer? { store.customers.first { $0.id == id } }

    var body: some View {
        Group {
            if let customer {
                let all = store.projects(of: customer).sorted { ($0.created ?? "") > ($1.created ?? "") }
                let list = all.filter { store.filter.matches($0) }
                let videos = all.flatMap(\.videos)
                StartScroll(bottom: 40) {
                    HStack(spacing: 14) {
                        CustomerAvatar(name: customer.name, size: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(customer.name).font(.system(size: 28, weight: .bold)).tracking(-0.6).foregroundStyle(Palette.text)
                                .accessibilityIdentifier("kunde-titel")
                            Text([customer.company, Plural.count(all.count, "Link", "Links"), Plural.count(videos.count, "Video", "Videos")]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 15)).foregroundStyle(Palette.muted)
                        }
                    }
                    .padding(.horizontal, 20)
                    HStack(spacing: 8) {
                        Button {
                            Haptics.press()
                            newLink = NewLinkStart(customerID: customer.id)
                        } label: { CapsuleButtonLabel(title: "Neuer Link", symbol: "plus", primary: true) }
                            .buttonStyle(PressStyle())
                        Button {
                            Haptics.select()
                            editing = true
                        } label: { CapsuleButtonLabel(title: "Bearbeiten", symbol: "pencil") }
                            .buttonStyle(PressStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    LinkFeed(projects: list, actions: StartActions(open: { path.append(.project($0.key)) },
                                                                   play: { project, video, source in store.play(project, video, source: source) },
                                                                   newLink: { _ in }, customer: { _ in }, delete: { deleting = $0 },
                                                                   client: { path.append(.client($0.key)) }))
                }
                .sheet(isPresented: $editing) { CustomerEditSheet(customer: customer) }
            } else {
                Text("Diesen Kunden gibt es nicht mehr.").font(.system(size: 15)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { FilterMenu(customers: false, bare: true) } }
        .sheet(item: $newLink) { start in NewLinkSheet(start: start, path: $path) }
        .linkDeletion($deleting)
    }
}

extension View {
    /// Rückfrage vor dem Löschen eines Links (gleich auf jeder Seite)
    func linkDeletion(_ deleting: Binding<Project?>) -> some View {
        confirmationDialog("Link löschen?", isPresented: Binding(get: { deleting.wrappedValue != nil }, set: { if !$0 { deleting.wrappedValue = nil } }),
                           titleVisibility: .visible) {
            Button("Link löschen", role: .destructive) {
                guard let project = deleting.wrappedValue else { return }
                Haptics.cancel()
                Task { await Store.shared.deleteLink(project) }
            }
        } message: { Text(DeleteText.link(deleting.wrappedValue)) }
    }
}
