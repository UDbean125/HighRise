import Testing
import Foundation
@testable import HighRise

/// Locks down CSV parsing — the format real contact exports arrive in. The
/// quoting rules (commas and newlines inside quotes, doubled quotes) are where
/// naive parsers corrupt a recipient's data, so they're pinned here.
struct CSVParserTests {

    // MARK: - Robustness (delimiters, BOM, encodings)

    @Test("Semicolon-delimited European CSVs are auto-detected")
    func semicolonDelimiter() throws {
        let table = try CSVParser.parse("Name;Email;City\nAda;ada@x.com;Berlin")
        #expect(table.headers == ["Name", "Email", "City"])
        #expect(table.rows[0] == ["Ada", "ada@x.com", "Berlin"])
    }

    @Test("Tab-separated values are auto-detected")
    func tabDelimiter() throws {
        let table = try CSVParser.parse("Name\tEmail\nAda\tada@x.com")
        #expect(table.headers == ["Name", "Email"])
        #expect(table.rows[0] == ["Ada", "ada@x.com"])
    }

    @Test("Comma wins when both comma and semicolon appear equally")
    func delimiterTieFavorsComma() {
        // "a,b;c" — one comma, one semicolon → comma preferred.
        #expect(CSVParser.detectDelimiter(in: "a,b;c") == ",")
    }

    @Test("A leading UTF-8 BOM is stripped from the first header")
    func stripsBOM() throws {
        let table = try CSVParser.parse("\u{FEFF}Name,Email\nAda,ada@x.com")
        #expect(table.headers == ["Name", "Email"])   // not "\u{FEFF}Name"
    }

    @Test("decode reads UTF-8 with a BOM")
    func decodeUTF8BOM() {
        var data = Data([0xEF, 0xBB, 0xBF])           // UTF-8 BOM
        data.append("Name,Email".data(using: .utf8)!)
        #expect(CSVParser.decode(data) == "Name,Email")
    }

    @Test("decode falls back to a single-byte encoding for non-UTF-8 bytes")
    func decodeLatin1() {
        // 0xE9 is 'é' in Latin-1 / CP1252 but invalid as standalone UTF-8.
        let data = Data([0x4E, 0x61, 0x6D, 0x65, 0x3A, 0x20, 0xE9])  // "Name: é"
        let decoded = CSVParser.decode(data)
        #expect(decoded?.contains("é") == true)
    }

    @Test("An explicit delimiter overrides detection")
    func explicitDelimiter() throws {
        // Force comma parsing on a line that also contains semicolons.
        let table = try CSVParser.parse("A,B\n1;2,3", delimiter: ",")
        #expect(table.headers == ["A", "B"])
        #expect(table.rows[0] == ["1;2", "3"])
    }

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
