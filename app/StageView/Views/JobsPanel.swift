import SwiftUI

/// Meldungen oben auf der Startseite (laufende Aufträge mit Fortschritt, fertige mit dem neuen Link, Fehler mit Grund), wie die
/// Mitteilungen von iOS (Ole, 22.11.2026: aus drei Entwürfen Nummer 2 gewählt). Glas Karten mit App Symbol, Titel, Zeit rechts und
/// einem Satz. Mehrere liegen als Stapel übereinander, Tipp fächert sie auf, oben „Weniger anzeigen“ und × für alle fertigen.
/// Aufgefächert höchstens 5, „Mehr anzeigen“ holt jeweils 5 weitere (Ole). Nach links wischen zeigt „Löschen“, ganz durchwischen
/// löscht sofort. Tipp auf eine Karte öffnet den Link. Laufende lassen sich nicht wegwischen.
struct JobsPanel: View {
    @Binding var path: [Route]
    @State private var store = Store.shared
    @State private var expanded = false
    @State private var limit = JobsPanel.page
    @Namespace private var stack

    private static let page = 5

    var body: some View {
        let jobs = store.visibleJobs
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if jobs.count > 1 && expanded {
                    header(jobs)
                }
                if jobs.count == 1 || expanded {
                    ForEach(jobs.prefix(limit)) { job in
                        SwipeAway(enabled: !job.running, dismiss: { store.dismiss(job) }) {
                            NotificationCard(job: job)
                                .onTapGesture { openJob(job) }
                        }
                        .matchedGeometryEffect(id: job.id, in: stack)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if expanded && jobs.count > limit {
                        more(left: jobs.count - limit)
                    }
                } else {
                    pile(jobs)
                }
            }
            .onChange(of: jobs.count) { _, n in
                if n <= 1 { expanded = false; limit = Self.page }
            }
        }
    }

    private func header(_ jobs: [Job]) -> some View {
        HStack(spacing: 8) {
            Text("Meldungen").font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
            Spacer()
            Button {
                Haptics.select()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    expanded = false
                    limit = Self.page
                }
            } label: {
                Text("Weniger anzeigen").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.text)
                    .padding(.horizontal, 12).frame(height: 32)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            .accessibilityIdentifier("ios-weniger")
            if jobs.contains(where: { !$0.running }) {
                Button {
                    Haptics.select()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                        store.dismissFinishedJobs()
                        expanded = false
                        limit = Self.page
                    }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.text)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("Alle fertigen ausblenden")
                .accessibilityIdentifier("alle-gelesen")
            }
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
    }

    /// „Mehr anzeigen“ unter der fünften Karte, jedes Mal 5 weitere
    private func more(left: Int) -> some View {
        Button {
            Haptics.select()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { limit += Self.page }
        } label: {
            HStack(spacing: 6) {
                Text("Mehr anzeigen").font(.system(size: 14, weight: .semibold))
                Text("\(left)").font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.muted)
            }
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 16)
            .frame(height: 36)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .transition(.opacity)
        .accessibilityLabel("Mehr anzeigen, noch \(left)")
        .accessibilityIdentifier("ios-mehr")
    }

    /// Stapel: vorne die neueste, dahinter bis zu zwei angedeutet (gleich groß wie die vordere, nach unten versetzt)
    private func pile(_ jobs: [Job]) -> some View {
        let behind = min(jobs.count, 3) - 1
        return NotificationCard(job: jobs[0])
            .background(alignment: .bottom) {
                ForEach((1...max(behind, 1)).reversed(), id: \.self) { i in
                    if i <= behind {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(i == 1 ? 0.10 : 0.06))
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .scaleEffect(x: 1 - CGFloat(i) * 0.05, y: 1, anchor: .bottom)
                            .offset(y: CGFloat(i) * 10)
                    }
                }
            }
            .matchedGeometryEffect(id: jobs[0].id, in: stack)
            .padding(.bottom, CGFloat(behind) * 10)
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.select()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { expanded = true }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("\(jobs.count) Meldungen, Tippen fächert sie auf")
            .accessibilityIdentifier("ios-stapel")
    }

    private func openJob(_ job: Job) {
        let code = job.link?.pathComponents.last ?? job.code
        guard let code, let project = store.project(code: code) else { return }
        Haptics.select()
        path.append(.project(project.key))
    }
}

