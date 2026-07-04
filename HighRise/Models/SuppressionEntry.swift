import Foundation

/// One entry on the local do-not-contact list: either a single address or a
/// whole domain that should never be emailed, across every future merge.
///
/// Stored on disk (see `DoNotContactStore`) so opt-outs, ex-clients, and legal
/// do-not-contact requests survive between launches without re-editing CSVs —
/// and entirely on-device, with no suppression list ever leaving the Mac.
struct SuppressionEntry: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case address
        case domain
    }

    let kind: Kind
    /// Normalized (trimmed, lowercased) address or domain.
    let value: String
    let dateAdded: Date
    var note: String?

    /// Stable identity: one entry per kind+value, so adding a duplicate is a no-op.
    var id: String { "\(kind.rawValue):\(value)" }

    /// How this entry reads in the management list.
    var displayLabel: String {
        switch kind {
        case .address: return value
        case .domain:  return "everyone @\(value)"
        }
    }
}
