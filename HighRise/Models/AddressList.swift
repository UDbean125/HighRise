import Foundation

/// Summarizes a comma-separated envelope field (CC / BCC): how many addresses
/// it holds, how many are `{{Field}}` references resolved per-recipient, and
/// which fixed addresses look invalid. Pure, so the parsing and validation are
/// unit-tested; the Send envelope card shows the count and flags typos before a
/// run goes out with a bad CC.
enum AddressList {

    struct Summary: Equatable {
        /// Non-empty comma-separated entries.
        let total: Int
        /// Entries containing a `{{merge field}}` (validated per recipient, not now).
        let placeholders: Int
        /// Fixed (non-placeholder) entries that fail email validation.
        let invalid: [String]

        var hasInvalid: Bool { !invalid.isEmpty }
    }

    static func summarize(_ field: String) -> Summary {
        let entries = field
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var placeholders = 0
        var invalid: [String] = []
        for entry in entries {
            if entry.contains("{{") {
                placeholders += 1
            } else if !EmailValidator.isValid(entry) {
                invalid.append(entry)
            }
        }
        return Summary(total: entries.count, placeholders: placeholders, invalid: invalid)
    }

    /// A short caption like "2 addresses" / "1 address · 1 invalid", or nil for
    /// an empty field.
    static func caption(_ summary: Summary) -> String? {
        guard summary.total > 0 else { return nil }
        var text = "\(summary.total) address\(summary.total == 1 ? "" : "es")"
        if summary.hasInvalid {
            text += " · \(summary.invalid.count) invalid"
        }
        return text
    }
}
