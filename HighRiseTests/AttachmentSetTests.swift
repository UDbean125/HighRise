import Testing
import Foundation
@testable import HighRise

/// Attachment size math and the oversize threshold gate whether a run starts,
/// so they're pinned with injected existence/size so no real files are needed.
struct AttachmentSetTests {

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test("Missing files are exactly those that fail the existence check")
    func missingFiles() {
        let urls = [url("/a/here.pdf"), url("/a/gone.pdf")]
        let missing = AttachmentSet.missing(urls, existsAt: { $0 == "/a/here.pdf" })
        #expect(missing == [url("/a/gone.pdf")])
    }

    @Test("Total bytes sums file sizes, treating unreadable as zero")
    func totals() {
        let urls = [url("/a"), url("/b"), url("/c")]
        let sizes: [String: Int64] = ["/a": 100, "/b": 50] // /c unreadable
        let total = AttachmentSet.totalBytes(urls, sizeOf: { sizes[$0.path] })
        #expect(total == 150)
    }

    @Test("Oversize warning only fires above the threshold")
    func warnsAboveThreshold() {
        #expect(AttachmentSet.oversizeWarning(totalBytes: 1_000) == nil)
        #expect(AttachmentSet.oversizeWarning(totalBytes: AttachmentSet.warningThresholdBytes) == nil)
        let warning = AttachmentSet.oversizeWarning(totalBytes: AttachmentSet.warningThresholdBytes + 1)
        #expect(warning != nil)
        #expect(warning?.contains("MB") == true)
    }
}
