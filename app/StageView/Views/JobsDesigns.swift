import SwiftUI

/// Entwürfe für die Meldungen oben auf der Startseite (Ole, 22.11.2026: „ein neues Design für die Benachrichtigungen oben auf der
/// Startseite, drei Designs und eins, was mehr wie iOS Benachrichtigungen aussieht und sich so verhält“).
/// Umschalten zum Vorführen mit SV_MELDUNG, fest später über sv.meldungen.stil. Bis Ole wählt, bleibt „karte“ (bisher).
enum JobsStyle: String, CaseIterable {
    case karte, leiste, ios, karussell

    static var current: JobsStyle {
        let raw = ProcessInfo.processInfo.environment["SV_MELDUNG"] ?? UserDefaults.standard.string(forKey: "sv.meldungen.stil") ?? ""
        return JobsStyle(rawValue: raw) ?? .karte
    }
}

// MARK: Gemeinsame Teile

extension Job {
    /// Zweite Zeile wie bisher in der Liste: Fortschritt, Ergebnis oder Fehler
    var detailText: String {
        if running { return readable }
        if ok, kind == "drive" { return readable }
        if ok { return link.map { "Fertig · " + $0.absoluteString.replacingOccurrences(of: "https://", with: "") } ?? "Fertig" }
        return "Hat nicht geklappt: " + (error ?? "unbekannter Fehler")
    }

    /// Ein Satz für Mitteilungen im Stil von iOS
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
    var stateSymbol: String { running ? "arrow.triangle.2.circlepath" : ok ? "checkmark" : "exclamationmark" }
    var when: String { When.ago(start).replacingOccurrences(of: "gerade eben", with: "jetzt") }
}

@MainActor
private func openJob(_ job: Job, _ path: Binding<[Route]>) {
    let store = Store.shared
    let code = job.link?.pathComponents.last ?? job.code
    guard let code, let project = store.project(code: code) else { return }
    Haptics.select()
    path.wrappedValue.append(.project(project.key))
}

/// Fortschrittsring: mit Prozent gefüllt, ohne Prozent dreht ein Bogen
struct JobRing: View {
    let job: Job
    var size: CGFloat = 24
    var line: CGFloat = 3
    @State private var spin = false

