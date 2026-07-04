import SwiftUI

/// Stage 3: review the personalized messages before anything leaves the Mac.
/// Recipients with missing data or bad addresses are surfaced and excluded.
struct ReviewView: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator
    @State private var selection: MergePreview.ID?

    private var previews: [MergePreview] { coordinator.previews }

    var body: some View {
        HSplitView {
            recipientList
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            detailPane
                .frame(minWidth: 360, maxWidth: .infinity)
        }
        .onAppear {
            if selection == nil { selection = previews.first?.id }
        }
    }

    private var recipientList: some View {
        VStack(alignment: .leading, spacing: 0) {
            countsBanner
                .padding(12)
            Divider()
            List(previews, selection: $selection) { preview in
                HStack {
                    Image(systemName: preview.isSendable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(preview.isSendable ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview.contact.displayName).lineLimit(1)
                        Text(preview.contact.email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .tag(preview.id)
            }
            .listStyle(.inset)
        }
    }

    private var countsBanner: some View {
        let sendable = coordinator.sendablePreviews.count
        let blocked = coordinator.blockedPreviews.count
        let duplicates = coordinator.duplicateCount
        return VStack(alignment: .leading, spacing: 4) {
            Label("\(sendable) ready to send", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)
            if blocked > 0 {
                Label("\(blocked) excluded (missing data or bad address)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
            if duplicates > 0 {
                Label("\(duplicates) duplicate\(duplicates == 1 ? "" : "s") held back", systemImage: "person.2.slash")
                    .foregroundStyle(.orange).font(.callout)
            }
            if coordinator.suppressedCount > 0 {
                Label("\(coordinator.suppressedCount) on your do-not-contact list", systemImage: "nosign")
                    .foregroundStyle(.orange).font(.callout)
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let id = selection, let preview = previews.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let reason = preview.blockingReason {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    field("To", value: "\(preview.contact.displayName) <\(preview.contact.email)>")
                    field("Subject", value: preview.resolvedSubject)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Body").font(.caption).foregroundStyle(.secondary)
                        Text(preview.resolvedBody.isEmpty ? "—" : preview.resolvedBody)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView("Select a recipient", systemImage: "envelope",
                                   description: Text("Choose someone on the left to preview their personalized message."))
        }
    }

    private func field(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
