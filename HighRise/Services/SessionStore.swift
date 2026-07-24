import Foundation

/// Everything the working session holds beyond the template draft (which
/// `TemplateLibraryStore`'s autosave already preserves): the imported
/// recipient table, column choices, the cleanup/fill decisions the user
/// accepted, campaign settings, and any pending scheduled send.
///
/// Closing the window quits the app (the App Review-approved behavior for
/// this single-window app), so this snapshot is what makes that quit
/// lossless: contacts are *not* stored — they re-derive deterministically by
/// replaying `rawTable` + decisions through `ImportPipeline.run`, exactly as
/// a live re-map does.
struct SessionSnapshot: Codable, Equatable {
    var rawTable: RecipientTable?
    var importSourceLabel: String?
    var emailColumn: String?
    var nameColumn: String?
    var attachmentColumn: String?
    var cleanupEnabled = true
    var appliedSuggestions: [ImportCleaner.Suggestion] = []
    var appliedFills: [ContactDataFiller.Proposal] = []

    var envelope = CampaignEnvelope()
    /// Stored as raw strings, not the enums: the Outlook case doesn't exist
    /// in the MAS build, and a raw string degrades to the default instead of
    /// failing the whole snapshot's decode.
    var selectedClientRaw: String?
    var sendModeRaw: String?
    var senderIdentity = ""
    var unsubscribeEnabled = false
    var unsubscribeReplyTo = ""
    var unsubscribeNote = ""

    /// A pending scheduled send's fire time. The queue itself isn't stored;
    /// on restore the coordinator re-freezes it from the restored list —
    /// identical data in, identical queue out.
    var scheduledFireDate: Date?

    var hasImport: Bool { rawTable != nil }
}

/// JSON persistence for `SessionSnapshot` in Application Support, following
/// `TemplateLibraryStore`'s pattern: atomic writes, silent failure (a session
/// that can't persist must never break the live one), and an injectable
/// directory (`nil` → no-op) so tests never touch the real folder.
final class SessionStore {

    private let url: URL?

    init(directory: URL? = TemplateLibraryStore.defaultDirectory) {
        url = directory?.appendingPathComponent("session.json")
    }

    func save(_ snapshot: SessionSnapshot) {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func load() -> SessionSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
