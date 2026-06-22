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
            case .accessDenied:     return "HighRise doesn't have permission to read your Contacts. Grant access in System Settings ▸ Privacy & Security ▸ Contacts."
            case .fetchFailed(let m): return "Couldn't read Contacts: \(m)"
            case .noneWithEmail:    return "None of your contacts have an email address."
            }
        }
    }

    static func fetchTable() async throws -> RecipientTable {
        try await requestAccess()

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
            throw ContactsError.fetchFailed(error.localizedDescription)
        }

        guard !rows.isEmpty else { throw ContactsError.noneWithEmail }
        Log.csv.info("Fetched \(rows.count, privacy: .public) Apple Contacts email rows")
        return RecipientTable(headers: ["Name", "Company", "Email"], rows: rows)
    }

    /// Bridges the callback-based authorization API to async/await.
    private static func requestAccess() async throws {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            return
        case .denied, .restricted:
            throw ContactsError.accessDenied
        default:
            break // .notDetermined → prompt below
        }

        let granted: Bool = try await withCheckedThrowingContinuation { continuation in
            CNContactStore().requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: ContactsError.fetchFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        guard granted else { throw ContactsError.accessDenied }
    }
}
