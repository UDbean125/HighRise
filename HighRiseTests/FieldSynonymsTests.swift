import Testing
@testable import HighRise

/// Pins the exact-phrase synonym groups `Contact.value(for:)` and
/// `FieldCoverage` rely on to recognize "Company" and "Account" (etc.) as the
/// same field — and, just as importantly, pins what must NOT match, since a
/// false positive here would silently merge the wrong data into a message.
struct FieldSynonymsTests {

    @Test("Recognizes company/account as synonyms")
    func companyAndAccount() {
        #expect(FieldSynonyms.match("Company", "Account"))
        #expect(FieldSynonyms.match("Account Name", "Company"))
        #expect(FieldSynonyms.match("Organization", "company name"))
    }

    @Test("Recognizes first-name and last-name synonym groups")
    func nameSynonyms() {
        #expect(FieldSynonyms.match("Given Name", "First Name"))
        #expect(FieldSynonyms.match("Surname", "Last Name"))
        // First name and last name are different concepts, not synonyms.
        #expect(!FieldSynonyms.match("First Name", "Last Name"))
    }

    @Test("Is case- and whitespace-insensitive, like every other field match")
    func normalization() {
        #expect(FieldSynonyms.match("  company  ", "ACCOUNT"))
    }

    @Test("Identical names always match, synonym table or not")
    func literalMatchAlwaysWorks() {
        #expect(FieldSynonyms.match("Renewal Date", "Renewal Date"))
        #expect(FieldSynonyms.match("Coupon Code", "coupon code"))
    }

    @Test("Related-looking but distinct fields do NOT match")
    func avoidsFalsePositives() {
        // "Company Status" and "Account Manager" are real headers from a CRM
        // export — neither is the company-name field, and naive substring
        // matching would wrongly say they are.
        #expect(!FieldSynonyms.match("Company Status", "Company"))
        #expect(!FieldSynonyms.match("Account Manager", "Company"))
        #expect(!FieldSynonyms.match("Parent Account", "Account"))
        #expect(!FieldSynonyms.match("Business Phone", "Company"))
    }

    @Test("Fields with no recognized synonym only match themselves")
    func unknownFieldsAreLiteralOnly() {
        #expect(!FieldSynonyms.match("Quote Number", "PO Number"))
    }
}
