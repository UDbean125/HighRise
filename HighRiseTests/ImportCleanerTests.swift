import Testing
import Foundation
@testable import HighRise

/// The import cleaner rewrites user data, so its behavior is pinned tightly:
/// auto-fixes must be mechanical and loss-free, suggestions must never apply
/// themselves, and anything ambiguous must be left exactly as imported.
struct ImportCleanerTests {

    // MARK: - Whitespace & invisibles

    @Test("Trims ends, collapses runs, and converts exotic spaces")
    func whitespaceBasics() {
        #expect(ImportCleaner.normalizeWhitespace("  Ada   Lovelace ") == "Ada Lovelace")
        #expect(ImportCleaner.normalizeWhitespace("Acme\u{00A0}Corp") == "Acme Corp")
        #expect(ImportCleaner.normalizeWhitespace("Ada\tLovelace") == "Ada Lovelace")
        #expect(ImportCleaner.normalizeWhitespace("clean") == "clean")
    }

    @Test("Deletes zero-width characters and soft hyphens outright")
    func invisibleCharacters() {
        #expect(ImportCleaner.normalizeWhitespace("ada\u{200B}@example.com") == "ada@example.com")
        #expect(ImportCleaner.normalizeWhitespace("Lo\u{00AD}ve\u{FEFF}lace") == "Lovelace")
    }

    @Test("Preserves intentional line breaks inside a value")
    func multilineValues() {
        #expect(ImportCleaner.normalizeWhitespace("200 Harbor Way\nSeattle") == "200 Harbor Way\nSeattle")
        #expect(ImportCleaner.normalizeWhitespace("200 Harbor Way\r\nSeattle") == "200 Harbor Way\nSeattle")
        // Blank lines at the ends go; interior structure stays.
        #expect(ImportCleaner.normalizeWhitespace("\nline one\n\nline two\n") == "line one\n\nline two")
    }

    // MARK: - Junk tokens

    @Test("Recognizes spreadsheet error and placeholder tokens")
    func junkTokens() {
        for junk in ["#N/A", "#REF!", "#VALUE!", "#DIV/0!", "NULL", "null", "n/a", "N/A", "-", "--"] {
            #expect(ImportCleaner.isJunkValue(junk), "\(junk) should be junk")
        }
    }

    @Test("Leaves ambiguous values alone")
    func notJunk() {
        for value in ["0", "NA", "Naomi", "None Given", "N/A Consulting", ""] {
            #expect(!ImportCleaner.isJunkValue(value), "\(value) should not be junk")
        }
    }

    // MARK: - Email repair

    @Test("Repairs the mechanical email manglings")
    func emailRepairs() {
        #expect(ImportCleaner.repairedEmail("mailto:ada@example.com") == "ada@example.com")
        #expect(ImportCleaner.repairedEmail("Ada Lovelace <ada@example.com>") == "ada@example.com")
        #expect(ImportCleaner.repairedEmail("<mailto:ada@example.com>") == "ada@example.com")
        #expect(ImportCleaner.repairedEmail("\"ada@example.com\"") == "ada@example.com")
        #expect(ImportCleaner.repairedEmail("ada@example.com,") == "ada@example.com")
        #expect(ImportCleaner.repairedEmail("ada@example.com.") == "ada@example.com")
        #expect(ImportCleaner.repairedEmail("ada @example.com") == "ada@example.com")
    }

    @Test("Never touches valid, empty, or unfixable addresses")
    func emailRepairRestraint() {
        #expect(ImportCleaner.repairedEmail("ada@example.com") == nil)
        #expect(ImportCleaner.repairedEmail("") == nil)
        #expect(ImportCleaner.repairedEmail("not-an-email") == nil)
        #expect(ImportCleaner.repairedEmail("ada(at)example.com") == nil)
    }

    // MARK: - Repeated header rows

    @Test("Spots a header row repeated inside the data")
    func repeatedHeader() {
        let headers = ["Name", "Email"]
        #expect(ImportCleaner.isRepeatedHeaderRow(["Name", "Email"], headers: headers))
        #expect(ImportCleaner.isRepeatedHeaderRow(["name", " EMAIL "], headers: headers))
        #expect(!ImportCleaner.isRepeatedHeaderRow(["Name", "ada@example.com"], headers: headers))
        // A single trivial match is not enough evidence.
        #expect(!ImportCleaner.isRepeatedHeaderRow(["email"], headers: ["Email"]))
    }

    // MARK: - autoClean end to end

