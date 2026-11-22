#if DEBUG
import SwiftUI

/// Vorführung ohne Anmeldung und ohne Server (nur Testbuilds). Daten aus SV_DEMO_DATEI (scripts/demo_daten.py, echter Stand der
/// öffentlichen Videoseiten), sonst ein kleines Beispiel. SV_DEMO wählt den Startpunkt:
///   liste, anmeldung, kunde:<id>, filter:<kommentare|aenderung|fertig>, suche:<text>, projekt:<code>, bearbeiten:<code>,
///   player:<code>:<nr>[:<sekunde>], neu, neu-lauf, kunden, meldungen
/// Schreiben bleibt lokal, nichts geht an den Server.
enum Demo {
    static let mode = ProcessInfo.processInfo.environment["SV_DEMO"]
    static var isOn: Bool { mode != nil }
    static var showsLogin: Bool { mode == "anmeldung" }

    private struct File: Decodable {
        var uebersicht: Overview
        var kommentare: [String: ReviewState]
    }

    private static let file: File? = {
        guard let path = ProcessInfo.processInfo.environment["SV_DEMO_DATEI"], let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }()

    static let overview: Overview = {
        var o = file?.uebersicht ?? sample
        if mode == "meldungen" { o.jobs = sampleJobs }
        return o
    }()

    static func review(_ code: String) -> ReviewState { file?.kommentare[code] ?? ReviewState() }

    private static var parts: [String] { (mode ?? "").split(separator: ":").map(String.init) }

    /// Startpunkt anwenden (MainView beim Erscheinen)
    @MainActor
    static func start() {
        let store = Store.shared
        switch parts.first {
        case "kunde": store.customerID = parts.dropFirst().first
        case "filter": store.filter = LinkFilter(rawValue: parts.dropFirst().first ?? "") ?? .all
        case "suche": store.search = parts.dropFirst().joined(separator: ":")
        case "player":
            guard parts.count >= 3, let project = store.project(code: parts[1]),
                  let video = project.videos.first(where: { $0.nr == Int(parts[2]) }) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                store.play(project, video, at: parts.count > 3 ? Double(parts[3]) : nil, source: nil)
            }
        default: break
        }
    }

    /// Seite, auf der die App starten soll
    @MainActor
    static var initialPath: [Route] {
        guard ["projekt", "bearbeiten"].contains(parts.first ?? ""), parts.count > 1, let project = Store.shared.project(code: parts[1]) else { return [] }
        return [.project(project.key)]
    }

    static var opensEditor: Bool { parts.first == "bearbeiten" }
    static var sheet: String? { ["neu", "neu-lauf", "kunden"].contains(parts.first ?? "") ? parts.first : nil }

    // MARK: Aufträge zum Vorführen

    private static func job(_ json: String) -> Job { try! JSONDecoder().decode(Job.self, from: Data(json.utf8)) }

    static func prepJob(ready: Int) -> Job {
        job("""
        {"id":"demo","art":"vorbereiten","titel":"Vorbereiten","laeuft":true,"ok":false,"zuletzt":"warte auf Mux",
         "stand":{"phase":"mux","name":"Content Day Dezember","unterordner":3,
           "videos":[{"drive":"a","titel":"01 Hook Penthouse.mp4"},{"drive":"b","titel":"02 Grundriss erklärt.mp4"},
                     {"drive":"c","titel":"03 Dachterrasse.mp4"},{"drive":"d","titel":"04 Fazit.mp4"}],
           "stand":{"a":{"status":"ready","prozent":100},"b":{"status":"preparing","prozent":64},
                    "c":{"status":"preparing","prozent":38},"d":{"status":"preparing","prozent":12}}}}
        """)
    }

    static func linkJob() -> Job {
        job(#"{"id":"demo-neu","art":"neu","titel":"Content Day Dezember","laeuft":false,"ok":true,"zuletzt":"Link: https://videos.stagecraft.media/uuwvte","link":"https://videos.stagecraft.media/uuwvte","stand":{}}"#)
    }

    private static var sampleJobs: [Job] {
        let now = ISO8601DateFormatter().string(from: .now)
        return [
            job(#"{"id":"j1","art":"dazu","titel":"Penthouse an der Spree · Schnitt 2","code":"zskz92","start":"\#(now)","laeuft":true,"ok":false,"zuletzt":"warte auf Mux: 01.mp4 72 %, 02.mp4 41 %","stand":{}}"#),
            job(#"{"id":"j2","art":"neu","titel":"Content Day Dezember","start":"\#(now)","laeuft":false,"ok":true,"zuletzt":"fertig","link":"https://videos.stagecraft.media/uuwvte","stand":{}}"#),
            job(#"{"id":"j3","art":"dazu","titel":"Vlog KW48","start":"\#(now)","laeuft":false,"ok":false,"zuletzt":"FEHLER: Kein Zugriff auf den Drive Ordner","fehler":"Kein Zugriff auf den Drive Ordner","stand":{}}"#),
        ]
    }

    // MARK: Kleines Beispiel ohne Datei (Testlink Formate Test)

    private static let sample: Overview = {
        let videos = [
            Video(nr: 1, id: "19V2PLvG2fJaEkMqAula-Ph1Rxmo17Yd0", title: "Kanal Trailer (9:16)", playbackID: "fm8tS01lgF6ZXYhMQsMLuR1FQrtDmKrXiavF00axWo8Hk",
                  duration: 90, aspect: 0.5625, status: .approved),
            Video(nr: 3, id: "1RA1JY-u7Z41w17g2BDKNXwMYz0G2RZ9B", title: "Web Exposé (9:16)", playbackID: "WDibrsH5M475E8VDyLIxttNsR1izt3wHPWBz7KunwuQ",
                  duration: 27, aspect: 0.5625, status: .changes, open: 1, comments: 1),
            Video(nr: 2, id: "1w1r59QGcO5Uy1ce3FOW7AcbNfX46LK2h", title: "Babyboomer (16:9)", playbackID: "rt7v3eUfSXUFx9fNuOBKxbfGKNMDuAndfDEVj8kCB02Y",
                  duration: 614, aspect: 16 / 9),
        ]
        let project = Project(key: "stagecraft-test-gemischt", code: "uuwvte", title: "Formate Test", customer: "Stagecraft", company: "Testprojekt",
                              videos: videos, lastActivity: ISO8601DateFormatter().string(from: .now.addingTimeInterval(-3600)), created: "2026-11-13")
        return Overview(projects: [project], customers: [Customer(id: "stagecraft", name: "Stagecraft", links: 1)], jobs: [],
                        me: Me(zugang: "tess", name: "Ole"))
    }()
}
#endif
