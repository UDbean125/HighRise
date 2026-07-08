import Testing
@testable import HighRise

/// The progress caption is shown live during a run, so its rounding and clamping
/// must never show a count past the total or a negative one, and the verb has to
/// match the mode.
struct SendProgressTests {

    @Test("Fraction maps to a done-of-total count")
    func counts() {
        #expect(SendProgress.caption(fraction: 0, total: 42, mode: .send) == "Sending 0 of 42…")
        #expect(SendProgress.caption(fraction: 0.5, total: 42, mode: .send) == "Sending 21 of 42…")
        #expect(SendProgress.caption(fraction: 1, total: 42, mode: .send) == "Sending 42 of 42…")
    }

    @Test("Draft mode uses the drafting verb")
    func draftVerb() {
        #expect(SendProgress.caption(fraction: 0.5, total: 10, mode: .draft) == "Drafting 5 of 10…")
    }

    @Test("Out-of-range fractions are clamped to the total")
    func clamping() {
        #expect(SendProgress.caption(fraction: 1.5, total: 5, mode: .send) == "Sending 5 of 5…")
        #expect(SendProgress.caption(fraction: -0.3, total: 5, mode: .send) == "Sending 0 of 5…")
    }

    @Test("An empty run has a plain verb caption")
    func emptyTotal() {
        #expect(SendProgress.caption(fraction: 0, total: 0, mode: .send) == "Sending…")
        #expect(SendProgress.caption(fraction: 0, total: 0, mode: .draft) == "Drafting…")
    }
}
