import SwiftUI

// Listen der Startseite (Runde 3, 22.11.2026): Links kompakt wie in Konzept 2 „Eingang“, die neuesten oben und nach Tagen
// gruppiert, dazu offene Kommentare und Kunden als eigene Listen für Tabs und Kurzwege. Keine großen Kacheln.

extension Store {
    /// Sichtbare Links (Ansicht, Kunde, Suche), zuletzt angelegte zuerst. Am selben Tag bleibt die letzte Aktivität vorne.
    var newestProjects: [Project] { visibleProjects.sorted { ($0.created ?? "") > ($1.created ?? "") } }

    /// Kunden mit mindestens einem Link, der mit dem neuesten Link zuerst
    var customersWithLinks: [(customer: Customer, projects: [Project])] {
        customers.compactMap { c -> (Customer, [Project])? in
            let list = projects.filter { c.owns($0) }.sorted { ($0.created ?? "") > ($1.created ?? "") }
            return list.isEmpty ? nil : (c, list)
        }
        .sorted { ($0.1.first?.created ?? "") > ($1.1.first?.created ?? "") }
    }

    /// Alle offenen Kommentare, neueste zuerst
    var allOpenComments: [(project: Project, comment: OpenComment)] { latestComments(500) }

    /// „12 Links · 48 Videos · 30 von 48 freigegeben“ für eine beliebige Liste
    func summary(of list: [Project]) -> String {
        let videos = list.flatMap(\.videos)
        let approved = videos.filter { $0.status == .approved }.count
        return [Plural.count(list.count, "Link", "Links"), Plural.count(videos.count, "Video", "Videos"),
                videos.isEmpty ? "" : "\(approved) von \(videos.count) freigegeben"].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

extension LinkFilter {
    /// Ausgeschrieben für Menü und Seitentitel
    var longLabel: String {
        switch self {
        case .all: "Alle Links"
        case .comments: "Offene Kommentare"
        case .changes: "Änderung gewünscht"
        case .done: "Freigegeben"
        }
    }
}

/// Gruppen nach dem Tag, an dem der Link angelegt wurde: Heute, Gestern, Diese Woche, Letzte Woche, dann Monate
enum LinkAge {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "de_DE")
        c.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        c.firstWeekday = 2
        return c
    }()
    private static let month: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.timeZone = calendar.timeZone; f.dateFormat = "LLLL"; return f
    }()
    private static let monthYear: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.timeZone = calendar.timeZone; f.dateFormat = "LLLL yyyy"; return f
    }()

    static func title(_ text: String?, now: Date = .now) -> String {
        guard let date = When.date(text) else { return "Ohne Datum" }
        let c = calendar
        if c.isDate(date, inSameDayAs: now) { return "Heute" }
        if let yesterday = c.date(byAdding: .day, value: -1, to: now), c.isDate(date, inSameDayAs: yesterday) { return "Gestern" }
        if c.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return "Diese Woche" }
        if let last = c.date(byAdding: .weekOfYear, value: -1, to: now), c.isDate(date, equalTo: last, toGranularity: .weekOfYear) { return "Letzte Woche" }
        return c.isDate(date, equalTo: now, toGranularity: .year) ? month.string(from: date) : monthYear.string(from: date)
    }

    static func groups(_ projects: [Project]) -> [(title: String, items: [Project])] {
        let now = Date.now
        var result: [(title: String, items: [Project])] = []
        for project in projects {
            let title = title(project.created, now: now)
            if let i = result.firstIndex(where: { $0.title == title }) { result[i].items.append(project) } else { result.append((title, [project])) }
        }
        return result
    }
}

// MARK: Links

/// Alle Links kompakt, nach Tagen gruppiert, die neuesten oben
struct LinkFeed: View {
    let projects: [Project]
    let actions: StartActions
    var empty: String?

