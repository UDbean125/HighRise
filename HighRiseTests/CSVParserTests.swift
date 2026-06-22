import Testing
import Foundation
@testable import HighRise

/// Locks down CSV parsing — the format real contact exports arrive in. The
/// quoting rules (commas and newlines inside quotes, doubled quotes) are where
/// naive parsers corrupt a recipient's data, so they're pinned here.
struct CSVParserTests {

    @Test("Parses a simple header + rows")
    func simple() throws {
        let table = try CSVParser.parse("Name,Email\nAda,ada@example.com\nGrace,grace@example.com")
        #expect(table.headers == ["Name", "Email"])
        #expect(table.rows.count == 2)
        #expect(table.rows[0] == ["Ada", "ada@example.com"])
    }

    @Test("Honors commas inside quoted fields")
    func quotedCommas() throws {
        let table = try CSVParser.parse("Company,Email\n\"Smith, Jones & Co\",info@sj.com")
        #expect(table.rows[0][0] == "Smith, Jones & Co")
        #expect(table.rows[0][1] == "info@sj.com")
    }

    @Test("Unescapes doubled quotes inside a quoted field")
    func doubledQuotes() throws {
        let table = try CSVParser.parse("Note,Email\n\"She said \"\"hi\"\"\",a@b.com")
        #expect(table.rows[0][0] == "She said \"hi\"")
    }

    @Test("Handles newlines inside quoted fields")
    func quotedNewlines() throws {
        let table = try CSVParser.parse("Address,Email\n\"Line 1\nLine 2\",a@b.com")
        #expect(table.rows.count == 1)
        #expect(table.rows[0][0] == "Line 1\nLine 2")
    }

    @Test("Empty input throws rather than producing junk")
    func emptyThrows() {
        #expect(throws: CSVParser.ParseError.self) {
            _ = try CSVParser.parse("")
        }
    }

    @Test("Detects an email column by header name")
    func detectByHeader() throws {
        let table = try CSVParser.parse("Name,Work Email\nAda,ada@example.com")
        #expect(CSVParser.detectEmailColumn(in: table) == "Work Email")
    }

    @Test("Detects an email column by content when no header hints")
    func detectByContent() throws {
        let table = try CSVParser.parse("A,B\nAda,ada@example.com\nGrace,grace@example.com")
        #expect(CSVParser.detectEmailColumn(in: table) == "B")
    }

    @Test("Maps rows to contacts and skips rows with no email")
    func contactsSkipNoEmail() throws {
        let table = try CSVParser.parse("Name,Email\nAda,ada@example.com\nNoEmail,")
        let (contacts, header) = CSVParser.contacts(from: table)
        #expect(header == "Email")
        #expect(contacts.count == 1)
        #expect(contacts[0].email == "ada@example.com")
        #expect(contacts[0].value(for: "name") == "Ada")
    }

    @Test("Contact field lookup is case-insensitive")
    func caseInsensitiveLookup() throws {
        let table = try CSVParser.parse("Company,Email\nAcme,a@acme.com")
        let (contacts, _) = CSVParser.contacts(from: table)
        #expect(contacts[0].value(for: "COMPANY") == "Acme")
        #expect(contacts[0].value(for: " company ") == "Acme")
    }
}
