import Foundation

/// Builds a shareable plain-text pre-send report — a printable audit of exactly
/// what's about to go out: who's included, who's held back and why, the content
/// check, pacing estimate, and attachments. Pure and deterministic (the caller
/// supplies the timestamp), so it's fully unit-testable and never touches I/O.
enum PreSendReport {

    struct Input {
        /// A pre-formatted "generated at" label (the caller formats the Date, so
        /// this stays pure and locale-agnostic to test).
        var generatedAtLabel: String
        var client: MailClient
        var senderIdentity: String
        var mode: SendMode
        var provider: SendingProvider
        var template: EmailTemplate
        var previews: [MergePreview]
        var throttle: ThrottlePolicy
        var attachmentNames: [String]
    }

    /// How a held-back recipient is categorized, in the same priority order the
    /// review screen uses (`MergePreview.blockingReason`).
    enum Block: String {
        case invalidEmail = "Invalid or missing email"
        case suppressed = "On do-not-contact list"
        case missingData = "Missing merge data"
        case missingAttachment = "Attachment file not found"
        case duplicate = "Duplicate address"
    }

    static func category(of preview: MergePreview) -> Block? {
        if preview.isSendable { return nil }
        if !preview.hasValidEmail { return .invalidEmail }
        if preview.isSuppressed { return .suppressed }
        if !preview.unresolvedFields.isEmpty { return .missingData }
        if !preview.missingAttachmentPaths.isEmpty { return .missingAttachment }
        if preview.isDuplicate { return .duplicate }
        return nil
    }

    static func plainText(_ input: Input) -> String {
        let ready = input.previews.filter(\.isSendable)
        let blocked = input.previews.filter { !$0.isSendable }

        let findings = ContentLinter.lint(template: input.template)
        let score = ContentLinter.score(for: findings)

        var lines: [String] = []
        lines.append("HighRise — Pre-send report")
        lines.append("Generated: \(input.generatedAtLabel)")
        lines.append("")

        lines.append("SENDING")
        lines.append("  Via:      \(account(for: input))")
        lines.append("  Mode:     \(input.mode.rawValue)")
        lines.append("  Provider: \(input.provider.rawValue)")
        lines.append("")

        lines.append("RECIPIENTS")
        lines.append("  Ready to send: \(ready.count)")
        lines.append("  Held back: \(blocked.count)")
        for block in orderedBlocks {
            let count = blocked.filter { category(of: $0) == block }.count
            if count > 0 {
                lines.append("    \(block.rawValue): \(count)")
            }
        }
        lines.append("")

        lines.append("CONTENT CHECK")
        lines.append("  Score: \(score)/100 — \(ContentLinter.grade(for: score))")
        if findings.isEmpty {
            lines.append("  No issues flagged.")
        } else {
            for finding in findings {
                lines.append("  · \(finding.message)")
            }
        }
        lines.append("")

        lines.append("PACING")
        let estimate = input.throttle.expectedDuration(forCount: ready.count)
        lines.append("  Estimated send time: \(ThrottlePolicy.humanDuration(estimate))")
        if input.throttle.baseDelay > 0 || input.throttle.jitter > 0 {
            lines.append(String(format: "  Pause between sends: %.1fs + up to %.1fs jitter",
                                input.throttle.baseDelay, input.throttle.jitter))
        }
        lines.append("")

        lines.append("ATTACHMENTS")
        lines.append(input.attachmentNames.isEmpty
                     ? "  None."
                     : "  \(input.attachmentNames.count): \(input.attachmentNames.joined(separator: ", "))")
        lines.append("")

        if !blocked.isEmpty {
            lines.append("HELD-BACK RECIPIENTS")
            for preview in blocked {
                let reason = preview.blockingReason ?? "Held back."
                lines.append("  \(preview.contact.displayName) <\(preview.contact.email)> — \(reason)")
            }
            lines.append("")
        }

        lines.append("— \(ready.count) message\(ready.count == 1 ? "" : "s") ready. Nothing has been sent.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static let orderedBlocks: [Block] =
        [.invalidEmail, .suppressed, .missingData, .missingAttachment, .duplicate]

    private static func account(for input: Input) -> String {
        switch input.client {
        case .appleMail:
            return input.senderIdentity.isEmpty
                ? "Apple Mail — default account"
                : "Apple Mail — \(input.senderIdentity)"
#if !MAS_BUILD
        case .outlook:
            return "Microsoft Outlook — default account"
#endif
        }
    }
}
