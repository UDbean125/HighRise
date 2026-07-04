import Foundation

/// Builds an optional opt-out footer using a `mailto:` link — the privacy-honest
/// alternative to a hosted unsubscribe page (which would need a server the app
/// deliberately doesn't have). The recipient replies to an address the sender
/// controls; the sender then adds them to the local do-not-contact list.
///
/// Pure and per-recipient (the mailto pre-fills the recipient's address), so the
/// URL encoding and markup are unit-tested.
enum UnsubscribeFooter {

    /// A `mailto:` URL to `address` with a pre-filled subject and body.
    static func mailtoURL(to address: String, subject: String, body: String) -> String {
        func encode(_ s: String) -> String {
            // Encode everything but alphanumerics — safe inside a query value.
            s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
        }
        return "mailto:\(address)?subject=\(encode(subject))&body=\(encode(body))"
    }

    /// The plain-text footer appended after the body.
    static func plainText(replyTo: String, recipientEmail: String, note: String) -> String {
        let url = mailtoURL(to: replyTo, subject: "Unsubscribe",
                            body: "Please remove \(recipientEmail) from your list.")
        let lead = trimmedNote(note) ?? "Don't want these emails? Unsubscribe here:"
        return "\n\n—\n\(lead) \(url)"
    }

    /// The HTML footer appended after the body; the mailto is attribute-escaped.
    static func html(replyTo: String, recipientEmail: String, note: String) -> String {
        let url = mailtoURL(to: replyTo, subject: "Unsubscribe",
                            body: "Please remove \(recipientEmail) from your list.")
        let href = url.replacingOccurrences(of: "&", with: "&amp;")
        let lead = TemplateMergeEngine.htmlEscape(trimmedNote(note) ?? "Don't want these emails?")
        return "<hr>\n<p style=\"font-size:12px;color:#888\">\(lead) "
            + "<a href=\"\(href)\">Unsubscribe</a></p>"
    }

    private static func trimmedNote(_ note: String) -> String? {
        let t = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
