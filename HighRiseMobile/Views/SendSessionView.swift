import SwiftUI
import MessageUI

/// Step 4: the one-recipient-at-a-time send queue. There's no unattended
/// batch send on iOS (see `MailComposeView`), so this presents each ready
/// recipient's merged message and lets the user open it in Mail, send it, and
/// move to the next — or skip a recipient without sending.
struct SendSessionView: View {
    @EnvironmentObject var coordinator: MobileCoordinator
    @State private var showingComposer = false
    @State private var showingMailUnavailableAlert = false

    var body: some View {
        Group {
            if let queue = coordinator.queue, !queue.isFinished, let current = queue.current {
                inProgress(queue: queue, current: current)
            } else if let queue = coordinator.queue, queue.isFinished {
                doneSummary(queue)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Sending")
        .navigationBarBackButtonHidden(!(coordinator.queue?.isFinished ?? true))
        .onAppear {
            // Rebuild on re-entry with a finished queue too — otherwise the
            // stale "Done" summary shows forever and a second session can
            // never start without re-importing the list. Safe within a
            // visit: onAppear doesn't refire while the just-finished summary
            // is on screen.
            if coordinator.queue == nil || coordinator.queue?.isFinished == true {
                coordinator.startSendQueue()
            }
        }
        .sheet(isPresented: $showingComposer) {
            if let current = coordinator.queue?.current {
                MailComposeView(preview: current, isHTML: coordinator.template.format.isHTMLDelivery) { result, error in
                    handle(result: result, error: error)
                }
            }
        }
        .alert("Mail Isn't Set Up", isPresented: $showingMailUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add a mail account in Settings ▸ Mail before sending from HighRise.")
        }
    }

    @ViewBuilder
    private func inProgress(queue: SendQueue, current: MergePreview) -> some View {
        VStack(spacing: 20) {
            resumedNotice(queue: queue)

            Text("\(queue.completedCount + 1) of \(queue.totalCount)")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text(current.contact.displayName).font(.title3.bold())
                Text(current.contact.email).foregroundStyle(.secondary)
                Divider()
                Text(current.resolvedSubject).bold()
                Text(current.resolvedBody).font(.footnote).lineLimit(6)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Button("Open in Mail…") {
                if MFMailComposeViewController.canSendMail() {
                    showingComposer = true
                } else {
                    showingMailUnavailableAlert = true
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Skip This Recipient") {
                coordinator.recordOutcome(.skipped(reason: "Skipped by user"))
            }
            .buttonStyle(.bordered)
        }
    }

    /// Explains why the queue is shorter than the list. Without this the
    /// protection would be invisible — the user would just see a smaller
    /// number and wonder who got dropped.
    @ViewBuilder
    private func resumedNotice(queue: SendQueue) -> some View {
        let skipped = coordinator.resumedFromInterruptedCount
        if skipped > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Label("Picking up where you left off",
                      systemImage: "arrow.clockwise.circle.fill")
                    .font(.subheadline.bold())
                Text("\(skipped) recipient\(skipped == 1 ? "" : "s") already received this from an earlier run that was interrupted, so \(skipped == 1 ? "it isn't" : "they aren't") in this queue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                // Only offered before this run has sent anything. Rebuilding
                // the queue mid-run would put the people already emailed in
                // *this* session back into it — the exact double-send the
                // journal exists to prevent.
                if queue.completedCount == 0 {
                    Button("Email them again anyway") {
                        coordinator.discardInterruptedRun()
                        coordinator.startSendQueue()
                    }
                    .font(.footnote)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    /// Every outcome goes through the coordinator rather than mutating
    /// `queue` directly, so each one is written to the durable run journal
    /// as it happens — see `MobileCoordinator.recordOutcome`.
    private func handle(result: MFMailComposeResult, error: Error?) {
        switch result {
        case .sent:
            coordinator.recordOutcome(.sent)
        case .saved:
            coordinator.recordOutcome(.drafted)
        case .cancelled:
            break // leave this recipient queued so the user can retry or skip
        case .failed:
            coordinator.recordOutcome(.failed(reason: error?.localizedDescription ?? "Unknown error"))
        @unknown default:
            break
        }
    }

    @ViewBuilder
    private func doneSummary(_ queue: SendQueue) -> some View {
        let sent = queue.outcomes.filter {
            switch $0.status {
            case .sent: return true
            default: return false
            }
        }.count
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Done — \(sent) of \(queue.totalCount) sent")
                .font(.title3.bold())
        }
    }
}
