import Testing
@testable import HighRise

/// Malformed braces silently drop a merge field, so the balance check is pinned.
struct PlaceholderCheckTests {

    @Test("Balanced braces produce no warning")
    func balanced() {
        #expect(PlaceholderCheck.malformedWarning(in: "Hi {{First Name}}") == nil)
        #expect(PlaceholderCheck.malformedWarning(in: "{{A}} and {{B}}") == nil)
        #expect(PlaceholderCheck.malformedWarning(in: "plain text, no fields") == nil)
        #expect(PlaceholderCheck.malformedWarning(in: "") == nil)
    }

    @Test("An unclosed or unmatched brace pair warns")
    func unbalanced() {
        #expect(PlaceholderCheck.malformedWarning(in: "Hi {{First Name") != nil)   // no close
        #expect(PlaceholderCheck.malformedWarning(in: "Hi }} there") != nil)         // no open
        #expect(PlaceholderCheck.malformedWarning(in: "{{A}} and {{B") != nil)       // 2 opens, 1 close
    }

    @Test("Merged text with no braces left has no fragments")
    func noLeftovers() {
        #expect(PlaceholderCheck.leftoverBraceFragments(in: "Hi Dana, about the Fifth Street job").isEmpty)
        #expect(PlaceholderCheck.leftoverBraceFragments(in: "").isEmpty)
        #expect(PlaceholderCheck.leftoverBraceFragments(in: "a single { brace is fine").isEmpty)
    }

    @Test("A malformed field left in merged text is reported, quoted")
    func leftoverReported() {
        let fragments = PlaceholderCheck.leftoverBraceFragments(in: "Hi Dana, how is {{Company doing?")
        #expect(fragments == ["{{Company doing?"])
    }

    @Test("Fragments stop at a line break and are capped in length")
    func fragmentsStayShort() {
        let fragments = PlaceholderCheck.leftoverBraceFragments(in: "{{Company\nnext line here")
        #expect(fragments == ["{{Company"])

        let long = PlaceholderCheck.leftoverBraceFragments(in: "{{" + String(repeating: "x", count: 200))
        #expect(long.count == 1)
        #expect(long[0].count <= 24)
    }

    @Test("Repeated and multiple fragments dedupe, in order, up to the limit")
    func multipleFragments() {
        let fragments = PlaceholderCheck.leftoverBraceFragments(in: "{{A one {{A one {{B two")
        #expect(fragments == ["{{A one", "{{B two"])

        let many = PlaceholderCheck.leftoverBraceFragments(in: "{{a {{b {{c {{d", limit: 2)
        #expect(many.count == 2)
    }

    @Test("A stray closing pair counts too — it also renders verbatim")
    func strayClose() {
        #expect(PlaceholderCheck.leftoverBraceFragments(in: "Thanks}} again") == ["}} again"])
    }
}
