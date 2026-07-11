import Testing
import Foundation
@testable import HighRise

/// Import now runs its heavy work off the main thread (see
/// `ImportPipeline`'s doc comment) — these pin the coordinator-level wiring
/// end to end: `isImporting` clears, contacts land, and failures still
/// report cleanly, all through the new `async` entry points.
@MainActor
struct HighRiseCoordinatorImportTests {

    @Test("importCSV ingests pasted text and clears isImporting")
    func importCSVEndToEnd() async {
        let coordinator = HighRiseCoordinator()
        await coordinator.importCSV("Name,Email\nAda,ada@example.com\nGrace,grace@example.com")
        #expect(coordinator.isImporting == false)
        #expect(coordinator.contacts.count == 2)
        #expect(coordinator.emailColumn == "Email")
        #expect(coordinator.importError == nil)
    }

    @Test("A second import replaces the first rather than merging")
    func reimportReplaces() async {
        let coordinator = HighRiseCoordinator()
        await coordinator.importCSV("Name,Email\nAda,ada@example.com")
        #expect(coordinator.contacts.count == 1)
        await coordinator.importCSV("Name,Email\nAda,ada@example.com\nGrace,grace@example.com")
        #expect(coordinator.contacts.count == 2)
    }

    @Test("Empty CSV text reports a failure instead of throwing")
    func badCSVReportsFailure() async {
        let coordinator = HighRiseCoordinator()
        await coordinator.importCSV("")
        #expect(coordinator.importError != nil)
        #expect(coordinator.contacts.isEmpty)
        #expect(coordinator.isImporting == false)
    }

    @Test("A manually chosen email column survives re-ingest of the same shape")
    func manualColumnChoiceRemapsSynchronously() async {
        let coordinator = HighRiseCoordinator()
        await coordinator.importCSV("Name,Email,Backup\nAda,ada@example.com,backup@example.com")
        coordinator.emailColumn = "Backup"
        #expect(coordinator.contacts.first?.email == "backup@example.com")
    }

    @Test("unmatchedTemplateFields recognizes a synonym column, e.g. Company/Account")
    func unmatchedTemplateFieldsRecognizesSynonyms() async {
        let coordinator = HighRiseCoordinator()
        await coordinator.importCSV("Account Name,Email\nAcme,a@example.com")
        coordinator.template = EmailTemplate(subject: "Hi {{Company}}", body: "…")
        #expect(coordinator.unmatchedTemplateFields.isEmpty)
    }
}
