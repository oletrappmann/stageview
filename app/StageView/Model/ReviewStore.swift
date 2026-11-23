import SwiftUI

/// Ein Kommentar mit seinen Antworten (Antworten gibt es nur eine Ebene tief, wie auf der Videoseite)
struct CommentThread: Identifiable, Hashable {
    var root: Comment
    var replies: [Comment]
    var id: Int { root.id }
}

/// Kommentare und Freigabe einer Videoseite (GET /api/<code>/). Angemeldet gilt die App als Stagecraft (Rolle team), genau wie
/// das Dashboard im Browser. Ein Speicher pro Link, Projektseite und Player teilen ihn.
@MainActor
@Observable
final class ReviewStore {
    private static var stores: [String: ReviewStore] = [:]

    static func of(_ code: String) -> ReviewStore {
        if let store = stores[code] { return store }
        let store = ReviewStore(code: code)
        stores[code] = store
        return store
    }

    let code: String
    var state = ReviewState()
    var loaded = false
    var failed = false
    private var poller: Task<Void, Never>?
    private var watchers = 0

    private init(code: String) {
        self.code = code
        #if DEBUG
        if Demo.isOn { state = Demo.review(code); loaded = true }
        #endif
    }

    private var name: String { Store.shared.me?.name ?? "Stagecraft" }

    func load() async {
        #if DEBUG
        if Demo.isOn { return }
        #endif
        do {
            let fresh: ReviewState = try await API.get("\(code)/")
            state = fresh
            keepPending()
            loaded = true
            failed = false
        } catch {
            failed = !loaded
        }
    }

    /// Solange Projektseite oder Player offen sind, alle 15 s nachsehen (Kunden kommentieren gleichzeitig)
    func watch() {
        watchers += 1
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.load()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func unwatch() {
        watchers = max(0, watchers - 1)
        if watchers == 0 { poller?.cancel(); poller = nil }
    }

    // MARK: Lesen

    func threads(for video: String) -> [CommentThread] {
        let all = state.comments.filter { $0.video == video }
        let roots = all.filter { $0.replyTo == nil }.sorted { a, b in
            switch (a.time, b.time) {
            case let (x?, y?): x != y ? x < y : a.id < b.id
            case (nil, nil): a.id < b.id
            case (_?, nil): true
            case (nil, _?): false
            }
        }
        return roots.map { root in CommentThread(root: root, replies: all.filter { $0.replyTo == root.id }.sorted { $0.id < $1.id }) }
    }

    func openCount(for video: String) -> Int {
        state.comments.filter { $0.video == video && $0.replyTo == nil && !$0.done }.count
    }

    func status(of video: Video) -> ReviewStatus { state.status[video.id]?.value ?? video.status }
    func statusEntry(of video: Video) -> StatusEntry? { state.status[video.id] }

    // MARK: Schreiben (sofort sichtbar, bei Fehler zurück)

    func add(video: String, text: String, time: Double?, replyTo: Int? = nil) async -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        var body: [String: Any] = ["video": video, "text": clean, "name": name]
        if let replyTo { body["antwort_auf"] = replyTo } else if let time { body["zeit"] = (time * 10).rounded() / 10 }
        #if DEBUG
        if Demo.isOn {
            state.comments.append(Comment(id: (state.comments.map(\.id).max() ?? 0) + 1, video: video, time: replyTo == nil ? time : nil,
                                          text: clean, name: name, team: true, replyTo: replyTo, created: ISO8601DateFormatter().string(from: .now)))
            return true
        }
        #endif
        do {
            let created: Comment = try await API.post("\(code)/kommentare", body)
            state.comments.append(created)
            Task { await Store.shared.refresh() }
            return true
        } catch {
            Store.shared.show(error.localizedDescription, error: true)
            return false
        }
    }

    func setDone(_ comment: Comment, _ done: Bool) async {
        let root = comment.replyTo ?? comment.id
        let before = state.comments
        for index in state.comments.indices where state.comments[index].id == root || state.comments[index].replyTo == root {
            state.comments[index].done = done
            state.comments[index].doneBy = done ? name : nil
        }
        #if DEBUG
        if Demo.isOn { return }
        #endif
        do {
            let _: Comment = try await API.post("\(code)/kommentare/\(root)/erledigt", ["erledigt": done, "name": name])
            Task { await Store.shared.refresh() }
        } catch {
            state.comments = before
            Store.shared.show(error.localizedDescription, error: true)
        }
    }

