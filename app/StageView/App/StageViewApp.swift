import SwiftUI

@main
struct StageViewApp: App {
    @AppStorage("sv.darstellung") private var appearance = "auto"

    init() {
        // Vorschaubilder von Mux bleiben auf der Platte, dann sind sie beim nächsten Öffnen sofort da
        URLCache.shared = URLCache(memoryCapacity: 48 * 1024 * 1024, diskCapacity: 600 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(appearance == "hell" ? .light : appearance == "dunkel" ? .dark : nil)
                .tint(Palette.accent)
        }
    }
}

/// Wohin die Navigation geht
enum Route: Hashable {
    case project(String)
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
        .onChange(of: phase, initial: true) { _, now in
            if now == .active && store.signedIn { store.startPolling() } else if now != .active { store.stopPolling() }
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
            LinksPage(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .project(let key): ProjectPage(key: key, path: $path)
                    }
                }
        }
        .environment(\.zoomSpace, zoom)
        .fullScreenCover(item: $store.playing) { request in
            PlayerScreen(request: request)
                .zoomTransition(request.sourceID, zoom)
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
    /// Player öffnen. source: Kennung des Vorschaubilds, aus dem er wachsen soll
    func play(_ project: Project, _ video: Video, at time: Double? = nil, source: String?) {
        guard project.code != nil else { return }
        playing = PlayerRequest(projectKey: project.key, videoID: video.id, time: time, sourceID: source)
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
