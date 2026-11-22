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
    @State private var sources = ""
    @State private var addTitle = ""
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
                        LinkMenuItems(project: project, client: { path.append(.client(key)) }, delete: { confirmDelete = true })
                    } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("Mehr")
                        .accessibilityIdentifier("projekt-mehr")
                }
            }
        }
        .sheet(isPresented: $editing) { if let project { ProjectEditSheet(project: project) } }
        .confirmationDialog("Link löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Link löschen", role: .destructive) {
                guard let project else { return }
                Haptics.cancel()
                Task { if await store.deleteLink(project) { dismiss() } }
            }
        } message: { Text(DeleteText.link(project)) }
        .confirmationDialog("Von der Seite nehmen?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Von der Seite nehmen", role: .destructive) {
                guard let project, let video = removing else { return }
                Haptics.cancel()
                Task { await store.removeVideo(project, video) }
            }
        } message: {
            Text("„\(removing?.title ?? "")“ verschwindet von der Seite. Das Video im Drive, bei Mux und alle Kommentare bleiben, die Nummer \(removing?.nr ?? 0) wird nie neu vergeben.")
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
                linkBox(project).padding(.top, 18)
                if !project.videos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ApprovalBar(approved: project.approved, changes: project.changes, total: project.videos.count, height: 8)
                        Text(project.approvalSummary).font(.system(size: 15)).foregroundStyle(Palette.muted)
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

                SectionTitle(title: "Videos", count: project.videos.count).padding(.top, 30).padding(.horizontal, 4)
                videos(project).padding(.top, 10)
                if project.waiting > 0 {
                    Text("\(Plural.count(project.waiting, "Video ist", "Videos sind")) noch bei Mux und \(project.waiting == 1 ? "erscheint" : "erscheinen") gleich von selbst.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                }

                if project.code != nil {
                    SectionTitle(title: "Videos dazu", detail: "Neue Schnittfassung? Einfach dazu, die alte bleibt mit ihren Kommentaren daneben stehen.")
                        .padding(.top, 30).padding(.horizontal, 4)
                    addBox(project).padding(.top, 10)
                }

                SectionTitle(title: "Offene Kommentare", count: project.openComments.count).padding(.top, 30).padding(.horizontal, 4)
                comments(project).padding(.top, 10)

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

    private func linkBox(_ project: Project) -> some View {
        CardBox {
            VStack(alignment: .leading, spacing: 12) {
                // Der Link öffnet die Kundenansicht wie im Web (Ole, 22.11.2026)
                Button {
                    guard project.code != nil else { return }
                    Haptics.select()
                    path.append(.client(project.key))
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
                            path.append(.client(project.key))
                        } label: { CapsuleButtonLabel(title: "Ansehen", symbol: "play.fill", primary: true) }
                            .buttonStyle(PressStyle())
                            .disabled(project.videos.isEmpty)
                            .accessibilityIdentifier("ansehen")
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
                        videoRow(project, video)
                            .overlay(alignment: .top) { if index > 0 { RowDivider(leading: 78) } }
                    }
                }
                .padding(.vertical, 4)
                .background(Palette.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.line.opacity(0.6), lineWidth: 0.5))
            }
        }
    }

    private func videoRow(_ project: Project, _ video: Video) -> some View {
        Button {
            Haptics.press()
            store.play(project, video, source: "projekt-\(video.id)")
        } label: {
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
                        StatusDot(status: video.status)
                        Text([video.status.title, Clock.text(video.duration)].joined(separator: " · "))
                            .foregroundStyle(Palette.muted)
                        if video.open > 0 {
                            Text("· \(Plural.count(video.open, "offen", "offen"))").foregroundStyle(Palette.changesInk).fontWeight(.semibold)
                        }
                    }
                    .font(.system(size: 13))
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Palette.accent.opacity(0.85))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .contextMenu {
            Button { store.play(project, video, source: "projekt-\(video.id)") } label: { Label("Ansehen", systemImage: "play.rectangle") }
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
            if let drive = video.driveURL { Link(destination: drive) { Label("Im Drive öffnen", systemImage: "externaldrive") } }
            Divider()
            Button(role: .destructive) { removing = video } label: { Label("Von der Seite nehmen", systemImage: "rectangle.badge.minus") }
        }
        .accessibilityIdentifier("video-\(video.nr)")
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
            guard let video else { return }
            Haptics.press()
            store.play(project, video, at: comment.time, source: "projekt-\(video.id)")
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
