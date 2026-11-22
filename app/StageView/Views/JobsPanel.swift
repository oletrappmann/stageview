import SwiftUI

/// Meldungen oben auf der Startseite wie im Dashboard: laufende Aufträge mit Fortschritt, fertige mit dem neuen Link, Fehler mit
/// Grund. Höchstens vier auf einmal (Ole, 17.11.2026), ab zwei mit Kopf zum Einklappen und „Alle gelesen“.
struct JobsPanel: View {
    @Binding var path: [Route]
    @State private var store = Store.shared

    var body: some View {
        let jobs = store.visibleJobs
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if jobs.count >= 2 {
                    HStack {
                        Button {
                            Haptics.select()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { store.jobsCollapsed.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                                    .rotationEffect(.degrees(store.jobsCollapsed ? -90 : 0))
                                Text("Meldungen").font(.system(size: 15, weight: .semibold))
                                Text("\(jobs.count)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.muted)
                            }
                            .foregroundStyle(Palette.text)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("meldungen-klappen")
                        Spacer()
                        if jobs.contains(where: { !$0.running }) {
                            Button("Alle gelesen") {
                                Haptics.select()
                                withAnimation(.easeOut(duration: 0.25)) { store.dismissFinishedJobs() }
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .accessibilityIdentifier("alle-gelesen")
                        }
                    }
                    .padding(.bottom, store.jobsCollapsed ? 0 : 10)
                }
                if !store.jobsCollapsed || jobs.count < 2 {
                    VStack(spacing: 0) {
                        ForEach(Array(jobs.prefix(4).enumerated()), id: \.element.id) { index, job in
                            JobRow(job: job, path: $path)
                                .padding(.vertical, 10)
                                .overlay(alignment: .top) { if index > 0 { RowDivider(leading: 40) } }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .accessibilityIdentifier("meldungen")
        }
    }
}

private struct JobRow: View {
    let job: Job
    @Binding var path: [Route]
    @State private var store = Store.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if job.running {
                    ProgressView().controlSize(.small)
                } else if job.ok {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.approvedInk)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.changesInk)
                }
            }
            .font(.system(size: 20))
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(job.kindTitle): \(job.title)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(job.running || job.ok ? Palette.muted : Palette.changesInk)
                    .lineLimit(2)
                if job.running, let percent = job.percent {
                    ProgressView(value: Double(percent), total: 100)
                        .tint(Palette.accent)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 4)
            if job.ok, let link = job.link {
                Button {
                    Haptics.select()
                    if let code = link.pathComponents.last, let project = store.project(code: code) {
                        path.append(.project(project.key))
                    } else {
                        UIApplication.shared.open(link)
                    }
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Palette.forest, in: Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Öffnen")
            }
            if !job.running {
                Button {
                    Haptics.select()
                    withAnimation(.easeOut(duration: 0.25)) { store.dismiss(job) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 32, height: 32)
                        .background(Palette.surface, in: Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Ausblenden")
            }
        }
    }

    private var detail: String {
        if job.running { return job.readable }
        if job.ok, job.kind == "drive" { return job.readable }
        if job.ok { return job.link.map { "Fertig · " + $0.absoluteString.replacingOccurrences(of: "https://", with: "") } ?? "Fertig" }
        return "Hat nicht geklappt: " + (job.error ?? "unbekannter Fehler")
    }
}
