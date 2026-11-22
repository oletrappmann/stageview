import SwiftUI

// Daten genau wie im Admin Dashboard (GET /api/admin/uebersicht, videos_api.py uebersicht()) und auf der Videoseite
// (GET /api/<code>/). Alles nachsichtig gelesen: fehlt ein Feld oder hat es einen anderen Typ, gilt ein Standard, statt dass
// die ganze Übersicht nicht lädt.

extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ key: Key, _ fallback: T) -> T { (try? decodeIfPresent(T.self, forKey: key)) ?? fallback }
    func lenient<T: Decodable>(_ key: Key) -> T? { (try? decodeIfPresent(T.self, forKey: key)) ?? nil }
    /// Zahl, die auch als Text oder Wahrheitswert kommen kann
    func number(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b ? 1 : 0 }
        return nil
    }
}

/// Wer sich anmelden darf: dieselben vier Zugänge wie in der TESS App und im Admin Dashboard (Brücke 127.0.0.1:8651)
enum Access: String, CaseIterable, Identifiable {
    case tess, alfred, caspar, niklas
    var id: String { rawValue }
    var person: String {
        switch self {
        case .tess: "Ole"
        case .alfred: "Jonas"
        case .caspar: "Caspar"
        case .niklas: "Niklas"
        }
    }
}

/// Freigabe eines Videos, gleiche Werte, Texte und Farben wie auf der Videoseite
enum ReviewStatus: String, CaseIterable, Identifiable {
    case pending = "zur-freigabe"
    case changes = "aenderung"
    case approved = "freigegeben"

    var id: String { rawValue }
    init(_ value: String?) { self = ReviewStatus(rawValue: value ?? "") ?? .pending }

    var title: String {
        switch self {
        case .pending: "Zur Freigabe"
        case .changes: "Änderung gewünscht"
        case .approved: "Freigegeben"
        }
    }
    var help: String {
        switch self {
        case .pending: "Noch nicht entschieden"
        case .changes: "Wir passen das Video nach den Kommentaren an"
        case .approved: "Passt so, kann gepostet werden"
        }
    }
    var color: Color {
        switch self {
        case .pending: Palette.pendingInk
        case .changes: Palette.changesInk
        case .approved: Palette.approvedInk
        }
    }
    var symbol: String {
        switch self {
        case .pending: "circle.dashed"
        case .changes: "pencil.circle.fill"
        case .approved: "checkmark.circle.fill"
        }
    }
}

struct Me: Decodable, Equatable {
    var zugang: String
    var name: String
}

struct Overview: Decodable {
    var projects: [Project]
    var customers: [Customer]
    var jobs: [Job]
    var me: Me?

    enum CodingKeys: String, CodingKey { case projekte, kunden, auftraege, ich }

    init(projects: [Project], customers: [Customer], jobs: [Job], me: Me?) {
        self.projects = projects; self.customers = customers; self.jobs = jobs; self.me = me
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projects = c.lenient(.projekte, [Lenient<Project>]()).compactMap(\.value)
        customers = c.lenient(.kunden, [Lenient<Customer>]()).compactMap(\.value)
        jobs = c.lenient(.auftraege, [Lenient<Job>]()).compactMap(\.value)
        me = c.lenient(.ich)
    }
}

/// Ein kaputter Eintrag fällt weg, statt die ganze Liste zu verlieren
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

struct Video: Decodable, Identifiable, Hashable {
    var nr: Int
    var id: String
    var title: String
    var playbackID: String?
    var duration: Double
    var aspect: Double
    var posting: String?
    var format: String?
    var status: ReviewStatus
    var open: Int
    var comments: Int

    enum CodingKeys: String, CodingKey {
        case nr, id, titel, playback_id, dauer, seitenverhaeltnis, posting, format, status, offen, kommentare
    }

    init(nr: Int, id: String, title: String, playbackID: String?, duration: Double, aspect: Double, posting: String? = nil,
         format: String? = nil, status: ReviewStatus = .pending, open: Int = 0, comments: Int = 0) {
        self.nr = nr; self.id = id; self.title = title; self.playbackID = playbackID; self.duration = duration; self.aspect = aspect
        self.posting = posting; self.format = format; self.status = status; self.open = open; self.comments = comments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nr = Int(c.number(.nr) ?? 0)
        id = try c.decode(String.self, forKey: .id)
        title = c.lenient(.titel, "Video")
        playbackID = c.lenient(.playback_id)
        duration = c.number(.dauer) ?? 0
        let ar = c.number(.seitenverhaeltnis) ?? 0.5625
        aspect = ar > 0.1 && ar < 10 ? ar : 0.5625
        posting = c.lenient(.posting)
        format = c.lenient(.format)
        status = ReviewStatus(c.lenient(.status))
        open = Int(c.number(.offen) ?? 0)
        comments = Int(c.number(.kommentare) ?? 0)
    }

