import Network
import SwiftUI

/// Kurzer Hinweis oben als Glaskapsel (wie TaskNotice in der TESS App)
struct Notice: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var symbol: String = "checkmark.circle.fill"
    var isError = false
}

/// Ansichten wie in der Seitenleiste des Dashboards (ANSICHTEN in admin.html)
enum LinkFilter: String, CaseIterable {
    case all = "alle", comments = "kommentare", changes = "aenderung", done = "fertig"
    var label: String {
        switch self {
        case .all: "Alle"
        case .comments: "Offen"
        case .changes: "Änderung"
        case .done: "Fertig"
        }
    }
    func matches(_ p: Project) -> Bool {
        switch self {
        case .all: true
        case .comments: p.openCount > 0
        case .changes: p.changes > 0
        case .done: p.allApproved
        }
    }
}

enum LinkSort: String, CaseIterable {
    case activity = "aktiv", newest = "neu", name = "name"
    var label: String {
        switch self {
        case .activity: "Letzte Aktivität"
        case .newest: "Zuletzt angelegt"
        case .name: "Name"
        }
    }
    var symbol: String {
        switch self {
        case .activity: "clock"
        case .newest: "sparkles"
        case .name: "textformat"
        }
    }
}

/// Alles, was das Admin Dashboard kann, für die App: Übersicht laden, Filter, Aktionen. Ein Speicher für die ganze App
/// (wie TaskStore in der TESS App).
@MainActor
@Observable
final class Store {
    static let shared = Store()

    var me: Me?
    var signedIn: Bool
    var overview: Overview?
    var loadError: String?
    var notice: Notice?
    /// Offener Player (über allem, wächst aus dem angetippten Vorschaubild)
    var playing: PlayerRequest?

    var filter: LinkFilter { didSet { UserDefaults.standard.set(filter.rawValue, forKey: "sv.ansicht") } }
    var sort: LinkSort { didSet { UserDefaults.standard.set(sort.rawValue, forKey: "sv.sortierung") } }
    var customerID: String?
    var search = ""
    var dismissedJobs: [String] { didSet { UserDefaults.standard.set(Array(dismissedJobs.suffix(200)), forKey: "sv.meldungen.weg") } }
    var jobsCollapsed: Bool { didSet { UserDefaults.standard.set(jobsCollapsed, forKey: "sv.meldungen.zu") } }

    private var poller: Task<Void, Never>?
    private var noticeTimer: Task<Void, Never>?
    private var busyKeys: Set<String> = []

    private init() {
        let d = UserDefaults.standard
        filter = LinkFilter(rawValue: d.string(forKey: "sv.ansicht") ?? "") ?? .all
        sort = LinkSort(rawValue: d.string(forKey: "sv.sortierung") ?? "") ?? .activity
        dismissedJobs = d.stringArray(forKey: "sv.meldungen.weg") ?? []
        jobsCollapsed = d.bool(forKey: "sv.meldungen.zu")
        if let zugang = d.string(forKey: "sv.zugang"), let name = d.string(forKey: "sv.name") { me = Me(zugang: zugang, name: name) }
        signedIn = Keychain.token != nil
        #if DEBUG
        if Demo.isOn { signedIn = !Demo.showsLogin; overview = Demo.overview; me = Demo.overview.me }
        #endif
    }

    // MARK: Anmelden

    func signIn(_ access: Access, password: String) async -> String? {
        #if DEBUG
        if Demo.isOn {
            try? await Task.sleep(for: .milliseconds(500))
            if password != "demo" { return "Passwort falsch." }
            me = Me(zugang: access.rawValue, name: access.person); signedIn = true; overview = Demo.overview
            return nil
        }
        #endif
        do {
            let who = try await API.signIn(access, password: password)
            remember(who)
            signedIn = true
            await refresh()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func signOut() async {
        stopPolling()
        #if DEBUG
        if Demo.isOn { signedIn = false; return }
        #endif
        await API.signOut()
        signedIn = false
        overview = nil
        customerID = nil
    }

    private func remember(_ who: Me) {
        me = who
        UserDefaults.standard.set(who.zugang, forKey: "sv.zugang")
        UserDefaults.standard.set(who.name, forKey: "sv.name")
    }

    // MARK: Laden

    /// Übersicht holen. Ohne gültige Sitzung zurück zur Anmeldung.
    func refresh(quiet: Bool = true) async {
        #if DEBUG
        if Demo.isOn { return }
        #endif
        guard signedIn else { return }
        do {
            let fresh: Overview = try await API.get("admin/uebersicht")
            withAnimation(.easeOut(duration: 0.25)) { overview = fresh }
            if let who = fresh.me, who != me { remember(who) }
            loadError = nil
            if let id = customerID, !fresh.customers.contains(where: { $0.id == id }) { customerID = nil }
        } catch APIError.signedOut {
            Keychain.token = nil
            signedIn = false
            overview = nil
        } catch {
            loadError = error.localizedDescription
            if !quiet { show(error.localizedDescription, error: true) }
        }
    }

    /// Läuft ein Auftrag, alle 4 s nachsehen, sonst alle 30 s (wie das Dashboard), nur solange die App offen ist
    func startPolling() {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let running = self.overview?.jobs.contains(where: \.running) ?? false
                try? await Task.sleep(for: .seconds(running ? 4 : 30))
            }
        }
    }

