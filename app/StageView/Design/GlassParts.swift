import SwiftUI

// Bausteine des Designs Glas aus der TESS App (TESS_APP/TESS/Views/GlassParts.swift, design/glas/BLUEPRINT.md), dazu, was
// StageView selbst braucht. Gleiche Maße und Federn wie dort, damit sich beide Apps gleich anfühlen.

/// Glaskreis für die Bedienung, interaktives Liquid Glass
struct GlassCircle: View {
    let symbol: String
    var size: CGFloat = 54
    var symbolSize: CGFloat = 19
    var tint: Color = Palette.text
    /// Gerade an: grünes Glas
    var active = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(active ? Color.white : tint)
            .frame(width: size, height: size)
            .glassEffect(active ? .regular.tint(Palette.forest).interactive() : .regular.interactive(), in: .circle)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.25), value: active)
    }
}

/// Weiche Kante oben: der Canvas deckt bis unter den Kopf und läuft dann weich aus. Nur Canvas, kein Material (Ole, 12.11.2026:
/// sichtbare Flächen ohne Inhalt „sehen billig aus“)
struct TopEdge: View {
    var overhang: CGFloat = 0
    var color: Color = Palette.canvas

    var body: some View {
        LinearGradient(stops: [
            .init(color: color, location: 0),
            .init(color: color, location: 0.6),
            .init(color: color.opacity(0.86), location: 0.72),
            .init(color: color.opacity(0.55), location: 0.84),
            .init(color: color.opacity(0.2), location: 0.94),
            .init(color: color.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .padding(.bottom, -overhang)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

/// Weiche Kante unten: der Inhalt läuft sanft unter die Glasknöpfe
struct BottomEdge: View {
    var color: Color = Palette.canvas
    var height: CGFloat = 150

    var body: some View {
        LinearGradient(stops: [
            .init(color: color.opacity(0), location: 0),
            .init(color: color.opacity(0.72), location: 0.48),
            .init(color: color.opacity(0.72), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: height)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }
}

/// Kein Internet: kleine Glaskapsel unter dem Kopf, verschwindet von selbst
struct OfflineCapsule: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash").font(.system(size: 13, weight: .semibold))
            Text("Keine Verbindung. Versuche zu verbinden …").font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Palette.text.opacity(0.75))
        .padding(.horizontal, 14)
        .frame(height: 32)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("keine-verbindung")
    }
}

/// Schalter als Glaskapsel (TESS Aufgaben Seite): Spur in text 7 %, Schieber in field gleitet mit Feder
struct GlassSwitch: View {
    let options: [(id: String, label: String)]
    let selection: String
    var badges: [String: Int] = [:]
    var badgeColor: Color = Palette.overdue
    let choose: (String) -> Void
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.id) { option in
                let chosen = option.id == selection
                Button {
                    guard !chosen else { return }
                    Haptics.select()
                    choose(option.id)
                } label: {
                    HStack(spacing: 5) {
                        Text(option.label)
                            .font(.system(size: 14, weight: chosen ? .semibold : .medium))
                            .foregroundStyle(chosen ? Palette.text : Palette.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let badge = badges[option.id], badge > 0 {
                            Text("\(badge)")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(Palette.canvas)
                                .frame(minWidth: 16, minHeight: 16)
                                .padding(.horizontal, badge > 9 ? 3 : 0)
                                .background(badgeColor, in: Capsule())
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background {
                        if chosen {
                            Capsule()
                                .fill(Palette.field)
                                .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
                                .matchedGeometryEffect(id: "schieber", in: thumb)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("schalter-\(option.id)")
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Palette.text.opacity(0.07), in: Capsule())
        .padding(5)
        .glassEffect(.regular, in: .capsule)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: selection)
    }
}

/// Knöpfe geben beim Drücken etwas nach
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Gewählt: Ring 2,5 pt in Canvas, darum 2 pt in accent (TESS Personen Reihe)
struct SelectedRing: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(Palette.canvas, lineWidth: 2.5).padding(-2.5)
            Circle().strokeBorder(Palette.accent, lineWidth: 2).padding(-4.5)
        }
        .allowsHitTesting(false)
    }
}

/// Einmal kurz schütteln (falsches Passwort, etwas ging nicht raus), gleiche Kurve wie in der TESS App. Schüttelt bei jeder
/// neuen Zahl in `trigger`, also auch beim zweiten Fehler hintereinander.
struct Shake: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let still = reduceMotion
        return content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, offset in
            view.offset(x: still ? 0 : offset)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-9, duration: 0.07)
                CubicKeyframe(8, duration: 0.09)
                CubicKeyframe(-5, duration: 0.09)
                CubicKeyframe(2, duration: 0.08)
                CubicKeyframe(0, duration: 0.1)
            }
        }
    }
}

