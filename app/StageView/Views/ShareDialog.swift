import SwiftUI

/// Was das Teilen Fenster zeigt: ein Video (mit Stelle) oder alle Videos eines Links
struct ShareRequest: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var subtitle: String
    var url: URL
    /// Sekunde im Video, ab 2 s bietet das Fenster „Ab 0:12 starten“ an
    var time: Int = 0
}

/// Teilen Fenster wie auf der Videoseite (projekt.html, teilen-dialog, Ole 13.11.2026 und 22.11.2026: „wie im Web das Popup“):
/// Titel, wer bzw. welches Video, der Link ganz (ohne https://), auf Wunsch ab der Stelle, Hinweis, großer weißer Knopf
/// „Link kopieren“, danach grün „Kopiert“. Kein Teilen über Apps (Ole). Tipp daneben oder auf das X schließt.
struct ShareDialog: View {
    let request: ShareRequest
    let close: () -> Void

    @State private var fromTime = false
    @State private var copied = false
    @State private var shown = false
    @State private var resetTask: Task<Void, Never>?

    private static let panel = Color(UIColor(hex: 0x1E1E1C))
    private static let panel2 = Color(UIColor(hex: 0x2A2A27))
    private static let accent = Color(UIColor(hex: 0x93AA98))

    private var link: URL {
        guard fromTime, request.time > 1 else { return request.url }
        return URL(string: request.url.absoluteString + "?t=\(request.time)") ?? request.url
    }

    var body: some View {
        ZStack {
            // Dahinter weich und abgedunkelt wie im Web (backdrop: blur 4px, schwarz 45 %)
            Rectangle().fill(.ultraThinMaterial).opacity(shown ? 0.85 : 0)
                .overlay(Color.black.opacity(shown ? 0.35 : 0))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
                .accessibilityHidden(true)
            card
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.98)
                .offset(y: shown ? 0 : 10)
        }
        .onAppear { withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.24)) { shown = true } }
        .environment(\.colorScheme, .dark)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(request.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(UIColor(hex: 0xF3F2EE)))
                .padding(.trailing, 44)
                .accessibilityAddTraits(.isHeader)
            Text(request.subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Color(UIColor(hex: 0xF3F2EE)).opacity(0.56))
                .lineLimit(1)
                .padding(.top, 4)
                .padding(.trailing, 44)
            // Der Link steht immer ganz da, kopiert wird der volle Link
            Text(link.absoluteString.replacingOccurrences(of: "https://", with: ""))
                .font(.system(size: 15))
                .foregroundStyle(Color(UIColor(hex: 0xF3F2EE)).opacity(0.56))
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Self.panel2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 18)
                .accessibilityIdentifier("teilen-link")
            if request.time > 1 {
                Button {
                    Haptics.select()
                    fromTime.toggle()
                    resetCopied()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: fromTime ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundStyle(fromTime ? Self.accent : Color.white.opacity(0.5))
                        Text("Ab \(Clock.text(Double(request.time))) starten")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(UIColor(hex: 0xF3F2EE)))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                .accessibilityAddTraits(fromTime ? .isSelected : [])
                .accessibilityIdentifier("teilen-ab-stelle")
            }
            Text("Jeder mit dem Link kann die Videos ansehen und kommentieren.")
                .font(.system(size: 13))
                .foregroundStyle(Color(UIColor(hex: 0xF3F2EE)).opacity(0.36))
                .padding(.top, 14)
            Button(action: copy) {
                HStack(spacing: 8) {
                    Image(systemName: copied ? "checkmark" : "link").font(.system(size: 17, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(copied ? "Kopiert" : "Link kopieren").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(copied ? Color(UIColor(hex: 0x10130F)) : Color(UIColor(hex: 0x1C1C1E)))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(copied ? Self.accent : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .animation(.easeOut(duration: 0.15), value: copied)
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .padding(.top, 18)
            .accessibilityIdentifier("teilen-kopieren")
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: 460)
        .background(Self.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(UIColor(hex: 0xF3F2EE)))
                    .frame(width: 36, height: 36)
                    .background(Self.panel2, in: Circle())
            }
            .buttonStyle(PressStyle(scale: 0.92))
            .padding(14)
            .accessibilityLabel("Schließen")
            .accessibilityIdentifier("teilen-zu")
        }
        .shadow(color: .black.opacity(0.4), radius: 40, y: 30)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func copy() {
        UIPasteboard.general.url = link
        Haptics.done()
        copied = true
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }

    private func resetCopied() {
        resetTask?.cancel()
        copied = false
    }

    private func dismiss() {
        Haptics.select()
        withAnimation(.easeOut(duration: 0.18)) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            close()
        }
    }
}
