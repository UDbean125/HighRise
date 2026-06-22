import Testing
import Foundation
@testable import HighRise

/// AppleScript string escaping is the security boundary of this app: recipient
/// names, subjects, and bodies become part of an executable script. These tests
/// pin the escaping so a stray quote can't break the script and crafted text
/// can't escape its string literal to inject commands.
struct AppleScriptBuilderTests {

    @Test("Plain text becomes a quoted literal")
    func plainLiteral() {
        #expect(AppleScriptBuilder.stringLiteral("Hello") == "\"Hello\"")
    }

    @Test("Empty string is a valid empty literal")
    func emptyLiteral() {
        #expect(AppleScriptBuilder.stringLiteral("") == "\"\"")
    }

    @Test("Double quotes are escaped")
    func escapesQuotes() {
        #expect(AppleScriptBuilder.stringLiteral("say \"hi\"") == "\"say \\\"hi\\\"\"")
    }

    @Test("Backslashes are escaped")
    func escapesBackslash() {
        #expect(AppleScriptBuilder.stringLiteral("a\\b") == "\"a\\\\b\"")
    }

    @Test("Newlines are split and joined with linefeed, never left raw")
    func newlinesUseLinefeed() {
        let literal = AppleScriptBuilder.stringLiteral("Line 1\nLine 2")
        #expect(literal == "\"Line 1\" & linefeed & \"Line 2\"")
        #expect(!literal.contains("\n"))
    }

    @Test("CRLF and CR are normalized to linefeed joins")
    func normalizesLineEndings() {
        #expect(AppleScriptBuilder.stringLiteral("a\r\nb") == "\"a\" & linefeed & \"b\"")
        #expect(AppleScriptBuilder.stringLiteral("a\rb") == "\"a\" & linefeed & \"b\"")
    }

    @Test("An injection attempt stays inside the string literal")
    func neutralizesInjection() {
        // A subject crafted to try to terminate the string and run a command.
        let evil = "\" & (do shell script \"rm -rf ~\") & \""
        let literal = AppleScriptBuilder.stringLiteral(evil)

        // The result must be a single quoted literal...
        #expect(literal.hasPrefix("\""))
        #expect(literal.hasSuffix("\""))
        // ...and every embedded quote must be backslash-escaped, so the payload
        // is inert text. Strip the outer quotes and all escaped quotes (\"):
        // no bare quote may remain to break out of the literal.
        let inner = String(literal.dropFirst().dropLast())
        let withoutEscapedQuotes = inner.replacingOccurrences(of: "\\\"", with: "")
        #expect(!withoutEscapedQuotes.contains("\""))
        // Each of the four quotes in the payload is escaped.
        #expect(literal.components(separatedBy: "\\\"").count - 1 == 4)
    }

    @Test("Apple Mail uses save for drafts and send for live sends")
    func appleMailActions() {
        let message = ComposedMessage(recipientEmail: "a@b.com", recipientName: "A",
                                      subject: "S", body: "B", isHTML: false)
        let draft = AppleScriptBuilder.script(for: message, client: .appleMail, mode: .draft)
        #expect(draft.contains("tell application \"Mail\""))
        #expect(draft.contains("save newMessage"))
        #expect(!draft.contains("send newMessage"))

        let send = AppleScriptBuilder.script(for: message, client: .appleMail, mode: .send)
        #expect(send.contains("send newMessage"))
    }

    @Test("Outlook selects HTML vs plain-text body property by format")
    func outlookBodyProperty() {
        let html = ComposedMessage(recipientEmail: "a@b.com", recipientName: "A",
                                   subject: "S", body: "<p>B</p>", isHTML: true)
        let htmlScript = AppleScriptBuilder.script(for: html, client: .outlook, mode: .draft)
        #expect(htmlScript.contains("content:"))
        #expect(!htmlScript.contains("plain text content:"))

        let plain = ComposedMessage(recipientEmail: "a@b.com", recipientName: "A",
                                    subject: "S", body: "B", isHTML: false)
        let plainScript = AppleScriptBuilder.script(for: plain, client: .outlook, mode: .draft)
        #expect(plainScript.contains("plain text content:"))
    }
}
