import Foundation

/// A pure breakdown of an imported list by email domain — the top domains plus
/// an "other" bucket — so the Contacts list-health rail can show at a glance
/// whether a list is mostly Gmail, a single company, or a broad mix (which
/// affects deliverability and which sending account makes sense).
struct EmailDomainStats: Equatable {

    struct Entry: Identifiable, Equatable {
        var id: String { domain }
        let domain: String
        let count: Int
    }

    /// Top `topN` domains by count, then a single "other" entry for the tail.
    let entries: [Entry]
    /// Total recipients with a usable domain (blank/invalid addresses excluded).
    let total: Int

    /// The lowercased domain after the last `@`, or nil when there isn't one.
    static func domain(of email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let at = trimmed.lastIndex(of: "@") else { return nil }
        let domain = String(trimmed[trimmed.index(after: at)...])
        return domain.isEmpty ? nil : domain
    }

    static func of(_ contacts: [Contact], topN: Int = 5) -> EmailDomainStats {
        var counts: [String: Int] = [:]
        var total = 0
        for contact in contacts {
            guard let domain = domain(of: contact.email) else { continue }
            counts[domain, default: 0] += 1
            total += 1
        }
        // Count descending, then domain ascending for a stable order.
        let sorted = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }

        var entries = sorted.prefix(topN).map { Entry(domain: $0.key, count: $0.value) }
        let otherCount = sorted.dropFirst(topN).reduce(0) { $0 + $1.value }
        if otherCount > 0 {
            entries.append(Entry(domain: "other", count: otherCount))
        }
        return EmailDomainStats(entries: entries, total: total)
    }
}