    @Test("Cleans a messy table and reports every fix")
    func autoCleanEndToEnd() {
        let table = RecipientTable(
            headers: ["Name", "Email\u{00A0}", "Company"],
            rows: [
                ["  Ada   Lovelace ", "mailto:ada@example.com", "Acme"],
                ["Name", "Email", ""],                       // repeated header
                ["Bob", "bob@example.com", "#N/A"],
                ["Cat", "Cat Doe <cat@example.com>", "Cyberdyne"]
            ])

        let (cleaned, report) = ImportCleaner.autoClean(table, emailColumn: "Email")

        #expect(cleaned.headers == ["Name", "Email", "Company"])
        #expect(cleaned.rows.count == 3)
        #expect(cleaned.rows[0] == ["Ada Lovelace", "ada@example.com", "Acme"])
        #expect(cleaned.rows[1] == ["Bob", "bob@example.com", ""])
        #expect(cleaned.rows[2] == ["Cat", "cat@example.com", "Cyberdyne"])

        let kinds = Dictionary(uniqueKeysWithValues: report.changes.map { ($0.kind, $0.count) })
        #expect(kinds[.whitespace, default: 0] >= 2)          // header + name cell
        #expect(kinds[.junkValue] == 1)
        #expect(kinds[.emailRepair] == 2)
        #expect(kinds[.repeatedHeaderRow] == 1)
        #expect(report.totalFixes == report.changes.reduce(0) { $0 + $1.count })
    }

    @Test("A clean table passes through untouched with an empty report")
    func autoCleanNoop() {
        let table = RecipientTable(headers: ["Name", "Email"],
                                   rows: [["Ada", "ada@example.com"]])
        let (cleaned, report) = ImportCleaner.autoClean(table, emailColumn: "Email")
        #expect(cleaned == table)
        #expect(report.isEmpty)
        #expect(report.totalFixes == 0)
    }

    @Test("Detects the email column itself when none is named")
    func autoCleanDetectsEmailColumn() {
        let table = RecipientTable(headers: ["Name", "E-Mail Address"],
                                   rows: [["Ada", "mailto:ada@example.com"]])
        let (cleaned, report) = ImportCleaner.autoClean(table)
        #expect(cleaned.rows[0][1] == "ada@example.com")
        #expect(report.changes.contains { $0.kind == .emailRepair })
    }

    @Test("Examples are capped at three per change kind")
    func exampleCap() {
        let rows = (0..<10).map { ["  row \($0) ", "r\($0)@example.com"] }
        let table = RecipientTable(headers: ["Name", "Email"], rows: rows)
        let (_, report) = ImportCleaner.autoClean(table, emailColumn: "Email")
        let whitespace = report.changes.first { $0.kind == .whitespace }
        #expect(whitespace?.count == 10)
        #expect(whitespace?.examples.count == 3)
    }

    // MARK: - Domain typo suggestions

    @Test("Corrects known domain typos, dead TLDs, and comma-for-dot")
    func domainCorrections() {
        #expect(ImportCleaner.correctedDomainEmail("laura@gmial.com") == "laura@gmail.com")
        #expect(ImportCleaner.correctedDomainEmail("bob@hotmial.com") == "bob@hotmail.com")
        #expect(ImportCleaner.correctedDomainEmail("kim@acme.con") == "kim@acme.com")
        #expect(ImportCleaner.correctedDomainEmail("kim@acme.cmo") == "kim@acme.com")
        #expect(ImportCleaner.correctedDomainEmail("kim@acme,com") == "kim@acme.com")
    }

    @Test("Leaves plausible domains alone")
    func domainRestraint() {
        #expect(ImportCleaner.correctedDomainEmail("ada@example.com") == nil)
        #expect(ImportCleaner.correctedDomainEmail("ada@acme.co") == nil)     // real ccTLD
        #expect(ImportCleaner.correctedDomainEmail("no-at-sign") == nil)
        #expect(ImportCleaner.correctedDomainEmail("@gmial.com") == nil)      // no local part
    }

    // MARK: - Casing suggestions

    @Test("Title-cases shouting or lowercase names and companies")
    func casingFixes() {
        #expect(ImportCleaner.fixedCasing("ACME HOLDINGS") == "Acme Holdings")
        #expect(ImportCleaner.fixedCasing("jordan avery") == "Jordan Avery")
        #expect(ImportCleaner.fixedCasing("O'BRIEN-SMITH") == "O'Brien-Smith")
        #expect(ImportCleaner.fixedCasing("MCDONALD") == "McDonald")
        #expect(ImportCleaner.fixedCasing("LUDWIG VAN BEETHOVEN") == "Ludwig van Beethoven")
        #expect(ImportCleaner.fixedCasing("HENRY FORD III") == "Henry Ford III")
    }

    @Test("Leaves mixed case, short values, and non-names alone")
    func casingRestraint() {
        #expect(ImportCleaner.fixedCasing("McDonald") == nil)           // already deliberate
        #expect(ImportCleaner.fixedCasing("Acme Holdings") == nil)
        #expect(ImportCleaner.fixedCasing("AL") == nil)                 // too short to judge
        #expect(ImportCleaner.fixedCasing("ADA@EXAMPLE.COM") == nil)    // address, not a name
        #expect(ImportCleaner.fixedCasing("WWW.ACME.COM") == nil)
        #expect(ImportCleaner.fixedCasing("") == nil)
    }

