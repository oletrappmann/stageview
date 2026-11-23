import SwiftUI
import UIKit

// MARK: Logo

/// Das StageView Zeichen: grünes Quadrat mit dem offenen Dreieck aus dem Stagecraft Logo (wie TESS StageViewCards, engine/seite/icon.svg)
struct StageViewMark: View {
    var size: CGFloat = 20

    var body: some View {
        let k = size / 64
        ZStack {
            RoundedRectangle(cornerRadius: 14 * k, style: .continuous)
                .fill(LinearGradient(colors: [Color(UIColor(hex: 0x6A7B6D)), Color(UIColor(hex: 0x2A302C))],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 14 * k, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: max(0.5, 1.5 * k))
            PlayA()
                .stroke(Color(UIColor(hex: 0xF3F2EE)), style: StrokeStyle(lineWidth: 5.5 * k, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Das offene Dreieck, zum Play Pfeil gedreht (Raster 64)
struct PlayA: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 64
        var path = Path()
        path.move(to: CGPoint(x: 20 * k, y: 15 * k))
        path.addLine(to: CGPoint(x: 49.5 * k, y: 32 * k))
        path.addLine(to: CGPoint(x: 20 * k, y: 49 * k))
        path.addLine(to: CGPoint(x: 20 * k, y: 27 * k))
        return path
    }
}

/// Schriftzug STAGEVIEW (engine/seite/stageview.svg), oben links wie das TESS Logo, in Textfarbe
struct StageViewWordmark: View {
    var height: CGFloat = 17

    var body: some View {
        HStack(spacing: height * 0.5) {
            StageViewMark(size: height * 1.55)
            Image("Wortmarke")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(height: height)
                .foregroundStyle(Palette.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("StageView")
    }
}

// MARK: Bilder

/// Vorschaubilder von Mux. Eigener Speicher im Arbeitsspeicher und auf der Platte (URLCache), damit beim Scrollen und beim
/// Zurückkommen nichts neu lädt oder flackert.
@MainActor
final class ImageStore {
    static let shared = ImageStore()
    private let memory = NSCache<NSURL, UIImage>()
    private var running: [URL: Task<UIImage?, Never>] = [:]

    private init() { memory.totalCostLimit = 80 * 1024 * 1024 }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let image = cached(url) { return image }
        if let task = running[url] { return await task.value }
        let task = Task<UIImage?, Never> {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, _) = try? await URLSession.shared.data(for: request), let image = UIImage(data: data) else { return nil }
            return await image.byPreparingForDisplay() ?? image
        }
        running[url] = task
        let image = await task.value
        running[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4)) }
        return image
    }
}

/// Bild von Mux, bis es da ist die Fläche. Blendet weich ein, aus dem Speicher sofort ohne Blenden.
struct RemoteImage: View {
    let url: URL?
    var placeholder: Color = Palette.surface
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            placeholder
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            }
        }
        .clipped()
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImageStore.shared.cached(url) { image = hit; return }
            image = nil
            let loaded = await ImageStore.shared.load(url)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
        .accessibilityHidden(true)
    }
}

/// Dunkles Glas mit weißem Dreieck wie der Knopf auf videos.stagecraft.media
struct PlayDisc: View {
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(Color.black.opacity(0.28))
            Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: size * 0.03)
        }
        .frame(width: size, height: size)
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }
}

// MARK: Freigabe

/// Punkt in der Farbe des Freigabe Status
struct StatusDot: View {
    let status: ReviewStatus
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(status.color).frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// Freigabe als Balken: freigegeben grün, Änderung gewünscht warm, offen Fläche. Füllt sich mit Feder.
struct ApprovalBar: View {
    let approved: Int
    let changes: Int
    let total: Int
    var height: CGFloat = 6

    var body: some View {
        Capsule()
            .fill(Palette.surface)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    let all = CGFloat(max(total, 1))
                    HStack(spacing: approved > 0 && changes > 0 ? 2 : 0) {
                        Capsule().fill(Palette.approvedInk).frame(width: geo.size.width * CGFloat(approved) / all)
                        Capsule().fill(Palette.changesInk).frame(width: geo.size.width * CGFloat(changes) / all)
                    }
                }
            }
            .animation(.spring(response: 0.7, dampingFraction: 0.85), value: approved)
            .animation(.spring(response: 0.7, dampingFraction: 0.85), value: changes)
            .accessibilityHidden(true)
    }
}

// MARK: Personen und Kunden

/// Gesicht einer Person aus dem Team (gleiche Bilder wie in der TESS App), sonst der Anfangsbuchstabe
struct TeamAvatar: View {
    let access: Access
    var size: CGFloat = 52
    @State private var loaded: UIImage?

    /// Töne für Konten ohne Bild, nach der Reihenfolge wie bei StageHub (stil.css .ton0 bis .ton3)
    private static let tones: [(color: UInt32, text: UInt32)] = [(0x48514A, 0xF6F6F3), (0x6E7A70, 0xF6F6F3), (0xA3AFA5, 0x2B312C), (0x3A403B, 0xF6F6F3)]

    var body: some View {
        // Bild aus der Liste von StageHub (eigenes Profilbild oder das feste), bis es geladen ist das mitgelieferte, sonst der
        // Anfangsbuchstabe auf dem Ton seiner Reihe (23.11.2026)
        if let photo = loaded ?? access.picture.flatMap(ImageStore.shared.cached) ?? UIImage(named: "avatar-\(access.person.lowercased())") {
            Image(uiImage: photo).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
                .task(id: access.picture) { await load() }
        } else {
            let tone = Self.tones[abs(access.order) % Self.tones.count]
            Text(String(access.person.prefix(1)))
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color(UIColor(hex: tone.text)))
                .frame(width: size, height: size)
                .background(Color(UIColor(hex: tone.color)), in: Circle())
                .task(id: access.picture) { await load() }
        }
    }

    private func load() async {
        guard let url = access.picture else { loaded = nil; return }
        if let image = await ImageStore.shared.load(url) { loaded = image }
    }
}

/// Kunde als Kreis mit Kürzel in seiner Farbe (wie im Admin Dashboard), mit leichtem Verlauf wie die TESS Personen
struct CustomerAvatar: View {
    let name: String
    var size: CGFloat = 52

    var body: some View {
        let tone = CustomerTone.colors(for: name)
        Text(CustomerTone.initials(name))
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(tone.text)
            .frame(width: size, height: size)
            .background {
                Circle().fill(tone.fill)
                    .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)))
            }
            .accessibilityLabel(name)
    }
}
