import SwiftUI

/// Stage 4: choose the client and mode, then create drafts or send. Draft-first
/// is the default — every message is built automatically (no per-email prompt),
/// landing in Drafts so the user reviews and sends on their own terms.
struct SendView: View {
    @EnvironmentObject private var coordinator: HighRiseCoordinator
    @State private var showConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                clientPicker
                modePicker
                envelopeControls
                if coordinator.sendMode == .send {
                    throttleControls
                }
                Divider()
                testSendRow
                Divider()
                actionRow
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
                Label("Apple Mail's automation only reliably sets plain text. For full HTML, use Outlook.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
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

    private var envelopeControls: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                envelopeField("CC", text: $coordinator.envelope.cc,
                              hint: "Visible to the recipient. Use a column like {{Parent Email}} or a fixed address; separate several with commas.")
                envelopeField("BCC", text: $coordinator.envelope.bcc,
                              hint: "Hidden from the recipient. Supports {{Field}} references too.")
                envelopeField("BCC myself", text: $coordinator.envelope.bccSelf,
                              hint: "A fixed address BCC'd on every message — a private delivery record, no tracking.")
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

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results").font(.headline)
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
