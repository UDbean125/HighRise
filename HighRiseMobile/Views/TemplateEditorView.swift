import SwiftUI

/// Step 2: write the subject/body once, using the same `{{Field}}` merge
/// syntax as the Mac app. Live preview counts (via `refreshPreviews`) reuse
/// `TemplateMergeEngine`, so a placeholder that doesn't match a CSV column
/// shows up as a held-back recipient before the user ever tries to send.
///
/// Feature parity with the Mac Compose screen, all built on shared
/// Foundation-only logic: the starter-template gallery, tap-to-insert merge
/// fields, the on-device content check, and a live merged preview.
struct TemplateEditorView: View {
    @EnvironmentObject var coordinator: MobileCoordinator

    @State private var showingStarters = false
    @State private var showingFields = false
    /// Which text the field palette inserts into.
    @State private var insertTarget: InsertTarget = .body

    private enum InsertTarget { case subject, body }

    /// Merged against the first real recipient when there is one, else the
    /// built-in sample — so the preview is never empty.
    private var previewContact: Contact {
        coordinator.contacts.first ?? .sample
    }

    var body: some View {
        Form {
            starterSection
            subjectSection
            bodySection
            formatSection
            contentCheckSection
            previewSection
        }
        .navigationTitle("Template")
        .onChange(of: coordinator.template) { _, _ in coordinator.refreshPreviews() }
        .onAppear { coordinator.refreshPreviews() }
        .sheet(isPresented: $showingStarters) {
            StarterTemplateSheet { starter in
                coordinator.template = starter.emailTemplate
                coordinator.refreshPreviews()
            }
        }
        .sheet(isPresented: $showingFields) {
            MergeFieldSheet(columns: coordinator.importedHeaders) { token in
                insert(token)
            }
        }
        .safeAreaInset(edge: .bottom) {
            NavigationLink("Next: Review (\(coordinator.sendableCount) ready)") {
                ReviewQueueView()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    // MARK: - Sections

    private var starterSection: some View {
        Section {
            Button {
                showingStarters = true
            } label: {
                Label("Start from a template (\(StarterTemplateCatalog.all.count))",
                      systemImage: "square.grid.2x2")
            }
        } footer: {
            Text("Ready-made emails for outreach, meetings, invoices, renewals, announcements, and hiring — each already wired up with merge fields you can edit.")
        }
    }

    private var subjectSection: some View {
        Section("Subject") {
            TextField("Subject", text: $coordinator.template.subject)
            Button {
                insertTarget = .subject
                showingFields = true
            } label: {
                Label("Insert a merge field", systemImage: "curlybraces")
                    .font(.footnote)
            }
        }
    }

    private var bodySection: some View {
        Section("Body") {
            TextEditor(text: $coordinator.template.body)
                .frame(minHeight: 220)
            Button {
                insertTarget = .body
                showingFields = true
            } label: {
                Label("Insert a merge field", systemImage: "curlybraces")
                    .font(.footnote)
            }
        }
    }

    private var formatSection: some View {
        Section {
            Picker("Format", selection: $coordinator.template.format) {
                ForEach(EmailTemplate.BodyFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
        } header: {
            Text("Format")
        } footer: {
            Text("Use {{Field}} for any column from your list, e.g. {{First Name}} or {{Company}}. Add a fallback with {{First Name|there}} so a blank cell never holds a message back.")
        }
    }

    @ViewBuilder
    private var contentCheckSection: some View {
        let findings = ContentLinter.lint(template: coordinator.template)
        Section {
            if findings.isEmpty {
                Label("Nothing to flag — this reads well.", systemImage: "checkmark.seal")
                    .font(.footnote)
                    .foregroundStyle(.green)
            } else {
                ForEach(findings) { finding in
                    Label {
                        Text(finding.message).font(.footnote)
                    } icon: {
                        Image(systemName: finding.systemImage)
                            .foregroundStyle(finding.severity == .warning ? .orange : .secondary)
                    }
                }
            }
        } header: {
            Text("Content check")
        } footer: {
            Text("Checked on your device — nothing is uploaded. Advisory only; it never blocks a send.")
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        let merge = TemplateMergeEngine.merge(template: coordinator.template, with: previewContact)
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(merge.resolvedSubject.isEmpty ? "(no subject)" : merge.resolvedSubject)
                    .font(.footnote.weight(.semibold))
                Divider()
                Text(merge.resolvedBody.isEmpty ? "(empty body)" : merge.resolvedBody)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !merge.unresolvedFields.isEmpty {
                Label("Missing for this recipient: \(merge.unresolvedFields.joined(separator: ", "))",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Preview")
        } footer: {
            Text(coordinator.contacts.isEmpty
                 ? "Shown against a sample recipient until you import a list."
                 : "Shown against \(previewContact.displayName).")
        }
    }

    // MARK: - Field insertion

    /// Appends a merge token to whichever field the palette was opened from.
    /// (SwiftUI's `TextField`/`TextEditor` don't expose a caret position, so
    /// appending is the honest, predictable behavior.)
    private func insert(_ token: String) {
        switch insertTarget {
        case .subject:
            coordinator.template.subject += token
        case .body:
            coordinator.template.body += token
        }
        coordinator.refreshPreviews()
    }
}

/// Tap-to-insert merge fields: the columns from the imported list first (those
/// are guaranteed to resolve), then the curated catalog.
struct MergeFieldSheet: View {
    let columns: [String]
    let onInsert: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !columns.isEmpty {
                    Section {
                        ForEach(columns, id: \.self) { column in
                            Button {
                                onInsert("{{\(column)}}")
                                dismiss()
                            } label: {
                                Label("{{\(column)}}", systemImage: "checkmark.circle")
                            }
                        }
                    } header: {
                        Text("From your list")
                    } footer: {
                        Text("These columns exist in the list you imported, so they'll always resolve.")
                    }
                }
                ForEach(MergeFieldCatalog.groups) { group in
                    Section(group.title) {
                        ForEach(group.fields) { field in
                            Button {
                                onInsert(field.token)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(field.token).font(.body.monospaced())
                                    Text(field.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Merge Fields")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
