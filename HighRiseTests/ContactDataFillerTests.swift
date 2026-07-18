import Testing
@testable import HighRise

/// The missing-data filler writes only into blank cells, only on request, and
/// derives everything from the list itself — these tests pin both the
/// inferences and those invariants.
struct ContactDataFillerTests {

    private func table(_ headers: [String], _ rows: [[String]]) -> RecipientTable {
        RecipientTable(headers: headers, rows: rows)
    }

    private func proposal(_ kind: ContactDataFiller.Proposal.Kind,
                          in proposals: [ContactDataFiller.Proposal]) -> ContactDataFiller.Proposal? {
        proposals.first { $0.kind == kind }
    }

    // MARK: First/last name from email

    @Test("Blank first names are offered from name-like email addresses")
    func firstNameFromEmail() throws {
        let t = table(["First Name", "Email"], [
            ["", "john.smith@acme.com"],
            ["Ada", "ada@lovelace.dev"],       // already filled — untouched
            ["", "info@acme.com"]              // role mailbox — no inference
        ])
        let proposals = ContactDataFiller.proposals(for: t, emailColumn: "Email")
        let p = try #require(proposal(.firstNameFromEmail, in: proposals))
        #expect(p.count == 1)
        #expect(p.column == "First Name")

        let (filled, count) = ContactDataFiller.apply(p, to: t, emailColumn: "Email")
        #expect(count == 1)
        #expect(filled.rows[0][0] == "John")
        #expect(filled.rows[1][0] == "Ada")
        #expect(filled.rows[2][0] == "")
    }

    @Test("Blank last names come only from clear first.last local parts")
    func lastNameFromEmail() throws {
        let t = table(["Last Name", "Email"], [
            ["", "john.smith@acme.com"],
            ["", "jsmith@acme.com"],           // single token — too ambiguous
            ["Kept", "maria.garcia@x.com"]
        ])
        let proposals = ContactDataFiller.proposals(for: t, emailColumn: "Email")
        let p = try #require(proposal(.lastNameFromEmail, in: proposals))
        #expect(p.count == 1)
        let (filled, _) = ContactDataFiller.apply(p, to: t, emailColumn: "Email")
        #expect(filled.rows[0][0] == "Smith")
        #expect(filled.rows[1][0] == "")
        #expect(filled.rows[2][0] == "Kept")
    }

    @Test("Rows with a populated Full Name are left to the split proposal, not the email guess")
    func emailGuessDefersToFullName() {
        let t = table(["First Name", "Full Name", "Email"], [
            ["", "Jordan Avery", "totally.different@acme.com"]
        ])
        let proposals = ContactDataFiller.proposals(for: t, emailColumn: "Email")
        #expect(proposal(.firstNameFromEmail, in: proposals) == nil)
        #expect(proposal(.splitFullName, in: proposals) != nil)
    }

    // MARK: Splitting and joining name columns

    @Test("A Full Name splits into blank First and Last cells")
    func splitFullName() throws {
        let t = table(["Full Name", "First Name", "Last Name", "Email"], [
            ["Jordan Avery", "", "", "j@x.com"],
            ["Acme Holdings Inc", "", "", "info@acme.com"],  // company — not split
            ["Cher", "", "", "cher@x.com"]                   // single word — not split
        ])
        let proposals = ContactDataFiller.proposals(for: t, emailColumn: "Email")
        let p = try #require(proposal(.splitFullName, in: proposals))
        #expect(p.count == 2)  // First + Last of row 0

        let (filled, count) = ContactDataFiller.apply(p, to: t, emailColumn: "Email")
        #expect(count == 2)
        #expect(filled.rows[0][1] == "Jordan")
        #expect(filled.rows[0][2] == "Avery")
        #expect(filled.rows[1][1] == "")
    }

    @Test("Multi-word surnames keep everything after the first word")
    func splitKeepsCompoundSurname() {
        #expect(ContactDataFiller.splitPersonName("Ludwig van Beethoven")?.last == "van Beethoven")
        #expect(ContactDataFiller.splitPersonName("Mary Jo O'Brien-Smith")?.first == "Mary")
    }

    @Test("Blank Full Name is assembled from First + Last")
    func joinFirstLast() throws {
        let t = table(["Name", "First Name", "Last Name", "Email"], [
            ["", "Jordan", "Avery", "j@x.com"],
            ["Existing Value", "Sam", "Patel", "s@x.com"],
            ["", "Riley", "", "r@x.com"]                     // half missing — skipped
        ])
        let proposals = ContactDataFiller.proposals(for: t, emailColumn: "Email")
        let p = try #require(proposal(.joinFirstLast, in: proposals))
        #expect(p.count == 1)
        let (filled, _) = ContactDataFiller.apply(p, to: t, emailColumn: "Email")
        #expect(filled.rows[0][0] == "Jordan Avery")
        #expect(filled.rows[1][0] == "Existing Value")
        #expect(filled.rows[2][0] == "")
    }

    // MARK: Company and website from the domain

