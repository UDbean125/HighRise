import Testing
import Foundation
@testable import HighRise

/// Fixtures generated with Python's stdlib `zipfile` (not this code), so
/// these tests exercise the pure-Swift reader against real, independently
/// produced zip archives rather than round-tripping through itself.
struct ZipEntryReaderTests {

    /// A multi-entry, DEFLATE-compressed archive shaped like a real `.xlsx` —
    /// `xl/workbook.xml`, `xl/sharedStrings.xml`, `xl/worksheets/sheet1.xml`.
    private static let deflateArchiveBase64 = """
    UEsDBBQAAAAIACm08Fx8qnaiNAAAALAEAAAPAAAAeGwvd29ya2Jvb2sueG1ssynPL8pOys/PtrMp\
    zkhNLSmG0gp5ibmptkrBILahkr6djT5MWh+hY1TvqN5RvaN66agXAFBLAwQUAAAACAAptPBcoTXp\
    tiUAAAA1AAAAFAAAAHhsL3NoYXJlZFN0cmluZ3MueG1ssykuLrGzKc60symx80jNycm30Qfy9UEC\
    EMHw/KKcFISgPkg9AFBLAwQUAAAACAAptPBcX/AAVi0AAAA4AAAAGAAAAHhsL3dvcmtzaGVldHMv\
    c2hlZXQxLnhtbLMpzy/KLs5ITS2xsynKL7ezSVYoslVyNFSysymzM7DRL7Oz0U8GYrCcPkIxAFBL\
    AQIUAxQAAAAIACm08Fx8qnaiNAAAALAEAAAPAAAAAAAAAAAAAACAAQAAAAB4bC93b3JrYm9vay54\
    bWxQSwECFAMUAAAACAAptPBcoTXptiUAAAA1AAAAFAAAAAAAAAAAAAAAgAFhAAAAeGwvc2hhcmVk\
    U3RyaW5ncy54bWxQSwECFAMUAAAACAAptPBcX/AAVi0AAAA4AAAAGAAAAAAAAAAAAAAAgAG4AAAA\
    eGwvd29ya3NoZWV0cy9zaGVldDEueG1sUEsFBgAAAAADAAMAxQAAABsBAAAAAA==
    """

    /// A single-entry, uncompressed ("stored") archive shaped like a
    /// minimal `.docx` — `word/document.xml`.
    private static let storedArchiveBase64 = """
    UEsDBBQAAAAAAJS08FxOJ0zZOwAAADsAAAARAAAAd29yZC9kb2N1bWVudC54bWw8ZG9jdW1lbnQ+\
    PGJvZHk+PHA+UGxhaW4gc3RvcmVkIHRleHQuPC9wPjwvYm9keT48L2RvY3VtZW50PlBLAQIUAxQA\
    AAAAAJS08FxOJ0zZOwAAADsAAAARAAAAAAAAAAAAAACAAQAAAAB3b3JkL2RvY3VtZW50LnhtbFBL\
    BQYAAAAAAQABAD8AAABqAAAAAAA=
    """

    private static var deflateArchive: Data { Data(base64Encoded: deflateArchiveBase64, options: .ignoreUnknownCharacters)! }
    private static var storedArchive: Data { Data(base64Encoded: storedArchiveBase64, options: .ignoreUnknownCharacters)! }

    @Test("Reads a deflate-compressed entry from a multi-entry archive")
    func deflateEntry() throws {
        let data = try ZipEntryReader.entry("xl/sharedStrings.xml", in: Self.deflateArchive)
        let text = String(data: data, encoding: .utf8)
        #expect(text == "<sst><si><t>Hello</t></si><si><t>World</t></si></sst>")
    }

    @Test("Reads every entry in a multi-entry deflate archive, not just the first")
    func deflateAllEntries() throws {
        let workbook = try ZipEntryReader.entry("xl/workbook.xml", in: Self.deflateArchive)
        #expect(String(data: workbook, encoding: .utf8) == String(repeating: "<workbook><sheets><sheet name=\"Sheet1\"/></sheets></workbook>", count: 20))

        let sheet = try ZipEntryReader.entry("xl/worksheets/sheet1.xml", in: Self.deflateArchive)
        #expect(String(data: sheet, encoding: .utf8) == "<worksheet><row><c r=\"A1\"><v>0</v></c></row></worksheet>")
    }

    @Test("Reads a stored (uncompressed) entry")
    func storedEntry() throws {
        let data = try ZipEntryReader.entry("word/document.xml", in: Self.storedArchive)
        let text = String(data: data, encoding: .utf8)
        #expect(text == "<document><body><p>Plain stored text.</p></body></document>")
    }

    @Test("Throws entryNotFound for a name that isn't in the archive")
    func missingEntry() {
        #expect(throws: ZipEntryReader.ZipError.self) {
            try ZipEntryReader.entry("does/not/exist.xml", in: Self.storedArchive)
        }
    }

    @Test("Throws malformed for data that isn't a zip archive at all")
    func notAZip() {
        let junk = Data("this is not a zip file".utf8)
        #expect(throws: ZipEntryReader.ZipError.self) {
            try ZipEntryReader.entry("anything", in: junk)
        }
    }

    @Test("Throws malformed for data too short to hold an end-of-central-directory record")
    func tooShort() {
        let tiny = Data([0x50, 0x4b, 0x03, 0x04])
        #expect(throws: ZipEntryReader.ZipError.self) {
            try ZipEntryReader.entry("anything", in: tiny)
        }
    }
}
