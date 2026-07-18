import SwiftUI

/// The "Find & Fill Online" sheet: paste an Apollo API key once (kept in the
/// Keychain), run a lookup over the rows that need help, review every
/// proposed fill, and apply only the ones you accept.
///
/// This is the app's single deliberate exception to "nothing leaves your
/// Mac": name/company/domain values from the list are sent to Apollo.io to
/// look up business emails and missing fields — only when the user clicks
/// Search, and clearly labeled as such.
struct EnrichmentView: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = EnrichmentKeyStore.key(for: EnrichmentKeyStore.apolloAccount) ?? ""
    /// Fills the user has unchecked in the review list.
    @State private var excluded: Set<String> = []

    private var acceptedFills: [EnrichmentEngine.CellFill] {
        coordinator.enrichmentFills.filter { !excluded.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            keyRow
            runRow
            if let error = coordinator.enrichmentError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let summary = coordinator.enrichmentSummary {
                Label(summary, systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !coordinator.enrichmentFills.isEmpty {
                resultsList
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Find & fill online", systemImage: "network.badge.shield.half.filled")
                .font(.title3.bold())
            Text("Looks up missing emails, names, titles, and websites with Apollo.io using your own Apollo account. Company and name details from your list are sent to Apollo for matching — only when you click Search, and results are suggestions you review below, never automatic changes. Your file on disk is never touched.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var keyRow: some View {
        HStack(spacing: 8) {
            SecureField("Apollo API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
            Link("Get a key", destination: URL(string: "https://app.apollo.io/#/settings/integrations/api")!)
                .font(.callout)
            Spacer()
        }
    }

    private var runRow: some View {
        HStack(spacing: 12) {
            Button {
                let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                EnrichmentKeyStore.setKey(key, for: EnrichmentKeyStore.apolloAccount)
                excluded = []
                coordinator.findAndFillOnline(provider: ApolloEnrichmentProvider(apiKey: key))
            } label: {
                Label("Search Apollo", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                      || coordinator.isEnriching
                      || coordinator.enrichmentCandidateCount == 0)

            if coordinator.isEnriching {
                ProgressView(value: coordinator.enrichmentProgress)
                    .frame(maxWidth: 200)
                Button("Cancel") { coordinator.cancelEnrichment() }
            } else {
                Text(candidateNote)
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var candidateNote: String {
        let n = coordinator.enrichmentCandidateCount
        if n == 0 { return "Every row already has a valid email and full details." }
        let capped = min(n, EnrichmentEngine.maxRowsPerRun)
        var note = "\(n) row\(n == 1 ? "" : "s") could use help"
        if n > EnrichmentEngine.maxRowsPerRun {
            note += " — the first \(capped) are searched per run"
        }
        return note + ". Searching uses your Apollo credits."
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested fills — uncheck any you don't want")
                .font(.subheadline.weight(.semibold))
            List(coordinator.enrichmentFills) { fill in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { !excluded.contains(fill.id) },
                        set: { include in
                            if include { excluded.remove(fill.id) } else { excluded.insert(fill.id) }
                        }
                    ))
                    .labelsHidden()
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(fill.rowLabel) — \(fill.column)")
                            .font(.callout)
                        Text(fill.isCorrection
                             ? "“\(fill.before)” → “\(fill.after)”"
                             : "(blank) → “\(fill.after)”")
                            .font(.caption)
                            .foregroundStyle(fill.isCorrection ? .orange : .secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
            .frame(minHeight: 180)
        }
    }

    private var footer: some View {
        HStack {
            Button("Close") { dismiss() }
            Spacer()
            if !coordinator.enrichmentFills.isEmpty {
                Button {
                    coordinator.applyEnrichmentFills(acceptedFills)
                } label: {
                    Label("Apply \(acceptedFills.count) Fill\(acceptedFills.count == 1 ? "" : "s")",
                          systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(acceptedFills.isEmpty)
            }
        }
    }
}
