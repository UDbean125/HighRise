import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Stage 2: import the recipient list (CSV file or pasted text) and confirm
/// which column holds the email address.
struct ContactsImportView: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator
    @State private var isImporterPresented = false
    @State private var pastedText = ""
    @State private var showPaste = false
    @State private var showDoNotContact = false

    var body: some View {
        ScrollView {
            // Same two-column treatment as Compose: the import flow on the
            // left, a live "list health" rail on the right once data is in.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    mainColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !coordinator.contacts.isEmpty {
                        healthRail
                            .frame(width: 330)
                    }
                }
                .frame(minWidth: 900)

                VStack(alignment: .leading, spacing: 20) {
                    mainColumn
                    if !coordinator.contacts.isEmpty {
                        healthRail
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1320, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .fileImporter(isPresented: $isImporterPresented,
                      allowedContentTypes: allowedTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                coordinator.importFile(at: url)
            case .failure(let error):
                coordinator.importError = error.localizedDescription
            }
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            importControls
            templateRow

            if let error = coordinator.importError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }

            if !coordinator.contacts.isEmpty {
                columnsCard
                cleanupCard
                skippedRowsCard
                previewCard
            }
        }
    }

    /// Full disclosure of what the automatic import cleanup fixed, plus
    /// one-click suggested repairs that are never applied on their own —
    /// the answer to "why doesn't my list look exactly like my file?".
    @ViewBuilder
    private var cleanupCard: some View {
        let report = coordinator.cleanupReport
        let suggestions = coordinator.cleanupSuggestions
        if !coordinator.cleanupEnabled || !report.isEmpty || !suggestions.isEmpty {
            SectionCard("Import cleanup", systemImage: "wand.and.stars",
                        subtitle: "Fixes apply to this import only — your original file is never touched.") {
                VStack(alignment: .leading, spacing: 12) {
                    if !coordinator.cleanupEnabled {
                        Label("Cleanup is off — this is the data exactly as imported.",
                              systemImage: "eye")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Re-apply Cleanup") { coordinator.cleanupEnabled = true }
                    } else {
                        ForEach(report.changes) { change in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(change.summary, systemImage: icon(for: change.kind))
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let example = change.examples.first {
                                    exampleText(example).padding(.leading, 26)
                                }
                            }
                        }
                        if !suggestions.isEmpty {
                            if !report.isEmpty { Divider() }
                            Text("Suggested fixes")
                                .font(.subheadline.weight(.semibold))
                            ForEach(suggestions) { suggestion in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.title)
                                            .font(.callout)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if let example = suggestion.examples.first {
                                            exampleText(example)
                                        }
                                    }
                                    Spacer()
                                    Button("Apply") {
                                        coordinator.applyCleanupSuggestion(suggestion)
                                    }
                                }
                            }
                        }
                        Divider()
                        Button {
                            coordinator.cleanupEnabled = false
                        } label: {
                            Label("Show Original Data", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.link)
                        .help("Turn off all cleanup and use the import exactly as it was")
                    }
                }
            }
        }
    }

    /// Names the rows silently dropped for having no email address, so
    /// "N rows skipped" in the summary line is never a dead end — the user can
    /// see exactly which rows and fix the source file if it's a mistake.
    @ViewBuilder
    private var skippedRowsCard: some View {
        let skipped = coordinator.skippedRows
        if !skipped.isEmpty {
            SectionCard("Skipped rows", systemImage: "questionmark.folder",
                        subtitle: "\(skipped.count) row\(skipped.count == 1 ? "" : "s") had no value in the email column and weren't imported.") {
                DisclosureGroup("Show skipped rows") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(skipped) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("Row \(row.rowNumber)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 56, alignment: .leading)
                                Text(row.preview)
                                    .font(.callout)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func icon(for kind: ImportCleaner.Change.Kind) -> String {
        switch kind {
        case .whitespace:        return "scissors"
        case .junkValue:         return "eraser"
        case .emailRepair:       return "envelope.badge"
        case .repeatedHeaderRow: return "tablecells"
        }
    }

    private func exampleText(_ example: ImportCleaner.Example) -> some View {
        Text("e.g. “\(example.before)” → \(example.after.isEmpty ? "(blank)" : "“\(example.after)”")")
            .font(.caption).foregroundStyle(.secondary)
            .lineLimit(2)
    }

    /// Live data-quality readout: usable addresses, duplicates, and how
    /// completely each column is filled — the columns that need attention float
    /// to the top.
    private var healthRail: some View {
        let health = ListHealth.assess(contacts: coordinator.contacts,
                                       headers: coordinator.importedHeaders)
        return SectionCard("List health", systemImage: "waveform.path.ecg",
                           subtitle: "Better data, better personalization.") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    StatTile(value: "\(health.validEmails)", label: "usable emails",
                             systemImage: "checkmark.seal.fill",
                             tint: health.invalidEmails == 0 ? .green : Brand.accent)
                    StatTile(value: "\(health.total)", label: "recipients",
                             systemImage: "person.2.fill")
                }

                if health.invalidEmails > 0 {
                    Label("\(health.invalidEmails) missing or invalid address\(health.invalidEmails == 1 ? "" : "es") — those rows will be held back.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if health.duplicates > 0 {
                    Label("\(health.duplicates) duplicate address\(health.duplicates == 1 ? "" : "es") — only the first of each is sent.",
                          systemImage: "person.2.slash")
                        .font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !health.hasIssues {
                    Label("Every address is usable — no duplicates.",
                          systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green)
                }

                let dupeColumns = ColumnHealth.duplicateHeaders(coordinator.importedHeaders)
                if !dupeColumns.isEmpty {
                    Label("Duplicate column\(dupeColumns.count == 1 ? "" : "s"): \(dupeColumns.joined(separator: ", ")) — only the last of each is used. Rename them to keep both.",
                          systemImage: "square.on.square.dashed")
                        .font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                Text("Column completeness")
                    .font(.subheadline.weight(.semibold))

                ForEach(health.columnFill.prefix(12)) { fill in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(fill.column).font(.callout).lineLimit(1)
                            Spacer()
                            Text("\(Int((fill.rate * 100).rounded()))%")
                                .font(.caption.weight(.medium)).monospacedDigit()
                                .foregroundStyle(fill.rate < 0.5 ? .orange : .secondary)
                        }
                        ProgressView(value: fill.rate)
                            .tint(fill.rate < 0.5 ? .orange : Brand.accent)
                    }
                }
                if health.columnFill.count > 12 {
                    Text("+ \(health.columnFill.count - 12) more column\(health.columnFill.count - 12 == 1 ? "" : "s"), all fuller than these.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                domainBreakdown
            }
        }
    }

    /// A compact "top email domains" list — only interesting when a list spans
    /// more than one domain.
    @ViewBuilder
    private var domainBreakdown: some View {
        let stats = EmailDomainStats.of(coordinator.contacts)
        if stats.entries.count >= 2 {
            Divider()
            Text("Top domains").font(.subheadline.weight(.semibold))
            ForEach(stats.entries) { entry in
                HStack {
                    Text(entry.domain).font(.callout).lineLimit(1)
                        .foregroundStyle(entry.domain == "other" ? .secondary : .primary)
                    Spacer()
                    Text("\(entry.count)")
                        .font(.caption.weight(.medium)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var allowedTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .plainText, .text, .pdf, .tabSeparatedText]
        if let xlsx = UTType(filenameExtension: "xlsx") { types.append(xlsx) }
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        // Selectable so the user gets a clear "export to CSV" message rather than
        // the file being greyed out (Numbers' format can't be read directly).
        if let numbers = UTType(filenameExtension: "numbers") { types.append(numbers) }
        return types
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add your contacts").font(.title2).bold()
            Text("Import from a file (CSV, Excel, Word, or PDF) or pull directly from your address book. CSV and Excel need a header row naming each column; Word and PDF are scanned for addresses as a best effort. Messy exports are tidied automatically — every fix is disclosed below, and the original data is one click away.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var importControls: some View {
        HStack(spacing: 12) {
            Button {
                isImporterPresented = true
            } label: {
                Label("Choose File…", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .help("CSV, Excel (.xlsx), Word (.docx), or PDF")
            Button {
                showPaste.toggle()
            } label: {
                Label("Paste List", systemImage: "doc.on.clipboard")
            }
            Button {
                Task { await coordinator.importFromAppleContacts() }
            } label: {
                Label("Apple Contacts", systemImage: "person.crop.circle")
            }
            Button {
                coordinator.importFromOutlookContacts()
            } label: {
                Label("Outlook Contacts", systemImage: "person.crop.circle.badge.questionmark")
            }
            if !coordinator.contacts.isEmpty {
                Spacer()
                Text("\(coordinator.contacts.count) loaded")
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showPaste {
                pastePanel.offset(y: 4)
            }
        }
        .padding(.bottom, showPaste ? 220 : 0)
    }

    private var pastePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste CSV text (first line is the header row)")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $pastedText)
                .font(.body.monospaced())
                .frame(height: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Button("Import Pasted Text") {
                    coordinator.importCSV(pastedText)
                    showPaste = false
                }
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel") { showPaste = false }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .frame(maxWidth: 560)
    }

    private var templateRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .foregroundStyle(.secondary)
            Text("Need a starting point for a large list?")
                .font(.callout).foregroundStyle(.secondary)
            Button("Download CSV Template") { saveTemplate() }
                .buttonStyle(.link)
            Spacer()
            Button {
                showDoNotContact = true
            } label: {
                Label("Do-Not-Contact List", systemImage: "nosign")
            }
            .buttonStyle(.link)
            .help("Manage addresses and domains that are always skipped")
        }
        .sheet(isPresented: $showDoNotContact) {
            DoNotContactView().environmentObject(coordinator)
        }
    }

    /// Writes a ready-to-fill CSV (recommended columns + one example row) to a
    /// location the user picks, so they can build a big list in Excel/Numbers.
    private func saveTemplate() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "HighRise-contacts-template.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSVTemplateExporter.templateCSV().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            coordinator.importError = "Couldn't save the template: \(error.localizedDescription)"
        }
    }

    private var worksheetPicker: some View {
        HStack {
            Text("Worksheet").font(.subheadline).foregroundStyle(.secondary)
            Picker("Worksheet", selection: Binding(
                get: { coordinator.selectedWorksheet ?? "" },
                set: { if !$0.isEmpty { coordinator.selectWorksheet($0) } }
            )) {
                ForEach(coordinator.availableWorksheets, id: \.name) { sheet in
                    Text(sheet.name).tag(sheet.name)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
            Text("This workbook has \(coordinator.availableWorksheets.count) sheets.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var columnsCard: some View {
        SectionCard("Columns", systemImage: "tablecells",
                    subtitle: "Tell HighRise which columns to use.") {
            VStack(alignment: .leading, spacing: 12) {
                if !coordinator.availableWorksheets.isEmpty {
                    worksheetPicker
                    Divider()
                }
                emailColumnPicker
                attachmentColumnPicker
            }
        }
    }

    private var previewCard: some View {
        SectionCard("Preview", systemImage: "list.bullet.rectangle") {
            summaryAndPreview
        }
    }

    private var emailColumnPicker: some View {
        HStack {
            Text("Email column").font(.subheadline).foregroundStyle(.secondary)
            Picker("Email column", selection: Binding(
                get: { coordinator.emailColumn ?? "" },
                set: { coordinator.emailColumn = $0.isEmpty ? nil : $0 }
            )) {
                ForEach(coordinator.importedHeaders, id: \.self) { header in
                    Text(header).tag(header)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
            Spacer()
        }
    }

    private var attachmentColumnPicker: some View {
        HStack {
            Text("Attachment column").font(.subheadline).foregroundStyle(.secondary)
            Picker("Attachment column", selection: Binding(
                get: { coordinator.attachmentColumn ?? "" },
                set: { coordinator.attachmentColumn = $0.isEmpty ? nil : $0 }
            )) {
                Text("None").tag("")
                ForEach(coordinator.importedHeaders, id: \.self) { header in
                    Text(header).tag(header)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
            Text("Optional — a per-recipient file path (use “;” for several).")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var summaryAndPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let summary = coordinator.importSummary {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }
            Table(coordinator.contacts.prefix(50).map { $0 }) {
                TableColumn("Name") { contact in
                    HStack(spacing: 8) {
                        Avatar(name: contact.displayName, size: 22)
                        Text(contact.displayName).lineLimit(1)
                    }
                }
                TableColumn("Email", value: \.email)
                TableColumn("Valid") { contact in
                    Image(systemName: EmailValidator.isValid(contact.email) ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(EmailValidator.isValid(contact.email) ? .green : .orange)
                        .accessibilityLabel(EmailValidator.isValid(contact.email) ? "Valid email" : "Invalid email")
                }
                .width(50)
            }
            .frame(minHeight: 200, maxHeight: 320)
            if coordinator.contacts.count > 50 {
                Text("Showing first 50 of \(coordinator.contacts.count).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
