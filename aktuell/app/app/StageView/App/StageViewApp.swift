import SwiftUI
import UserNotifications

/// Die App bleibt hochkant, nur Apples Vollbild Player darf sich drehen (Fullscreen)
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = .portrait
    private let push = PushDelegate()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = push
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in Push.received(deviceToken) }
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientations
    }
}

@main
struct StageViewApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // Vorschaubilder von Mux bleiben auf der Platte, dann sind sie beim nächsten Öffnen sofort da
        URLCache.shared = URLCache(memoryCapacity: 48 * 1024 * 1024, diskCapacity: 600 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            // Immer dunkel (Ole, 22.11.2026: „App soll immer Darkmode sein“), Farben wie die Videoseite im Web
            RootView()
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
                // Konten und Bilder von StageHub auch angemeldet frisch halten (Konto Menü, 23.11.2026)
                .task { await Profiles.shared.refresh() }
        }
    }
}

/// Wohin die Navigation geht
enum Route: Hashable {
    case project(String)
    case customer(String)
    /// Kundenansicht eines Links wie videos.stagecraft.media/<code>
    case client(String)
}

/// Neuer Link, auf Wunsch schon mit Kunde
struct NewLinkStart: Identifiable {
    let id = UUID()
    var customerID: String?
}

/// Ohne Anmeldung die Anmeldung, sonst die App. Holt die Daten, solange die App vorne ist.
struct RootView: View {
    @State private var store = Store.shared
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack {
            if store.signedIn {
                MainView().transition(.opacity)
            } else {
                LoginView().transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: store.signedIn)
        // Links von videos.stagecraft.media (Universal Link) und stageview:// öffnen in der App
        .onOpenURL { store.open($0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { store.open(url) }
        }
        .onChange(of: phase, initial: true) { _, now in
            if now == .active && store.signedIn { store.startPolling(); Push.start() } else if now != .active { store.stopPolling() }
            // App weggelegt: die Links gelten als gesehen, beim nächsten Öffnen leuchtet nur, was danach kam
            if now == .background && store.signedIn { Seen.shared.markLinks() }
        }
        .onChange(of: store.signedIn) { _, now in
            if now { store.startPolling() } else { store.stopPolling() }
        }
    }
}

/// Navigation der App: Links, darüber die Seite eines Links, der Player legt sich über alles und wächst aus dem Vorschaubild
struct MainView: View {
    @State private var store = Store.shared
    @State private var path: [Route] = []
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: $path) {
            StartPage(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .project(let key): ProjectPage(key: key, path: $path)
                    case .customer(let id): CustomerPage(id: id, path: $path)
                    case .client(let key): ClientPage(key: key, path: $path)
                    }
                }
        }
        .environment(\.zoomSpace, zoom)
        .onChange(of: store.jump) { _, route in
            guard let route else { return }
            path = route
            store.jump = nil
        }
        .fullScreenCover(item: $store.playing) { request in
            PlayerScreen(request: request)
                .zoomTransition(request.sourceID, zoom)
                // Nur das Kreuz schließt (Ole, 22.11.2026): Wischen nach oben und unten gehört dem Blatt mit den Kommentaren,
                // Apples Zoom Übergang würde den Player sonst beim kräftigen Wischen zumachen
                .interactiveDismissDisabled()
        }
        .overlay {
            if let request = store.share, store.playing == nil {
                ShareDialog(request: request) { store.share = nil }
            }
        }
        .overlay(alignment: .top) {
            if let notice = store.notice, store.playing == nil {
                NoticeCapsule(notice: notice)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { store.notice = nil } }
            }
        }
        #if DEBUG
        .onAppear {
            path = Demo.initialPath
            Demo.start()
        }
        #endif
    }
}

/// Hinweis als Glaskapsel oben (gespeichert, kopiert, Fehler), verschwindet von selbst
struct NoticeCapsule: View {
    let notice: Notice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notice.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(notice.isError ? Palette.overdue : Palette.accent)
            Text(notice.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hinweis")
    }
}

// MARK: Zoom aus dem Vorschaubild in den Player

private struct ZoomSpaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var zoomSpace: Namespace.ID? {
        get { self[ZoomSpaceKey.self] }
        set { self[ZoomSpaceKey.self] = newValue }
    }
}

extension View {
    /// Vorschaubild, aus dem der Player herauswächst
    @ViewBuilder
    func zoomSource(_ id: String, _ space: Namespace.ID?) -> some View {
        if let space { matchedTransitionSource(id: id, in: space) { $0.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)) } } else { self }
    }

    @ViewBuilder
    func zoomTransition(_ id: String?, _ space: Namespace.ID) -> some View {
        if let id { navigationTransition(.zoom(sourceID: id, in: space)) } else { self }
    }
}

extension Store {
    /// Player öffnen. source: Kennung des Vorschaubilds, aus dem er wachsen soll. comment: von einem Kommentar aus (Blatt offen,
    /// Kommentar hervorgehoben, Video steht an der Stelle)
    func play(_ project: Project, _ video: Video, at time: Double? = nil, source: String?, comment: Int? = nil) {
        guard project.code != nil else { return }
        playing = PlayerRequest(projectKey: project.key, videoID: video.id, time: time, sourceID: source, comment: comment)
    }
}

/// Version und Stand für das Konto Menü
enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1" }
    static var built: String {
        guard let url = Bundle.main.executableURL, let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else { return "" }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "de_DE")))
    }
}
