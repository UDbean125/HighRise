import Testing
@testable import HighRise

/// The Home greeting adapts to the time of day; its hour boundaries are pinned
/// so no hour ever falls through to the wrong bucket.
struct GreetingTests {

    @Test("Each part of the day maps to the right greeting")
    func buckets() {
        #expect(Greeting.forHour(8)  == "Good morning")
        #expect(Greeting.forHour(13) == "Good afternoon")
        #expect(Greeting.forHour(19) == "Good evening")
        #expect(Greeting.forHour(2)  == "Welcome")
        #expect(Greeting.forHour(23) == "Welcome")
    }

    @Test("Boundary hours land in the expected bucket")
    func boundaries() {
        #expect(Greeting.forHour(5)  == "Good morning")     // start of morning
        #expect(Greeting.forHour(11) == "Good morning")     // last morning hour
        #expect(Greeting.forHour(12) == "Good afternoon")   // start of afternoon
        #expect(Greeting.forHour(16) == "Good afternoon")   // last afternoon hour
        #expect(Greeting.forHour(17) == "Good evening")     // start of evening
        #expect(Greeting.forHour(21) == "Good evening")     // last evening hour
        #expect(Greeting.forHour(22) == "Welcome")          // into late night
        #expect(Greeting.forHour(4)  == "Welcome")          // pre-dawn
        #expect(Greeting.forHour(0)  == "Welcome")          // midnight
    }
}
