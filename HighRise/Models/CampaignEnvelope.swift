import Foundation

/// Campaign-wide CC / BCC settings applied to every message in a run.
///
/// The `cc` and `bcc` fields are address lists that may reference merge fields —
/// `{{Manager Email}}`, or a literal `boss@acme.com`, or several separated by
/// commas/semicolons — so "CC each student's parent" is just a `{{Parent Email}}`
/// in `cc`. `bccSelf` is a fixed address BCC'd on every message, the
/// privacy-respecting way to keep a delivery record without any tracking pixel.
///
/// Resolution and validation happen in the coordinator via
/// `TemplateMergeEngine.resolvePlaceholders` + `EmailValidator`; this model just
/// holds the raw user input.
///
/// The do-not-contact list applies here too. A CC/BCC address is still an
/// address the app puts a message in front of, and a campaign-wide CC is worse
/// than a single To: row — an unfiltered `{{Manager Email}}` reaches the same
/// suppressed person once per recipient in the run. Suppressed addresses are
/// dropped from the envelope rather than blocking the row: the To: recipient
/// did nothing wrong, so the message still goes, minus the address that opted
/// out. `suppressedAddresses(for:isSuppressed:)` reports what was dropped so
/// the Send screen can say so rather than silently changing what the user asked
/// for.
struct CampaignEnvelope: Equatable, Codable {
    /// CC recipients, comma/semicolon-separated, may contain `{{Field}}`.
    var cc: String = ""
    /// BCC recipients, comma/semicolon-separated, may contain `{{Field}}`.
    var bcc: String = ""
    /// A single address BCC'd on every message as the sender's delivery record.
    var bccSelf: String = ""

    var isEmpty: Bool {
        cc.trimmingCharacters(in: .whitespaces).isEmpty &&
        bcc.trimmingCharacters(in: .whitespaces).isEmpty &&
        bccSelf.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Everything one contact's envelope resolves to: the addresses that will be
    /// used, and the ones the do-not-contact list removed.
    struct Resolution: Equatable {
        var cc: [String] = []
        var bcc: [String] = []
        /// Valid addresses that were dropped because they're suppressed, in the
        /// order they appeared, de-duplicated across CC and BCC together.
        var suppressed: [String] = []
    }

    /// Resolves this envelope's CC/BCC address lists for one contact: merges any
    /// `{{Field}}` references, splits on commas/semicolons, trims, keeps only
    /// syntactically valid addresses, drops any the do-not-contact list covers,
    /// and de-duplicates while preserving order. `bccSelf` (when valid and not
    /// suppressed) is always appended to the BCC list.
    ///
    /// `isSuppressed` defaults to "nothing is suppressed" so a caller that has
    /// no list — a preview, a test — behaves exactly as before.
    func resolve(for contact: Contact,
                 isSuppressed: (String) -> Bool = { _ in false }) -> Resolution {
        var result = Resolution()
        var seenSuppressed = Set<String>()

        func addresses(_ raw: String) -> [String] {
            let merged = TemplateMergeEngine.resolvePlaceholders(in: raw, with: contact)
            var seen = Set<String>()
            var kept: [String] = []
            for piece in merged.split(whereSeparator: { $0 == "," || $0 == ";" }) {
                let address = piece.trimmingCharacters(in: .whitespaces)
                guard EmailValidator.isValid(address) else { continue }
                let key = address.lowercased()
                guard !isSuppressed(address) else {
                    // Report each suppressed address once per contact, however
                    // many times it appears across CC and BCC.
                    if seenSuppressed.insert(key).inserted { result.suppressed.append(address) }
                    continue
                }
                if seen.insert(key).inserted { kept.append(address) }
            }
            return kept
        }

        result.cc = addresses(cc)
        var bccList = addresses(bcc)
        let selfAddress = bccSelf.trimmingCharacters(in: .whitespaces)
        if EmailValidator.isValid(selfAddress) {
            if isSuppressed(selfAddress) {
                if seenSuppressed.insert(selfAddress.lowercased()).inserted {
                    result.suppressed.append(selfAddress)
                }
            } else if !bccList.contains(where: { $0.lowercased() == selfAddress.lowercased() }) {
                bccList.append(selfAddress)
            }
        }
        result.bcc = bccList
        return result
    }

    /// The addresses that will actually be used, with suppressed ones removed.
    func resolved(for contact: Contact,
                  isSuppressed: (String) -> Bool = { _ in false }) -> (cc: [String], bcc: [String]) {
        let resolution = resolve(for: contact, isSuppressed: isSuppressed)
        return (resolution.cc, resolution.bcc)
    }

    /// The valid CC/BCC addresses the do-not-contact list removed for this
    /// contact — what the Send screen warns about before anything goes out.
    func suppressedAddresses(for contact: Contact,
                             isSuppressed: (String) -> Bool) -> [String] {
        resolve(for: contact, isSuppressed: isSuppressed).suppressed
    }
}
