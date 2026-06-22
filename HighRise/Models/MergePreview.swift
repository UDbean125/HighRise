import Foundation

/// The result of merging the template against one contact.
///
/// Carries enough information for the review screen to show the rendered
/// message *and* to warn about problems before anything is sent: unresolved
/// placeholders (a column the template wanted but this row didn't have) and an
/// invalid or missing email address.
struct MergePreview: Identifiable {
    let id: UUID
    let contact: Contact
    let resolvedSubject: String
    let resolvedBody: String

    /// Placeholder names that had no matching, non-empty field for this contact.
    /// A message with unresolved fields would go out with literal `{{…}}` text,
    /// so these are blocked from sending by default.
    let unresolvedFields: [String]

    /// Whether `contact.email` is a syntactically valid address.
    let hasValidEmail: Bool

    /// A preview is safe to send only if it has a valid recipient and no
    /// leftover placeholders.
    var isSendable: Bool {
        hasValidEmail && unresolvedFields.isEmpty
    }

    var blockingReason: String? {
        if !hasValidEmail {
            return contact.email.isEmpty
                ? "No email address."
                : "Invalid email address: \(contact.email)"
        }
        if !unresolvedFields.isEmpty {
            let list = unresolvedFields.joined(separator: ", ")
            return "Missing data for: \(list)"
        }
        return nil
    }
}

/// The outcome of attempting to deliver (or draft) one merged message.
struct SendOutcome: Identifiable {
    enum Status: Equatable {
        case drafted
        case sent
        case skipped(reason: String)
        case failed(reason: String)
    }

    let id: UUID
    let contact: Contact
    let status: Status

    var isSuccess: Bool {
        switch status {
        case .drafted, .sent: return true
        case .skipped, .failed: return false
        }
    }
}
