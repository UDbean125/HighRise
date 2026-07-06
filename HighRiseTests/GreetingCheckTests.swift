import Testing
@testable import HighRise

/// The greeting check nudges toward a warmer opening, so its word-boundary
/// matching (no false hits on "Hindsight") and empty-line skipping are pinned.
struct GreetingCheckTests {

    @Test("Recognizes common salutations at the start")
    func recognizes() {
        #expect(GreetingCheck.opensWithGreeting("Hi {{First Name}},\n\nBody"))
        #expect(GreetingCheck.opensWithGreeting("Hello there,"))
        #expect(GreetingCheck.opensWithGreeting("Dear {{Name}},"))
        #expect(GreetingCheck.opensWithGreeting("Good morning {{First Name}},"))
        #expect(GreetingCheck.opensWithGreeting("HEY, quick one"))   // case-insensitive
    }

    @Test("Skips leading blank lines to find the first real line")
    func skipsBlankLines() {
        #expect(GreetingCheck.opensWithGreeting("\n\n   \nHi {{First Name}},"))
    }

    @Test("A word boundary is required — no false hit on similar words")
    func wordBoundary() {
        #expect(!GreetingCheck.opensWithGreeting("Hindsight is 20/20"))   // not "Hi"
        #expect(!GreetingCheck.opensWithGreeting("Heyday sale ends soon")) // not "Hey"
    }

    @Test("No greeting when the body opens with the pitch")
    func noGreeting() {
        #expect(!GreetingCheck.opensWithGreeting("Just wanted to reach out about {{Company}}."))
        #expect(!GreetingCheck.opensWithGreeting(""))
        #expect(!GreetingCheck.opensWithGreeting("   \n  "))
    }
}
