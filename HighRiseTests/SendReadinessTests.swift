import Testing
@testable import HighRise

/// The Send verdict is the last thing users read before committing a run, so
/// its go/no-go logic, severity split, and wording are pinned. The one hard
/// rule: never say "ready" when there's nothing valid to send.
struct SendReadinessTests {

    @Test("No ready recipients blocks the send regardless of other checks")
    func noRecipientsBlocks() {
        let r = SendReadiness.assess(readyCount: 0, contentScore: 100,
                                     missingAttachments: 0, mode: .send)
        #expect(r.canSend == false)
        #expect(r.failedRequired.count == 1)
        #expect(r.headline == "Not ready yet — add at least one valid recipient")
    }

    @Test("A clean run reads ready with no advisories")
    func cleanRun() {
        let r = SendReadiness.assess(readyCount: 5, contentScore: 90,
                                     missingAttachments: 0, mode: .send)
        #expect(r.canSend)
        #expect(r.failedAdvisory.isEmpty)
        #expect(r.headline == "You're ready — 5 messages to send")
    }

    @Test("Advisories are counted but never block; draft wording differs")
    func advisoriesDontBlock() {
        let r = SendReadiness.assess(readyCount: 1, contentScore: 60,
                                     missingAttachments: 2, mode: .draft)
        #expect(r.canSend)                       // advisories don't block
        #expect(r.failedAdvisory.count == 2)     // content + attachments
        #expect(r.headline == "You're ready — 1 draft to create · 2 things worth a look")
    }

    @Test("A single advisory pluralizes correctly")
    func singleAdvisory() {
        let r = SendReadiness.assess(readyCount: 3, contentScore: 50,
                                     missingAttachments: 0, mode: .send)
        #expect(r.headline == "You're ready — 3 messages to send · 1 thing worth a look")
    }

    @Test("Only the recipient check is required; content/attachments are advisory")
    func severityAssignment() {
        let r = SendReadiness.assess(readyCount: 2, contentScore: 100,
                                     missingAttachments: 0, mode: .send)
        let required = r.checks.filter { $0.severity == .required }
        let advisory = r.checks.filter { $0.severity == .advisory }
        #expect(required.count == 1)
        #expect(advisory.count == 2)
    }
}
