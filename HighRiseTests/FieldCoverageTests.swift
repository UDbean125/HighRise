import Testing
@testable import HighRise

/// Field coverage tells users, in Compose, whether their merge fields will
/// actually resolve — so the matched/fallback/missing classification and the
/// summary wording are pinned. A "missing" field is the one that silently holds
/// rows back, so it must never be mislabeled.
struct FieldCoverageTests {

    @Test("Classifies matched, fallback-only, and missing fields")
    func classification() {
        // Company is only ever used with a fallback (not in `requiring`); Coupon
        // is required but has no column.
        let report = FieldCoverage.assess(
            referenced: ["First Name", "Company", "Coupon"],
            requiring: ["First Name", "Coupon"],
            headers: ["First Name", "Email"])

        #expect(report.total == 3)
        #expect(report.matched.map(\.name) == ["First Name"])
        #expect(report.fallbackOnly.map(\.name) == ["Company"])
        #expect(report.missing.map(\.name) == ["Coupon"])
        #expect(report.allBacked == false)
    }

    @Test("Matching is case- and whitespace-insensitive")
    func normalization() {
        let report = FieldCoverage.assess(
            referenced: ["first name"], requiring: ["first name"],
            headers: [" First Name "])
        #expect(report.matched.map(\.name) == ["first name"])
        #expect(report.missing.isEmpty)
    }

    @Test("A fully-backed template reports allBacked")
    func allBacked() {
        let report = FieldCoverage.assess(
            referenced: ["A", "B"], requiring: ["A"], headers: ["a", "b"])
        #expect(report.allBacked)
        #expect(report.missing.isEmpty)
        #expect(FieldCoverage.line(report) == "All 2 fields backed by your list")
    }

    @Test("Summary line pluralizes needs and counts backed fields")
    func lineWording() {
        let mixed = FieldCoverage.assess(
            referenced: ["First Name", "Company", "Coupon"],
            requiring: ["First Name", "Coupon"],
            headers: ["First Name"])
        // First Name matched; Company fallback; Coupon missing → 1 of 3 backed.
        #expect(FieldCoverage.line(mixed) == "1 of 3 backed · 1 needs a column")

        let twoMissing = FieldCoverage.assess(
            referenced: ["X", "Y"], requiring: ["X", "Y"], headers: [])
        #expect(FieldCoverage.line(twoMissing) == "0 of 2 backed · 2 need a column")

        #expect(FieldCoverage.line(FieldCoverage.assess(referenced: [], requiring: [], headers: [])) == "No merge fields yet")
    }

    @Test("A synonym column (Account Name) backs the Company field")
    func synonymCountsAsMatched() {
        let report = FieldCoverage.assess(
            referenced: ["Company"], requiring: ["Company"], headers: ["Account Name"])
        #expect(report.matched.map(\.name) == ["Company"])
        #expect(report.missing.isEmpty)
    }

    @Test("A near-miss header (Company Status) is NOT mistaken for the synonym")
    func nearMissHeaderDoesNotFalselyMatch() {
        let report = FieldCoverage.assess(
            referenced: ["Company"], requiring: ["Company"], headers: ["Company Status"])
        #expect(report.matched.isEmpty)
        #expect(report.missing.map(\.name) == ["Company"])
    }

    @Test("Drives from a real template through referencedFields/fieldsRequiringData")
    func fromTemplate() {
        // Subject uses Company (required); body uses First Name with a fallback.
        let template = EmailTemplate(subject: "Quote for {{Company}}",
                                     body: "Hi {{First Name|there}}, thanks.")
        let report = FieldCoverage.assess(template: template, headers: ["First Name"])
        // Company has no column and no fallback → missing; First Name matched.
        #expect(report.matched.map(\.name) == ["First Name"])
        #expect(report.missing.map(\.name) == ["Company"])
        #expect(report.allBacked == false)
    }
}
