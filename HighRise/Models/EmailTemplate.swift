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

    /// One parsed `{{ … }}` occurrence: the field name plus a chain of pipe
    /// filters — `{{First Name|there}}`, `{{Amount|currency:USD}}`,
    /// `{{Renewal Date|default:soon|date:MMMM d, yyyy}}`.
    ///
    /// A `default:` filter (or a bare `{{Field|there}}`, which parses to one)
    /// makes the placeholder optional: an empty/missing value uses the fallback
    /// instead of blocking the send. Without any `default`, a missing value
    /// still blocks the row — fallbacks stay a per-field opt-in. Other filters
    /// (upper, date, currency, …) transform whatever value is resolved.
    struct PlaceholderToken: Equatable {
        let name: String
        let filters: [MergeValueFormatter.Filter]

        /// The fallback supplied by the first `default:` filter, if any.
        var fallback: String? {
            for filter in filters {
                if case .defaultValue(let text) = filter { return text }
            }
            return nil
        }

        /// Filters that actually transform the value (everything but `default:`),
        /// in written order.
        var transforms: [MergeValueFormatter.Filter] {
            filters.filter { !$0.isDefault }
        }
    }

    /// Parses the raw inner text of a `{{ … }}` occurrence into a name + filters.
    /// Splits on pipes; the first piece is the field name, each remaining piece a
    /// filter (a bare fallback like `there` becomes a `default:` filter).
    static func token(fromRawPlaceholder inner: String) -> PlaceholderToken {
        let pieces = inner.components(separatedBy: "|")
        let name = pieces.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let filters = pieces.dropFirst().map { MergeValueFormatter.parseFilter($0) }
        return PlaceholderToken(name: name, filters: filters)
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
