import SwiftUI

/// Neuer Link wie im Dashboard (seit 16.11.2026): erst nur der Drive Link. Danach gehen die Videos sofort zu Mux (stageview
/// vorbereiten), das Fenster zeigt den Fortschritt pro Video und darunter Titel, Kunde, Drehtag. „Link anlegen“ geht, sobald alle
/// Videos bei Mux angelegt sind, der Fortschritt läuft danach weiter, bis der Link live ist. Wer vorher schließt, wird gefragt, dann
/// werden die schon hochgeladenen Videos bei Mux wieder gelöscht.
struct NewLinkSheet: View {
    let start: NewLinkStart
    @Binding var path: [Route]

    private enum Step { case source, preparing, done }
    private static let readyPhases = ["mux", "fertig", "verwendet"]
    private static let finishedPhases = ["fertig", "verwendet", "aufgeraeumt"]

    @State private var store = Store.shared
    @State private var step = Step.source
    @State private var source = ""
    @State private var sourceError: String?
    @State private var starting = false
    @State private var job: String?
    @State private var extraJob: String?
    @State private var allJobs: [String] = []
    @State private var prep: Job?
    @State private var linkJobID: String?
    @State private var linkJob: Job?
    @State private var title = ""
    @State private var titleTyped = false
    @State private var customerID = ""
    @State private var newName = ""
    @State private var newCompany = ""
    @State private var withDate = false
    @State private var shootDate = Date.now
    @State private var subfolders = false
    @State private var categories = false
    @State private var creating = false
    @State private var confirmDiscard = false
    @State private var failed = 0
    @FocusState private var sourceFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(title: step == .done ? "Link ist da" : "Neuer Link", cancel: close) {
            switch step {
            case .source: sourceStep
            case .preparing: preparingStep
            case .done: doneStep
            }
        }
        .interactiveDismissDisabled(step == .preparing && linkJobID == nil)
        .confirmationDialog("Neuen Link verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) {
                Haptics.cancel()
                cancelJobs()
                dismiss()
            }
        } message: { Text("Die Videos, die schon zu Mux gegangen sind, werden dort wieder gelöscht. Im Drive bleibt alles.") }
        .task(id: allJobs) { await poll() }
        .onAppear {
            customerID = start.customerID ?? ""
            sourceFocused = true
            #if DEBUG
            if Demo.sheet == "neu-lauf" {
                source = "https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOpQrStUv"
                job = "demo"; prep = Demo.prepJob(ready: 1); title = prep?.prep?.name ?? ""; customerID = "lukas-doberenz"
                step = .preparing; sourceFocused = false
            }
            #endif
        }
    }

    private func close() {
        if step == .preparing && linkJobID == nil { confirmDiscard = true } else { dismiss() }
    }

    // MARK: 1. Drive Link

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Drive Link").font(.system(size: 28, weight: .bold)).tracking(-0.6).foregroundStyle(Palette.text)
                Text("Export Ordner oder einzelnes Video aus dem Drive. Die Videos gehen sofort zu Mux, Titel und Kunde trägst du währenddessen ein.")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            DriveField(text: $source, focus: $sourceFocused)
                .modifier(Shake(trigger: failed))
                .onSubmit(next)
            if let sourceError {
                Label(sourceError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.changesInk)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
            Button(action: next) {
                CapsuleButtonLabel(title: starting ? "Startet …" : "Weiter", symbol: starting ? nil : "arrow.right", primary: true, height: 50)
            }
            .buttonStyle(PressStyle())
            .disabled(starting || source.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(source.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            .accessibilityIdentifier("weiter")
        }
        .animation(.easeOut(duration: 0.2), value: sourceError)
    }

    private func next() {
        let q = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !starting else { return }
        guard q.contains("drive.google.com") || q.wholeMatch(of: /[A-Za-z0-9_-]{20,}/) != nil else {
            return fail("Das sieht nicht nach einem Drive Link aus")
        }
        starting = true
        sourceError = nil
        Task {
            defer { starting = false }
            #if DEBUG
            if Demo.isOn {
                job = "demo"; allJobs = ["demo"]; prep = Demo.prepJob(ready: 1); Haptics.sent()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = .preparing }
                return
            }
            #endif
            do {
                let ref: Store.JobRef = try await API.post("admin/vorbereiten", ["quelle": q])
                job = ref.id
                allJobs = [ref.id]
                Haptics.sent()
                sourceFocused = false
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = .preparing }
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ text: String) {
        sourceError = text
        failed += 1
        Haptics.error()
    }

    // MARK: 2. Vorbereiten und Felder

    private var preparingStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            progressCard
            if linkJobID == nil {
                FieldBox(label: "Titel der Seite") {
                    TextField("", text: Binding(get: { title }, set: { title = $0; titleTyped = true }),
                              prompt: Text("Content Day November").foregroundStyle(Palette.faint))
                        .font(.system(size: 17))
                        .accessibilityIdentifier("neu-titel")
                }
                FieldBox(label: "Kunde") {
                    Picker("Kunde", selection: $customerID) {
                        Text("Kunde wählen …").tag("")
                        ForEach(store.customers) { customer in
                            Text(customer.company.isEmpty ? customer.name : "\(customer.name) · \(customer.company)").tag(customer.id)
                        }
                        Text("Neuen Kunden anlegen …").tag("__neu__")
                    }
                    .pickerStyle(.menu)
                    .tint(customerID.isEmpty ? Palette.muted : Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("neu-kunde")
                }
                if customerID == "__neu__" {
                    HStack(spacing: 10) {
                        FieldBox(label: "Name des neuen Kunden") {
                            TextField("", text: $newName, prompt: Text("Vorname Nachname").foregroundStyle(Palette.faint)).font(.system(size: 16))
                        }
                        FieldBox(label: "Firma") {
                            TextField("", text: $newCompany, prompt: Text("optional").foregroundStyle(Palette.faint)).font(.system(size: 16))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                VStack(spacing: 0) {
                    Toggle(isOn: $withDate.animation(.easeOut(duration: 0.2))) {
                        Text("Drehtag angeben").font(.system(size: 16)).foregroundStyle(Palette.text)
                    }
                    .padding(.vertical, 12)
                    if withDate {
                        DatePicker("Drehtag", selection: $shootDate, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "de_DE"))
                            .padding(.bottom, 12)
                    }
                    if (prep?.prep?.subfolders ?? 0) > 0 {
                        RowDivider()
                        Toggle(isOn: $subfolders) {
                            Text("Dazu \(Plural.count(prep?.prep?.subfolders ?? 0, "Video", "Videos")) aus Unterordnern mitnehmen")
                                .font(.system(size: 16)).foregroundStyle(Palette.text)
                        }
                        .padding(.vertical, 12)
                        .onChange(of: subfolders) { _, now in toggleSubfolders(now) }
                    }
                    if extraJob != nil || prep?.prep?.deep == true {
                        RowDivider()
                        Toggle(isOn: $categories) {
                            Text("Unterordner als Kategorien auf der Seite").font(.system(size: 16)).foregroundStyle(Palette.text)
                        }
                        .padding(.vertical, 12)
                    }
                }
                .tint(Palette.forest)
                .padding(.horizontal, 14)
                .background(Palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line.opacity(0.6), lineWidth: 0.5))

                Button(action: create) {
                    CapsuleButtonLabel(title: creating ? "Link wird angelegt …" : canCreate ? "Link anlegen" : "Videos werden gesucht …",
                                       symbol: canCreate && !creating ? "plus" : nil, primary: true, height: 52)
                }
                .buttonStyle(PressStyle())
                .disabled(!canCreate || creating)
                .opacity(canCreate ? 1 : 0.5)
                .accessibilityIdentifier("link-anlegen")
            }
        }
        .animation(.easeOut(duration: 0.2), value: customerID)
    }

    private var canCreate: Bool { Self.readyPhases.contains(prep?.prep?.phase ?? "") }

    private var progressCard: some View {
        let p = prep?.prep
        let videos = p?.videos ?? []
        let (text, percent) = progressText
        return CardBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(linkFailed ? Palette.changesInk : Palette.text)
                        .contentTransition(.opacity)
                    Spacer()
                    if let percent { Text("\(percent) %").font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.muted) }
                }
                if let percent {
                    ProgressView(value: Double(percent), total: 100).tint(Palette.forest)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(Palette.forest)
                }
                if !videos.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(videos, id: \.drive) { video in
                            let mux = p?.mux[video.drive]
                            HStack(spacing: 10) {
                                Text(video.title).font(.system(size: 14)).foregroundStyle(Palette.text).lineLimit(1)
                                Spacer(minLength: 8)
                                if mux?.status == "ready" {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.approvedInk)
                                } else if mux?.status == "errored" {
                                    Text("Fehler bei Mux").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.changesInk)
                                } else {
                                    ProgressView(value: Double(mux?.percent ?? 0), total: 100).tint(Palette.forestLight).frame(width: 60)
                                    Text("\(mux?.percent ?? 0) %").font(.system(size: 12).monospacedDigit()).foregroundStyle(Palette.muted)
                                        .frame(width: 38, alignment: .trailing)
                                }
                            }
                            .padding(.vertical, 7)
                        }
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: text)
        .accessibilityIdentifier("fortschritt")
    }

    private var linkFailed: Bool { linkJob.map { !$0.running && !$0.ok } ?? false }

    /// Texte wie laufZeichnen() im Dashboard
    private var progressText: (String, Int?) {
        let p = prep?.prep
        let count = p?.videos.count ?? 0, ready = p?.ready ?? 0
        var text: String, percent: Int?
        switch p?.phase {
        case nil, "drive": text = "Drive wird gelesen …"
        case "gefunden": text = "\(Plural.count(count, "Video", "Videos")) gefunden, gehen zu Mux …"; percent = 2
        default:
            if ready < count { text = "Mux bereitet vor · \(ready) von \(count) fertig"; percent = max(3, p?.muxPercent ?? 0) }
            else { text = count == 1 ? "Das Video ist bereit" : "Alle \(count) Videos sind bereit"; percent = 100 }
        }
        if let linkJob {
            if !linkJob.running && !linkJob.ok { text = "Link anlegen hat nicht geklappt: " + (linkJob.error ?? "unbekannter Fehler") }
            else if !linkJob.running && ready == count { text = "Fertig, der Link ist live"; percent = 100 }
            else if !linkJob.running { text = "Link ist live, Mux bereitet noch vor · \(ready) von \(count) fertig" }
            else if percent == 100 { text = "Seite wird gebaut …"; percent = 99 }
        }
        return (text, percent)
    }

    private func toggleSubfolders(_ on: Bool) {
        Task {
            do {
                if on {
                    #if DEBUG
                    if Demo.isOn { extraJob = "demo2"; return }
                    #endif
                    let ref: Store.JobRef = try await API.post("admin/vorbereiten", ["quelle": source, "unterordner": true])
                    extraJob = ref.id
                    allJobs.append(ref.id)
                } else if let old = extraJob {
                    extraJob = nil
                    try? await API.post("admin/auftrag/\(old)/abbrechen")
                }
            } catch {
                subfolders.toggle()
                store.show(error.localizedDescription, error: true)
            }
        }
    }

    private func create() {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return store.show("Bitte einen Titel eintragen", error: true) }
        guard !customerID.isEmpty else { return store.show("Bitte einen Kunden wählen", error: true) }
        creating = true
        Task {
            defer { creating = false }
            var customer = customerID
            if customer == "__neu__" {
                guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return store.show("Name des neuen Kunden fehlt", error: true) }
                guard let id = await store.newCustomer(name: newName, company: newCompany) else { return }
                customer = id
            }
            #if DEBUG
            if Demo.isOn {
                linkJobID = "demo-neu"; linkJob = Demo.linkJob(); Haptics.done()
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = .done }
                return
            }
            #endif
            var body: [String: Any] = ["titel": clean, "kunde": customer, "quellen": source,
                                       "unterordner": extraJob != nil || prep?.prep?.deep == true,
                                       "kategorien": categories && (extraJob != nil || prep?.prep?.deep == true)]
            if withDate {
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
                body["dreh"] = f.string(from: shootDate)
            }
            do {
                let ref: Store.JobRef = try await API.post("admin/neu", body)
                linkJobID = ref.id
                allJobs.append(ref.id)
                Haptics.sent()
                Task { await store.refresh() }
            } catch {
                store.show(error.localizedDescription, error: true)
            }
        }
    }

    /// Alle 1,5 s nachsehen, bis alles durch ist (wie neuPruefen im Dashboard)
    private func poll() async {
        while !Task.isCancelled, let job {
            #if DEBUG
            if Demo.isOn { return }
            #endif
            do {
                let a: Job = try await API.get("admin/auftrag/\(extraJob ?? job)")
                prep = a
                if let linkJobID { linkJob = try await API.get("admin/auftrag/\(linkJobID)") }
                if !titleTyped, title.isEmpty, let name = a.prep?.name { title = name }
                // Vorbereiten ging schief (falscher Link, kein Zugriff, keine Videos): zurück zum Link Feld, mit dem Grund
                if !a.running, !a.ok, linkJobID == nil, !Self.finishedPhases.contains(a.prep?.phase ?? "") {
                    cancelJobs()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = .source }
                    self.job = nil
                    allJobs = []
                    fail(a.last.contains("abgebrochen") ? "Abgebrochen" : (a.error ?? "Das hat nicht geklappt, bitte nochmal"))
                    return
                }
                if let linkJob, linkJob.link != nil, step != .done {
                    Haptics.done()
                    await store.refresh()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = .done }
                }
                let muxDone = Self.finishedPhases.contains(a.prep?.phase ?? "") || !a.running
                if let linkJob, !linkJob.running, muxDone { return }
            } catch APIError.signedOut {
                return
            } catch {}
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    private func cancelJobs() {
        guard linkJobID == nil else { return }
        let ids = allJobs + [extraJob].compactMap { $0 }
        Task {
            for id in Set(ids) { try? await API.post("admin/auftrag/\(id)/abbrechen") }
        }
    }

    // MARK: 3. Fertig

    private var doneStep: some View {
        let link = linkJob?.link
        let project = link?.pathComponents.last.flatMap { store.project(code: $0) }
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer()
                ZStack {
                    Circle().fill(Palette.approved.opacity(0.18)).frame(width: 96, height: 96)
                    Image(systemName: "checkmark").font(.system(size: 40, weight: .bold)).foregroundStyle(Palette.approvedInk)
                }
                .symbolEffect(.bounce, value: step == .done)
                Spacer()
            }
            .padding(.top, 10)
            VStack(spacing: 6) {
                Text(title.isEmpty ? "Neuer Link" : title).font(.system(size: 24, weight: .bold)).tracking(-0.5).foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
                Text(progressText.0).font(.system(size: 15)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            if let link {
                CardBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            StageViewMark(size: 26)
                            Text(link.absoluteString.replacingOccurrences(of: "https://", with: ""))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Palette.text)
                                .textSelection(.enabled)
                        }
                        HStack(spacing: 8) {
                            CopyButton(link: link)
                            ShareLink(item: link) {
                                CapsuleButtonLabel(title: "Teilen", symbol: "square.and.arrow.up")
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
            }
            if let project {
                Button {
                    Haptics.select()
                    dismiss()
                    path.append(.project(project.key))
                } label: { CapsuleButtonLabel(title: "Zum Link", symbol: "arrow.right", primary: true, height: 52) }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("zum-link")
            }
        }
    }
}
