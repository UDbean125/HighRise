import Foundation
import AppKit
import PDFKit

/// Renders a merged message body to a PDF file, optionally password-protected.
///
/// Uses first-party Apple frameworks only (AppKit text layout + PDFKit), so it
/// fits the "Apple SDK only, no servers" rule and generates the personalized
/// PDFs entirely on-device. Rendering runs on the main actor because AppKit text
/// views require it.
///
/// Note: this AppKit rendering path can't be exercised in the Linux CI; the pure
/// filename logic (`PDFFilename`) is unit-tested, and this renderer should be
/// smoke-tested on a Mac. Output is single-page-per-document sized to the
/// content (fine for invoices/letters); multi-page pagination via
/// `NSPrintOperation` is a future refinement.
@MainActor
enum PDFComposer {

    enum PDFError: LocalizedError {
        case renderFailed
        var errorDescription: String? { "Couldn't render the PDF." }
    }

    /// US Letter width in points; height grows to fit the content.
    private static let pageWidth: CGFloat = 612
    private static let margin: CGFloat = 54

    /// Renders `content` (HTML or plain text) to PDF and writes it to `url`.
    /// When `password` is non-empty the PDF is encrypted (user + owner password).
    static func write(content: String, isHTML: Bool, to url: URL, password: String? = nil) throws {
        guard let data = pdfData(content: content, isHTML: isHTML) else { throw PDFError.renderFailed }

        let pw = password?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pw, !pw.isEmpty, let document = PDFDocument(data: data) {
            document.write(to: url, withOptions: [
                .userPasswordOption: pw,
                .ownerPasswordOption: pw,
            ])
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    /// Lays the content into an off-screen text view sized to fit, then captures
    /// it as PDF data.
    static func pdfData(content: String, isHTML: Bool) -> Data? {
        let attributed = attributedString(content: content, isHTML: isHTML)
        let textWidth = pageWidth - margin * 2

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: textWidth, height: 10))
        textView.isEditable = false
        textView.textStorage?.setAttributedString(attributed)
        textView.sizeToFit()
        let contentHeight = max(textView.frame.height, 100)

        let page = NSView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: contentHeight + margin * 2))
        textView.frame = NSRect(x: margin, y: margin, width: textWidth, height: contentHeight)
        page.addSubview(textView)
        return page.dataWithPDF(inside: page.bounds)
    }

    private static func attributedString(content: String, isHTML: Bool) -> NSAttributedString {
        if isHTML, let data = content.data(using: .utf8),
           let html = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil) {
            return html
        }
        return NSAttributedString(string: content,
                                  attributes: [.font: NSFont.systemFont(ofSize: 12)])
    }
}
