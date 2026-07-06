import Testing
import Foundation
@testable import HighRise

/// The list-health readout drives real user decisions ("is my data good
/// enough to send?"), so its arithmetic is pinned: fill rates, invalid email
/// and duplicate counts, and the least-filled-first ordering.
struct ListHealthTests {

    private func contact(_ fields: [String: String], email: String) -> Contact {
        Contact(fields: fields, email: email)
    }

    @Test("Counts valid, invalid, and duplicate addresses")
    func emailCounts() {
        let health = ListHealth.assess(contacts: [
            contact(["Name": "Ada"], email: "ada@example.com"),
            contact(["Name": "Bob"], email: "not-an-email"),
            contact(["Name": "Cat"], email: ""),
            contact(["Name": "Ada again"], email: "ADA@example.com ")   // repeat, case/space-insensitive
        ], headers: ["Name"])

        #expect(health.total == 4)
        #expect(health.validEmails == 2)      // ada + the repeat are both valid
        #expect(health.invalidEmails == 2)    // bad format + blank
        #expect(health.duplicates == 1)       // the repeat of ada
    }

    @Test("Computes per-column fill rates, least-filled first")
    func fillRates() throws {
        let health = ListHealth.assess(contacts: [
            contact(["Name": "Ada", "Company": "Acme", "Phone": ""], email: "a@b.com"),
            contact(["Name": "Bob", "Company": "", "Phone": "  "], email: "b@b.com"),
            contact(["Name": "Cat", "Company": "Cyberdyne"], email: "c@b.com"),
            contact(["Name": ""], email: "d@b.com")
        ], headers: ["Name", "Company", "Phone"])

        #expect(health.columnFill.map(\.column) == ["Phone", "Company", "Name"])

        let byName = Dictionary(uniqueKeysWithValues: health.columnFill.map { ($0.column, $0) })
        #expect(byName["Name"]?.filled == 3)          // blank name doesn't count
        #expect(byName["Company"]?.filled == 2)       // empty string doesn't count
        #expect(byName["Phone"]?.filled == 0)         // whitespace doesn't count
        #expect(byName["Name"]?.rate == 0.75)
    }

    @Test("Empty list yields zeros, not division crashes")
    func emptyList() {
        let health = ListHealth.assess(contacts: [], headers: ["Name"])
        #expect(health.total == 0)
        #expect(health.validEmails == 0)
        #expect(health.duplicates == 0)
        #expect(health.columnFill.first?.rate == 0)
        #expect(!health.hasIssues)
    }

    @Test("hasIssues flags invalid emails or duplicates")
    func issueFlag() {
        let clean = ListHealth.assess(contacts: [contact([:], email: "a@b.com")], headers: [])
        #expect(!clean.hasIssues)
        let dirty = ListHealth.assess(contacts: [contact([:], email: "nope")], headers: [])
        #expect(dirty.hasIssues)
    }
}
