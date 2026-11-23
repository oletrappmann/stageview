import Foundation
import Security
import UIKit

/// Token, Zugang und Geräteschlüssel im iOS Schlüsselbund: bleibt auf diesem iPhone (kein iCloud, kein Backup), nach dem ersten
/// Entsperren lesbar. Wie in der TESS App steckt in der App selbst kein Schlüssel.
enum Keychain {
    private static let service = "media.stagecraft.stageview"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func string(_ account: String) -> String? {
        var search = query(account)
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        SecItemDelete(query(account) as CFDictionary)
        guard let value else { return }
        var item = query(account)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static var token: String? {
        get {
            #if DEBUG
            if let test = ProcessInfo.processInfo.environment["SV_TESTTOKEN"], !test.isEmpty { return test }
            if Demo.isOn { return nil }
            #endif
            return string("sitzung")
        }
        set { set(newValue, for: "sitzung") }
    }

    /// Eigener Geräteschlüssel für Kommentare (X-Autor auf der Videoseite): damit gelten Kommentare aus der App als eigene
    static var authorKey: String {
        if let key = string("autor"), key.count >= 20 { return key }
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let key = "app-" + bytes.map { String(format: "%02x", $0) }.joined()
        set(key, for: "autor")
        return key
    }
}

enum APIError: LocalizedError {
    case signedOut
    case offline
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .signedOut: "Bitte neu anmelden."
        case .offline: "Keine Verbindung, bitte gleich nochmal."
        case .server(_, let text): text
        }
    }
}

/// Spricht mit videos.stagecraft.media genau wie das Admin Dashboard: /api/admin/… für die Verwaltung, /api/<code>/… für
/// Kommentare und Freigabe. Das Token aus der Anmeldung geht als Cookie sv_sitzung mit, so wie im Browser. Am Server muss dafür
/// nichts anders sein.
enum API {
    static let host = URL(string: "https://videos.stagecraft.media")!

    /// Eigene Sitzung ohne Cookie Speicher: das Token verwaltet die App selbst, nichts landet in geteilten Cookies
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Datei vom Server holen (z.B. Marker für DaVinci als EDL), mit derselben Anmeldung
    static func download(_ path: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "/api/" + path, relativeTo: host)!)
        if let token = Keychain.token { request.setValue("sv_sitzung=\(token)", forHTTPHeaderField: "Cookie") }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw APIError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw APIError.signedOut }
        guard (200..<300).contains(status) else {
            let text = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["fehler"] as? String
            throw APIError.server(status, text ?? "Das hat nicht geklappt (Fehler \(status)).")
        }
        return data
    }

    static func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        try await send(path, method: "GET", body: nil)
    }

    @discardableResult
    static func post<T: Decodable>(_ path: String, _ body: [String: Any] = [:], as type: T.Type = T.self) async throws -> T {
        try await send(path, method: "POST", body: body)
    }

    static func post(_ path: String, _ body: [String: Any] = [:]) async throws {
        let _: Empty = try await send(path, method: "POST", body: body)
    }

    static func delete(_ path: String) async throws {
        let _: Empty = try await send(path, method: "DELETE", body: nil)
    }

    static func delete(_ path: String, _ body: [String: Any]) async throws {
        let _: Empty = try await send(path, method: "DELETE", body: body)
    }

    struct Empty: Decodable {}

    private static func send<T: Decodable>(_ path: String, method: String, body: [String: Any]?) async throws -> T {
        var request = URLRequest(url: URL(string: "/api/" + path, relativeTo: host)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = Keychain.token { request.setValue("sv_sitzung=\(token)", forHTTPHeaderField: "Cookie") }
        request.setValue(Keychain.authorKey, forHTTPHeaderField: "X-Autor")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw APIError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 && path.hasPrefix("admin/") { throw APIError.signedOut }
        guard (200..<300).contains(status) else {
            let text = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["fehler"] as? String
            throw APIError.server(status, text ?? "Das hat nicht geklappt (Fehler \(status)).")
        }
        if T.self == Empty.self { return Empty() as! T }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.server(status, "Die Antwort vom Server ließ sich nicht lesen.")
        }
    }

    // MARK: Anmeldung

    /// Name wählen, Passwort: geprüft von der Brücke der TESS App. Das Token kommt als Cookie zurück, die App legt es in den
    /// Schlüsselbund. Das Gerät heißt in der TESS App dann „Browser StageView iPhone App“ (sperren geht dort wie bei jedem Gerät).
    static func signIn(_ access: Access, password: String) async throws -> Me {
        var request = URLRequest(url: URL(string: "/api/admin/anmelden", relativeTo: host)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-StageView-App")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["zugang": access.rawValue, "passwort": password, "geraet": deviceName])
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw APIError.offline }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if status == 401 { throw APIError.server(401, "Passwort falsch.") }
        guard status == 200 else { throw APIError.server(status, json?["fehler"] as? String ?? "Das hat nicht geklappt (Fehler \(status)).") }
        let cookie = (http?.value(forHTTPHeaderField: "Set-Cookie") ?? "")
        guard let match = cookie.firstMatch(of: /sv_sitzung=([^;]+)/) else {
            throw APIError.server(status, "Die Anmeldung kam ohne Sitzung zurück.")
        }
        Keychain.token = String(match.1)
        return Me(zugang: access.rawValue, name: json?["name"] as? String ?? access.person)
    }

    /// Meldet das Gerät auch bei der Brücke ab (wie Abmelden im Dashboard)
    static func signOut() async {
        try? await post("admin/abmelden")
        Keychain.token = nil
    }

    /// Kurzer Name fürs Gerät (höchstens 20 Zeichen, der Server schneidet sonst ab). Die App gibt es nur fürs iPhone
    static let deviceName = "iPhone App"
}
