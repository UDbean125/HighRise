import Testing
@testable import HighRise

/// The coach-mark tour is a new user's guided first run, so its script is
/// pinned: well-formed steps, and — the load-bearing contract — every step must
/// target a coach-anchor that actually exists in the UI, or that step would
/// silently fail to spotlight anything.
struct HighRiseTourTests {

    @Test("Tour script is well-formed")
    func wellFormed() {
        let steps = HighRiseTour.steps
        #expect(steps.count >= 3)
        #expect(Set(steps.map(\.id)).count == steps.count, "step ids must be unique")
        for step in steps {
            #expect(!step.id.isEmpty)
            #expect(!step.title.isEmpty)
            #expect(!step.message.isEmpty)
            #expect(!step.systemImage.isEmpty)
        }
    }

    @Test("Every step targets a coach-anchor that exists in the UI")
    func targetsKnownAnchors() {
        // The ids attached via `.coachAnchor(...)` in ContentView and
        // TemplateEditorView. Keep this set in sync when adding steps so a typo
        // can never leave a step pointing at nothing.
        let placedAnchors: Set<String> = [
            "sidebar.rail",
            "compose.gallery",
            "compose.subject",
            "compose.templates",
            "footer.continue"
        ]
        for step in HighRiseTour.steps {
            #expect(placedAnchors.contains(step.id),
                    "tour step '\(step.id)' has no matching .coachAnchor in the views")
        }
    }
}
