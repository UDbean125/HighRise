import SwiftUI
import UniformTypeIdentifiers

/// Step 1: pick a CSV export and turn it into contacts via the shared
/// `ImportPipeline` (the same cleanup/column-detection logic the Mac app uses).
struct ImportView: View {
    @EnvironmentObject var coordinator: MobileCoordinator
    @State private var showingImporter = false

    var body: some View {
        VStack(spacing: 16) {
            if coordinator.contacts.isEmpty {
                ContentUnavailableView(
                    "Import a Recipient List",
                    systemImage: "tray.and.arrow.down",
                    description: Text("Pick a CSV export to get started.")
                )
            } else {
                List {
                    if let summary = coordinator.importSummary {
                        Section("Import") {
                            Text(summary).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section("Recipients (\(coordinator.contacts.count))") {
                        ForEach(coordinator.contacts) { contact in
                            VStack(alignment: .leading) {
                                Text(contact.displayName)
                                Text(contact.email).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let error = coordinator.importError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Button(coordinator.contacts.isEmpty ? "Choose CSV File…" : "Choose a Different File…") {
                showingImporter = true
            }
            .buttonStyle(.borderedProminent)

            if !coordinator.contacts.isEmpty {
                NavigationLink("Next: Write Template") {
                    TemplateEditorView()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.bottom)
        .navigationTitle("HighRise")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            switch result {
            case .success(let url):
                importFile(at: url)
            case .failure(let error):
                coordinator.importError = error.localizedDescription
            }
        }
    }

    private func importFile(at url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            coordinator.importError = "Couldn't access that file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: url)
            coordinator.importCSV(data: data, sourceLabel: url.lastPathComponent)
        } catch {
            coordinator.importError = error.localizedDescription
        }
    }
}
