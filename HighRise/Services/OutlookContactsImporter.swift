import Foundation
import AppKit

/// Imports recipients from Microsoft Outlook's address book via AppleScript —
/// the same automation channel used for sending. Outlook has no public Swift
/// API, so we ask it to emit its contacts as tab-delimited lines and parse the
/// result back into a `RecipientTable`.
@MainActor
enum OutlookContactsImporter {

    enum OutlookError: LocalizedError {
        case notInstalled
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:        return "Microsoft Outlook isn't installed on this Mac."
            case .scriptFailed(let m): return "Couldn't read Outlook contacts: \(m)"
            }
        }
    }

    static func fetchTable(runner: AppleScriptRunning? = nil) throws -> RecipientTable {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: MailClient.outlook.bundleIdentifier) != nil else {
            throw OutlookError.notInstalled
        }

        let scriptRunner = runner ?? NSAppleScriptRunner()
        let output: String
        do {
            output = try scriptRunner.runReturningString(script)
        } catch {
            throw OutlookError.scriptFailed(error.localizedDescription)
        }
        return parse(output)
    }

    /// Each line is `first \t last \t company \t email`. Combines the name parts
    /// and drops rows without a valid email.
    static func parse(_ output: String) -> RecipientTable {
        var rows: [[String]] = []
        var seen = Set<String>()
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: "\t")
            guard parts.count >= 4 else { continue }
            let name = [parts[0], parts[1]].filter { !$0.isEmpty }.joined(separator: " ")
            let company = parts[2]
            let email = parts[3].trimmingCharacters(in: .whitespaces)
            guard EmailValidator.isValid(email) else { continue }
            let key = email.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            rows.append([name, company, email])
        }
        return RecipientTable(headers: ["Name", "Company", "Email"], rows: rows)
    }

    /// AppleScript that walks every Outlook contact and prints its email rows.
    /// `try` blocks guard against contacts missing individual properties.
    private static let script = """
    tell application "Microsoft Outlook"
        set outputText to ""
        repeat with c in contacts
            set fn to ""
            set ln to ""
            set co to ""
            try
                set fn to (first name of c) as string
            end try
            try
                set ln to (last name of c) as string
            end try
            try
                set co to (company of c) as string
            end try
            repeat with e in (email addresses of c)
                set addr to ""
                try
                    set addr to (address of e) as string
                end try
                if addr is not "" then
                    set outputText to outputText & fn & tab & ln & tab & co & tab & addr & linefeed
                end if
            end repeat
        end repeat
        return outputText
    end tell
    """
}
