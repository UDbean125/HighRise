import Testing
@testable import HighRise

/// Name inference is offered as a suggested fix, so precision matters more than
/// recall: it must never suggest a name for a role mailbox or gibberish.
struct NameInferenceTests {

    @Test("first.last style addresses yield the capitalized first name")
    func dottedName() {
        #expect(NameInference.suggestedFirstName(from: "john.smith@acme.com") == "John")
        #expect(NameInference.suggestedFirstName(from: "ada_lovelace@x.io") == "Ada")
        #expect(NameInference.suggestedFirstName(from: "grace-hopper@navy.mil") == "Grace")
    }

    @Test("Plus-addressing is stripped before inference")
    func plusTag() {
        #expect(NameInference.suggestedFirstName(from: "jordan+newsletter@x.com") == "Jordan")
    }

    @Test("Case and whitespace are normalized")
    func normalization() {
        #expect(NameInference.suggestedFirstName(from: "  MARIA.Garcia@X.COM ") == "Maria")
    }

    @Test("Role and shared mailboxes never yield a name", arguments: [
        "info@acme.com", "sales@acme.com", "no-reply@acme.com", "support@acme.com",
        "hello@acme.com", "billing@acme.com", "sales.team@acme.com"
    ])
    func roleAddresses(address: String) {
        #expect(NameInference.suggestedFirstName(from: address) == nil)
    }

    @Test("Gibberish and initials are rejected", arguments: [
        "xkcd@x.com", "qwrtz@x.com", "a@x.com", "12345@x.com", "x1y2@x.com"
    ])
    func gibberish(address: String) {
        #expect(NameInference.suggestedFirstName(from: address) == nil)
    }

    @Test("A malformed address yields nil")
    func malformed() {
        #expect(NameInference.suggestedFirstName(from: "not-an-email") == nil)
        #expect(NameInference.suggestedFirstName(from: "") == nil)
    }

    @Test("Common-name membership is reported for high-confidence UX")
    func commonNames() {
        #expect(NameInference.isCommonName("Jordan"))
        #expect(!NameInference.isCommonName("Zzyzx"))
    }
}
