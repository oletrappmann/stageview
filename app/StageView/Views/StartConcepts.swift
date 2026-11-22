import SwiftUI

/// Vier Konzepte für die Startseite (Ole, 22.11.2026: „die Designsprache dieselbe, aber niemals die Anordnung und Strukturierung
/// der TESS App“). Bis Ole eins wählt, lassen sie sich im Testbuild mit SV_START umschalten.
enum StartConcept: String, CaseIterable {
    case regal, eingang, kunden, videos

    static var current: StartConcept {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["SV_START"], let concept = StartConcept(rawValue: value) { return concept }
        #endif
        return .regal
    }
}

/// Aktionen, die jedes Konzept braucht
struct StartActions {
    var open: (Project) -> Void
    var play: (Project, Video, String) -> Void
    var newLink: (String?) -> Void
    var customer: (Customer) -> Void
    var delete: (Project) -> Void
}

/// Startseite: gewähltes Konzept, dazu Kopf, Neuer Link unten, Fenster und Rückfragen für alle gleich
struct StartPage: View {
    @Binding var path: [Route]
    @State private var store = Store.shared
    @State private var searching = false
    @State private var newLink: NewLinkStart?
    @State private var customersOpen = false
    @State private var deleting: Project?

    private var actions: StartActions {
        StartActions(open: { path.append(.project($0.key)) },
                     play: { project, video, source in store.play(project, video, source: source) },
                     newLink: { newLink = NewLinkStart(customerID: $0) },
                     customer: { path.append(.customer($0.id)) },
                     delete: { deleting = $0 })
    }

