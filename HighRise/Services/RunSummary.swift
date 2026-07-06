import Foundation

/// A compact one-line summary of a completed run's outcomes — e.g.
/// "42 sent · 2 failed · 1 skipped" or "10 drafts created". Pure and
/// deterministic, so the wording and pluralization are unit-tested.
enum RunSummary {

    struct Tally: Equatable {
        var sent = 0
        var drafted = 0
        var failed = 0
        var skipped = 0

        var total: Int { sent + drafted + failed + skipped }
        var succeeded: Int { sent + drafted }
    }

    static func tally(_ outcomes: [SendOutcome]) -> Tally {
        var t = Tally()
        for outcome in outcomes {
            switch outcome.status {
            case .sent:    t.sent += 1
            case .drafted: t.drafted += 1
            case .failed:  t.failed += 1
            case .skipped: t.skipped += 1
            }
        }
        return t
    }

    /// The summary line for a set of outcomes. Empty input yields a friendly
    /// placeholder rather than a blank string.
    static func line(from outcomes: [SendOutcome]) -> String {
        let t = tally(outcomes)
        guard t.total > 0 else { return "No messages yet" }

        var parts: [String] = []
        if t.sent > 0    { parts.append("\(t.sent) sent") }
        if t.drafted > 0 { parts.append("\(t.drafted) draft\(t.drafted == 1 ? "" : "s") created") }
        if t.failed > 0  { parts.append("\(t.failed) failed") }
        if t.skipped > 0 { parts.append("\(t.skipped) skipped") }
        return parts.joined(separator: " · ")
    }
}
