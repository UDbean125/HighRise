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

    @Test("Apple Mail emits cc and bcc recipients, escaped, only when present")
    func appleMailCCBCC() {
        let plain = ComposedMessage(recipientEmail: "a@b.com", recipientName: "A",
                                    subject: "S", body: "B", isHTML: false)
        let noExtras = AppleScriptBuilder.script(for: plain, client: .appleMail, mode: .draft)
        #expect(!noExtras.contains("cc recipient"))
        #expect(!noExtras.contains("bcc recipient"))

        let withExtras = ComposedMessage(recipientEmail: "a@b.com", recipientName: "A",
                                         subject: "S", body: "B", isHTML: false,
                                         cc: ["boss@acme.com"], bcc: ["me@acme.com"])
        let script = AppleScriptBuilder.script(for: withExtras, client: .appleMail, mode: .draft)
        #expect(script.contains("make new cc recipient at end of cc recipients with properties {address:\"boss@acme.com\"}"))
        #expect(script.contains("make new bcc recipient at end of bcc recipients with properties {address:\"me@acme.com\"}"))
    }

    @Test("Outlook emits to, cc and bcc recipients")
    func outlookCCBCC() {
        let msg = ComposedMessage(recipientEmail: "a@b.com", recipientName: "A",
                                  subject: "S", body: "B", isHTML: false,
                                  cc: ["boss@acme.com"], bcc: ["me@acme.com"])
        let script = AppleScriptBuilder.script(for: msg, client: .outlook, mode: .draft)
        #expect(script.contains("make new to recipient at newMessage with properties {email address:{address:\"a@b.com\"}}"))
        #expect(script.contains("make new cc recipient at newMessage with properties {email address:{address:\"boss@acme.com\"}}"))
        #expect(script.contains("make new bcc recipient at newMessage with properties {email address:{address:\"me@acme.com\"}}"))
    }

    @Test("A crafted cc address stays inside its string literal")
    func ccAddressEscaped() {
        let evil = ComposedMessage(recipientEmail: "a@b.com", recipientName: "A",
                                   subject: "S", body: "B", isHTML: false,
                                   cc: ["\"} & (do shell script \"boom\") & {\""])
        let script = AppleScriptBuilder.script(for: evil, client: .appleMail, mode: .draft)
        // The payload's quotes must be backslash-escaped, never bare.
        #expect(script.contains("\\\""))
        #expect(!script.contains("do shell script \"boom\""))
    }

    @Test("Apple Mail attaches each file via an escaped POSIX path")
    func appleMailAttachments() {
        let msg = ComposedMessage(recipientEmail: "a@b.com", recipientName: "A",
                                  subject: "S", body: "B", isHTML: false,
                                  attachmentPaths: ["/Users/me/Q3 Report.pdf"])
        let script = AppleScriptBuilder.script(for: msg, client: .appleMail, mode: .draft)
        #expect(script.contains("make new attachment with properties {file name:(POSIX file \"/Users/me/Q3 Report.pdf\")} at after the last paragraph"))
    }

    @Test("Outlook attaches each file via an escaped POSIX path")
    func outlookAttachments() {
        let msg = ComposedMessage(recipientEmail: "a@b.com", recipientName: "A",
                                  subject: "S", body: "B", isHTML: false,
                                  attachmentPaths: ["/Users/me/invoice.pdf"])
        let script = AppleScriptBuilder.script(for: msg, client: .outlook, mode: .draft)
        #expect(script.contains("make new attachment at newMessage with properties {file:(POSIX file \"/Users/me/invoice.pdf\")}"))
    }

    @Test("No attachment verbs are emitted when there are none")
    func noAttachmentsNoVerb() {
        let msg = ComposedMessage(recipientEmail: "a@b.com", recipientName: "A",
                                  subject: "S", body: "B", isHTML: false)
        let mail = AppleScriptBuilder.script(for: msg, client: .appleMail, mode: .draft)
        let outlook = AppleScriptBuilder.script(for: msg, client: .outlook, mode: .draft)
        #expect(!mail.contains("make new attachment"))
        #expect(!outlook.contains("make new attachment"))
    }

    @Test("A crafted attachment path stays inside its POSIX file literal")
    func attachmentPathEscaped() {
        let msg = ComposedMessage(recipientEmail: "a@b.com", recipientName: "A",
                                  subject: "S", body: "B", isHTML: false,
                                  attachmentPaths: ["/tmp/\" & (do shell script \"boom\") & \""])
        let script = AppleScriptBuilder.script(for: msg, client: .appleMail, mode: .draft)
        #expect(!script.contains("do shell script \"boom\""))
        #expect(script.contains("\\\""))
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
