import Foundation

/// The heavy, pure computation behind every fresh import: clean the raw
/// table, resolve the email column (auto-detecting unless one is already
/// chosen), compute cleanup suggestions, build contacts, and note skipped
/// rows.
///
/// Deliberately a free function, not a method on the `@MainActor`
/// `HighRiseCoordinator` — a real CRM export can be 100,000+ rows and this
/// pass is O(rows × columns), so running it on the main thread makes the
/// app look frozen (or crashed) for the many seconds it takes. Callers run
/// this off the main thread (see `HighRiseCoordinator.ingest`) and apply the
/// `Result` back on the coordinator afterward.
enum ImportPipeline {
    struct Result {
        let importedHeaders: [String]
        let attachmentColumn: String?
        let emailColumn: String?
        let cleanupReport: ImportCleaner.Report
        let cleanupSuggestions: [ImportCleaner.Suggestion]
        let fillProposals: [ContactDataFiller.Proposal]
        let parsedTable: RecipientTable
        let contacts: [Contact]
        let skippedRows: [CSVParser.SkippedRow]
        let importSummary: String
    }

    static func run(table: RecipientTable, sourceLabel: String, cleanupEnabled: Bool,
                    appliedSuggestions: [ImportCleaner.Suggestion],
                    appliedFills: [ContactDataFiller.Proposal] = [],
                    emailColumnOverride: String?) -> Result {
        let parsedTable: RecipientTable
        let cleanupReport: ImportCleaner.Report
        var cleanupSuggestions: [ImportCleaner.Suggestion] = []
        var fillProposals: [ContactDataFiller.Proposal] = []

        if cleanupEnabled {
            let (cleaned, report) = ImportCleaner.autoClean(table, emailColumn: emailColumnOverride)
            var working = cleaned
            for suggestion in appliedSuggestions {
                working = ImportCleaner.apply(suggestion, to: working).table
            }
            // Fills run after cleanup and accepted suggestions, on the email
            // column as resolved against the cleaned table.
            let resolvedEmail = emailColumnOverride ?? CSVParser.detectEmailColumn(in: working)
            for fill in appliedFills {
                working = ContactDataFiller.apply(fill, to: working, emailColumn: resolvedEmail).table
            }
            parsedTable = working
            cleanupReport = report
            cleanupSuggestions = ImportCleaner.suggestions(for: working, emailColumn: emailColumnOverride)
            fillProposals = ContactDataFiller.proposals(for: working, emailColumn: resolvedEmail)
        } else {
            parsedTable = table
            cleanupReport = .empty
        }

        let importedHeaders = parsedTable.headers
        let attachmentColumn = detectAttachmentColumn(in: importedHeaders)
        let emailColumn = emailColumnOverride ?? CSVParser.detectEmailColumn(in: parsedTable)
        let (contacts, _) = CSVParser.contacts(from: parsedTable, emailHeader: emailColumn)
        let skippedRows = CSVParser.skippedRows(from: parsedTable, emailHeader: emailColumn)

        let summary = Self.summary(sourceLabel: sourceLabel, contacts: contacts.count,
                                   tableRows: parsedTable.rows.count, emailColumn: emailColumn,
                                   cleanupFixes: cleanupReport.totalFixes)

        return Result(importedHeaders: importedHeaders, attachmentColumn: attachmentColumn,
                      emailColumn: emailColumn, cleanupReport: cleanupReport,
                      cleanupSuggestions: cleanupSuggestions, fillProposals: fillProposals,
                      parsedTable: parsedTable,
                      contacts: contacts, skippedRows: skippedRows, importSummary: summary)
    }

    /// The one-line import summary shown above the preview. Extracted so the
    /// coordinator can rebuild it when the user re-picks the email column —
    /// the summary must always name the column actually in use, not the one
    /// detected at import time.
    static func summary(sourceLabel: String, contacts: Int, tableRows: Int,
                        emailColumn: String?, cleanupFixes: Int) -> String {
        let skipped = max(0, tableRows - contacts)
        var summary = "Imported \(contacts) contact\(contacts == 1 ? "" : "s") from \(sourceLabel)"
        if let emailColumn { summary += " · email column: “\(emailColumn)”" }
        if skipped > 0 { summary += " · \(skipped) row\(skipped == 1 ? "" : "s") skipped (no email)" }
        if cleanupFixes > 0 {
            summary += " · \(cleanupFixes) value\(cleanupFixes == 1 ? "" : "s") auto-cleaned"
        }
        return summary
    }

    /// Guesses an attachment column from the headers (a column named
    /// "attachment"/"attachments"/"file"/"files"), else nil.
    static func detectAttachmentColumn(in headers: [String]) -> String? {
        headers.first {
            let h = $0.lowercased()
            return h == "attachment" || h == "attachments" || h == "file" || h == "files"
        }
    }
}
