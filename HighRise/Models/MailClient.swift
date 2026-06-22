import Foundation

/// The desktop email client HighRise drives via AppleScript automation.
///
/// Both Apple Mail and Microsoft Outlook (for Mac) expose scripting
/// dictionaries that let us compose, save, and send messages from the user's
/// own account — no SMTP credentials, no third-party SDK, no servers. The mail
/// leaves from the user's real outbox so replies, signatures, and deliverability
/// all behave exactly as if they'd typed it themselves.
enum MailClient: String, CaseIterable, Identifiable {
    case appleMail = "Apple Mail"
    case outlook = "Microsoft Outlook"

    var id: String { rawValue }

    /// The macOS application name as it appears to AppleScript (`tell application "…"`).
    var scriptingName: String {
        switch self {
        case .appleMail: return "Mail"
        case .outlook:   return "Microsoft Outlook"
        }
    }

    /// Bundle identifier, used to check whether the client is installed.
    var bundleIdentifier: String {
        switch self {
        case .appleMail: return "com.apple.mail"
        case .outlook:   return "com.microsoft.Outlook"
        }
    }

    var symbolName: String {
        switch self {
        case .appleMail: return "envelope"
        case .outlook:   return "envelope.badge"
        }
    }
}

/// What HighRise does with each composed message.
///
/// `draft` is the safe default: every personalized message is created in the
/// client's Drafts so the user can eyeball them and send on their own terms.
/// `send` dispatches immediately and is gated behind an explicit confirmation
/// in the UI — a bulk mailer that fires on one click is how accidents happen.
enum SendMode: String, CaseIterable, Identifiable {
    case draft = "Save as drafts"
    case send = "Send immediately"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .draft:
            return "Each message is created in your Drafts folder for review. Nothing is sent until you send it yourself."
        case .send:
            return "Each message is sent immediately from your account. This cannot be undone."
        }
    }
}
