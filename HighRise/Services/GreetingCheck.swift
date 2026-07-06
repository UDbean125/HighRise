import Foundation

/// Detects whether an email body opens with a salutation ("Hi …", "Dear …").
/// A cold email that dives straight into the pitch reads as a blast; opening
/// with a personalized greeting lifts replies. Pure, so the detection is
/// unit-tested; the Compose content check turns a "no" into a gentle tip.
enum GreetingCheck {

    /// Common opening salutations (lowercased). Matched as a whole word at the
    /// start of the first non-empty line.
    static let salutations = [
        "hi", "hello", "hey", "dear", "greetings",
        "good morning", "good afternoon", "good evening"
    ]

    /// True when the body's first non-empty line begins with a salutation.
    static func opensWithGreeting(_ body: String) -> Bool {
        guard let firstLine = firstNonEmptyLine(body) else { return false }
        let lower = firstLine.lowercased()
        return salutations.contains { salutation in
            guard lower.hasPrefix(salutation) else { return false }
            // Require a word boundary after the salutation so "Hindsight" or
            // "Heyday" don't count as "Hi"/"Hey".
            let after = lower.dropFirst(salutation.count).first
            return after == nil || !after!.isLetter
        }
    }

    private static func firstNonEmptyLine(_ body: String) -> String? {
        body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