/// Weiße Karte auf dem Canvas wie die Aufgaben Gruppen in der TESS App
struct CardBox<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.line.opacity(0.6), lineWidth: 0.5))
    }
}

/// Überschrift eines Abschnitts: 22 pt fett, Zahl rechts leise (TESS „Jetzt 3“)
struct SectionTitle: View {
    let title: String
    var count: Int?
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.text)
                Spacer()
                if let count { Text("\(count)").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.muted) }
            }
            if let detail {
                Text(detail).font(.system(size: 15)).foregroundStyle(Palette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Feine Trennlinie zwischen Zeilen einer Karte
struct RowDivider: View {
    var leading: CGFloat = 0
    var body: some View {
        Rectangle().fill(Palette.line).frame(height: 0.5).padding(.leading, leading)
    }
}

/// Kapsel Knopf: dunkelgrün (Haupthandlung) oder Fläche
struct CapsuleButtonLabel: View {
    let title: String
    var symbol: String?
    var primary = false
    var destructive = false
    var height: CGFloat = 44

    var body: some View {
        HStack(spacing: 7) {
            if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)) }
            Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(primary ? Color.white : destructive ? Palette.overdue : Palette.text)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: height)
        .background(primary ? Palette.forest : Palette.surface, in: Capsule())
    }
}

/// „Made by Stagecraft“ unten mittig (Oles Schriftzug, ci/logos/made-by-stagecraft.svg, 110 × 25, 50 %)
struct MadeByStagecraft: View {
    var body: some View {
        Image("MadeBy")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 110, height: 25)
            .foregroundStyle(Palette.text)
            .opacity(0.5)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Made by Stagecraft")
    }
}

/// Zeile, die beim Wischen nach links eine rote Aktion freilegt (wie Apples Wischen in Listen, hier ohne List). Tippen auf die
/// Aktion oder ganz durchwischen löst sie aus, Tippen auf die offene Zeile schließt sie wieder. Senkrecht scrollt die Seite weiter.
struct SwipeReveal<Content: View>: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var start: CGFloat?
    @State private var armed = false
    private let width: CGFloat = 92

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                Haptics.press()
                close()
                action()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                    Text(title).font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(width: max(width, -offset), alignment: .center)
                .frame(maxHeight: .infinity)
                .background(Palette.overdue)
            }
            .buttonStyle(.plain)
            .opacity(offset < 0 ? 1 : 0)
            .accessibilityHidden(offset == 0)
            content
                .offset(x: offset)
                .overlay {
                    if offset < 0 {
                        Color.clear.contentShape(Rectangle()).offset(x: offset).onTapGesture(perform: close)
                    }
                }
        }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.4 || start != nil else { return }
                    if start == nil { start = offset }
                    let raw = (start ?? 0) + value.translation.width
                    offset = min(0, raw > -width * 2.2 ? raw : -width * 2.2 + (raw + width * 2.2) * 0.3)
                    let full = offset < -width * 1.9
                    if full != armed { armed = full; Haptics.select() }
                }
                .onEnded { value in
                    guard start != nil else { return }
                    start = nil
                    if armed {
                        armed = false
                        Haptics.press()
                        close()
                        action()
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            offset = offset < -width * 0.45 || value.predictedEndTranslation.width < -width ? -width : 0
                        }
                    }
                }
        )
        .accessibilityAction(named: title, action)
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { offset = 0 }
    }
}
