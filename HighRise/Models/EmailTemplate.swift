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

    /// Optional per-recipient variants. The first variant whose rule matches a
    /// contact supplies that recipient's subject/body; otherwise the base
    /// subject/body is used. The `format` (plain/HTML) is shared across all.
    var variants: [TemplateVariant]

    init(subject: String = "", body: String = "", format: BodyFormat = .plainText,
         variants: [TemplateVariant] = []) {
        self.subject = subject
        self.body = body
        self.format = format
        self.variants = variants
    }

    /// The subject/body to render for `contact`: the first matching variant, or
    /// the base template when none match.
    func effective(for contact: Contact) -> (subject: String, body: String) {
        for variant in variants where variant.rule.matches(contact) {
            return (variant.subject, variant.body)
        }
        return (subject, body)
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

    /// Every piece of merge-able text in the template: the base subject/body plus
    /// each variant's subject/body. Rule fields are handled separately.
    private var allMergeableText: [String] {
        [subject, body] + variants.flatMap { [$0.subject, $0.body] }
    }

    /// The distinct placeholder names referenced anywhere in the base or any
    /// variant, plus the fields used by routing rules, in first-appearance
    /// order. Used to tell the user which columns their template expects.
    var referencedFields: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        func add(_ field: String) {
            let key = field.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            ordered.append(field)
        }
        for text in allMergeableText {
            Self.placeholderNames(in: text).forEach(add)
        }
        variants.forEach { add($0.rule.field) }
        return ordered
    }

    /// The subset of `referencedFields` that appears at least once *without* a
    /// fallback in mergeable text. Only these must be satisfied by the imported
    /// list; a field whose every use carries a fallback can't block a send, and
    /// a routing-rule field being empty is a valid state — so neither triggers
    /// the "no column for …" warning on its own.
    var fieldsRequiringData: [String] {
        var required = Set<String>()
        for text in allMergeableText {
            for token in Self.placeholderTokens(in: text) where token.fallback == nil {
                required.insert(token.name.lowercased())
            }
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
