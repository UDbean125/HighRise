import Testing
import Contacts
@testable import HighRise

/// The Contacts import is mostly system-framework I/O, but the decision that
/// matters for the user — "is this a denial we should explain, or something
/// else?" — is pulled into a pure function so it can be pinned here.
struct ContactsImporterTests {

    @Test("Denied and restricted are treated as access denied")
    func deniedStates() {
        #expect(ContactsImporter.isDenied(.denied))
        #expect(ContactsImporter.isDenied(.restricted))
    }

    @Test("Authorized and not-determined are not denials")
    func nonDeniedStates() {
        #expect(!ContactsImporter.isDenied(.authorized))
        #expect(!ContactsImporter.isDenied(.notDetermined))
    }

    @Test("The access-denied message points the user to System Settings")
    func deniedMessageIsActionable() {
        let message = ContactsImporter.ContactsError.accessDenied.errorDescription ?? ""
        #expect(message.contains("System Settings"))
        #expect(message.contains("Contacts"))
    }
}

/// Test-send validation guards that resolve before any mail client is touched,
/// so they're safe to exercise without launching Mail/Outlook.
@MainActor
struct TestSendGuardTests {

    @Test("A malformed test address is rejected with actionable text")
    func rejectsBadAddress() {
        let coordinator = HighRiseCoordinator()
        coordinator.testRecipient = "not-an-email"
        coordinator.sendTestToSelf()
        #expect(coordinator.testSendResult?.succeeded == false)
        #expect(coordinator.testSendResult?.message.contains("valid") == true)
    }

    @Test("A valid address with nothing ready to send is reported, not attempted")
    func requiresASendableSample() {
        let coordinator = HighRiseCoordinator()
        coordinator.testRecipient = "me@example.com"   // valid, but no contacts loaded
        coordinator.sendTestToSelf()
        #expect(coordinator.testSendResult?.succeeded == false)
        #expect(coordinator.testSendResult?.message.contains("ready") == true)
    }
}
