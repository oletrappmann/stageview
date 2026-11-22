import SwiftUI

/// Startseite: alle Links wie die Aufgaben Seite der TESS App. Oben das StageView Zeichen (Tipp öffnet Konto und Darstellung),
/// großer Titel, Kunden als Reihe wie die Personen, darunter der Glasschalter (Alle, Kommentare, Änderung, Fertig), Meldungen
/// und die Links als Karten. Unten Suche, Neuer Link und Sortieren als Glasknöpfe.
struct LinksPage: View {
    @Binding var path: [Route]
    @State private var store = Store.shared
    @State private var searching = false
    @State private var confirmSignOut = false
    @State private var deleting: Project?
    @State private var editingCustomer: Customer?
    @State private var newCustomer = false
    @State private var customersOpen = false
    @State private var newLink: NewLinkStart?
    @FocusState private var searchFocused: Bool
    @AppStorage("sv.darstellung") private var appearance = "auto"

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.customer?.name ?? "Links")
                        .font(.pageTitle)
                        .tracking(-0.9)
                        .foregroundStyle(Palette.text)
                        .contentTransition(.opacity)
                        .accessibilityIdentifier("seitentitel")
                    if store.overview != nil {
                        Text(store.summary)
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.muted)
                            .contentTransition(.opacity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .animation(.easeOut(duration: 0.2), value: store.customerID)

                CustomerRow(open: { customersOpen = true }, edit: { editingCustomer = $0 }, newLink: { newLink = NewLinkStart(customerID: $0.id) })

                Section {
                    VStack(spacing: 14) {
                        JobsPanel(path: $path)
                        if store.overview == nil {
                            loading
                        } else if store.visibleProjects.isEmpty {
                            emptyState
                        } else {
                            ForEach(store.visibleProjects) { project in
                                LinkCard(project: project, open: { path.append(.project(project.key)) }, delete: { deleting = project })
                                    .transition(.opacity)
                            }
                        }
                        MadeByStagecraft().padding(.top, 26)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .animation(.easeOut(duration: 0.18), value: store.visibleProjects.map(\.key))
                } header: {
                    GlassSwitch(options: LinkFilter.allCases.map { ($0.rawValue, $0.label) }, selection: store.filter.rawValue,
                                badges: store.filterBadges) { id in
                        withAnimation(.easeOut(duration: 0.12)) { store.filter = LinkFilter(rawValue: id) ?? .all }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
            }
            .padding(.bottom, 130)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await store.refresh(quiet: false) }
        .background(Palette.canvas.ignoresSafeArea())
        .safeAreaBar(edge: .top) { topBar }
        .safeAreaBar(edge: .bottom) { bottomBar }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await store.signOut() } }
        } message: {
            Text("Dieses iPhone wird auch in der TESS App abgemeldet. Danach braucht es wieder Name und Passwort.")
        }
        .confirmationDialog("Link löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Link löschen", role: .destructive) {
                guard let project = deleting else { return }
                Haptics.cancel()
                Task { await store.deleteLink(project) }
            }
        } message: {
            Text(DeleteText.link(deleting))
        }
        .sheet(item: $editingCustomer) { customer in CustomerEditSheet(customer: customer) }
        .sheet(isPresented: $newCustomer) { CustomerEditSheet(customer: nil) }
        .sheet(isPresented: $customersOpen) { CustomersSheet() }
        .sheet(item: $newLink) { start in NewLinkSheet(start: start, path: $path) }
        #if DEBUG
        .onAppear {
            if Demo.sheet == "kunden" { customersOpen = true }
            if Demo.sheet?.hasPrefix("neu") == true { newLink = NewLinkStart() }
        }
        #endif
    }

    // MARK: Kopf

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                accountMenu
                Spacer()
                if store.visibleJobs.contains(where: \.running) {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Läuft").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .accessibilityIdentifier("auftrag-laeuft")
                }
            }
            .padding(.leading, 22)
            .padding(.trailing, 16)
            .frame(height: 52)
            .animation(.easeOut(duration: 0.25), value: store.visibleJobs.contains(where: \.running))
            if !Connection.shared.online { OfflineCapsule().transition(.opacity.combined(with: .offset(y: -8))) }
        }
        .background(alignment: .top) { TopEdge() }
    }

    /// Tipp aufs Zeichen: Darstellung, dann mit Abstand „Angemeldet als“ und Abmelden (wie die TESS App am Logo, Ole 07.11.2026:
    /// kritische Knöpfe nie direkt neben anderen)
    private var accountMenu: some View {
        Menu {
            Section("Darstellung") {
                Picker("Darstellung", selection: $appearance) {
                    Label("Automatisch", systemImage: "circle.lefthalf.filled").tag("auto")
                    Label("Hell", systemImage: "sun.max").tag("hell")
                    Label("Dunkel", systemImage: "moon").tag("dunkel")
                }
            }
            Section {
                Link(destination: URL(string: "https://videos.stagecraft.media/admin")!) {
                    Label("Dashboard im Browser", systemImage: "safari")
                }
            }
            Section("Angemeldet als \(store.me?.name ?? "")") {
                Button(role: .destructive) { confirmSignOut = true } label: {
                    Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            Section("StageView \(AppInfo.version) · \(AppInfo.built)") {}
        } label: {
            StageViewWordmark(height: 16)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.select() })
        .accessibilityLabel("Konto und Darstellung")
        .accessibilityIdentifier("konto")
    }

    // MARK: Fuß

    private var bottomBar: some View {
        Group {
            if searching {
                searchField.transition(.opacity.combined(with: .offset(y: 12)))
            } else {
                GlassEffectContainer(spacing: 24) {
                    HStack(spacing: 0) {
                        Button {
                            Haptics.select()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { searching = true }
                            searchFocused = true
                        } label: { GlassCircle(symbol: "magnifyingglass", active: !store.search.isEmpty) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Suchen")
                            .accessibilityIdentifier("suchen")
                        Spacer()
                        Button {
                            Haptics.press()
                            newLink = NewLinkStart(customerID: store.customerID)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 70, height: 70)
                                .glassEffect(.regular.tint(Palette.forest).interactive(), in: .circle)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Neuer Link")
                        .accessibilityIdentifier("neuer-link")
                        Spacer()
                        sortMenu
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
        .background(alignment: .bottom) { BottomEdge() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.muted)
            TextField("", text: $store.search, prompt: Text("Titel, Kunde oder Code").foregroundStyle(Palette.faint))
                .font(.system(size: 17))
                .foregroundStyle(Palette.text)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("suchfeld")
            Button {
                Haptics.select()
                store.search = ""
                searchFocused = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { searching = false }
            } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                    .frame(width: 36, height: 36).background(Palette.surface, in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Suche schließen")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(height: 54)
        .glassEffect(.regular, in: .capsule)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sortieren", selection: $store.sort) {
                ForEach(LinkSort.allCases, id: \.self) { sort in Label(sort.label, systemImage: sort.symbol).tag(sort) }
            }
        } label: {
            GlassCircle(symbol: "arrow.up.arrow.down")
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.select() })
        .accessibilityLabel("Sortieren")
        .accessibilityIdentifier("sortieren")
    }

    // MARK: Zustände

    private var loading: some View {
        HStack(spacing: 10) {
            if Connection.shared.online { ProgressView().controlSize(.small) }
            Text(store.loadError ?? (Connection.shared.online ? "Links laden …" : "Ohne Verbindung gibt es hier noch nichts."))
                .font(.system(size: 15))
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(store.projects.isEmpty ? "Noch keine Links" : !store.search.isEmpty ? "Nichts gefunden" : "Hier ist gerade nichts")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.text)
            Text(store.projects.isEmpty ? "Plus unten legt den ersten an." : !store.search.isEmpty ? "Such nach Titel, Kunde oder Code." :
                    "In dieser Ansicht gibt es keinen Link.")
                .font(.system(size: 15))
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

/// Wie lange der Text beim Löschen eines Links ist (gleich wie im Dashboard)
enum DeleteText {
    static func link(_ project: Project?) -> String {
        guard let project else { return "" }
        return "„\(project.title)“ ist danach für alle weg, auch für den Kunden: \(project.shortLink) zeigt nur noch eine Fehlerseite. "
            + "Videos im Drive und bei Mux und alle Kommentare bleiben gespeichert, zurückholen kann TESS."
    }
}

// MARK: Kunden Reihe

/// Kunden als Kreise wie die Personen auf der TESS Aufgaben Seite. Vorne „Alle“, rechts fest der Ordner Kunden (verwalten).
/// Langes Drücken: Neuer Link für den Kunden, Bearbeiten.
private struct CustomerRow: View {
    let open: () -> Void
    let edit: (Customer) -> Void
    let newLink: (Customer) -> Void
    @State private var store = Store.shared

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    allButton
                    ForEach(store.customers) { customer in
                        button(customer)
                            .visualEffect { content, proxy in
                                let fade = Self.underFolder(proxy)
                                return content.blur(radius: fade * 7).opacity(1 - fade * 0.92)
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.leading, 18)
                .padding(.trailing, 104)
                .padding(.top, 16)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            folder.padding(.trailing, 18)
        }
    }

    private var allButton: some View {
        let chosen = store.customerID == nil
        return Button {
            Haptics.select()
            withAnimation(.easeOut(duration: 0.15)) { store.customerID = nil }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Palette.text)
                    .frame(width: 52, height: 52)
                    .background(Palette.surface, in: Circle())
                    .overlay { if chosen { SelectedRing() } }
                Text("Alle")
                    .font(.system(size: 12, weight: chosen ? .semibold : .medium))
                    .foregroundStyle(chosen ? Palette.text : Palette.muted)
            }
            .frame(width: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .accessibilityIdentifier("kunde-alle")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func button(_ customer: Customer) -> some View {
        let chosen = store.customerID == customer.id
        let links = store.links(of: customer)
        return Button {
            Haptics.select()
            withAnimation(.easeOut(duration: 0.15)) { store.customerID = chosen ? nil : customer.id }
        } label: {
            VStack(spacing: 7) {
                CustomerAvatar(name: customer.name, size: 52)
                    .opacity(links == 0 ? 0.45 : 1)
                    .overlay { if chosen { SelectedRing() } }
                    .overlay(alignment: .topTrailing) {
                        if links > 0 {
                            Text("\(links)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.text)
                                .frame(minWidth: 18, minHeight: 18)
                                .padding(.horizontal, links > 9 ? 3 : 0)
                                .background(Palette.field, in: Capsule())
                                .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))
                                .offset(x: 4, y: -2)
                        }
                    }
                Text(customer.name.split(separator: " ").first.map(String.init) ?? customer.name)
                    .font(.system(size: 12, weight: chosen ? .semibold : .medium))
                    .foregroundStyle(chosen ? Palette.text : Palette.muted)
                    .lineLimit(1)
            }
            .frame(width: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .contextMenu {
            Button { newLink(customer) } label: { Label("Neuer Link für \(customer.name)", systemImage: "plus") }
            Button { edit(customer) } label: { Label("Bearbeiten", systemImage: "pencil") }
        }
        .accessibilityLabel(customer.name)
        .accessibilityIdentifier("kunde-\(customer.id)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var folder: some View {
        Button {
            Haptics.select()
            open()
        } label: {
            VStack(spacing: 7) {
                Image(systemName: "person.2")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Palette.text)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular.interactive(), in: .circle)
                Text("Kunden")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
            .frame(width: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("kunden-ordner")
    }

    /// Weicher Übergang unter dem Ordner wie in der TESS App: was darunter läuft, verschwimmt und blendet aus
    nonisolated static func underFolder(_ proxy: GeometryProxy) -> CGFloat {
        guard let visible = proxy.bounds(of: .scrollView(axis: .horizontal)) else { return 0 }
        // Ordner: 58 breit, 18 vom Rand. Der Übergang beginnt kurz vor ihm und ist nach 44 pt unter ihm fertig (wie TESS)
        let overlap = proxy.size.width - (visible.maxX - 80)
        return min(max(overlap / 44, 0), 1)
    }
}

// MARK: Karte eines Links

/// Ein Link als weiße Karte: Vorschaubilder (Tipp öffnet direkt das Video), Titel, Kunde, Freigabe, Kommentare, Code.
/// Tipp auf die Karte öffnet den Link, langes Drücken zeigt alles, was man damit machen kann.
struct LinkCard: View {
    let project: Project
    let open: () -> Void
    let delete: () -> Void
    @State private var store = Store.shared
    @Environment(\.zoomSpace) private var zoom

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !project.videos.isEmpty { images }
            VStack(alignment: .leading, spacing: 3) {
                Text(project.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(project.detail)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            if !project.videos.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ApprovalBar(approved: project.approved, changes: project.changes, total: project.videos.count)
                    summary
                }
            } else if project.waiting > 0 || !store.runningJobs(for: project.code).isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Mux bereitet die Videos vor").font(.system(size: 14)).foregroundStyle(Palette.muted)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 11, weight: .semibold))
                Text(project.shortLink).font(.system(size: 13, weight: .medium)).lineLimit(1).layoutPriority(1)
                Spacer(minLength: 8)
                if let last = project.lastActivity {
                    Text(When.ago(last)).font(.system(size: 13)).lineLimit(1)
                }
            }
            .foregroundStyle(Palette.faint)
        }
        .padding(16)
        .background(Palette.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.line.opacity(0.6), lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            Haptics.select()
            open()
        }
        .contextMenu { LinkMenuItems(project: project, open: open, delete: delete) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("link-\(project.code ?? project.key)")
    }

    private var summary: some View {
        let open = project.openCount
        let comments = Text(open > 0 ? Plural.count(open, "offener Kommentar", "offene Kommentare") : "").foregroundStyle(Palette.changesInk).bold()
        return Text("\(project.approvalSummary)\(open > 0 ? " · " : "")\(comments)")
            .font(.system(size: 14))
            .foregroundStyle(Palette.muted)
            .lineLimit(2)
    }

    @ViewBuilder
    private var images: some View {
        if project.allLandscape, let first = project.videos.first {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { RemoteImage(url: first.thumbnail(width: 720)) }
                .overlay { PlayDisc(size: 46) }
                .overlay(alignment: .bottomTrailing) {
                    if project.videos.count > 1 {
                        Text(Plural.count(project.videos.count, "Video", "Videos"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.5), in: Capsule())
                            .padding(10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .zoomSource("liste-\(first.id)", zoom)
                .onTapGesture { play(first) }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(first.title) abspielen")
        } else {
            HStack(spacing: 6) {
                ForEach(0..<min(4, project.videos.count), id: \.self) { slot in
                    Color.clear
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .overlay {
                            if slot < project.videos.count {
                                RemoteImage(url: project.videos[slot].thumbnail(width: 360))
                                    .overlay(alignment: .bottomLeading) { statusMark(project.videos[slot]) }
                            }
                        }
                        .overlay {
                            if slot == 3, project.videos.count > 4 {
                                ZStack {
                                    Color.black.opacity(0.45)
                                    Text("+\(project.videos.count - 3)")
                                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .containerRelativeFrame(.horizontal) { width, _ in (width - 32 - 18 - 32) / 4 }
                        .zoomSource(slot < project.videos.count ? "liste-\(project.videos[slot].id)" : "leer-\(slot)", zoom)
                        .onTapGesture {
                            if slot < project.videos.count { play(project.videos[slot]) } else { Haptics.select(); open() }
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(slot < project.videos.count ? "\(project.videos[slot].title) abspielen" : "")
                        .accessibilityIdentifier(slot < project.videos.count ? "vorschau-\(project.videos[slot].nr)" : "leer")
                }
            }
        }
    }

    /// Kleiner Punkt unten links im Bild: freigegeben oder Änderung gewünscht
    @ViewBuilder
    private func statusMark(_ video: Video) -> some View {
        if video.status != .pending {
            Image(systemName: video.status == .approved ? "checkmark" : "pencil")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(video.status == .approved ? Palette.approved : Palette.changes, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                .padding(6)
        }
    }

    private func play(_ video: Video) {
        Haptics.press()
        store.play(project, video, source: "liste-\(video.id)")
    }
}

/// Alles, was man mit einem Link machen kann (langes Drücken auf die Karte, Menü auf der Projektseite)
struct LinkMenuItems: View {
    let project: Project
    var open: (() -> Void)?
    let delete: () -> Void
    @State private var store = Store.shared

    var body: some View {
        if let first = project.videos.first {
            Button { store.play(project, first, source: nil) } label: { Label("Ansehen", systemImage: "play.rectangle") }
        }
        if let open { Button(action: open) { Label("Öffnen", systemImage: "rectangle.stack") } }
        if let link = project.link {
            Section {
                Button {
                    UIPasteboard.general.url = link
                    store.show("Link kopiert", symbol: "doc.on.doc")
                } label: { Label("Link kopieren", systemImage: "doc.on.doc") }
                ShareLink(item: link) { Label("Teilen", systemImage: "square.and.arrow.up") }
                Link(destination: link) { Label("In Safari öffnen", systemImage: "safari") }
            }
            Section {
                Button(role: .destructive, action: delete) { Label("Link löschen", systemImage: "trash") }
            }
        }
    }
}
