import SwiftUI

// Gemeinsame Teile der Startseite: Kopf mit Suche und Konto, Filter als Glaskapseln, schwebender Knopf Neuer Link, Kennzahlen.
// Designsprache wie die TESS App (Glas, Farben, Haptik), Aufbau eigenständig (Ole, 22.11.2026).

extension Store {
    /// Links eines Kunden, neueste Aktivität zuerst
    func projects(of customer: Customer) -> [Project] {
        projects.filter { customer.owns($0) }.sorted { ($0.lastActivity ?? $0.created ?? "") > ($1.lastActivity ?? $1.created ?? "") }
    }

    /// Zuletzt aktive Links (Kommentar, Status, angelegt)
    func recent(_ limit: Int) -> [Project] {
        Array(projects.filter { !$0.videos.isEmpty }.sorted { ($0.lastActivity ?? $0.created ?? "") > ($1.lastActivity ?? $1.created ?? "") }.prefix(limit))
    }

    /// Kunden mit ihren sichtbaren Links (Ansicht und Suche gelten), Kunden mit der neuesten Aktivität zuerst
    var shelves: [(customer: Customer, projects: [Project])] {
        let visible = visibleProjects
        return customers.compactMap { c -> (Customer, [Project])? in
            let list = visible.filter { c.owns($0) }
            return list.isEmpty ? nil : (c, list)
        }
        .sorted { a, b in
            let x = a.1.map { $0.lastActivity ?? $0.created ?? "" }.max() ?? "", y = b.1.map { $0.lastActivity ?? $0.created ?? "" }.max() ?? ""
            return x > y
        }
    }

    /// Neueste offene Kommentare über alle Links
    func latestComments(_ limit: Int) -> [(project: Project, comment: OpenComment)] {
        let all = projects.flatMap { p in p.openComments.map { (p, $0) } }
        return Array(all.sorted { ($0.1.created ?? "") > ($1.1.created ?? "") }.prefix(limit))
    }

    struct Totals { var openComments = 0, changes = 0, pending = 0, approved = 0, videos = 0, doneLinks = 0 }

    var totals: Totals {
        var t = Totals()
        for p in customerScoped {
            t.openComments += p.openCount
            t.changes += p.changes
            t.approved += p.approved
            t.videos += p.videos.count
            t.pending += p.videos.count - p.approved - p.changes
            if p.allApproved { t.doneLinks += 1 }
        }
        return t
    }

    /// Links des gewählten Kunden (oder alle), ohne Ansicht und Suche
    var customerScoped: [Project] { customer.map { c in projects.filter { c.owns($0) } } ?? projects }
}

// MARK: Kopf

/// Kopf der Startseite: StageView links, rechts Suche und das eigene Gesicht (Konto Menü). Beim Suchen wird daraus ein Glasfeld.
struct StartTopBar: View {
    @Binding var searching: Bool
    var customers: () -> Void
    @State private var store = Store.shared
    @State private var confirmSignOut = false
    @FocusState private var focused: Bool
    @AppStorage("sv.darstellung") private var appearance = "auto"

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if searching {
                    searchField.transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                } else {
                    HStack(spacing: 10) {
                        StageViewWordmark(height: 15)
                        Spacer()
                        Button {
                            Haptics.select()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { searching = true }
                            focused = true
                        } label: { GlassCircle(symbol: "magnifyingglass", size: 44, symbolSize: 17) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Suchen")
                            .accessibilityIdentifier("suchen")
                        account
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            if !Connection.shared.online { OfflineCapsule().transition(.opacity) }
        }
        .background(alignment: .top) { TopEdge() }
        .confirmationDialog("Abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await store.signOut() } }
        } message: {
            Text("Dieses iPhone wird auch in der TESS App abgemeldet. Danach braucht es wieder Name und Passwort.")
        }
    }

    private var account: some View {
        Menu {
            Section {
                Button(action: customers) { Label("Kunden verwalten", systemImage: "person.2") }
                Link(destination: URL(string: "https://videos.stagecraft.media/admin")!) { Label("Dashboard im Browser", systemImage: "safari") }
            }
            Section("Darstellung") {
                Picker("Darstellung", selection: $appearance) {
                    Label("Automatisch", systemImage: "circle.lefthalf.filled").tag("auto")
                    Label("Hell", systemImage: "sun.max").tag("hell")
                    Label("Dunkel", systemImage: "moon").tag("dunkel")
                }
            }
            Section("Angemeldet als \(store.me?.name ?? "")") {
                Button(role: .destructive) { confirmSignOut = true } label: { Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right") }
            }
            Section("StageView \(AppInfo.version) · \(AppInfo.built)") {}
        } label: {
            Group {
                if let access = store.me.flatMap({ Access(rawValue: $0.zugang) }) {
                    TeamAvatar(access: access, size: 36)
                } else {
                    Image(systemName: "person.fill").font(.system(size: 16)).frame(width: 36, height: 36)
                }
            }
            .padding(4)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.select() })
        .accessibilityLabel("Konto")
        .accessibilityIdentifier("konto")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.muted)
            TextField("", text: $store.search, prompt: Text("Titel, Kunde oder Code").foregroundStyle(Palette.faint))
                .font(.system(size: 17))
                .foregroundStyle(Palette.text)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("suchfeld")
            Button {
                Haptics.select()
                store.search = ""
                focused = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { searching = false }
            } label: {
                Text("Fertig").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    .padding(.horizontal, 14).frame(height: 36).background(Palette.surface, in: Capsule())
            }
            .buttonStyle(PressStyle())
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 48)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: Filter

/// Ansichten als einzelne Glaskapseln zum Wischen (nicht der Schalter der TESS App): gewählt dunkelgrün, Zahl dahinter
struct FilterChips: View {
    var leading: CGFloat = 20
    @State private var store = Store.shared

