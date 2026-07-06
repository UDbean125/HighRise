import Foundation

/// A pure snapshot of an imported list's data quality: how many addresses are
/// usable, how many rows repeat, and how completely each column is filled in.
/// Powers the Contacts screen's "List health" rail — better data means better
/// personalization, so problems are surfaced before Review blocks rows.
struct ListHealth {

    /// Fill rate for one column: how many rows have a non-blank value.
    struct ColumnFill: Identifiable {
        var id: String { column }
        let column: String
        let filled: Int
        let total: Int

        /// 0…1 share of rows with a value in this column.
        var rate: Double { total == 0 ? 0 : Double(filled) / Double(total) }
    }

    let total: Int
    let validEmails: Int
    let invalidEmails: Int
    let duplicates: Int
    /// One entry per imported header, least-filled first so the columns that
    /// need attention surface at the top.
    let columnFill: [ColumnFill]

    var hasIssues: Bool { invalidEmails > 0 || duplicates > 0 }

    /// Assesses `contacts` against the imported `headers`.
    static func assess(contacts: [Contact], headers: [String]) -> ListHealth {
        let valid = contacts.filter { EmailValidator.isValid($0.email) }.count
        let duplicates = DuplicateDetector.duplicateIDs(in: contacts).count

        let fills = headers.map { header in
            let filled = contacts.filter { contact in
                guard let value = contact.value(for: header) else { return false }
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
            return ColumnFill(column: header, filled: filled, total: contacts.count)
        }
        .sorted { ($0.rate, $0.column) < ($1.rate, $1.column) }

        return ListHealth(total: contacts.count,
                          validEmails: valid,
                          invalidEmails: contacts.count - valid,
                          duplicates: duplicates,
                          columnFill: fills)
    }
}
