import SwiftUI

/// Startseite nach Konzept 2 „Eingang“ (Ole, 22.11.2026): die neuesten Links ganz oben, keine großen Kacheln, „lieber einfach nur
/// direkt die Links sehen oder vielleicht noch kurz Tabs, Shortcuts zu den anderen Seiten“. Vier Entwürfe, bis Ole wählt
/// (Testbuild: SV_START = liste, tabs, kurzwege, leiste).
enum StartConcept: String, CaseIterable {
    /// A: nur die Links, Filter klein oben rechts
    case liste
    /// B: Links, Kommentare, Kunden als Umschalter unter dem Kopf, zum Wischen
    case tabs
    /// C: eine Reihe kleiner Kurzwege über den Links, jede öffnet eine eigene Seite
    case kurzwege
    /// D: Apples Tab Leiste unten, Neuer Link oben im Kopf
    case leiste

    static var current: StartConcept {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["SV_START"], let concept = StartConcept(rawValue: value) { return concept }
        #endif
        return .liste
    }
}

/// Aktionen, die jede Liste braucht
struct StartActions {
    var open: (Project) -> Void
    var play: (Project, Video, String) -> Void
    var newLink: (String?) -> Void
    var customer: (Customer) -> Void
    var delete: (Project) -> Void
    var manageCustomers: () -> Void = {}
    var go: (Route) -> Void = { _ in }
}

/// Bereiche, die Tabs und Kurzwege öffnen
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
}

/// Startseite: gewählter Entwurf, dazu Kopf, Neuer Link, Fenster und Rückfragen für alle gleich
struct StartPage: View {
    @Binding var path: [Route]
    @State private var store = Store.shared
    @State private var searching = false
    @State private var newLink: NewLinkStart?
    @State private var customersOpen = false
    @State private var deleting: Project?
    @State private var section: StartSection = .links

    private var actions: StartActions {
        StartActions(open: { path.append(.project($0.key)) },
                     play: { project, video, source in store.play(project, video, source: source) },
                     newLink: { newLink = NewLinkStart(customerID: $0) },
                     customer: { path.append(.customer($0.id)) },
                     delete: { deleting = $0 },
                     manageCustomers: { customersOpen = true },
                     go: { path.append($0) })
    }

