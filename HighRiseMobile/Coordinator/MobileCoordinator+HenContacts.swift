import UIKit

/// iOS side of the Hen Contacts hand-off. See `HenContactsBridge`.
extension MobileCoordinator {

    /// Imports a list from a `highrise://import…` link or an opened CSV file.
    /// Returns true when a list loaded, so the caller can show the Import screen.
    @discardableResult
    func handleIncoming(_ url: URL) -> Bool {
        if url.isFileURL {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                importError = "Couldn't open \(url.lastPathComponent)."
                return false
            }
            importCSV(data: data, sourceLabel: url.lastPathComponent)
            return importError == nil
        }
        do {
            guard let inbound = try HenContactsBridge.inboundImport(from: url, pasteboardText: {
                UIPasteboard.general.string
            }) else { return false }
            importCSV(data: Data(inbound.csvText.utf8), sourceLabel: inbound.sourceLabel)
            if let hint = inbound.subjectHint,
               template.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                template.subject = hint
            }
            return importError == nil
        } catch {
            importError = error.localizedDescription
            return false
        }
    }

    /// Whether Hen Contacts is installed (needs `hencontacts` in LSApplicationQueriesSchemes).
    var isHenContactsInstalled: Bool {
        guard let probe = URL(string: "\(HenContactsBridge.henScheme)://") else { return false }
        return UIApplication.shared.canOpenURL(probe)
    }

    /// Hen Contacts' list picker, which sends the chosen list back here.
    var henListPickerURL: URL? { URL(string: "\(HenContactsBridge.henScheme)://highrise/export") }

    /// A `hencontacts://highrise/log…` link journaling this session's outcomes.
    func henLogURL(for queue: SendQueue) -> URL? {
        let campaign = HenContactsBridge.campaign(
            subject: template.subject,
            mode: "send",
            sourceLabel: nil,
            outcomes: queue.outcomes.map { ($0.contact.email, $0.contact.displayName,
                                            HenContactsBridge.statusString($0.status)) })
        return HenContactsBridge.logURL(for: campaign)
    }
}
