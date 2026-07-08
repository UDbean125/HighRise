import Foundation

/// Groups the held-back recipients by *why* they're held, so the Review stage
/// can show a breakdown ("3 missing merge data · 1 duplicate") instead of a
/// single opaque "held back" count. Reuses `PreSendReport`'s categorization so
/// the on-screen tally and the exported report can never disagree. Pure and
/// deterministic; the grouping and ordering are unit-tested.
enum HeldReasons {

    struct Entry: Identifiable, Equatable {
        let category: PreSendReport.Block
        let count: Int
        var id: String { category.rawValue }
        var label: String { category.rawValue }
    }

    /// The canonical display order — the same priority `PreSendReport.category`
    /// resolves in, so the most fundamental problem (a bad address) shows first.
    static let order: [PreSendReport.Block] =
        [.invalidEmail, .suppressed, .missingData, .missingAttachment, .duplicate]

    /// Held recipients grouped by category, in `order`, dropping empty buckets.
    static func tally(_ previews: [MergePreview]) -> [Entry] {
        var counts: [PreSendReport.Block: Int] = [:]
        for preview in previews {
            if let category = PreSendReport.category(of: preview) {
                counts[category, default: 0] += 1
            }
        }
        return order.compactMap { category in
            guard let count = counts[category], count > 0 else { return nil }
            return Entry(category: category, count: count)
        }
    }

    /// Total held recipients across all reasons.
    static func total(_ entries: [Entry]) -> Int {
        entries.reduce(0) { $0 + $1.count }
    }
}
