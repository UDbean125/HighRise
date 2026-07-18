import Foundation

/// The iOS app's single source of truth, driving import → template → review →
/// send. A deliberately smaller sibling of `HighRiseCoordinator` (the macOS
/// version): no do-not-contact list, attachments, scheduling, or Contacts
/// import — just enough to get a CSV list merged and queued for sending.
@MainActor
final class MobileCoordinator: ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var importSummary: String?
    @Published var importError: String?

    /// Opt-in fills for *missing* data (blank names inferable from the email
    /// address or a Full Name column, blank companies from coworkers' rows, …),
    /// mirroring the macOS import screen. Never applied on their own; only
    /// blank cells are ever written.
    @Published private(set) var fillProposals: [ContactDataFiller.Proposal] = []

    /// The import as parsed, kept so accepted fills can be re-derived through
    /// the same pipeline pass the Mac app uses.
    private var rawTable: RecipientTable?
    private var sourceLabel = ""
    /// The cleaned table the pipeline last produced — what enrichment runs
    /// against, so its row indices match what the user sees.
    private var currentTable: RecipientTable?

    /// Fill proposals the user accepted, replayed in order on each re-derive.
    private var appliedFills: [ContactDataFiller.Proposal] = []

    @Published var template = EmailTemplate()
    @Published var previews: [MergePreview] = []

    @Published var queue: SendQueue?

    var sendableCount: Int { previews.filter(\.isSendable).count }
    var blockedCount: Int { previews.count - sendableCount }

    /// Whether the template has any content yet — the Home dashboard's
    /// first gate, mirroring the macOS app's "write your email first" flow.
    var hasTemplateContent: Bool {
        !template.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !template.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether there's something worth reviewing yet (a template and at
    /// least one imported contact).
    var canProceedToReview: Bool { hasTemplateContent && !contacts.isEmpty }

    /// Whether the current (or most recent) send queue has actually sent
    /// anything — used to pick the Home dashboard's "next step" suggestion.
    var hasCompletedASend: Bool {
        guard let queue, queue.isFinished else { return false }
        return queue.outcomes.contains { $0.isSuccess }
    }

    /// Parses `data` as CSV, runs it through the same cleanup/import pipeline
    /// the Mac app uses, and refreshes the merge preview against the current
    /// template.
    func importCSV(data: Data, sourceLabel: String) {
        importError = nil
        guard let text = CSVParser.decode(data) else {
            importError = "Couldn't read that file — check it's a text CSV export."
            return
        }
        do {
            let table = try CSVParser.parse(text)
            rawTable = table
            self.sourceLabel = sourceLabel
            appliedFills = []
            rerunPipeline()
            queue = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Applies one missing-data fill proposal (only blank cells are written)
    /// and re-derives contacts, previews, and the remaining proposals.
    func applyFillProposal(_ proposal: ContactDataFiller.Proposal) {
        appliedFills.append(proposal)
        rerunPipeline()
    }

    /// Applies every currently offered fill at once, most confident first.
    func applyAllFillProposals() {
        guard !fillProposals.isEmpty else { return }
        appliedFills.append(contentsOf: fillProposals)
        rerunPipeline()
    }

    /// Re-derives everything from the retained raw table: cleanup, any
    /// accepted fills, contacts, and the remaining fill proposals.
    private func rerunPipeline() {
        guard let rawTable else { return }
        let result = ImportPipeline.run(
            table: rawTable, sourceLabel: sourceLabel, cleanupEnabled: true,
            appliedSuggestions: [], appliedFills: appliedFills,
            emailColumnOverride: nil)
        contacts = result.contacts
        importSummary = result.importSummary
        fillProposals = result.fillProposals
        currentTable = result.parsedTable
        refreshPreviews()
    }

    // MARK: - Online enrichment (Find & Fill Online)

    /// Same contract as the macOS coordinator: results are proposals the user
    /// reviews; nothing is sent anywhere except from this explicit flow.
    @Published private(set) var enrichmentFills: [EnrichmentEngine.CellFill] = []
    @Published private(set) var enrichmentSummary: String?
    @Published private(set) var isEnriching = false
    @Published private(set) var enrichmentProgress: Double = 0
    @Published var enrichmentError: String?
    private var enrichmentTask: Task<Void, Never>?

    var enrichmentCandidateCount: Int {
        guard let table = currentTable ?? rawTable else { return 0 }
        let emailIndex = EnrichmentEngine.emailColumnIndex(in: table, named: nil)
        return EnrichmentEngine.rowsNeedingHelp(table, emailIndex: emailIndex).count
    }

    func findAndFillOnline(provider: EnrichmentProvider) {
        guard let table = currentTable ?? rawTable, !isEnriching else { return }
        isEnriching = true
        enrichmentError = nil
        enrichmentFills = []
        enrichmentSummary = nil
        enrichmentProgress = 0

        enrichmentTask = Task { [weak self] in
            do {
                let result = try await EnrichmentEngine.run(
                    table: table, emailColumn: nil, provider: provider,
                    onProgress: { done, total in
                        Task { @MainActor [weak self] in
                            self?.enrichmentProgress = total > 0 ? Double(done) / Double(total) : 0
                        }
                    })
                guard let self, !Task.isCancelled else { return }
                self.enrichmentFills = result.fills
                var summary = "Queried \(result.queried) row\(result.queried == 1 ? "" : "s") · \(result.fills.count) suggested fill\(result.fills.count == 1 ? "" : "s")"
                if result.noMatch > 0 { summary += " · no match for \(result.noMatch)" }
                self.enrichmentSummary = summary
            } catch is CancellationError {
            } catch {
                self?.enrichmentError = error.localizedDescription
            }
            self?.isEnriching = false
        }
    }

    func cancelEnrichment() {
        enrichmentTask?.cancel()
        enrichmentTask = nil
        isEnriching = false
    }

    /// Applies accepted fills and adopts the result as the new baseline, then
    /// re-derives contacts and the offline fill proposals against it.
    func applyEnrichmentFills(_ fills: [EnrichmentEngine.CellFill]) {
        guard !fills.isEmpty, let table = currentTable ?? rawTable else { return }
        let (updated, applied) = EnrichmentEngine.apply(fills, to: table)
        guard applied > 0 else { return }
        rawTable = updated
        appliedFills = []
        rerunPipeline()
        enrichmentFills = []
        enrichmentSummary = "Applied \(applied) fill\(applied == 1 ? "" : "s") to the list."
    }

    func refreshPreviews() {
        previews = TemplateMergeEngine.mergeAll(template: template, contacts: contacts)
    }

    /// Builds a fresh send queue from whatever's currently sendable. Called
    /// once when the user enters the send screen.
    func startSendQueue() {
        queue = SendQueue(items: previews.filter(\.isSendable))
    }
}
