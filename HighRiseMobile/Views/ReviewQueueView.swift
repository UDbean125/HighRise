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
                    // "Don't email this person" has to be reachable at the
                    // moment you notice, not buried in a settings screen.
                    .swipeActions {
                        Button(role: .destructive) {
                            coordinator.suppressAddress(preview.contact.email)
                        } label: {
                            Label("Never email", systemImage: "hand.raised")
                        }
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    DoNotContactView()
                } label: {
                    Label("Do not contact", systemImage: "hand.raised")
                }
            }
        }
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
