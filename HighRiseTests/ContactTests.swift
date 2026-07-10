import Testing
@testable import HighRise

/// `Contact.value(for:)` is the one place every merge, routing rule, and
/// display-name lookup actually resolves a field — pinned directly, plus its
/// synonym fallback ("Company" resolves an "Account Name" column).
struct ContactTests {

    @Test("Literal match wins over a synonym when both exist")
    func literalMatchPreferred() {
        let contact = Contact(fields: ["Company": "Acme", "Account": "Widgets Inc"],
                              email: "a@example.com")
        #expect(contact.value(for: "Company") == "Acme")
    }

    @Test("Falls back to a synonym when there's no literal match")
    func synonymFallback() {
        let contact = Contact(fields: ["Account Name": "Acme Holdings"],
                              email: "a@example.com")
        #expect(contact.value(for: "Company") == "Acme Holdings")
        #expect(contact.value(for: "Account") == "Acme Holdings")
    }

    @Test("An unrelated field with no data and no synonym returns nil")
    func noMatchReturnsNil() {
        let contact = Contact(fields: ["Account Name": "Acme"], email: "a@example.com")
        #expect(contact.value(for: "Coupon Code") == nil)
    }
}
