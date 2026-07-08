import Foundation

/// A pure go/no-go pre-flight for the Send stage. Turns the current state —
/// ready recipients, content-check score, missing attachments — into a single
/// clear verdict plus a structured checklist, so the Send screen can lead with
/// "You're ready" or "Not ready yet" instead of making the user parse each row.
/// Deterministic; the wording, severity, and pluralization are unit-tested.
enum SendReadiness {

    /// A required check must pass before anything can go out; an advisory is
    /// worth a look but doesn't block (e.g. a so-so content score, or files
    /// missing on rows that are already held back).
    enum Severity: Equatable { case required, advisory }

    struct Check: Identifiable, Equatable {
        let passed: Bool
        let severity: Severity
        let title: String
        var id: String { title }
    }

    struct Report: Equatable {
        let readyCount: Int
        let mode: SendMode
        let checks: [Check]

        var failedRequired: [Check] { checks.filter { !$0.passed && $0.severity == .required } }
        var failedAdvisory: [Check] { checks.filter { !$0.passed && $0.severity == .advisory } }

        /// Safe to proceed when every required check passes.
        var canSend: Bool { failedRequired.isEmpty }

        /// The one-line verdict for the banner at the top of the rail.
        var headline: String {
            guard canSend else { return "Not ready yet — add at least one valid recipient" }
            let unit = mode == .send ? "message" : "draft"
            let verb = mode == .send ? "to send" : "to create"
            var line = "You're ready — \(readyCount) \(unit)\(readyCount == 1 ? "" : "s") \(verb)"
            let advisories = failedAdvisory.count
            if advisories > 0 {
                line += " · \(advisories) thing\(advisories == 1 ? "" : "s") worth a look"
            }
            return line
        }
    }

    static func assess(readyCount: Int, contentScore: Int,
                       missingAttachments: Int, mode: SendMode) -> Report {
        let checks = [
            Check(passed: readyCount > 0, severity: .required,
                  title: readyCount > 0 ? "At least one recipient is ready"
                                        : "No recipients are ready yet"),
            Check(passed: contentScore >= 75, severity: .advisory,
                  title: contentScore >= 75 ? "Content looks inbox-friendly"
                                            : "Content check flags some issues"),
            Check(passed: missingAttachments == 0, severity: .advisory,
                  title: missingAttachments == 0 ? "All attachments found"
                                                 : "\(missingAttachments) attachment\(missingAttachments == 1 ? "" : "s") missing")
        ]
        return Report(readyCount: readyCount, mode: mode, checks: checks)
    }
}