    var portrait: Bool { aspect < 1 }
    var hlsURL: URL? { playbackID.flatMap { URL(string: "https://stream.mux.com/\($0).m3u8") } }
    /// Standbild bei 2 s (bei sehr kurzen Videos in der Mitte), wie die Videoseite
    func thumbnail(width: Int, at time: Double? = nil) -> URL? {
        guard let playbackID else { return nil }
        let t = time ?? min(2, max(duration, 0.2) / 2)
        return URL(string: "https://image.mux.com/\(playbackID)/thumbnail.jpg?width=\(width)&time=\(String(format: "%.1f", t))")
    }
    var driveURL: URL? { URL(string: "https://drive.google.com/file/d/\(id)/view") }
}

struct OpenComment: Decodable, Identifiable, Hashable {
    var id: Int
    var video: String
    var time: Double?
    var text: String
    var name: String
    var team: Bool
    var created: String?
    var nr: Int?

    enum CodingKeys: String, CodingKey { case id, video, zeit, text, name, rolle, erstellt, nr }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Int(c.number(.id) ?? 0)
        video = c.lenient(.video, "")
        time = c.number(.zeit)
        text = c.lenient(.text, "")
        name = c.lenient(.name, "")
        team = c.lenient(.rolle, "") == "team"
        created = c.lenient(.erstellt)
        nr = c.number(.nr).map { Int($0) }
    }
}

struct Project: Decodable, Identifiable, Hashable {
    var key: String
    var code: String?
    var link: URL?
    var title: String
    var customer: String
    var customerFolder: String
    var company: String
    var note: String
    var layout: String
    var shootDate: String?
    var created: String?
    var updated: String?
    var lastActivity: String?
    var videos: [Video]
    var waiting: Int
    var openComments: [OpenComment]
    /// Nicht mehr im Drive und deshalb ausgeblendet (seit 22.11.2026, der Server gleicht alle 5 Minuten ab)
    var driveGone: [String] = []
    /// Hinweis vom Drive Abgleich, z.B. wenn alle Videos fehlen und die Seite deshalb bleibt, wie sie ist
    var driveNote: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case schluessel, code, link, titel, kunde, kunde_ordner, firma, hinweis, darstellung, dreh, angelegt, stand, letzte, videos, wartend, kommentare
        case drive_weg, drive_hinweis
    }

    private struct Gone: Decodable { var titel: String? }

    init(key: String, code: String?, title: String, customer: String, company: String = "", videos: [Video], openComments: [OpenComment] = [],
         lastActivity: String? = nil, created: String? = nil, waiting: Int = 0) {
        self.key = key; self.code = code; self.link = code.flatMap { URL(string: "https://videos.stagecraft.media/\($0)") }
        self.title = title; self.customer = customer; self.customerFolder = ""; self.company = company; self.note = ""
        self.layout = "abschnitte"; self.shootDate = nil; self.created = created; self.updated = nil; self.lastActivity = lastActivity
        self.videos = videos; self.waiting = waiting; self.openComments = openComments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .schluessel)
        code = c.lenient(.code)
        link = (c.lenient(.link) as String?).flatMap(URL.init(string:))
        title = c.lenient(.titel, key)
        customer = c.lenient(.kunde, "")
        customerFolder = c.lenient(.kunde_ordner, "")
        company = c.lenient(.firma, "")
        note = c.lenient(.hinweis, "")
        layout = c.lenient(.darstellung, "abschnitte")
        shootDate = c.lenient(.dreh)
        created = c.lenient(.angelegt)
        updated = c.lenient(.stand)
        lastActivity = c.lenient(.letzte)
        videos = c.lenient(.videos, [Lenient<Video>]()).compactMap(\.value)
        waiting = Int(c.number(.wartend) ?? 0)
        openComments = c.lenient(.kommentare, [Lenient<OpenComment>]()).compactMap(\.value)
        driveGone = c.lenient(.drive_weg, [Lenient<Gone>]()).compactMap { $0.value?.titel }.filter { !$0.isEmpty }
        driveNote = c.lenient(.drive_hinweis)
    }

    var customerName: String { customer.isEmpty ? "Ohne Kunde" : customer }
    var approved: Int { videos.filter { $0.status == .approved }.count }
    var changes: Int { videos.filter { $0.status == .changes }.count }
    var openCount: Int { videos.reduce(0) { $0 + $1.open } }
    var allApproved: Bool { !videos.isEmpty && approved == videos.count }
    var allLandscape: Bool { !videos.isEmpty && videos.allSatisfy { !$0.portrait } }
    func videoLink(_ video: Video) -> URL? { link.map { $0.appendingPathComponent("\(video.nr)") } }
    var shortLink: String { code.map { "videos.stagecraft.media/\($0)" } ?? "Noch kein Link" }

    /// Zeile unter dem Titel: Kunde · Firma · 5 Videos
    var detail: String {
        [customerName, company, videos.isEmpty ? (waiting > 0 ? "\(waiting) bei Mux" : "") : Plural.count(videos.count, "Video", "Videos")]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var approvalSummary: String {
        guard !videos.isEmpty else { return waiting > 0 ? "Mux bereitet die Videos vor" : "Noch keine Videos" }
        var parts = [allApproved ? "Alles freigegeben" : "\(approved) von \(videos.count) freigegeben"]
        if changes > 0 { parts.append(Plural.count(changes, "Änderung", "Änderungen")) }
        return parts.joined(separator: " · ")
    }
}

