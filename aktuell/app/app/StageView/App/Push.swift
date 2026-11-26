import UIKit
import UserNotifications

/// Mitteilungen bei neuen Kommentaren (Ole, 22.11.2026: „Benachrichtigung, wenn Kommentare geschrieben werden, gebündelt alle
/// 10 Minuten“). Die Bündelung macht der Server (videos_api.py, push_runde), die App fragt nur nach der Erlaubnis, meldet ihre
/// Kennung an (POST /api/admin/push) und öffnet beim Antippen den Kommentar im Player (Link mit ?k= und ?t=).
@MainActor
enum Push {
    private static var token: String? {
        get { UserDefaults.standard.string(forKey: "sv.push.kennung") }
        set { UserDefaults.standard.set(newValue, forKey: "sv.push.kennung") }
    }

    /// Nach der Anmeldung und bei jedem Start: Erlaubnis (einmal fragt iOS), dann bei Apple registrieren
    static func start() {
        #if DEBUG
        // Testbuild: nur mit SV_MITTEILUNGEN nach der Erlaubnis fragen (Test mit xcrun simctl push), nie beim Server anmelden
        if Demo.isOn {
            guard ProcessInfo.processInfo.environment["SV_MITTEILUNGEN"] != nil else { return }
            Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
            return
        }
        #endif
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Kennung von Apple: beim Server anmelden (an den angemeldeten Zugang gebunden)
    static func received(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        token = hex
        guard Store.shared.signedIn else { return }
        Task { try? await API.post("admin/push", ["token": hex, "umgebung": environment]) }
    }

    /// Beim Abmelden: der Server schickt diesem iPhone nichts mehr
    static func stop() async {
        guard let token else { return }
        try? await API.delete("admin/push", ["token": token])
    }

    /// Welcher Apple Server: aus dem Bereitstellungsprofil (iPhone Build über scripts/iphone.sh = development, TestFlight und
    /// App Store haben keins oder production)
    private static var environment: String {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .isoLatin1),
              let range = text.range(of: "<key>aps-environment</key>") else { return "production" }
        let rest = text[range.upperBound...].prefix(80)
        return rest.contains("development") ? "sandbox" : "production"
    }
}

/// Mitteilungen auch zeigen, wenn die App offen ist, und Antippen öffnet den Kommentar.
/// Mit Abschluss Block statt async (Absturz 25.11.2026 auf Oles iPhone, im Simulator nachgestellt mit testMitteilungEcht): Die
/// async Fassung meldete iOS das Ende aus einem Nebenstrang (cooperative Thread), UIKit verlangt dafür den Hauptstrang und brach
/// die App ab (NSAssertion in _updateSnapshotAndStateRestorationWithAction), sobald man eine Mitteilung aus dem Hintergrund antippte.
/// Jetzt läuft alles auf dem Hauptstrang, der Abschluss Block kommt erst, wenn der Link geöffnet ist.
final class PushDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let link = response.notification.request.content.userInfo["link"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let link, let url = URL(string: link) { Store.shared.open(url) }
            }
            completionHandler()
        }
    }
}
