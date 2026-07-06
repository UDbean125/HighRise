import SwiftUI

/// Stage 1: write the email draft with `{{Field}}` merge placeholders.
///
/// Fields are open-ended: any column from the imported list is usable, plus a
/// curated catalog of common professional fields. Clicking any field in the
/// palette drops its `{{token}}` into whichever box (subject or body) you were
/// last typing in.
struct TemplateEditorView: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator

    private enum Field: Hashable { case subject, body }
    @FocusState private var focus: Field?

    @State private var showSaveDialog = false
    @State private var newTemplateName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    header
                    Spacer()
                    templateLibraryMenu
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Subject").font(.headline)
                    TextField("e.g. Quick question about {{Company}}",
                              text: $coordinator.template.subject)
                        .textFieldStyle(.roundedBorder)
                        .focused($focus, equals: .subject)
                        .accessibilityLabel("Email subject")
                }

                bodyFormatPicker

                VStack(alignment: .leading, spacing: 6) {
                    Text("Body").font(.headline)
                    TextEditor(text: $coordinator.template.body)
                        .font(.body)
                        .frame(minHeight: 220)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                        .focused($focus, equals: .body)
                        .accessibilityLabel("Email body")
                    if coordinator.template.body.isEmpty {
                        Text("Use {{FieldName}} anywhere to drop in a contact's details, e.g.\n\nHi {{First Name}},\n\nI've been following {{Company}} and wanted to reach out about {{Product Name}}…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                fieldPalette
                variantsEditor
                fieldsSummary
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var templateLibraryMenu: some View {
        Menu {
            Button {
                newTemplateName = ""
                showSaveDialog = true
            } label: {
                Label("Save current template…", systemImage: "square.and.arrow.down")
            }
            if !coordinator.savedTemplates.isEmpty {
                Divider()
                Section("Load") {
                    ForEach(coordinator.savedTemplates.sorted(by: { $0.savedAt > $1.savedAt })) { saved in
                        Button(saved.name) { coordinator.loadTemplate(saved) }
                    }
                }
                Divider()
                Menu("Delete") {
                    ForEach(coordinator.savedTemplates.sorted(by: { $0.savedAt > $1.savedAt })) { saved in
                        Button(saved.name, role: .destructive) { coordinator.deleteTemplate(saved) }
                    }
                }
            }
        } label: {
            Label("Templates", systemImage: "tray.full")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .alert("Save template", isPresented: $showSaveDialog) {
            TextField("Template name", text: $newTemplateName)
            Button("Save") { coordinator.saveCurrentTemplate(as: newTemplateName) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Saves the subject, body, format, and any variants under a name you can reload later.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Compose your template").font(.title2).bold()
            Text("Write the email once. Wrap any field from your contact list in double braces — like {{First Name}} or {{Company}} — and HighRise fills it in for each recipient. Add a fallback after a pipe — {{First Name|there}} — for rows with no value, and format with filters like {{Amount|currency:USD}}, {{Renewal Date|date:MMMM d, yyyy}}, or {{Name|fixcaps}} to fix ALL-CAPS.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bodyFormatPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Body format").font(.headline)
            Picker("Body format", selection: $coordinator.template.format) {
                ForEach(EmailTemplate.BodyFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)
            if coordinator.template.format == .html {
                Text("Paste HTML markup as the body. Field values are HTML-escaped automatically. Full fidelity in Outlook; Apple Mail renders it as plain text.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Field palette

    private var fieldPalette: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insert a merge field").font(.headline)
            Text("Click a field to add it where you're typing.")
                .font(.callout).foregroundStyle(.secondary)

            if !coordinator.importedHeaders.isEmpty {
                Text("From your list").font(.subheadline).foregroundStyle(.secondary)
                FieldChipsRow(fields: coordinator.importedHeaders.map { MergeField(name: $0, detail: "Column from your imported list") },
                              onInsert: insert)
            }

            DisclosureGroup("Recommended professional fields") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(MergeFieldCatalog.groups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.title).font(.subheadline).foregroundStyle(.secondary)
                            FieldChipsRow(fields: group.fields, onInsert: insert)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .font(.subheadline)
        }
        .card(padding: 14)
    }

    /// Appends `field.token` to whichever box is focused (body by default),
    /// inserting a separating space when the existing text needs one.
    private func insert(_ field: MergeField) {
        let target: Field = (focus == .subject) ? .subject : .body
        switch target {
        case .subject:
            coordinator.template.subject = appended(field.token, to: coordinator.template.subject)
            focus = .subject
        case .body:
            coordinator.template.body = appended(field.token, to: coordinator.template.body)
            focus = .body
        }
    }

    private func appended(_ token: String, to existing: String) -> String {
        guard let last = existing.last else { return token }
        let needsSpace = !last.isWhitespace && last != "\n"
        return existing + (needsSpace ? " " : "") + token
    }

    // MARK: - Conditional variants

    private var variantsEditor: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Send a different subject/body to recipients matching a rule. The first matching variant wins; everyone else gets the template above.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach($coordinator.template.variants) { $variant in
                    variantCard($variant)
                }

                Button {
                    coordinator.template.variants.append(TemplateVariant())
                } label: {
                    Label("Add a variant", systemImage: "plus.circle")
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Conditional variants (\(coordinator.template.variants.count))", systemImage: "arrow.triangle.branch")
                .font(.headline)
        }
    }

    private func variantCard(_ variant: Binding<TemplateVariant>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("If").foregroundStyle(.secondary)
                fieldMenu(variant.rule.field)
                Picker("", selection: variant.rule.predicate) {
                    ForEach(RoutingRule.Predicate.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(maxWidth: 150)
                if variant.wrappedValue.rule.predicate.needsValue {
                    TextField("value", text: variant.rule.value)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 160)
                }
                Spacer()
                Button(role: .destructive) {
                    coordinator.template.variants.removeAll { $0.id == variant.wrappedValue.id }
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
            }
            TextField("Variant subject", text: variant.subject)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: variant.body)
                .font(.body).frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private func fieldMenu(_ selection: Binding<String>) -> some View {
        Menu {
            ForEach(coordinator.importedHeaders, id: \.self) { header in
                Button(header) { selection.wrappedValue = header }
            }
        } label: {
            Text(selection.wrappedValue.isEmpty ? "field" : selection.wrappedValue)
                .frame(maxWidth: 140)
        }
    }

    @ViewBuilder
    private var fieldsSummary: some View {
        let fields = coordinator.template.referencedFields
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Merge fields in this template").font(.headline)
                FieldChipsRow(fields: fields.map { MergeField(name: $0, detail: "") }, onInsert: nil)
                if !coordinator.unmatchedTemplateFields.isEmpty && !coordinator.importedHeaders.isEmpty {
                    Label("Your imported list has no column for: \(coordinator.unmatchedTemplateFields.joined(separator: ", "))",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 4)
        }
    }
}

/// A wrapping row of merge-field chips. When `onInsert` is provided each chip is
/// a button; otherwise the chips are static labels (used to display detected
/// fields).
struct FieldChipsRow: View {
    let fields: [MergeField]
    let onInsert: ((MergeField) -> Void)?

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 90, maximum: 240), spacing: 8, alignment: .leading)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(fields) { field in
                if let onInsert {
                    Button { onInsert(field) } label: { chip(field) }
                        .buttonStyle(.plain)
                        .help(field.detail)
                } else {
                    chip(field)
                }
            }
        }
    }

    private func chip(_ field: MergeField) -> some View {
        Text(field.name)
            .font(.callout.monospaced())
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .contentShape(Capsule())
    }
}