    var body: some View {
        ZStack {
            if job.running {
                Circle().stroke(Palette.accent.opacity(0.18), lineWidth: line)
                if let p = job.percent {
                    Circle().trim(from: 0, to: CGFloat(max(4, p)) / 100)
                        .stroke(Palette.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.4), value: p)
                } else {
                    Circle().trim(from: 0, to: 0.28)
                        .stroke(Palette.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .onAppear { withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true } }
                }
            } else {
                Circle().fill(job.tint.opacity(0.16))
                Image(systemName: job.stateSymbol)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(job.tint)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: Entwurf 1: Leiste

/// Eine schmale Glas Pille: der wichtigste Stand in einer Zeile (laufend vor fertig), Zahl der übrigen. Tipp klappt die Liste auf.
struct JobsPill: View {
    let jobs: [Job]
    @Binding var path: [Route]
    @State private var store = Store.shared
    @State private var open = false

    private var lead: Job { jobs.first(where: \.running) ?? jobs[0] }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                Haptics.select()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { open.toggle() }
            } label: {
                HStack(spacing: 11) {
                    JobRing(job: lead, size: 26, line: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lead.running ? "\(lead.kindTitle) läuft" : "\(lead.kindTitle): \(lead.title)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Text(lead.running ? "\(lead.title) · \(lead.readable)" : lead.detailText)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if jobs.count > 1 {
                        Text("+\(jobs.count - 1)")
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(Palette.text)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(Palette.surface, in: Capsule())
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.faint)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .frame(height: 56)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            .accessibilityIdentifier("meldungen-leiste")
            if open {
                VStack(spacing: 0) {
                    ForEach(Array(jobs.prefix(4).enumerated()), id: \.element.id) { index, job in
                        HStack(spacing: 12) {
                            JobRing(job: job, size: 28, line: 3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(job.kindTitle): \(job.title)").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                                Text(job.detailText).font(.system(size: 12.5)).foregroundStyle(job.ok || job.running ? Palette.muted : Palette.changesInk).lineLimit(2)
                            }
                            Spacer(minLength: 4)
                            if !job.running {
                                Button {
                                    Haptics.select()
                                    withAnimation(.easeOut(duration: 0.25)) { store.dismiss(job) }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.muted)
                                        .frame(width: 30, height: 30).background(Palette.surface, in: Circle())
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityLabel("Ausblenden")
                            }
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                        .onTapGesture { openJob(job, $path) }
                        .overlay(alignment: .top) { if index > 0 { RowDivider(leading: 40) } }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
    }
}

// MARK: Entwurf 2: wie iOS Mitteilungen

/// Wie die Mitteilungen von iOS: Glas Karten mit App Symbol, Titel, Zeit rechts und einem Satz. Mehrere liegen als Stapel
/// übereinander, Tipp fächert sie auf (oben „Weniger anzeigen“ und × für alle fertigen). Nach links wischen zeigt „Löschen“,
/// ganz durchwischen löscht sofort. Tipp auf eine Karte öffnet den Link. Laufende lassen sich nicht wegwischen.
struct JobsNotifications: View {
    let jobs: [Job]
    @Binding var path: [Route]
    @State private var store = Store.shared
    @State private var expanded = false
    @Namespace private var stack

    var body: some View {
        let shown = Array(jobs.prefix(4))
        VStack(alignment: .leading, spacing: 8) {
            if shown.count > 1 && expanded {
                HStack(spacing: 8) {
                    Text("Meldungen").font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
                    Spacer()
                    Button {
                        Haptics.select()
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { expanded = false }
                    } label: {
                        Text("Weniger anzeigen").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.text)
                            .padding(.horizontal, 12).frame(height: 32)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .accessibilityIdentifier("ios-weniger")
                    if shown.contains(where: { !$0.running }) {
                        Button {
                            Haptics.select()
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                store.dismissFinishedJobs()
                                expanded = false
                            }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.text)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .accessibilityLabel("Alle fertigen ausblenden")
                    }
                }
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
            if shown.count == 1 || expanded {
                ForEach(shown) { job in
                    SwipeAway(enabled: !job.running, dismiss: { store.dismiss(job) }) {
                        NotificationCard(job: job)
                            .onTapGesture { openJob(job, $path) }
                    }
                    .matchedGeometryEffect(id: job.id, in: stack)
                }
            } else {
                // Stapel: vorne die neueste, dahinter bis zu zwei angedeutet (gleich groß wie die vordere, nach unten versetzt)
                NotificationCard(job: shown[0])
                    .background(alignment: .bottom) {
                        ForEach((1..<min(shown.count, 3)).reversed(), id: \.self) { i in
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.white.opacity(i == 1 ? 0.10 : 0.06))
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .scaleEffect(x: 1 - CGFloat(i) * 0.05, y: 1, anchor: .bottom)
                                .offset(y: CGFloat(i) * 10)
                        }
                    }
                    .matchedGeometryEffect(id: shown[0].id, in: stack)
                    .padding(.bottom, CGFloat(min(shown.count, 3) - 1) * 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.select()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { expanded = true }
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("\(shown.count) Meldungen, Tippen fächert sie auf")
                .accessibilityIdentifier("ios-stapel")
            }
        }
    }
}

private struct NotificationCard: View {
    let job: Job
    var quiet = false

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
        .opacity(quiet ? 0 : 1)
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

// MARK: Entwurf 3: Karussell

/// Karten nebeneinander zum Durchwischen, wie kleine Widgets: großer Ring oder Haken, Art, Titel, Stand. Tipp öffnet den Link.
struct JobsCarousel: View {
    let jobs: [Job]
    @Binding var path: [Route]
    @State private var store = Store.shared

    var body: some View {
        let shown = Array(jobs.prefix(4))
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(shown) { job in
                    card(job)
                        .containerRelativeFrame(.horizontal) { w, _ in shown.count == 1 ? w : w * 0.78 }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
        .accessibilityIdentifier("meldungen-karussell")
    }

    private func card(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                JobRing(job: job, size: 34, line: 3.5)
                Spacer()
                if !job.running {
                    Button {
                        Haptics.select()
                        withAnimation(.easeOut(duration: 0.25)) { store.dismiss(job) }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.muted)
                            .frame(width: 28, height: 28).background(Palette.surface.opacity(0.8), in: Circle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Ausblenden")
                } else if let p = job.percent {
                    Text("\(p) %").font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.accent)
                }
            }
            Text(job.kindTitle.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(job.tint)
                .padding(.top, 12)
            Text(job.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .padding(.top, 2)
            Text(job.running ? job.readable : job.sentence)
                .font(.system(size: 13))
                .foregroundStyle(job.ok || job.running ? Palette.muted : Palette.changesInk)
                .lineLimit(2, reservesSpace: true)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.field)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [job.tint.opacity(0.22), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.line.opacity(0.6), lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { openJob(job, $path) }
    }
}
