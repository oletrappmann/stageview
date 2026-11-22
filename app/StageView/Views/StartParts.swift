import SwiftUI

// Gemeinsame Teile der Startseite: Kopf mit Suche und Konto, Kennzahlen, Ring der Freigabe, Marke offener Kommentare.
// Designsprache wie die TESS App (Glas, Farben, Haptik), Aufbau eigenständig (Ole, 22.11.2026).

extension Store {
    /// Links eines Kunden, neueste Aktivität zuerst
    func projects(of customer: Customer) -> [Project] {
        projects.filter { customer.owns($0) }.sorted { ($0.lastActivity ?? $0.created ?? "") > ($1.lastActivity ?? $1.created ?? "") }
    }

    /// Neueste offene Kommentare über alle Links
    func latestComments(_ limit: Int) -> [(project: Project, comment: OpenComment)] {
        let all = projects.flatMap { p in p.openComments.map { (p, $0) } }
        return Array(all.sorted { ($0.1.created ?? "") > ($1.1.created ?? "") }.prefix(limit))
    }

    struct Totals { var openComments = 0, changes = 0, pending = 0, approved = 0, videos = 0, doneLinks = 0 }

    var totals: Totals {
        var t = Totals()
        for p in customerScoped {
            t.openComments += p.openCount
            t.changes += p.changes
            t.approved += p.approved
            t.videos += p.videos.count
            t.pending += p.videos.count - p.approved - p.changes
            if p.allApproved { t.doneLinks += 1 }
        }
        return t
    }

    /// Links des gewählten Kunden (oder alle), ohne Ansicht und Suche
    var customerScoped: [Project] { customer.map { c in projects.filter { c.owns($0) } } ?? projects }
}

// MARK: Kopf

/// Grüner Verlauf oben wie in der Kundenansicht und auf der Webseite (Ole, 22.11.2026: „ein grüner Ambient Farbverlauf“, dann
/// „weiter nach unten, ohne Unterbrechung von der Nav Bar, ein bisschen mehr reinstrahlen bei den Meldungen oder der Überschrift“).
/// Fest am oberen Bildschirmrand hinter der ganzen Startseite und noch einmal gleich im Kopf, so gibt es keine Kante
struct StartGlow: View {
    static let height: CGFloat = 560

