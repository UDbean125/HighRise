import Testing
@testable import HighRise

/// The Send pre-flight preview names who a batch is going to; its truncation and
/// natural-language joining are pinned so the count in "+ N more" is always
/// right and small batches read grammatically.
struct RecipientPreviewTests {

    @Test("Empty or all-blank input has a friendly placeholder")
    func empty() {
        #expect(RecipientPreview.summary([]) == "No recipients yet")
        #expect(RecipientPreview.summary(["", "   "]) == "No recipients yet")
    }

    @Test("Small lists read as a natural sentence")
    func naturalJoins() {
        #expect(RecipientPreview.summary(["Jordan"]) == "Jordan")
        #expect(RecipientPreview.summary(["Jordan", "Alex"]) == "Jordan and Alex")
        #expect(RecipientPreview.summary(["Jordan", "Alex", "Sam"]) == "Jordan, Alex and Sam")
    }

    @Test("Lists longer than max collapse the tail into a count")
    func truncation() {
        #expect(RecipientPreview.summary(["A", "B", "C", "D"]) == "A, B, C + 1 more")
        let many = (0..<43).map { "n\($0)" }
        #expect(RecipientPreview.summary(many) == "n0, n1, n2 + 40 more")
    }

    @Test("Names are trimmed and blanks dropped before counting")
    func trimming() {
        #expect(RecipientPreview.summary([" Jordan ", "Alex"]) == "Jordan and Alex")
        // The blank in the middle shouldn't inflate the "+ N more" count.
        #expect(RecipientPreview.summary(["A", "  ", "B", "C", "D"]) == "A, B, C + 1 more")
    }

    @Test("A custom max is respected")
    func customMax() {
        #expect(RecipientPreview.summary(["A", "B", "C"], max: 2) == "A, B + 1 more")
    }
}