    func edit(_ comment: Comment, text: String) async -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        #if DEBUG
        if Demo.isOn {
            if let i = state.comments.firstIndex(where: { $0.id == comment.id }) { state.comments[i].text = clean }
            return true
        }
        #endif
        do {
            let updated: Comment = try await API.post("\(code)/kommentare/\(comment.id)/text", ["text": clean])
            if let i = state.comments.firstIndex(where: { $0.id == comment.id }) { state.comments[i] = updated }
            return true
        } catch {
            Store.shared.show(error.localizedDescription, error: true)
            return false
        }
    }

    func delete(_ comment: Comment) async {
        let before = state.comments
        state.comments.removeAll { $0.id == comment.id || $0.replyTo == comment.id }
        #if DEBUG
        if Demo.isOn { return }
        #endif
        do {
            try await API.delete("\(code)/kommentare/\(comment.id)")
            Store.shared.show("Kommentar gelöscht", symbol: "trash")
            Task { await Store.shared.refresh() }
        } catch {
            state.comments = before
            Store.shared.show(error.localizedDescription, error: true)
        }
    }

    /// Stände vor dem Schalter „Alle freigegeben“: Ausschalten holt sie zurück (nur solange die App läuft)
    private var beforeAll: [String: ReviewStatus]?

    /// Schalter „Alle freigegeben“ (Ole, 23.11.2026: „ein On/Off Schalter“). An: alle freigegeben, die Stände davor gemerkt.
    /// Aus: die gemerkten Stände zurück, ohne gemerkte (z.B. der Kunde hat alles freigegeben) alle auf Zur Freigabe
    func setAllApproved(_ on: Bool, videos: [Video]) async {
        if on {
            beforeAll = Dictionary(uniqueKeysWithValues: videos.filter { status(of: $0) != .approved }.map { ($0.id, status(of: $0)) })
            await setStatus(.approved, for: videos)
            return
        }
        let back = beforeAll ?? [:]
        beforeAll = nil
        if back.isEmpty {
            await setStatus(.pending, for: videos)
        } else {
            for value in Set(back.values) {
                await setStatus(value, for: videos.filter { back[$0.id] == value })
            }
        }
    }

    // MARK: Freigabe speichern (Ole, 23.11.2026: „so viel rumdrücken, wie man möchte, es wird trotzdem gespeichert und ist
    // automatisch fehlerresistent“): sofort sichtbar, kurz gesammelt, gebündelt in einer Anfrage, bei schnellem Hin und Her
    // zählt nur der letzte Stand. Klappt das Speichern nicht, versucht es die App selbst weiter (1, 2, 4 … höchstens 20 s),
    // bis es gespeichert ist. Neu laden überschreibt nichts, was noch unterwegs ist

    /// Noch nicht gesendet und gerade unterwegs (Video ID → Stand)
    private var wanted: [String: ReviewStatus] = [:]
    private var sending: [String: ReviewStatus] = [:]
    private var flushTask: Task<Void, Never>?
    private var saveFailures = 0

    func setStatus(_ status: ReviewStatus, for videos: [Video]) async {
        queue(Dictionary(videos.map { ($0.id, status) }, uniquingKeysWith: { _, last in last }))
    }

    func setStatus(_ status: ReviewStatus, for video: Video) async {
        queue([video.id: status])
    }

    private func queue(_ changes: [String: ReviewStatus]) {
        guard !changes.isEmpty else { return }
        let at = ISO8601DateFormatter().string(from: .now)
        for (id, value) in changes {
            state.status[id] = StatusEntry(value: value, by: name, at: at)
            wanted[id] = value
        }
        #if DEBUG
        if Demo.isOn { wanted = [:]; return }
        #endif
        guard flushTask == nil else { return }  // läuft schon: nimmt den neuen Stand gleich mit
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            await self?.flush()
        }
    }

    private func flush() async {
        while !wanted.isEmpty {
            let batch = wanted
            wanted = [:]
            sending = batch
            do {
                try await API.post("\(code)/status", ["eintraege": batch.map { ["video": $0.key, "status": $0.value.rawValue] }, "name": name])
                sending = [:]
                if saveFailures >= 2 { Store.shared.show("Freigabe gespeichert") }
                saveFailures = 0
            } catch APIError.signedOut {
                sending = [:]
                wanted = [:]
                break
            } catch APIError.server(let code, let text) where code == 400 || code == 403 || code == 404 {
                // Ungültig (z.B. Video inzwischen weg): nicht wiederholen, Stand vom Server holen
                sending = [:]
                Store.shared.show(text, error: true)
                await load()
            } catch {
                sending = [:]
                for (id, value) in batch where wanted[id] == nil { wanted[id] = value }  // Neueres gewinnt
                saveFailures += 1
                if saveFailures == 2 { Store.shared.show("Freigabe wird gespeichert, sobald es wieder geht", symbol: "arrow.triangle.2.circlepath") }
                try? await Task.sleep(for: .seconds(min(20, pow(2, Double(saveFailures - 1)))))
            }
        }
        flushTask = nil
        await Store.shared.refresh()
    }

    /// Was noch nicht beim Server angekommen ist, über frisch geladene Stände legen
    private func keepPending() {
        let pending = sending.merging(wanted) { _, newer in newer }
        guard !pending.isEmpty else { return }
        let at = ISO8601DateFormatter().string(from: .now)
        for (id, value) in pending { state.status[id] = StatusEntry(value: value, by: name, at: at) }
    }
}
