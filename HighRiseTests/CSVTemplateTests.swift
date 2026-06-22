import Testing
import Foundation
@testable import HighRise

struct CSVTemplateTests {

    @Test("Fields without specials are left unquoted")
    func plainField() {
        #expect(CSVTemplateExporter.escapeField("Jordan") == "Jordan")
    }

    @Test("Fields with a comma are quoted")
    func commaQuoted() {
        #expect(CSVTemplateExporter.escapeField("Avery, Jordan") == "\"Avery, Jordan\"")
    }

    @Test("Internal quotes are doubled and the field quoted")
    func quoteEscaped() {
        #expect(CSVTemplateExporter.escapeField("12\" pipe") == "\"12\"\" pipe\"")
    }

    @Test("Template has a header row plus one example row")
    func twoRows() {
        let lines = CSVTemplateExporter.templateCSV()
            .split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2)
        #expect(lines[0].contains("Email"))
        #expect(lines[0].contains("Product Name"))
    }

    @Test("Generated template parses back into exactly one valid contact")
    func roundTrips() throws {
        let table = try CSVParser.parse(CSVTemplateExporter.templateCSV())
        let (contacts, emailHeader) = CSVParser.contacts(from: table)
        #expect(emailHeader == "Email")
        #expect(contacts.count == 1)
        #expect(EmailValidator.isValid(contacts[0].email))
        // Custom professional fields are present and addressable as merge fields.
        #expect(contacts[0].value(for: "Product Name") == "Fleet Analytics Suite")
        #expect(contacts[0].value(for: "Quote Number") == "Q-2026-0417")
    }

    @Test("Recommended catalog exposes the expected professional fields")
    func catalogCoverage() {
        let names = Set(MergeFieldCatalog.allFields.map(\.name))
        for expected in ["First Name", "Company", "Product Name", "Quote Number",
                         "Amount", "Due Date", "Account Manager"] {
            #expect(names.contains(expected))
        }
    }
}
