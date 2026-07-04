import Testing
import Foundation
@testable import HighRise

struct QuotedPrintableTests {
    @Test("Plain ASCII passes through unchanged")
    func asciiPassthrough() {
        #expect(QuotedPrintable.encode("Hello, world!") == "Hello, world!")
    }

    @Test("An equals sign is encoded")
    func encodesEquals() {
        #expect(QuotedPrintable.encode("a=b") == "a=3Db")
    }

    @Test("Non-ASCII bytes become uppercase =XX of their UTF-8")
    func encodesUTF8() {
        // 'é' is U+00E9 → UTF-8 C3 A9.
        #expect(QuotedPrintable.encode("café") == "caf=C3=A9")
        // '€' is U+20AC → UTF-8 E2 82 AC.
        #expect(QuotedPrintable.encode("€") == "=E2=82=AC")
    }

    @Test("Trailing whitespace is encoded so it survives transport")
    func encodesTrailingSpace() {
        #expect(QuotedPrintable.encode("trailing ") == "trailing=20")
        #expect(QuotedPrintable.encode("tab\t") == "tab=09")
        // Interior spaces stay literal.
        #expect(QuotedPrintable.encode("a b c") == "a b c")
    }

    @Test("Hard newlines become CRLF; interior spaces on non-final lines stay literal")
    func newlines() {
        #expect(QuotedPrintable.encode("line1\nline2") == "line1\r\nline2")
    }

    @Test("Long lines are soft-wrapped at 76 columns with =CRLF")
    func softWrap() {
        let long = String(repeating: "a", count: 100)
        let encoded = QuotedPrintable.encode(long)
        #expect(encoded.contains("=\r\n"))
        for line in encoded.components(separatedBy: "\r\n") {
            #expect(line.count <= 76)
        }
    }
}

struct MIMEMessageComposerTests {
    private func message(subject: String = "Hi", html: String = "<p>Hi</p>",
                         from: String? = nil) -> MIMEMessageComposer.Message {
        MIMEMessageComposer.Message(from: from, to: "ada@x.com", subject: subject,
                                    html: html, plainText: "Hi")
    }

    @Test("The message has both alternative parts and Apple's draft header")
    func structure() {
        let eml = MIMEMessageComposer.eml(message(), boundary: "BND", date: "Sat, 04 Jul 2026 10:00:00 +0000")
        #expect(eml.contains("MIME-Version: 1.0"))
        #expect(eml.contains("X-Uniform-Type-Identifier: com.apple.mail-draft"))
        #expect(eml.contains("Content-Type: multipart/alternative; boundary=\"BND\""))
        #expect(eml.contains("Content-Type: text/plain; charset=utf-8"))
        #expect(eml.contains("Content-Type: text/html; charset=utf-8"))
        #expect(eml.contains("--BND--"))          // closing boundary
        #expect(eml.contains("To: ada@x.com"))
        #expect(eml.contains("Date: Sat, 04 Jul 2026 10:00:00 +0000"))
    }

    @Test("From is included only when provided")
    func optionalFrom() {
        #expect(!MIMEMessageComposer.eml(message(), boundary: "B").contains("From:"))
        #expect(MIMEMessageComposer.eml(message(from: "me@x.com"), boundary: "B").contains("From: me@x.com"))
    }

    @Test("A non-ASCII subject is RFC 2047 encoded; ASCII is left alone")
    func subjectEncoding() {
        #expect(MIMEMessageComposer.encodeHeaderValue("Hello") == "Hello")
        let encoded = MIMEMessageComposer.encodeHeaderValue("Café ☕")
        #expect(encoded.hasPrefix("=?UTF-8?B?"))
        #expect(encoded.hasSuffix("?="))
    }

    @Test("The HTML body is quoted-printable encoded in the html part")
    func htmlPartEncoded() {
        let eml = MIMEMessageComposer.eml(message(html: "<p>Café</p>"), boundary: "B")
        #expect(eml.contains("Caf=C3=A9"))
    }
}

struct HTMLTextExtractorTests {
    @Test("Tags are stripped and blocks become line breaks")
    func stripsTags() {
        let text = HTMLTextExtractor.plainText(fromHTML: "<p>Hi <b>Ada</b></p><p>Bye</p>")
        #expect(text == "Hi Ada\n\nBye")
    }

    @Test("Entities are decoded")
    func decodesEntities() {
        #expect(HTMLTextExtractor.plainText(fromHTML: "A &amp; B &lt;x&gt;") == "A & B <x>")
    }

    @Test("br becomes a single newline")
    func lineBreaks() {
        #expect(HTMLTextExtractor.plainText(fromHTML: "a<br>b") == "a\nb")
    }
}
