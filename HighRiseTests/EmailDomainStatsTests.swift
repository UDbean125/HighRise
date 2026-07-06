import Testing
import Foundation
@testable import HighRise

/// The domain breakdown informs sending decisions, so its parsing, tallying,
/// top-N cut, and "other" bucket are pinned.
struct EmailDomainStatsTests {

    private func contacts(_ emails: [String]) -> [Contact] {
        emails.map { Contact(fields: [:], email: $0) }
    }

    @Test("Domain parsing lowercases, trims, and rejects addresses with no @")
    func domainParsing() {
        #expect(EmailDomainStats.domain(of: " Ada@Gmail.com ") == "gmail.com")
        #expect(EmailDomainStats.domain(of: "a@b@example.org") == "example.org")  // last @ wins
        #expect(EmailDomainStats.domain(of: "no-at-sign") == nil)
        #expect(EmailDomainStats.domain(of: "trailing@") == nil)
        #expect(EmailDomainStats.domain(of: "") == nil)
    }

    @Test("Tallies by domain, count-descending with a stable tie-break")
    func tally() {
        let stats = EmailDomainStats.of(contacts([
            "a@gmail.com", "b@gmail.com", "c@gmail.com",
            "d@outlook.com", "e@outlook.com",
            "f@yahoo.com",
            "g-has-no-at-sign"     // no @ → excluded
        ]))
        #expect(stats.total == 6)
        #expect(stats.entries.first == EmailDomainStats.Entry(domain: "gmail.com", count: 3))
        #expect(stats.entries[1] == EmailDomainStats.Entry(domain: "outlook.com", count: 2))
        #expect(stats.entries.contains(EmailDomainStats.Entry(domain: "yahoo.com", count: 1)))
    }

    @Test("Beyond topN, the tail collapses into a single 'other' entry")
    func otherBucket() {
        let stats = EmailDomainStats.of(contacts([
            "a@one.com", "a@one.com",   // one.com: 2
            "b@two.com",                // two.com: 1
            "c@three.com",              // three.com: 1
            "d@four.com",               // four.com: 1
            "e@five.com",               // five.com: 1
            "f@six.com",                // six.com: 1  -> beyond top 5 -> other
            "g@seven.com"               // seven.com: 1 -> other
        ]), topN: 5)
        #expect(stats.total == 8)
        #expect(stats.entries.count == 6)                       // top 5 + other
        #expect(stats.entries.last?.domain == "other")
        #expect(stats.entries.last?.count == 2)                 // the two tail domains
    }

    @Test("No 'other' entry when everything fits under topN")
    func noOtherWhenSmall() {
        let stats = EmailDomainStats.of(contacts(["a@x.com", "b@y.com"]))
        #expect(stats.entries.count == 2)
        #expect(!stats.entries.contains { $0.domain == "other" })
    }
}
