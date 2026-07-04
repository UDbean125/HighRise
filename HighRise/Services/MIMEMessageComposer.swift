import Foundation

/// Builds a full RFC 5322 email message (`.eml`) with a `multipart/alternative`
/// body, so a recipient's HTML template can reach Apple Mail at full fidelity.
///
/// Apple Mail's AppleScript dictionary exposes no HTML-body setter (only a
/// plain-text `content`), so the normal send path can't carry HTML into Mail.
/// A `.eml` file with the long-stable `X-Uniform-Type-Identifier:
/// com.apple.mail-draft` header opens in Mail as an editable draft — the
/// documented workaround. **This behavior is undocumented by Apple and can't be
/// exercised in CI; treat it as experimental and smoke-test on a Mac.** The MIME
/// construction itself (headers, boundaries, quoted-printable, encoded-words) is
/// pure and unit-tested.
enum MIMEMessageComposer {

    struct Message {
        let from: String?
        let to: String
        let subject: String
        let html: String
        /// A plain-text alternative shown by clients that don't render HTML.
        let plainText: String
    }

    /// Renders `message` as a complete RFC 5322 `.eml` string. `boundary` and
    /// `date` are injected for deterministic tests; callers pass a unique
    /// boundary and an RFC 822 date.
    static func eml(_ message: Message, boundary: String, date: String = "") -> String {
        var headers: [String] = []
        if let from = message.from, !from.isEmpty { headers.append("From: \(from)") }
        headers.append("To: \(message.to)")
        headers.append("Subject: \(encodeHeaderValue(message.subject))")
        if !date.isEmpty { headers.append("Date: \(date)") }
        headers.append("MIME-Version: 1.0")
        headers.append("X-Uniform-Type-Identifier: com.apple.mail-draft")
        headers.append("Content-Type: multipart/alternative; boundary=\"\(boundary)\"")

        let plainPart = part(contentType: "text/plain; charset=utf-8",
                             body: message.plainText, boundary: boundary)
        let htmlPart = part(contentType: "text/html; charset=utf-8",
                            body: message.html, boundary: boundary)

        return headers.joined(separator: "\r\n")
            + "\r\n\r\n"
            + plainPart + "\r\n"
            + htmlPart + "\r\n"
            + "--\(boundary)--\r\n"
    }

    private static func part(contentType: String, body: String, boundary: String) -> String {
        "--\(boundary)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Transfer-Encoding: quoted-printable\r\n"
            + "\r\n"
            + QuotedPrintable.encode(body)
    }

    /// Encodes a header value as an RFC 2047 base64 encoded-word when it contains
    /// non-ASCII; returns it unchanged when it's plain ASCII.
    static func encodeHeaderValue(_ value: String) -> String {
        if value.allSatisfy({ $0.isASCII }) { return value }
        let base64 = Data(value.utf8).base64EncodedString()
        return "=?UTF-8?B?\(base64)?="
    }
}
