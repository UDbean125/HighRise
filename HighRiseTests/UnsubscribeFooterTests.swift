import Testing
@testable import HighRise

/// The unsubscribe footer is the privacy-honest opt-out path, so its mailto
/// encoding (which must survive an email client) and markup are pinned.
struct UnsubscribeFooterTests {

    @Test("mailto encodes the subject and body, leaving the address plain")
    func mailtoEncoding() {
        let url = UnsubscribeFooter.mailtoURL(to: "me@x.com", subject: "Unsubscribe",
                                              body: "Please remove ada@x.com from your list.")
        #expect(url.hasPrefix("mailto:me@x.com?"))
        #expect(url.contains("subject=Unsubscribe"))
        // Spaces and the address in the body are percent-encoded.
        #expect(url.contains("Please%20remove%20ada%40x%2Ecom"))
        #expect(!url.contains(" "))
    }

    @Test("The plain-text footer includes a separator and the mailto link")
    func plainFooter() {
        let footer = UnsubscribeFooter.plainText(replyTo: "me@x.com",
                                                 recipientEmail: "ada@x.com", note: "")
        #expect(footer.contains("—"))
        #expect(footer.contains("mailto:me@x.com"))
        #expect(footer.hasPrefix("\n\n"))            // separated from the body
    }

    @Test("A custom note replaces the default lead-in")
    func customNote() {
        let footer = UnsubscribeFooter.plainText(replyTo: "me@x.com",
                                                 recipientEmail: "ada@x.com",
                                                 note: "Rather not hear from us?")
        #expect(footer.contains("Rather not hear from us?"))
        #expect(!footer.contains("Don't want these emails?"))
    }

    @Test("The HTML footer escapes the mailto ampersand in the href")
    func htmlFooterEscaped() {
        let footer = UnsubscribeFooter.html(replyTo: "me@x.com",
                                            recipientEmail: "ada@x.com", note: "")
        #expect(footer.contains("<a href="))
        #expect(footer.contains("&amp;body="))       // & escaped for HTML attribute
        #expect(footer.contains("Unsubscribe</a>"))
    }
}
