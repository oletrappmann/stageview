import SwiftUI

/// Anmeldung wie in der TESS App und im Admin Dashboard: Namen wählen, Passwort, dieselben Zugänge und Passwörter (Ole, Jonas,
/// Caspar, Niklas). Geprüft von der Brücke der TESS App, danach bleibt die App angemeldet, bis man im Konto Menü abmeldet oder
/// das Gerät in der TESS App gesperrt wird.
struct LoginView: View {
    @State private var store = Store.shared
    @State private var chosen: Access?
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var failures = 0
    @State private var float = false
    @FocusState private var passwordFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let spring = Animation.spring(response: 0.55, dampingFraction: 0.78)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StageViewWordmark(height: 16)
                .frame(height: 52)
                .padding(.leading, 22)

            Text("Wer bist du?")
                .font(.pageTitle)
                .tracking(-0.9)
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            Spacer(minLength: 12)

            // Groß das Zeichen, beim Tippen klein, damit die Tastatur Platz hat (wie die Kugel in der TESS App)
            StageViewMark(size: passwordFocused ? 72 : 168)
                .shadow(color: Palette.forest.opacity(0.35), radius: passwordFocused ? 10 : 30, y: passwordFocused ? 6 : 18)
                .offset(y: float && !reduceMotion && !passwordFocused ? -6 : 0)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .onAppear { withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { float = true } }

            Spacer(minLength: 12)

            VStack(spacing: 20) {
                HStack(spacing: 4) {
                    ForEach(Access.allCases) { access in
                        NameButton(access: access, selected: access == chosen) {
                            Haptics.select()
                            chosen = access
                            error = nil
                            passwordFocused = true
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                if chosen != nil {
                    passwordField.transition(.opacity.combined(with: .offset(y: 12)))
                }

                if let error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.text.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("anmeldung-hinweis")
                        .transition(.opacity)
                } else if chosen == nil {
                    Text("Gleiche Namen und Passwörter wie in der TESS App und im StageView Dashboard.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { passwordFocused = false }
        .animation(Self.spring, value: passwordFocused)
        .animation(Self.spring, value: chosen)
        .animation(.easeOut(duration: 0.2), value: error)
        .onAppear {
            if let last = UserDefaults.standard.string(forKey: "sv.zugang").flatMap(Access.init(rawValue:)) { chosen = last }
        }
    }

    private var passwordField: some View {
        SecureField("", text: $password, prompt: Text("Passwort").foregroundStyle(Palette.text.opacity(0.45)))
            .textContentType(.password)
            .submitLabel(.go)
            .focused($passwordFocused)
            .onSubmit(signIn)
            .font(.system(size: 17))
            .foregroundStyle(Palette.text)
            .padding(.leading, 20)
            .padding(.trailing, 56)
            .frame(height: 54)
            .glassEffect(.regular, in: Capsule())
            .accessibilityIdentifier("passwort")
            .overlay(alignment: .trailing) {
                Button(action: signIn) {
                    ZStack {
                        if busy {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(Palette.forest.opacity(password.isEmpty ? 0.3 : 1), in: Circle())
                }
                .buttonStyle(PressStyle(scale: 0.92))
                .disabled(password.isEmpty || busy)
                .padding(.trailing, 7)
                .accessibilityLabel("Anmelden")
                .accessibilityIdentifier("anmelden")
            }
            .modifier(Shake(trigger: failures))
    }

    private func signIn() {
        guard let chosen, !password.isEmpty, !busy else { return }
        busy = true
        error = nil
        Task {
            let failure = await store.signIn(chosen, password: password)
            busy = false
            if let failure {
                error = failure
                failures += 1
                Haptics.error()
            } else {
                password = ""
                Haptics.done()
            }
        }
    }
}

/// Name zum Antippen mit Gesicht, wie die Personen Kreise der TESS App
private struct NameButton: View {
    let access: Access
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                TeamAvatar(access: access, size: 68)
                    .overlay { if selected { SelectedRing() } }
                Text(access.person)
                    .font(.system(size: 15, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Palette.text : Palette.muted)
            }
            .frame(width: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .animation(.easeOut(duration: 0.18), value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(access.person)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("zugang-\(access.rawValue)")
    }
}
