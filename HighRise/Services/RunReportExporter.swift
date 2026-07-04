import Foundation

/// Turns a send run into a per-recipient results report: who was sent/drafted,
/// who was held back and why, who failed and why. This is the accountability
/// half of campaign reporting — no tracking required — and it exports as CSV so
/// the source list can become the single source of truth (fix the held rows,
/// re-import, run again).
///
/// Pure: it reuses the unit-tested RFC-4180 writer and takes plain data, so the
/// exact output is pinned by tests.
enum RunReportExporter {

    struct Row: Equatable {
        let name: String
        let email: String
        /// "Sent", "Draft created", "Held back", "Failed", "Skipped".
        let status: String
        /// Reason for held/failed/skipped rows; empty for success.
        let detail: String
    }

    /// Builds report rows from a completed run's outcomes plus the rows that were
    /// held back before the run. Sent/drafted/failed come from `outcomes`; the
    /// `blocked` previews contribute "Held back" rows with their blocking reason.
    static func rows(outcomes: [SendOutcome], blocked: [MergePreview]) -> [Row] {
        let sentRows = outcomes.map { outcome -> Row in
            switch outcome.status {
            case .sent:
                return Row(name: outcome.contact.displayName, email: outcome.contact.email,
                           status: "Sent", detail: "")
            case .drafted:
                return Row(name: outcome.contact.displayName, email: outcome.contact.email,
                           status: "Draft created", detail: "")
            case .skipped(let reason):
                return Row(name: outcome.contact.displayName, email: outcome.contact.email,
                           status: "Skipped", detail: reason)
            case .failed(let reason):
                return Row(name: outcome.contact.displayName, email: outcome.contact.email,
                           status: "Failed", detail: reason)
            }
        }
        let heldRows = blocked.map { preview in
            Row(name: preview.contact.displayName, email: preview.contact.email,
                status: "Held back", detail: preview.blockingReason ?? "")
        }
        return sentRows + heldRows
    }

    /// Renders the rows as an RFC-4180 CSV with a header line.
    static func csv(_ rows: [Row]) -> String {
        var out = CSVTemplateExporter.csvLine(["Name", "Email", "Status", "Detail"]) + "\n"
        for row in rows {
            out += CSVTemplateExporter.csvLine([row.name, row.email, row.status, row.detail]) + "\n"
        }
        return out
    }
}
