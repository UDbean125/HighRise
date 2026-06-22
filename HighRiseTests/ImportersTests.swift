import Testing
import Foundation
@testable import HighRise

struct EmailValidatorTests {
    @Test("Accepts ordinary addresses", arguments: [
        "ada@example.com", "first.last@sub.domain.co", "name+tag@host.io", "a@b.cd"
    ])
    func valid(address: String) {
        #expect(EmailValidator.isValid(address))
    }

    @Test("Rejects malformed addresses", arguments: [
        "", "no-at-sign", "missing@domain", "@example.com", "spaces in@x.com", "trailing@x.com,"
    ])
    func invalid(address: String) {
        #expect(!EmailValidator.isValid(address))
    }

    @Test("Trims surrounding whitespace before validating")
    func trims() {
        #expect(EmailValidator.isValid("  ada@example.com  "))
    }
}

struct XLSXReaderTests {
    @Test("Column letters map to zero-based indices", arguments: [
        ("A1", 0), ("B2", 1), ("Z9", 25), ("AA1", 26), ("AB10", 27)
    ])
    func columnIndex(ref: String, expected: Int) {
        #expect(XLSXReader.columnIndex(fromCellRef: ref) == expected)
    }
}

struct LooseContactExtractorTests {
    @Test("Finds emails and a name guess from prefix text")
    func extracts() {
        let text = "Ada Lovelace <ada@example.com>\nGrace Hopper: grace@navy.mil"
        let table = LooseContactExtractor.table(from: text)
        #expect(table.headers == ["Name", "Email"])
        #expect(table.rows.count == 2)
        #expect(table.rows[0] == ["Ada Lovelace", "ada@example.com"])
        #expect(table.rows[1] == ["Grace Hopper", "grace@navy.mil"])
    }

    @Test("Deduplicates repeated addresses")
    func dedupes() {
        let text = "a@b.com\nagain a@b.com"
        let table = LooseContactExtractor.table(from: text)
        #expect(table.rows.count == 1)
    }

    @Test("Returns no rows when there are no addresses")
    func none() {
        let table = LooseContactExtractor.table(from: "just some prose with no contacts")
        #expect(table.rows.isEmpty)
    }
}

@MainActor
struct OutlookContactsParseTests {
    @Test("Parses tab-delimited contact lines into a table")
    func parses() {
        let output = "Ada\tLovelace\tAnalytical Engine Co\tada@example.com\nGrace\tHopper\tUS Navy\tgrace@navy.mil\n"
        let table = OutlookContactsImporter.parse(output)
        #expect(table.headers == ["Name", "Company", "Email"])
        #expect(table.rows.count == 2)
        #expect(table.rows[0] == ["Ada Lovelace", "Analytical Engine Co", "ada@example.com"])
    }

    @Test("Skips rows with an invalid or missing email")
    func skipsInvalid() {
        let output = "No\tEmail\tCorp\t\nBad\tAddr\tCorp\tnotanemail\nOK\tOne\tCorp\tok@x.com\n"
        let table = OutlookContactsImporter.parse(output)
        #expect(table.rows.count == 1)
        #expect(table.rows[0][2] == "ok@x.com")
    }
}
