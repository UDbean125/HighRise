import Foundation

/// What the iPhone app needs to remember between launches.
///
/// iOS terminates backgrounded apps routinely — the user doesn't choose it
/// and gets no warning — so without this, switching to Mail to check
/// something could throw away an imported list and a half-written template.
/// The Mac solved the same problem for quit-on-window-close (`SessionStore`);
/// this is the iOS counterpart, deliberately smaller because the mobile
/// coordinator holds less: no CC/BCC envelope, no cleanup suggestions, no
/// scheduled send.
///
/// Contacts and previews are *not* stored — they re-derive exactly by
/// replaying the raw table and the accepted fills through `ImportPipeline`,
/// the same funnel a live import uses.
struct MobileSessionSnapshot: Codable, Equatable {
    var rawTable: RecipientTable?
    var sourceLabel = ""
    var appliedFills: [ContactDataFiller.Proposal] = []
    var template = EmailTemplate()

    var isEmpty: Bool {
        rawTable == nil
            && template.subject.isEmpty
            && template.body.isEmpty
    }
}

/// JSON persistence for `MobileSessionSnapshot`, following the same pattern
/// as the Mac's stores: atomic writes, silent failure (a session that can't
/// be saved must never break the live one), and an injectable directory
/// (`nil` → inert) so tests never touch the real container.
final class MobileSessionStore {

    private let url: URL?

    init(directory: URL? = MobileSessionStore.defaultDirectory) {
        url = directory?.appendingPathComponent("session.json")
    }

    /// Application Support inside the app's own container.
    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("HighRise")
    }

    func save(_ snapshot: MobileSessionSnapshot) {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func load() -> MobileSessionSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MobileSessionSnapshot.self, from: data)
    }

    func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