struct Customer: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var company: String
    var source: String
    var links: Int

    enum CodingKeys: String, CodingKey { case id, name, firma, quelle, links }

    init(id: String, name: String, company: String = "", source: String = "stageview", links: Int = 0) {
        self.id = id; self.name = name; self.company = company; self.source = source; self.links = links
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.lenient(.name, id)
        company = c.lenient(.firma, "")
        source = c.lenient(.quelle, "")
        links = Int(c.number(.links) ?? 0)
    }

    /// Wie gehoertZu() im Dashboard: über den Kunden Ordner, sonst über den Namen
    func owns(_ project: Project) -> Bool {
        project.customerFolder == id || (project.customerFolder.isEmpty && project.customer == name)
    }
}

/// Lange Aufträge (neuer Link, Videos dazu, Vorbereiten): Stand aus dem Protokoll von stageview
struct Job: Decodable, Identifiable, Hashable {
    var id: String
    var kind: String
    var title: String
    var code: String?
    var start: String?
    var running: Bool
    var ok: Bool
    var last: String
    var link: URL?
    var error: String?
    var prep: PrepState?

    enum CodingKeys: String, CodingKey { case id, art, titel, code, start, laeuft, ok, zuletzt, link, fehler, stand }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = c.lenient(.art, "")
        title = c.lenient(.titel, "")
        code = c.lenient(.code)
        start = c.lenient(.start)
        running = c.lenient(.laeuft, false)
        ok = c.lenient(.ok, false)
        last = c.lenient(.zuletzt, "")
        link = (c.lenient(.link) as String?).flatMap(URL.init(string:))
        error = c.lenient(.fehler)
        prep = c.lenient(.stand)
    }

    /// Protokollzeilen von stageview lesbar machen (admin.html schoen())
    var readable: String {
        let z = last
        if let range = z.range(of: "warte auf Mux: ") {
            let rest = z[range.upperBound...]
            let values = rest.matches(of: /(\d+) %/).compactMap { Int($0.1) }
            return values.isEmpty ? "Mux bereitet vor" : "Mux bereitet vor: \(values.reduce(0, +) / values.count) %"
        }
        if z.contains("zu Mux") { return "Videos gehen zu Mux" }
        if z.hasPrefix("Link:") { return "Link steht, Mux startet" }
        if z.contains("Mux fertig") { return "Mux fertig, Seite wird gebaut" }
        if z.hasPrefix("Drive geprüft: ") { return String(z.dropFirst("Drive geprüft: ".count)).capitalizedFirst }
        return z.isEmpty ? "startet …" : z
    }

    var kindTitle: String {
        switch kind {
        case "neu": "Neuer Link"
        case "dazu": "Videos dazu"
        case "vorbereiten": "Vorbereiten"
        case "drive": "Drive abgleichen"
        default: "Auftrag"
        }
    }

    /// Fortschritt in Prozent, wenn das Protokoll einen hergibt
    var percent: Int? {
        guard let range = last.range(of: "warte auf Mux: ") else { return nil }
        let values = last[range.upperBound...].matches(of: /(\d+) %/).compactMap { Int($0.1) }
        return values.isEmpty ? nil : values.reduce(0, +) / values.count
    }
}

/// Stand von „stageview vorbereiten“: Phase, gefundene Videos und Mux Fortschritt pro Drive Datei
struct PrepState: Decodable, Hashable {
    struct PrepVideo: Decodable, Hashable { var drive: String; var title: String
        enum CodingKeys: String, CodingKey { case drive, titel }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            drive = c.lenient(.drive, ""); title = c.lenient(.titel, "Video")
        }
    }
    struct MuxState: Decodable, Hashable { var status: String; var percent: Int
        enum CodingKeys: String, CodingKey { case status, prozent }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            status = c.lenient(.status, ""); percent = Int(c.number(.prozent) ?? 0)
        }
    }

    var phase: String?
    var videos: [PrepVideo]
    var mux: [String: MuxState]
    var name: String?
    var subfolders: Int
    var deep: Bool

    enum CodingKeys: String, CodingKey { case phase, videos, stand, name, unterordner, tief }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = c.lenient(.phase)
        videos = c.lenient(.videos, [Lenient<PrepVideo>]()).compactMap(\.value)
        mux = c.lenient(.stand, [String: MuxState]())
        name = c.lenient(.name)
        subfolders = Int(c.number(.unterordner) ?? 0)
        deep = (c.number(.tief) ?? 0) > 0
    }

    var ready: Int { videos.filter { mux[$0.drive]?.status == "ready" }.count }
    var muxPercent: Int {
        guard !videos.isEmpty else { return 0 }
        return videos.reduce(0) { $0 + (mux[$1.drive]?.percent ?? 0) } / videos.count
    }
}

