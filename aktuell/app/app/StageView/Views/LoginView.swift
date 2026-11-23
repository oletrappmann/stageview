import SwiftUI

/// Anmeldung: nur die Profile, oben das Schriftlogo, ein grüner Verlauf (Ole, 22.11.2026: „es reicht, wenn man wirklich nur die
/// Profile sieht und oben das Stagecraft Logo und irgendwo diesen grünen Farbverlauf“). Gewählt: Entwurf 3, dunkle Bühne
/// (Ole, 22.11.2026). Gleiche Zugänge und Passwörter wie TESS App und Dashboard, geprüft von der Brücke der TESS App.
/// Seit 23.11.2026 kommen die Konten aus der Liste von StageHub (`Profiles`), angeordnet wie dort: je vier pro Seite, ab dem
/// fünften zum Wischen mit Punkten darunter und weichem Rand (Ole: „kleiner Fade am Rand, Anordnung, Profilbilder … ein System“).
struct LoginView: View {
    @State private var store = Store.shared
    @State private var profiles = Profiles.shared
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
            if ProcessInfo.processInfo.environment["SV_DEMO"] == "anmeldung" {
                chosen = ProcessInfo.processInfo.environment["SV_GEWAEHLT"].flatMap(Access.init(rawValue:))
            }
            #endif
        }
        .task { await profiles.refresh() }
        // Neue Liste: gewähltes Konto mit frischem Namen und Bild, verschwundenes abwählen
        .onChange(of: profiles.all) { _, list in
            if let current = chosen { chosen = list.first { $0.rawValue == current.rawValue } }
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
        ProfilePages(profiles: profiles.all, chosen: chosen, size: size, names: names) { choose($0) }
    }

    private func choose(_ access: Access) {
        Haptics.select()
        // Ring und Name in einer Feder, gleich beim Antippen. Die Bilder behalten ihre Größe (Ole, 22.11.2026: der Ring stand
        // kurz allein): vorher schrumpften sie mit dem Fokus, gleichzeitig schob die Tastatur alles hoch, zwei Bewegungen übereinander
        withAnimation(Self.spring) {
            chosen = access
            error = nil
        }
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
                // Der Ring ist immer da und fährt mit dem Bild in derselben Feder mit (Ole, 22.11.2026: vorher kam er erst beim
                // Antippen dazu und stand kurz allein an der Endstelle, während das Bild noch hochfuhr). Nie ganz unsichtbar:
                // bei Deckkraft 0 merkt sich SwiftUI seine Lage nicht und er springt beim Einblenden sofort ans Ziel
                TeamAvatar(access: access, size: size)
                    .overlay {
                        SelectedRing()
                            .opacity(selected ? 1 : 0.001)
                            .scaleEffect(selected ? 1 : 0.86)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                // Fett wird fließend (interpolate): sonst blendet iOS den alten Namen an der alten Stelle aus und er hängt kurz unten
                Text(access.person)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .font(.system(size: 15))
                    .fontWeight(selected ? .semibold : .medium)
                    .contentTransition(.interpolate)
                    .foregroundStyle(selected ? names : names.opacity(0.6))
            }
            .frame(width: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(access.person)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("zugang-\(access.rawValue)")
    }
}

/// Konten in Seiten zu je vier wie bei StageHub (TESS App `ProfilePages`, Webseite `anmeldeSeiten`): bis vier eine Zeile ohne
/// Wischen, ab dem fünften weitere Seiten dahinter, darunter Punkte (antippbar), links und rechts ein weicher Rand, der in Ruhe
/// neben den Gesichtern liegt und nur beim Wischen auf ihnen (wie die Maske auf der Webseite, 22 pt). Eine halbe letzte Seite
/// steht mittig. Beim Öffnen steht die Seite mit dem gewählten Konto vorn.
private struct ProfilePages: View {
    let profiles: [Access]
    let chosen: Access?
    var size: CGFloat
    var names: Color
    let choose: (Access) -> Void

    static let perPage = 4
    @State private var page: Int? = 0

    private var pages: [[Access]] {
        stride(from: 0, to: profiles.count, by: Self.perPage).map { Array(profiles[$0..<min($0 + Self.perPage, profiles.count)]) }
    }

    var body: some View {
        let pages = pages
        VStack(spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { index in
                        HStack(spacing: 4) {
                            ForEach(pages[index]) { access in
                                NameButton(access: access, selected: access.rawValue == chosen?.rawValue, size: size, names: names) { choose(access) }
                            }
                        }
                        // Platz für den Ring, die Seite schneidet sonst ab
                        .padding(.vertical, 6)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $page)
            .scrollDisabled(pages.count < 2)
            .mask {
                if pages.count > 1 {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 22)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 22)
                    }
                } else {
                    Color.black
                }
            }
            .accessibilityIdentifier("profile")

            if pages.count > 1 {
                PageDots(count: pages.count, current: page ?? 0) { target in
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { page = target }
                }
            }
        }
        .onAppear { showChosen(animated: false) }
        .onChange(of: profiles) { _, _ in showChosen(animated: false) }
        // Die gemerkte Wahl kommt erst nach dem ersten Zeichnen (onAppear der Anmeldung), dann zu ihrer Seite
        .onChange(of: chosen?.rawValue) { _, _ in showChosen(animated: true) }
    }

    private func showChosen(animated: Bool) {
        guard let chosen, let index = profiles.firstIndex(where: { $0.rawValue == chosen.rawValue }) else { return }
        let target = index / Self.perPage
        guard target != (page ?? 0) else { return }
        if animated { withAnimation { page = target } } else { page = target }
    }
}

/// Punkte unter den Konten, einer pro Seite, der aktuelle hell (wie bei StageHub)
private struct PageDots: View {
    let count: Int
    let current: Int
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Button { select(index) } label: {
                    Circle()
                        .fill(Color.white.opacity(index == current ? 0.75 : 0.2))
                        .frame(width: 7, height: 7)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seite \(current + 1) von \(count)")
        .accessibilityIdentifier("profil-seiten")
    }
}
