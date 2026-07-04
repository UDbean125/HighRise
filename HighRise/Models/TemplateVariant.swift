import Foundation

/// A per-recipient routing rule: "does this contact's {{field}} satisfy a
/// simple test?" Used to pick a template variant without any template language —
/// the have-data / don't-have-data and value-equals cases cover most real
/// conditional-content needs.
struct RoutingRule: Equatable, Codable {
    enum Predicate: String, CaseIterable, Identifiable, Equatable, Codable {
        case isNotEmpty = "is filled in"
        case isEmpty = "is empty"
        case equals = "equals"
        case notEquals = "is not"
        var id: String { rawValue }

        /// Whether this predicate compares against a typed value.
        var needsValue: Bool { self == .equals || self == .notEquals }
    }

    /// The column/field this rule tests.
    var field: String
    var predicate: Predicate
    /// The comparison value for `equals` / `notEquals` (ignored otherwise).
    var value: String

    init(field: String = "", predicate: Predicate = .isNotEmpty, value: String = "") {
        self.field = field
        self.predicate = predicate
        self.value = value
    }

    /// Whether `contact` satisfies this rule. Matching mirrors the merge engine:
    /// case- and whitespace-insensitive, empty-aware.
    func matches(_ contact: Contact) -> Bool {
        let raw = contact.value(for: field)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch predicate {
        case .isNotEmpty: return !raw.isEmpty
        case .isEmpty:    return raw.isEmpty
        case .equals:     return raw.caseInsensitiveCompare(value.trimmingCharacters(in: .whitespaces)) == .orderedSame
        case .notEquals:  return raw.caseInsensitiveCompare(value.trimmingCharacters(in: .whitespaces)) != .orderedSame
        }
    }

    /// A short human description, e.g. `Region is filled in` or `Plan equals Pro`.
    var summary: String {
        let name = field.isEmpty ? "(choose a field)" : field
        return predicate.needsValue ? "\(name) \(predicate.rawValue) “\(value)”" : "\(name) \(predicate.rawValue)"
    }
}

/// An alternate subject/body sent to recipients matching a routing rule. The
/// first variant whose rule matches wins; the base template is the fallback.
struct TemplateVariant: Equatable, Identifiable, Codable {
    let id: UUID
    var rule: RoutingRule
    var subject: String
    var body: String

    init(id: UUID = UUID(), rule: RoutingRule = RoutingRule(), subject: String = "", body: String = "") {
        self.id = id
        self.rule = rule
        self.subject = subject
        self.body = body
    }
}
