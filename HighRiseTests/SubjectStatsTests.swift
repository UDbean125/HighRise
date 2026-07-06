import Testing
@testable import HighRise

/// The subject counter is a live typing aid, so its count (grapheme-accurate)
/// and the clip threshold are pinned.
struct SubjectStatsTests {

    @Test("Counts characters and flags nothing when short")
    func short() {
        #expect(SubjectStats.of("").characters == 0)
        #expect(SubjectStats.of("").isLong == false)
        #expect(SubjectStats.of("Hello").characters == 5)
        #expect(SubjectStats.of("Hello").isLong == false)
    }

    @Test("The threshold is exclusive — 60 is fine, 61 is long")
    func threshold() {
        let sixty = String(repeating: "a", count: 60)
        #expect(SubjectStats.of(sixty).characters == 60)
        #expect(SubjectStats.of(sixty).isLong == false)

        let sixtyOne = String(repeating: "a", count: 61)
        #expect(SubjectStats.of(sixtyOne).isLong == true)
    }

    @Test("Emoji and accents count as one grapheme each")
    func graphemes() {
        #expect(SubjectStats.of("🎉").characters == 1)
        #expect(SubjectStats.of("café").characters == 4)
        #expect(SubjectStats.of("👍🏽").characters == 1)   // emoji + skin-tone modifier
    }
}
