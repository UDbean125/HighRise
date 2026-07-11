import Testing
import Foundation
@testable import HighRise

/// `ImportPipeline.run` is the pure, off-main-thread heavy lifting behind
/// every import (see its doc comment) — pinned directly here so it can be
/// tested without spinning up a coordinator or touching the main actor.
struct ImportPipelineTests {

    @Test("Builds contacts, resolves the email column, and writes a summary")
    func basicRun() throws {
        let table = try CSVParser.parse("Name,Email\nAda,ada@example.com\nGrace,grace@example.com")
        let result = ImportPipeline.run(table: table, sourceLabel: "test.csv",
                                        cleanupEnabled: true, appliedSuggestions: [],
                                        emailColumnOverride: nil)
        #expect(result.emailColumn == "Email")
        #expect(result.contacts.count == 2)
        #expect(result.skippedRows.isEmpty)
        #expect(result.importSummary.contains("Imported 2 contacts from test.csv"))
        #expect(result.importSummary.contains("email column: \u{201C}Email\u{201D}"))
    }

    @Test("Rows with no value in the resolved email column are skipped and named")
    func skipsAndNamesRowsWithNoEmail() throws {
        let table = try CSVParser.parse("Name,Email\nAda,ada@example.com\nNoEmail,")
        let result = ImportPipeline.run(table: table, sourceLabel: "test.csv",
                                        cleanupEnabled: true, appliedSuggestions: [],
                                        emailColumnOverride: nil)
        #expect(result.contacts.count == 1)
        #expect(result.skippedRows.count == 1)
        #expect(result.importSummary.contains("1 row skipped (no email)"))
    }

    @Test("cleanupEnabled false skips cleanup but still builds contacts")
    func cleanupDisabled() throws {
        let table = try CSVParser.parse("Name,Email\nAda,  ada@example.com  ")
        let result = ImportPipeline.run(table: table, sourceLabel: "test.csv",
                                        cleanupEnabled: false, appliedSuggestions: [],
                                        emailColumnOverride: nil)
        #expect(result.cleanupReport.totalFixes == 0)
        #expect(result.contacts.count == 1)   // CSVParser.contacts trims regardless of cleanup
    }

    @Test("An explicit emailColumnOverride is honored over auto-detection")
    func honorsExplicitColumn() throws {
        let table = try CSVParser.parse("Name,Email,Backup Email\nAda,ada@example.com,backup@example.com")
        let result = ImportPipeline.run(table: table, sourceLabel: "test.csv",
                                        cleanupEnabled: true, appliedSuggestions: [],
                                        emailColumnOverride: "Backup Email")
        #expect(result.emailColumn == "Backup Email")
        #expect(result.contacts.first?.email == "backup@example.com")
    }

    @Test("Guesses the attachment column from its header name")
    func detectsAttachmentColumn() {
        #expect(ImportPipeline.detectAttachmentColumn(in: ["Name", "Email", "Attachments"]) == "Attachments")
        #expect(ImportPipeline.detectAttachmentColumn(in: ["Name", "Email"]) == nil)
    }
}
