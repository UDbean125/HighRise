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

    @Test("A column value splits on ; and expands ~")
    func parsesColumnPaths() {
        let paths = AttachmentSet.paths(fromColumnValue: " ~/Docs/a.pdf ; /tmp/b.pdf ;; ~",
                                        homeDirectory: "/Users/me")
        #expect(paths == ["/Users/me/Docs/a.pdf", "/tmp/b.pdf", "/Users/me"])
    }

    @Test("A blank column value yields no paths")
    func parsesBlank() {
        #expect(AttachmentSet.paths(fromColumnValue: "   ", homeDirectory: "/Users/me").isEmpty)
    }

    @Test("Human byte labels scale from bytes to GB")
    func humanBytes() {
        #expect(AttachmentSet.humanBytes(0) == "0 bytes")
        #expect(AttachmentSet.humanBytes(512) == "512 bytes")
        #expect(AttachmentSet.humanBytes(1023) == "1023 bytes")
        #expect(AttachmentSet.humanBytes(1024) == "1.0 KB")
        #expect(AttachmentSet.humanBytes(1536) == "1.5 KB")
        #expect(AttachmentSet.humanBytes(1_048_576) == "1.0 MB")
        #expect(AttachmentSet.humanBytes(1_048_576 * 3 / 2) == "1.5 MB")
        #expect(AttachmentSet.humanBytes(1_073_741_824) == "1.0 GB")
        // 200 MB: at/above 100 in its unit, drop the decimal.
        #expect(AttachmentSet.humanBytes(200 * 1_048_576) == "200 MB")
    }
}
