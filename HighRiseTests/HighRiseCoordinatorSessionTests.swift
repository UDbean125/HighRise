import Testing
import Foundation
@testable import HighRise

/// Coordinator-level session restore: closing the window quits the app, so a
/// relaunch must rebuild the imported list (with the user's accepted cleanup
/// decisions re-applied), the campaign settings, and any pending schedule —
/// and a schedule whose fire time passed while quit must become a notice, not
/// an auto-send of stale content.
@MainActor
struct HighRiseCoordinatorSessionTests {

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CoordinatorSessionTests-\(UUID().uuidString)")
    }

    /// Restore replays through an async pipeline; poll until it settles.
    private func waitForRestore(_ coordinator: HighRiseCoordinator,
                                until done: @autoclosure () -> Bool) async {
        for _ in 0..<200 where !done() {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    @Test("A saved session restores the list, settings, and applied decisions")
    func sessionRoundTripThroughCoordinator() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = HighRiseCoordinator(sessionStore: SessionStore(directory: directory),
                                           library: TemplateLibraryStore(directory: directory),
                                           runLog: SendRunLogStore(directory: nil))
        await first.importCSV("""
        Name,Email,Company
        Ada,ada@gmial.com,Analytical Engines
        Grace,grace@example.com,
        """)
        #expect(first.contacts.count == 2)
        // Accept the gmial→gmail repair so restore has a decision to replay.
        if let typoFix = first.cleanupSuggestions.first(where: { $0.kind == .domainTypo }) {
            first.applyCleanupSuggestion(typoFix)
        }
        #expect(first.contacts.first?.email == "ada@gmail.com")
        first.envelope.bccSelf = "me@example.com"
        first.senderIdentity = "bryan@example.com"
        first.sendMode = .send
        first.saveSessionNow()

        let second = HighRiseCoordinator(sessionStore: SessionStore(directory: directory),
                                           library: TemplateLibraryStore(directory: directory),
                                           runLog: SendRunLogStore(directory: nil))
        await waitForRestore(second, until: !second.isImporting && !second.contacts.isEmpty)

        #expect(second.contacts.count == 2)
        #expect(second.contacts.first?.email == "ada@gmail.com",
                "the accepted domain-typo repair must be re-applied on restore")
        #expect(second.emailColumn == "Email")
        #expect(second.importSummary != nil)
        #expect(second.envelope.bccSelf == "me@example.com")
        #expect(second.senderIdentity == "bryan@example.com")
        #expect(second.sendMode == .send)
    }

    @Test("A schedule still in the future is re-armed on restore")
    func futureScheduleRearms() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fireDate = Date().addingTimeInterval(3600)
        let first = HighRiseCoordinator(sessionStore: SessionStore(directory: directory),
                                           library: TemplateLibraryStore(directory: directory),
                                           runLog: SendRunLogStore(directory: nil))
        await first.importCSV("Name,Email\nAda,ada@example.com")
        first.template = EmailTemplate(subject: "Hi {{Name}}", body: "Hello {{Name}}")
        first.scheduleSend(at: fireDate)
        #expect(first.isScheduled)
        first.saveSessionNow()

        let second = HighRiseCoordinator(sessionStore: SessionStore(directory: directory),
                                           library: TemplateLibraryStore(directory: directory),
                                           runLog: SendRunLogStore(directory: nil))
        await waitForRestore(second, until: second.isScheduled)

        #expect(second.scheduledFireDate == fireDate)
        #expect(second.missedScheduleDate == nil)
        second.cancelSchedule()
    }

    @Test("A schedule that expired while quit becomes a notice, never an auto-send")
    func expiredScheduleBecomesNotice() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let missedDate = Date().addingTimeInterval(-600)
        var snapshot = SessionSnapshot()
        snapshot.rawTable = RecipientTable(headers: ["Name", "Email"],
                                           rows: [["Ada", "ada@example.com"]])
        snapshot.importSourceLabel = "Leads.csv"
        snapshot.emailColumn = "Email"
        snapshot.scheduledFireDate = missedDate
        SessionStore(directory: directory).save(snapshot)

        let coordinator = HighRiseCoordinator(sessionStore: SessionStore(directory: directory),
                                           library: TemplateLibraryStore(directory: directory),
                                           runLog: SendRunLogStore(directory: nil))
        await waitForRestore(coordinator, until: coordinator.missedScheduleDate != nil)

        #expect(coordinator.missedScheduleDate == missedDate)
        #expect(!coordinator.isScheduled)
        #expect(!coordinator.isSending, "stale scheduled content must never auto-send")
        #expect(coordinator.contacts.count == 1, "the list itself still restores")

        coordinator.dismissMissedSchedule()
        #expect(coordinator.missedScheduleDate == nil)
    }

    @Test("An Outlook session restored where Outlook is unavailable falls back to Apple Mail")
    func unknownClientFallsBack() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var snapshot = SessionSnapshot()
        snapshot.selectedClientRaw = "Some Client That Does Not Exist"
        snapshot.sendModeRaw = "Not a real mode"
        SessionStore(directory: directory).save(snapshot)

        let coordinator = HighRiseCoordinator(sessionStore: SessionStore(directory: directory),
                                           library: TemplateLibraryStore(directory: directory),
                                           runLog: SendRunLogStore(directory: nil))
        #expect(coordinator.selectedClient == .appleMail)
        #expect(coordinator.sendMode == .draft)
    }

    @Test("No saved session leaves a pristine coordinator")
    func freshLaunchIsPristine() async {
        let coordinator = HighRiseCoordinator(sessionStore: SessionStore(directory: temporaryDirectory()),
                                              library: TemplateLibraryStore(directory: nil),
                                              runLog: SendRunLogStore(directory: nil))
        #expect(coordinator.contacts.isEmpty)
        #expect(coordinator.missedScheduleDate == nil)
        #expect(!coordinator.isScheduled)
    }
}
