import Foundation

/// Backs the Compose formatting toolbar for the Rich (Markdown) body: what each
/// button inserts and how it's spliced into the existing text. Insertion (not
/// selection-wrapping) keeps it working on the app's minimum macOS, matching how
/// merge fields are already inserted. Pure, so the snippets and the spacing
/// rules are unit-tested; the view just swaps in the returned text.
enum MarkdownFormatting {

    enum Style: String, CaseIterable, Identifiable {
        case bold, italic, link, bullet
        var id: String { rawValue }

        var label: String {
            switch self {
            case .bold:   return "Bold"
            case .italic: return "Italic"
            case .link:   return "Link"
            case .bullet: return "Bullet list"
            }
        }

        var systemImage: String {
            switch self {
            case .bold:   return "bold"
            case .italic: return "italic"
            case .link:   return "link"
            case .bullet: return "list.bullet"
            }
        }

        /// The Markdown inserted for this style. The placeholder words are meant
        /// to be typed over.
        var snippet: String {
            switch self {
            case .bold:   return "**bold text**"
            case .italic: return "*italic text*"
            case .link:   return "[link text](https://)"
            case .bullet: return "- list item"
            }
        }
    }

    /// Splices `style`'s snippet onto `text`, choosing a separator so the result
    /// reads well: a bullet begins on its own line; inline styles get a single
    /// leading space after non-space text. Empty text takes the snippet as-is.
    static func inserting(_ style: Style, into text: String) -> String {
        guard !text.isEmpty else { return style.snippet }
        switch style {
        case .bullet:
            return text + (text.hasSuffix("\n") ? "" : "\n") + style.snippet
        case .bold, .italic, .link:
            let needsSpace = !(text.hasSuffix(" ") || text.hasSuffix("\n"))
            return text + (needsSpace ? " " : "") + style.snippet
        }
    }

    // MARK: - Selection wrapping (WYSIWYG)

    /// The result of applying a style to a selection: the new text and where the
    /// editor should leave the selection afterward (both in NSString/UTF-16
    /// terms, matching `NSTextView.selectedRange`).
    struct WrapResult: Equatable {
        let text: String
        let selection: NSRange
    }

    /// Applies `style` to `selection` within `text`, wrapping the selected run in
    /// Markdown (or inserting a placeholder when the selection is empty) and
    /// returning where selection should land — the inner text for bold/italic,
    /// the URL for a link, end-of-block for a bullet. `selection` is clamped
    /// defensively so an out-of-range value can't crash.
    static func wrap(_ text: String, selection: NSRange, style: Style) -> WrapResult {
        let ns = text as NSString
        let loc = max(0, min(selection.location, ns.length))
        let len = max(0, min(selection.length, ns.length - loc))
        let range = NSRange(location: loc, length: len)

        switch style {
        case .bold:   return wrapInline(ns, range, marker: "**", placeholder: "bold text")
        case .italic: return wrapInline(ns, range, marker: "*", placeholder: "italic text")
        case .link:   return wrapLink(ns, range)
        case .bullet: return prefixLines(ns, range, with: "- ")
        }
    }

    private static func wrapInline(_ ns: NSString, _ range: NSRange,
                                   marker: String, placeholder: String) -> WrapResult {
        let selected = ns.substring(with: range)
        let inner = selected.isEmpty ? placeholder : selected
        let newText = ns.replacingCharacters(in: range, with: marker + inner + marker)
        let innerLoc = range.location + (marker as NSString).length
        return WrapResult(text: newText,
                          selection: NSRange(location: innerLoc, length: (inner as NSString).length))
    }

    private static func wrapLink(_ ns: NSString, _ range: NSRange) -> WrapResult {
        let selected = ns.substring(with: range)
        let label = selected.isEmpty ? "link text" : selected
        let url = "https://"
        let newText = ns.replacingCharacters(in: range, with: "[" + label + "](" + url + ")")
        // Select the URL so it's the first thing the user replaces.
        let urlLoc = range.location + 1 + (label as NSString).length + 2   // "[" + label + "]("
        return WrapResult(text: newText,
                          selection: NSRange(location: urlLoc, length: (url as NSString).length))
    }

    private static func prefixLines(_ ns: NSString, _ range: NSRange, with prefix: String) -> WrapResult {
        let lineRange = ns.lineRange(for: range)
        let block = ns.substring(with: lineRange)
        let hasTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        for i in lines.indices {
            // Skip the empty element after a trailing newline, and blank lines.
            if hasTrailingNewline && i == lines.count - 1 && lines[i].isEmpty { continue }
            if lines[i].isEmpty { continue }
            lines[i] = prefix + lines[i]
        }
        let prefixed = lines.joined(separator: "\n")
        let newText = ns.replacingCharacters(in: lineRange, with: prefixed)
        let caret = lineRange.location + (prefixed as NSString).length
        return WrapResult(text: newText, selection: NSRange(location: caret, length: 0))
    }
}
