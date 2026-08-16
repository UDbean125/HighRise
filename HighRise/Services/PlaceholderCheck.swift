import Foundation

/// A quick sanity check for merge-field braces: an opening `{{` without a
/// matching `}}` (or vice versa) means a field silently won't fill in — an easy
/// typo to make and an embarrassing one to send. Pure, so it's unit-tested; the
/// Compose content check turns an imbalance into a warning.
enum PlaceholderCheck {

    /// A warning when `text` has an unbalanced number of `{{` and `}}`, else nil.
    static func malformedWarning(in text: String) -> String? {
        let opens = text.components(separatedBy: "{{").count - 1
        let closes = text.components(separatedBy: "}}").count - 1
        guard opens != closes else { return nil }
        return message
    }

    /// The one wording used everywhere braces don't line up — Compose's advisory
    /// check and the review screen's hard block say the same thing.
    static let message = "Unclosed merge field — check your {{ }} braces so every field fills in."

    /// Brace fragments still present in *already merged* text.
    ///
    /// The merge regex only matches a well-formed `{{ … }}`, so a typo like
    /// `{{Company` (no closing braces) is invisible to it: nothing resolves,
    /// nothing is reported unresolved, and the literal text sails through to the
    /// recipient. Scanning the rendered output catches that however the braces
    /// got there — a template typo or a data value that contains them.
    ///
    /// Returns short quotable snippets (deduplicated, in order) for the message
    /// shown to the user, or empty when the merged text is clean.
    static func leftoverBraceFragments(in text: String, limit: Int = 3) -> [String] {
        guard text.contains("{{") || text.contains("}}") else { return [] }

        var fragments: [String] = []
        var seen = Set<String>()
        let characters = Array(text)
        var index = 0

        while index + 1 < characters.count && fragments.count < limit {
            let pair = String(characters[index...index + 1])
            guard pair == "{{" || pair == "}}" else {
                index += 1
                continue
            }
            // Quote from the marker up to a line break or the next brace
            // marker, capped so a whole paragraph never lands in a one-line
            // blocking reason. Stopping at the next marker keeps each fragment
            // tight and lets repeats of the same typo collapse together.
            let end = min(index + snippetLength, characters.count)
            var snippet = pair
            var scan = index + 2
            while scan < end {
                let character = characters[scan]
                if character.isNewline { break }
                if scan + 1 < characters.count {
                    let ahead = String(characters[scan...scan + 1])
                    if ahead == "{{" || ahead == "}}" { break }
                }
                snippet.append(character)
                scan += 1
            }
            let trimmed = snippet.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && seen.insert(trimmed).inserted {
                fragments.append(trimmed)
            }
            index += 2
        }
        return fragments
    }

    private static let snippetLength = 24
}
