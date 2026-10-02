import AppKit
import Foundation

/// macOS side of the Hen Contacts hand-off. See `HenContactsBridge`.
extension HighRiseCoordinator {

    /// Handles a `highrise://import…` link from Hen Contacts, or a CSV file
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
            guard let inbound = try HenContactsBridge.inboundImport(from: url, pasteboardText: {
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

    /// Whether Hen Contacts is installed on this Mac.
    var isHenContactsInstalled: Bool {
        guard let probe = URL(string: "\(HenContactsBridge.henScheme)://") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }

    /// Opens Hen Contacts' list picker; it sends the chosen list back here.
    func requestListFromHenContacts() {
        if let url = URL(string: "\(HenContactsBridge.henScheme)://highrise/export") {
            NSWorkspace.shared.open(url)
        }
    }

    /// True once a run has delivered something and Hen Contacts can journal it.
    var canLogToHenContacts: Bool {
        outcomes.contains(where: \.isSuccess) && isHenContactsInstalled
    }

    /// Sends this run's outcomes to Hen Contacts, which logs one email per
    /// recipient in their relationship journal.
    @discardableResult
    func logRunToHenContacts() -> Bool {
        let campaign = HenContactsBridge.campaign(
            subject: template.subject,
            mode: sendMode == .send ? "send" : "draft",
            sourceLabel: currentImportSource,
            outcomes: outcomes.map { ($0.contact.email, displayName(for: $0.contact),
                                      HenContactsBridge.statusString($0.status)) })
        guard let url = HenContactsBridge.logURL(for: campaign) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
