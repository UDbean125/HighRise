import Foundation
import SwiftUI
import os

/// The app's single source of truth, driving the import → review → send flow.
///
/// SwiftUI views observe this; all mutation happens on the main actor. The
/// heavy lifting (parsing, merging, scripting) is delegated to the pure
/// services so this type stays focused on orchestration and published state.
@MainActor
final class HighRiseCoordinator: ObservableObject {

    enum Stage: Int, CaseIterable {
        case compose, contacts, review, send
    }

    // MARK: - Published state

    @Published var stage: Stage = .compose
    @Published var template = EmailTemplate()

    @Published private(set) var contacts: [Contact] = []
    @Published private(set) var importedHeaders: [String] = []
    @Published var emailColumn: String? { didSet { remapContacts() } }
    @Published private(set) var importSummary: String?
    @Published var importError: String?

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

    /// The on-device do-not-contact list. Mutations are mirrored into
    /// `suppressionEntries` so SwiftUI re-renders and `previews` re-evaluates.
    private let doNotContact = DoNotContactStore()
    @Published private(set) var suppressionEntries: [SuppressionEntry] = []

    init() {
        suppressionEntries = doNotContact.entries
    }

    // MARK: - Derived state

    /// Live previews of the merged messages for every imported contact.
    var previews: [MergePreview] {
        TemplateMergeEngine.mergeAll(template: template, contacts: contacts,
                                     isSuppressed: { self.doNotContact.isSuppressed($0.email) })
    }

    var sendablePreviews: [MergePreview] { previews.filter(\.isSendable) }
    var blockedPreviews: [MergePreview] { previews.filter { !$0.isSendable } }

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
                let text = try String(contentsOf: url, encoding: .utf8)
                let table = try CSVParser.parse(text)
                ingest(table, sourceLabel: url.lastPathComponent)
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

    private func remapContacts() {
        guard let table = parsedTable else { return }
        let (parsedContacts, _) = CSVParser.contacts(from: table, emailHeader: emailColumn)
        contacts = parsedContacts
    }

    // MARK: - Sending

    /// Runs the merge-and-deliver loop over every sendable preview.
    func startSending() {
        run(queue: sendablePreviews)
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
                let message = ComposedMessage(
                    recipientEmail: preview.contact.email,
                    recipientName: preview.contact.displayName,
                    subject: preview.resolvedSubject,
                    body: preview.resolvedBody,
                    isHTML: template.format == .html,
                    cc: cc,
                    bcc: bcc,
                    attachmentPaths: attachmentPaths
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
            body: sample.resolvedBody,
            isHTML: template.format == .html,
            attachmentPaths: attachments.map(\.path)
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
        clearWorkbookSelection()
        outcomes = []
        sendProgress = 0
        stage = .contacts
    }
}
