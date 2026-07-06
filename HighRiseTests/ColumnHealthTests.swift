import Testing
@testable import HighRise

/// Duplicate columns silently drop data on import, so the detector's
/// case/whitespace-insensitive matching and first-seen ordering are pinned.
struct ColumnHealthTests {

    @Test("No duplicates when every header is unique")
    func unique() {
        #expect(ColumnHealth.duplicateHeaders(["Name", "Email", "Company"]).isEmpty)
        #expect(ColumnHealth.duplicateHeaders([]).isEmpty)
    }

    @Test("Matches case- and whitespace-insensitively, keeping the first form")
    func caseAndWhitespace() {
        #expect(ColumnHealth.duplicateHeaders(["Email", " email ", "EMAIL"]) == ["Email"])
        #expect(ColumnHealth.duplicateHeaders(["Name", "Company", "name"]) == ["Name"])
    }

    @Test("Reports each duplicated header once, in first-seen order")
    func firstSeenOrder() {
        let dupes = ColumnHealth.duplicateHeaders(["A", "B", "b", "A", "C", "c"])
        #expect(dupes == ["A", "B", "C"])
    }

    @Test("Blank headers are ignored")
    func blanksIgnored() {
        #expect(ColumnHealth.duplicateHeaders(["", "  ", "\t"]).isEmpty)
        #expect(ColumnHealth.duplicateHeaders(["Name", "", "name", "  "]) == ["Name"])
    }
}
