import Testing
@testable import HighRise

/// The Home "next step" CTA is the app's primary wayfinding, so its priority
/// order must be exactly right — never point someone at Send before rows are
/// ready, or at Review before a list is in.
struct NextStepTests {

    @Test("With no template, the first step is to compose")
    func compose() {
        let s = NextStep.suggest(hasTemplate: false, contactCount: 0, readyCount: 0, hasSent: false)
        #expect(s.action == .compose)
    }

    @Test("With a template but no contacts, import next")
    func contacts() {
        let s = NextStep.suggest(hasTemplate: true, contactCount: 0, readyCount: 0, hasSent: false)
        #expect(s.action == .contacts)
    }

    @Test("Contacts loaded but none ready points at Review to fix them")
    func fixHeld() {
        let s = NextStep.suggest(hasTemplate: true, contactCount: 10, readyCount: 0, hasSent: false)
        #expect(s.action == .review)
        #expect(s.title == "A few recipients need attention")
    }

    @Test("Rows ready and nothing sent yet points at Review & send with a count")
    func readyToSend() {
        let many = NextStep.suggest(hasTemplate: true, contactCount: 10, readyCount: 8, hasSent: false)
        #expect(many.action == .review)
        #expect(many.detail.contains("8 messages are ready"))

        let one = NextStep.suggest(hasTemplate: true, contactCount: 1, readyCount: 1, hasSent: false)
        #expect(one.detail.contains("1 message is ready"))
    }

    @Test("After a run, there's nothing pressing to do")
    func done() {
        let s = NextStep.suggest(hasTemplate: true, contactCount: 10, readyCount: 8, hasSent: true)
        #expect(s.action == .done)
    }

    @Test("A template being ready outranks having sent before")
    func priorityOrder() {
        // No template wins even if a previous run happened.
        let s = NextStep.suggest(hasTemplate: false, contactCount: 5, readyCount: 3, hasSent: true)
        #expect(s.action == .compose)
    }
}