    func stopPolling() {
        poller?.cancel()
        poller = nil
    }

    // MARK: Ansicht

    var projects: [Project] { overview?.projects ?? [] }
    var customers: [Customer] { overview?.customers ?? [] }
    var customer: Customer? { customerID.flatMap { id in customers.first { $0.id == id } } }

    func project(_ key: String) -> Project? { projects.first { $0.key == key } }
    func project(code: String) -> Project? { projects.first { $0.code == code } }

    /// Kunde und Ansicht filtern zusammen, die Suche geht über Titel, Kunde, Firma und Code
    var visibleProjects: [Project] {
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        let chosen = customer
        let list = projects.filter { p in
            (chosen.map { $0.owns(p) } ?? true) && filter.matches(p)
                && (term.isEmpty || [p.title, p.customer, p.company, p.code ?? "", p.key].contains { $0.lowercased().contains(term) })
        }
        switch sort {
        case .name:
            return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .newest:
            return list.sorted { ($0.created ?? "") > ($1.created ?? "") }
        case .activity:
            return list.sorted {
                let a = $0.lastActivity ?? $0.created ?? "", b = $1.lastActivity ?? $1.created ?? ""
                return a != b ? a > b : $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
    }

    /// Für den Kunden gefilterte Links ohne Ansicht und Suche (Zahlen auf dem Schalter)
    private var customerProjects: [Project] { customer.map { c in projects.filter { c.owns($0) } } ?? projects }

    var filterBadges: [String: Int] {
        let list = customerProjects
        return [LinkFilter.comments.rawValue: list.reduce(0) { $0 + $1.openCount }]
    }

    /// „12 Links · 48 Videos · 30 von 48 freigegeben“
    var summary: String {
        let list = visibleProjects
        let videos = list.flatMap(\.videos)
        let approved = videos.filter { $0.status == .approved }.count
        return [customer?.company ?? "", Plural.count(list.count, "Link", "Links"), Plural.count(videos.count, "Video", "Videos"),
                videos.isEmpty ? "" : "\(approved) von \(videos.count) freigegeben"].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func links(of customer: Customer) -> Int { projects.filter { customer.owns($0) }.count }

    /// Meldungen oben: laufende immer, fertige der letzten 2 Stunden, bis man sie wegtippt
    var visibleJobs: [Job] {
        let limit = Date.now.addingTimeInterval(-2 * 3600)
        return (overview?.jobs ?? []).filter { job in
            job.kind != "vorbereiten"
                && (job.running || ((When.date(job.start) ?? .distantPast) > limit && !dismissedJobs.contains(job.id)))
        }
    }

    func runningJobs(for code: String?) -> [Job] {
        guard let code else { return [] }
        return (overview?.jobs ?? []).filter { $0.running && $0.code == code }
    }

    func dismiss(_ job: Job) { dismissedJobs.append(job.id) }
    func dismissFinishedJobs() { dismissedJobs.append(contentsOf: visibleJobs.filter { !$0.running }.map(\.id)) }

    // MARK: Hinweise

    func show(_ title: String, symbol: String = "checkmark.circle.fill", error: Bool = false) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            notice = Notice(title: title, symbol: error ? "exclamationmark.triangle.fill" : symbol, isError: error)
        }
        if error { Haptics.error() }
        noticeTimer?.cancel()
        noticeTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(error ? 3.6 : 2.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self?.notice = nil }
        }
    }

    // MARK: Aktionen (gleiche Wege wie das Dashboard, alles über den Befehl stageview auf dem Server)

