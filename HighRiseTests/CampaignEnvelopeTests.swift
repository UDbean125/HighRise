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

    // MARK: - Do-not-contact list

    /// Suppression is only ever applied by an explicit predicate, so a caller
    /// that doesn't pass one keeps its old behavior exactly.
    @Test("With no suppression predicate, nothing is filtered")
    func noPredicateFiltersNothing() {
        let envelope = CampaignEnvelope(cc: "boss@acme.com")
        let (cc, _) = envelope.resolved(for: contact([:]))
        #expect(cc == ["boss@acme.com"])
    }

    /// The failure mode this guards: a campaign-wide CC would otherwise email a
    /// suppressed person once per recipient in the run.
    @Test("A suppressed CC address is dropped, not emailed")
    func suppressedCCDropped() {
        let envelope = CampaignEnvelope(cc: "boss@acme.com, ok@acme.com")
        let (cc, _) = envelope.resolved(for: contact([:]),
                                        isSuppressed: { $0.lowercased() == "boss@acme.com" })
        #expect(cc == ["ok@acme.com"])
    }

    @Test("A suppressed BCC address is dropped too")
    func suppressedBCCDropped() {
        let envelope = CampaignEnvelope(bcc: "boss@acme.com, ok@acme.com")
        let (_, bcc) = envelope.resolved(for: contact([:]),
                                         isSuppressed: { $0.lowercased() == "boss@acme.com" })
        #expect(bcc == ["ok@acme.com"])
    }

    /// bccSelf takes a separate path through resolution, so it needs its own
    /// coverage — a suppressed sender copy must not slip in at the end.
    @Test("A suppressed bccSelf is not appended")
    func suppressedBCCSelfDropped() {
        let envelope = CampaignEnvelope(bcc: "list@x.com", bccSelf: "me@x.com")
        let (_, bcc) = envelope.resolved(for: contact([:]),
                                         isSuppressed: { $0.lowercased() == "me@x.com" })
        #expect(bcc == ["list@x.com"])
    }

    /// Suppression matching goes through the caller's predicate, which is
    /// `DoNotContactStore.isSuppressed` in the app — this pins that the address
    /// is handed over as written, so case folding is the store's job and a
    /// differently-cased CC can't sneak past.
    @Test("A suppressed address is matched however it's capitalized")
    func suppressionIsCaseInsensitive() {
        let envelope = CampaignEnvelope(cc: "BOSS@Acme.com")
        let (cc, _) = envelope.resolved(for: contact([:]),
                                        isSuppressed: { $0.lowercased() == "boss@acme.com" })
        #expect(cc.isEmpty)
    }

    @Test("A suppressed merge-field CC resolves and is then dropped")
    func suppressedPlaceholderDropped() {
        let envelope = CampaignEnvelope(cc: "{{Manager Email}}")
        let (cc, _) = envelope.resolved(for: contact(["Manager Email": "boss@acme.com"]),
                                        isSuppressed: { $0.lowercased() == "boss@acme.com" })
        #expect(cc.isEmpty)
    }

    @Test("Dropped addresses are reported so the drop isn't silent")
    func reportsWhatItDropped() {
        let envelope = CampaignEnvelope(cc: "boss@acme.com, ok@acme.com")
        let dropped = envelope.suppressedAddresses(for: contact([:]),
                                                   isSuppressed: { $0.lowercased() == "boss@acme.com" })
        #expect(dropped == ["boss@acme.com"])
    }

    @Test("An address suppressed in both CC and BCC is reported once")
    func reportsEachDroppedAddressOnce() {
        let envelope = CampaignEnvelope(cc: "boss@acme.com", bcc: "BOSS@acme.com", bccSelf: "boss@acme.com")
        let dropped = envelope.suppressedAddresses(for: contact([:]),
                                                   isSuppressed: { $0.lowercased() == "boss@acme.com" })
        #expect(dropped == ["boss@acme.com"])
    }

    /// An invalid address is already discarded, so it must not also be counted
    /// as something the do-not-contact list removed.
    @Test("Invalid addresses aren't reported as suppressed")
    func invalidAddressIsNotReportedAsSuppressed() {
        let envelope = CampaignEnvelope(cc: "not-an-email, ok@acme.com")
        let dropped = envelope.suppressedAddresses(for: contact([:]), isSuppressed: { _ in true })
        #expect(dropped == ["ok@acme.com"])
    }

    @Test("Nothing is reported when the envelope is clear of the list")
    func reportsNothingWhenClean() {
        let envelope = CampaignEnvelope(cc: "ok@acme.com", bccSelf: "me@x.com")
        let dropped = envelope.suppressedAddresses(for: contact([:]), isSuppressed: { _ in false })
        #expect(dropped.isEmpty)
    }
}