    @Test("Blank Company copies the value coworkers' rows already have")
    func companyFromColleagues() throws {
        let t = table(["Company", "Email"], [
            ["Northwind Traders", "ada@northwind.com"],
            ["", "grace@northwind.com"],
            ["", "solo@unknownfirm.com"]
        ])
        let proposals = ContactDataFiller.proposals(for: t, emailColumn: "Email")
        let p = try #require(proposal(.companyFromColleagues, in: proposals))
        #expect(p.count == 1)
        let (filled, _) = ContactDataFiller.apply(p, to: t, emailColumn: "Email")
        #expect(filled.rows[1][0] == "Northwind Traders")
        // The lone unknown-domain row is left for the domain guess instead.
        #expect(filled.rows[2][0] == "")
    }

    @Test("With no coworker to copy from, Company is guessed from the domain")
    func companyFromDomain() throws {
        let t = table(["Company", "Email"], [
            ["", "sam@acme-corp.com"],
            ["", "pat@stark.co.uk"],
            ["", "casey@gmail.com"]           // consumer domain — never guessed
        ])
        let proposals = ContactDataFiller.proposals(for: t, emailColumn: "Email")
        let p = try #require(proposal(.companyFromDomain, in: proposals))
        #expect(p.count == 2)
        let (filled, _) = ContactDataFiller.apply(p, to: t, emailColumn: "Email")
        #expect(filled.rows[0][0] == "Acme Corp")
        #expect(filled.rows[1][0] == "Stark")
        #expect(filled.rows[2][0] == "")
    }

    @Test("Blank Website derives from the work domain, never a free-mail one")
    func websiteFromDomain() throws {
        let t = table(["Website", "Email"], [
            ["", "sam@acme.com"],
            ["", "casey@icloud.com"],
            ["https://kept.example.net", "pat@kept.net"]
        ])
        let proposals = ContactDataFiller.proposals(for: t, emailColumn: "Email")
        let p = try #require(proposal(.websiteFromDomain, in: proposals))
        #expect(p.count == 1)
        let (filled, _) = ContactDataFiller.apply(p, to: t, emailColumn: "Email")
        #expect(filled.rows[0][0] == "https://acme.com")
        #expect(filled.rows[1][0] == "")
        #expect(filled.rows[2][0] == "https://kept.example.net")
    }

    // MARK: Duplicate rows

    @Test("Rows sharing an email address fill each other's blanks")
    func duplicateRows() throws {
        let t = table(["First Name", "Company", "Email"], [
            ["Jordan", "", "jordan@acme.com"],
            ["", "Acme", "jordan@acme.com"],
            ["Riley", "", "riley@x.com"]      // unique address — untouched
        ])
        let proposals = ContactDataFiller.proposals(for: t, emailColumn: "Email")
        let p = try #require(proposal(.fromDuplicates, in: proposals))
        #expect(p.count == 2)
        let (filled, count) = ContactDataFiller.apply(p, to: t, emailColumn: "Email")
        #expect(count == 2)
        #expect(filled.rows[0][1] == "Acme")
        #expect(filled.rows[1][0] == "Jordan")
        #expect(filled.rows[2][1] == "")
    }

    // MARK: Invariants

    @Test("Applying a stale proposal to a table with no matching blanks is a no-op")
    func staleProposalIsSafe() throws {
        let t = table(["First Name", "Email"], [["", "john.smith@acme.com"]])
        let proposals = ContactDataFiller.proposals(for: t, emailColumn: "Email")
        let p = try #require(proposal(.firstNameFromEmail, in: proposals))
        let (once, _) = ContactDataFiller.apply(p, to: t, emailColumn: "Email")
        let (twice, secondCount) = ContactDataFiller.apply(p, to: once, emailColumn: "Email")
        #expect(twice == once)
        #expect(secondCount == 0)
    }

    @Test("A table with nothing to fill yields no proposals")
    func fullyPopulatedTable() {
        let t = table(["First Name", "Company", "Email"], [
            ["Jordan", "Acme", "jordan@acme.com"]
        ])
        #expect(ContactDataFiller.proposals(for: t, emailColumn: "Email").isEmpty)
    }

    @Test("Domain prettifying handles hyphens and country-code endings")
    func domainCompanyNames() {
        #expect(ContactDataFiller.companyName(fromDomain: "acme-corp.com") == "Acme Corp")
        #expect(ContactDataFiller.companyName(fromDomain: "northwind.co.uk") == "Northwind")
        #expect(ContactDataFiller.companyName(fromDomain: "x.io") == nil)  // too short to mean anything
    }

    @Test("Proposals surface source → value examples for the import screen")
    func proposalExamples() throws {
        let t = table(["First Name", "Email"], [["", "john.smith@acme.com"]])
        let proposals = ContactDataFiller.proposals(for: t, emailColumn: "Email")
        let p = try #require(proposal(.firstNameFromEmail, in: proposals))
        #expect(p.examples.first == ImportCleaner.Example(before: "john.smith@acme.com", after: "John"))
    }
}
