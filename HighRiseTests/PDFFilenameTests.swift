import Testing
@testable import HighRise

/// Per-recipient PDF filenames come from user-supplied patterns and recipient
/// data, so sanitization (no path escapes, no illegal characters) is pinned.
struct PDFFilenameTests {

    private func contact(_ fields: [String: String], email: String = "a@b.com") -> Contact {
        Contact(fields: fields, email: email)
    }

    @Test("A pattern resolves placeholders and keeps the .pdf extension")
    func resolvesPattern() {
        let name = PDFFilename.make(pattern: "{{Full Name}} - invoice.pdf",
                                    contact: contact(["Full Name": "Ada Lovelace"]),
                                    fallback: "a@b.com")
        #expect(name == "Ada Lovelace - invoice.pdf")
    }

    @Test("A .pdf extension is added when the pattern omits it")
    func addsExtension() {
        let name = PDFFilename.make(pattern: "{{Full Name}}",
                                    contact: contact(["Full Name": "Bo"]), fallback: "x@y.com")
        #expect(name == "Bo.pdf")
    }

    @Test("Path separators and illegal characters are neutralized")
    func sanitizesIllegal() {
        let name = PDFFilename.make(pattern: "{{Company}}.pdf",
                                    contact: contact(["Company": "A/B:C*D?\"E<>|F"]),
                                    fallback: "x@y.com")
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
        #expect(!name.contains("*"))
        #expect(name.hasSuffix(".pdf"))
    }

    @Test("A path-traversal attempt can't escape the folder")
    func blocksTraversal() {
        let name = PDFFilename.make(pattern: "{{X}}.pdf",
                                    contact: contact(["X": "../../etc/passwd"]),
                                    fallback: "x@y.com")
        #expect(!name.contains("/"))
        #expect(!name.hasPrefix("."))
    }

    @Test("An empty resolved name falls back to the sanitized fallback")
    func usesFallback() {
        let name = PDFFilename.make(pattern: "{{Missing}}",
                                    contact: contact([:]), fallback: "ada@example.com")
        #expect(name == "ada@example.com.pdf")
    }

    @Test("Leading dots are stripped so no hidden file is produced")
    func stripsLeadingDots() {
        #expect(!PDFFilename.sanitize("...secret").hasPrefix("."))
    }
}
