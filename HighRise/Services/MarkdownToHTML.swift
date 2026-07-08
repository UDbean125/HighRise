import Foundation

/// Converts a small, safe subset of Markdown to HTML for the rich template
/// editor, so users can format an email (bold, italic, links, bullet lists)
/// without hand-writing HTML.
///
/// Design rules that make it safe to email the output:
/// - Literal text is HTML-escaped (`&`, `<`, `>`, `"`), so a stray `<` renders
///   as text rather than breaking the markup.
/// - `{{merge fields}}` pass through **untouched** — the merge engine still
///   substitutes and HTML-escapes their values afterward, so escaping isn't
///   double-applied and placeholders never get mangled here.
///
/// Deliberately conservative (a nudge toward nice email, not a full CommonMark
/// engine). Pure and Foundation-only, so the grammar and escaping are
/// exhaustively unit-tested — important, since this becomes outgoing mail.
enum MarkdownToHTML {

    /// The HTML for a Markdown template body. Blank lines separate paragraphs;
    /// a block whose every line starts with "- " becomes a bullet list.
    static func html(from markdown: String) -> String {
        blocks(in: markdown).map(render).joined()
    }

    // MARK: Block splitting

    private static func blocks(in text: String) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty { result.append(current); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func render(_ lines: [String]) -> String {
        let isBulleted = lines.allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ")
        }
        if isBulleted {
            let items = lines.map { line -> String in
                let content = String(line.trimmingCharacters(in: .whitespaces).dropFirst(2))
                return "<li>" + inline(content) + "</li>"
            }
            return "<ul>" + items.joined() + "</ul>"
        }
        return "<p>" + lines.map(inline).joined(separator: "<br>") + "</p>"
    }

    // MARK: Inline formatting

    /// Protect `{{merge fields}}` first (so nothing inside them is escaped or
    /// treated as markup), then escape the literal text, then apply links, bold,
    /// and italic, and finally restore the fields verbatim. Order matters within
    /// formatting too: bold consumes `**` before the single-`*` italic pass.
    private static func inline(_ text: String) -> String {
        // 1. Swap each {{…}} for an inert sentinel the passes below won't touch.
        var fields: [String] = []
        let masked = replace(text, pattern: #"\{\{[^}]*\}\}"#) { m, str in
            let token = sentinel(fields.count)
            fields.append(group(m, 0, in: str))
            return token
        }

        // 2. Escape + format the literal text around the sentinels.
        var s = escape(masked)
        s = replace(s, pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#) { m, str in
            "<a href=\"\(group(m, 2, in: str))\">\(group(m, 1, in: str))</a>"
        }
        s = replace(s, pattern: #"\*\*([^*]+)\*\*"#) { m, str in
            "<strong>" + group(m, 1, in: str) + "</strong>"
        }
        s = replace(s, pattern: #"\*([^*]+)\*"#) { m, str in
            "<em>" + group(m, 1, in: str) + "</em>"
        }

        // 3. Restore the merge fields exactly as written.
        for (index, field) in fields.enumerated() {
            s = s.replacingOccurrences(of: sentinel(index), with: field)
        }
        return s
    }

    /// A placeholder unlikely to occur in input and inert to escaping and the
    /// formatting regexes (Unicode private-use brackets around the index).
    private static func sentinel(_ index: Int) -> String { "\u{E000}\(index)\u{E001}" }

    private static func escape(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "&", with: "&amp;")
        s = s.replacingOccurrences(of: "<", with: "&lt;")
        s = s.replacingOccurrences(of: ">", with: "&gt;")
        s = s.replacingOccurrences(of: "\"", with: "&quot;")
        return s
    }

    // MARK: Regex helpers

    private static func replace(_ s: String, pattern: String,
                                _ transform: (NSTextCheckingResult, String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }

        var result = ""
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            result += transform(match, s)
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in s: String) -> String {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return "" }
        return (s as NSString).substring(with: range)
    }
}
