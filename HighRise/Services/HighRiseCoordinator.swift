import Foundation
import SwiftUI
import Combine
import os

/// The app's single source of truth, driving the import → review → send flow.
///
/// SwiftUI views observe this; all mutation happens on the main actor. The
/// heavy lifting (parsing, merging, scripting) is delegated to the pure
/// services so this type stays focused on orchestration and published state.
@MainActor
final class HighRiseCoordinator: ObservableObject {

    enum Stage: Int, CaseIterable {
        case home, compose, contacts, review, send

        /// The four numbered workflow steps, excluding the Home hub.
        static var workflow: [Stage] { [.compose, .contacts, .review, .send] }
    }

    // MARK: - Published state

    @Published var stage: Stage = .home
    @Published var template = EmailTemplate()

    /// Drives the first-run (and replayable) welcome tour sheet.
    @Published var isShowingWelcome = false
    /// Set by the welcome tour to ask the Compose screen to open the starter
    /// gallery once it appears.
    @Published var pendingStarterGalleryRequest = false

    /// Jumps to Compose and asks it to open the starter-template gallery —
    /// the welcome tour's "start with a template" call to action.
    func beginWithStarterTemplate() {
        stage = .compose
        pendingStarterGalleryRequest = true
        isShowingWelcome = false
    }

    // MARK: - Interactive walkthrough (coach-marks)

    /// True while the coach-mark tour is spotlighting the real dashboard.
    @Published var isTouring = false
    /// Index into `HighRiseTour.steps` for the current spotlight.
    @Published var tourIndex = 0

    /// The step currently being spotlighted, or nil when the tour is off.
    var currentTourStep: TourStep? {
        guard isTouring, HighRiseTour.steps.indices.contains(tourIndex) else { return nil }
        return HighRiseTour.steps[tourIndex]
    }

    var isLastTourStep: Bool { tourIndex >= HighRiseTour.steps.count - 1 }

    /// Dismisses the welcome sheet and starts the walkthrough on Compose.
    func startTour() {
        stage = .compose
        tourIndex = 0
        isShowingWelcome = false
        isTouring = true
    }

    func advanceTour() {
        if isLastTourStep { endTour() } else { tourIndex += 1 }
    }

    func retreatTour() { if tourIndex > 0 { tourIndex -= 1 } }

    func endTour() {
        isTouring = false
        tourIndex = 0
    }

    @Published private(set) var contacts: [Contact] = []
    @Published private(set) var importedHeaders: [String] = []
    @Published var emailColumn: String? { didSet { remapContacts() } }
    @Published private(set) var importSummary: String?
    @Published var importError: String?

    /// Optional column whose value is a per-recipient attachment file path
    /// (`;`-separated for several, `~` expanded). Nil = no per-recipient files.
    @Published var attachmentColumn: String?

    /// For a multi-sheet `.xlsx`: the visible worksheets and which one is loaded,
    /// so the import screen can offer a tab picker. Empty for other sources and
    /// single-sheet workbooks.
    @Published private(set) var availableWorksheets: [XLSXReader.Worksheet] = []
    @Published private(set) var selectedWorksheet: String?
    private var workbookURL: URL?

    @Published var selectedClient: MailClient = .appleMail
    @Published var sendMode: SendMode = .draft

    /// Campaign-wide CC / BCC / BCC-me applied to every message in the run.
    @Published var envelope = CampaignEnvelope()

    /// Optional From identity for Apple Mail (e.g. `Jordan <jordan@work.com>`),
    /// which must match a configured Mail account. Empty = default account.
    @Published var senderIdentity: String = ""

    /// Optional opt-out footer: when enabled and given a valid reply address, a
    /// `mailto:` unsubscribe line is appended to every message body at send time.
    @Published var unsubscribeEnabled = false
    @Published var unsubscribeReplyTo = ""
    @Published var unsubscribeNote = ""

    /// Appends the unsubscribe footer to `body` for `contact`, if enabled and the
    /// reply address is valid. Applied at send time so `previews` stays pure.
    private func bodyWithFooter(_ body: String, for contact: Contact) -> String {
        guard unsubscribeEnabled else { return body }
        let replyTo = unsubscribeReplyTo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailValidator.isValid(replyTo) else { return body }
        let footer = template.format == .html
            ? UnsubscribeFooter.html(replyTo: replyTo, recipientEmail: contact.email, note: unsubscribeNote)
            : UnsubscribeFooter.plainText(replyTo: replyTo, recipientEmail: contact.email, note: unsubscribeNote)
        return body + footer
    }

