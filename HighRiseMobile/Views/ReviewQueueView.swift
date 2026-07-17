import SwiftUI

/// Step 3: shows exactly what the Mac app's review screen shows — who's ready
/// to send and who's held back and why (`MergePreview.blockingReason`) —
/// before committing to the send queue.
struct ReviewQueueView: View {
    @EnvironmentObject var coordinator: MobileCoordinator

    var body: some View {
        List {
            Section("\(coordinator.sendableCount) Ready to Send") {
                ForEach(coordinator.previews.filter(\.isSendable)) { preview in
                    VStack(alignment: .leading) {
                        Text(preview.contact.displayName).font(.headline)
                        Text(preview.resolvedSubject).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if coordinator.blockedCount > 0 {
                Section("\(coordinator.blockedCount) Held Back") {
                    ForEach(coordinator.previews.filter { !$0.isSendable }) { preview in
                        VStack(alignment: .leading) {
                            Text(preview.contact.displayName).font(.headline)
                            Text(preview.blockingReason ?? "Blocked")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle("Review")
        .safeAreaInset(edge: .bottom) {
            NavigationLink("Start Sending") {
                SendSessionView()
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .disabled(coordinator.sendableCount == 0)
        }
    }
}
