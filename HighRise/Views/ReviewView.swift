import SwiftUI

/// Stage 3: review the personalized messages before anything leaves the Mac.
/// Recipients with missing data or bad addresses are surfaced and excluded.
struct ReviewView: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator
    @State private var selection: MergePreview.ID?
    @State private var searchText = ""
    @State private var statusFilter: StatusFilter = .all

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All", ready = "Ready", held = "Held"
        var id: String { rawValue }
    }

    private var previews: [MergePreview] { coordinator.previews }

    /// The list after the search box and status chips are applied.
    private var filteredPreviews: [MergePreview] {
        previews.filter { preview in
            let statusOK: Bool
            switch statusFilter {
            case .all:   statusOK = true
            case .ready: statusOK = preview.isSendable
            case .held:  statusOK = !preview.isSendable
            }
            guard statusOK else { return false }
            guard !searchText.isEmpty else { return true }
            return preview.contact.displayName.localizedCaseInsensitiveContains(searchText)
                || preview.contact.email.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HSplitView {
            recipientList
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 380)
            detailPane
                .frame(minWidth: 360, maxWidth: .infinity)
        }
        .onAppear {
            if selection == nil { selection = previews.first?.id }
        }
        .onChange(of: searchText) { _, _ in reconcileSelection() }
        .onChange(of: statusFilter) { _, _ in reconcileSelection() }
    }

    /// Keeps a sensible selection when the filter hides the current one.
    private func reconcileSelection() {
        if !filteredPreviews.contains(where: { $0.id == selection }) {
            selection = filteredPreviews.first?.id
        }
    }

    private var recipientList: some View {
        VStack(alignment: .leading, spacing: 0) {
            countsBanner
                .padding(12)
            Divider()
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a recipient", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                Picker("Show", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(10)
            if filteredPreviews.isEmpty {
                Spacer()
                Text(previews.isEmpty ? "No recipients yet." : "No matches — clear the search or filter.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                List(filteredPreviews, selection: $selection) { preview in
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
    }

    private var countsBanner: some View {
        let sendable = coordinator.sendablePreviews.count
        let blocked = coordinator.blockedPreviews.count
        let duplicates = coordinator.duplicateCount
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(sendable)").font(.title2.weight(.bold).monospacedDigit())
                    Text("ready to send").font(.caption).foregroundStyle(.secondary)
                }
            }
            if blocked > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    heldBackLine("\(blocked) excluded", "exclamationmark.triangle.fill")
                    if duplicates > 0 {
                        heldBackLine("\(duplicates) duplicate\(duplicates == 1 ? "" : "s") held back", "person.2.slash")
                    }
                    if coordinator.suppressedCount > 0 {
                        heldBackLine("\(coordinator.suppressedCount) on do-not-contact list", "nosign")
                    }
                }
            }
        }
    }

    private func heldBackLine(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon).font(.caption).foregroundStyle(.orange)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let id = selection, let preview = previews.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let reason = preview.blockingReason {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(reason, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            if let suggestion = coordinator.nameSuggestion(for: preview) {
                                Button {
                                    coordinator.fillField(suggestion.field, with: suggestion.name,
                                                          forContact: preview.contact.id)
                                } label: {
                                    Label("Use “\(suggestion.name)” for \(suggestion.field)",
                                          systemImage: "wand.and.stars")
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        field("To", value: "\(preview.contact.displayName) <\(preview.contact.email)>")
                        Divider()
                        field("Subject", value: preview.resolvedSubject)
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Body").font(.caption).foregroundStyle(.secondary)
                            Text(preview.resolvedBody.isEmpty ? "—" : preview.resolvedBody)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .card()
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