    var body: some View {
        let t = store.totals
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip(.all, "Alle", nil)
                    chip(.comments, "Offene Kommentare", t.openComments)
                    chip(.changes, "Änderung gewünscht", t.changes)
                    chip(.done, "Freigegeben", t.doneLinks)
                }
            }
            .padding(.horizontal, leading)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ filter: LinkFilter, _ title: String, _ count: Int?) -> some View {
        let chosen = store.filter == filter
        return Button {
            Haptics.select()
            withAnimation(.easeOut(duration: 0.18)) { store.filter = chosen && filter != .all ? .all : filter }
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 14, weight: chosen ? .semibold : .medium))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(chosen ? Palette.forest : Palette.canvas)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(chosen ? Color.white : (filter == .comments ? Palette.changesInk : Palette.muted), in: Capsule())
                }
            }
            .foregroundStyle(chosen ? Color.white : Palette.text)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .glassEffect(chosen ? .regular.tint(Palette.forest).interactive() : .regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter-\(filter.rawValue)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

// MARK: Neuer Link

/// Schwebender Glasknopf unten in der Mitte: „Neuer Link“
struct NewLinkCapsule: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.press()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 17, weight: .bold))
                Text("Neuer Link").font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 54)
            .glassEffect(.regular.tint(Palette.forest).interactive(), in: .capsule)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("neuer-link")
    }
}

// MARK: Bausteine

/// Mosaik aus den Standbildern eines Links: Hochkant bis drei nebeneinander, Querformat ein Bild
struct LinkCover: View {
    let project: Project
    var count = 3
    var width = 480

    var body: some View {
        let videos = Array(project.videos.prefix(project.allLandscape ? 1 : count))
        HStack(spacing: 2) {
            ForEach(videos) { video in
                RemoteImage(url: video.thumbnail(width: width))
            }
            if videos.isEmpty { Palette.surface }
        }
        .accessibilityHidden(true)
    }
}

/// Ring mit Anteil freigegeben (Änderungen warm), Zahl in der Mitte
struct ApprovalRing: View {
    let project: Project
    var size: CGFloat = 40

    var body: some View {
        let total = CGFloat(max(project.videos.count, 1))
        ZStack {
            Circle().stroke(Palette.surface, lineWidth: 4)
            Circle().trim(from: 0, to: CGFloat(project.approved) / total)
                .stroke(Palette.approvedInk, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle().trim(from: CGFloat(project.approved) / total, to: CGFloat(project.approved + project.changes) / total)
                .stroke(Palette.changesInk, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(project.approved)/\(project.videos.count)")
                .font(.system(size: size * 0.26, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.text)
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(project.approved) von \(project.videos.count) freigegeben")
    }
}

/// Kleine Marke mit offenen Kommentaren (warm)
struct OpenBadge: View {
    let count: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "text.bubble.fill").font(.system(size: 10, weight: .bold))
            Text("\(count)").font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Palette.changes, in: Capsule())
        .accessibilityLabel(Plural.count(count, "offener Kommentar", "offene Kommentare"))
    }
}

/// Überschrift eines Bereichs mit optionalem Knopf rechts
struct StartHeading: View {
    let title: String
    var detail: String?
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 20, weight: .bold)).tracking(-0.3).foregroundStyle(Palette.text)
                if let detail { Text(detail).font(.system(size: 14)).foregroundStyle(Palette.muted) }
            }
            Spacer()
            if let action {
                Button {
                    Haptics.select()
                    action.run()
                } label: {
                    HStack(spacing: 3) {
                        Text(action.title).font(.system(size: 15, weight: .semibold))
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }
}
