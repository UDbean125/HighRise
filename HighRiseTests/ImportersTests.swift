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
        ("A1", 0), ("B2", 1), ("Z9", 25), ("AA1", 26), ("AB10", 27), ("XFD1", 16_383)
    ])
    func columnIndex(ref: String, expected: Int) {
        #expect(XLSXReader.columnIndex(fromCellRef: ref) == expected)
    }

    @Test("Out-of-range column references are rejected, not trapped or materialized", arguments: [
        "XFE1",              // one past the real OOXML maximum (XFD)
        "ZZZZ1",             // would normalize every row to 475,254 cells
        "AAAAAAAA1",         // ~8 billion columns — guaranteed OOM if honored
        "AAAAAAAAAAAAAAA1",  // enough letters to trap Int overflow unbounded
    ])
    func columnIndexRejectsOutOfRange(ref: String) {
        #expect(XLSXReader.columnIndex(fromCellRef: ref) == nil)
    }

    // MARK: - Sheet cell placement

    @Test("Cells without the optional r= attribute occupy sequential columns")
    func cellsWithoutRefsPlaceSequentially() {
        // ECMA-376 makes r optional on <c>; streaming writers (SheetJS dense
        // mode and friends) omit it. Every cell must not collapse into col 0.
        let sheet = """
        <worksheet><sheetData>
          <row><c t="inlineStr"><is><t>Name</t></is></c><c t="inlineStr"><is><t>Email</t></is></c></row>
          <row><c t="inlineStr"><is><t>Jane</t></is></c><c t="inlineStr"><is><t>j@acme.com</t></is></c></row>
        </sheetData></worksheet>
        """
        let grid = XLSXReader.SheetParser_forTesting(Data(sheet.utf8))
        #expect(grid == [["Name", "Email"], ["Jane", "j@acme.com"]])
    }

    @Test("Referenced and unreferenced cells interleave correctly")
    func mixedRefsInterleave() {
        // B1 is explicit; the next ref-less cell continues after it (C1).
        let sheet = """
        <worksheet><sheetData>
          <row>
            <c t="inlineStr"><is><t>first</t></is></c>
            <c r="B1" t="inlineStr"><is><t>second</t></is></c>
            <c t="inlineStr"><is><t>third</t></is></c>
          </row>
        </sheetData></worksheet>
        """
        let grid = XLSXReader.SheetParser_forTesting(Data(sheet.utf8))
        #expect(grid == [["first", "second", "third"]])
    }

    @Test("A malformed cell reference aborts the sheet instead of crashing")
    func malformedRefAbortsParse() {
        let sheet = """
        <worksheet><sheetData>
          <row><c r="ZZZZ1" t="inlineStr"><is><t>x</t></is></c></row>
        </sheetData></worksheet>
        """
        #expect(XLSXReader.SheetParser_forTesting(Data(sheet.utf8)) == nil)
    }

    // MARK: - Worksheet discovery (multi-sheet picker + first-sheet bug fix)

    @Test("Workbook sheets are read in declared tab order, not filename order")
    func workbookOrder() {
        // Tab order Leads → Archive maps to sheet3.xml → sheet1.xml: filename
        // numbering is NOT the tab order, which is the bug the picker fixes.
        let workbook = """
        <?xml version="1.0"?>
        <workbook xmlns:r="http://.../relationships">
          <sheets>
            <sheet name="Leads" sheetId="3" r:id="rId5"/>
            <sheet name="Archive" sheetId="1" r:id="rId3"/>
          </sheets>
        </workbook>
        """
        let sheets = XLSXReader.WorkbookParser_forTesting(Data(workbook.utf8))
        #expect(sheets.map(\.name) == ["Leads", "Archive"])
        #expect(sheets.map(\.relationshipID) == ["rId5", "rId3"])
    }

    @Test("Hidden and very-hidden sheets are marked non-visible")
    func workbookHiddenState() {
        let workbook = """
        <workbook xmlns:r="http://x">
          <sheets>
            <sheet name="Visible" r:id="rId1"/>
            <sheet name="Gone" state="hidden" r:id="rId2"/>
            <sheet name="Deep" state="veryHidden" r:id="rId3"/>
          </sheets>
        </workbook>
        """
        let sheets = XLSXReader.WorkbookParser_forTesting(Data(workbook.utf8))
        #expect(sheets.first(where: { $0.name == "Visible" })?.state == "")
        #expect(sheets.first(where: { $0.name == "Gone" })?.state == "hidden")
        #expect(sheets.first(where: { $0.name == "Deep" })?.state == "veryhidden")
    }

    @Test("Relationships map ids to worksheet part targets")
    func relationships() {
        let rels = """
        <Relationships xmlns="http://.../relationships">
          <Relationship Id="rId3" Type="http://.../worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId5" Type="http://.../worksheet" Target="worksheets/sheet3.xml"/>
        </Relationships>
        """
        let map = XLSXReader.RelationshipsParser_forTesting(Data(rels.utf8))
        #expect(map["rId3"] == "worksheets/sheet1.xml")
        #expect(map["rId5"] == "worksheets/sheet3.xml")
    }
}

struct DuplicateDetectorTests {
    @Test("Returns every occurrence after the first, case/space-insensitively")
    func findsLaterDuplicates() {
        let contacts = [
            Contact(fields: [:], email: "a@x.com"),
            Contact(fields: [:], email: "b@x.com"),
            Contact(fields: [:], email: "A@X.com"),   // dup of 0
            Contact(fields: [:], email: " b@x.com "),  // dup of 1
        ]
        let dupes = DuplicateDetector.duplicateIDs(in: contacts)
        #expect(dupes.count == 2)
        #expect(dupes.contains(contacts[2].id))
        #expect(dupes.contains(contacts[3].id))
        #expect(!dupes.contains(contacts[0].id)) // first kept
        #expect(!dupes.contains(contacts[1].id))
    }

    @Test("No duplicates in a clean list")
    func noneWhenUnique() {
        let contacts = [
            Contact(fields: [:], email: "a@x.com"),
            Contact(fields: [:], email: "b@x.com"),
        ]
        #expect(DuplicateDetector.duplicateIDs(in: contacts).isEmpty)
    }

    @Test("Blank addresses are ignored, not treated as duplicates of each other")
    func blanksIgnored() {
        let contacts = [
            Contact(fields: [:], email: ""),
            Contact(fields: [:], email: "   "),
        ]
        #expect(DuplicateDetector.duplicateIDs(in: contacts).isEmpty)
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
