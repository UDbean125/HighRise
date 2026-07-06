import Testing
@testable import HighRise

/// The word count / reading time is a live writing signal, so its splitting and
/// minute rounding are pinned.
struct WordCountTests {

    @Test("Counts words split on any whitespace")
    func counts() {
        #expect(WordCount.of("").words == 0)
        #expect(WordCount.of("   \n  ").words == 0)
        #expect(WordCount.of("Hello world").words == 2)
        #expect(WordCount.of("one\ttwo\nthree   four").words == 4)
    }

    @Test("Reading minutes round, floored at 1 once there's text")
    func minutes() {
        #expect(WordCount.of("").minutes == 0)
        #expect(WordCount.of("just a few words here").minutes == 1)   // well under 200
        #expect(WordCount.of(String(repeating: "word ", count: 200)).minutes == 1)
        #expect(WordCount.of(String(repeating: "word ", count: 300)).minutes == 2)  // 1.5 → 2
        #expect(WordCount.of(String(repeating: "word ", count: 500)).minutes == 3)  // 2.5 → 3
    }

    @Test("Caption reads naturally and is empty with no words")
    func caption() {
        #expect(WordCount.caption(WordCount.of("")) == "")
        #expect(WordCount.caption(WordCount.of("solo")) == "1 word · ~1 min read")
        #expect(WordCount.caption(WordCount.of("two words")) == "2 words · ~1 min read")
    }
}
