import SwiftUI

/// Oben auf der Seite Links: Widgets und kleine Berichte (Ole, 22.11.2026: „noch mehr Vorschläge, oben irgendwelche Widgets,
/// irgendwelche Berichte“). Entwürfe, bis Ole wählt (Testbuild: SV_WIDGET = zahlen, woche, zutun, stapel). Der Entwurf „Freigabe“
/// ist seit 22.11.2026 raus (Ole: keine Zahl, wie viele Videos freigegeben sind).
/// Ohne Wahl steht oben nichts, so wie abgenommen.
enum WidgetStyle: String {
    case keine, zahlen, woche, zutun, stapel

    static var current: WidgetStyle {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["SV_WIDGET"], let style = WidgetStyle(rawValue: value) { return style }
        #endif
        return .keine
    }
}

extension Store {
    private static let berlin: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "de_DE")
        c.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        c.firstWeekday = 2
        return c
    }()

    /// Montag bis Sonntag der laufenden Woche
    var weekDays: [Date] {
        let c = Self.berlin
        guard let start = c.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<7).compactMap { c.date(byAdding: .day, value: $0, to: start) }
    }

    /// Links, die diese Woche angelegt wurden
    var weekProjects: [Project] {
        let c = Self.berlin
        return projects.filter { p in When.date(p.created).map { c.isDate($0, equalTo: .now, toGranularity: .weekOfYear) } ?? false }
    }

    /// Neue Links pro Tag der laufenden Woche (Mo bis So)
    var linksPerDay: [Int] {
        let c = Self.berlin
        let days = weekDays
        return days.map { day in projects.filter { p in When.date(p.created).map { c.isDate($0, inSameDayAs: day) } ?? false }.count }
    }

    /// Offene Kommentare, die diese Woche geschrieben wurden
    var weekOpenComments: Int {
        let c = Self.berlin
        return projects.flatMap(\.openComments).filter { k in When.date(k.created).map { c.isDate($0, equalTo: .now, toGranularity: .weekOfYear) } ?? false }.count
    }

    /// Links, bei denen etwas auf das Team wartet: offene Kommentare oder Änderung gewünscht, die meisten zuerst
    var waiting: [Project] {
        projects.filter { $0.openCount > 0 || $0.changes > 0 }
            .sorted { ($0.openCount + $0.changes * 3, $0.lastActivity ?? "") > ($1.openCount + $1.changes * 3, $1.lastActivity ?? "") }
    }
}

/// Widget Bereich über den Links, je nach Entwurf
struct StartWidgets: View {
    let actions: StartActions
    let go: (StartSection) -> Void
    @State private var store = Store.shared

    var body: some View {
        switch WidgetStyle.current {
        case .keine: EmptyView()
        case .zahlen: NumbersWidget(go: go).padding(.horizontal, 16).padding(.bottom, 14)
        case .woche: WeekWidget().padding(.horizontal, 16).padding(.bottom, 14)
        case .zutun: WaitingWidget(actions: actions, go: go).padding(.horizontal, 16).padding(.bottom, 14)
        case .stapel: WidgetStack(actions: actions, go: go).padding(.bottom, 10)
        }
    }
}

/// Fläche eines Widgets: wie die Karten der Links, etwas mehr Luft
private struct WidgetCard<Content: View>: View {
    var height: CGFloat?
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .background(Palette.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.line.opacity(0.6), lineWidth: 0.5))
    }
}

private struct WidgetTitle: View {
    let title: String
    var detail: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
            Spacer()
            if let detail { Text(detail).font(.system(size: 12.5)).foregroundStyle(Palette.muted) }
        }
    }
}

// MARK: 1 Zahlen

/// Eine schmale Leiste mit vier Zahlen, jede antippbar (Offen führt zu den Kommentaren, die anderen filtern die Links)
struct NumbersWidget: View {
    let go: (StartSection) -> Void
    @State private var store = Store.shared

    var body: some View {
        let t = store.totals
        // Ohne Freigabe Zahlen (Ole, 22.11.2026): offene Kommentare, Links ohne Feedback, neue Links der Woche, Videos
        let silent = store.projects.filter { !$0.videos.isEmpty && $0.feedbackTotal == 0 }.count
        HStack(spacing: 0) {
            cell(t.openComments, "Offen", Palette.changes) { go(.kommentare) }
            divider
            cell(silent, "Ohne Feedback", Palette.faint) {}
            divider
            cell(store.weekProjects.count, "Neu diese Woche", Palette.accent) {}
            divider
            cell(t.videos, "Videos", Palette.forestLight) {}
        }
        .padding(.vertical, 12)
        .background(Palette.field, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.line.opacity(0.6), lineWidth: 0.5))
        .accessibilityIdentifier("widget-zahlen")
    }

    private var divider: some View { Rectangle().fill(Palette.line).frame(width: 1, height: 34) }

    private func cell(_ value: Int, _ title: String, _ color: Color, _ run: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            withAnimation(.easeOut(duration: 0.2)) { run() }
        } label: {
            VStack(spacing: 3) {
                Text("\(value)").font(.system(size: 22, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.text)
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.95))
        .accessibilityLabel("\(value) \(title)")
    }
}

// MARK: 2 Wochenbericht

/// Diese Woche: neue Links, Videos, neue offene Kommentare und neue Links pro Tag als kleine Balken (eine Reihe, ohne Legende,
/// nur der höchste Wert steht dran)
struct WeekWidget: View {
    var compact = false
    @State private var store = Store.shared

