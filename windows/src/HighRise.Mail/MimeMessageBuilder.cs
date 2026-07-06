using System.Text;

namespace HighRise.Mail;

/// <summary>
/// Builds an RFC 822 MIME message and its base64url encoding for the Gmail API
/// (which sends a raw message). String hygiene is the whole point here: a
/// recipient or subject containing a CR/LF could otherwise inject extra headers
/// (a Bcc, say), so header values are stripped of line breaks before assembly.
/// This is the Windows analog of the macOS app's AppleScript-escaping boundary,
/// and it is unit-tested for exactly that reason.
/// </summary>
public static class MimeMessageBuilder
{
    /// <summary>The full MIME message as text (CRLF line endings).</summary>
    public static string BuildMime(ComposedMessage message)
    {
        var to = SanitizeHeader(message.RecipientEmail);
        var subject = EncodeSubject(SanitizeHeader(message.Subject));
        var contentType = message.IsHtml ? "text/html" : "text/plain";

        var body = WrapBase64(Convert.ToBase64String(Encoding.UTF8.GetBytes(message.Body)));

        var sb = new StringBuilder();
        sb.Append("MIME-Version: 1.0\r\n");
        sb.Append($"To: {to}\r\n");
        sb.Append($"Subject: {subject}\r\n");
        sb.Append($"Content-Type: {contentType}; charset=\"utf-8\"\r\n");
        sb.Append("Content-Transfer-Encoding: base64\r\n");
        sb.Append("\r\n");
        sb.Append(body);
        return sb.ToString();
    }

    /// <summary>The MIME message encoded as base64url (no padding) for the Gmail API's <c>raw</c> field.</summary>
    public static string BuildRawBase64Url(ComposedMessage message) =>
        Base64Url(Encoding.UTF8.GetBytes(BuildMime(message)));

    /// <summary>Removes CR/LF so a value can never start a new header line (injection guard).</summary>
    internal static string SanitizeHeader(string value) =>
        value.Replace("\r", string.Empty).Replace("\n", string.Empty);

    /// <summary>Leaves pure-ASCII subjects as-is; RFC 2047 base64-encodes anything else.</summary>
    internal static string EncodeSubject(string subject)
    {
        var isAscii = true;
        foreach (var ch in subject)
        {
            if (ch > 127) { isAscii = false; break; }
        }
        if (isAscii)
            return subject;
        return "=?utf-8?B?" + Convert.ToBase64String(Encoding.UTF8.GetBytes(subject)) + "?=";
    }

    internal static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes)
            .Replace('+', '-')
            .Replace('/', '_')
            .TrimEnd('=');

    private static string WrapBase64(string base64)
    {
        var sb = new StringBuilder(base64.Length + base64.Length / 76 * 2);
        for (var i = 0; i < base64.Length; i += 76)
        {
            sb.Append(base64.AsSpan(i, Math.Min(76, base64.Length - i)));
            sb.Append("\r\n");
        }
        return sb.ToString();
    }
}
