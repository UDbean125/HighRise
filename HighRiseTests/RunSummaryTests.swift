import Testing
import Foundation
@testable import HighRise

/// The run summary is the first thing a user reads after a send, so its counts
/// and wording are pinned — including the sent-vs-drafted distinction and
/// plural "drafts".
struct RunSummaryTests {

    private func outcome(_ status: SendOutcome.Status) -> SendOutcome {
        SendOutcome(id: UUID(),
                    contact: Contact(fields: ["Full Name": "X"], email: "x@y.com"),
                    status: status)
    }

    @Test("Tally counts each status")
    func tally() {
        let t = RunSummary.tally([
            outcome(.sent), outcome(.sent),
            outcome(.drafted),
            outcome(.failed(reason: "bounced")),
            outcome(.skipped(reason: "duplicate"))
        ])
        #expect(t.sent == 2)
        #expect(t.drafted == 1)
        #expect(t.failed == 1)
        #expect(t.skipped == 1)
        #expect(t.total == 5)
        #expect(t.succeeded == 3)
    }

    @Test("Line joins present categories with a middot")
    func lineJoins() {
        let line = RunSummary.line(from: [
            outcome(.sent), outcome(.sent),
            outcome(.failed(reason: "x")),
            outcome(.skipped(reason: "y"))
        ])
        #expect(line == "2 sent · 1 failed · 1 skipped")
    }

    @Test("Drafts pluralize; a single draft does not")
    func draftPluralization() {
        #expect(RunSummary.line(from: [outcome(.drafted)]) == "1 draft created")
        #expect(RunSummary.line(from: [outcome(.drafted), outcome(.drafted)]) == "2 drafts created")
    }

    @Test("Only non-zero categories appear")
    func omitsZeros() {
        #expect(RunSummary.line(from: [outcome(.sent)]) == "1 sent")
        #expect(RunSummary.line(from: [outcome(.failed(reason: "x"))]) == "1 failed")
    }

    @Test("Empty outcomes yield a friendly placeholder")
    func empty() {
        #expect(RunSummary.line(from: []) == "No messages yet")
        #expect(RunSummary.tally([]).total == 0)
    }
}
