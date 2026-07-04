import Foundation

/// Finds recipients that share an email address so the same person isn't mailed
/// twice from one merge.
///
/// Pure and list-aware: the whole contact array is needed to know which rows
/// repeat, which is why this lives here rather than in the per-contact merge.
/// Matching mirrors `Contact.value(for:)` — case- and whitespace-insensitive —
/// so `Ada@Example.com ` and `ada@example.com` count as the same person.
enum DuplicateDetector {

    /// The ids of every contact whose address already appeared earlier in the
    /// list. The first occurrence of each address is kept (not returned); all
    /// later repeats are. Blank addresses are ignored — a missing email is a
    /// separate blocking reason, not a duplicate.
    static func duplicateIDs(in contacts: [Contact]) -> Set<UUID> {
        var seen = Set<String>()
        var duplicates = Set<UUID>()
        for contact in contacts {
            let key = contact.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            if seen.contains(key) {
                duplicates.insert(contact.id)
            } else {
                seen.insert(key)
            }
        }
        return duplicates
    }
}
