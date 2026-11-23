import SwiftUI

/// Ein Kommentar Faden im Player: Kopf (Name, Stagecraft, Zeitmarke, wann), Text, Antworten eingerückt. Tippen springt an die
/// Stelle, der Kreis rechts hakt ab. Mehr im Menü bei langem Drücken: Antworten, Bearbeiten, Kopieren, Löschen.
struct ThreadView: View {
    let thread: CommentThread
    let highlighted: Bool
    var fps: Double?
    let jump: (Double) -> Void
    let reply: (Comment) -> Void
    let toggleDone: (Comment) -> Void
    let edit: (Comment) -> Void
    let delete: (Comment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CommentRow(comment: thread.root, reply: false, highlighted: highlighted, fps: fps, jump: jump, toggleDone: toggleDone)
                .contextMenu { menu(thread.root) }
            ForEach(thread.replies) { answer in
                CommentRow(comment: answer, reply: true, highlighted: false, fps: fps, jump: jump, toggleDone: toggleDone)
                    .padding(.leading, 38)
                    .contextMenu { menu(answer) }
            }
            if !thread.root.done {
                Button {
                    Haptics.select()
                    reply(thread.root)
                } label: {
                    Text("Antworten")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .padding(.vertical, 6)
                        .padding(.leading, 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("antworten-\(thread.root.id)")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(highlighted ? Color.white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeOut(duration: 0.25), value: highlighted)
        .opacity(thread.root.done ? 0.55 : 1)
    }

    @ViewBuilder
    private func menu(_ comment: Comment) -> some View {
        Button { reply(comment) } label: { Label("Antworten", systemImage: "arrowshape.turn.up.left") }
        Button { toggleDone(comment) } label: {
            Label(comment.done ? "Wieder offen" : "Erledigt", systemImage: comment.done ? "arrow.uturn.backward.circle" : "checkmark.circle")
        }
        if comment.canEdit { Button { edit(comment) } label: { Label("Bearbeiten", systemImage: "pencil") } }
        Button { UIPasteboard.general.string = comment.text; Store.shared.show("Text kopiert", symbol: "doc.on.doc") } label: {
            Label("Text kopieren", systemImage: "doc.on.doc")
        }
        if comment.canDelete {
            Divider()
            Button(role: .destructive) { delete(comment) } label: { Label("Löschen", systemImage: "trash") }
        }
    }
}

private struct CommentRow: View {
    let comment: Comment
    let reply: Bool
    let highlighted: Bool
    var fps: Double?
    let jump: (Double) -> Void
    let toggleDone: (Comment) -> Void
    @AppStorage(Timecode.key) private var timecode = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if comment.team {
                        Text("Stagecraft")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.approved)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Palette.approved.opacity(0.16), in: Capsule())
                    }
                    if let time = comment.time {
                        Button {
                            Haptics.select()
                            jump(time)
                        } label: {
                            Text(Timecode.display(time, fps: fps, on: timecode))
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Palette.stage)
                                .padding(.horizontal, 7)
                                .frame(height: 20)
                                .background(Palette.pending, in: Capsule())
                                .fixedSize()
                        }
                        .buttonStyle(PressStyle())
                        .layoutPriority(1)
                        .accessibilityLabel("Zu \(Timecode.display(time, fps: fps, on: timecode)) springen")
                    }
                    Text(When.ago(comment.created))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                Text(LinkedText.make(comment.text))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .tint(Palette.approved)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .environment(\.openURL, OpenURLAction { url in
                        // StageView Links öffnen in der App, alles andere wie gewohnt in Safari
                        if Store.isStageViewLink(url) { Haptics.press(); Store.shared.open(url); return .handled }
                        return .systemAction
                    })
                if comment.edited != nil {
                    Text("bearbeitet").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.35))
                }
            }
            Spacer(minLength: 4)
            if !reply {
                Button {
                    toggleDone(comment)
                } label: {
                    Image(systemName: comment.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(comment.done ? Palette.approved : Color.white.opacity(0.45))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle(scale: 0.86))
                .accessibilityLabel(comment.done ? "Wieder offen" : "Erledigt")
                .accessibilityIdentifier("erledigt-\(comment.id)")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if let time = comment.time { Haptics.select(); jump(time) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kommentar-\(comment.id)")
    }

    private var avatar: some View {
        Group {
            if comment.team, let photo = UIImage(named: "avatar-\(comment.name.lowercased())") {
                Image(uiImage: photo).resizable().scaledToFill()
            } else if comment.team {
                StageViewMark(size: reply ? 24 : 28)
            } else {
                Text(String(comment.name.prefix(1)).uppercased())
                    .font(.system(size: reply ? 11 : 13, weight: .semibold))
                    .foregroundStyle(Palette.stage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.pending)
            }
        }
        .frame(width: reply ? 24 : 28, height: reply ? 24 : 28)
        .clipShape(Circle())
        .padding(.top, 1)
    }
}

/// Freigabe eines Videos als Glaskapsel mit Menü (Zur Freigabe, Änderung gewünscht, Freigegeben)
struct StatusMenu: View {
    let status: ReviewStatus
    let entry: StatusEntry?
    let choose: (ReviewStatus) -> Void

    var body: some View {
        Menu {
            Section(entry?.by.map { "\(status.title) von \($0)" + (entry?.at.map { ", " + When.ago($0) } ?? "") } ?? "Freigabe") {
                ForEach(ReviewStatus.allCases) { option in
                    Button {
                        choose(option)
                    } label: {
                        Label {
                            Text(option.title)
                            Text(option.help)
                        } icon: {
                            Image(systemName: option == status ? "checkmark" : option.symbol)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Circle().fill(dot).frame(width: 9, height: 9)
                Text(status.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.white.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .menuOrder(.fixed)
        .simultaneousGesture(TapGesture().onEnded { Haptics.select() })
        .accessibilityIdentifier("freigabe")
    }

    private var dot: Color {
        switch status {
        case .pending: Palette.pending
        case .changes: Palette.changes
        case .approved: Palette.approved
        }
    }
}

/// Links in Kommentaren antippbar wie auf der Videoseite (http, https, www.), Satzzeichen am Ende gehören nicht dazu
enum LinkedText {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func make(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector else { return result }
        let ns = text as NSString
        for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let url = match.url, let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].link = url
            result[lower..<upper].underlineStyle = .single
        }
        return result
    }
}
