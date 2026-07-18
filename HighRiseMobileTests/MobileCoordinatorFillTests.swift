import XCTest
@testable import HighRiseMobile

/// The iOS coordinator surfaces the same missing-data fill proposals the Mac
/// import screen offers, replaying accepted ones through the shared pipeline.
@MainActor
final class MobileCoordinatorFillTests: XCTestCase {

    private func importCSV(_ csv: String, into coordinator: MobileCoordinator) {
        coordinator.importCSV(data: Data(csv.utf8), sourceLabel: "test.csv")
    }

    func testImportOffersFillProposalsForBlankCells() {
        let coordinator = MobileCoordinator()
        importCSV("""
        First Name,Email
        ,john.smith@acme.com
        Ada,ada@lovelace.dev
        """, into: coordinator)

        XCTAssertEqual(coordinator.contacts.count, 2)
        XCTAssertTrue(coordinator.fillProposals.contains { $0.kind == .firstNameFromEmail })
    }

    func testApplyingAFillWritesOnlyTheBlankCellAndClearsTheProposal() {
        let coordinator = MobileCoordinator()
        importCSV("""
        First Name,Email
        ,john.smith@acme.com
        Ada,ada@lovelace.dev
        """, into: coordinator)

        guard let proposal = coordinator.fillProposals.first(where: { $0.kind == .firstNameFromEmail })
        else { return XCTFail("expected a first-name fill proposal") }
        coordinator.applyFillProposal(proposal)

        XCTAssertEqual(coordinator.contacts.first?.value(for: "First Name"), "John")
        XCTAssertEqual(coordinator.contacts.last?.value(for: "First Name"), "Ada")
        XCTAssertFalse(coordinator.fillProposals.contains { $0.kind == .firstNameFromEmail })
    }

    func testFillAllAppliesEveryProposal() {
        let coordinator = MobileCoordinator()
        importCSV("""
        First Name,Company,Email
        ,Acme,sam.patel@acme-corp.com
        """, into: coordinator)

        XCTAssertFalse(coordinator.fillProposals.isEmpty)
        coordinator.applyAllFillProposals()
        XCTAssertTrue(coordinator.fillProposals.isEmpty)
        XCTAssertEqual(coordinator.contacts.first?.value(for: "First Name"), "Sam")
    }

    func testReimportResetsAppliedFills() {
        let coordinator = MobileCoordinator()
        importCSV("First Name,Email\n,john.smith@acme.com", into: coordinator)
        coordinator.applyAllFillProposals()
        XCTAssertEqual(coordinator.contacts.first?.value(for: "First Name"), "John")

        importCSV("First Name,Email\n,maria.garcia@acme.com", into: coordinator)
        XCTAssertEqual(coordinator.contacts.first?.value(for: "First Name"), "")
        XCTAssertTrue(coordinator.fillProposals.contains { $0.kind == .firstNameFromEmail })
    }
}
