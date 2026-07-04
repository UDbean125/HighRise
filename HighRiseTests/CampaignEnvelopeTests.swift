import Testing
@testable import HighRise

/// The envelope turns raw CC/BCC input (which may reference columns) into
/// validated address lists. Getting this wrong either drops a legitimate CC or
/// leaks the wrong address, so the resolution rules are pinned here.
struct CampaignEnvelopeTests {

    private func contact(_ fields: [String: String], email: String = "to@x.com") -> Contact {
        Contact(fields: fields, email: email)
    }

    @Test("Merge-field references in CC/BCC resolve against the contact")
    func resolvesPlaceholders() {
        let envelope = CampaignEnvelope(cc: "{{Manager Email}}", bcc: "")
        let (cc, _) = envelope.resolved(for: contact(["Manager Email": "boss@acme.com"]))
        #expect(cc == ["boss@acme.com"])
    }

    @Test("Comma- and semicolon-separated lists split, trim, and validate")
    func splitsAndValidates() {
        let envelope = CampaignEnvelope(cc: "one@x.com, two@x.com; not-an-email ;three@x.com")
        let (cc, _) = envelope.resolved(for: contact([:]))
        #expect(cc == ["one@x.com", "two@x.com", "three@x.com"])
    }

    @Test("Duplicate addresses are removed case-insensitively, order preserved")
    func deduplicates() {
        let envelope = CampaignEnvelope(cc: "a@x.com, A@X.com, b@x.com")
        let (cc, _) = envelope.resolved(for: contact([:]))
        #expect(cc == ["a@x.com", "b@x.com"])
    }

    @Test("bccSelf is always appended to BCC when valid")
    func bccSelfAppended() {
        let envelope = CampaignEnvelope(bcc: "list@x.com", bccSelf: "me@x.com")
        let (_, bcc) = envelope.resolved(for: contact([:]))
        #expect(bcc == ["list@x.com", "me@x.com"])
    }

    @Test("bccSelf isn't duplicated if already present in BCC")
    func bccSelfNotDuplicated() {
        let envelope = CampaignEnvelope(bcc: "me@x.com", bccSelf: "ME@x.com")
        let (_, bcc) = envelope.resolved(for: contact([:]))
        #expect(bcc == ["me@x.com"])
    }

    @Test("An unresolved field with no fallback yields no CC, not a broken address")
    func missingFieldDropsQuietly() {
        let envelope = CampaignEnvelope(cc: "{{Manager Email}}")
        let (cc, _) = envelope.resolved(for: contact([:]))  // no Manager Email column
        #expect(cc.isEmpty)
    }

    @Test("An empty envelope reports empty and resolves to nothing")
    func emptyEnvelope() {
        let envelope = CampaignEnvelope()
        #expect(envelope.isEmpty)
        let (cc, bcc) = envelope.resolved(for: contact([:]))
        #expect(cc.isEmpty && bcc.isEmpty)
    }
}
