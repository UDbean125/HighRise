import XCTest
@testable import HighRiseMobile

/// iOS kills backgrounded apps without warning, and the iOS send flow is a
/// long interactive one — a Mail compose sheet per recipient. `SendQueue`
/// lives only in memory, so before the run journal a kill partway through a
/// run left no record at all: the next launch restored the list and template,
/// rebuilt the queue from every sendable recipient, and silently emailed the
/// people already reached a second time.
///
/// These tests pin the guarantee — nobody is emailed twice — and specifically
/// the failure mode, by simulating the kill as a *new coordinator reading the
/// same journal directory*, which is exactly what a relaunch is.
@MainActor
final class MobileRunJournalTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("run-journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A coordinator sharing `directory`'s journal but its own inert session
    /// and template stores — a fresh launch against the same on-disk journal.
    private func makeCoordinator() -> MobileCoordinator {
        MobileCoordinator(sessionStore: MobileSessionStore(directory: nil),
                          library: TemplateLibraryStore(directory: nil),
                          doNotContact: DoNotContactStore(fileURL: nil),
                          runLog: SendRunLogStore(directory: directory))
    }

    private func loadList(into coordinator: MobileCoordinator) {
        coordinator.importCSV(data: Data("""
        Name,Email
        Ada,ada@example.com
        Grace,grace@example.com
        Alan,alan@example.com
        """.utf8), sourceLabel: "test.csv")
        coordinator.template = EmailTemplate(subject: "Hi {{Name}}", body: "Hello {{Name}}")
        coordinator.refreshPreviews()
    }

    // MARK: - The failure mode

    func testARunInterruptedPartwayDoesNotEmailAnyoneTwiceAfterRelaunch() {
        let first = makeCoordinator()
        loadList(into: first)
        first.startSendQueue()
        XCTAssertEqual(first.queue?.totalCount, 3)

        // Email the first recipient, then the app is killed — no finish, no
        // teardown, nothing but what already reached disk.
        let emailed = first.queue?.current?.contact.email
        first.recordOutcome(.sent)
        XCTAssertEqual(emailed, "ada@example.com")

        // Relaunch: same list, same template, same journal directory.
        let relaunched = makeCoordinator()
        loadList(into: relaunched)
        relaunched.startSendQueue()

        let queued = relaunched.queue?.items.map(\.contact.email) ?? []
        XCTAssertFalse(queued.contains("ada@example.com"),
                       "the recipient already emailed before the kill must not be queued again")
        XCTAssertEqual(queued.sorted(), ["alan@example.com", "grace@example.com"])
        XCTAssertEqual(relaunched.resumedFromInterruptedCount, 1)
    }

    func testDraftedCountsAsDeliveredAcrossRelaunch() {
        let first = makeCoordinator()
        loadList(into: first)
        first.startSendQueue()
        first.recordOutcome(.drafted)

        let relaunched = makeCoordinator()
        loadList(into: relaunched)
        relaunched.startSendQueue()

        XCTAssertFalse((relaunched.queue?.items.map(\.contact.email) ?? []).contains("ada@example.com"),
                       "a drafted message is already in the user's Mail — re-queueing it risks a second send")
    }

    func testSkippedAndFailedRecipientsAreStillOfferedAfterRelaunch() {
        let first = makeCoordinator()
        loadList(into: first)
        first.startSendQueue()
        first.recordOutcome(.skipped(reason: "not now"))
        first.recordOutcome(.failed(reason: "no mail account"))

        let relaunched = makeCoordinator()
        loadList(into: relaunched)
        relaunched.startSendQueue()

        let queued = relaunched.queue?.items.map(\.contact.email) ?? []
        XCTAssertEqual(queued.sorted(), ["ada@example.com", "alan@example.com", "grace@example.com"],
                       "nobody was actually emailed, so nobody may be dropped from the queue")
        XCTAssertEqual(relaunched.resumedFromInterruptedCount, 0)
    }

    // MARK: - Durability

    func testEveryOutcomeIsWrittenAsItHappensNotBatchedAtTheEnd() throws {
        let coordinator = makeCoordinator()
        loadList(into: coordinator)
        coordinator.startSendQueue()
        coordinator.recordOutcome(.sent)

        // Read the journal straight off disk mid-run — a batched write would
        // be the very record a kill destroys.
        let onDisk = SendRunLogStore(directory: directory).load()
        XCTAssertEqual(onDisk?.records.count, 1)
        XCTAssertEqual(onDisk?.records.first?.email, "ada@example.com")
        XCTAssertEqual(onDisk?.records.first?.status, "sent")
        XCTAssertEqual(onDisk?.finished, false, "a run still in progress must read as unfinished")
    }

    func testASecondInterruptionStillRemembersTheFirstRunsRecipients() {
        let first = makeCoordinator()
        loadList(into: first)
        first.startSendQueue()
        first.recordOutcome(.sent)          // ada — then killed

        let second = makeCoordinator()
        loadList(into: second)
        second.startSendQueue()
        second.recordOutcome(.sent)          // grace — then killed again

        let third = makeCoordinator()
        loadList(into: third)
        third.startSendQueue()

        let queued = third.queue?.items.map(\.contact.email) ?? []
        XCTAssertEqual(queued, ["alan@example.com"],
                       "carrying the journal forward is what stops the first run's recipients being forgotten")
        XCTAssertEqual(third.resumedFromInterruptedCount, 2)
    }

    // MARK: - Not a trap

    func testAFinishedRunDoesNotFilterALaterDeliberateSend() {
        let coordinator = makeCoordinator()
        loadList(into: coordinator)
        coordinator.startSendQueue()
        while coordinator.queue?.isFinished == false {
            coordinator.recordOutcome(.sent)
        }

        // Same list, same app session — a deliberate second campaign.
        coordinator.startSendQueue()
        XCTAssertEqual(coordinator.queue?.totalCount, 3,
                       "a run that ended normally must not block sending to the same list again")
        XCTAssertEqual(coordinator.resumedFromInterruptedCount, 0)
    }

    func testAFinishedRunIsNotOfferedAsInterruptedOnTheNextLaunch() {
        let first = makeCoordinator()
        loadList(into: first)
        first.startSendQueue()
        while first.queue?.isFinished == false {
            first.recordOutcome(.sent)
        }

        let relaunched = makeCoordinator()
        XCTAssertNil(relaunched.incompleteLastRun,
                     "only a run that never finished should be surfaced as interrupted")
        loadList(into: relaunched)
        relaunched.startSendQueue()
        XCTAssertEqual(relaunched.queue?.totalCount, 3)
    }

    func testDiscardingAnInterruptedRunLetsThoseRecipientsThroughAgain() {
        let first = makeCoordinator()
        loadList(into: first)
        first.startSendQueue()
        first.recordOutcome(.sent)

        let relaunched = makeCoordinator()
        loadList(into: relaunched)
        XCTAssertNotNil(relaunched.incompleteLastRun)

        relaunched.discardInterruptedRun()
        relaunched.startSendQueue()

        XCTAssertEqual(relaunched.queue?.totalCount, 3,
                       "the override has to actually work, or the protection becomes a trap")
        XCTAssertNil(relaunched.incompleteLastRun)
    }

    func testStartingOverClearsTheJournalSoANewListIsNotFiltered() {
        let first = makeCoordinator()
        loadList(into: first)
        first.startSendQueue()
        first.recordOutcome(.sent)

        let relaunched = makeCoordinator()
        relaunched.clearSession()
        loadList(into: relaunched)
        relaunched.startSendQueue()

        XCTAssertEqual(relaunched.queue?.totalCount, 3,
                       "an explicit start-over must not leave a journal filtering the next list")
    }

    func testAListWhoseRecipientsWereAllReachedClosesTheRunRatherThanStayingInterrupted() {
        let first = makeCoordinator()
        loadList(into: first)
        first.startSendQueue()
        first.recordOutcome(.sent)

        // Relaunch with a list containing only the already-emailed recipient.
        let relaunched = makeCoordinator()
        relaunched.importCSV(data: Data("Name,Email\nAda,ada@example.com".utf8),
                             sourceLabel: "just-ada.csv")
        relaunched.template = EmailTemplate(subject: "Hi", body: "Hello")
        relaunched.refreshPreviews()
        relaunched.startSendQueue()

        XCTAssertEqual(relaunched.queue?.totalCount, 0)
        XCTAssertNil(relaunched.incompleteLastRun,
                     "with nobody left to reach the run is over, not perpetually interrupted")
    }
}