extension Job {
    /// Ein Satz wie in einer Mitteilung: Fortschritt, Ergebnis oder Fehler
    var sentence: String {
        if running { return readable }
        if !ok { return "Hat nicht geklappt: " + (error ?? "unbekannter Fehler") }
        switch kind {
        case "neu": return "Der Link ist online" + (link.map { ": " + $0.absoluteString.replacingOccurrences(of: "https://", with: "") } ?? ".")
        case "dazu": return "Die neuen Videos sind auf der Seite."
        case "drive": return readable
        default: return "Fertig."
        }
    }

    var tint: Color { running ? Palette.accent : ok ? Palette.approvedInk : Palette.changesInk }
    var stateSymbol: String { ok ? "checkmark" : "exclamationmark" }
    var when: String { When.ago(start).replacingOccurrences(of: "gerade eben", with: "jetzt") }
}

private struct NotificationCard: View {
    let job: Job

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            StageViewMark(size: 38)
                .overlay(alignment: .bottomTrailing) {
                    if !job.running {
                        Image(systemName: job.stateSymbol)
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(job.tint, in: Circle())
                            .overlay(Circle().strokeBorder(Palette.field, lineWidth: 1.5))
                            .offset(x: 4, y: 4)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(job.kindTitle): \(job.title)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(job.when).font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                Text(job.sentence)
                    .font(.system(size: 15))
                    .foregroundStyle(job.ok || job.running ? Palette.text.opacity(0.86) : Palette.changesInk)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if job.running {
                    ProgressView(value: Double(job.percent ?? 8), total: 100)
                        .tint(Palette.accent)
                        .padding(.top, 5)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Nach links wischen wie bei iOS: zeigt „Löschen“ als Glas Knopf, ganz durchwischen löscht sofort. Gebaut als kleine
/// waagerechte Scrollfläche in der Karte, so gewinnt die Karte gegen das Blättern der Startseite (ein DragGesture verlor dort)
private struct SwipeAway<Content: View>: View {
    var enabled: Bool
    let dismiss: () -> Void
    @ViewBuilder let content: Content
    @State private var offset: CGFloat = 0
    @State private var pulled: CGFloat = 0
    @State private var gone = false
    private let button: CGFloat = 96

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                content
                    .containerRelativeFrame(.horizontal)
                Button(action: remove) {
                    Text("Löschen").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                        .frame(width: button, height: 52)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())
                .opacity(min(1, Double(offset / 50)))
                .scaleEffect(0.85 + 0.15 * min(1, offset / button))
                .accessibilityIdentifier("ios-loeschen")
            }
        }
        .scrollTargetBehavior(RevealSnap(width: button + 8, fling: { DispatchQueue.main.async { remove() } }))
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .scrollDisabled(!enabled)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, x in
            offset = x
            pulled = max(pulled, x)
        }
        .onScrollPhaseChange { _, phase in
            // Ganz durchgewischt (weit über den Knopf hinaus gezogen): sofort löschen wie bei iOS
            if phase == .decelerating || phase == .idle {
                if pulled > button + 50 { remove() }
                pulled = 0
            }
        }
        .offset(x: gone ? -500 : 0)
        .opacity(gone ? 0 : 1)
    }

    private func remove() {
        guard !gone else { return }
        Haptics.select()
        withAnimation(.easeIn(duration: 0.22)) { gone = true }
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { dismiss() }
        }
    }
}

/// Rastet nur offen (Löschen sichtbar) oder zu ein, je nachdem, wohin der Schwung trägt
private struct RevealSnap: ScrollTargetBehavior {
    let width: CGFloat
    /// Schneller langer Wisch (der Schwung trüge weit über den Knopf hinaus): löschen wie bei iOS
    var fling: () -> Void = {}
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let projected = target.rect.origin.x
        if projected > width + 150, context.velocity.dx > 0 { fling() }
        target.rect.origin.x = projected > width * 0.45 ? width : 0
    }
}