    /// The sender to hand the builder — only for Apple Mail (Outlook sends from
    /// its own default account), and only when the user set one.
    private var effectiveSender: String? {
        guard selectedClient == .appleMail else { return nil }
        let trimmed = senderIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The name of a Mail signature to attach (Apple Mail only), if set.
    @Published var signatureName: String = ""
    private var effectiveSignature: String? {
        guard selectedClient == .appleMail else { return nil }
        let trimmed = signatureName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Files attached to every message in the run (same files for all recipients).
    @Published var attachments: [URL] = []

    /// Attachment files that no longer exist on disk — the run is blocked until
    /// these are removed or restored, rather than failing per-recipient.
    var missingAttachments: [URL] { AttachmentSet.missing(attachments) }

    /// A heads-up when the attachments are large enough that servers may bounce
    /// the message; `nil` when within a safe size.
    var attachmentSizeWarning: String? {
        AttachmentSet.oversizeWarning(totalBytes: AttachmentSet.totalBytes(attachments))
    }

    /// How the live send is paced (delay, jitter, batch pauses). Keeps the mail
    /// client responsive and avoids tripping rate limits when sending live.
    @Published var throttle = ThrottlePolicy()

    /// The user's mail provider, used only to warn when a run looks likely to
    /// exceed its rough daily cap.
    @Published var sendingProvider: SendingProvider = .other

    /// A heads-up when the number of ready recipients exceeds the selected
    /// provider's approximate daily limit; `nil` when within limits or unknown.
    var quotaWarning: String? {
        sendingProvider.quotaWarning(forRecipientCount: sendablePreviews.count)
    }

    @Published private(set) var isSending = false
    @Published private(set) var sendProgress: Double = 0
    @Published private(set) var outcomes: [SendOutcome] = []

    /// Where a "send test to myself" goes, and the result of the last attempt,
    /// shown inline on the Send screen.
    @Published var testRecipient: String = ""
    @Published private(set) var testSendResult: TestSendResult?

    struct TestSendResult: Equatable {
        let succeeded: Bool
        let message: String
    }

    private var parsedTable: RecipientTable?
    private var sendTask: Task<Void, Never>?

    /// When a run is scheduled, the fire time and a frozen snapshot of the
    /// recipients to send — so later edits don't change what was scheduled, and
    /// the run can be canceled any time before it fires.
    @Published private(set) var scheduledFireDate: Date?
    private var scheduledQueue: [MergePreview] = []
    private var scheduleTask: Task<Void, Never>?
    var isScheduled: Bool { scheduledFireDate != nil }

    /// The on-device do-not-contact list. Mutations are mirrored into
    /// `suppressionEntries` so SwiftUI re-renders and `previews` re-evaluates.
    private let doNotContact = DoNotContactStore()
    @Published private(set) var suppressionEntries: [SuppressionEntry] = []

    /// The saved-template library and crash-safe autosave of the working draft.
    private let library = TemplateLibraryStore()
    @Published private(set) var savedTemplates: [SavedTemplate] = []
    private var cancellables = Set<AnyCancellable>()

    init() {
        suppressionEntries = doNotContact.entries
        savedTemplates = library.templates
        // Restore the last working draft if one was autosaved.
        if let restored = library.loadAutosave() { template = restored }
        // Autosave the working draft, debounced so it's not written per keystroke.
        $template
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] draft in self?.library.saveAutosave(draft) }
            .store(in: &cancellables)
    }

    // MARK: - Template library

    /// Saves the current template under `name` (overwriting a same-named one).
    func saveCurrentTemplate(as name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        library.save(template, as: name)
        savedTemplates = library.templates
    }

    /// Loads a saved template into the composer.
    func loadTemplate(_ saved: SavedTemplate) {
        template = saved.template
    }

    func deleteTemplate(_ saved: SavedTemplate) {
        library.delete(id: saved.id)
        savedTemplates = library.templates
    }

    /// Loads a built-in starter template into the composer.
    func loadStarterTemplate(_ starter: StarterTemplate) {
        template = starter.emailTemplate
    }

