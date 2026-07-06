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
        return "Unclosed merge field — check your {{ }} braces so every field fills in."
    }
}