    // MARK: - Name order suggestions

    @Test("Flips Last, First names")
    func nameFlips() {
        #expect(ImportCleaner.flippedName("Avery, Jordan") == "Jordan Avery")
        #expect(ImportCleaner.flippedName("O'Brien, Mary-Kate") == "Mary-Kate O'Brien")
        #expect(ImportCleaner.flippedName("van der Berg, Anna") == "Anna van der Berg")
    }

    @Test("Never flips company suffixes, generational suffixes, or non-names")
    func nameFlipRestraint() {
        #expect(ImportCleaner.flippedName("Acme, Inc.") == nil)
        #expect(ImportCleaner.flippedName("Smith, Jr.") == nil)
        #expect(ImportCleaner.flippedName("Jordan Avery") == nil)       // no comma
        #expect(ImportCleaner.flippedName("Doe, Jane, Extra") == nil)   // two commas
        #expect(ImportCleaner.flippedName("Suite 4, Acme House 22") == nil) // digits
    }

    // MARK: - Suggestions end to end

    @Test("Builds suggestions with counts and examples, never applying them")
    func suggestionScan() {
        let table = RecipientTable(
            headers: ["Name", "Email", "Company"],
            rows: [
                ["Avery, Jordan", "jordan@gmial.com", "ACME HOLDINGS"],
                ["Bob Smith", "bob@example.com", "Cyberdyne"]
            ])
        let suggestions = ImportCleaner.suggestions(for: table, emailColumn: "Email")

        let byKind = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.kind, $0) })
        #expect(byKind[.domainTypo]?.count == 1)
        #expect(byKind[.domainTypo]?.column == "Email")
        #expect(byKind[.nameOrder]?.count == 1)
        #expect(byKind[.shoutingCase]?.count == 1)
        #expect(byKind[.shoutingCase]?.column == "Company")
        #expect(byKind[.domainTypo]?.examples.first ==
                ImportCleaner.Example(before: "jordan@gmial.com", after: "jordan@gmail.com"))
        // Scanning must not mutate — apply is a separate, explicit step.
        #expect(table.rows[0][1] == "jordan@gmial.com")
    }

    @Test("A tidy table yields no suggestions")
    func suggestionSilence() {
        let table = RecipientTable(headers: ["Name", "Email", "Company"],
                                   rows: [["Jordan Avery", "jordan@example.com", "Acme"]])
        #expect(ImportCleaner.suggestions(for: table, emailColumn: "Email").isEmpty)
    }

    @Test("Applying a suggestion fixes exactly the matching values")
    func applySuggestion() throws {
        let table = RecipientTable(
            headers: ["Name", "Email"],
            rows: [
                ["Avery, Jordan", "jordan@example.com"],
                ["Bob Smith", "bob@example.com"],
                ["O'Brien, Mary", "mary@example.com"]
            ])
        let suggestion = ImportCleaner.suggestions(for: table, emailColumn: "Email")
            .first { $0.kind == .nameOrder }
        let unwrapped = try #require(suggestion)

        let (updated, fixed) = ImportCleaner.apply(unwrapped, to: table)
        #expect(fixed == 2)
        #expect(updated.rows.map { $0[0] } == ["Jordan Avery", "Bob Smith", "Mary O'Brien"])
        #expect(updated.rows.map { $0[1] } == table.rows.map { $0[1] })  // other columns untouched
    }

    @Test("Re-applying a suggestion is a no-op (safe after a re-clean)")
    func applyIdempotent() throws {
        let table = RecipientTable(headers: ["Email"], rows: [["kim@gmial.com"]])
        let suggestion = try #require(
            ImportCleaner.suggestions(for: table, emailColumn: "Email").first)
        let once = ImportCleaner.apply(suggestion, to: table)
        let twice = ImportCleaner.apply(suggestion, to: once.table)
        #expect(once.table.rows[0][0] == "kim@gmail.com")
        #expect(twice.fixed == 0)
        #expect(twice.table == once.table)
    }

    // MARK: - Column classification

    @Test("Only name- and company-like columns are casing candidates")
    func casingColumns() {
        for header in ["Name", "Full Name", "first_name", "Company", "Organisation", "Account Name"] {
            #expect(ImportCleaner.isCasingColumn(header), "\(header)")
        }
        for header in ["Email", "Notes", "Address", "Job Title", "Website"] {
            #expect(!ImportCleaner.isCasingColumn(header), "\(header)")
        }
    }

    @Test("Only whole-name columns are flip candidates")
    func fullNameColumns() {
        #expect(ImportCleaner.isFullNameColumn("Name"))
        #expect(ImportCleaner.isFullNameColumn("Full Name"))
        #expect(!ImportCleaner.isFullNameColumn("First Name"))
        #expect(!ImportCleaner.isFullNameColumn("Company"))
    }
}
