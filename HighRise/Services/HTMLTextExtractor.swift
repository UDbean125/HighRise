import Foundation

/// A minimal HTML → plain-text reducer for building the `text/plain` alternative
/// of a `multipart/alternative` message. Pure and Foundation-only.
///
/// This is intentionally simple (strip tags, turn block elements into line
/// breaks, decode the common entities) — the plain part is a fallback for
/// clients that can't render the HTML, not a faithful rendering.
enum HTMLTextExtractor {

    static func plainText(fromHTML html: String) -> String {
        var text = html
        // Turn common block/line elements into newlines before stripping tags.
        for (pattern, replacement) in [
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</p>", "\n\n"),
            ("(?i)</div>", "\n"),
            ("(?i)</h[1-6]>", "\n\n"),
            ("(?i)</li>", "\n"),
        ] {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        // Strip all remaining tags.
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode the handful of entities we emit or commonly see.
        for (entity, char) in [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "),
        ] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        // Collapse 3+ newlines and trim.
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
