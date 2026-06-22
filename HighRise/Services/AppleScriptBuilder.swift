import Foundation

/// One personalized message, ready to hand to a mail client.
struct ComposedMessage {
    let recipientEmail: String
    let recipientName: String
    let subject: String
    let body: String
    /// When true, `body` is HTML markup; when false, plain text.
    let isHTML: Bool
}

/// Builds the AppleScript that drives Apple Mail / Outlook for a single message.
///
/// This is isolated from the code that *executes* the script for one reason:
/// **string escaping is the whole ballgame here.** A recipient name, subject,
/// or body containing a `"` or `\` — or, in the worst case, crafted text trying
/// to break out of the string literal — must be neutralized before it lands in
/// a script. Keeping the builder pure means every escaping rule is pinned by a
/// unit test rather than discovered in production against a real customer list.
enum AppleScriptBuilder {

    /// Renders an arbitrary Swift string as an AppleScript string *expression*.
    ///
    /// AppleScript has no escape for newlines inside a `"…"` literal, so we
    /// split on line breaks and re-join the pieces with `& linefeed &`. Within
    /// each piece, backslash and double-quote are the only characters AppleScript
    /// itself treats specially, so those are the only ones we escape. The result
    /// is a self-contained expression like:
    ///
    ///     "Hi \"Sam\"" & linefeed & "Line two"
    ///
    /// An empty string renders as `""`.
    static func stringLiteral(_ value: String) -> String {
        // Normalize CRLF / CR to LF so line splitting is uniform.
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let escapedLines = normalized.components(separatedBy: "\n").map { line -> String in
            let escaped = line
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return escapedLines.joined(separator: " & linefeed & ")
    }

    /// The full `tell application … end tell` script for one message.
    static func script(for message: ComposedMessage,
                       client: MailClient,
                       mode: SendMode) -> String {
        switch client {
        case .appleMail: return appleMailScript(message, mode: mode)
        case .outlook:   return outlookScript(message, mode: mode)
        }
    }

    // MARK: - Apple Mail

    private static func appleMailScript(_ m: ComposedMessage, mode: SendMode) -> String {
        let subject = stringLiteral(m.subject)
        let body = stringLiteral(m.body)
        let address = stringLiteral(m.recipientEmail)
        // Draft: build invisibly and save to Drafts. Send: dispatch immediately.
        let finalAction = mode == .send ? "send newMessage" : "save newMessage"

        // Mail's scripting dictionary only exposes a plain-text `content`
        // property on an outgoing message; there is no reliable HTML-body
        // setter. HTML markup is therefore sent as-is into `content`, which
        // Mail treats as text — the UI warns the user about this so the
        // limitation is a known choice, not a silent surprise.
        return """
        tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:\(subject), content:\(body), visible:false}
            tell newMessage
                make new to recipient at end of to recipients with properties {address:\(address)}
            end tell
            \(finalAction)
        end tell
        """
    }

    // MARK: - Microsoft Outlook

    private static func outlookScript(_ m: ComposedMessage, mode: SendMode) -> String {
        let subject = stringLiteral(m.subject)
        let body = stringLiteral(m.body)
        let address = stringLiteral(m.recipientEmail)
        // Draft: open the composed message so the user can review and send.
        // Send: dispatch immediately.
        let finalAction = mode == .send ? "send newMessage" : "open newMessage"

        // Outlook distinguishes the HTML body (`content`) from the plain-text
        // body (`plain text content`), so HTML is full-fidelity here.
        let bodyProperty = m.isHTML ? "content" : "plain text content"

        return """
        tell application "Microsoft Outlook"
            set newMessage to make new outgoing message with properties {subject:\(subject), \(bodyProperty):\(body)}
            make new recipient at newMessage with properties {email address:{address:\(address)}}
            \(finalAction)
        end tell
        """
    }
}