    var body: some View {
        Group {
            if store.overview == nil {
                loading
            } else {
                switch StartConcept.current {
                case .regal: ShelfStart(actions: actions)
                case .eingang: InboxStart(actions: actions)
                case .kunden: FolderStart(actions: actions)
                case .videos: VideoGridStart(actions: actions)
                }
            }
        }
        .background(Palette.canvas.ignoresSafeArea())
        .safeAreaBar(edge: .top) { StartTopBar(searching: $searching, customers: { customersOpen = true }) }
        .safeAreaBar(edge: .bottom) {
            NewLinkCapsule { newLink = NewLinkStart(customerID: store.customerID) }
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
                .background(alignment: .bottom) { BottomEdge(height: 120) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Link löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Link löschen", role: .destructive) {
                guard let project = deleting else { return }
                Haptics.cancel()
                Task { await store.deleteLink(project) }
            }
        } message: { Text(DeleteText.link(deleting)) }
        .sheet(isPresented: $customersOpen) { CustomersSheet() }
        .sheet(item: $newLink) { start in NewLinkSheet(start: start, path: $path) }
        #if DEBUG
        .onAppear {
            if Demo.sheet == "kunden" { customersOpen = true }
            if Demo.sheet?.hasPrefix("neu") == true { newLink = NewLinkStart() }
            if store.search.isEmpty == false { searching = true }
        }
        #endif
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

/// Leer: nichts gefunden oder nichts in dieser Ansicht
struct StartEmpty: View {
    @State private var store = Store.shared
    var body: some View {
        VStack(spacing: 6) {
            Text(store.projects.isEmpty ? "Noch keine Links" : !store.search.isEmpty ? "Nichts gefunden" : "Hier ist gerade nichts")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
            Text(store.projects.isEmpty ? "Neuer Link unten legt den ersten an." : !store.search.isEmpty ? "Such nach Titel, Kunde oder Code." : "In dieser Ansicht gibt es keinen Link.")
                .font(.system(size: 15)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Konzept 1: Regal

/// Oben große Karten der zuletzt aktiven Links zum Wischen, darunter jeder Kunde als eigene Reihe (wie Regale in einer Mediathek)
struct ShelfStart: View {
    let actions: StartActions
    @State private var store = Store.shared
    @Environment(\.zoomSpace) private var zoom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if store.search.isEmpty && store.filter == .all {
                    StartHeading(title: "Zuletzt aktiv").padding(.top, 8)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) {
                            ForEach(store.recent(6)) { project in
                                hero(project).containerRelativeFrame(.horizontal) { w, _ in w * 0.84 }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .contentMargins(.horizontal, 20)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.hidden)
                    .padding(.top, 12)
                }
                FilterChips().padding(.top, 22)
                if store.shelves.isEmpty { StartEmpty() }
                ForEach(store.shelves, id: \.customer.id) { shelf in
                    StartHeading(title: shelf.customer.name, detail: Plural.count(shelf.projects.count, "Link", "Links"),
                                 action: ("Alle", { actions.customer(shelf.customer) }))
                        .padding(.top, 26)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(shelf.projects) { tile($0) }
                        }
                    }
                    .contentMargins(.horizontal, 20)
                    .scrollIndicators(.hidden)
                    .padding(.top, 10)
                }
                MadeByStagecraft().padding(.top, 36)
            }
            .padding(.bottom, 110)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .refreshable { await store.refresh(quiet: false) }
    }

    private func hero(_ project: Project) -> some View {
        Color.clear
            .frame(height: 330)
            .overlay { LinkCover(project: project, count: 3, width: 480) }
            .overlay { LinearGradient(colors: [.clear, .black.opacity(0.15), .black.opacity(0.78)], startPoint: .center, endPoint: .bottom) }
            .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    CustomerAvatar(name: project.customerName, size: 22)
                    Text(project.customerName).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    if let last = project.lastActivity { Text("· " + When.ago(last)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)) }
                }
                Text(project.title).font(.system(size: 24, weight: .bold)).tracking(-0.5).foregroundStyle(.white).lineLimit(2)
                HStack(spacing: 10) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 5)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Capsule().fill(Palette.approved).frame(width: g.size.width * CGFloat(project.approved) / CGFloat(max(project.videos.count, 1)))
                            }
                        }
                    Text("\(project.approved)/\(project.videos.count) frei").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(16)
            .padding(.trailing, 58)
            }
        .overlay(alignment: .topTrailing) {
            if project.openCount > 0 { OpenBadge(count: project.openCount).padding(12) }
        }
        .overlay(alignment: .bottomTrailing) {
            if let first = project.videos.first {
                Button {
                    Haptics.press()
                    actions.play(project, first, "regal-\(first.id)")
                } label: { PlayDisc(size: 48) }
                    .buttonStyle(PressStyle())
                    .padding(14)
                    .accessibilityLabel("Abspielen")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .zoomSource("regal-\(project.videos.first?.id ?? project.key)", zoom)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture { Haptics.select(); actions.open(project) }
        .contextMenu { LinkMenuItems(project: project, open: { actions.open(project) }, delete: { actions.delete(project) }) }
        .accessibilityIdentifier("held-\(project.code ?? project.key)")
    }

    private func tile(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LinkCover(project: project, count: 2, width: 360)
                .frame(width: 156, height: 208)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topLeading) { if project.openCount > 0 { OpenBadge(count: project.openCount).padding(8) } }
            Text(project.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(2)
                .frame(width: 156, alignment: .leading)
            HStack(spacing: 6) {
                ApprovalBar(approved: project.approved, changes: project.changes, total: project.videos.count, height: 4).frame(width: 60)
                Text(Plural.count(project.videos.count, "Video", "Videos")).font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { Haptics.select(); actions.open(project) }
        .contextMenu { LinkMenuItems(project: project, open: { actions.open(project) }, delete: { actions.delete(project) }) }
        .accessibilityIdentifier("kachel-\(project.code ?? project.key)")
    }
}

// MARK: - Konzept 2: Eingang

/// Was gerade wartet: Kennzahlen oben (antippen filtert), dann die neuesten Kommentare mit Bild, dann alle Links kompakt mit Ring
struct InboxStart: View {
    let actions: StartActions
    @State private var store = Store.shared
    @State private var allComments = false

    var body: some View {
        let t = store.totals
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    stat(t.openComments, "Offene Kommentare", "text.bubble.fill", Palette.changesInk, .comments)
                    stat(t.changes, "Änderung gewünscht", "pencil", Palette.changesInk, .changes)
                    stat(t.pending, "Zur Freigabe", "circle.dashed", Palette.pendingInk, .all)
                    stat(t.approved, "Freigegeben", "checkmark", Palette.approvedInk, .done)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                let comments = store.latestComments(allComments ? 30 : 4)
                if !comments.isEmpty && store.search.isEmpty {
                    StartHeading(title: "Neue Kommentare", action: (allComments ? "Weniger" : "Alle", { withAnimation { allComments.toggle() } }))
                        .padding(.top, 28)
                    VStack(spacing: 0) {
                        ForEach(Array(comments.enumerated()), id: \.element.comment.id) { index, item in
                            commentRow(item.project, item.comment).overlay(alignment: .top) { if index > 0 { RowDivider(leading: 16) } }
                        }
                    }
                    .background(Palette.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.line.opacity(0.6), lineWidth: 0.5))
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }

                StartHeading(title: store.filter == .all ? "Alle Links" : store.filter.label, detail: store.summary).padding(.top, 28)
                FilterChips().padding(.top, 10)
                if store.visibleProjects.isEmpty { StartEmpty() } else {
                    VStack(spacing: 0) {
                        ForEach(Array(store.visibleProjects.enumerated()), id: \.element.id) { index, project in
                            row(project).overlay(alignment: .top) { if index > 0 { RowDivider(leading: 86) } }
                        }
                    }
                    .background(Palette.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.line.opacity(0.6), lineWidth: 0.5))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                MadeByStagecraft().padding(.top, 36)
            }
            .padding(.bottom, 110)
            .animation(.easeOut(duration: 0.2), value: store.filter)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .refreshable { await store.refresh(quiet: false) }
    }

    private func stat(_ value: Int, _ title: String, _ symbol: String, _ color: Color, _ filter: LinkFilter) -> some View {
        let chosen = store.filter == filter && filter != .all
        return Button {
            Haptics.select()
            withAnimation(.easeOut(duration: 0.18)) { store.filter = chosen ? .all : filter }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(value)").font(.system(size: 30, weight: .bold).monospacedDigit()).tracking(-0.5).foregroundStyle(Palette.text)
                        .contentTransition(.numericText())
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassEffect(chosen ? .regular.tint(Palette.forest.opacity(0.35)).interactive() : .regular.interactive(),
                         in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("zahl-\(filter.rawValue)")
    }

    private func commentRow(_ project: Project, _ comment: OpenComment) -> some View {
        let video = project.videos.first { $0.id == comment.video }
        return Button {
            guard let video else { return }
            Haptics.press()
            store.play(project, video, at: comment.time, source: nil)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(comment.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                        if let time = comment.time {
                            Text(Clock.text(time)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color(UIColor(hex: 0x1E1E1C))).padding(.horizontal, 7).frame(height: 20)
                                .background(Palette.pending, in: Capsule())
                        }
                        Text(When.ago(comment.created)).font(.system(size: 12)).foregroundStyle(Palette.faint)
                    }
                    Text(comment.text).font(.system(size: 15)).foregroundStyle(Palette.text).lineLimit(2).multilineTextAlignment(.leading)
                    Text("\(project.title) · \(video?.title ?? "")").font(.system(size: 13)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let video {
                    RemoteImage(url: video.thumbnail(width: 240, at: comment.time))
                        .frame(width: video.portrait ? 44 : 70, height: video.portrait ? 78 : 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }

    private func row(_ project: Project) -> some View {
        Button {
            Haptics.select()
            actions.open(project)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    ForEach(Array(project.videos.prefix(3).enumerated().reversed()), id: \.element.id) { index, video in
                        RemoteImage(url: video.thumbnail(width: 240))
                            .frame(width: 40, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.field, lineWidth: 2))
                            .rotationEffect(.degrees(Double(index) * 7 - 7), anchor: .bottom)
                            .offset(x: CGFloat(index) * 6)
                    }
                }
                .frame(width: 56, height: 70)
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text(project.detail).font(.system(size: 13)).foregroundStyle(Palette.muted).lineLimit(1)
                    HStack(spacing: 6) {
                        if project.openCount > 0 { OpenBadge(count: project.openCount) }
                        if let last = project.lastActivity { Text(When.ago(last)).font(.system(size: 12)).foregroundStyle(Palette.faint) }
                    }
                }
                Spacer(minLength: 4)
                ApprovalRing(project: project, size: 44)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .contextMenu { LinkMenuItems(project: project, open: { actions.open(project) }, delete: { actions.delete(project) }) }
        .accessibilityIdentifier("zeile-\(project.code ?? project.key)")
    }
}

// MARK: - Konzept 3: Kunden

/// Erst der Kunde, dann seine Links: Kunden als Ordner mit vier Standbildern, oben die zuletzt aktiven Links als Kapseln
struct FolderStart: View {
    let actions: StartActions
    @State private var store = Store.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if store.search.isEmpty {
                    StartHeading(title: "Zuletzt").padding(.top, 8)
                    ScrollView(.horizontal) {
                        GlassEffectContainer(spacing: 10) {
                            HStack(spacing: 10) { ForEach(store.recent(8)) { pill($0) } }
                        }
                    }
                    .contentMargins(.horizontal, 20)
                    .scrollIndicators(.hidden)
                    .padding(.top, 10)
                    StartHeading(title: "Kunden", detail: "\(Plural.count(store.customers.count, "Kunde", "Kunden")) · \(Plural.count(store.projects.count, "Link", "Links"))")
                        .padding(.top, 26)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
                        ForEach(store.customers.filter { store.links(of: $0) > 0 }) { folder($0) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                } else {
                    StartHeading(title: "Gefunden", detail: store.summary).padding(.top, 8)
                    if store.visibleProjects.isEmpty { StartEmpty() }
                    VStack(spacing: 14) {
                        ForEach(store.visibleProjects) { project in
                            LinkCard(project: project, open: { actions.open(project) }, delete: { actions.delete(project) })
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                MadeByStagecraft().padding(.top, 36)
            }
            .padding(.bottom, 110)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .refreshable { await store.refresh(quiet: false) }
    }

    private func pill(_ project: Project) -> some View {
        Button {
            Haptics.select()
            actions.open(project)
        } label: {
            HStack(spacing: 9) {
                RemoteImage(url: project.videos.first?.thumbnail(width: 160))
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(project.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text(project.customerName).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                if project.openCount > 0 {
                    Text("\(project.openCount)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18).background(Palette.changes, in: Capsule())
                }
            }
            .frame(maxWidth: 210, alignment: .leading)
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .frame(height: 46)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func folder(_ customer: Customer) -> some View {
        let list = store.projects(of: customer)
        let thumbs = Array(list.flatMap(\.videos).prefix(4))
        let open = list.reduce(0) { $0 + $1.openCount }
        return Button {
            Haptics.select()
            actions.customer(customer)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)], spacing: 3) {
                    ForEach(0..<4, id: \.self) { i in
                        Color.clear
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .overlay {
                                if i < thumbs.count { RemoteImage(url: thumbs[i].thumbnail(width: 240)) } else { Palette.surface }
                            }
                            .clipped()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    CustomerAvatar(name: customer.name, size: 40)
                        .overlay(Circle().strokeBorder(Palette.canvas, lineWidth: 3))
                        .offset(x: 10, y: 14)
                }
                .overlay(alignment: .topTrailing) { if open > 0 { OpenBadge(count: open).padding(8) } }
                VStack(alignment: .leading, spacing: 1) {
                    Text(customer.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text([Plural.count(list.count, "Link", "Links"), customer.company].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                .padding(.top, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .accessibilityIdentifier("ordner-\(customer.id)")
    }
}

// MARK: - Konzept 4: Videos

/// Videos zuerst: jedes Video als Bild im Raster, nach Link gruppiert, die Kopfzeile des Links bleibt beim Scrollen oben.
/// Ein Tipp spielt sofort, der Kopf öffnet den Link.
struct VideoGridStart: View {
    let actions: StartActions
    @State private var store = Store.shared
    @Environment(\.zoomSpace) private var zoom

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                HStack(spacing: 8) {
                    customerMenu
                    Spacer()
                    Text(store.summary).font(.system(size: 13)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                FilterChips().padding(.top, 12)
                if store.visibleProjects.isEmpty { StartEmpty() }
                ForEach(store.visibleProjects) { project in
                    Section {
                        grid(project).padding(.horizontal, 16).padding(.bottom, 22)
                    } header: {
                        header(project)
                    }
                }
                MadeByStagecraft().padding(.top, 20)
            }
            .padding(.bottom, 110)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .refreshable { await store.refresh(quiet: false) }
    }

    private var customerMenu: some View {
        Menu {
            Button { store.customerID = nil } label: { Label("Alle Kunden", systemImage: store.customerID == nil ? "checkmark" : "") }
            ForEach(store.customers.filter { store.links(of: $0) > 0 }) { customer in
                Button { store.customerID = customer.id } label: {
                    Label(customer.name, systemImage: store.customerID == customer.id ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 7) {
                if let customer = store.customer { CustomerAvatar(name: customer.name, size: 24) }
                Text(store.customer?.name ?? "Alle Kunden").font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Palette.text)
            .padding(.leading, store.customer == nil ? 14 : 6)
            .padding(.trailing, 14)
            .frame(height: 38)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.select() })
        .accessibilityIdentifier("kunde-menue")
    }

    private func header(_ project: Project) -> some View {
        Button {
            Haptics.select()
            actions.open(project)
        } label: {
            HStack(spacing: 10) {
                CustomerAvatar(name: project.customerName, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(project.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text("\(project.customerName) · \(project.approved) von \(project.videos.count) frei").font(.system(size: 12))
                        .foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer(minLength: 6)
                if project.openCount > 0 { OpenBadge(count: project.openCount) }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.faint)
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .frame(height: 50)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contextMenu { LinkMenuItems(project: project, open: { actions.open(project) }, delete: { actions.delete(project) }) }
        .accessibilityIdentifier("gruppe-\(project.code ?? project.key)")
    }

    private func grid(_ project: Project) -> some View {
        let wide = project.allLandscape
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: wide ? 2 : 3), spacing: 6) {
            ForEach(project.videos) { video in
                Button {
                    Haptics.press()
                    actions.play(project, video, "raster-\(video.id)")
                } label: {
                    Color.clear
                        .aspectRatio(video.portrait ? 9 / 16 : 16 / 9, contentMode: .fit)
                        .overlay { RemoteImage(url: video.thumbnail(width: 360)) }
                        .overlay(alignment: .bottomLeading) {
                            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                                .overlay(alignment: .bottomLeading) {
                                    Text(video.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                                        .padding(7)
                                }
                        }
                        .overlay(alignment: .topTrailing) { statusMark(video) }
                        .overlay(alignment: .topLeading) {
                            if video.open > 0 {
                                Text("\(video.open)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                    .frame(minWidth: 20, minHeight: 20).background(Palette.changes, in: Capsule()).padding(6)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .zoomSource("raster-\(video.id)", zoom)
                }
                .buttonStyle(PressStyle(scale: 0.96))
                .accessibilityLabel("\(video.title) abspielen")
                .accessibilityIdentifier("raster-\(video.nr)")
            }
        }
    }

    @ViewBuilder
    private func statusMark(_ video: Video) -> some View {
        Image(systemName: video.status == .approved ? "checkmark" : video.status == .changes ? "pencil" : "circle")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(video.status == .pending ? Color.white.opacity(0.0) : .white)
            .frame(width: 20, height: 20)
            .background(video.status == .approved ? Palette.approved : video.status == .changes ? Palette.changes : Color.black.opacity(0.0), in: Circle())
            .padding(6)
            .opacity(video.status == .pending ? 0 : 1)
    }
}

// MARK: - Seite eines Kunden

/// Ein Kunde mit allen Links (aus Regal „Alle“, aus einem Kunden Ordner): Kopf mit Zahlen, Neuer Link für ihn, Bearbeiten
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
                let list = store.projects(of: customer).filter { store.filter.matches($0) }
                let all = store.projects(of: customer)
                let videos = all.flatMap(\.videos)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
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
                        .padding(.top, 4)
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
                        FilterChips().padding(.top, 18)
                        VStack(spacing: 14) {
                            if list.isEmpty { StartEmpty() }
                            ForEach(list) { project in
                                LinkCard(project: project, open: { path.append(.project(project.key)) }, delete: { deleting = project })
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        MadeByStagecraft().padding(.top, 30)
                    }
                    .padding(.bottom, 40)
                }
                .scrollEdgeEffectStyle(.soft, for: .all)
                .refreshable { await store.refresh(quiet: false) }
                .sheet(isPresented: $editing) { CustomerEditSheet(customer: customer) }
            } else {
                Text("Diesen Kunden gibt es nicht mehr.").font(.system(size: 15)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $newLink) { start in NewLinkSheet(start: start, path: $path) }
        .confirmationDialog("Link löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Link löschen", role: .destructive) {
                guard let project = deleting else { return }
                Haptics.cancel()
                Task { await store.deleteLink(project) }
            }
        } message: { Text(DeleteText.link(deleting)) }
    }
}
