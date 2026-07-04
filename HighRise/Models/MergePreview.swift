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

    /// True when this row's address already appeared earlier in the list. The
    /// first occurrence sends; later duplicates are held back so the same person
    /// isn't emailed twice. Determined across the whole list by `mergeAll`, so a
    /// preview merged in isolation is never a duplicate.
    let isDuplicate: Bool

    /// True when this row's address (or its domain) is on the do-not-contact
    /// list. Held back silently on future merges without editing the source.
    let isSuppressed: Bool

    /// Per-recipient attachment file paths resolved from a data column (empty
    /// when the feature isn't used), plus any of those paths that don't exist
    /// on disk — a missing file blocks the row rather than sending a broken one.
    let attachmentPaths: [String]
    let missingAttachmentPaths: [String]

    init(id: UUID, contact: Contact, resolvedSubject: String, resolvedBody: String,
         unresolvedFields: [String], hasValidEmail: Bool,
         isDuplicate: Bool = false, isSuppressed: Bool = false,
         attachmentPaths: [String] = [], missingAttachmentPaths: [String] = []) {
        self.id = id
        self.contact = contact
        self.resolvedSubject = resolvedSubject
        self.resolvedBody = resolvedBody
        self.unresolvedFields = unresolvedFields
        self.hasValidEmail = hasValidEmail
        self.isDuplicate = isDuplicate
        self.isSuppressed = isSuppressed
        self.attachmentPaths = attachmentPaths
        self.missingAttachmentPaths = missingAttachmentPaths
    }

    /// A preview is safe to send only if it has a valid recipient, no leftover
    /// placeholders, isn't a repeat of an earlier row, isn't suppressed, and all
    /// of its per-recipient attachment files exist.
    var isSendable: Bool {
        hasValidEmail && unresolvedFields.isEmpty && !isDuplicate && !isSuppressed
            && missingAttachmentPaths.isEmpty
    }

    var blockingReason: String? {
        if !hasValidEmail {
            return contact.email.isEmpty
                ? "No email address."
                : "Invalid email address: \(contact.email)"
        }
        if isSuppressed {
            return "On your do-not-contact list — \(contact.email) is skipped."
        }
        if !unresolvedFields.isEmpty {
            let list = unresolvedFields.joined(separator: ", ")
            return "Missing data for: \(list)"
        }
        if !missingAttachmentPaths.isEmpty {
            let names = missingAttachmentPaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            return "Attachment file not found: \(names)"
        }
        if isDuplicate {
            return "Duplicate of an earlier recipient — held back so \(contact.email) isn't emailed twice."
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
