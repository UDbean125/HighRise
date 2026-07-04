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

    /// One parsed `{{ … }}` occurrence: the field name plus an optional inline
    /// fallback written after a pipe — `{{First Name|there}}`.
    ///
    /// A fallback makes the placeholder optional: when the row has no value the
    /// fallback text is used instead of blocking the send. `{{Field|}}` (an
    /// explicitly empty fallback) means "render nothing, don't block". Without
    /// a pipe the field is required and a missing value blocks the row, exactly
    /// as before — fallbacks are a per-field opt-in, never a silent default.
    struct PlaceholderToken: Equatable {
        let name: String
        let fallback: String?
    }

    /// Parses the raw inner text of a `{{ … }}` occurrence into name + fallback.
    /// Splits on the *first* pipe so the fallback itself may contain pipes.
    static func token(fromRawPlaceholder inner: String) -> PlaceholderToken {
        guard let pipe = inner.firstIndex(of: "|") else {
            return PlaceholderToken(
                name: inner.trimmingCharacters(in: .whitespacesAndNewlines),
                fallback: nil
            )
        }
        let name = String(inner[..<pipe]).trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = String(inner[inner.index(after: pipe)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return PlaceholderToken(name: name, fallback: fallback)
    }

    /// The distinct placeholder names referenced anywhere in subject or body,
    /// in first-appearance order. Used to tell the user which columns their
    /// template expects. Names are the base field names — a fallback never
    /// changes which column a placeholder refers to.
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

    /// The subset of `referencedFields` that appears at least once *without* a
    /// fallback. Only these must be satisfied by the imported list; a field
    /// whose every use carries a fallback can't block a send, so it shouldn't
    /// trigger the "no column for …" warning either.
    var fieldsRequiringData: [String] {
        var required = Set<String>()
        for token in Self.placeholderTokens(in: subject) + Self.placeholderTokens(in: body)
        where token.fallback == nil {
            required.insert(token.name.lowercased())
        }
        return referencedFields.filter { required.contains($0.lowercased()) }
    }

    /// Extracts the trimmed field names inside every `{{ … }}` occurrence.
    static func placeholderNames(in text: String) -> [String] {
        placeholderTokens(in: text).map(\.name)
    }

    /// Extracts every `{{ … }}` occurrence as a parsed name + fallback token.
    static func placeholderTokens(in text: String) -> [PlaceholderToken] {
        guard let regex = try? NSRegularExpression(pattern: Self.placeholderPattern) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: text) else { return nil }
            return Self.token(fromRawPlaceholder: String(text[r]))
        }
    }

    /// Matches `{{ FieldName }}` — any run of characters that isn't a brace,
    /// surrounded by double braces, with optional internal whitespace.
    static let placeholderPattern = #"\{\{\s*([^{}]+?)\s*\}\}"#
}
