import Testing
@testable import HighRise

/// The confirmation detail is the last line a user reads before a run commits,
/// so its account fallback and attachment wording are pinned.
struct SendConfirmationTests {

    @Test("A blank account falls back to the default-account phrasing")
    func defaultAccount() {
        #expect(SendConfirmation.detail(account: "", attachments: 0)
                == "From your default account · no attachments")
        #expect(SendConfirmation.detail(account: "   ", attachments: 1)
                == "From your default account · 1 attachment on every message")
    }

    @Test("A named account is shown verbatim")
    func namedAccount() {
        #expect(SendConfirmation.detail(account: "jordan@work.com", attachments: 0)
                == "From jordan@work.com · no attachments")
        #expect(SendConfirmation.detail(account: "Jordan <j@w.com>", attachments: 2)
                == "From Jordan <j@w.com> · 2 attachments on every message")
    }

    @Test("Attachment count pluralizes")
    func attachmentPluralization() {
        #expect(SendConfirmation.detail(account: "a@b.com", attachments: 1).hasSuffix("1 attachment on every message"))
        #expect(SendConfirmation.detail(account: "a@b.com", attachments: 3).hasSuffix("3 attachments on every message"))
    }
}
