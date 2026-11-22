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
