import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Stage 4: choose the client and mode, then create drafts or send. Draft-first
/// is the default — every message is built automatically (no per-email prompt),
/// landing in Drafts so the user reviews and sends on their own terms.
struct SendView: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator
    @State private var showConfirm = false
    @State private var scheduleDate = Date().addingTimeInterval(3600)

    var body: some View {
        ScrollView {
            // Two-column workspace like the other stages: the options on the
            // left, a live "ready to send?" pre-flight rail on the right.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    mainColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                    readinessRail
                        .frame(width: 340)
                }
                .frame(minWidth: 940)

                VStack(alignment: .leading, spacing: 16) {
                    readinessRail
                    mainColumn
                }
            }
            .padding(24)
            .frame(maxWidth: 1320, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .confirmationDialog(confirmTitle, isPresented: $showConfirm, titleVisibility: .visible) {
            Button(confirmButton, role: coordinator.sendMode == .send ? .destructive : nil) {
                coordinator.startSending()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(coordinator.sendMode.explanation)
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            if coordinator.selectedClient == .appleMail {
                senderCard
            }
            attachmentsCard
            recipientsCard
            if coordinator.sendMode == .send {
                pacingCard
            }
            toolsCard
            scheduleCard
            if !coordinator.outcomes.isEmpty {
                resultsCard
            }
        }
    }

    // MARK: - Readiness rail (pre-flight)

    /// A live, at-a-glance pre-flight: how many will go out, an estimated send
    /// duration from the pacing settings, the content-check score, attachments,
    /// the chosen client, any provider quota warning, and a short go/no-go
    /// checklist — all before anything leaves the Mac.
    private var readinessRail: some View {
        let ready = coordinator.sendablePreviews.count
        let excluded = coordinator.blockedPreviews.count
        let findings = ContentLinter.lint(template: coordinator.template)
        let score = ContentLinter.score(for: findings)
        let noun = coordinator.sendMode == .send ? "ready to send" : "drafts to create"
        let report = SendReadiness.assess(readyCount: ready, contentScore: score,
                                          missingAttachments: coordinator.missingAttachments.count,
                                          mode: coordinator.sendMode)

        return SectionCard("Ready to send?", systemImage: "airplane.departure",
                           subtitle: "A quick pre-flight — nothing leaves your Mac until you confirm.") {
            VStack(alignment: .leading, spacing: 14) {
                verdictBanner(report)
                HStack(spacing: 12) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(ready > 0 ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(ready)").font(.system(size: 34, weight: .bold)).monospacedDigit()
                        Text(noun).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if ready > 0 {
                    Label {
                        Text(RecipientPreview.summary(coordinator.sendablePreviews.map(\.contact.displayName)))
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "person.crop.circle").foregroundStyle(Brand.accent)
                    }
                }
                if excluded > 0 {
                    Label("\(excluded) excluded — missing data, duplicate, or opted out.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                metricRow("checkmark.shield", "Content score", "\(score)/100", scoreTint(score))
                if coordinator.sendMode == .send {
                    metricRow("timer", "Est. send time",
                              ThrottlePolicy.humanDuration(coordinator.throttle.expectedDuration(forCount: ready)))
                }
                metricRow("paperclip", "Attachments",
                          coordinator.attachments.isEmpty
                            ? "None"
                            : "\(coordinator.attachments.count) · \(AttachmentSet.humanBytes(AttachmentSet.totalBytes(coordinator.attachments)))")
                metricRow(coordinator.selectedClient.symbolName, "Sending via", coordinator.selectedClient.rawValue)

                if let warning = coordinator.quotaWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                ForEach(report.checks) { check in
                    checkItem(check.passed, check.title)
                }

                Divider()
                Button {
                    exportPreSendReport()
                } label: {
                    Label("Export pre-send report…", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .help("Save a plain-text summary of exactly what's about to go out")
                if let reportStatus {
                    Text(reportStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The single go/no-go line at the top of the rail — green when the run is
    /// clear to proceed, amber when something needs attention first.
    private func verdictBanner(_ report: SendReadiness.Report) -> some View {
        HStack(spacing: 8) {
            Image(systemName: report.canSend ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
            Text(report.headline)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(report.canSend ? .green : .orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((report.canSend ? Color.green : Color.orange).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @State private var reportStatus: String?

    private func exportPreSendReport() {
        let input = PreSendReport.Input(
            generatedAtLabel: Date.now.formatted(date: .abbreviated, time: .shortened),
            client: coordinator.selectedClient,
            senderIdentity: coordinator.senderIdentity,
            mode: coordinator.sendMode,
            provider: coordinator.sendingProvider,
            template: coordinator.template,
            previews: coordinator.previews,
            throttle: coordinator.throttle,
            attachmentNames: coordinator.attachments.map(\.lastPathComponent)
        )
        let report = PreSendReport.plainText(input)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "HighRise-pre-send-report.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            reportStatus = "Report saved to \(url.lastPathComponent)."
        } catch {
            reportStatus = "Couldn't save the report: \(error.localizedDescription)"
        }
    }

    private func metricRow(_ icon: String, _ label: String, _ value: String,
                           _ tint: Color = .primary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            Text(label).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.weight(.medium)).foregroundStyle(tint)
        }
    }

    private func checkItem(_ ok: Bool, _ text: String) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "circle")
            .font(.callout)
            .foregroundStyle(ok ? .green : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func scoreTint(_ score: Int) -> Color {
        switch score {
        case 90...: return .green
        case 75..<90: return Brand.accent
        case 50..<75: return .orange
        default: return .red
        }
    }

    // MARK: - Hero (summary + client + mode + primary action)

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Send").font(.title.bold())
                Text("Review your options, then create drafts or send.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Send with").font(.subheadline).foregroundStyle(.secondary)
                Picker("Email client", selection: $coordinator.selectedClient) {
                    ForEach(MailClient.allCases) { client in
                        Label(client.rawValue, systemImage: client.symbolName).tag(client)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
                if coordinator.selectedClient == .appleMail && coordinator.template.format == .html {
                    htmlNote
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Mode").font(.subheadline).foregroundStyle(.secondary)
                Picker("Mode", selection: $coordinator.sendMode) {
                    ForEach(SendMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup).labelsHidden()
                Text(coordinator.sendMode.explanation)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            actionRow
        }
        .card(padding: 20)
    }

    private var htmlNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Apple Mail's automation only reliably sets plain text. For full HTML, use Outlook — or export .eml drafts.",
                  systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                exportHTMLDrafts()
            } label: {
                Label("Export HTML drafts (.eml)…  ·  experimental", systemImage: "curlybraces")
            }
            .disabled(coordinator.sendablePreviews.isEmpty)
            if let emlStatus {
                Text(emlStatus).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - From & signature (Apple Mail)

    private var senderCard: some View {
        CollapsibleCard("From & signature", systemImage: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 12) {
                labeledField("From account", placeholder: "Jordan <jordan@work.com>",
                             text: $coordinator.senderIdentity,
                             hint: "Must match one of your configured Mail accounts. Blank = your default.")
                labeledField("Signature", placeholder: "signature name, e.g. Work",
                             text: $coordinator.signatureName,
                             hint: "Must match a signature configured in Mail. Blank = none.")
            }
        }
    }

    private func labeledField(_ label: String, placeholder: String,
                              text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 340)
            Text(hint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Pacing

    private var pacingCard: some View {
        CollapsibleCard("Pacing", systemImage: "timer",
                        badge: coordinator.throttle.baseDelay > 0 ? "on" : nil) {
            throttleControls
        }
    }

    private var throttleControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pause between sends: \(coordinator.throttle.baseDelay, specifier: "%.1f")s")
                    .font(.headline)
                Slider(value: $coordinator.throttle.baseDelay, in: 0...5, step: 0.1)
                    .frame(maxWidth: 360)
                Text("A short gap keeps your mail client responsive and avoids tripping rate limits.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Add up to \(coordinator.throttle.jitter, specifier: "%.1f")s of random jitter")
                    .font(.subheadline)
                Slider(value: $coordinator.throttle.jitter, in: 0...5, step: 0.1)
                    .frame(maxWidth: 360)
                Text("Varies the gap so sends don't fire on a perfectly regular clock.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Stepper("Pause every \(coordinator.throttle.batchSize) messages",
                        value: $coordinator.throttle.batchSize, in: 0...500, step: 25)
                    .fixedSize()
                if coordinator.throttle.batchSize > 0 {
                    Stepper("for \(Int(coordinator.throttle.batchPause))s",
                            value: $coordinator.throttle.batchPause, in: 0...1800, step: 30)
                        .fixedSize()
                }
            }
            if coordinator.throttle.batchSize == 0 {
                Text("Batch pausing off — set a batch size to rest between groups on a large list.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Sending account").font(.subheadline)
                Picker("Sending account", selection: $coordinator.sendingProvider) {
                    ForEach(SendingProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
                if let warning = coordinator.quotaWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var attachmentsCard: some View {
        let totalBytes = AttachmentSet.totalBytes(coordinator.attachments)
        return CollapsibleCard("Attachments", systemImage: "paperclip",
                        badge: coordinator.attachments.isEmpty ? nil : "\(coordinator.attachments.count)") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("The same file(s) are attached to every message — drag files in, or add them.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        addAttachments()
                    } label: {
                        Label("Add Files…", systemImage: "paperclip")
                    }
                }

                if coordinator.attachments.isEmpty {
                    dropHint
                } else {
                    ForEach(coordinator.attachments, id: \.self) { url in
                        attachmentRow(url)
                    }
                    HStack {
                        Text("\(coordinator.attachments.count) file\(coordinator.attachments.count == 1 ? "" : "s") · \(AttachmentSet.humanBytes(totalBytes)) total")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                if let warning = coordinator.attachmentSizeWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Brand.accent, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .opacity(isDropTargeted ? 1 : 0)
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleAttachmentDrop(providers)
            }
        }
    }

    private func attachmentRow(_ url: URL) -> some View {
        let missing = coordinator.missingAttachments.contains(url)
        return HStack {
            Image(systemName: missing ? "exclamationmark.triangle.fill" : "doc")
                .foregroundStyle(missing ? .orange : .secondary)
            Text(url.lastPathComponent).lineLimit(1)
            if missing {
                Text("missing").font(.caption).foregroundStyle(.orange)
            } else {
                Text(AttachmentSet.humanBytes(AttachmentSet.totalBytes([url])))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                coordinator.attachments.removeAll { $0 == url }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove attachment")
        }
        .padding(.vertical, 1)
    }

    private var dropHint: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "arrow.down.doc").font(.title2).foregroundStyle(.secondary)
                Text("Drag files here").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Appends dropped files to the attachment list (deduped, main-thread).
    private func handleAttachmentDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.isFileURL else { return }
                DispatchQueue.main.async {
                    if !coordinator.attachments.contains(url) {
                        coordinator.attachments.append(url)
                    }
                }
            }
        }
        return handled
    }

    @State private var isDropTargeted = false
    @State private var pdfStatus: String?
    @State private var emlStatus: String?

    private func exportHTMLDrafts() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose Folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let result = coordinator.exportHTMLDrafts(toFolder: folder)
        emlStatus = "\(result.written) .eml draft\(result.written == 1 ? "" : "s") saved"
            + (result.failed > 0 ? " · \(result.failed) failed" : "")
            + ". Double-click one to open it in Mail."
    }

    private var pdfContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Merge to PDF", systemImage: "doc.richtext").font(.subheadline.weight(.semibold))
            Text("Generate one personalized PDF per recipient from the message body — for invoices, offer letters, or certificates. Saved locally; never sent anywhere on its own.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("Filename").font(.subheadline)
                TextField("{{Full Name}} - letter.pdf", text: $coordinator.pdfFilenamePattern)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            }
            HStack(spacing: 8) {
                Text("Password (optional)").font(.subheadline)
                SecureField("leave blank for none", text: $coordinator.pdfPassword)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
            }
            Button {
                exportPDFs()
            } label: {
                Label("Save Personalized PDFs…", systemImage: "doc.richtext")
            }
            .disabled(coordinator.sendablePreviews.isEmpty)
            if let pdfStatus {
                Text(pdfStatus).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func exportPDFs() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose Folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let result = coordinator.exportPersonalizedPDFs(toFolder: folder)
        pdfStatus = "\(result.written) PDF\(result.written == 1 ? "" : "s") saved"
            + (result.failed > 0 ? " · \(result.failed) failed" : "") + "."
    }

    private func exportResults() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "HighRise-results.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? coordinator.resultsReportCSV().write(to: url, atomically: true, encoding: .utf8)
    }

    private func addAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !coordinator.attachments.contains(url) {
            coordinator.attachments.append(url)
        }
    }

    private var recipientsCard: some View {
        CollapsibleCard("CC, BCC & unsubscribe", systemImage: "person.2",
                        badge: coordinator.unsubscribeEnabled ? "unsub" : nil) {
            VStack(alignment: .leading, spacing: 10) {
                envelopeField("CC", text: $coordinator.envelope.cc,
                              hint: "Visible to the recipient. Use a column like {{Parent Email}} or a fixed address; separate several with commas.",
                              summarize: true)
                envelopeField("BCC", text: $coordinator.envelope.bcc,
                              hint: "Hidden from the recipient. Supports {{Field}} references too.",
                              summarize: true)
                envelopeField("BCC myself", text: $coordinator.envelope.bccSelf,
                              hint: "A fixed address BCC'd on every message — a private delivery record, no tracking.")

                Divider()
                Toggle("Add an unsubscribe footer", isOn: $coordinator.unsubscribeEnabled)
                    .font(.subheadline)
                if coordinator.unsubscribeEnabled {
                    envelopeField("Opt-out replies go to", text: $coordinator.unsubscribeReplyTo,
                                  hint: "A mailto: link recipients use to ask off the list. No hosted page, no tracking — you add their reply to your do-not-contact list.")
                    envelopeField("Footer text (optional)", text: $coordinator.unsubscribeNote,
                                  hint: "e.g. “Prefer not to hear from us? Let us know:”")
                }
            }
        }
    }

    private func envelopeField(_ label: String, text: Binding<String>, hint: String,
                               summarize: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline)
            TextField(label == "BCC myself" ? "you@example.com" : "name@example.com or {{Column}}",
                      text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
                .accessibilityLabel(label)
            if summarize {
                let summary = AddressList.summarize(text.wrappedValue)
                if let caption = AddressList.caption(summary) {
                    Text(caption)
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(summary.hasInvalid ? .orange : .secondary)
                }
            }
            Text(hint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var toolsCard: some View {
        CollapsibleCard("Tools", systemImage: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: 16) {
                testSendContent
                Divider()
                pdfContent
            }
        }
    }

    private var testSendContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Send yourself a test", systemImage: "paperplane").font(.subheadline.weight(.semibold))
            Text("Delivers one fully personalized sample — your first ready recipient — to your own address so you can check how it renders.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("you@example.com", text: $coordinator.testRecipient)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .accessibilityLabel("Your test email address")
                Button {
                    coordinator.sendTestToSelf()
                } label: {
                    Label("Send Test", systemImage: "paperplane")
                }
                .disabled(coordinator.sendablePreviews.isEmpty)
            }
            if let result = coordinator.testSendResult {
                Label(result.message, systemImage: result.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(result.succeeded ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            if coordinator.isSending {
                ProgressView(value: coordinator.sendProgress)
                    .frame(maxWidth: 240)
                Button("Stop", role: .destructive) { coordinator.cancelSending() }
            } else {
                Button {
                    showConfirm = true
                } label: {
                    Label(primaryActionLabel, systemImage: coordinator.sendMode == .send ? "paperplane.fill" : "tray.and.arrow.down.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!coordinator.canSend)
            }
            Spacer()
            if !coordinator.outcomes.isEmpty {
                let ok = coordinator.outcomes.filter(\.isSuccess).count
                Text("\(ok)/\(coordinator.outcomes.count) succeeded").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var scheduleCard: some View {
        if let fireDate = coordinator.scheduledFireDate {
            HStack(spacing: 10) {
                Image(systemName: "clock.badge.checkmark").font(.title3).foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scheduled for \(fireDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.headline)
                    Text("Keep this Mac awake and HighRise open until then.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .destructive) { coordinator.cancelSchedule() }
            }
            .card()
        } else if !coordinator.isSending {
            CollapsibleCard("Schedule for later", systemImage: "clock") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(SendSchedulePreset.allCases) { preset in
                            Button {
                                scheduleDate = SendScheduler.date(for: preset, from: Date())
                            } label: {
                                Label(preset.rawValue, systemImage: preset.systemImage)
                            }
                            .controlSize(.small)
                        }
                    }
                    HStack(spacing: 8) {
                        DatePicker("Start at", selection: $scheduleDate, in: Date()...)
                            .labelsHidden()
                        Button {
                            coordinator.scheduleSend(at: scheduleDate)
                        } label: {
                            Label("Schedule", systemImage: "clock")
                        }
                        .disabled(!coordinator.canSend || scheduleDate <= Date())
                    }
                    Text("Runs on this Mac at the chosen time — it must be awake with HighRise open. Editable and cancelable until it fires.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Label("Results", systemImage: "list.bullet.clipboard").font(.headline)
                    if !coordinator.outcomes.isEmpty {
                        Text(RunSummary.line(from: coordinator.outcomes))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if coordinator.failedCount > 0 && !coordinator.isSending {
                    Button {
                        coordinator.retryFailed()
                    } label: {
                        Label("Retry \(coordinator.failedCount) failed", systemImage: "arrow.clockwise")
                    }
                }
                if coordinator.hasResultsToExport {
                    Button {
                        exportResults()
                    } label: {
                        Label("Export Results…", systemImage: "square.and.arrow.up")
                    }
                }
            }
            ForEach(coordinator.outcomes) { outcome in
                HStack {
                    Image(systemName: icon(for: outcome.status))
                        .foregroundStyle(color(for: outcome.status))
                    Text(outcome.contact.displayName)
                    Spacer()
                    Text(label(for: outcome.status)).font(.callout).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .card()
    }

    // MARK: - Labels

    private var primaryActionLabel: String {
        coordinator.sendMode == .send
            ? "Send \(coordinator.sendablePreviews.count) Emails"
            : "Create \(coordinator.sendablePreviews.count) Drafts"
    }

    private var confirmTitle: String {
        coordinator.sendMode == .send
            ? "Send \(coordinator.sendablePreviews.count) emails via \(coordinator.selectedClient.rawValue)?"
            : "Create \(coordinator.sendablePreviews.count) drafts in \(coordinator.selectedClient.rawValue)?"
    }

    private var confirmButton: String {
        coordinator.sendMode == .send ? "Send Now" : "Create Drafts"
    }

    private func icon(for status: SendOutcome.Status) -> String {
        switch status {
        case .sent:    return "paperplane.fill"
        case .drafted: return "tray.and.arrow.down.fill"
        case .skipped: return "minus.circle"
        case .failed:  return "xmark.octagon.fill"
        }
    }

    private func color(for status: SendOutcome.Status) -> Color {
        switch status {
        case .sent, .drafted: return .green
        case .skipped:        return .secondary
        case .failed:         return .red
        }
    }

    private func label(for status: SendOutcome.Status) -> String {
        switch status {
        case .sent:                  return "Sent"
        case .drafted:               return "Draft created"
        case .skipped(let reason):   return "Skipped — \(reason)"
        case .failed(let reason):    return "Failed — \(reason)"
        }
    }
}
