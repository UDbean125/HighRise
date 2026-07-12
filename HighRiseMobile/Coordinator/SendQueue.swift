import Foundation

/// Drives the recipient-by-recipient compose queue for the iOS send flow.
///
/// iOS has no automation API to draft/send unattended the way the macOS app
/// does via AppleScript (see `HighRiseMobile/Mail/MailComposeView.swift`), so
/// sending is inherently one `MFMailComposeViewController` sheet per
/// recipient with the person tapping Send themselves. This tracks where the
/// user is in that queue and what happened to each recipient so far. Pure
/// Foundation logic, kept separate from the UIKit-wrapping view so it's
/// unit-testable without a simulator.
struct SendQueue {
    let items: [MergePreview]
    private(set) var index: Int = 0
    private(set) var outcomes: [SendOutcome] = []

    init(items: [MergePreview]) {
        self.items = items
    }

    var current: MergePreview? {
        items.indices.contains(index) ? items[index] : nil
    }

    var isFinished: Bool { index >= items.count }

    var completedCount: Int { outcomes.count }
    var totalCount: Int { items.count }

    /// Records what happened to the current recipient and advances to the
    /// next one. A no-op if the queue is already finished.
    mutating func recordOutcome(_ status: SendOutcome.Status) {
        guard let contact = current?.contact else { return }
        outcomes.append(SendOutcome(id: contact.id, contact: contact, status: status))
        index += 1
    }
}