    var body: some View {
        Group {
            if store.overview == nil {
                loading.safeAreaBar(edge: .top) { topBar() }
            } else {
                switch StartConcept.current {
                case .liste:
                    StartScroll { FeedLine(); LinkFeed(projects: store.newestProjects, actions: actions) }
                        .safeAreaBar(edge: .top) { topBar() }
                        .safeAreaBar(edge: .bottom) { newLinkBar }
                case .tabs:
                    tabsStart
                case .kurzwege:
                    StartScroll { StartShortcuts(actions: actions); LinkFeed(projects: store.newestProjects, actions: actions) }
                        .safeAreaBar(edge: .top) { topBar() }
                        .safeAreaBar(edge: .bottom) { newLinkBar }
                case .leiste:
                    barStart
                }
            }
        }
        .background(Palette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .linkDeletion($deleting)
        .sheet(isPresented: $customersOpen) { CustomersSheet() }
        .sheet(item: $newLink) { start in NewLinkSheet(start: start, path: $path) }
        .onChange(of: searching) { _, now in if now { section = .links } }
        #if DEBUG
        .onAppear {
            if Demo.sheet == "kunden" { customersOpen = true }
            if Demo.sheet?.hasPrefix("neu") == true { newLink = NewLinkStart() }
            if store.search.isEmpty == false { searching = true }
            if let value = ProcessInfo.processInfo.environment["SV_BEREICH"], let s = StartSection(rawValue: value) { section = s }
        }
        #endif
    }

    private func topBar(tabs: Bool = false, plus: Bool = false) -> some View {
        StartTopBar(searching: $searching, customers: { customersOpen = true },
                    newLink: plus ? { newLink = NewLinkStart(customerID: store.customerID) } : nil,
                    tabs: tabs ? $section : nil)
    }

    private var newLinkBar: some View {
        NewLinkCapsule { newLink = NewLinkStart(customerID: store.customerID) }
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .background(alignment: .bottom) { BottomEdge(height: 120) }
    }

    @ViewBuilder
    private func feed(_ s: StartSection) -> some View {
        switch s {
        case .links: FeedLine(); LinkFeed(projects: store.newestProjects, actions: actions)
        case .kommentare: CommentFeed()
        case .kunden: CustomerFeed(actions: actions)
        }
    }

    // MARK: B: Tabs oben

    private var tabsStart: some View {
        TabView(selection: $section) {
            ForEach(StartSection.allCases) { s in
                StartScroll { feed(s) }.tag(s)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaBar(edge: .top) { topBar(tabs: true) }
        .safeAreaBar(edge: .bottom) { newLinkBar }
    }

    // MARK: D: Leiste unten

    private var barStart: some View {
        TabView(selection: $section) {
            ForEach(StartSection.allCases) { s in
                Tab(s.title, systemImage: s.symbol, value: s) {
                    StartScroll { feed(s) }
                        .safeAreaBar(edge: .top) { topBar(plus: true) }
                        .background(Palette.canvas.ignoresSafeArea())
                }
                .badge(s == .kommentare ? store.totals.openComments : 0)
                .accessibilityIdentifier("leiste-\(s.rawValue)")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Palette.accent)
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

/// Senkrechte Liste der Startseite mit Ziehen zum Aktualisieren und „Made by Stagecraft“ am Ende
struct StartScroll<Content: View>: View {
    var bottom: CGFloat = 110
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
                Text(store.projects.isEmpty ? "Neuer Link unten legt den ersten an." : !store.search.isEmpty ? "Such nach Titel, Kunde oder Code." : "In dieser Ansicht gibt es keinen Link.")
                    .font(.system(size: 15)).foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Kurzwege (Entwurf C)

/// Vier runde Glasknöpfe über den Links, Beschriftung darunter, Zahl als Marke. Anders als ein Filter öffnet jeder eine eigene Seite.
struct StartShortcuts: View {
    let actions: StartActions
    @State private var store = Store.shared

    var body: some View {
        let t = store.totals
        HStack(alignment: .top, spacing: 0) {
            shortcut("kommentare", "Kommentare", "text.bubble", t.openComments) { actions.go(.comments) }
            shortcut("aenderung", "Änderung", "pencil", t.changes) { actions.go(.filtered(LinkFilter.changes.rawValue)) }
            shortcut("kunden", "Kunden", "person.2", 0) { actions.go(.customers) }
            shortcut("fertig", "Freigegeben", "checkmark", 0) { actions.go(.filtered(LinkFilter.done.rawValue)) }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func shortcut(_ id: String, _ title: String, _ symbol: String, _ count: Int, _ run: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            run()
        } label: {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    GlassCircle(symbol: symbol, size: 56, symbolSize: 20)
                    if count > 0 {
                        Text("\(count)").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                            .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 22)
                            .background(Palette.changes, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.canvas, lineWidth: 2))
                            .offset(x: 8, y: -4)
                            .zIndex(1)
                    }
                }
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .accessibilityLabel(count > 0 ? "\(title), \(count)" : title)
        .accessibilityIdentifier("kurzweg-\(id)")
    }
}

// MARK: - Seiten hinter Kurzwegen (Entwurf C)

/// Alle offenen Kommentare über alle Links, neueste zuerst
struct CommentsPage: View {
    var body: some View {
        StartScroll(bottom: 30) { CommentFeed(showsLine: false) }
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle("Kommentare")
            .navigationBarTitleDisplayMode(.large)
    }
}

/// Alle Kunden mit ihren Links
struct CustomersPage: View {
    @Binding var path: [Route]
    @State private var manage = false

    var body: some View {
        StartScroll(bottom: 30) {
            CustomerFeed(actions: StartActions(open: { path.append(.project($0.key)) }, play: { _, _, _ in }, newLink: { _ in },
                                               customer: { path.append(.customer($0.id)) }, delete: { _ in },
                                               manageCustomers: { manage = true }))
        }
        .background(Palette.canvas.ignoresSafeArea())
        .navigationTitle("Kunden")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $manage) { CustomersSheet() }
    }
}

/// Links einer Ansicht (Änderung gewünscht, Freigegeben), neueste zuerst
struct FilteredLinksPage: View {
    let filter: LinkFilter
    @Binding var path: [Route]
    @State private var store = Store.shared
    @State private var deleting: Project?

    var body: some View {
        let list = store.projects.filter(filter.matches).sorted { ($0.created ?? "") > ($1.created ?? "") }
        StartScroll(bottom: 30) {
            Text(store.summary(of: list)).font(.system(size: 13)).foregroundStyle(Palette.muted).padding(.horizontal, 22)
            LinkFeed(projects: list, actions: StartActions(open: { path.append(.project($0.key)) },
                                                           play: { project, video, source in store.play(project, video, source: source) },
                                                           newLink: { _ in }, customer: { _ in }, delete: { deleting = $0 }),
                     empty: "Gerade kein Link in dieser Ansicht")
        }
        .background(Palette.canvas.ignoresSafeArea())
        .navigationTitle(filter.longLabel)
        .navigationBarTitleDisplayMode(.large)
        .linkDeletion($deleting)
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
                                                                   newLink: { _ in }, customer: { _ in }, delete: { deleting = $0 }))
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
