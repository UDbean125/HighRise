import Foundation

/// The iOS app's single source of truth, driving import → template → review →
/// send. A deliberately smaller sibling of `HighRiseCoordinator` (the macOS
/// version): no do-not-contact list, attachments, scheduling, or Contacts
/// import — just enough to get a CSV list merged and queued for sending.
@MainActor
final class MobileCoordinator: ObservableObject {

    /// Quit-safe persistence. iOS kills backgrounded apps without warning,
    /// so the imported list and the working template are written to disk and
    /// restored on the next launch — see `MobileSessionStore`.
    private let sessionStore: MobileSessionStore

    /// The user's own saved templates — the same on-device library type the
    /// Mac uses, so a template saved here behaves identically there.
    private let library: TemplateLibraryStore
    @Published private(set) var savedTemplates: [SavedTemplate] = []

    /// The do-not-contact list. Same store the Mac uses, so an address
    /// suppressed on either device is honored on both — without it, a list
    /// sent from the phone would email people who asked not to be contacted.
    private let doNotContact: DoNotContactStore
    @Published private(set) var suppressionEntries: [SuppressionEntry] = []

    /// A durable, record-by-record journal of who has already been emailed.
    ///
    /// `SendQueue` lives only in memory, and iOS terminates backgrounded apps
    /// without warning — while the iOS send flow is inherently long, because
    /// it is one `MFMailComposeViewController` sheet per recipient with the
    /// user tapping Send each time. So a kill 40 recipients into a 100-person
    /// run used to leave no trace at all: the next launch restored the list
    /// and the template, rebuilt the queue from *every* sendable recipient,
    /// and silently emailed those 40 people a second time. The Mac has had
    /// this protection (`SendRunLog`); Windows gained it in its run journal.
    /// This is the same type writing the same file.
    private let runLog: SendRunLogStore
    private var currentRunJournal: SendRunLog?

    /// The journal of a run that never finished — i.e. the app was killed
    /// mid-send. Surfaced in the UI, and subtracted from the next queue.
    @Published private(set) var incompleteLastRun: SendRunLog?

    /// Every store is injectable so tests never read or write the real
    /// container.
    init(sessionStore: MobileSessionStore = MobileSessionStore(),
         library: TemplateLibraryStore = TemplateLibraryStore(),
         doNotContact: DoNotContactStore = DoNotContactStore(),
         runLog: SendRunLogStore = SendRunLogStore()) {
        self.sessionStore = sessionStore
        self.library = library
        self.doNotContact = doNotContact
        self.runLog = runLog
        incompleteLastRun = runLog.loadIncomplete()
        savedTemplates = library.templates
        suppressionEntries = doNotContact.entries
        restoreSession()
    }

    // MARK: - Do-not-contact

    /// Adds an address to the do-not-contact list. Returns false on invalid
    /// or already-present input so the UI can say so.
    @discardableResult
    func suppressAddress(_ address: String, note: String? = nil) -> Bool {
        let added = doNotContact.addAddress(address, note: note)
        if added {
            suppressionEntries = doNotContact.entries
            refreshPreviews()
        }
        return added
    }

    /// Adds a whole domain (e.g. `acme.com`).
    @discardableResult
    func suppressDomain(_ domain: String, note: String? = nil) -> Bool {
        let added = doNotContact.addDomain(domain, note: note)
        if added {
            suppressionEntries = doNotContact.entries
            refreshPreviews()
        }
        return added
    }

    func removeSuppression(_ entry: SuppressionEntry) {
        doNotContact.remove(entry)
        suppressionEntries = doNotContact.entries
        refreshPreviews()
    }

    /// How many of the current recipients are held back by the list.
    var suppressedCount: Int { previews.filter(\.isSuppressed).count }

    // MARK: - Saved templates

    /// Saves the working template under `name`, replacing a same-named one.
    func saveCurrentTemplate(as name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        library.save(template, as: trimmed)
        savedTemplates = library.templates
    }

    func loadTemplate(_ saved: SavedTemplate) {
        template = saved.template
        refreshPreviews()
        saveSession()
    }

    func deleteTemplate(_ saved: SavedTemplate) {
        library.delete(id: saved.id)
        savedTemplates = library.templates
    }

