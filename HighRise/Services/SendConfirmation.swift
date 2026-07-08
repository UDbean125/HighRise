import Foundation

/// The factual one-liner shown under the send/draft confirmation dialog's mode
/// explanation — which account the run goes out from and how many attachments
/// ride along — so the last thing a user reads before committing spells out the
/// costliest easy mistake (wrong account) in plain terms. Pure; the wording and
/// pluralization are unit-tested.
enum SendConfirmation {

    static func detail(account: String, attachments: Int) -> String {
        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let from = trimmed.isEmpty ? "your default account" : trimmed
        let attach = attachments == 0
            ? "no attachments"
            : "\(attachments) attachment\(attachments == 1 ? "" : "s") on every message"
        return "From \(from) · \(attach)"
    }
}
