import Testing
import Foundation
@testable import HighRise

/// The Review header summary is the first thing users read on the stage, so its
/// counts and domain-spread math (only ready recipients count toward domains)
/// and its wording/pluralization are pinned.
struct ReviewSummaryTests {

    private func preview(email: String, unresolved: [String] = [],
                         validEmail: Bool = true, duplicate: Bool = false,
                         suppressed: Bool = false) -> MergePreview {
        MergePreview(id: UUID(),
                     contact: Contact(fields: ["Full Name": "Test Person"], email: email),
                     resolvedSubject: "Hi", resolvedBody: "Body",
                     unresolvedFields: unresolved, hasValidEmail: validEmail,
                     isDuplicate: duplicate, isSuppressed: suppressed)
    }

    @Test("Counts total, ready, and held recipients")
    func counts() {
        let s = ReviewSummary.of([
            preview(email: "a@acme.com"),
            preview(email: "b@acme.com"),
            preview(email: "bad", validEmail: false),
            preview(email: "c@acme.com", unresolved: ["First Name"]),
            preview(email: "d@acme.com", suppressed: true)
        ])
        #expect(s.total == 5)
        #expect(s.ready == 2)
        #expect(s.held == 3)
    }

    @Test("Domains are counted only across ready recipients, deduplicated")
    func domainsOnlyFromReady() {
        let s = ReviewSummary.of([
            preview(email: "a@acme.com"),          // ready · acme.com
            preview(email: "b@acme.com"),          // ready · acme.com (dup domain)
            preview(email: "c@globex.com"),        // ready · globex.com
            preview(email: "d@held.com", suppressed: true)   // held — domain ignored
        ])
        #expect(s.ready == 3)
        #expect(s.domains == 2)   // acme.com, globex.com — held.com excluded
    }

    @Test("An empty review has no counts and a friendly line")
    func empty() {
        let s = ReviewSummary.of([])
        #expect(s == ReviewSummary.Summary())
        #expect(ReviewSummary.line([]) == "No recipients yet")
    }

    @Test("The line reads recipients · domains · ready with pluralization")
    func linePluralized() {
        let many = (0..<41).map { preview(email: "u\($0)@acme.com") } + [preview(email: "v@globex.com")]
        // 42 total, all ready, 2 domains.
        #expect(ReviewSummary.line(many) == "42 recipients · 2 domains · 42 ready")

        // Singular recipient and singular domain.
        #expect(ReviewSummary.line([preview(email: "solo@acme.com")]) == "1 recipient · 1 domain · 1 ready")
    }

    @Test("The domain clause is dropped when nothing is ready")
    func noReadyNoDomainClause() {
        let s = [preview(email: "bad", validEmail: false),
                 preview(email: "worse", validEmail: false)]
        #expect(ReviewSummary.of(s).domains == 0)
        #expect(ReviewSummary.line(s) == "2 recipients · 0 ready")
    }
}
