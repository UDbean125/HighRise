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
                    previewCard
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
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
            Text("Import from a file (CSV, Excel, Word, or PDF) or pull directly from your address book. CSV and Excel need a header row naming each column; Word and PDF are scanned for addresses as a best effort.")
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
                TableColumn("Name", value: \.displayName)
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
