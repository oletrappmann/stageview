import Foundation

/// „Neu seit deinem letzten Blick“ (Review 22.11.2026, Ole: ja): pro Gerät gemerkt, wann man zuletzt auf die Kommentare und auf die
/// Links geschaut hat. Neues bekommt einen Punkt, die Zahl am Tab Kommentare zählt nur Neues. Beim ersten Start gilt alles als
/// gesehen, damit nicht gleich alles leuchtet.
@MainActor
@Observable
final class Seen {
    static let shared = Seen()

    private(set) var comments: Date
    private(set) var links: Date

    private init() {
        let d = UserDefaults.standard
        let now = Date()
        if d.object(forKey: "sv.gesehen.kommentare") == nil { d.set(now, forKey: "sv.gesehen.kommentare") }
        if d.object(forKey: "sv.gesehen.links") == nil { d.set(now, forKey: "sv.gesehen.links") }
        comments = d.object(forKey: "sv.gesehen.kommentare") as? Date ?? now
        links = d.object(forKey: "sv.gesehen.links") as? Date ?? now
        #if DEBUG
        // Vorführung: SV_GESEHEN=2026-11-19 tut so, als hätte man zuletzt an dem Tag geschaut
        if let value = ProcessInfo.processInfo.environment["SV_GESEHEN"], let date = When.date(value) { comments = date; links = date }
        #endif
    }

    /// Neu, wenn nach dem letzten Blick geschrieben und nicht von einem selbst
    func isNewComment(_ comment: OpenComment) -> Bool {
        if let me = Store.shared.me?.name, comment.team, comment.name == me { return false }
        return When.date(comment.created).map { $0 > comments } ?? false
    }

    /// Neu angelegt oder neue Aktivität (Kommentar, Freigabe) seit dem letzten Blick auf die Links
    func isNewLink(_ project: Project) -> Bool {
        if let last = When.date(project.lastActivity), last > links { return true }
        // Angelegt kennt nur den Tag: neu, wenn der Tag nach dem letzten Blick liegt
        if let created = When.date(project.created), created > links { return true }
        return false
    }

    func markComments() {
        comments = Date()
        UserDefaults.standard.set(comments, forKey: "sv.gesehen.kommentare")
    }

    func markLinks() {
        links = Date()
        UserDefaults.standard.set(links, forKey: "sv.gesehen.links")
    }
}

extension Store {
    /// Offene Kommentare, die seit dem letzten Blick auf die Kommentare dazugekommen sind
    var newCommentCount: Int { allOpenComments.filter { Seen.shared.isNewComment($0.comment) }.count }
}
