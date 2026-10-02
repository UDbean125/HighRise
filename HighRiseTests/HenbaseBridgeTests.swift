import Testing
import Foundation
@testable import HighRise

/// Pins the Henbase hand-off: the `highrise://import` link format Hen
/// sends, the `henbase://highrise/log` payload HighRise sends back, and the
/// coordinator landing an incoming list on the Contacts step.
struct HenbaseBridgeTests {

    private let csv = "First Name,Last Name,Email,Company,Next Step\nDana,Whitfield,dwhitfield@harborline-arch.com,Harborline Architects,Send pilot plan\nTom,Brandt,tbrandt@meridiancivil.com,\"Meridian Civil Group, Inc.\",Book lunch-and-learn\n"

    private func importLink(csv: String, source: String = "Henbase – Clients", subject: String? = nil) -> URL {
        var c = URLComponents()
        c.scheme = "highrise"
        c.host = "import"
        c.queryItems = [URLQueryItem(name: "source", value: source),
                        URLQueryItem(name: "csv", value: HenbaseBridge.base64URLEncode(Data(csv.utf8)))]
        if let subject { c.queryItems?.append(URLQueryItem(name: "subject", value: subject)) }
        return c.url!
    }

    @Test("base64url round-trips bytes that need + and / in plain base64")
    func base64URL() {
        let data = Data([0xfb, 0xff, 0xbf, 0x00, 0x3e, 0x3f])
        let encoded = HenbaseBridge.base64URLEncode(data)
        #expect(!encoded.contains("+") && !encoded.contains("/") && !encoded.contains("="))
        #expect(HenbaseBridge.base64URLDecode(encoded) == data)
    }

    @Test("An import link carries the CSV, source label and subject hint")
    func inboundFromLink() throws {
        let link = importLink(csv: csv, subject: "Q4 renewal check-in")
        let inbound = try #require(try HenbaseBridge.inboundImport(from: link, pasteboardText: { nil }))
        #expect(inbound.csvText == csv)
        #expect(inbound.sourceLabel == "Henbase – Clients")
        #expect(inbound.subjectHint == "Q4 renewal check-in")
    }

    @Test("Large lists can travel by pasteboard, read only when asked")
    func inboundFromPasteboard() throws {
        let link = URL(string: "highrise://import?from=pasteboard&source=Hen%20Contacts")!
        var pasteboardReads = 0
        let inbound = try HenbaseBridge.inboundImport(from: link, pasteboardText: { pasteboardReads += 1; return csv })
        #expect(inbound?.csvText == csv)
        #expect(pasteboardReads == 1)

        _ = try HenbaseBridge.inboundImport(from: importLink(csv: csv), pasteboardText: { pasteboardReads += 1; return nil })
        #expect(pasteboardReads == 1)
    }

    @Test("Other links are ignored; malformed ones explain the problem")
    func rejects() throws {
        #expect(try HenbaseBridge.inboundImport(from: URL(string: "highrise://compose")!, pasteboardText: { nil }) == nil)
        #expect(try HenbaseBridge.inboundImport(from: URL(string: "https://example.com/import")!, pasteboardText: { nil }) == nil)
        #expect(throws: HenbaseBridge.BridgeError.missingPayload) {
            try HenbaseBridge.inboundImport(from: URL(string: "highrise://import?source=Hen")!, pasteboardText: { nil })
        }
        #expect(throws: HenbaseBridge.BridgeError.unreadablePayload) {
            try HenbaseBridge.inboundImport(from: URL(string: "highrise://import?csv=%%%")!, pasteboardText: { nil })
        }
    }

    @Test("The log link round-trips the campaign Henbase journals")
    func logRoundTrip() throws {
        let campaign = HenbaseBridge.campaign(
            subject: "Renewal check-in", mode: "send", sourceLabel: "Henbase – Clients",
            sentAt: Date(timeIntervalSince1970: 1_790_000_000),
            outcomes: [("dwhitfield@harborline-arch.com", "Dana Whitfield", "sent"),
                       ("", "No Address", "skipped"),
                       ("tbrandt@meridiancivil.com", "Tom Brandt", "failed")])
        #expect(campaign.recipients.count == 2)
        #expect(campaign.deliveredCount == 1)
        let url = try #require(HenbaseBridge.logURL(for: campaign))
        #expect(url.scheme == "henbase")
        #expect(url.host == "highrise")
        #expect(url.path == "/log")
        #expect(HenbaseBridge.campaign(fromLogURL: url) == campaign)
    }

    @Test("Only lists that came from Henbase are treated as Hen sources")
    func henSource() {
        #expect(HenbaseBridge.isHenSource("Henbase – Clients gone quiet"))
        #expect(!HenbaseBridge.isHenSource("contacts.csv"))
        #expect(!HenbaseBridge.isHenSource(nil))
    }

    @MainActor
    @Test("An incoming Hen list loads, keeps its label, and opens the Contacts step")
    func coordinatorIngestsLink() async {
        let coordinator = HighRiseCoordinator.hermetic()
        await coordinator.handleIncoming(importLink(csv: csv, subject: "Q4 renewal check-in"))
        #expect(coordinator.contacts.count == 2)
        #expect(coordinator.stage == .contacts)
        #expect(coordinator.currentImportSource == "Henbase – Clients")
        #expect(coordinator.template.subject == "Q4 renewal check-in")
        #expect(coordinator.importError == nil)
    }

    @MainActor
    @Test("A Hen list that arrives while the last session restores is still saved")
    func handoffDuringRestoreStillSaves() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HenBridge-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        func coordinator() -> HighRiseCoordinator {
            HighRiseCoordinator(sessionStore: SessionStore(directory: directory),
                                library: TemplateLibraryStore(directory: directory),
                                runLog: SendRunLogStore(directory: nil))
        }
        let first = coordinator()
        await first.importCSV("Name,Email\nOld,old@example.com\n")
        first.saveSessionNow()

        // Launch with a saved session (restore in flight) and a Hen link.
        let second = coordinator()
        await second.handleIncoming(importLink(csv: csv))
        for _ in 0..<200 where second.isImporting { try? await Task.sleep(nanoseconds: 25_000_000) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(second.contacts.count == 2)
        second.saveSessionNow()

        let third = coordinator()
        for _ in 0..<200 where third.contacts.isEmpty || third.isImporting { try? await Task.sleep(nanoseconds: 25_000_000) }
        #expect(third.currentImportSource == "Henbase – Clients",
                "the hand-off must not leave session saving switched off")
        #expect(third.contacts.count == 2)
    }
}