// MARK: Kommentare einer Videoseite

struct Comment: Decodable, Identifiable, Hashable {
    var id: Int
    var video: String
    var time: Double?
    var text: String
    var name: String
    var team: Bool
    var replyTo: Int?
    var done: Bool
    var doneBy: String?
    var created: String?
    var edited: String?
    var canDelete: Bool
    var canEdit: Bool

    enum CodingKeys: String, CodingKey {
        case id, video, zeit, text, name, rolle, antwort_auf, erledigt, erledigt_von, erstellt, bearbeitet, darf_loeschen, darf_bearbeiten
    }

    init(id: Int, video: String, time: Double?, text: String, name: String, team: Bool, replyTo: Int? = nil, done: Bool = false,
         created: String? = nil) {
        self.id = id; self.video = video; self.time = time; self.text = text; self.name = name; self.team = team; self.replyTo = replyTo
        self.done = done; self.doneBy = nil; self.created = created; self.edited = nil; self.canDelete = true; self.canEdit = team
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Int(c.number(.id) ?? 0)
        video = c.lenient(.video, "")
        time = c.number(.zeit)
        text = c.lenient(.text, "")
        name = c.lenient(.name, "")
        team = c.lenient(.rolle, "") == "team"
        replyTo = c.number(.antwort_auf).map { Int($0) }
        done = (c.number(.erledigt) ?? 0) > 0
        doneBy = c.lenient(.erledigt_von)
        created = c.lenient(.erstellt)
        edited = c.lenient(.bearbeitet)
        canDelete = (c.number(.darf_loeschen) ?? 0) > 0
        canEdit = (c.number(.darf_bearbeiten) ?? 0) > 0
    }
}

struct StatusEntry: Decodable, Hashable {
    var value: ReviewStatus
    var by: String?
    var at: String?
    enum CodingKeys: String, CodingKey { case wert, von, am }
    init(value: ReviewStatus, by: String?, at: String?) { self.value = value; self.by = by; self.at = at }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = ReviewStatus(c.lenient(.wert)); by = c.lenient(.von); at = c.lenient(.am)
    }
}

struct ReviewState: Decodable {
    var comments: [Comment]
    var status: [String: StatusEntry]
    var team: Bool
    enum CodingKeys: String, CodingKey { case kommentare, status, team }
    init(comments: [Comment] = [], status: [String: StatusEntry] = [:], team: Bool = true) {
        self.comments = comments; self.status = status; self.team = team
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        comments = c.lenient(.kommentare, [Lenient<Comment>]()).compactMap(\.value)
        status = c.lenient(.status, [String: StatusEntry]())
        team = c.lenient(.team, false)
    }
}

// MARK: Text Hilfen

enum Plural {
    /// „1 Video“, „3 Videos“
    static func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
}

enum Clock {
    /// 1:30, 10:14, 1:02:03
    static func text(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
    }
}

enum When {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let isoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let local: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Europe/Berlin")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Europe/Berlin")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.locale = Locale(identifier: "de_DE"); f.unitsStyle = .full; return f
    }()
    private static let short: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.setLocalizedDateFormatFromTemplate("d. MMM"); return f
    }()

    static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return iso.date(from: text) ?? isoFraction.date(from: text) ?? local.date(from: String(text.prefix(16)))
            ?? day.date(from: String(text.prefix(10)))
    }

    /// „gerade eben“, „vor 5 Minuten“, „vor 3 Stunden“, „gestern“, „vor 4 Tagen“, sonst „12. Nov.“
    static func ago(_ text: String?, now: Date = .now) -> String {
        guard let date = date(text) else { return "" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "gerade eben" }
        if seconds > 6 * 86400 { return short.string(from: date) }
        return relative.localizedString(for: date, relativeTo: now)
    }

    static func dayText(_ text: String?) -> String? {
        guard let date = date(text) else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.setLocalizedDateFormatFromTemplate("EEE d. MMM")
        return f.string(from: date)
    }
}

extension String {
    /// „keine neuen Videos“ → „Keine neuen Videos“
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
