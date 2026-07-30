import XCTest
@testable import HighRiseMobile

/// The do-not-contact list is a promise: someone who asked not to be emailed
/// must not be emailed, whichever device the list is sent from. Before this,
/// iOS ignored the list entirely and would happily send to a suppressed
/// address. These pin the enforcement.
@MainActor
final class MobileDoNotContactTests: XCTestCase {

    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MobileDNCTests-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    private func makeCoordinator() -> MobileCoordinator {
        MobileCoordinator(sessionStore: MobileSessionStore(directory: nil),
                          library: TemplateLibraryStore(directory: nil),
                          doNotContact: DoNotContactStore(fileURL: fileURL))
    }

    private func importSample(into coordinator: MobileCoordinator) {
        coordinator.importCSV(data: Data("""
        Name,Email
        Ada,ada@example.com
        Grace,grace@navy.mil
        Boss,boss@acme.com
        """.utf8), sourceLabel: "list.csv")
        coordinator.template = EmailTemplate(subject: "Hi {{Name}}", body: "Hello {{Name}}")
        coordinator.refreshPreviews()
    }

    func testSuppressedAddressIsHeldBackFromSending() {
        let coordinator = makeCoordinator()
        importSample(into: coordinator)
        XCTAssertEqual(coordinator.sendableCount, 3)

        XCTAssertTrue(coordinator.suppressAddress("ada@example.com"))

        XCTAssertEqual(coordinator.sendableCount, 2, "a suppressed address must not be sendable")
        XCTAssertEqual(coordinator.suppressedCount, 1)
        let ada = coordinator.previews.first { $0.contact.email == "ada@example.com" }
        XCTAssertEqual(ada?.isSuppressed, true)
        XCTAssertEqual(ada?.isSendable, false)
        // And it never reaches the send queue.
        coordinator.startSendQueue()
        XCTAssertFalse(coordinator.queue?.items.contains { $0.contact.email == "ada@example.com" } ?? true)
    }

    func testSuppressingAWholeDomainHoldsEveryoneThere() {
        let coordinator = makeCoordinator()
        importSample(into: coordinator)
        XCTAssertTrue(coordinator.suppressDomain("acme.com"))
        XCTAssertEqual(coordinator.suppressedCount, 1)
        XCTAssertFalse(coordinator.previews.first { $0.contact.email == "boss@acme.com" }?.isSendable ?? true)
    }

    func testSuppressionSurvivesRelaunchAndAppliesToANewImport() {
        let first = makeCoordinator()
        importSample(into: first)
        XCTAssertTrue(first.suppressAddress("grace@navy.mil"))

        // A brand-new coordinator (relaunch) importing the same list again.
        let second = makeCoordinator()
        importSample(into: second)
        XCTAssertEqual(second.suppressedCount, 1, "the list must persist and re-apply")
        XCTAssertEqual(second.suppressionEntries.count, 1)
    }

    func testUnblockingLetsThemThroughAgain() {
        let coordinator = makeCoordinator()
        importSample(into: coordinator)
        coordinator.suppressAddress("ada@example.com")
        XCTAssertEqual(coordinator.sendableCount, 2)

        guard let entry = coordinator.suppressionEntries.first else { return XCTFail("nothing suppressed") }
        coordinator.removeSuppression(entry)
        XCTAssertEqual(coordinator.sendableCount, 3, "unblocking must restore the recipient")
        XCTAssertEqual(coordinator.suppressedCount, 0)
    }

    func testGarbageInputIsRejected() {
        let coordinator = makeCoordinator()
        XCTAssertFalse(coordinator.suppressAddress("not an email"))
        XCTAssertTrue(coordinator.suppressionEntries.isEmpty)
    }

    func testSuppressingTheSameAddressTwiceIsANoOp() {
        let coordinator = makeCoordinator()
        importSample(into: coordinator)
        XCTAssertTrue(coordinator.suppressAddress("ada@example.com"))
        XCTAssertFalse(coordinator.suppressAddress("ADA@example.com"),
                       "case-insensitive duplicate must not add a second entry")
        XCTAssertEqual(coordinator.suppressionEntries.count, 1)
    }
}
