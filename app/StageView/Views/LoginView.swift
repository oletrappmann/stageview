import SwiftUI

/// Anmeldung: nur die Profile, oben das Schriftlogo, ein grüner Verlauf (Ole, 22.11.2026: „es reicht, wenn man wirklich nur die
/// Profile sieht und oben das Stagecraft Logo und irgendwo diesen grünen Farbverlauf“). Gewählt: Entwurf 3, dunkle Bühne
/// (Ole, 22.11.2026). Gleiche Zugänge und Passwörter wie TESS App und Dashboard, geprüft von der Brücke der TESS App.
struct LoginView: View {
    @State private var store = Store.shared
    @State private var chosen: Access?
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var failures = 0
    @FocusState private var passwordFocused: Bool

    private static let spring = Animation.spring(response: 0.55, dampingFraction: 0.78)

    var body: some View {
        stage
        .contentShape(Rectangle())
        .onTapGesture { passwordFocused = false }
        .animation(Self.spring, value: passwordFocused)
        .animation(Self.spring, value: chosen)
        .animation(.easeOut(duration: 0.2), value: error)
        .onAppear {
            if let last = UserDefaults.standard.string(forKey: "sv.zugang").flatMap(Access.init(rawValue:)) { chosen = last }
            #if DEBUG
            if ProcessInfo.processInfo.environment["SV_DEMO"] == "anmeldung" { chosen = nil }
            #endif
        }
    }

    // MARK: Dunkle Bühne

    /// Dunkel wie der Player: oben STAGEVIEW in Weiß, in der Mitte ein bewegter grüner Schein (Mesh), die Profile davor, unten klein
    /// STAGE CRAFT
    private var stage: some View {
        VStack(spacing: 0) {
            wordmark(height: 24, color: .white).padding(.top, 26)
            Spacer()
            profiles(size: 70, names: .white)
                .background { GreenMesh().frame(width: 520, height: 420).blur(radius: 40).opacity(0.9) }
            Spacer()
            form.padding(.horizontal, 20).padding(.bottom, 18)
            Image("StagecraftLogo").resizable().renderingMode(.template).scaledToFit().frame(height: 10)
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .background(Palette.stage.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    // MARK: Bausteine

    private func wordmark(height: CGFloat, color: Color = Palette.text) -> some View {
        Image("Wortmarke").resizable().renderingMode(.template).scaledToFit()
            .frame(height: height)
            .foregroundStyle(color)
            .accessibilityLabel("StageView")
    }

    private func profiles(size: CGFloat, names: Color) -> some View {
        HStack(spacing: 4) {
            ForEach(Access.allCases) { access in
                NameButton(access: access, selected: access == chosen, size: passwordFocused ? size * 0.8 : size, names: names) { choose(access) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func choose(_ access: Access) {
        Haptics.select()
        chosen = access
        error = nil
        passwordFocused = true
    }

    private var form: some View {
        VStack(spacing: 14) {
            if chosen != nil {
                passwordField.transition(.opacity.combined(with: .offset(y: 12)))
            }
            if let error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("anmeldung-hinweis")
                    .transition(.opacity)
            }
        }
        .frame(minHeight: 54)
    }

    private var passwordField: some View {
        SecureField("", text: $password, prompt: Text(chosen.map { "Passwort für \($0.person)" } ?? "Passwort")
            .foregroundStyle(Color.white.opacity(0.45)))
            .textContentType(.password)
            .submitLabel(.go)
            .focused($passwordFocused)
            .onSubmit(signIn)
            .font(.system(size: 17))
            .foregroundStyle(Color.white)
            .padding(.leading, 20)
            .padding(.trailing, 56)
            .frame(height: 54)
            .glassEffect(.regular, in: Capsule())
            .accessibilityIdentifier("passwort")
            .overlay(alignment: .trailing) {
                Button(action: signIn) {
                    ZStack {
                        if busy { ProgressView().tint(.white) } else {
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

/// Grüner Verlauf als Mesh, bewegt sich ganz langsam (Stagecraft Grüntöne vom Forest bis Salbei)
struct GreenMesh: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate)
            let s = reduceMotion ? 0 : sin(t * 0.35) * 0.08, c = reduceMotion ? 0 : cos(t * 0.27) * 0.08
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5 + s, 0.5 + c], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: [
                Color(UIColor(hex: 0x2A302C)), Color(UIColor(hex: 0x48514A)), Color(UIColor(hex: 0x6A7B6D)),
                Color(UIColor(hex: 0x48514A)), Color(UIColor(hex: 0x93AA98)), Color(UIColor(hex: 0x5F8068)),
                Color(UIColor(hex: 0x6A7B6D)), Color(UIColor(hex: 0x3A443D)), Color(UIColor(hex: 0x2A302C)),
            ])
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Profil zum Antippen: Gesicht und Name, gewählt mit Ring wie in der TESS App
private struct NameButton: View {
    let access: Access
    let selected: Bool
    var size: CGFloat = 68
    var names: Color = Palette.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                TeamAvatar(access: access, size: size)
                    .overlay { if selected { SelectedRing() } }
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                Text(access.person)
                    .font(.system(size: 15, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? names : names.opacity(0.6))
            }
            .frame(minWidth: 84)
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
