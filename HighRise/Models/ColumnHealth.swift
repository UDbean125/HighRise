import Foundation

/// Column-level data-quality checks for an imported list. Because the importer
/// keys each contact's fields by header name, two columns sharing a name (even
/// with different casing) silently collapse — only the last one survives. The
/// list-health rail flags that so it isn't discovered mid-merge.
enum ColumnHealth {

    /// Header names that appear more than once, compared case-insensitively and
    /// ignoring surrounding whitespace. Returned in first-seen order using the
    /// first occurrence's display form; blank headers are ignored.
    static func duplicateHeaders(_ headers: [String]) -> [String] {
        var order: [String] = []              // lowercased keys, first-seen order
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]

        for raw in headers {
            let name = raw.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            if counts[key] == nil {
                order.append(key)
                display[key] = name
            }
            counts[key, default: 0] += 1
        }

        return order.filter { counts[$0, default: 0] > 1 }.map { display[$0, default: $0] }
    }
}
