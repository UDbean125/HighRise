import Foundation

/// Builds a friendly inline preview of who a run is going to — "Jordan Avery,
/// Alex Kim + 40 more" — so the Send pre-flight can show *whom* you're about to
/// email, not just how many. Pure and deterministic; the truncation and the
/// natural-language joining ("and" vs "+ N more") are unit-tested.
enum RecipientPreview {

    /// A one-line preview of `names`, showing at most `max` before collapsing
    /// the rest into "+ N more". Blank names are ignored.
    static func summary(_ names: [String], max: Int = 3) -> String {
        let cleaned = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "No recipients yet" }

        if cleaned.count <= max {
            return naturalList(cleaned)
        }
        let shown = cleaned.prefix(max).joined(separator: ", ")
        return "\(shown) + \(cleaned.count - max) more"
    }

    /// "A" · "A and B" · "A, B and C" — an Oxford-free natural list.
    private static func naturalList(_ items: [String]) -> String {
        switch items.count {
        case 0:  return ""
        case 1:  return items[0]
        case 2:  return "\(items[0]) and \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head) and \(items[items.count - 1])"
        }
    }
}
