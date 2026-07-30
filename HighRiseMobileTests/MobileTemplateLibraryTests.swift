import XCTest
@testable import HighRiseMobile

/// The iPhone can now save your own templates, using the very same library
/// type the Mac uses — so a template saved on one reads correctly on the
/// other. These pin the coordinator-level behavior.
@MainActor
final class MobileTemplateLibraryTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MobileLibraryTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeCoordinator() -> MobileCoordinator {
        MobileCoordinator(sessionStore: MobileSessionStore(directory: nil),
                          library: TemplateLibraryStore(directory: directory))
    }

    func testSavingATemplateMakesItAvailableAfterRelaunch() {
        let first = makeCoordinator()
        first.template = EmailTemplate(subject: "Spring hello {{First Name}}",
                                       body: "Hi {{First Name|there}},")
        first.saveCurrentTemplate(as: "Spring outreach")
        XCTAssertEqual(first.savedTemplates.count, 1)

        let second = makeCoordinator()
        XCTAssertEqual(second.savedTemplates.first?.name, "Spring outreach")
        XCTAssertEqual(second.savedTemplates.first?.template.subject, "Spring hello {{First Name}}")
    }

    func testLoadingASavedTemplateReplacesTheWorkingDraft() {
        let coordinator = makeCoordinator()
        coordinator.template = EmailTemplate(subject: "First", body: "Body one")
        coordinator.saveCurrentTemplate(as: "Keeper")
        coordinator.template = EmailTemplate(subject: "Something else", body: "Body two")

        guard let saved = coordinator.savedTemplates.first else { return XCTFail("nothing saved") }
        coordinator.loadTemplate(saved)
        XCTAssertEqual(coordinator.template.subject, "First")
    }

    func testSavingUnderAnExistingNameReplacesRatherThanDuplicates() {
        let coordinator = makeCoordinator()
        coordinator.template = EmailTemplate(subject: "Version one", body: "Body")
        coordinator.saveCurrentTemplate(as: "Outreach")
        coordinator.template = EmailTemplate(subject: "Version two", body: "Body")
        coordinator.saveCurrentTemplate(as: "Outreach")

        XCTAssertEqual(coordinator.savedTemplates.count, 1, "same name must overwrite")
        XCTAssertEqual(coordinator.savedTemplates.first?.template.subject, "Version two")
    }

    func testDeletingRemovesItEverywhere() {
        let first = makeCoordinator()
        first.template = EmailTemplate(subject: "Doomed", body: "Body")
        first.saveCurrentTemplate(as: "Doomed")
        guard let saved = first.savedTemplates.first else { return XCTFail("nothing saved") }
        first.deleteTemplate(saved)
        XCTAssertTrue(first.savedTemplates.isEmpty)

        XCTAssertTrue(makeCoordinator().savedTemplates.isEmpty, "delete must persist")
    }

    func testBlankNamesAndEmptyDraftsAreRejected() {
        let coordinator = makeCoordinator()
        coordinator.template = EmailTemplate(subject: "Something", body: "Body")
        coordinator.saveCurrentTemplate(as: "   ")
        XCTAssertTrue(coordinator.savedTemplates.isEmpty, "a blank name must not save")

        let empty = makeCoordinator()
        XCTAssertFalse(empty.canSaveTemplate, "an empty draft is not worth saving")
    }
}
