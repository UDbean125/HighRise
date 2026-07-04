import Foundation

/// Quoted-printable encoding (RFC 2045 §6.7) for MIME message bodies.
///
/// Pure and byte-exact so the encoding — which, if wrong, corrupts every
/// accented character or trips a mail server's line-length limit — is pinned by
/// tests. Operates on UTF-8 bytes, soft-wraps at 76 columns, and encodes
/// trailing whitespace and `=`.
enum QuotedPrintable {

    /// Encodes `text` to quoted-printable with CRLF hard breaks and `=`-CRLF
    /// soft breaks. Input newlines (LF/CRLF/CR) are normalized to hard breaks.
    static func encode(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n").map(encodeLine)
        return lines.joined(separator: "\r\n")
    }

    /// Encodes one logical line (no embedded newlines), soft-wrapping at 76.
    private static func encodeLine(_ line: String) -> String {
        let bytes = Array(line.utf8)
        // Trailing spaces/tabs must be encoded so they survive transport.
        var lastNonWhitespace = bytes.count - 1
        while lastNonWhitespace >= 0, bytes[lastNonWhitespace] == 32 || bytes[lastNonWhitespace] == 9 {
            lastNonWhitespace -= 1
        }

        var result = ""
        var column = 0
        for (index, byte) in bytes.enumerated() {
            let token = encodeByte(byte, atLineEnd: index > lastNonWhitespace)
            // Soft-wrap before exceeding 76 columns, leaving room for the '='.
            if column + token.count > 75 {
                result += "=\r\n"
                column = 0
            }
            result += token
            column += token.count
        }
        return result
    }

    private static func encodeByte(_ byte: UInt8, atLineEnd: Bool) -> String {
        switch byte {
        case 9, 32:                       // tab / space
            return atLineEnd ? String(format: "=%02X", byte) : String(UnicodeScalar(byte))
        case 61:                          // '='
            return "=3D"
        case 33...126:                    // other printable ASCII
            return String(UnicodeScalar(byte))
        default:                          // everything else, incl. all UTF-8 multibyte
            return String(format: "=%02X", byte)
        }
    }
}
