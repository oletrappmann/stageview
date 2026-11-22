import SwiftUI

/// Feld mit kleiner Überschrift auf weißer Fläche (Formulare in den Fenstern)
struct FieldBox<Content: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.label).foregroundStyle(Palette.muted).padding(.leading, 4)
            content
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line.opacity(0.6), lineWidth: 0.5))
            if let hint { Text(hint).font(.system(size: 13)).foregroundStyle(Palette.muted).padding(.leading, 4) }
        }
    }
}

/// Fenster mit Kopf (Abbrechen links, Aktion rechts) und Canvas Grund, wie die Blätter der TESS App
struct SheetFrame<Content: View>: View {
    let title: String
    var action: String?
    var actionEnabled = true
    var busy = false
    var cancel: (() -> Void)?
    var perform: (() -> Void)?
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        Haptics.select()
                        if let cancel { cancel() } else { dismiss() }
                    } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Schließen")
                        .accessibilityIdentifier("fenster-zu")
                }
                if let action, let perform {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            perform()
                        } label: {
                            if busy { ProgressView() } else { Text(action).fontWeight(.semibold) }
                        }
                        .disabled(!actionEnabled || busy)
                        .accessibilityIdentifier("fenster-aktion")
                    }
                }
            }
        }
    }
}

// MARK: Link bearbeiten

/// Titel, Kunde, Firma, Hinweis und Darstellung eines Links (oben im Projekt Fenster des Dashboards). Der Link bleibt immer gleich.
struct ProjectEditSheet: View {
    let project: Project
    @State private var store = Store.shared
    @State private var title: String
    @State private var customerID: String
    @State private var company: String
    @State private var note: String
    @State private var layout: String
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    init(project: Project) {
        self.project = project
        _title = State(initialValue: project.title)
        _company = State(initialValue: project.company)
        _note = State(initialValue: project.note)
        _layout = State(initialValue: project.layout == "youtube" ? "youtube" : "abschnitte")
        _customerID = State(initialValue: Store.shared.customers.first { $0.owns(project) }?.id ?? "")
    }

    private var originalCustomer: String { store.customers.first { $0.owns(project) }?.id ?? "" }

