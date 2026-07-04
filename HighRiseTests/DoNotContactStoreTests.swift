import Testing
import Foundation
@testable import HighRise

/// The do-not-contact list decides whether a real person gets emailed, so its
/// matching, normalization, and persistence are pinned. File I/O uses a temp
/// path (the app is unsandboxed) or an in-memory store (`fileURL: nil`).
struct DoNotContactStoreTests {

    private func memoryStore() -> DoNotContactStore { DoNotContactStore(fileURL: nil) }

    @Test("An added address is matched case- and whitespace-insensitively")
    func matchesAddress() {
        let store = memoryStore()
        #expect(store.addAddress("Ada@Example.com"))
        #expect(store.isSuppressed("ada@example.com"))
        #expect(store.isSuppressed("  ADA@EXAMPLE.COM  "))
        #expect(!store.isSuppressed("other@example.com"))
    }

    @Test("A domain entry suppresses every address at that domain")
    func matchesDomain() {
        let store = memoryStore()
        #expect(store.addDomain("acme.com"))
        #expect(store.isSuppressed("anyone@acme.com"))
        #expect(store.isSuppressed("boss@ACME.com"))
        #expect(!store.isSuppressed("anyone@notacme.com"))
    }

    @Test("A leading @ on a domain is accepted and stripped")
    func domainWithAtPrefix() {
        let store = memoryStore()
        #expect(store.addDomain("@acme.com"))
        #expect(store.isSuppressed("x@acme.com"))
    }

    @Test("Invalid addresses and domains are rejected")
    func rejectsInvalid() {
        let store = memoryStore()
        #expect(!store.addAddress("not-an-email"))
        #expect(!store.addDomain("no-dot"))
        #expect(!store.addDomain("has space.com"))
        #expect(!store.addDomain("a@b.com")) // that's an address, not a domain
        #expect(store.entries.isEmpty)
    }

    @Test("Adding the same entry twice is a no-op")
    func noDuplicates() {
        let store = memoryStore()
        #expect(store.addAddress("a@b.com"))
        #expect(!store.addAddress("A@B.com"))
        #expect(store.entries.count == 1)
    }

    @Test("Removing an entry stops it matching")
    func remove() {
        let store = memoryStore()
        store.addAddress("a@b.com")
        let entry = store.entries[0]
        store.remove(entry)
        #expect(!store.isSuppressed("a@b.com"))
        #expect(store.entries.isEmpty)
    }

    @Test("A blank address is never suppressed")
    func blankNeverSuppressed() {
        let store = memoryStore()
        store.addDomain("acme.com")
        #expect(!store.isSuppressed(""))
        #expect(!store.isSuppressed("   "))
    }

    @Test("Entries persist across store instances at the same file")
    func persistsToDisk() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("highrise-dnc-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let first = DoNotContactStore(fileURL: tmp)
        first.addAddress("keep@me.com")
        first.addDomain("blocked.com")

        // A fresh store reading the same file sees the persisted entries.
        let second = DoNotContactStore(fileURL: tmp)
        #expect(second.entries.count == 2)
        #expect(second.isSuppressed("keep@me.com"))
        #expect(second.isSuppressed("anyone@blocked.com"))
    }
}