    /// Whether the composer is currently empty (used to offer the gallery/empty
    /// state rather than a blank editor).
    var isTemplateEmpty: Bool {
        template.subject.trimmingCharacters(in: .whitespaces).isEmpty &&
        template.body.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Derived state

    /// Live previews of the merged messages for every imported contact.
    var previews: [MergePreview] {
        TemplateMergeEngine.mergeAll(template: template, contacts: contacts,
                                     isSuppressed: { self.doNotContact.isSuppressed($0.email) },
                                     attachments: { self.recipientAttachments(for: $0) })
    }

    /// Resolves a contact's per-recipient attachment paths (and which are
    /// missing) from `attachmentColumn`. Empty when the feature isn't in use.
    private func recipientAttachments(for contact: Contact) -> (paths: [String], missing: [String]) {
        guard let column = attachmentColumn,
              let raw = contact.value(for: column), !raw.isEmpty else { return ([], []) }
        let paths = AttachmentSet.paths(fromColumnValue: raw)
        let missing = paths.filter { !FileManager.default.fileExists(atPath: $0) }
        return (paths, missing)
    }

    var sendablePreviews: [MergePreview] { previews.filter(\.isSendable) }
    var blockedPreviews: [MergePreview] { previews.filter { !$0.isSendable } }

    /// A live preview of the template while composing: the first imported
    /// recipient if a list is loaded, otherwise a realistic sample so the writer
    /// can see the personalized result before importing anything.
    var composePreview: MergePreview {
        let contact = contacts.first ?? Contact.sample
        return TemplateMergeEngine.merge(template: template, with: contact)
    }

    /// Whether `composePreview` is using the built-in sample (no list imported).
    var composePreviewIsSample: Bool { contacts.isEmpty }

    /// How many rows are held back purely because they repeat an earlier
    /// address — surfaced as a distinct warning since it's a list-hygiene issue,
    /// not a per-row data problem.
    var duplicateCount: Int { previews.lazy.filter(\.isDuplicate).count }

    /// How many rows are held back because they're on the do-not-contact list.
    var suppressedCount: Int { previews.lazy.filter(\.isSuppressed).count }

    // MARK: - Do-not-contact list

    /// Adds an address to the do-not-contact list. Returns false on invalid or
    /// already-present input, so the UI can flag it.
    @discardableResult
    func suppressAddress(_ address: String, note: String? = nil) -> Bool {
        let added = doNotContact.addAddress(address, note: note)
        if added { suppressionEntries = doNotContact.entries }
        return added
    }

    /// Adds a whole domain (e.g. `acme.com`) to the do-not-contact list.
    @discardableResult
    func suppressDomain(_ domain: String, note: String? = nil) -> Bool {
        let added = doNotContact.addDomain(domain, note: note)
        if added { suppressionEntries = doNotContact.entries }
        return added
    }

    func removeSuppression(_ entry: SuppressionEntry) {
        doNotContact.remove(entry)
        suppressionEntries = doNotContact.entries
    }

    /// Template fields that none of the imported columns can satisfy — surfaced
    /// in compose so the user notices a typo'd `{{Compnay}}` before review.
    /// Fields whose every use carries a `{{Field|fallback}}` are exempt: they
    /// can't block a send, so a missing column isn't a problem.
    var unmatchedTemplateFields: [String] {
        let available = Set(importedHeaders.map { $0.lowercased() })
        return template.fieldsRequiringData.filter { !available.contains($0.lowercased()) }
    }

    var canProceedToContacts: Bool {
        !template.subject.trimmingCharacters(in: .whitespaces).isEmpty &&
        !template.body.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var canProceedToReview: Bool { !contacts.isEmpty }
    var canSend: Bool { !sendablePreviews.isEmpty && !isSending }

    // MARK: - Import

    /// The single funnel every recipient source flows through. Whatever the
    /// origin — CSV, Excel, Word/PDF, Apple Contacts, Outlook — it is reduced to
    /// a `RecipientTable` (headers + rows) and ingested here, so email-column
    /// detection, preview, and merge behave identically regardless of source.
    func ingest(_ table: RecipientTable, sourceLabel: String) {
        parsedTable = table
        importedHeaders = table.headers
        importError = nil
        attachmentColumn = Self.detectAttachmentColumn(in: table.headers)

        // Choosing the email column repopulates `contacts` via `didSet`;
        // when detection lands on the column already selected, remap by hand.
        let detected = CSVParser.detectEmailColumn(in: table)
        if emailColumn != detected {
            emailColumn = detected
        } else {
            remapContacts()
        }

        let skipped = max(0, table.rows.count - contacts.count)
        var summary = "Imported \(contacts.count) contact\(contacts.count == 1 ? "" : "s") from \(sourceLabel)"
        if let detected { summary += " · email column: “\(detected)”" }
        if skipped > 0 { summary += " · \(skipped) row\(skipped == 1 ? "" : "s") skipped (no email)" }
        importSummary = summary
        Log.csv.info("Ingested \(self.contacts.count, privacy: .public) contacts from \(sourceLabel, privacy: .public); skipped \(skipped, privacy: .public)")
    }

    /// Records a failed import and clears any partial state.
    func reportImportFailure(_ message: String) {
        importError = message
        importSummary = nil
        contacts = []
        importedHeaders = []
        parsedTable = nil
        clearWorkbookSelection()
        Log.csv.error("Import failed: \(message, privacy: .public)")
    }

    /// Parses CSV text into contacts. Auto-detects the email column unless one
    /// was already chosen.
    func importCSV(_ text: String) {
        do {
            let table = try CSVParser.parse(text)
            ingest(table, sourceLabel: "pasted text")
        } catch {
            reportImportFailure(error.localizedDescription)
        }
    }

    /// Routes a dropped/chosen file to the right reader based on its extension.
    func importFile(at url: URL) {
        let ext = url.pathExtension.lowercased()
        // Any new file supersedes a previously loaded workbook's sheet picker.
        clearWorkbookSelection()
        do {
            switch ext {
            case "csv", "tsv", "txt":
                let data = try Data(contentsOf: url)
                guard let text = CSVParser.decode(data) else {
                    reportImportFailure("Couldn't read \(url.lastPathComponent) — its text encoding isn't recognized. Re-save it as UTF-8 CSV.")
                    return
                }
                // TSV files are tab-delimited; other text auto-detects.
                let table = try CSVParser.parse(text, delimiter: ext == "tsv" ? "\t" : nil)
                ingest(table, sourceLabel: url.lastPathComponent)
            case "numbers":
                reportImportFailure("Apple Numbers files can't be read directly. In Numbers, choose File ▸ Export To ▸ CSV… (or Excel), then import that file.")
            case "xlsx":
                let sheets = (try? XLSXReader.worksheets(in: url)) ?? []
                let table = try XLSXReader.read(url)
                // Only offer the picker when there's a real choice to make.
                if sheets.count > 1 {
                    workbookURL = url
                    availableWorksheets = sheets
                    selectedWorksheet = sheets.first?.name
                }
                ingest(table, sourceLabel: sheetSourceLabel(url, sheet: selectedWorksheet))
            case "docx", "pdf":
                let text = try DocumentTextExtractor.extractText(from: url)
                let table = LooseContactExtractor.table(from: text)
                guard !table.rows.isEmpty else {
                    reportImportFailure("No email addresses were found in \(url.lastPathComponent). Try a CSV or Excel export for reliable results.")
                    return
                }
                ingest(table, sourceLabel: url.lastPathComponent)
            default:
                reportImportFailure("Unsupported file type: .\(ext)")
            }
        } catch {
            reportImportFailure("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Imports recipients from the user's Apple/iCloud address book.
    func importFromAppleContacts() async {
        do {
            let table = try await ContactsImporter.fetchTable()
            ingest(table, sourceLabel: "Apple Contacts")
        } catch {
            reportImportFailure(error.localizedDescription)
        }
    }

    /// Imports recipients from Microsoft Outlook's contacts via automation.
    func importFromOutlookContacts() {
        do {
            let table = try OutlookContactsImporter.fetchTable()
            guard !table.rows.isEmpty else {
                reportImportFailure("No Outlook contacts with email addresses were found.")
                return
            }
            ingest(table, sourceLabel: "Outlook Contacts")
        } catch {
            reportImportFailure(error.localizedDescription)
        }
    }

    /// Re-imports the loaded workbook using a different worksheet tab.
    func selectWorksheet(_ name: String) {
        guard let url = workbookURL, name != selectedWorksheet else { return }
        do {
            let table = try XLSXReader.read(url, sheetName: name)
            selectedWorksheet = name
            emailColumn = nil // headers may differ between sheets; re-detect
            ingest(table, sourceLabel: sheetSourceLabel(url, sheet: name))
        } catch {
            reportImportFailure("Couldn't read “\(name)”: \(error.localizedDescription)")
        }
    }

    /// A source label that names the chosen sheet, e.g. `Leads.xlsx › Q3`.
    private func sheetSourceLabel(_ url: URL, sheet: String?) -> String {
        guard let sheet else { return url.lastPathComponent }
        return "\(url.lastPathComponent) › \(sheet)"
    }

    private func clearWorkbookSelection() {
        workbookURL = nil
        availableWorksheets = []
        selectedWorksheet = nil
    }

    /// Guesses an attachment column from the headers (a column named
    /// "attachment"/"attachments"/"file"/"files"), else nil.
    static func detectAttachmentColumn(in headers: [String]) -> String? {
        headers.first {
            let h = $0.lowercased()
            return h == "attachment" || h == "attachments" || h == "file" || h == "files"
        }
    }

    private func remapContacts() {
        guard let table = parsedTable else { return }
        let (parsedContacts, _) = CSVParser.contacts(from: table, emailHeader: emailColumn)
        contacts = parsedContacts
    }

    // MARK: - Name-inference repair

    /// For a row blocked on a missing first-name field, a suggested (field, name)
    /// inferred from the recipient's email — or nil when there's nothing to
    /// suggest. Offered as a manual fix in review, never applied automatically.
    func nameSuggestion(for preview: MergePreview) -> (field: String, name: String)? {
        guard let field = preview.unresolvedFields.first(where: { Self.isFirstNameField($0) }),
              let name = NameInference.suggestedFirstName(from: preview.contact.email)
        else { return nil }
        return (field, name)
    }

    /// Fills `field` with `value` for the given contact and re-merges.
    func fillField(_ field: String, with value: String, forContact id: UUID) {
        guard let index = contacts.firstIndex(where: { $0.id == id }) else { return }
        contacts[index].fields[field] = value
    }

    private static func isFirstNameField(_ field: String) -> Bool {
        let key = field.lowercased().replacingOccurrences(of: " ", with: "")
        return key == "firstname" || key == "name" || key == "first" || key == "givenname"
    }

    // MARK: - Sending

    /// Runs the merge-and-deliver loop over every sendable preview.
    func startSending() {
        cancelSchedule() // a manual send supersedes any pending schedule
        run(queue: sendablePreviews)
    }

    /// Schedules the current sendable recipients to be sent/drafted at `date`.
    /// The recipient list and merged content are frozen now; client, mode, and
    /// throttle are applied at fire time. Requires the Mac awake and the app
    /// running — see `ScheduledSend`.
    func scheduleSend(at date: Date) {
        let seconds = ScheduledSend.secondsUntil(date, from: Date())
        guard seconds > 0, !sendablePreviews.isEmpty, !isSending else { return }
        cancelSchedule()
        scheduledQueue = sendablePreviews
        scheduledFireDate = date
        Log.send.info("Scheduled \(self.scheduledQueue.count, privacy: .public) messages for a future time")
        scheduleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let queue = scheduledQueue
            scheduledFireDate = nil
            scheduledQueue = []
            run(queue: queue)
        }
    }

    func cancelSchedule() {
        scheduleTask?.cancel()
        scheduleTask = nil
        scheduledFireDate = nil
        scheduledQueue = []
    }

    /// Re-runs only the recipients whose last attempt failed (transient errors
    /// like a declined prompt or a briefly-unavailable client). Rows held back
    /// for missing data aren't retried — those need corrected data re-imported.
    func retryFailed() {
        let failedIDs = Set(outcomes.compactMap { outcome -> UUID? in
            if case .failed = outcome.status { return outcome.id }
            return nil
        })
        let queue = previews.filter { failedIDs.contains($0.id) && $0.isSendable }
        cancelSchedule()
        run(queue: queue)
    }

    /// How many of the last run's recipients failed (enables the retry action).
    var failedCount: Int {
        outcomes.filter { if case .failed = $0.status { return true }; return false }.count
    }

    /// A complete per-recipient results report (sent/drafted/held/failed) for
    /// the last run, or the currently held-back rows before a run. Empty only
    /// when there's nothing to report.
    func resultsReportCSV() -> String {
        RunReportExporter.csv(RunReportExporter.rows(outcomes: outcomes, blocked: blockedPreviews))
    }

    /// Whether there's anything worth exporting yet.
    var hasResultsToExport: Bool { !outcomes.isEmpty || !blockedPreviews.isEmpty }

    // MARK: - Merge to PDF

    /// Filename pattern for generated PDFs; supports `{{Field}}` placeholders.
    @Published var pdfFilenamePattern: String = "{{Full Name}} - letter.pdf"
    /// Optional password applied to every generated PDF.
    @Published var pdfPassword: String = ""

    /// Writes one `.eml` draft per sendable recipient into `folder`, carrying the
    /// full HTML body so Apple Mail can open it at full fidelity (double-click,
    /// or File ▸ Import). Experimental — see `MIMEMessageComposer`. Returns the
    /// count written and the count that failed.
    @discardableResult
    func exportHTMLDrafts(toFolder folder: URL) -> (written: Int, failed: Int) {
        let date = Self.rfc822Date(Date())
        var written = 0, failed = 0
        for (index, preview) in sendablePreviews.enumerated() {
            let plain = HTMLTextExtractor.plainText(fromHTML: preview.resolvedBody)
            let message = MIMEMessageComposer.Message(
                from: effectiveSender, to: preview.contact.email,
                subject: preview.resolvedSubject, html: preview.resolvedBody, plainText: plain)
            // A stable, collision-free boundary without relying on randomness.
            let boundary = "HighRise-boundary-\(index)-\(preview.contact.email.hashValue)"
            let eml = MIMEMessageComposer.eml(message, boundary: boundary, date: date)
            let name = PDFFilename.sanitize(preview.contact.email) + ".eml"
            do {
                try eml.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
                written += 1
            } catch {
                failed += 1
                Log.send.error("EML draft write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return (written, failed)
    }

    private static func rfc822Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }

    /// Renders one personalized PDF per sendable recipient into `folder`.
    /// Returns the count written and the count that failed to render.
    @discardableResult
    func exportPersonalizedPDFs(toFolder folder: URL) -> (written: Int, failed: Int) {
        var written = 0, failed = 0
        let password = pdfPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        for preview in sendablePreviews {
            let name = PDFFilename.make(pattern: pdfFilenamePattern,
                                        contact: preview.contact,
                                        fallback: preview.contact.email)
            do {
                try PDFComposer.write(content: preview.resolvedBody,
                                      isHTML: template.format == .html,
                                      to: folder.appendingPathComponent(name),
                                      password: password.isEmpty ? nil : password)
                written += 1
            } catch {
                failed += 1
                Log.send.error("PDF render failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return (written, failed)
    }

    /// The shared merge-and-deliver loop over an explicit queue.
    private func run(queue: [MergePreview]) {
        guard !isSending else { return }
        guard !queue.isEmpty else { return }

        let sender = MailSender(client: selectedClient)
        guard sender.isClientInstalled else {
            outcomes = [SendOutcome(id: UUID(), contact: queue[0].contact,
                                    status: .failed(reason: MailSenderError.clientNotInstalled(selectedClient).localizedDescription))]
            return
        }
        // Don't start a run that would fail on every message for a missing file.
        guard missingAttachments.isEmpty else {
            let names = missingAttachments.map(\.lastPathComponent).joined(separator: ", ")
            outcomes = [SendOutcome(id: UUID(), contact: queue[0].contact,
                                    status: .failed(reason: "Missing attachment file(s): \(names). Remove or restore them first."))]
            return
        }

        let attachmentPaths = attachments.map(\.path)
        isSending = true
        sendProgress = 0
        outcomes = []
        let mode = sendMode
        Log.send.info("Starting \(mode == .send ? "send" : "draft", privacy: .public) of \(queue.count, privacy: .public) messages via \(self.selectedClient.rawValue, privacy: .public)")

        sendTask = Task { @MainActor in
            var collected: [SendOutcome] = []
            for (index, preview) in queue.enumerated() {
                if Task.isCancelled { break }
                let (cc, bcc) = envelope.resolved(for: preview.contact)
                // Campaign-wide files plus this recipient's own column files.
                let allAttachments = attachmentPaths + preview.attachmentPaths
                let message = ComposedMessage(
                    recipientEmail: preview.contact.email,
                    recipientName: preview.contact.displayName,
                    subject: preview.resolvedSubject,
                    body: bodyWithFooter(preview.resolvedBody, for: preview.contact),
                    isHTML: template.format == .html,
                    cc: cc,
                    bcc: bcc,
                    attachmentPaths: allAttachments,
                    sender: effectiveSender,
                    signatureName: effectiveSignature
                )
                let status: SendOutcome.Status
                do {
                    try sender.deliver(message, mode: mode)
                    status = mode == .send ? .sent : .drafted
                } catch {
                    status = .failed(reason: error.localizedDescription)
                    Log.send.error("Delivery failed for a recipient: \(error.localizedDescription, privacy: .public)")
                }
                collected.append(SendOutcome(id: preview.id, contact: preview.contact, status: status))
                outcomes = collected
                sendProgress = Double(index + 1) / Double(queue.count)

                let delay = throttle.delayAfter(index: index, count: queue.count)
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
            isSending = false
            Log.send.info("Run complete: \(collected.filter(\.isSuccess).count, privacy: .public)/\(queue.count, privacy: .public) succeeded")
        }
    }

    func cancelSending() {
        sendTask?.cancel()
        sendTask = nil
        isSending = false
        Log.send.info("Send cancelled by user")
    }

    /// Sends (or drafts) one fully-merged sample message to the user's own
    /// address so they can see the real inbox render before the run. Uses the
    /// first ready recipient as the sample and the currently selected client and
    /// mode, with a `[TEST]` subject prefix. Complements — doesn't replace — the
    /// per-recipient review step.
    func sendTestToSelf() {
        let target = testRecipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailValidator.isValid(target) else {
            testSendResult = TestSendResult(succeeded: false,
                message: "Enter a valid email address to send yourself a test.")
            return
        }
        guard let sample = sendablePreviews.first else {
            testSendResult = TestSendResult(succeeded: false,
                message: "No ready message to test yet — import a list and compose your template first.")
            return
        }
        let sender = MailSender(client: selectedClient)
        guard sender.isClientInstalled else {
            testSendResult = TestSendResult(succeeded: false,
                message: MailSenderError.clientNotInstalled(selectedClient).localizedDescription)
            return
        }

        guard missingAttachments.isEmpty else {
            let names = missingAttachments.map(\.lastPathComponent).joined(separator: ", ")
            testSendResult = TestSendResult(succeeded: false,
                message: "Missing attachment file(s): \(names).")
            return
        }
        // The test carries the real attachments (only to the user), but never
        // the CC/BCC envelope — a test must not email real third parties.
        let message = ComposedMessage(
            recipientEmail: target,
            recipientName: "Test recipient",
            subject: "[TEST] " + sample.resolvedSubject,
            body: bodyWithFooter(sample.resolvedBody, for: sample.contact),
            isHTML: template.format == .html,
            attachmentPaths: attachments.map(\.path),
            sender: effectiveSender,
            signatureName: effectiveSignature
        )
        do {
            try sender.deliver(message, mode: sendMode)
            let where_ = sendMode == .send
                ? "Test sent to \(target)."
                : "Test draft for \(target) created in \(selectedClient.rawValue)."
            testSendResult = TestSendResult(succeeded: true,
                message: "\(where_) Sampled “\(sample.contact.displayName)”.")
            Log.send.info("Test \(self.sendMode == .send ? "send" : "draft", privacy: .public) to self succeeded")
        } catch {
            testSendResult = TestSendResult(succeeded: false,
                message: "Test failed: \(error.localizedDescription)")
            Log.send.error("Test send failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clears the contact list and results, keeping the composed template so the
    /// user can run another list against the same draft.
    func resetForNewList() {
        cancelSending()
        contacts = []
        importedHeaders = []
        importSummary = nil
        importError = nil
        parsedTable = nil
        emailColumn = nil
        attachmentColumn = nil
        clearWorkbookSelection()
        outcomes = []
        sendProgress = 0
        stage = .contacts
    }
}
