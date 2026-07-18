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
        refreshPreviews()
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
