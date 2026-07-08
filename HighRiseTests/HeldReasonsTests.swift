import Testing
import Foundation
@testable import HighRise

/// The held-reasons breakdown tells users why rows won't send, so its grouping,
/// priority ordering, and "each row counted once by its top reason" rule are
/// pinned — and it must agree with PreSendReport's categorization.
struct HeldReasonsTests {

    private func preview(email: String, unresolved: [String] = [],
                         validEmail: Bool = true, duplicate: Bool = false,
                         suppressed: Bool = false, missingAttachment: Bool = false) -> MergePreview {
        MergePreview(id: UUID(),
                     contact: Contact(fields: ["Full Name": "Test"], email: email),
                     resolvedSubject: "Hi", resolvedBody: "Body",
                     unresolvedFields: unresolved, hasValidEmail: validEmail,
                     isDuplicate: duplicate, isSuppressed: suppressed,
                     attachmentPaths: missingAttachment ? ["/nope/a.pdf"] : [],
                     missingAttachmentPaths: missingAttachment ? ["/nope/a.pdf"] : [])
    }

    @Test("Sendable recipients are never counted as held")
    func sendableExcluded() {
        let entries = HeldReasons.tally([preview(email: "a@b.com"), preview(email: "c@d.com")])
        #expect(entries.isEmpty)
        #expect(HeldReasons.total(entries) == 0)
    }

    @Test("Each reason is tallied and reported in priority order")
    func groupingAndOrder() {
        let previews = [
            preview(email: "dup@b.com", duplicate: true),
            preview(email: "bad", validEmail: false),
            preview(email: "x@b.com", suppressed: true),
            preview(email: "y@b.com", unresolved: ["First Name"]),
            preview(email: "z@b.com", unresolved: ["Company"])
        ]
        let entries = HeldReasons.tally(previews)
        // invalidEmail, suppressed, missingData(×2), duplicate — missingAttachment absent.
        #expect(entries.map(\.category) == [.invalidEmail, .suppressed, .missingData, .duplicate])
        #expect(entries.first { $0.category == .missingData }?.count == 2)
        #expect(HeldReasons.total(entries) == 5)
    }

    @Test("A row is counted once, by its highest-priority reason")
    func singleReasonPerRow() {
        // Both a bad address and missing data — invalidEmail wins (it's checked first).
        let entries = HeldReasons.tally([preview(email: "bad", unresolved: ["First Name"], validEmail: false)])
        #expect(entries.map(\.category) == [.invalidEmail])
        #expect(HeldReasons.total(entries) == 1)
    }

    @Test("Labels come straight from the shared PreSendReport categories")
    func labels() {
        let entries = HeldReasons.tally([preview(email: "x@b.com", suppressed: true)])
        #expect(entries.first?.label == "On do-not-contact list")
    }
}
