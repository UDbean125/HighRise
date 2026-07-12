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

    @Published var template = EmailTemplate()
    @Published var previews: [MergePreview] = []

    @Published var queue: SendQueue?

    var sendableCount: Int { previews.filter(\.isSendable).count }
    var blockedCount: Int { previews.count - sendableCount }

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
            let result = ImportPipeline.run(
                table: table, sourceLabel: sourceLabel, cleanupEnabled: true,
                appliedSuggestions: [], emailColumnOverride: nil)
            contacts = result.contacts
            importSummary = result.importSummary
            queue = nil
            refreshPreviews()
        } catch {
            importError = error.localizedDescription
        }
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
