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
}
