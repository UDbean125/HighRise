import Testing
import Foundation
@testable import HighRise

/// The pre-send report is an audit users may keep or share, so its counts and
/// categorization must be exactly right — and it must never claim anything was
/// sent.
struct PreSendReportTests {

    private func preview(email: String, unresolved: [String] = [],
                         validEmail: Bool = true, duplicate: Bool = false,
                         suppressed: Bool = false, missingAttachment: Bool = false,
                         name: String = "Test Person") -> MergePreview {
        MergePreview(id: UUID(),
                     contact: Contact(fields: ["Full Name": name], email: email),
                     resolvedSubject: "Hi", resolvedBody: "Body",
                     unresolvedFields: unresolved, hasValidEmail: validEmail,
                     isDuplicate: duplicate, isSuppressed: suppressed,
                     attachmentPaths: missingAttachment ? ["/nope/a.pdf"] : [],
                     missingAttachmentPaths: missingAttachment ? ["/nope/a.pdf"] : [])
    }

    private func input(previews: [MergePreview],
                       template: EmailTemplate = EmailTemplate(subject: "Quick note for {{Company}}",
                                                               body: "Hi {{First Name|there}}"),
                       throttle: ThrottlePolicy = ThrottlePolicy(baseDelay: 1, jitter: 1),
                       attachments: [String] = []) -> PreSendReport.Input {
        PreSendReport.Input(generatedAtLabel: "Jul 6, 2026 at 2:00 PM",
                            client: .appleMail, senderIdentity: "jordan@work.com",
                            mode: .draft, provider: .gmailPersonal,
                            template: template, previews: previews,
                            throttle: throttle, attachmentNames: attachments)
    }

    @Test("Categorizes each held-back recipient by priority")
    func categorization() {
        #expect(PreSendReport.category(of: preview(email: "a@b.com")) == nil)              // sendable
        #expect(PreSendReport.category(of: preview(email: "bad", validEmail: false)) == .invalidEmail)
        #expect(PreSendReport.category(of: preview(email: "a@b.com", suppressed: true)) == .suppressed)
        #expect(PreSendReport.category(of: preview(email: "a@b.com", unresolved: ["First Name"])) == .missingData)
        #expect(PreSendReport.category(of: preview(email: "a@b.com", missingAttachment: true)) == .missingAttachment)
        #expect(PreSendReport.category(of: preview(email: "a@b.com", duplicate: true)) == .duplicate)
    }

    @Test("Report counts ready and held-back recipients correctly")
    func counts() {
        let previews = [
            preview(email: "ok1@b.com"),
            preview(email: "ok2@b.com"),
            preview(email: "bad", validEmail: false),
            preview(email: "dup@b.com", duplicate: true),
            preview(email: "x@b.com", suppressed: true)
        ]
        let text = PreSendReport.plainText(input(previews: previews))
        #expect(text.contains("Ready to send: 2"))
        #expect(text.contains("Held back: 3"))
        #expect(text.contains("Invalid or missing email: 1"))
        #expect(text.contains("Duplicate address: 1"))
        #expect(text.contains("On do-not-contact list: 1"))
    }

    @Test("Report always states nothing was sent")
    func neverClaimsSent() {
        let text = PreSendReport.plainText(input(previews: [preview(email: "a@b.com")]))
        #expect(text.contains("Nothing has been sent."))
        #expect(text.contains("1 message ready"))
    }

    @Test("Sending section reflects client, account, and mode")
    func sendingSection() {
        let text = PreSendReport.plainText(input(previews: [preview(email: "a@b.com")]))
        #expect(text.contains("Apple Mail — jordan@work.com"))
        #expect(text.contains("Save as drafts"))
        #expect(text.contains("Gmail (personal)"))
    }

    @Test("Held-back recipients are listed with their reasons")
    func heldBackList() {
        let text = PreSendReport.plainText(input(previews: [
            preview(email: "jane@x.com", unresolved: ["First Name"], name: "Jane Doe")
        ]))
        #expect(text.contains("HELD-BACK RECIPIENTS"))
        #expect(text.contains("Jane Doe <jane@x.com>"))
        #expect(text.contains("Missing data for: First Name"))
    }

    @Test("Attachments section lists files or says None")
    func attachments() {
        let none = PreSendReport.plainText(input(previews: [preview(email: "a@b.com")]))
        #expect(none.contains("ATTACHMENTS\n  None."))
        let some = PreSendReport.plainText(input(previews: [preview(email: "a@b.com")],
                                                 attachments: ["brochure.pdf", "terms.pdf"]))
        #expect(some.contains("2: brochure.pdf, terms.pdf"))
    }

    @Test("Pacing section shows the estimated duration")
    func pacing() {
        // 11 ready, base 2s no jitter → 10 gaps * 2 = 20s.
        let previews = (0..<11).map { preview(email: "r\($0)@b.com") }
        let text = PreSendReport.plainText(input(previews: previews,
                                                 throttle: ThrottlePolicy(baseDelay: 2)))
        #expect(text.contains("Estimated send time: ~20s"))
    }
}
