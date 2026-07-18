import SwiftUI

/// iOS twin of the macOS "Find & Fill Online" sheet: Apollo key (Keychain),
/// one-tap search over rows that need help, review list, apply. Same rules —
/// user-triggered only, suggestions only, valid emails never touched.
struct EnrichmentSheet: View {
    @EnvironmentObject var coordinator: MobileCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = EnrichmentKeyStore.key(for: EnrichmentKeyStore.apolloAccount) ?? ""
    @State private var excluded: Set<String> = []

    private var acceptedFills: [EnrichmentEngine.CellFill] {
        coordinator.enrichmentFills.filter { !excluded.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Apollo API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("Get a key from Apollo",
                         destination: URL(string: "https://app.apollo.io/#/settings/integrations/api")!)
                } header: {
                    Text("Apollo account")
                } footer: {
                    Text("Company and name details from your list are sent to Apollo.io for matching — only when you tap Search. Results are suggestions you approve below; your original file is never changed. Searching uses your Apollo credits.")
                }

                Section {
                    if coordinator.isEnriching {
                        HStack {
                            ProgressView(value: coordinator.enrichmentProgress)
                            Button("Cancel") { coordinator.cancelEnrichment() }
                        }
                    } else {
                        Button {
                            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            EnrichmentKeyStore.setKey(key, for: EnrichmentKeyStore.apolloAccount)
                            excluded = []
                            coordinator.findAndFillOnline(provider: ApolloEnrichmentProvider(apiKey: key))
                        } label: {
                            Label("Search Apollo (\(min(coordinator.enrichmentCandidateCount, EnrichmentEngine.maxRowsPerRun)) rows)",
                                  systemImage: "magnifyingglass")
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                                  || coordinator.enrichmentCandidateCount == 0)
                    }
                    if let error = coordinator.enrichmentError {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                    if let summary = coordinator.enrichmentSummary {
                        Text(summary).foregroundStyle(.secondary).font(.footnote)
                    }
                }

                if !coordinator.enrichmentFills.isEmpty {
                    Section("Suggested fills — toggle off any you don't want") {
                        ForEach(coordinator.enrichmentFills) { fill in
                            Toggle(isOn: Binding(
                                get: { !excluded.contains(fill.id) },
                                set: { include in
                                    if include { excluded.remove(fill.id) } else { excluded.insert(fill.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(fill.rowLabel) — \(fill.column)").font(.footnote)
                                    Text(fill.isCorrection
                                         ? "“\(fill.before)” → “\(fill.after)”"
                                         : "(blank) → “\(fill.after)”")
                                        .font(.caption2)
                                        .foregroundStyle(fill.isCorrection ? .orange : .secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Button("Apply \(acceptedFills.count) Fill\(acceptedFills.count == 1 ? "" : "s")") {
                            coordinator.applyEnrichmentFills(acceptedFills)
                            dismiss()
                        }
                        .disabled(acceptedFills.isEmpty)
                    }
                }
            }
            .navigationTitle("Find & Fill Online")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