    /// Führt eine Aktion aus, zeigt den Fehler als Hinweis und lädt danach neu. Gibt true zurück, wenn es geklappt hat.
    @discardableResult
    func run(_ key: String, done: String? = nil, _ action: () async throws -> Void) async -> Bool {
        guard !busyKeys.contains(key) else { return false }
        busyKeys.insert(key)
        defer { busyKeys.remove(key) }
        do {
            #if DEBUG
            if Demo.isOn {
                try? await Task.sleep(for: .milliseconds(400))
                if let done { show(done) }
                return true
            }
            #endif
            try await action()
            if let done { show(done) }
            await refresh()
            return true
        } catch APIError.signedOut {
            Keychain.token = nil; signedIn = false
            return false
        } catch {
            show(error.localizedDescription, error: true)
            return false
        }
    }

    func isBusy(_ key: String) -> Bool { busyKeys.contains(key) }

    func saveProject(_ project: Project, fields: [String: Any]) async -> Bool {
        guard let code = project.code, !fields.isEmpty else { return true }
        return await run("projekt-\(code)", done: "Gespeichert, die Seite ist aktualisiert") {
            try await API.post("admin/projekt/\(code)", fields)
        }
    }

    func renameVideo(_ project: Project, _ video: Video, to title: String) async -> Bool {
        guard let code = project.code else { return false }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != video.title else { return true }
        return await run("titel-\(code)-\(video.nr)", done: "Titel gespeichert") {
            try await API.post("admin/projekt/\(code)/video/\(video.nr)", ["titel": clean])
        }
    }

    func removeVideo(_ project: Project, _ video: Video) async -> Bool {
        guard let code = project.code else { return false }
        return await run("entfernen-\(code)-\(video.nr)", done: "Von der Seite genommen") {
            try await API.post("admin/projekt/\(code)/video/\(video.nr)/entfernen")
        }
    }

    func deleteLink(_ project: Project) async -> Bool {
        guard let code = project.code else { return false }
        if !runningJobs(for: code).isEmpty {
            show("Für diesen Link läuft gerade noch ein Auftrag. Lösch ihn, wenn der fertig ist.", error: true)
            return false
        }
        return await run("loeschen-\(code)", done: "Link gelöscht") {
            try await API.post("admin/projekt/\(code)/loeschen")
        }
    }

    func addVideos(_ project: Project, sources: String, title: String) async -> Bool {
        guard let code = project.code else { return false }
        var body: [String: Any] = ["quellen": sources]
        if !title.trimmingCharacters(in: .whitespaces).isEmpty { body["titel"] = title }
        return await run("dazu-\(code)", done: "Läuft, Mux braucht ein paar Minuten") {
            let _: JobRef = try await API.post("admin/projekt/\(code)/dazu", body)
        }
    }

    struct JobRef: Decodable { var id: String }
    struct NewCustomerRef: Decodable { var id: String? }

    func newCustomer(name: String, company: String) async -> String? {
        var created: String?
        let ok = await run("kunde-neu", done: "Kunde angelegt") {
            let r: NewCustomerRef = try await API.post("admin/kunden", ["name": name, "firma": company])
            created = r.id
        }
        #if DEBUG
        if Demo.isOn, ok { return "demo-\(name.lowercased())" }
        #endif
        return ok ? created : nil
    }

    func editCustomer(_ customer: Customer, name: String, company: String) async -> Bool {
        await run("kunde-\(customer.id)", done: "Kunde gespeichert") {
            try await API.post("admin/kunden/\(customer.id)", ["name": name, "firma": company])
        }
    }

    func deleteCustomer(_ customer: Customer) async -> Bool {
        let n = links(of: customer)
        if n > 0 {
            show("\(customer.name) hat noch \(Plural.count(n, "Link", "Links")). Erst einem anderen Kunden zuteilen, dann löschen.", error: true)
            return false
        }
        let ok = await run("kunde-weg-\(customer.id)", done: "Kunde gelöscht") {
            try await API.post("admin/kunden/\(customer.id)/loeschen")
        }
        if ok, customerID == customer.id { customerID = nil }
        return ok
    }
}

/// Internet da oder nicht (wie Connection in der TESS App)
@MainActor
@Observable
final class Connection {
    static let shared = Connection()
    var online = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in
                let now = path.status == .satisfied
                if now != Connection.shared.online { withAnimation(.easeOut(duration: 0.3)) { Connection.shared.online = now } }
                if now { await Store.shared.refresh() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "verbindung"))
    }
}