    var body: some View {
        if projects.isEmpty {
            StartEmpty(text: empty)
        } else {
            ForEach(LinkAge.groups(projects), id: \.title) { group in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(group.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("\(group.items.count)").font(.system(size: 14, weight: .medium).monospacedDigit()).foregroundStyle(Palette.faint)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
                StartCard {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, project in
                        StartLinkRow(project: project, actions: actions)
                            .overlay(alignment: .top) { if index > 0 { RowDivider(leading: 84) } }
                    }
                }
            }
        }
    }
}

/// Feld mit runden Ecken für Zeilen (wie Konzept 2)
struct StartCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Palette.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.line.opacity(0.6), lineWidth: 0.5))
            .padding(.horizontal, 16)
    }
}

/// Ein Link als Zeile: Fächer aus drei Standbildern, Titel, Kunde, offene Kommentare, rechts der Ring der Freigabe
struct StartLinkRow: View {
    let project: Project
    let actions: StartActions

    var body: some View {
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
                    if project.videos.isEmpty {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.surface).frame(width: 40, height: 64)
                    }
                }
                .frame(width: 56, height: 70)
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text(project.detail).font(.system(size: 13)).foregroundStyle(Palette.muted).lineLimit(1)
                    if project.openCount > 0 || project.lastActivity != nil {
                        HStack(spacing: 6) {
                            if project.openCount > 0 { OpenBadge(count: project.openCount) }
                            if let last = project.lastActivity { Text(When.ago(last)).font(.system(size: 12)).foregroundStyle(Palette.faint) }
                        }
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

/// Zeile über den Links: links die Zahlen, rechts klein der Filter
struct FeedLine: View {
    @State private var store = Store.shared

    var body: some View {
        HStack(spacing: 8) {
            Text(store.summary).font(.system(size: 13)).foregroundStyle(Palette.muted).lineLimit(1)
            Spacer(minLength: 8)
            FilterMenu()
        }
        .padding(.leading, 22)
        .padding(.trailing, 16)
    }
}

/// Kleiner Glasknopf mit Menü: Ansicht (mit Zahlen) und Kunde
struct FilterMenu: View {
    var customers = true
    /// In der Navigationsleiste: nur das Zeichen, das Glas kommt von der Leiste
    var bare = false
    @State private var store = Store.shared

    var body: some View {
        Menu {
            Picker("Ansicht", selection: $store.filter) {
                ForEach(LinkFilter.allCases, id: \.self) { filter in
                    Text(filter.longLabel).tag(filter)
                }
            }
            if customers {
                Picker("Kunde", selection: $store.customerID) {
                    Text("Alle Kunden").tag(String?.none)
                    ForEach(store.customersWithLinks, id: \.customer.id) { item in
                        Text(item.customer.name).tag(Optional(item.customer.id))
                    }
                }
                .pickerStyle(.menu)
            }
        } label: {
            let active = store.filter != .all || (customers && store.customerID != nil)
            if bare {
                Image(systemName: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
            } else {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 13, weight: .bold))
                Text(label).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(active ? Color.white : Palette.text)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .glassEffect(active ? .regular.tint(Palette.forest).interactive() : .regular.interactive(), in: .capsule)
            }
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.select() })
        .accessibilityIdentifier("filter-menue")
    }

    private var label: String {
        let parts = [store.filter == .all ? nil : store.filter.label,
                     customers ? store.customer.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name } : nil]
            .compactMap { $0 }
        return parts.isEmpty ? "Alle" : parts.joined(separator: " · ")
    }
}

// MARK: Kommentare

/// Alle offenen Kommentare, neueste zuerst. Tipp springt im Player an die Stelle.
struct CommentFeed: View {
    var showsLine = true
    @State private var store = Store.shared

