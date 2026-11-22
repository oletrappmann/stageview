import SwiftUI

/// Zahnrad Menü wie auf der Videoseite am Handy (Ole, 23.11.2026: „nicht das Liquid Glas Menü von Apple, sondern das wie im Web“,
/// projekt.html .einstell-menue.klassisch): dunkles Feld über dem Zahnrad, Hauptliste Tempo und Qualität mit dem aktuellen Wert,
/// Tipp öffnet die Auswahl (gleitet von rechts herein), Haken links, nach der Wahl zurück zur Hauptliste. Dahinter abgedunkelt,
/// Tipp daneben schließt.
struct SettingsPanel: View {
    let pool: PlayerPool
    let video: Video

    enum Page { case main, tempo, quality }
    @State private var page = Page.main
    @State private var forward = true

    private static let panel = Color(UIColor(hex: 0x2A2A27))
    private static let ink = Color(UIColor(hex: 0xF3F2EE))
    private static let check = Color(UIColor(hex: 0xA9C1AE))

    var body: some View {
        ZStack {
            switch page {
            case .main: mainList.transition(slide)
            case .tempo: choiceList(title: "Tempo", options: tempoOptions).transition(slide)
            case .quality: choiceList(title: "Qualität", options: qualityOptions).transition(slide)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 25, y: 20)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("einstell-menue")
    }

    /// Herein von rechts, zurück von links (wie e-rein und e-zurueck im Web)
    private var slide: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(x: forward ? 22 : -22)), removal: .opacity)
    }

    private func go(_ next: Page) {
        Haptics.select()
        forward = next != .main
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)) { page = next }
    }

    // MARK: Hauptliste

    private var mainList: some View {
        VStack(spacing: 0) {
            mainRow(icon: AnyView(Image(systemName: "timer").font(.system(size: 19, weight: .medium))), title: "Tempo",
                    value: PlayerPool.speedText(pool.speed), id: "e-tempo") { go(.tempo) }
            mainRow(icon: AnyView(HDBadge(size: 22)), title: "Qualität", value: qualityValue, id: "e-quali") { go(.quality) }
        }
    }

    private func mainRow(icon: AnyView, title: String, value: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon.frame(width: 24)
                Text(title).font(.system(size: 16))
                Spacer(minLength: 8)
                Text(value).font(.system(size: 15).monospacedDigit()).foregroundStyle(Self.ink.opacity(0.56))
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Self.ink.opacity(0.56))
            }
            .foregroundStyle(Self.ink)
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityValue(value)
        .accessibilityIdentifier(id)
    }

    // MARK: Auswahl

    private struct Option: Identifiable {
        var id: String
        var text: String
        var extra: String = ""
        var selected: Bool
        var choose: () -> Void
    }

    private var tempoOptions: [Option] {
        PlayerPool.speeds.map { rate in
            Option(id: "tempo-\(rate)", text: rate.formatted(.number.precision(.fractionLength(0...2))) + "×", extra: rate == 1 ? "Normal" : "",
                   selected: pool.speed == rate) { pool.speed = rate }
        }
    }

    private var qualityOptions: [Option] {
        [Option(id: "quali-auto", text: "Auto", extra: pool.currentHeight.map(PlayerPool.qualityText) ?? "", selected: pool.quality == nil) { pool.quality = nil }]
            + pool.qualities(for: video).map { h in
                Option(id: "quali-\(h)", text: PlayerPool.qualityText(h), selected: pool.quality == h) { pool.quality = h }
            }
    }

    private var qualityValue: String {
        guard let q = pool.quality else { return pool.currentHeight.map { "Auto · " + PlayerPool.qualityText($0) } ?? "Auto" }
        return PlayerPool.qualityText(q)
    }

    private func choiceList(title: String, options: [Option]) -> some View {
        VStack(spacing: 0) {
            Button { go(.main) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                    Text(title).font(.system(size: 16, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(Self.ink)
                .padding(.horizontal, 10)
                .frame(height: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPress())
            .accessibilityLabel("Zurück")
            .accessibilityIdentifier("e-zurueck")
            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
            if options.count <= 1 && title == "Qualität" && pool.qualities(for: video).isEmpty {
                Text("Automatisch, passend zur Verbindung")
                    .font(.system(size: 13)).foregroundStyle(Self.ink.opacity(0.56))
                    .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(options) { option in
                Button {
                    option.choose()
                    // Nach der Wahl zurück zur Hauptliste, dort steht dann der neue Wert (wie im Web)
                    go(.main)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Self.check)
                            .opacity(option.selected ? 1 : 0)
                            .frame(width: 22)
                        Text(option.text).font(.system(size: 16).monospacedDigit())
                        Spacer(minLength: 8)
                        if !option.extra.isEmpty {
                            Text(option.extra).font(.system(size: 14)).foregroundStyle(Self.ink.opacity(0.56))
                        }
                    }
                    .foregroundStyle(Self.ink)
                    .padding(.leading, 12)
                    .padding(.trailing, 14)
                    .frame(height: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .accessibilityAddTraits(option.selected ? .isSelected : [])
                .accessibilityIdentifier(option.id)
            }
        }
    }
}

/// Zeile im Menü: beim Drücken kurz hinterlegt wie :active im Web
private struct RowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color(UIColor(hex: 0x373733)).opacity(configuration.isPressed ? 1 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Das HD Zeichen der Videoseite (Rahmen mit „HD“)
struct HDBadge: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
                .strokeBorder(lineWidth: size * 0.075)
                .frame(width: size * 0.82, height: size * 0.56)
            Text("HD").font(.system(size: size * 0.3, weight: .heavy))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
