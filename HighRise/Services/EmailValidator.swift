import Foundation

/// Pragmatic email-address validation.
///
/// Deliberately not a full RFC 5322 grammar — that accepts addresses no mail
/// server in practice will. This catches the mistakes that actually appear in
/// pasted contact lists (missing `@`, missing domain, trailing commas, spaces)
/// while accepting the addresses people really use.
enum EmailValidator {
    private static let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#

    private static let regex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    static func isValid(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let regex else { return false }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return regex.firstMatch(in: trimmed, range: range) != nil
    }
}
