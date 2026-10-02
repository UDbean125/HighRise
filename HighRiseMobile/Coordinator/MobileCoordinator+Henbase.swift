import UIKit

/// iOS side of the Henbase hand-off. See `HenbaseBridge`.
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
            guard let inbound = try HenbaseBridge.inboundImport(from: url, pasteboardText: {
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

    /// Whether Henbase is installed (needs `henbase` in LSApplicationQueriesSchemes).
    var isHenbaseInstalled: Bool {
        guard let probe = URL(string: "\(HenbaseBridge.henScheme)://") else { return false }
        return UIApplication.shared.canOpenURL(probe)
    }

    /// Henbase's list picker, which sends the chosen list back here.
    var henListPickerURL: URL? { URL(string: "\(HenbaseBridge.henScheme)://highrise/export") }

    /// A `henbase://highrise/log…` link journaling this session's outcomes.
    func henLogURL(for queue: SendQueue) -> URL? {
        let campaign = HenbaseBridge.campaign(
            subject: template.subject,
            mode: "send",
            sourceLabel: nil,
            outcomes: queue.outcomes.map { ($0.contact.email, $0.contact.displayName,
                                            HenbaseBridge.statusString($0.status)) })
        return HenbaseBridge.logURL(for: campaign)
    }
}
