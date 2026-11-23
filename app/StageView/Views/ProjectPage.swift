import SwiftUI

/// Seite eines Links: alles aus dem Fenster „Projekt“ im Dashboard. Link teilen und ansehen, Freigabe, Videos (Tipp spielt sofort,
/// langes Drücken: Titel ändern, von der Seite nehmen), Videos dazu, offene Kommentare, Titel und Kunde bearbeiten, Link löschen.
struct ProjectPage: View {
    let key: String
    @Binding var path: [Route]
    @State private var store = Store.shared
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var renaming: Video?
    @State private var renameText = ""
    @State private var removing: Video?
    /// Freigabe eines Videos ändern (mittiges Fenster) und „Alle freigeben“ (Ole, 23.11.2026)
    @State private var choosingStatus: Video?
    @State private var confirmAll = false
    @State private var sources = ""
    @State private var addTitle = ""
    @State private var addOpen = false
    @Environment(\.zoomSpace) private var zoom
    @Environment(\.dismiss) private var dismiss

    private var project: Project? { store.project(key) }

    var body: some View {
        Group {
            if let project {
                content(project)
            } else {
                Text("Dieser Link ist nicht mehr da.")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let project {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.select()
                        editing = true
                    } label: { Image(systemName: "pencil") }
                        .accessibilityLabel("Bearbeiten")
                        .accessibilityIdentifier("projekt-bearbeiten")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        LinkMenuItems(project: project, client: { path.switchTo(.client(key)) }, delete: { confirmDelete = true })
                    } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("Mehr")
                        .accessibilityIdentifier("projekt-mehr")
                }
            }
        }
        .sheet(isPresented: $editing) { if let project { ProjectEditSheet(project: project) } }
        .centerConfirm("Link löschen?", isPresented: $confirmDelete, action: "Link löschen", message: { DeleteText.link(project) }) {
            guard let project else { return }
            Haptics.cancel()
            Task { if await store.deleteLink(project) { dismiss() } }
        }
        .centerConfirm("Von der Seite nehmen?", item: $removing, action: "Von der Seite nehmen", symbol: "rectangle.badge.minus",
                       message: { video in
                           "„\(video.title)“ verschwindet von der Seite. Das Video im Drive, bei Mux und alle Kommentare bleiben, die Nummer \(video.nr) wird nie neu vergeben."
                       }) { video in
            guard let project else { return }
            Haptics.cancel()
            Task { await store.removeVideo(project, video) }
        }
        .statusChooser($choosingStatus, current: { video in project.flatMap { $0.code }.map { ReviewStore.of($0).status(of: video) } ?? video.status }) { video, status in
            guard let code = project?.code else { return }
            status == .approved ? Haptics.check() : Haptics.select()
            Task { await ReviewStore.of(code).setStatus(status, for: video) }
        }
        .centerConfirm("Alle freigeben?", isPresented: $confirmAll, action: "Alle freigeben", symbol: "checkmark.seal.fill", destructive: false,
                       message: { approveAllText }) {
            guard let project, let code = project.code else { return }
            Haptics.check()
            Task {
                await ReviewStore.of(code).setStatus(.approved, for: project.videos)
                store.show("Alle freigegeben", symbol: "checkmark.seal.fill")
            }
        }
        .alert("Titel ändern", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Titel", text: $renameText)
            Button("Abbrechen", role: .cancel) {}
            Button("Speichern") {
                guard let project, let video = renaming else { return }
                Task { await store.renameVideo(project, video, to: renameText) }
            }
        } message: { Text("So heißt das Video auf der Seite. Der Link bleibt gleich.") }
        #if DEBUG
        .onAppear { if Demo.opensEditor { editing = true } }
        #endif
    }

    private func content(_ project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(project)
                // Ein einzelnes Video (Ole, 22.11.2026): gleich oben groß, darunter Link öffnen, Safari usw.
                linkBox(project, hero: project.videos.count == 1 ? project.videos.first : nil).padding(.top, 18)
                if !project.videos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        // Feedback statt Freigabe (Ole, 22.11.2026), gleich wie im Admin Dashboard
                        let total = project.feedbackTotal, open = project.openCount, done = project.feedbackDone
                        if total > 0 {
                            GeometryReader { g in
                                HStack(spacing: 2) {
                                    if done > 0 { Capsule().fill(Palette.approved).frame(width: max(4, (g.size.width - (open > 0 ? 2 : 0)) * CGFloat(done) / CGFloat(total))) }
                                    if open > 0 { Capsule().fill(Palette.pending) }
                                }
                            }
                            .frame(height: 8)
                        }
                        Text(total == 0 ? "Noch kein Feedback" : open == 0 ? "Feedback erledigt · \(Plural.count(total, "Kommentar", "Kommentare"))"
                             : "\(done) von \(total) Kommentaren erledigt · \(open) offen")
                            .font(.system(size: 15)).foregroundStyle(Palette.muted)
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 4)
                }
                ForEach(store.runningJobs(for: project.code)) { job in
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.kindTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                            Text(job.readable).font(.system(size: 13)).foregroundStyle(Palette.muted)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.top, 14)
                }


                if project.videos.count != 1 {
                    videosTitle(project).padding(.top, 30).padding(.horizontal, 4)
                    videos(project).padding(.top, 10)
                }
                if let note = project.driveNote {
                    Label(note.hasSuffix(".") ? note : note + ".", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.changesInk)
                        .padding(.top, 10)
                        .padding(.horizontal, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !project.driveGone.isEmpty {
                    Text("Nicht mehr im Drive, deshalb ausgeblendet: \(project.driveGone.map { "„\($0)“" }.joined(separator: ", ")). Liegt ein Video wieder im Ordner, ist es von selbst zurück.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 10)
                        .padding(.horizontal, 4)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("drive-weg")
                }
                if project.waiting > 0 {
                    Text("\(Plural.count(project.waiting, "Video ist", "Videos sind")) noch bei Mux und \(project.waiting == 1 ? "erscheint" : "erscheinen") gleich von selbst.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                }

                // Offene Kommentare unter den Videos (Ole, 23.11.2026)
                if !project.openComments.isEmpty {
                    SectionTitle(title: "Offene Kommentare", count: project.openComments.count).padding(.top, 30).padding(.horizontal, 4)
                    comments(project).padding(.top, 10)
                }

                if project.code != nil {
                    driveRow(project).padding(.top, 30)
                    Button {
                        Haptics.select()
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { addOpen.toggle() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Palette.text)
                                .frame(width: 34, height: 34)
                                .background(Palette.surface, in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Videos dazu").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                                Text("Neue Schnittfassung? Die alte bleibt mit ihren Kommentaren stehen, solange sie im Drive liegt.")
                                    .font(.system(size: 13)).foregroundStyle(Palette.muted).lineLimit(2).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.faint)
                                .rotationEffect(.degrees(addOpen ? 0 : -90))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 22)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("videos-dazu")
                    if addOpen {
                        addBox(project).padding(.top, 10).transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                if project.code != nil {
                    deleteBox(project).padding(.top, 34)
                }
                MadeByStagecraft().padding(.top, 30)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.refresh(quiet: false) }
    }

    // MARK: Kopf

    private func header(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.title)
                .font(.pageTitle)
                .tracking(-0.9)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("projekt-titel")
            HStack(spacing: 8) {
                CustomerAvatar(name: project.customerName, size: 24)
                Text([project.customerName, project.company, project.shootDate.flatMap { When.dayText($0).map { "Dreh " + $0 } } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
            if !project.note.isEmpty {
                Text(project.note)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func linkBox(_ project: Project, hero: Video? = nil) -> some View {
        CardBox {
            VStack(alignment: .leading, spacing: 12) {
                if let hero {
                    heroVideo(project, hero)
                }
                // Der Link öffnet die Kundenansicht wie im Web (Ole, 22.11.2026)
                Button {
                    guard project.code != nil else { return }
                    Haptics.select()
                    path.switchTo(.client(project.key))
                } label: {
                    HStack(spacing: 8) {
                        StageViewMark(size: 26)
                        Text(project.shortLink)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(project.code != nil ? Palette.accent : Palette.text)
                            .underline(project.code != nil, color: Palette.accent.opacity(0.4))
                            .lineLimit(1)
                        Spacer()
                        if project.code != nil {
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.faint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kundenansicht öffnen, \(project.shortLink)")
                .accessibilityIdentifier("link-kundenansicht")
                if let link = project.link {
                    HStack(spacing: 8) {
                        Button {
                            Haptics.press()
                            path.switchTo(.client(project.key))
                        } label: {
                            CapsuleButtonLabel(title: hero == nil ? "Projekt anzeigen" : "Link öffnen",
                                               symbol: hero == nil ? "rectangle.grid.2x2" : "arrow.up.forward.app", primary: true)
                        }
                            .buttonStyle(PressStyle())
                            .disabled(project.videos.isEmpty)
                            .accessibilityIdentifier("projekt-anzeigen")
                        CopyButton(link: link, round: true)
                        ShareLink(item: link) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Palette.text)
                                .frame(width: 44, height: 44)
                                .background(Palette.surface, in: Circle())
                        }
                        .buttonStyle(PressStyle())
                        .simultaneousGesture(TapGesture().onEnded { Haptics.select() })
                        .accessibilityLabel("Teilen")
                        Link(destination: link) {
                            Image(systemName: "safari")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Palette.text)
                                .frame(width: 44, height: 44)
                                .background(Palette.surface, in: Circle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("In Safari öffnen")
                    }
                } else {
                    Text("Der Link entsteht, sobald Mux die Videos vorbereitet hat.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }

    // MARK: Ein Video groß

    /// Das einzige Video eines Links groß oben (Ole, 22.11.2026). Tipp spielt es, langes Drücken oder ⋯ hat alles aus der Videozeile
    private func heroVideo(_ project: Project, _ video: Video) -> some View {
        let play = {
            Haptics.press()
            store.play(project, video, source: "projekt-\(video.id)")
        }
        let status = project.code.map { ReviewStore.of($0).status(of: video) } ?? video.status
        return VStack(alignment: .leading, spacing: 12) {
            Color.clear
                .aspectRatio(video.portrait ? 4 / 5 : max(video.aspect, 1), contentMode: .fit)
                .overlay {
                    GeometryReader { g in
                        ZStack {
                            // Hochkant im Rahmen: dahinter die Bildmitte groß und weich als Licht, vorne das ganze Bild
                            RemoteImage(url: video.thumbnail(width: 200), placeholder: Palette.surface)
                                .blur(radius: 30)
                                .saturation(1.6)
                                .brightness(0.04)
                                .scaleEffect(video.portrait ? 2.2 : 1.3)
                            RemoteImage(url: video.thumbnail(width: 900), placeholder: .clear)
                                .frame(width: min(g.size.width, g.size.height * video.aspect),
                                       height: min(g.size.height, g.size.width / max(video.aspect, 0.1)))
                        }
                        .frame(width: g.size.width, height: g.size.height)
                    }
                }
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: 2)
                        .frame(width: 68, height: 68)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .overlay(alignment: .bottomLeading) {
                    Text(Clock.text(video.duration))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .zoomSource("projekt-\(video.id)", zoom)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture(perform: play)
                .contextMenu { videoMenu(project, video) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(video.title) abspielen")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default, play)
                .accessibilityIdentifier("einzelvideo")
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    if video.title != project.title {
                        Text(video.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        StatusPill(status: status) { choosingStatus = video }
                        if video.open > 0 {
                            Text("· \(Plural.count(video.open, "offen", "offen"))").foregroundStyle(Palette.changesInk).fontWeight(.semibold)
                        }
                    }
                    .font(.system(size: 13))
                }
                Spacer(minLength: 4)
                Menu { videoMenu(project, video) } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .frame(width: 36, height: 36)
                        .background(Palette.surface, in: Circle())
                }
                .accessibilityLabel("Mehr zum Video")
                .accessibilityIdentifier("einzelvideo-mehr")
            }
            Divider().overlay(Palette.line.opacity(0.6)).padding(.vertical, 2)
        }
    }

    // MARK: Drive

    /// Drive abgleichen (Ole, 22.11.2026): holt neue Videos aus dem Ordner. Was nicht mehr im Drive liegt, nimmt der Server
    /// sowieso alle 5 Minuten von der Seite.
    private func driveRow(_ project: Project) -> some View {
        let busy = store.isSyncingDrive(project)
        return Button {
            guard !busy else { return }
            Task { await store.syncDrive(project) }
        } label: {
            HStack(spacing: 10) {
                Group {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundStyle(Palette.text)
                .frame(width: 34, height: 34)
                .background(Palette.surface, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(busy ? "Drive wird abgeglichen …" : "Drive abgleichen").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("Holt neue Videos aus dem Ordner. Was nicht mehr im Drive liegt, verschwindet von selbst.")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier("drive-abgleichen")
    }

    // MARK: Freigabe

    private func pending(_ project: Project) -> [Video] {
        guard let code = project.code else { return [] }
        return project.videos.filter { ReviewStore.of(code).status(of: $0) != .approved }
    }

    private var approveAllText: String {
        guard let project else { return "" }
        let left = pending(project).count
        return (left == project.videos.count ? "Alle \(left) Videos" : "Die übrigen \(left) Videos")
            + " von „\(project.title)“ stehen danach auf Freigegeben, auch auf der Seite für den Kunden. Ändern geht jederzeit pro Video."
    }

    /// Überschrift der Videoliste, bei mehreren Videos mit „Alle freigeben“ (Ole, 23.11.2026)
    private func videosTitle(_ project: Project) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Videos").font(.system(size: 22, weight: .bold)).tracking(-0.4).foregroundStyle(Palette.text)
            Text("\(project.videos.count)").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.muted)
            Spacer()
            if project.code != nil && project.videos.count > 1 {
                let done = pending(project).isEmpty
                Button {
                    Haptics.select()
                    confirmAll = true
                } label: {
                    Label(done ? "Alle freigegeben" : "Alle freigeben", systemImage: done ? "checkmark.seal.fill" : "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(done ? Palette.approvedInk : Palette.text)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(done ? Palette.approved.opacity(0.14) : Palette.surface, in: Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(done)
                .accessibilityIdentifier("alle-freigeben")
            }
        }
    }

    // MARK: Videos

    private func videos(_ project: Project) -> some View {
        Group {
            if project.videos.isEmpty {
                CardBox {
                    Text("Noch keine Videos online.").font(.system(size: 15)).foregroundStyle(Palette.muted)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(project.videos.enumerated()), id: \.element.id) { index, video in
                        // Nach links wischen: von der Seite nehmen (Ole, 22.11.2026), mit Rückfrage
                        SwipeReveal(title: "Entfernen", symbol: "rectangle.badge.minus") { removing = video } content: {
                            videoRow(project, video)
                        }
                        .overlay(alignment: .top) { if index > 0 { RowDivider(leading: 78) } }
                    }
                }
                .padding(.vertical, 4)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .background(Palette.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.line.opacity(0.6), lineWidth: 0.5))
            }
        }
    }

    private func videoRow(_ project: Project, _ video: Video) -> some View {
        // Kein Button: der löst auch bei einer Wischbewegung aus, dann spielte das Video statt „Entfernen“ zu zeigen
        let play = {
            Haptics.press()
            store.play(project, video, source: "projekt-\(video.id)")
        }
        return Group {
            HStack(spacing: 12) {
                RemoteImage(url: video.thumbnail(width: 360))
                    .frame(width: video.portrait ? 40 : 54, height: video.portrait ? 71 : 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(width: 54)
                    .zoomSource("projekt-\(video.id)", zoom)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(video.nr)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.muted)
                            .frame(minWidth: 20, minHeight: 18)
                            .background(Palette.surface, in: Capsule())
                        Text(video.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Palette.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    HStack(spacing: 6) {
                        Text(Clock.text(video.duration))
                            .foregroundStyle(Palette.muted)
                        if video.open > 0 {
                            Text("· \(Plural.count(video.open, "offen", "offen"))").foregroundStyle(Palette.changesInk).fontWeight(.semibold)
                        }
                    }
                    .font(.system(size: 13))
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                // Freigabe direkt in der Zeile ändern (Ole, 23.11.2026), Tipp auf die Zeile spielt weiter das Video
                StatusPill(status: project.code.map { ReviewStore.of($0).status(of: video) } ?? video.status, compact: true) {
                    choosingStatus = video
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Palette.field)
            .contentShape(Rectangle())
            .onTapGesture(perform: play)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, play)
        .accessibilityIdentifier("videozeile-\(video.nr)")
        .contextMenu { videoMenu(project, video) }
        .accessibilityIdentifier("video-\(video.nr)")
    }

    @ViewBuilder
    private func videoMenu(_ project: Project, _ video: Video) -> some View {
            Button { store.play(project, video, source: "projekt-\(video.id)") } label: { Label("Abspielen", systemImage: "play.rectangle") }
            Button {
                renameText = video.title
                renaming = video
            } label: { Label("Titel ändern", systemImage: "pencil") }
            if let link = project.videoLink(video) {
                Button {
                    UIPasteboard.general.url = link
                    store.show("Link zum Video kopiert", symbol: "doc.on.doc")
                } label: { Label("Link zum Video kopieren", systemImage: "doc.on.doc") }
                ShareLink(item: link) { Label("Teilen", systemImage: "square.and.arrow.up") }
                Link(destination: link) { Label("In Safari öffnen", systemImage: "safari") }
            }
            if let drive = video.driveURL { Link(destination: drive) { Label("Original im Drive", systemImage: "arrow.down.circle") } }
            StatusMenuItems(project: project, video: video)
            Divider()
            Button(role: .destructive) { removing = video } label: { Label("Von der Seite nehmen", systemImage: "rectangle.badge.minus") }
    }

    // MARK: Videos dazu

    private func addBox(_ project: Project) -> some View {
        CardBox {
            VStack(spacing: 10) {
                DriveField(text: $sources, placeholder: "Drive Link zu Ordner oder Video")
                TextField("", text: $addTitle, prompt: Text("Titel (optional)").foregroundStyle(Palette.faint))
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button {
                    Haptics.sent()
                    Task {
                        if await store.addVideos(project, sources: sources, title: addTitle) { sources = ""; addTitle = "" }
                    }
                } label: {
                    CapsuleButtonLabel(title: store.isBusy("dazu-\(project.code ?? "")") ? "Startet …" : "Dazu", symbol: "plus", primary: true)
                }
                .buttonStyle(PressStyle())
                .disabled(sources.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(sources.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                .accessibilityIdentifier("dazu")
            }
        }
    }

    // MARK: Kommentare

    private func comments(_ project: Project) -> some View {
        Group {
            if project.openComments.isEmpty {
                CardBox { Text("Keine offenen Kommentare.").font(.system(size: 15)).foregroundStyle(Palette.muted) }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(project.openComments.enumerated()), id: \.element.id) { index, comment in
                        commentRow(project, comment)
                            .overlay(alignment: .top) { if index > 0 { RowDivider(leading: 16) } }
                    }
                }
                .background(Palette.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.line.opacity(0.6), lineWidth: 0.5))
            }
        }
    }

    private func commentRow(_ project: Project, _ comment: OpenComment) -> some View {
        let video = project.videos.first { $0.id == comment.video }
        return Button {
            guard let video else {
                Haptics.error()
                store.show("Das Video ist nicht mehr auf der Seite", symbol: "rectangle.badge.minus", error: true)
                return
            }
            Haptics.press()
            store.play(project, video, at: comment.time, source: "projekt-\(video.id)", comment: comment.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                    if comment.team { Text("· Stagecraft").font(.system(size: 13)).foregroundStyle(Palette.muted) }
                    if let time = comment.time {
                        Text(Clock.text(time))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color(UIColor(hex: 0x1E1E1C)))
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(Palette.pending, in: Capsule())
                    }
                    Spacer(minLength: 4)
                    Text(When.ago(comment.created)).font(.system(size: 12)).foregroundStyle(Palette.faint)
                }
                Text(comment.text)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                Text(video?.title ?? "Video \(comment.nr ?? 0)")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .accessibilityIdentifier("kommentar-\(comment.id)")
    }

    // MARK: Löschen

    private func deleteBox(_ project: Project) -> some View {
        let running = !store.runningJobs(for: project.code).isEmpty
        return CardBox {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Link löschen").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(running ? "Geht erst, wenn der Auftrag fertig ist." :
                            "Die Seite ist danach für alle weg, auch für den Kunden. Videos im Drive und bei Mux und alle Kommentare bleiben gespeichert.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    Haptics.select()
                    confirmDelete = true
                } label: {
                    Text("Löschen")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.overdue)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(Palette.overdue.opacity(0.1), in: Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(running)
                .opacity(running ? 0.4 : 1)
                .accessibilityIdentifier("link-loeschen")
            }
        }
    }
}

/// Link kopieren, danach kurz ein Haken (wie in den StageView Karten der TESS App)
struct CopyButton: View {
    let link: URL
    var round = false
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.url = link
            Haptics.select()
            withAnimation(.easeOut(duration: 0.2)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeOut(duration: 0.25)) { copied = false }
            }
        } label: {
            Group {
                if round {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Palette.surface, in: Circle())
                } else {
                    Label(copied ? "Kopiert" : "Kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Palette.surface, in: Capsule())
                }
            }
            .foregroundStyle(copied ? Palette.accent : Palette.text)
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(copied ? "Kopiert" : "Link kopieren")
        .accessibilityIdentifier("kopieren")
    }
}

/// Feld für einen Drive Link mit Einfügen Knopf (Drive Links kommen fast immer aus der Zwischenablage)
struct DriveField: View {
    @Binding var text: String
    var placeholder = "Drive Link einfügen"
    var focus: FocusState<Bool>.Binding?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.muted)
            field
            if text.isEmpty {
                PasteButton(payloadType: String.self) { values in
                    if let value = values.first { text = value.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .tint(Palette.forest)
                .controlSize(.small)
            } else {
                Button {
                    text = ""
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.faint) }
                    .accessibilityLabel("Leeren")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var field: some View {
        let base = TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.faint))
            .font(.system(size: 16))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .submitLabel(.done)
            .accessibilityIdentifier("drive-feld")
        if let focus { base.focused(focus) } else { base }
    }
}
