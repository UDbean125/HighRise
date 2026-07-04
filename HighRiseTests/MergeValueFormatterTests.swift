import Testing
import Foundation
@testable import HighRise

/// Formatting filters run at render time and must never corrupt data — an
/// unparseable value passes through untouched. These pin parsing and each
/// transform, plus their interaction with the fallback (`default`) filter.
struct MergeValueFormatterTests {

    private func contact(_ fields: [String: String]) -> Contact {
        Contact(fields: fields, email: "a@b.com")
    }

    // MARK: - Parsing

    @Test("Known filter names parse, with and without args")
    func parsesKnownFilters() {
        #expect(MergeValueFormatter.parseFilter("upper") == .upper)
        #expect(MergeValueFormatter.parseFilter(" Lowercase ") == .lower)
        #expect(MergeValueFormatter.parseFilter("capitalize") == .capitalize)
        #expect(MergeValueFormatter.parseFilter("fixcaps") == .fixCaps)
        #expect(MergeValueFormatter.parseFilter("currency:USD") == .currency("USD"))
        #expect(MergeValueFormatter.parseFilter("date:\"MMM d\"") == .date("MMM d"))
        #expect(MergeValueFormatter.parseFilter("default:there") == .defaultValue("there"))
    }

    @Test("An unrecognized segment becomes bare fallback text")
    func unknownIsFallback() {
        #expect(MergeValueFormatter.parseFilter("Hi there") == .defaultValue("Hi there"))
    }

    // MARK: - Casing

    @Test("Casing filters transform as expected")
    func casing() {
        #expect(MergeValueFormatter.apply(.upper, to: "acme") == "ACME")
        #expect(MergeValueFormatter.apply(.lower, to: "ACME") == "acme")
        #expect(MergeValueFormatter.apply(.capitalize, to: "ada lovelace") == "Ada Lovelace")
    }

    @Test("fixCaps repairs ALL-CAPS but leaves mixed case alone")
    func fixCaps() {
        #expect(MergeValueFormatter.apply(.fixCaps, to: "JOHN SMITH") == "John Smith")
        #expect(MergeValueFormatter.apply(.fixCaps, to: "McDonald") == "McDonald")
        #expect(MergeValueFormatter.apply(.fixCaps, to: "Ada") == "Ada")
    }

    // MARK: - Numbers & currency

    @Test("Number groups digits; currency formats with the given code")
    func numbersAndCurrency() {
        #expect(MergeValueFormatter.apply(.number, to: "1234567") == "1,234,567")
        // Currency symbol placement is locale-dependent; assert the parts.
        let usd = MergeValueFormatter.apply(.currency("USD"), to: "1234.5")
        #expect(usd.contains("1,234"))
        #expect(usd.contains("$") || usd.contains("US"))
    }

    @Test("Currency parses through symbols and separators")
    func currencyParsesMessyInput() {
        let out = MergeValueFormatter.apply(.currency("USD"), to: "$1,234.50")
        #expect(out.contains("1,234"))
    }

    @Test("Unparseable numbers pass through unchanged")
    func numberPassthrough() {
        #expect(MergeValueFormatter.apply(.number, to: "N/A") == "N/A")
        #expect(MergeValueFormatter.apply(.currency("USD"), to: "TBD") == "TBD")
    }

    // MARK: - Dates

    @Test("An ISO date reformats to the requested pattern")
    func isoDateReformat() {
        #expect(MergeValueFormatter.apply(.date("MMMM d, yyyy"), to: "2026-06-22") == "June 22, 2026")
    }

    @Test("A US-style date reformats")
    func usDateReformat() {
        #expect(MergeValueFormatter.apply(.date("yyyy-MM-dd"), to: "06/22/2026") == "2026-06-22")
    }

    @Test("An Excel serial day reformats to a real date")
    func excelSerialReformat() {
        // 46195 = 2026-06-22 in Excel's 1900 date system.
        #expect(MergeValueFormatter.apply(.date("yyyy-MM-dd"), to: "46195") == "2026-06-22")
    }

    @Test("An unparseable date passes through unchanged")
    func datePassthrough() {
        #expect(MergeValueFormatter.apply(.date("yyyy"), to: "sometime soon") == "sometime soon")
    }

    // MARK: - End-to-end through the merge engine

    @Test("Filters apply to a merged field value")
    func filtersThroughMerge() {
        let template = EmailTemplate(subject: "Due {{Due Date|date:MMM d, yyyy}} — {{Amount|currency:USD}}",
                                     body: "Hi {{Name|fixcaps}}")
        let preview = TemplateMergeEngine.merge(template: template,
            with: contact(["Due Date": "2026-07-22", "Amount": "24500", "Name": "JORDAN AVERY"]))
        #expect(preview.resolvedSubject == "Due Jul 22, 2026 — $24,500.00")
        #expect(preview.resolvedBody == "Hi Jordan Avery")
    }

    @Test("A fallback is formatted too, and still doesn't block")
    func fallbackThenFormat() {
        let template = EmailTemplate(subject: "Hi {{Name|there|capitalize}}", body: "x")
        let preview = TemplateMergeEngine.merge(template: template, with: contact([:]))
        #expect(preview.resolvedSubject == "Hi There")
        #expect(preview.unresolvedFields.isEmpty)
    }
}
