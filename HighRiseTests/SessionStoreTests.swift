import Testing
import Foundation
@testable import HighRise

/// `SessionStore` is what makes quit-on-close lossless: the working session
/// (imported table, accepted decisions, settings, pending schedule) round-trips
/// through JSON in an injectable directory. These pin the store itself; the
/// coordinator-level replay is covered in `HighRiseCoordinatorSessionTests`.
struct SessionStoreTests {

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)")
    }

    private var sampleSnapshot: SessionSnapshot {
        var snapshot = SessionSnapshot()
        snapshot.rawTable = RecipientTable(
            headers: ["Name", "Email", "Company"],
            rows: [["Ada", "ada@example.com", "Analytical Engines"],
                   ["Grace", "grace@example.com", ""]])
        snapshot.importSourceLabel = "Leads.csv"
        snapshot.emailColumn = "Email"
        snapshot.nameColumn = "Name"
        snapshot.cleanupEnabled = true
        snapshot.appliedSuggestions = [
            .init(kind: .domainTypo, column: "Email", count: 1,
                  examples: [.init(before: "a@gmial.com", after: "a@gmail.com")]),
        ]
        snapshot.appliedFills = [
            .init(kind: .companyFromColleagues, column: "Company", count: 1,
                  examples: [.init(before: "", after: "Analytical Engines")]),
        ]
        snapshot.envelope = {
            var envelope = CampaignEnvelope()
            envelope.cc = "{{Manager Email}}"
            envelope.bccSelf = "me@example.com"
            return envelope
        }()
        snapshot.selectedClientRaw = "Apple Mail"
        snapshot.sendModeRaw = SendMode.draft.rawValue
        snapshot.senderIdentity = "bryan@example.com"
        snapshot.unsubscribeEnabled = true
        snapshot.unsubscribeReplyTo = "unsub@example.com"
        snapshot.scheduledFireDate = Date(timeIntervalSince1970: 2_000_000_000)
        return snapshot
    }

    @Test("A full snapshot round-trips losslessly")
    func roundTrip() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let saved = sampleSnapshot
        store.save(saved)
        let loaded = SessionStore(directory: directory).load()
        #expect(loaded == saved)
    }

    @Test("clear() removes the persisted session")
    func clearRemoves() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        store.save(sampleSnapshot)
        #expect(store.load() != nil)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test("A nil directory makes the store inert: nothing loads, saving is a no-op")
    func nilDirectoryIsInert() {
        let store = SessionStore(directory: nil)
        store.save(sampleSnapshot)
        #expect(store.load() == nil)
    }

    @Test("Loading from an empty directory returns nil, not a crash")
    func missingFileLoadsNil() {
        #expect(SessionStore(directory: temporaryDirectory()).load() == nil)
    }

    @Test("Corrupt JSON on disk degrades to a fresh session")
    func corruptFileLoadsNil() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json{{{".utf8).write(to: directory.appendingPathComponent("session.json"))
        #expect(SessionStore(directory: directory).load() == nil)
    }
}
