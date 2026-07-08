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
}
