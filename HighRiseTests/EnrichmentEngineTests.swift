import Testing
import Foundation
@testable import HighRise

/// The enrichment engine's safety contract: blanks can fill, invalid emails
/// can be corrected, valid emails and populated cells are never touched, and
/// stale fills refuse to apply.
struct EnrichmentEngineTests {

    /// A canned provider: returns the same finding for every askable query.
    private struct StubProvider: EnrichmentProvider {
        var displayName: String { "Stub" }
        let finding: EnrichmentFinding?
        func enrich(_ query: EnrichmentQuery) async throws -> EnrichmentFinding? { finding }
    }

    private func table(_ headers: [String], _ rows: [[String]]) -> RecipientTable {
        RecipientTable(headers: headers, rows: rows)
    }

    @Test("Rows with invalid emails or blank fillable cells are selected")
    func rowSelection() {
        let t = table(["Company", "Email"], [
            ["Acme", "good@acme.com"],       // complete — not selected
            ["Turner", "not-an-email"],      // invalid email
            ["", "sam@stark.com"],           // blank company
            ["Kiewit", ""]                   // missing email
        ])
        let emailIndex = EnrichmentEngine.emailColumnIndex(in: t, named: "Email")
        #expect(EnrichmentEngine.rowsNeedingHelp(t, emailIndex: emailIndex) == [1, 2, 3])
    }

    @Test("A finding fills the blank email and other blank cells, never populated ones")
    func fillsBlanksOnly() async throws {
        let t = table(["Company", "Director Title", "Email"], [
            ["Kimley-Horn", "Director of Engineering", ""]
        ])
        let finding = EnrichmentFinding(firstName: "Jordan", lastName: "Avery",
                                        email: "jordan.avery@kimley-horn.com",
                                        title: "VP Something Else",
                                        company: "Kimley-Horn and Associates")
        let result = try await EnrichmentEngine.run(table: t, emailColumn: "Email",
                                                    provider: StubProvider(finding: finding))
        #expect(result.queried == 1)
        // Email fills; Company and Director Title are populated so they are
        // left alone (no first/last name columns exist to fill).
        #expect(result.fills.count == 1)
        let fill = try #require(result.fills.first)
        #expect(fill.column == "Email")
        #expect(fill.before == "")
        #expect(fill.after == "jordan.avery@kimley-horn.com")
        #expect(fill.rowLabel == "Kimley-Horn")
    }

    @Test("An invalid email is offered as a correction; a valid one is untouched")
    func correctsInvalidOnly() async throws {
        let t = table(["Company", "Email"], [
            ["Acme", "not-an-email"],
            ["Acme", "kept@acme.com"]
        ])
        let finding = EnrichmentFinding(email: "fixed@acme.com")
        let result = try await EnrichmentEngine.run(table: t, emailColumn: "Email",
                                                    provider: StubProvider(finding: finding))
        #expect(result.fills.count == 1)
        let fill = try #require(result.fills.first)
        #expect(fill.row == 0)
        #expect(fill.isCorrection)
        #expect(fill.before == "not-an-email")
        #expect(fill.after == "fixed@acme.com")
    }

    @Test("Blank name cells fill from the finding")
    func fillsNames() async throws {
        let t = table(["First Name", "Last Name", "Company", "Email"], [
            ["", "", "Parsons", "invalid"]
        ])
        let finding = EnrichmentFinding(firstName: "Riley", lastName: "Chen",
                                        email: "riley.chen@parsons.com")
        let result = try await EnrichmentEngine.run(table: t, emailColumn: "Email",
                                                    provider: StubProvider(finding: finding))
        let columns = Set(result.fills.map(\.column))
        #expect(columns == ["First Name", "Last Name", "Email"])
    }

    @Test("A provider with nothing counts as no-match, not an error")
    func noMatch() async throws {
        let t = table(["Company", "Email"], [["Acme", ""]])
        let result = try await EnrichmentEngine.run(table: t, emailColumn: "Email",
                                                    provider: StubProvider(finding: nil))
        #expect(result.queried == 1)
        #expect(result.noMatch == 1)
        #expect(result.fills.isEmpty)
    }

    @Test("Rows with nothing to ask about are skipped, not sent")
    func skipsUnaskable() async throws {
        let t = table(["Notes", "Email"], [["hello", ""]])
        let result = try await EnrichmentEngine.run(table: t, emailColumn: "Email",
                                                    provider: StubProvider(finding: EnrichmentFinding()))
        #expect(result.queried == 0)
        #expect(result.skippedUnaskable == 1)
    }

    @Test("Apply writes accepted fills and refuses stale ones")
    func applyGuardsStaleness() {
        let t = table(["Company", "Email"], [["Acme", "bad"]])
        let fresh = EnrichmentEngine.CellFill(row: 0, column: "Email",
                                              before: "bad", after: "good@acme.com",
                                              rowLabel: "Acme")
        let stale = EnrichmentEngine.CellFill(row: 0, column: "Email",
                                              before: "something-else", after: "wrong@acme.com",
                                              rowLabel: "Acme")
        let (applied, count) = EnrichmentEngine.apply([fresh], to: t)
        #expect(count == 1)
        #expect(applied.rows[0][1] == "good@acme.com")

        let (unchanged, staleCount) = EnrichmentEngine.apply([stale], to: t)
        #expect(staleCount == 0)
        #expect(unchanged == t)
    }

    @Test("Queries carry the row's identity fields, including a website-derived domain")
    func queryBuilding() {
        let t = table(["Company", "Director Title", "Website", "Email"], [
            ["Gensler", "Design Director", "https://www.gensler.com/about", "invalid"]
        ])
        let emailIndex = EnrichmentEngine.emailColumnIndex(in: t, named: "Email")
        let q = EnrichmentEngine.query(for: 0, in: t, emailIndex: emailIndex)
        #expect(q.company == "Gensler")
        #expect(q.title == "Design Director")
        #expect(q.domain == "gensler.com")
        #expect(q.email == nil)  // invalid values aren't sent as identity
        #expect(!q.identifiesPerson)
        #expect(q.isAskable)
    }

    @Test("Apollo response decoding surfaces people and filters locked emails")
    func apolloDecoding() throws {
        let json = Data("""
        {"person": {"first_name": "Jordan", "last_name": "Avery", "name": "Jordan Avery",
                    "email": "email_not_unlocked@domain.com", "title": "Director",
                    "organization": {"name": "Kimley-Horn", "primary_domain": "kimley-horn.com",
                                     "website_url": "https://www.kimley-horn.com"}}}
        """.utf8)
        let decoded = try JSONDecoder().decode(ApolloEnrichmentProvider.MatchResponse.self, from: json)
        let person = try #require(decoded.person)
        #expect(person.usableEmail == nil)  // locked placeholder is not an address
        #expect(person.finding.email == nil)
        #expect(person.finding.company == "Kimley-Horn")
        #expect(person.finding.website == "https://www.kimley-horn.com")
        #expect(person.domain == "kimley-horn.com")

        let unlocked = Data("""
        {"people": [{"first_name": "Riley", "last_name": "Chen",
                     "email": "riley.chen@parsons.com", "organization": {"name": "Parsons"}}]}
        """.utf8)
        let search = try JSONDecoder().decode(ApolloEnrichmentProvider.SearchResponse.self, from: unlocked)
        #expect(search.people?.first?.usableEmail == "riley.chen@parsons.com")
    }
}
