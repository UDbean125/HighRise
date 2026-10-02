import AppKit
import Foundation

/// macOS side of the Henbase hand-off. See `HenbaseBridge`.
extension HighRiseCoordinator {

    /// Handles a `highrise://import…` link from Henbase, or a CSV file
    /// opened with HighRise, then jumps to the Contacts step so the user sees
    /// the list (and its cleanup report) straight away.
    func handleIncoming(_ url: URL) async {
        if url.isFileURL {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            await importFile(at: url)
            stage = .contacts
            return
        }
        do {
            guard let inbound = try HenbaseBridge.inboundImport(from: url, pasteboardText: {
                NSPasteboard.general.string(forType: .string)
            }) else { return }
            await importCSV(inbound.csvText, sourceLabel: inbound.sourceLabel)
            if let hint = inbound.subjectHint,
               template.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                template.subject = hint
            }
        } catch {
            reportImportFailure(error.localizedDescription)
        }
        stage = .contacts
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Whether Henbase is installed on this Mac.
    var isHenbaseInstalled: Bool {
        guard let probe = URL(string: "\(HenbaseBridge.henScheme)://") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }

    /// Opens Henbase's list picker; it sends the chosen list back here.
    func requestListFromHenbase() {
        if let url = URL(string: "\(HenbaseBridge.henScheme)://highrise/export") {
            NSWorkspace.shared.open(url)
        }
    }

    /// True once a run has delivered something and Henbase can journal it.
    var canLogToHenbase: Bool {
        outcomes.contains(where: \.isSuccess) && isHenbaseInstalled
    }

    /// Sends this run's outcomes to Henbase, which logs one email per
    /// recipient in their relationship journal.
    @discardableResult
    func logRunToHenbase() -> Bool {
        let campaign = HenbaseBridge.campaign(
            subject: template.subject,
            mode: sendMode == .send ? "send" : "draft",
            sourceLabel: currentImportSource,
            outcomes: outcomes.map { ($0.contact.email, displayName(for: $0.contact),
                                      HenbaseBridge.statusString($0.status)) })
        guard let url = HenbaseBridge.logURL(for: campaign) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
