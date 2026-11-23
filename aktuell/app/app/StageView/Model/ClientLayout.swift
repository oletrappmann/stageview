import Foundation

/// Aufbau der Kundenansicht eines Links aus der öffentlichen projekt.json (dieselbe Datei, die videos.stagecraft.media/<code>
/// lädt): Kategorien und ihre Reihenfolge, Kategorie pro Video, Darstellung (abschnitte oder youtube), Hinweis. Videos, Status und
/// Kommentare kommen weiter aus der Übersicht der App bzw. dem ReviewStore.
struct ClientLayout: Decodable, Equatable {
    var groups: [String] = []
    var display: String = "abschnitte"
    var hint: String = ""
    /// Video ID → Kategorie
    var groupOf: [String: String] = [:]

    private enum Keys: String, CodingKey { case gruppen, darstellung, hinweis, videos }
    private struct Entry: Decodable { var id: String; var gruppe: String? }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        groups = (try? c.decodeIfPresent([String].self, forKey: .gruppen)) ?? []
        display = (try? c.decodeIfPresent(String.self, forKey: .darstellung)) ?? "abschnitte"
        hint = (try? c.decodeIfPresent(String.self, forKey: .hinweis)) ?? ""
        let entries = (try? c.decodeIfPresent([Entry].self, forKey: .videos)) ?? []
        groupOf = Dictionary(entries.compactMap { e in e.gruppe.map { (e.id, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    var youtube: Bool { display == "youtube" }
}

/// Lädt und merkt die projekt.json pro Link (öffentlich, ohne Anmeldung)
@MainActor
@Observable
final class ClientLayouts {
    static let shared = ClientLayouts()
    private(set) var layouts: [String: ClientLayout] = [:]

    func layout(_ code: String) -> ClientLayout? { layouts[code] }

    func load(_ code: String) async {
        #if DEBUG
        if Demo.isOn { layouts[code] = Demo.page(code); return }
        #endif
        guard let url = URL(string: "https://videos.stagecraft.media/\(code)/projekt.json") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let layout = try? JSONDecoder().decode(ClientLayout.self, from: data) else { return }
        if layouts[code] != layout { layouts[code] = layout }
    }
}
