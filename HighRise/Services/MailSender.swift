import Foundation
import AppKit
import os

/// Executes a raw AppleScript string and surfaces any error.
///
/// Abstracted behind a protocol so the senders can be exercised in tests with a
/// fake runner that records scripts instead of actually launching Mail.
///
/// Main-actor isolated because the only real conformer (`NSAppleScriptRunner`)
/// must run on the main thread, and both callers (`MailSender`,
/// `OutlookContactsImporter`) are already `@MainActor`. This keeps the
/// conformance from crossing actor boundaries (an error in Swift 6).
@MainActor
protocol AppleScriptRunning {
    /// Runs `source`, throwing `MailSenderError.scriptFailed` on any AppleScript
    /// error (which includes the user declining the automation permission).
    func run(_ source: String) throws

    /// Runs `source` and returns its string result (used to read data back out
    /// of a client, e.g. listing Outlook contacts).
    func runReturningString(_ source: String) throws -> String
}

enum MailSenderError: LocalizedError {
    case clientNotInstalled(MailClient)
    case scriptFailed(String)
    case invalidRecipient(String)

    var errorDescription: String? {
        switch self {
        case .clientNotInstalled(let client):
            return "\(client.rawValue) isn't installed on this Mac."
        case .scriptFailed(let detail):
            return detail
        case .invalidRecipient(let email):
            return "Invalid recipient: \(email)"
        }
    }
}

/// Runs AppleScript via `NSAppleScript`. Must execute on the main thread, which
/// `@MainActor` guarantees.
@MainActor
struct NSAppleScriptRunner: AppleScriptRunning {
    func run(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw MailSenderError.scriptFailed("Could not compile the automation script.")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error."
            // Log only the message, never the script body (which contains the
            // recipient address and personalized content).
            Log.send.error("AppleScript execution failed: \(message, privacy: .public)")
            throw MailSenderError.scriptFailed(message)
        }
    }

    func runReturningString(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw MailSenderError.scriptFailed("Could not compile the automation script.")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error."
            Log.send.error("AppleScript execution failed: \(message, privacy: .public)")
            throw MailSenderError.scriptFailed(message)
        }
        return result.stringValue ?? ""
    }
}

/// Composes and dispatches one message at a time through a `MailClient`.
///
/// Sending one message per script (rather than one giant batch script) is
/// deliberate: it lets the coordinator report per-recipient success/failure,
/// throttle between sends, and stop cleanly partway through.
@MainActor
struct MailSender {
    let client: MailClient
    let runner: AppleScriptRunning

    init(client: MailClient, runner: AppleScriptRunning? = nil) {
        self.client = client
        self.runner = runner ?? NSAppleScriptRunner()
    }

    /// Whether the target client is installed (so we can fail fast with a clear
    /// message instead of a cryptic AppleScript error).
    var isClientInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: client.bundleIdentifier) != nil
    }

    func deliver(_ message: ComposedMessage, mode: SendMode) throws {
        guard EmailValidator.isValid(message.recipientEmail) else {
            throw MailSenderError.invalidRecipient(message.recipientEmail)
        }
        guard isClientInstalled else {
            throw MailSenderError.clientNotInstalled(client)
        }
        let source = AppleScriptBuilder.script(for: message, client: client, mode: mode)
        try runner.run(source)
    }
}
