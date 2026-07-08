import Foundation

/// Renders a Rich (Markdown) body for the Compose live preview using
/// Foundation's **native** Markdown parser — deliberately *not* the HTML path,
/// which would need WebKit and be flaky. It keeps formatting inline (bold,
/// italic, links) while preserving line breaks, and shows "- " lines with a
/// real bullet. Falls back to plain text if the Markdown can't be parsed.
///
/// This is a preview approximation; the actual send still goes through
/// `MarkdownToHTML`. Pure and Foundation-only, so the text it produces is
/// unit-tested.
enum RichPreview {

    static func attributed(from markdown: String) -> AttributedString {
        let prepared = bulletized(markdown)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: prepared, options: options) {
            return parsed
        }
        return AttributedString(prepared)
    }

    /// Turn Markdown "- " list lines into "• " so they read as bullets — the
    /// inline-only parser doesn't build real lists, and a literal "- " looks
    /// unfinished in the preview.
    static func bulletized(_ markdown: String) -> String {
        markdown
            .components(separatedBy: "\n")
            .map { line -> String in
                let trimmed = line.drop { $0 == " " }
                return trimmed.hasPrefix("- ") ? "• " + trimmed.dropFirst(2) : line
            }
            .joined(separator: "\n")
    }
}