    private var changes: [String: Any] {
        var body: [String: Any] = [:]
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t != project.title { body["titel"] = t }
        if company.trimmingCharacters(in: .whitespaces) != project.company { body["firma"] = company.trimmingCharacters(in: .whitespaces) }
        if note.trimmingCharacters(in: .whitespacesAndNewlines) != project.note { body["hinweis"] = note.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !customerID.isEmpty && customerID != originalCustomer { body["kunde_id"] = customerID }
        if layout != (project.layout == "youtube" ? "youtube" : "abschnitte") { body["darstellung"] = layout }
        return body
    }

    var body: some View {
        SheetFrame(title: "Link bearbeiten", action: "Sichern", actionEnabled: !changes.isEmpty && !title.trimmingCharacters(in: .whitespaces).isEmpty,
                   busy: saving, perform: save) {
            FieldBox(label: "Titel") {
                TextField("", text: $title, prompt: Text("Content Day November").foregroundStyle(Palette.faint))
                    .font(.system(size: 17))
                    .accessibilityIdentifier("feld-titel")
            }
            FieldBox(label: "Kunde") {
                Picker("Kunde", selection: $customerID) {
                    if customerID.isEmpty { Text("Kunde wählen").tag("") }
                    ForEach(store.customers) { customer in Text(customer.name).tag(customer.id) }
                }
                .pickerStyle(.menu)
                .tint(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: customerID) { _, id in
                    if let customer = store.customers.first(where: { $0.id == id }) { company = customer.company }
                }
            }
            FieldBox(label: "Firma oder Zusatz") {
                TextField("", text: $company, prompt: Text("optional").foregroundStyle(Palette.faint)).font(.system(size: 17))
            }
            FieldBox(label: "Hinweis oben auf der Seite", hint: "Leer lassen für den Standard Text.") {
                TextField("", text: $note, prompt: Text("Standard Text").foregroundStyle(Palette.faint), axis: .vertical)
                    .lineLimit(2...6)
                    .font(.system(size: 16))
                    .padding(.vertical, 12)
            }
            FieldBox(label: "Darstellung der Kategorien") {
                Picker("Darstellung", selection: $layout) {
                    Text("Abschnitte (Standard)").tag("abschnitte")
                    Text("YouTube Video und Shorts").tag("youtube")
                }
                .pickerStyle(.menu)
                .tint(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Der Link bleibt immer gleich, auch wenn sich der Titel ändert. Die Seite wird nach dem Sichern neu gebaut.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 4)
        }
    }

    private func save() {
        saving = true
        Task {
            let ok = await store.saveProject(project, fields: changes)
            saving = false
            if ok { Haptics.done(); dismiss() }
        }
    }
}

// MARK: Kunden

/// Alle Kunden in StageView mit Zahl der Links. Antippen bearbeitet, Plus legt neu an, löschen geht nur ohne Links.
struct CustomersSheet: View {
    @State private var store = Store.shared
    @State private var editing: Customer?
    @State private var creating = false
    @State private var deleting: Customer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(title: "Kunden", action: "Neu", perform: { Haptics.select(); creating = true }) {
            Text("Neue Kunden gibt es nur in StageView, das Kundenregister im Content Brain bleibt, wie es ist.")
                .font(.system(size: 14))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(store.customers.enumerated()), id: \.element.id) { index, customer in
                    row(customer).overlay(alignment: .top) { if index > 0 { RowDivider(leading: 64) } }
                }
            }
            .background(Palette.field, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.line.opacity(0.6), lineWidth: 0.5))
        }
        .sheet(item: $editing) { CustomerEditSheet(customer: $0) }
        .sheet(isPresented: $creating) { CustomerEditSheet(customer: nil) }
        .confirmationDialog("Kunden löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                guard let customer = deleting else { return }
                Haptics.cancel()
                Task { await store.deleteCustomer(customer) }
            }
        } message: {
            Text(deleting?.source == "content-brain" ? "\(deleting?.name ?? "") verschwindet aus StageView. Im Content Brain bleibt der Kunde, wie er ist."
                    : "\(deleting?.name ?? "") verschwindet aus StageView.")
        }
    }

    private func row(_ customer: Customer) -> some View {
        let links = store.links(of: customer)
        return Button {
            Haptics.select()
            editing = customer
        } label: {
            HStack(spacing: 12) {
                CustomerAvatar(name: customer.name, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(customer.name).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.text)
                    Text([customer.company, links == 0 ? "noch kein Link" : Plural.count(links, "Link", "Links")].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .contextMenu {
            Button { editing = customer } label: { Label("Bearbeiten", systemImage: "pencil") }
            Button {
                store.customerID = customer.id
                dismiss()
            } label: { Label("Links zeigen", systemImage: "line.3.horizontal.decrease") }
            if links == 0 {
                Button(role: .destructive) { deleting = customer } label: { Label("Löschen", systemImage: "trash") }
            }
        }
        .accessibilityIdentifier("kunde-zeile-\(customer.id)")
    }
}

/// Kunde anlegen oder ändern (Name, Firma). Ändern gilt für alle Links des Kunden, die Seiten werden neu gebaut.
struct CustomerEditSheet: View {
    let customer: Customer?
    var created: ((String) -> Void)?
    @State private var store = Store.shared
    @State private var name: String
    @State private var company: String
    @State private var saving = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    init(customer: Customer?, created: ((String) -> Void)? = nil) {
        self.customer = customer
        self.created = created
        _name = State(initialValue: customer?.name ?? "")
        _company = State(initialValue: customer?.company ?? "")
    }

    var body: some View {
        let links = customer.map { store.links(of: $0) } ?? 0
        SheetFrame(title: customer == nil ? "Neuer Kunde" : "Kunde bearbeiten", action: customer == nil ? "Anlegen" : "Sichern",
                   actionEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty
                    && (customer == nil || name != customer?.name || company != customer?.company),
                   busy: saving, perform: save) {
            HStack {
                Spacer()
                CustomerAvatar(name: name.isEmpty ? "?" : name, size: 72)
                Spacer()
            }
            .padding(.top, 6)
            .animation(.easeOut(duration: 0.2), value: name)
            FieldBox(label: "Name") {
                TextField("", text: $name, prompt: Text("Vorname Nachname").foregroundStyle(Palette.faint))
                    .font(.system(size: 17))
                    .textContentType(.name)
                    .accessibilityIdentifier("kunde-name")
            }
            FieldBox(label: "Firma", hint: customer == nil ? "Neue Kunden gibt es nur in StageView." :
                        links > 0 ? "Gilt für \(Plural.count(links, "Link", "Links")), die Seiten werden dabei neu gebaut." : "Bei diesem Kunden gibt es noch keinen Link.") {
                TextField("", text: $company, prompt: Text("optional").foregroundStyle(Palette.faint)).font(.system(size: 17))
            }
            if let customer, links == 0 {
                Button {
                    Haptics.select()
                    confirmDelete = true
                } label: { CapsuleButtonLabel(title: "Kunden löschen", symbol: "trash", destructive: true) }
                    .buttonStyle(PressStyle())
                    .padding(.top, 10)
                    .confirmationDialog("Kunden löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Löschen", role: .destructive) {
                            Haptics.cancel()
                            Task { if await store.deleteCustomer(customer) { dismiss() } }
                        }
                    } message: { Text("\(customer.name) verschwindet aus StageView.") }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            if let customer {
                let ok = await store.editCustomer(customer, name: name, company: company)
                saving = false
                if ok { Haptics.done(); dismiss() }
            } else {
                let id = await store.newCustomer(name: name, company: company)
                saving = false
                if let id { Haptics.done(); created?(id); dismiss() }
            }
        }
    }
}
