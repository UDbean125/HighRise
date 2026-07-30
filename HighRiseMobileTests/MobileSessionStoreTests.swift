import XCTest
@testable import HighRiseMobile

/// iOS terminates backgrounded apps without warning, so the imported list and
/// the working template have to survive a relaunch. These pin the store's
/// round-trip and the coordinator's restore-by-replay.
@MainActor
final class MobileSessionStoreTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MobileSessionTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeCoordinator() -> MobileCoordinator {
        MobileCoordinator(sessionStore: MobileSessionStore(directory: directory))
    }

    private func importSample(into coordinator: MobileCoordinator) {
        coordinator.importCSV(data: Data("""
        First Name,Email,Company
        ,john.smith@acme.com,Acme
        Ada,ada@lovelace.dev,
        """.utf8), sourceLabel: "leads.csv")
    }

    func testSnapshotRoundTripsThroughTheStore() {
        var snapshot = MobileSessionSnapshot()
        snapshot.rawTable = RecipientTable(headers: ["Name", "Email"],
                                           rows: [["Ada", "ada@example.com"]])
        snapshot.sourceLabel = "leads.csv"
        snapshot.template = EmailTemplate(subject: "Hi {{Name}}", body: "Hello")

        let store = MobileSessionStore(directory: directory)
        store.save(snapshot)
        XCTAssertEqual(MobileSessionStore(directory: directory).load(), snapshot)
    }

    func testListAndTemplateSurviveARelaunch() {
        let first = makeCoordinator()
        importSample(into: first)
        first.template = EmailTemplate(subject: "Hi {{First Name}}", body: "Hello there")
        first.saveSession()
        XCTAssertEqual(first.contacts.count, 2)

        // A fresh coordinator is what a relaunch produces.
        let second = makeCoordinator()
        XCTAssertEqual(second.contacts.count, 2, "the imported list must come back")
        XCTAssertEqual(second.template.subject, "Hi {{First Name}}")
        XCTAssertEqual(second.importedHeaders, first.importedHeaders)
        XCTAssertFalse(second.previews.isEmpty, "previews must re-derive on restore")
    }

    func testAcceptedFillsAreReplayedOnRestore() {
        let first = makeCoordinator()
        importSample(into: first)
        guard let fill = first.fillProposals.first(where: { $0.kind == .firstNameFromEmail }) else {
            return XCTFail("expected a first-name-from-email proposal")
        }
        first.applyFillProposal(fill)
        let filled = first.contacts.first { $0.email == "john.smith@acme.com" }?.value(for: "First Name")
        XCTAssertEqual(filled, "John")

        let second = makeCoordinator()
        let restored = second.contacts.first { $0.email == "john.smith@acme.com" }?.value(for: "First Name")
        XCTAssertEqual(restored, "John", "an accepted fill must be re-applied, not lost")
    }

    func testNoSavedSessionLeavesAPristineCoordinator() {
        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator.contacts.isEmpty)
        XCTAssertTrue(coordinator.template.subject.isEmpty)
        XCTAssertNil(coordinator.queue)
    }

    func testClearSessionWipesBothMemoryAndDisk() {
        let first = makeCoordinator()
        importSample(into: first)
        first.template = EmailTemplate(subject: "Subject", body: "Body")
        first.saveSession()

        first.clearSession()
        XCTAssertTrue(first.contacts.isEmpty)
        XCTAssertTrue(first.previews.isEmpty)

        let second = makeCoordinator()
        XCTAssertTrue(second.contacts.isEmpty, "a cleared session must not come back")
    }

    func testAnInertStoreNeverPersists() {
        let coordinator = MobileCoordinator(sessionStore: MobileSessionStore(directory: nil))
        importSample(into: coordinator)
        coordinator.saveSession()
        XCTAssertNil(MobileSessionStore(directory: nil).load())
    }

    func testCorruptSessionFileDegradesToAFreshStart() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json{{{".utf8).write(to: directory.appendingPathComponent("session.json"))

        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator.contacts.isEmpty, "a corrupt session must not crash or half-load")
    }
}