    /// Whether there's anything worth saving yet.
    var canSaveTemplate: Bool {
        !template.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !template.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @Published var contacts: [Contact] = []
    /// Column headers from the current import — the Compose screen offers
    /// these as tap-to-insert merge fields, since they always resolve.
    @Published private(set) var importedHeaders: [String] = []
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

    /// Suppresses session writes while `restoreSession` populates state, so
    /// a half-restored session can never overwrite the good one on disk.
    private var isRestoring = false

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

    /// Outcomes of the most recently completed send session, snapshotted when
    /// a new queue replaces a finished one — so the Home dashboard's "you're
    /// all set" state survives starting another run.
    @Published private(set) var lastRunOutcomes: [SendOutcome] = []

    /// Whether the current (or most recent) send queue has actually sent
    /// anything — used to pick the Home dashboard's "next step" suggestion.
    var hasCompletedASend: Bool {
        if let queue, queue.isFinished, queue.outcomes.contains(where: \.isSuccess) {
            return true
        }
        return lastRunOutcomes.contains { $0.isSuccess }
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
            // A new list is a new campaign: drop the old queue and the
            // previous run's completion state with it.
            queue = nil
            lastRunOutcomes = []
            saveSession()
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Applies one missing-data fill proposal (only blank cells are written)
    /// and re-derives contacts, previews, and the remaining proposals.
    func applyFillProposal(_ proposal: ContactDataFiller.Proposal) {
        appliedFills.append(proposal)
        rerunPipeline()
        saveSession()
    }

    /// Applies every currently offered fill at once, most confident first.
    func applyAllFillProposals() {
        guard !fillProposals.isEmpty else { return }
        appliedFills.append(contentsOf: fillProposals)
        rerunPipeline()
        saveSession()
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
        importedHeaders = result.importedHeaders
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
                    onProgress: { [weak self] done, total in
                        guard let self else { return }
                        Task { @MainActor in
                            self.enrichmentProgress = total > 0 ? Double(done) / Double(total) : 0
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
        // Passing the suppression check is what actually enforces the
        // do-not-contact list — without it a suppressed address merges as
        // sendable and goes out.
        previews = TemplateMergeEngine.mergeAll(
            template: template,
            contacts: contacts,
            isSuppressed: { [doNotContact] in doNotContact.isSuppressed($0.email) })
    }

    // MARK: - Session persistence

    /// Writes the current session to disk. Called when the app leaves the
    /// foreground (see `ContentView`'s scenePhase handler) and after the
    /// edits that are expensive to lose.
    func saveSession() {
        guard !isRestoring else { return }
        sessionStore.save(MobileSessionSnapshot(rawTable: rawTable,
                                                sourceLabel: sourceLabel,
                                                appliedFills: appliedFills,
                                                template: template))
    }

    /// Rebuilds the previous session at launch: the template immediately,
    /// then the recipient list by replaying the raw table and accepted fills
    /// through the shared `ImportPipeline` — identical input, identical
    /// contacts, no stale derived state.
    private func restoreSession() {
        guard let snapshot = sessionStore.load(), !snapshot.isEmpty else { return }
        isRestoring = true
        defer { isRestoring = false }
        template = snapshot.template
        guard let table = snapshot.rawTable else {
            refreshPreviews()
            return
        }
        rawTable = table
        sourceLabel = snapshot.sourceLabel
        appliedFills = snapshot.appliedFills
        rerunPipeline()
    }

    /// Clears the imported list and the saved session — the "start over"
    /// escape hatch, so a restored list is never a trap.
    func clearSession() {
        rawTable = nil
        currentTable = nil
        sourceLabel = ""
        appliedFills = []
        contacts = []
        importedHeaders = []
        importSummary = nil
        importError = nil
        fillProposals = []
        enrichmentFills = []
        enrichmentSummary = nil
        queue = nil
        lastRunOutcomes = []
        previews = []
        sessionStore.clear()
        // "Start over" has to clear the journal too, or a run interrupted
        // before the reset would keep filtering a brand-new list.
        discardInterruptedRun()
        currentRunJournal = nil
    }

    /// Builds a fresh send queue from whatever's currently sendable. Called
    /// when the user enters the send screen with no queue — or with a
    /// finished one, which previously dead-ended sending forever (the queue
    /// was only ever cleared by a re-import). A finished run's outcomes are
    /// snapshotted first so the Home dashboard's state survives.
    ///
    /// Anyone an *interrupted* run already reached is left out. That is the
    /// whole point of the journal: re-importing the same list and pressing
    /// Send is the innocent gesture that would otherwise double-email them.
    func startSendQueue() {
        if let finished = queue, finished.isFinished, !finished.outcomes.isEmpty {
            lastRunOutcomes = finished.outcomes
        }
        let delivered = interruptedDeliveries
        let items = previews
            .filter(\.isSendable)
            .filter { !delivered.contains($0.contact.email.lowercased()) }
        resumedFromInterruptedCount = delivered.count
        queue = SendQueue(items: items)
        openRunJournal(total: items.count)
        // Nothing left to send means the campaign is actually done — close
        // the journal now, or it stays "interrupted" forever and keeps
        // filtering lists it has nothing to do with.
        if items.isEmpty { finishRunJournal() }
    }

    // MARK: - Run journal

    /// Addresses already reached by a run that never finished.
    ///
    /// A *finished* run filters nothing — starting another send to the same
    /// list is a deliberate act, and the app should not silently refuse it.
    private var interruptedDeliveries: Set<String> {
        guard let journal = currentRunJournal ?? incompleteLastRun,
              !journal.finished else { return [] }
        return Set(journal.records
            .filter { $0.status == "sent" || $0.status == "drafted" }
            .map { $0.email.lowercased() })
    }

    /// How many people the interrupted run had already reached at the moment
    /// the current queue was built. Frozen there on purpose: reading
    /// `interruptedDeliveries` live would climb as this run sends, and the
    /// notice is about the *previous* run, not this one.
    @Published private(set) var resumedFromInterruptedCount = 0

    /// Opens the journal for a run that is about to start. An interrupted
    /// run's records are carried forward rather than overwritten: if the
    /// resumed run is *also* killed, the next launch still has to know about
    /// everyone the first one emailed.
    private func openRunJournal(total: Int) {
        var journal: SendRunLog
        if let carried = incompleteLastRun, !carried.finished {
            journal = carried
            journal.total = journal.deliveredCount + total
            journal.finished = false
        } else {
            journal = SendRunLog(startedAt: Date(), mode: "sent", total: total)
        }
        currentRunJournal = journal
        runLog.save(journal)
    }

    /// Records what happened to the current recipient — in the live queue and,
    /// durably, in the journal. The disk write happens per recipient on
    /// purpose: a batched write is exactly the record a mid-run kill destroys.
    func recordOutcome(_ status: SendOutcome.Status) {
        guard let contact = queue?.current?.contact else { return }
        queue?.recordOutcome(status)

        let statusText: String
        let reason: String?
        switch status {
        case .sent: statusText = "sent"; reason = nil
        case .drafted: statusText = "drafted"; reason = nil
        case .skipped(let why): statusText = "skipped"; reason = why
        case .failed(let why): statusText = "failed"; reason = why
        }

        if var journal = currentRunJournal {
            journal.records.append(SendRunLog.Record(email: contact.email,
                                                     name: contact.displayName,
                                                     status: statusText,
                                                     reason: reason,
                                                     at: Date()))
            currentRunJournal = journal
            runLog.save(journal)
        }

        if queue?.isFinished == true { finishRunJournal() }
    }

    /// Closes the journal once the run ends normally. A closed journal stops
    /// filtering future queues and is no longer offered as interrupted.
    private func finishRunJournal() {
        guard var journal = currentRunJournal else { return }
        journal.finished = true
        currentRunJournal = journal
        runLog.save(journal)
        incompleteLastRun = nil
    }

    /// Forgets an interrupted run without resuming it — the deliberate
    /// "email them anyway" escape hatch, so the protection is never a trap.
    func discardInterruptedRun() {
        guard var journal = incompleteLastRun else { return }
        journal.finished = true
        runLog.save(journal)
        incompleteLastRun = nil
        currentRunJournal = nil
    }
}
