import SwiftUI
import UniformTypeIdentifiers

/// Step 1: pick a CSV export and turn it into contacts via the shared
/// `ImportPipeline` (the same cleanup/column-detection logic the Mac app uses).
struct ImportView: View {
    @EnvironmentObject var coordinator: MobileCoordinator
    @State private var showingImporter = false
    @State private var showEnrichment = false

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
                    if !coordinator.fillProposals.isEmpty {
                        Section {
                            ForEach(coordinator.fillProposals) { proposal in
                                Button {
                                    coordinator.applyFillProposal(proposal)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(proposal.title)
                                            .font(.footnote)
                                            .foregroundStyle(.primary)
                                        if let example = proposal.examples.first {
                                            Text("\(example.before) → \(example.after)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                            if coordinator.fillProposals.count > 1 {
                                Button("Fill All") {
                                    coordinator.applyAllFillProposals()
                                }
                                .font(.footnote.weight(.semibold))
                            }
                        } header: {
                            Text("Fill missing data")
                        } footer: {
                            Text("Optional fills for blank cells, worked out from the list itself — nothing is looked up online, and existing values are never changed. Tap a fill to apply it.")
                        }
                    }
                    if coordinator.enrichmentCandidateCount > 0 {
                        Section {
                            Button {
                                showEnrichment = true
                            } label: {
                                Label("Find & Fill Online…", systemImage: "magnifyingglass")
                            }
                        } footer: {
                            Text("\(coordinator.enrichmentCandidateCount) row\(coordinator.enrichmentCandidateCount == 1 ? "" : "s") could use help — look up missing emails and details with Apollo.io using your own account.")
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
        .navigationTitle("Import")
        .sheet(isPresented: $showEnrichment) {
            EnrichmentSheet().environmentObject(coordinator)
        }
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
