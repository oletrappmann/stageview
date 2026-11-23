import SwiftUI

/// Alle Konten für die Anmeldung, aus der Liste von StageHub (Ole, 23.11.2026: „die Login Geschichte synchronisieren mit
/// StageHub, dass immer, wenn ein neues Profil angelegt wird, es auch direkt in StageView drin ist … dass das ein System ist“).
/// Quelle ist die Brücke der TESS App (`/profile`), die App fragt über videos.stagecraft.media (`GET /api/admin/profile`, ohne
/// Anmeldung). Die letzte Liste bleibt auf dem Gerät, so steht die Anmeldung sofort und auch ohne Netz. Ohne jede Liste gelten
/// die vier Konten von vorher.
@MainActor @Observable
final class Profiles {
    static let shared = Profiles()

    private(set) var all: [Access]

    private static let key = "sv.profile"

    static let fallback: [Access] = [
        Access(rawValue: "tess", person: "Ole", role: "admin", order: 0),
        Access(rawValue: "alfred", person: "Jonas", role: "admin", order: 1),
        Access(rawValue: "caspar", person: "Caspar", order: 2),
        Access(rawValue: "niklas", person: "Niklas", order: 3),
    ]

    private init() {
        #if DEBUG
        if Demo.isOn {
            all = Self.demo
            return
        }
        #endif
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Access].self, from: data), !saved.isEmpty {
            all = saved
        } else {
            all = Self.fallback
        }
    }

    /// Frisch vom Server holen. Fehler zählen nicht, dann bleibt die gemerkte Liste.
    func refresh() async {
        #if DEBUG
        if Demo.isOn { return }
        #endif
        struct Answer: Decodable { var profile: [Access] }
        guard let answer = try? await API.get("admin/profile", as: Answer.self) else { return }
        // Reihenfolge wie geliefert, doppelte Zugänge nur einmal
        var seen = Set<String>()
        let list = answer.profile.filter { seen.insert($0.rawValue).inserted }
            .enumerated().map { index, profile in var p = profile; p.order = index; return p }
        guard !list.isEmpty, list != all else { return }
        all = list
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    #if DEBUG
    /// Vorführung: die vier mit festen Bildern, dazu Noah ohne Bild (wie live seit 22.11.2026), mit SV_PROFILE_MEHR=<Anzahl> mehr
    private static var demo: [Access] {
        var list = fallback + [Access(rawValue: "noah", person: "Noah", order: 4)]
        if let extra = ProcessInfo.processInfo.environment["SV_PROFILE_MEHR"].flatMap(Int.init), extra > 0 {
            let names = ["Lena", "Max", "Mia", "Paul", "Emma", "Finn", "Sara", "Tom"]
            list += (0..<extra).map { Access(rawValue: "demo\($0)", person: names[$0 % names.count], order: 5 + $0) }
        }
        return list
    }
    #endif
}
