import Foundation

/// The draft the user writes once and HighRise personalizes per recipient.
///
/// Placeholders use a `{{Field}}` syntax that maps to contact column headers.
/// The double-brace form is deliberately chosen over single braces or `[Field]`
/// so that ordinary prose containing brackets or single braces is never
/// mistaken for a merge field.
struct EmailTemplate: Equatable {

    /// How the body is interpreted when composing the message.
    ///
    /// `plainText` is the robust default and works identically in Mail and
    /// Outlook. `html` is full-fidelity in Outlook; Apple Mail's AppleScript
    /// support for setting HTML is unreliable, so the UI warns when the two
    /// are combined rather than silently shipping broken markup.
    enum BodyFormat: String, CaseIterable, Identifiable, Equatable {
        case plainText = "Plain text"
        case html = "HTML"
        var id: String { rawValue }
    }

    var subject: String
    var body: String
    var format: BodyFormat

    init(subject: String = "", body: String = "", format: BodyFormat = .plainText) {
        self.subject = subject
        self.body = body
        self.format = format
    }

    /// The distinct placeholder names referenced anywhere in subject or body,
    /// in first-appearance order. Used to tell the user which columns their
    /// template expects, and to flag columns the imported list doesn't provide.
    var referencedFields: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for field in Self.placeholderNames(in: subject) + Self.placeholderNames(in: body) {
            let key = field.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                ordered.append(field)
            }
        }
        return ordered
    }

    /// Extracts the trimmed names inside every `{{ … }}` occurrence in `text`.
    static func placeholderNames(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: Self.placeholderPattern) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: text) else { return nil }
            return text[r].trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Matches `{{ FieldName }}` — any run of characters that isn't a brace,
    /// surrounded by double braces, with optional internal whitespace.
    static let placeholderPattern = #"\{\{\s*([^{}]+?)\s*\}\}"#
}
