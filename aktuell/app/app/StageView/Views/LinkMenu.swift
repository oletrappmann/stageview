import SwiftUI

/// Wie lange der Text beim Löschen eines Links ist (gleich wie im Dashboard)
enum DeleteText {
    static func link(_ project: Project?) -> String {
        guard let project else { return "" }
        return "„\(project.title)“ ist danach für alle weg, auch für den Kunden: \(project.shortLink) zeigt nur noch eine Fehlerseite. "
            + "Videos im Drive und bei Mux und alle Kommentare bleiben gespeichert, zurückholen kann TESS."
    }
}

/// Alles, was man mit einem Link machen kann (langes Drücken auf die Karte, Menü auf der Projektseite)
struct LinkMenuItems: View {
    let project: Project
    var open: (() -> Void)?
    /// Kundenansicht wie im Web, sonst spielt „Ansehen“ das erste Video
    var client: (() -> Void)?
    let delete: () -> Void
    @State private var store = Store.shared

    var body: some View {
        if let client, project.code != nil {
            Button(action: client) { Label("Projekt anzeigen", systemImage: "rectangle.grid.2x2") }
        } else if let first = project.videos.first {
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
                // Drive abgleichen (Ole, 22.11.2026): neue Videos aus dem Ordner holen
                Button { Task { await store.syncDrive(project) } } label: {
                    Label("Drive abgleichen", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.isSyncingDrive(project))
            }
            Section {
                Button(role: .destructive, action: delete) { Label("Link löschen", systemImage: "trash") }
            }
        }
    }
}

/// Freigabe per langem Drücken auf ein Video, ohne erst den Player zu öffnen (Review 22.11.2026)
struct StatusMenuItems: View {
    let project: Project
    let video: Video

    var body: some View {
        if let code = project.code {
            let review = ReviewStore.of(code)
            let current = review.status(of: video)
            Section("Freigabe") {
                ForEach(ReviewStatus.allCases) { option in
                    Button {
                        option == .approved ? Haptics.check() : Haptics.select()
                        Task { await review.setStatus(option, for: video) }
                    } label: { Label(option.title, systemImage: option == current ? "checkmark" : option.symbol) }
                }
            }
        }
    }
}

extension Array where Element == Route {
    /// Zur Kundenansicht bzw. Verwaltung eines Links wechseln. Liegt das Gegenstück direkt davor, geht es zurück statt immer
    /// tiefer (Review 22.11.2026: Kundenansicht und Verwaltung stapelten sich endlos)
    mutating func switchTo(_ route: Route) {
        if count >= 2, self[count - 2] == route { removeLast() } else { append(route) }
    }
}
