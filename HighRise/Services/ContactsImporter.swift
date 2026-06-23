import Foundation
import Contacts

/// Imports recipients from the user's iCloud / on-device address book via the
/// native `Contacts` framework. One row per email address (a contact with both
/// a work and personal address yields two rows) so every reachable address is
/// available; name and company are carried alongside as merge fields.
enum ContactsImporter {

    enum ContactsError: LocalizedError {
        case accessDenied
        case fetchFailed(String)
        case noneWithEmail

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "HighRise doesn't have permission to read your Contacts. Open System Settings ▸ Privacy & Security ▸ Contacts and turn on HighRise, then try again."
            case .fetchFailed(let m):
                return "Couldn't read Contacts: \(m)"
            case .noneWithEmail:
                return "None of your contacts have an email address."
            }
        }
    }

    /// Pure decision: does this authorization status mean access is *denied*
    /// (as opposed to granted or merely not-yet-decided)? Kept separate so the
    /// mapping is unit-tested without a live `CNContactStore`. `.notDetermined`
    /// is not a denial — it means we should prompt. Unknown/newer cases (e.g.
    /// `.limited`) are treated as readable rather than blocked.
    static func isDenied(_ status: CNAuthorizationStatus) -> Bool {
        switch status {
        case .denied, .restricted: return true
        default: return false
        }
    }

    static func fetchTable() async throws -> RecipientTable {
        try await ensureAccess()

        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)

        var rows: [[String]] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let company = contact.organizationName
                for emailValue in contact.emailAddresses {
                    let email = (emailValue.value as String).trimmingCharacters(in: .whitespaces)
                    guard !email.isEmpty else { continue }
                    rows.append([name, company, email])
                }
            }
        } catch {
            // A fetch can fail because TCC revoked access mid-flight, which
            // surfaces as a generic error (e.g. "Access Denied"). If we're no
            // longer authorized, show the actionable Settings guidance instead
            // of the raw message.
            if isDenied(CNContactStore.authorizationStatus(for: .contacts)) {
                throw ContactsError.accessDenied
            }
            Log.csv.error("Contacts fetch failed: \(error.localizedDescription, privacy: .public)")
            throw ContactsError.fetchFailed(error.localizedDescription)
        }

        guard !rows.isEmpty else { throw ContactsError.noneWithEmail }
        Log.csv.info("Fetched \(rows.count, privacy: .public) Apple Contacts email rows")
        return RecipientTable(headers: ["Name", "Company", "Email"], rows: rows)
    }

    /// Ensures the app is authorized, prompting once if the user hasn't decided.
    /// Throws `.accessDenied` (with Settings guidance) for any denial.
    private static func ensureAccess() async throws {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized { return }
        if isDenied(status) { throw ContactsError.accessDenied }

        // .notDetermined → prompt. A thrown error here (or a false grant) is
        // reported as a denial, since the practical fix is the same: enable it.
        let granted: Bool
        do {
            granted = try await withCheckedThrowingContinuation { continuation in
                CNContactStore().requestAccess(for: .contacts) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        } catch {
            Log.csv.error("Contacts access request failed: \(error.localizedDescription, privacy: .public)")
            throw ContactsError.accessDenied
        }
        guard granted else { throw ContactsError.accessDenied }
    }
}
