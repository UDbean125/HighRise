import XCTest
@testable import HighRiseMobile

/// A finished send queue used to persist forever (only a re-import cleared
/// it), so re-entering the send flow dead-ended on the stale "Done" summary.
/// These pin the fix: entering with a finished queue starts a fresh session,
/// and the Home dashboard's completed-a-send state survives via a snapshot.
@MainActor
final class MobileCoordinatorSendSessionTests: XCTestCase {

    private func makeCoordinatorWithFinishedRun() -> MobileCoordinator {
        // An inert run journal (`directory: nil`) so these tests can't be
        // perturbed by — or leave behind — a real one in the app container.
        // The journal's own behavior is covered in MobileRunJournalTests.
        let coordinator = MobileCoordinator(runLog: SendRunLogStore(directory: nil))
        coordinator.importCSV(data: Data("""
        Name,Email
        Ada,ada@example.com
        Grace,grace@example.com
        """.utf8), sourceLabel: "test.csv")
        coordinator.template = EmailTemplate(subject: "Hi {{Name}}", body: "Hello {{Name}}")
        coordinator.refreshPreviews()
        coordinator.startSendQueue()
        while coordinator.queue?.isFinished == false {
            coordinator.recordOutcome(.sent)
        }
        return coordinator
    }

    func testReenteringWithAFinishedQueueStartsAFreshSession() {
        let coordinator = makeCoordinatorWithFinishedRun()
        XCTAssertEqual(coordinator.queue?.isFinished, true)

        // What SendSessionView.onAppear now does on re-entry:
        coordinator.startSendQueue()

        XCTAssertEqual(coordinator.queue?.isFinished, false,
                       "a finished queue must be replaced by a fresh, startable one")
        XCTAssertEqual(coordinator.queue?.completedCount, 0)
        XCTAssertEqual(coordinator.queue?.totalCount, 2)
    }

    func testCompletedSendStateSurvivesStartingANewSession() {
        let coordinator = makeCoordinatorWithFinishedRun()
        XCTAssertTrue(coordinator.hasCompletedASend)

        coordinator.startSendQueue()

        XCTAssertTrue(coordinator.hasCompletedASend,
                      "the Home dashboard must not forget a completed run when a new queue starts")
        XCTAssertEqual(coordinator.lastRunOutcomes.count, 2)
    }

    func testNewImportClearsThePreviousRunEntirely() {
        let coordinator = makeCoordinatorWithFinishedRun()
        coordinator.startSendQueue()
        XCTAssertTrue(coordinator.hasCompletedASend)

        coordinator.importCSV(data: Data("Name,Email\nNew,new@example.com".utf8),
                              sourceLabel: "fresh.csv")

        XCTAssertNil(coordinator.queue)
        XCTAssertFalse(coordinator.hasCompletedASend,
                       "a new list is a new campaign — the old run's state must not leak into it")
    }
}