    var body: some View {
        HeroGlow()
            .frame(height: Self.height)
            .offset(y: -30)
            .opacity(0.95)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Kopf der Startseite: StageView links, rechts Suche und das eigene Gesicht (Konto Menü). Beim Suchen wird daraus ein Glasfeld.
struct StartTopBar: View {
    @Binding var searching: Bool
    var customers: () -> Void
    @State private var store = Store.shared
    @State private var confirmSignOut = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if searching {
                    searchField.transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                } else {
                    HStack(spacing: 10) {
                        StageViewWordmark(height: 15)
                        Spacer()
                        Button {
                            Haptics.select()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { searching = true }
                            focused = true
                        } label: { GlassCircle(symbol: "magnifyingglass", size: 44, symbolSize: 17) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Suchen")
                            .accessibilityIdentifier("suchen")
                        account
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            if !Connection.shared.online { OfflineCapsule().transition(.opacity) }
        }
        .background(alignment: .top) {
            // Kopf zeigt denselben Grund wie die Seite (Dunkel plus StartGlow an derselben Stelle), nur nach unten weich
            // auslaufend: Inhalt darunter verschwindet sanft, der grüne Verlauf läuft ohne Kante weiter
            // Der Kopf behält seine Höhe, der Grund liegt als Überhang darin und wird von der weichen Kante beschnitten
            Color.clear
                .overlay(alignment: .top) {
                    Palette.canvas.frame(height: StartGlow.height).overlay(alignment: .top) { StartGlow() }
                }
                .ignoresSafeArea(edges: .top)
                .mask { TopEdge(color: .black) }
                .allowsHitTesting(false)
        }
        .centerConfirm("Abmelden?", isPresented: $confirmSignOut, action: "Abmelden", symbol: "rectangle.portrait.and.arrow.right",
                       message: { "Dieses iPhone wird auch in der TESS App abgemeldet. Danach braucht es wieder Name und Passwort." }) {
            Task { await store.signOut() }
        }
    }

    private var account: some View {
        Menu {
            Section {
                Button(action: customers) { Label("Kunden verwalten", systemImage: "person.2") }
                Link(destination: URL(string: "https://videos.stagecraft.media/admin")!) { Label("Dashboard im Browser", systemImage: "safari") }
            }
            Section("Angemeldet als \(store.me?.name ?? "")") {
                Button(role: .destructive) { confirmSignOut = true } label: { Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right") }
            }
            Section("StageView \(AppInfo.version) · \(AppInfo.built)") {}
        } label: {
            Group {
                if let access = store.me.flatMap({ Access(rawValue: $0.zugang) }) {
                    TeamAvatar(access: access, size: 36)
                } else {
                    Image(systemName: "person.fill").font(.system(size: 16)).frame(width: 36, height: 36)
                }
            }
            .padding(4)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.select() })
        .accessibilityLabel("Konto")
        .accessibilityIdentifier("konto")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.muted)
            TextField("", text: $store.search, prompt: Text("Titel, Kunde, Code oder Link").foregroundStyle(Palette.faint))
                .font(.system(size: 17))
                .foregroundStyle(Palette.text)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("suchfeld")
                // Einen StageView Link eingefügt: direkt öffnen wie im Browser, die Suche geht zu
                .onChange(of: store.search) { _, text in
                    guard text.contains("videos.stagecraft.media/") || text.hasPrefix("stageview://"), store.openLink(in: text) else { return }
                    Haptics.press()
                    store.search = ""
                    focused = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { searching = false }
                }
            Button {
                Haptics.select()
                store.search = ""
                focused = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { searching = false }
            } label: {
                Text("Fertig").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    .padding(.horizontal, 14).frame(height: 36).background(Palette.surface, in: Capsule())
            }
            .buttonStyle(PressStyle())
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 48)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: Bausteine

/// Ring mit Anteil freigegeben (Änderungen warm), Zahl in der Mitte
struct ApprovalRing: View {
    let project: Project
    var size: CGFloat = 40

    var body: some View {
        let total = CGFloat(max(project.videos.count, 1))
        ZStack {
            Circle().stroke(Palette.surface, lineWidth: 4)
            Circle().trim(from: 0, to: CGFloat(project.approved) / total)
                .stroke(Palette.approvedInk, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle().trim(from: CGFloat(project.approved) / total, to: CGFloat(project.approved + project.changes) / total)
                .stroke(Palette.changesInk, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(project.approved)/\(project.videos.count)")
                .font(.system(size: size * 0.26, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.text)
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(project.approved) von \(project.videos.count) freigegeben")
    }
}

/// Kleine Marke mit offenen Kommentaren (warm)
struct OpenBadge: View {
    let count: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "text.bubble.fill").font(.system(size: 10, weight: .bold))
            Text("\(count)").font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Palette.changes, in: Capsule())
        .accessibilityLabel(Plural.count(count, "offener Kommentar", "offene Kommentare"))
    }
}

extension Project {
    /// Kommentare insgesamt und davon erledigt (Feedback statt Freigabe, Ole 22.11.2026)
    var feedbackTotal: Int { videos.reduce(0) { $0 + $1.comments } }
    var feedbackDone: Int { max(0, feedbackTotal - openCount) }
}

/// Rechts in der Zeile eines Links: offene Kommentare, „erledigt“ oder „kein Feedback“ (Ole, 22.11.2026: „die Zahl, wie viele
/// Videos freigegeben sind, entfernen, etwas Brauchbares hin“). Gleich wie die Spalte Feedback im Admin Dashboard.
struct FeedbackMark: View {
    let project: Project

    var body: some View {
        let open = project.openCount, total = project.feedbackTotal
        VStack(spacing: 2) {
            if open > 0 {
                Text("\(open)").font(.system(size: 18, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.changesInk)
                Text("offen").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
            } else if total > 0 {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 19)).foregroundStyle(Palette.approvedInk)
                Text("erledigt").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
            } else {
                Image(systemName: "bubble.left").font(.system(size: 16)).foregroundStyle(Palette.faint)
                Text("kein Feedback").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Palette.faint)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
        }
        .frame(width: 62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(open > 0 ? "\(open) offene Kommentare" : total > 0 ? "Feedback erledigt" : "Noch kein Feedback")
    }
}