    var body: some View {
        let links = store.weekProjects
        let videos = links.reduce(0) { $0 + $1.videos.count }
        let perDay = store.linksPerDay
        WidgetCard(height: compact ? 182 : nil) {
            WidgetTitle(title: "Diese Woche", detail: range)
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                figure(links.count, links.count == 1 ? "neuer Link" : "neue Links")
                figure(videos, videos == 1 ? "Video" : "Videos")
                figure(store.weekOpenComments, "neue Kommentare")
            }
            .padding(.top, 10)
            DayBars(values: perDay, days: store.weekDays)
                .frame(height: compact ? 58 : 70)
                .padding(.top, 14)
        }
        .accessibilityIdentifier("widget-woche")
    }

    private var range: String {
        let days = store.weekDays
        guard let first = days.first, let last = days.last else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d."
        let g = DateFormatter()
        g.locale = Locale(identifier: "de_DE")
        g.dateFormat = "d. MMM"
        return "\(f.string(from: first)) bis \(g.string(from: last))"
    }

    private func figure(_ value: Int, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)").font(.system(size: 26, weight: .semibold).monospacedDigit()).tracking(-0.5).foregroundStyle(Palette.text)
            Text(title).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1)
        }
    }
}

/// Neue Links pro Tag: dünne Balken mit runder Kante oben, auf der Grundlinie, leise Tageskürzel, heute hervorgehoben
struct DayBars: View {
    let values: [Int]
    let days: [Date]
    private static let letters = ["M", "D", "M", "D", "F", "S", "S"]
    private static let names = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        let today = days.firstIndex { Calendar.current.isDateInToday($0) }
        let peak = values.firstIndex(of: values.max() ?? 0)
        GeometryReader { g in
            let barArea = g.size.height - 18
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(values.indices, id: \.self) { i in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        if i == peak, values[i] > 0 {
                            Text("\(values[i])").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.muted)
                        }
                        UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
                            .fill(values[i] == 0 ? Palette.line : (i == today ? Palette.accent : Palette.forestLight))
                            .frame(width: 14, height: values[i] == 0 ? 2 : max(4, barArea * 0.82 * CGFloat(values[i]) / CGFloat(top)))
                        Text(Self.letters[i % 7])
                            .font(.system(size: 11, weight: i == today ? .bold : .medium))
                            .foregroundStyle(i == today ? Palette.text : Palette.faint)
                            .frame(height: 14)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Neue Links pro Tag")
        .accessibilityValue(values.indices.map { "\(Self.names[$0 % 7]) \(values[$0])" }.joined(separator: ", "))
    }
}

// MARK: 3 Wartet auf euch

/// Links, bei denen etwas wartet: offene Kommentare oder Änderung gewünscht, höchstens drei, darunter „Alle Kommentare“
struct WaitingWidget: View {
    let actions: StartActions
    let go: (StartSection) -> Void
    var compact = false
    @State private var store = Store.shared

    var body: some View {
        let list = Array(store.waiting.prefix(compact ? 2 : 3))
        WidgetCard(height: compact ? 182 : nil) {
            WidgetTitle(title: "Wartet auf euch", detail: store.waiting.isEmpty ? nil : Plural.count(store.waiting.count, "Link", "Links"))
            if list.isEmpty {
                Text("Gerade wartet nichts. Alle Kommentare sind erledigt.")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted).padding(.top, 10)
            }
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, project in
                    Button {
                        Haptics.select()
                        actions.open(project)
                    } label: {
                        HStack(spacing: 12) {
                            CustomerAvatar(name: project.customerName, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(project.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                                Text(reason(project)).font(.system(size: 12.5)).foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if project.openCount > 0 { OpenBadge(count: project.openCount) }
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.faint)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                    .overlay(alignment: .top) { if index > 0 { Rectangle().fill(Palette.line).frame(height: 0.5).padding(.leading, 44) } }
                }
            }
            .padding(.top, 6)
            if !compact && !list.isEmpty {
                Button {
                    Haptics.select()
                    go(.kommentare)
                } label: {
                    HStack(spacing: 4) {
                        Text("Alle offenen Kommentare").font(.system(size: 14, weight: .semibold))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Palette.accent)
                    .padding(.top, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("widget-zutun")
    }

    private func reason(_ p: Project) -> String {
        [p.openCount > 0 ? Plural.count(p.openCount, "offener Kommentar", "offene Kommentare") : "",
         p.changes > 0 ? (p.changes == 1 ? "1 Änderung gewünscht" : "\(p.changes) Änderungen gewünscht") : "",
         p.customerName].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: 5 Stapel

/// Die Widgets als Stapel zum seitlichen Wischen wie auf dem Home Bildschirm, Punkte darunter
struct WidgetStack: View {
    let actions: StartActions
    let go: (StartSection) -> Void
    @State private var page = 0

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $page) {
                WeekWidget(compact: true).padding(.horizontal, 16).tag(0)
                WaitingWidget(actions: actions, go: go, compact: true).padding(.horizontal, 16).tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 182)
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { i in
                    Capsule().fill(i == page ? Palette.text : Palette.faint)
                        .frame(width: i == page ? 16 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
        }
        .onChange(of: page) { _, _ in Haptics.select() }
        .accessibilityIdentifier("widget-stapel")
    }
}
