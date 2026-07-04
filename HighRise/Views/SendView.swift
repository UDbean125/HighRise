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
            VStack(alignment: .leading, spacing: 20) {
                header
                clientPicker
                modePicker
                attachmentControls
                envelopeControls
                if coordinator.sendMode == .send {
                    throttleControls
                }
                Divider()
                testSendRow
                Divider()
                pdfRow
                Divider()
                actionRow
                scheduleRow
                if !coordinator.outcomes.isEmpty {
                    resultsList
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
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

    private var header: some View {
        let count = coordinator.sendablePreviews.count
        return VStack(alignment: .leading, spacing: 4) {
            Text("Send").font(.title2).bold()
            Text("\(count) personalized message\(count == 1 ? "" : "s") ready · \(coordinator.blockedPreviews.count) excluded.")
                .foregroundStyle(.secondary)
        }
    }

    private var clientPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Email client").font(.headline)
            Picker("Email client", selection: $coordinator.selectedClient) {
                ForEach(MailClient.allCases) { client in
                    Label(client.rawValue, systemImage: client.symbolName).tag(client)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if coordinator.selectedClient == .appleMail && coordinator.template.format == .html {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Apple Mail's automation only reliably sets plain text. For full HTML, use Outlook — or export .eml drafts below.",
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
            }
            if coordinator.selectedClient == .appleMail {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From account (optional)").font(.subheadline)
                    TextField("Jordan <jordan@work.com>", text: $coordinator.senderIdentity)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                    Text("Must match one of your configured Mail accounts. Leave blank for your default.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signature (optional)").font(.subheadline)
                    TextField("signature name, e.g. Work", text: $coordinator.signatureName)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                    Text("Must match a signature configured in Mail. Leave blank for none.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mode").font(.headline)
            Picker("Mode", selection: $coordinator.sendMode) {
                ForEach(SendMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text(coordinator.sendMode.explanation)
                .font(.callout).foregroundStyle(.secondary)
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

    private var attachmentControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Attachments").font(.headline)
                Spacer()
                Button {
                    addAttachments()
                } label: {
                    Label("Add Files…", systemImage: "paperclip")
                }
            }
            Text("The same file(s) are attached to every message.")
                .font(.callout).foregroundStyle(.secondary)

            ForEach(coordinator.attachments, id: \.self) { url in
                let missing = coordinator.missingAttachments.contains(url)
                HStack {
                    Image(systemName: missing ? "exclamationmark.triangle.fill" : "doc")
                        .foregroundStyle(missing ? .orange : .secondary)
                    Text(url.lastPathComponent).lineLimit(1)
                    if missing {
                        Text("missing").font(.caption).foregroundStyle(.orange)
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

            if let warning = coordinator.attachmentSizeWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

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

    private var pdfRow: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
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
            .padding(.top, 8)
        } label: {
            Label("Merge to PDF", systemImage: "doc.richtext")
                .font(.headline)
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

    private var envelopeControls: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                envelopeField("CC", text: $coordinator.envelope.cc,
                              hint: "Visible to the recipient. Use a column like {{Parent Email}} or a fixed address; separate several with commas.")
                envelopeField("BCC", text: $coordinator.envelope.bcc,
                              hint: "Hidden from the recipient. Supports {{Field}} references too.")
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
            .padding(.top, 8)
        } label: {
            Label("CC, BCC & delivery record", systemImage: "person.2")
                .font(.headline)
        }
    }

    private func envelopeField(_ label: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline)
            TextField(label == "BCC myself" ? "you@example.com" : "name@example.com or {{Column}}",
                      text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
                .accessibilityLabel(label)
            Text(hint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var testSendRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Send yourself a test").font(.headline)
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
    private var scheduleRow: some View {
        if let fireDate = coordinator.scheduledFireDate {
            HStack(spacing: 10) {
                Image(systemName: "clock.badge.checkmark").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scheduled for \(fireDate.formatted(date: .abbreviated, time: .shortened))")
                    Text("Keep this Mac awake and HighRise open until then.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .destructive) { coordinator.cancelSchedule() }
            }
            .padding(10)
            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        } else if !coordinator.isSending {
            VStack(alignment: .leading, spacing: 6) {
                Text("Or schedule it").font(.headline)
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

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Results").font(.headline)
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
