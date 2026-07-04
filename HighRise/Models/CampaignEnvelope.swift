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
struct CampaignEnvelope: Equatable {
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

    /// Resolves this envelope's CC/BCC address lists for one contact: merges any
    /// `{{Field}}` references, splits on commas/semicolons, trims, keeps only
    /// syntactically valid addresses, and de-duplicates while preserving order.
    /// `bccSelf` (when valid) is always appended to the BCC list.
    func resolved(for contact: Contact) -> (cc: [String], bcc: [String]) {
        func addresses(_ raw: String) -> [String] {
            let merged = TemplateMergeEngine.resolvePlaceholders(in: raw, with: contact)
            var seen = Set<String>()
            var result: [String] = []
            for piece in merged.split(whereSeparator: { $0 == "," || $0 == ";" }) {
                let address = piece.trimmingCharacters(in: .whitespaces)
                guard EmailValidator.isValid(address) else { continue }
                let key = address.lowercased()
                if seen.insert(key).inserted { result.append(address) }
            }
            return result
        }

        var bccList = addresses(bcc)
        let selfAddress = bccSelf.trimmingCharacters(in: .whitespaces)
        if EmailValidator.isValid(selfAddress),
           !bccList.contains(where: { $0.lowercased() == selfAddress.lowercased() }) {
            bccList.append(selfAddress)
        }
        return (addresses(cc), bccList)
    }
}