    var body: some View {
        let items = store.allOpenComments
        if showsLine {
            Text(Plural.count(items.count, "offener Kommentar", "offene Kommentare") + " · neueste zuerst")
                .font(.system(size: 13)).foregroundStyle(Palette.muted)
                .padding(.horizontal, 22)
                .frame(height: 34)
        }
        if items.isEmpty {
            StartEmpty(text: "Keine offenen Kommentare")
        } else {
            StartCard {
                ForEach(Array(items.enumerated()), id: \.element.comment.id) { index, item in
                    CommentFeedRow(project: item.project, comment: item.comment)
                        .overlay(alignment: .top) { if index > 0 { RowDivider(leading: 16) } }
                }
            }
            .padding(.top, showsLine ? 6 : 0)
        }
    }
}

private struct CommentFeedRow: View {
    let project: Project
    let comment: OpenComment
    @State private var store = Store.shared

    var body: some View {
        let video = project.videos.first { $0.id == comment.video }
        Button {
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
        .accessibilityIdentifier("kommentar-\(comment.id)")
    }
}

// MARK: Kunden

/// Kunden als Zeilen: Kürzel, Name, Firma und Anzahl Links, darunter der neueste Link. Tipp öffnet die Seite des Kunden.
struct CustomerFeed: View {
    let actions: StartActions
    @State private var store = Store.shared

    var body: some View {
        let items = store.customersWithLinks
        HStack {
            Text("\(Plural.count(items.count, "Kunde", "Kunden")) · neuester Link zuerst").font(.system(size: 13)).foregroundStyle(Palette.muted)
            Spacer()
            Button {
                Haptics.select()
                actions.manageCustomers()
            } label: {
                Text("Verwalten").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                    .padding(.horizontal, 13).frame(height: 34)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("kunden-verwalten")
        }
        .padding(.leading, 22)
        .padding(.trailing, 16)
        StartCard {
            ForEach(Array(items.enumerated()), id: \.element.customer.id) { index, item in
                row(item.customer, item.projects)
                    .overlay(alignment: .top) { if index > 0 { RowDivider(leading: 72) } }
            }
        }
        .padding(.top, 10)
    }

    private func row(_ customer: Customer, _ list: [Project]) -> some View {
        let open = list.reduce(0) { $0 + $1.openCount }
        return Button {
            Haptics.select()
            actions.customer(customer)
        } label: {
            HStack(spacing: 14) {
                CustomerAvatar(name: customer.name, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(customer.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text([customer.company, Plural.count(list.count, "Link", "Links")].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(Palette.muted).lineLimit(1)
                    if let newest = list.first {
                        Text("Neu: \(newest.title) · \(LinkAge.title(newest.created))")
                            .font(.system(size: 12)).foregroundStyle(Palette.faint).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if open > 0 { OpenBadge(count: open) }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .accessibilityIdentifier("kunde-\(customer.id)")
    }
}

// MARK: Tabs (Entwurf B)

/// Umschalter unter dem Kopf: Links, Kommentare (mit Zahl), Kunden. Gewählt grünes Glas, das mitgleitet.
struct StartTabs: View {
    @Binding var section: StartSection
    @State private var store = Store.shared
    @Namespace private var space

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StartSection.allCases) { s in
                let chosen = section == s
                let count = s == .kommentare ? store.totals.openComments : 0
                Button {
                    Haptics.select()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { section = s }
                } label: {
                    HStack(spacing: 5) {
                        Text(s.title).font(.system(size: 14, weight: chosen ? .semibold : .medium)).lineLimit(1)
                        if count > 0 {
                            Text("\(count)").font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(chosen ? Color(UIColor(hex: 0x3A443D)) : .white)
                                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                                .background(chosen ? Color.white : Palette.changes, in: Capsule())
                        }
                    }
                    .fixedSize()
                    .foregroundStyle(chosen ? Color.white : Palette.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background {
                        if chosen { Capsule().fill(Color(UIColor(hex: 0x5F8068))).matchedGeometryEffect(id: "tab", in: space) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab-\(s.rawValue)")
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
    }
}
