import SwiftUI

/// Stage 3: review the personalized messages before anything leaves the Mac.
/// A glanceable summary strip tops the stage; recipients with missing data or
/// bad addresses are surfaced with a status pill and excluded from sending.
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
    private var summary: ReviewSummary.Summary { ReviewSummary.of(previews) }

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
        VStack(spacing: 0) {
            summaryStrip
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            Divider()
            HSplitView {
                recipientList
                    .frame(minWidth: 250, idealWidth: 300, maxWidth: 380)
                detailPane
                    .frame(minWidth: 360, maxWidth: .infinity)
            }
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

    // MARK: - Summary strip

    /// The glanceable header: recipients / ready / held / domains as stat tiles,
    /// with a compact breakdown of *why* rows are held below.
    private var summaryStrip: some View {
        let s = summary
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                StatTile(value: "\(s.total)",
                         label: s.total == 1 ? "recipient" : "recipients",
                         systemImage: "person.2.fill")
                StatTile(value: "\(s.ready)", label: "ready to send",
                         systemImage: "checkmark.seal.fill", tint: .green)
                if s.held > 0 {
                    StatTile(value: "\(s.held)", label: "held back",
                             systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
                StatTile(value: "\(s.domains)",
                         label: s.domains == 1 ? "domain" : "domains",
                         systemImage: "at")
            }
            heldBreakdown
        }
    }

    /// Pills breaking the held-back rows down by *reason* — invalid address,
    /// missing data, duplicate, do-not-contact, missing file — so users know
    /// exactly what to fix, not just that something was held.
    @ViewBuilder
    private var heldBreakdown: some View {
        let entries = HeldReasons.tally(previews)
        if !entries.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 260), spacing: 6, alignment: .leading)],
                      alignment: .leading, spacing: 6) {
                ForEach(entries) { entry in
                    StatusPill(text: "\(entry.count) \(heldShortLabel(entry.category))",
                               color: .orange, systemImage: heldIcon(entry.category))
                }
            }
        }
    }

    private func heldShortLabel(_ category: PreSendReport.Block) -> String {
        switch category {
        case .invalidEmail:      return "invalid email"
        case .suppressed:        return "do-not-contact"
        case .missingData:       return "missing data"
        case .missingAttachment: return "missing file"
        case .duplicate:         return "duplicate"
        }
    }

    private func heldIcon(_ category: PreSendReport.Block) -> String {
        switch category {
        case .invalidEmail:      return "envelope.badge"
        case .suppressed:        return "nosign"
        case .missingData:       return "exclamationmark.triangle.fill"
        case .missingAttachment: return "paperclip"
        case .duplicate:         return "person.2.slash"
        }
    }

    // MARK: - Recipient list

    private var recipientList: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    recipientRow(preview).tag(preview.id)
                }
                .listStyle(.inset)
            }
        }
    }

    /// A scannable row: initials avatar, name + address, and a status pill so
    /// "who's ready vs held" reads at a glance without opening each one.
    private func recipientRow(_ preview: MergePreview) -> some View {
        HStack(spacing: 10) {
            Avatar(name: preview.contact.displayName, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.contact.displayName).lineLimit(1)
                Text(preview.contact.email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if preview.isSendable {
                StatusPill(text: "Ready", color: .green, systemImage: "checkmark")
            } else {
                StatusPill(text: "Held", color: .orange, systemImage: "exclamationmark.triangle.fill")
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if let id = selection, let preview = previews.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    recipientHeader(preview)

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

    /// The recipient identity header above the message card — avatar, name,
    /// address, and a status pill mirroring the list.
    private func recipientHeader(_ preview: MergePreview) -> some View {
        HStack(spacing: 12) {
            Avatar(name: preview.contact.displayName, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.contact.displayName).font(.title3.weight(.semibold)).lineLimit(1)
                Text(preview.contact.email).font(.subheadline).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(1)
            }
            Spacer(minLength: 8)
            if preview.isSendable {
                StatusPill(text: "Ready to send", color: .green, systemImage: "checkmark.seal.fill")
            } else {
                StatusPill(text: "Held back", color: .orange, systemImage: "exclamationmark.triangle.fill")
            }
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
