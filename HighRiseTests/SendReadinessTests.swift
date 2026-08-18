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

    @Test("Only the recipient check is required; the rest are advisory")
    func severityAssignment() {
        let r = SendReadiness.assess(readyCount: 2, contentScore: 100,
                                     missingAttachments: 0, mode: .send)
        let required = r.checks.filter { $0.severity == .required }
        let advisory = r.checks.filter { $0.severity == .advisory }
        #expect(required.count == 1)
        #expect(advisory.count == 3)
    }

    // MARK: - Suppressed CC/BCC

    /// The addresses are dropped before delivery either way, so this can never
    /// block a send — it only has to be visible.
    @Test("A suppressed CC/BCC address is an advisory, never a blocker")
    func suppressedEnvelopeIsAdvisory() {
        let r = SendReadiness.assess(readyCount: 2, contentScore: 100,
                                     missingAttachments: 0, mode: .send,
                                     suppressedEnvelopeAddresses: 1)
        #expect(r.canSend)
        #expect(r.failedAdvisory.contains { $0.title.contains("do-not-contact") })
    }

    @Test("The suppressed CC/BCC check passes and stays quiet when there are none")
    func noSuppressedEnvelopeAddresses() {
        let r = SendReadiness.assess(readyCount: 2, contentScore: 100,
                                     missingAttachments: 0, mode: .send,
                                     suppressedEnvelopeAddresses: 0)
        #expect(r.failedAdvisory.isEmpty)
        #expect(r.checks.contains { $0.title == "CC/BCC clear of your do-not-contact list" })
    }

    @Test("One suppressed address reads in the singular")
    func suppressedEnvelopeSingular() {
        let r = SendReadiness.assess(readyCount: 1, contentScore: 100,
                                     missingAttachments: 0, mode: .send,
                                     suppressedEnvelopeAddresses: 1)
        #expect(r.failedAdvisory.first?.title
            == "1 CC/BCC address is on your do-not-contact list — it won't be included")
    }

    @Test("Several suppressed addresses read in the plural")
    func suppressedEnvelopePlural() {
        let r = SendReadiness.assess(readyCount: 1, contentScore: 100,
                                     missingAttachments: 0, mode: .send,
                                     suppressedEnvelopeAddresses: 2)
        #expect(r.failedAdvisory.first?.title
            == "2 CC/BCC addresses are on your do-not-contact list — they won't be included")
    }

    /// Callers that predate this check keep their old verdict, so the default
    /// can't quietly add a warning to a clean run.
    @Test("Omitting the count leaves the report unchanged")
    func defaultsToNoSuppressedAddresses() {
        let r = SendReadiness.assess(readyCount: 2, contentScore: 100,
                                     missingAttachments: 0, mode: .send)
        #expect(r.failedAdvisory.isEmpty)
        #expect(r.headline == "You're ready — 2 messages to send")
    }
}
