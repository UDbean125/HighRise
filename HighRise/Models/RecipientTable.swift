import Foundation

/// A source-agnostic tabular representation of a recipient list.
///
/// Every importer — CSV, Excel, Word/PDF, Apple Contacts, Outlook — reduces its
/// input to this same shape: a header row plus data rows. That lets one
/// pipeline (`CSVParser.contacts`, email-column detection, the preview table,
/// the merge engine) serve every source without special-casing.
struct RecipientTable: Equatable {
    /// Column headers, in order, original casing preserved.
    let headers: [String]
    /// Data rows; each is padded/truncated to `headers.count` on access.
    let rows: [[String]]

    init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }
}
