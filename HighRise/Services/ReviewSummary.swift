import Foundation

/// A glanceable, one-look summary of the Review stage: how many recipients were
/// merged, how many are ready to send, how many are held back, and across how
/// many distinct domains the outgoing mail spreads. Pure and deterministic, so
/// the counting rules and wording are unit-tested and the view just renders it.
enum ReviewSummary {

    struct Summary: Equatable {
        /// Every merged recipient, ready or held.
        var total = 0
        /// Recipients that will actually send (`isSendable`).
        var ready = 0
        /// Recipients held back for any reason (invalid address, missing data,
        /// duplicate, suppressed, missing attachment).
        var held = 0
        /// Distinct email domains among the *ready* recipients — the spread of
        /// where mail is actually going. A single-company list reads "1 domain";
        /// a broad consumer list reads many.
        var domains = 0
    }

    static func of(_ previews: [MergePreview]) -> Summary {
        var summary = Summary()
        var readyDomains = Set<String>()
        for preview in previews {
            summary.total += 1
            if preview.isSendable {
                summary.ready += 1
                if let domain = EmailDomainStats.domain(of: preview.contact.email) {
                    readyDomains.insert(domain)
                }
            } else {
                summary.held += 1
            }
        }
        summary.domains = readyDomains.count
        return summary
    }

    /// A compact one-line headline — e.g. "42 recipients · 5 domains · 38 ready".
    /// The domain clause is dropped when nothing is ready (there are no outgoing
    /// domains to count), and empty input yields a friendly placeholder.
    static func line(_ previews: [MergePreview]) -> String {
        let s = of(previews)
        guard s.total > 0 else { return "No recipients yet" }

        var parts = ["\(s.total) recipient\(s.total == 1 ? "" : "s")"]
        if s.domains > 0 {
            parts.append("\(s.domains) domain\(s.domains == 1 ? "" : "s")")
        }
        parts.append("\(s.ready) ready")
        return parts.joined(separator: " · ")
    }
}
