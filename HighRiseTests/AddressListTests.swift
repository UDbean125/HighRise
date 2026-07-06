import Testing
@testable import HighRise

/// The CC/BCC summary flags a typo'd address before a whole run goes out with a
/// bad copy line, so its parsing, placeholder handling, and validation are
/// pinned.
struct AddressListTests {

    @Test("Counts comma-separated entries, trimming and dropping blanks")
    func counts() {
        let s = AddressList.summarize(" a@b.com , c@d.com ,, e@f.com ")
        #expect(s.total == 3)
        #expect(s.placeholders == 0)
        #expect(s.invalid.isEmpty)
    }

    @Test("Placeholder entries are counted but not validated now")
    func placeholders() {
        let s = AddressList.summarize("{{Manager Email}}, boss@corp.com")
        #expect(s.total == 2)
        #expect(s.placeholders == 1)
        #expect(s.invalid.isEmpty)   // the {{…}} isn't judged invalid
    }

    @Test("Invalid fixed addresses are collected")
    func invalid() {
        let s = AddressList.summarize("good@x.com, not-an-email, also bad")
        #expect(s.total == 3)
        #expect(s.hasInvalid)
        #expect(s.invalid.contains("not-an-email"))
        #expect(s.invalid.contains("also bad"))
    }

    @Test("An empty field summarizes to nothing")
    func empty() {
        let s = AddressList.summarize("   ,  , ")
        #expect(s.total == 0)
        #expect(AddressList.caption(s) == nil)
    }

    @Test("Caption pluralizes and appends the invalid count")
    func caption() {
        #expect(AddressList.caption(AddressList.summarize("a@b.com")) == "1 address")
        #expect(AddressList.caption(AddressList.summarize("a@b.com, c@d.com")) == "2 addresses")
        #expect(AddressList.caption(AddressList.summarize("a@b.com, nope")) == "2 addresses · 1 invalid")
    }
}
