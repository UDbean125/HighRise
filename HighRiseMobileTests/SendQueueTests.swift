import XCTest
@testable import HighRiseMobile

final class SendQueueTests: XCTestCase {
    private func preview(email: String) -> MergePreview {
        let contact = Contact(fields: ["Email": email], email: email)
        return MergePreview(id: contact.id, contact: contact, resolvedSubject: "Hi",
                             resolvedBody: "Body", unresolvedFields: [], hasValidEmail: true)
    }

    func testAdvancesThroughQueueAndRecordsOutcomes() {
        var queue = SendQueue(items: [preview(email: "a@example.com"), preview(email: "b@example.com")])
        XCTAssertEqual(queue.current?.contact.email, "a@example.com")
        XCTAssertFalse(queue.isFinished)

        queue.recordOutcome(.sent)
        XCTAssertEqual(queue.current?.contact.email, "b@example.com")
        XCTAssertEqual(queue.completedCount, 1)

        queue.recordOutcome(.skipped(reason: "test"))
        XCTAssertTrue(queue.isFinished)
        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.outcomes.count, 2)
        XCTAssertEqual(queue.outcomes.map(\.isSuccess), [true, false])
    }

    func testEmptyQueueStartsFinished() {
        let queue = SendQueue(items: [])
        XCTAssertTrue(queue.isFinished)
        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.totalCount, 0)
    }

    func testRecordOutcomeOnFinishedQueueIsNoOp() {
        var queue = SendQueue(items: [preview(email: "a@example.com")])
        queue.recordOutcome(.sent)
        XCTAssertTrue(queue.isFinished)

        queue.recordOutcome(.sent)
        XCTAssertEqual(queue.outcomes.count, 1)
    }
}
