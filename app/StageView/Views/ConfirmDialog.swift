import SwiftUI

/// Rückfragen wie „Link löschen?“ genau in der Mitte (Ole, 22.11.2026: „diese extra Sicherheit Popups genau in die Mitte und nicht
/// so komisch auf dem Bildschirm verteilt“). Apples confirmationDialog legt auf dem iPhone ein Blatt unten an, das hier ersetzt
/// ein eigenes Fenster im Stil des Teilen Fensters: abgedunkelt dahinter, Symbol, Frage, Text, roter Knopf, darunter Abbrechen.
/// Tipp daneben bricht ab. Läuft über ein durchsichtiges Vollbild, damit es auch über Navigationsleiste, Blättern und Sheets liegt.
struct ConfirmContent: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var action: String
    var symbol: String
    var destructive: Bool
    var perform: () -> Void
}

extension View {
    /// Wie confirmationDialog, nur mittig. `perform` läuft, nachdem das Fenster zu ist.
    func centerConfirm(_ title: String, isPresented: Binding<Bool>, action: String, symbol: String = "trash", destructive: Bool = true,
                       message: @escaping () -> String, perform: @escaping () -> Void) -> some View {
        modifier(CenterConfirmModifier(isPresented: isPresented) {
            ConfirmContent(title: title, message: message(), action: action, symbol: symbol, destructive: destructive, perform: perform)
        })
    }

    /// Variante für „welches Video, welcher Kunde“: der Wert wird beim Öffnen festgehalten und an `perform` gegeben
    func centerConfirm<Item>(_ title: String, item: Binding<Item?>, action: String, symbol: String = "trash", destructive: Bool = true,
                             message: @escaping (Item) -> String, perform: @escaping (Item) -> Void) -> some View {
        let shown = Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
        return modifier(CenterConfirmModifier(isPresented: shown) {
            let value = item.wrappedValue
            return ConfirmContent(title: title, message: value.map(message) ?? "", action: action, symbol: symbol, destructive: destructive,
                                  perform: { if let value { perform(value) } })
        })
    }
}

private struct CenterConfirmModifier: ViewModifier {
    @Binding var isPresented: Bool
    let make: () -> ConfirmContent
    /// Mit festem Inhalt (item), sonst liest das Vollbild den Inhalt beim ersten Mal zu früh und bleibt schwarz
    @State private var current: ConfirmContent?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, now in
                // Ohne Apples Hochfahren, das Fenster blendet sich selbst ein
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { current = now ? make() : nil }
            }
            .fullScreenCover(item: $current) { shown in
                ConfirmDialog(content: shown) { confirmed in
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { current = nil }
                    isPresented = false
                    if confirmed { shown.perform() }
                }
                .presentationBackground(.clear)
            }
    }
}

struct ConfirmDialog: View {
    let content: ConfirmContent
    let finish: (Bool) -> Void
    @State private var shown = false
    @State private var closing = false

    private static let panel = Color(UIColor(hex: 0x1E1E1C))
    private static let panel2 = Color(UIColor(hex: 0x2A2A27))
    private static let ink = Color(UIColor(hex: 0xF3F2EE))

    private var tint: Color { content.destructive ? Palette.overdue : Color(UIColor(hex: 0x93AA98)) }

    var body: some View {
        ZStack {
            // Dahinter weich und abgedunkelt wie beim Teilen Fenster
            Rectangle().fill(.ultraThinMaterial).opacity(shown ? 0.85 : 0)
                .overlay(Color.black.opacity(shown ? 0.4 : 0))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close(false) }
                .accessibilityHidden(true)
            card
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.94)
        }
        .onAppear { withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.26)) { shown = true } }
        .environment(\.colorScheme, .dark)
    }

    private var card: some View {
        VStack(spacing: 0) {
            Image(systemName: content.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 54, height: 54)
                .background(tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            Text(content.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Self.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)
            if !content.message.isEmpty {
                Text(content.message)
                    .font(.system(size: 14))
                    .foregroundStyle(Self.ink.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            VStack(spacing: 10) {
                Button { close(true) } label: {
                    Text(content.action)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(content.destructive ? Color.white : Color(UIColor(hex: 0x1C1C1E)))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(content.destructive ? Palette.overdue : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressStyle(scale: 0.98))
                .accessibilityIdentifier("rueckfrage-ja")
                Button { close(false) } label: {
                    Text("Abbrechen")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Self.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Self.panel2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressStyle(scale: 0.98))
                .accessibilityIdentifier("rueckfrage-nein")
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .frame(maxWidth: 380)
        .background(Self.panel, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.45), radius: 40, y: 26)
        .padding(.horizontal, 28)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("rueckfrage")
    }

    private func close(_ confirmed: Bool) {
        guard !closing else { return }
        closing = true
        if !confirmed { Haptics.select() }
        withAnimation(.easeOut(duration: 0.16)) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(170))
            finish(confirmed)
        }
    }
}
