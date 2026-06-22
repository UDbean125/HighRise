import Foundation
import PDFKit

/// Pulls plain text out of `.docx` and `.pdf` files.
///
/// These formats don't carry a clean table of contacts the way CSV/Excel do, so
/// extraction is deliberately "get the text, then scan it" (see
/// `LooseContactExtractor`). PDFs use PDFKit; `.docx` is a ZIP whose
/// `word/document.xml` holds the text inside `<w:t>` runs.
enum DocumentTextExtractor {

    enum ExtractError: LocalizedError {
        case unreadablePDF
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .unreadablePDF:        return "The PDF couldn't be read (it may be scanned images rather than text)."
            case .unsupported(let ext): return "Can't extract text from .\(ext) files."
            }
        }
    }

    static func extractText(from url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":  return try extractPDF(url)
        case "docx": return try extractDocx(url)
        case let other: throw ExtractError.unsupported(other)
        }
    }

    private static func extractPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { throw ExtractError.unreadablePDF }
        var text = ""
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractError.unreadablePDF
        }
        return text
    }

    private static func extractDocx(_ url: URL) throws -> String {
        let data = try ZipEntryReader.entry("word/document.xml", in: url)
        return DocxTextParser.parse(data)
    }

    /// Concatenates `<w:t>` text runs, inserting a newline per `<w:p>` paragraph
    /// and a tab per `<w:tab>`, so table-ish layouts keep some structure.
    private final class DocxTextParser: NSObject, XMLParserDelegate {
        private var text = ""
        private var inText = false

        static func parse(_ data: Data) -> String {
            let parser = XMLParser(data: data)
            let delegate = DocxTextParser()
            parser.delegate = delegate
            parser.parse()
            return delegate.text
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            // Element names are namespace-qualified, e.g. "w:t", "w:p", "w:tab".
            switch elementName {
            case "w:t":   inText = true
            case "w:tab": text += "\t"
            default:      break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case "w:t": inText = false
            case "w:p": text += "\n"
            default:    break
            }
        }
    }
}

/// Best-effort recovery of contacts from unstructured text.
///
/// Word/PDF documents rarely carry a tidy table, so we find every email address
/// and pair it with the most plausible name nearby (the words just before the
/// address on the same line). The result is intentionally minimal —
/// `Name` + `Email` — and the review screen lets the user catch anything the
/// heuristic got wrong before a single message goes out.
enum LooseContactExtractor {
    private static let emailPattern = #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#

    static func table(from text: String) -> RecipientTable {
        guard let regex = try? NSRegularExpression(pattern: emailPattern, options: [.caseInsensitive]) else {
            return RecipientTable(headers: ["Name", "Email"], rows: [])
        }

        var rows: [[String]] = []
        var seen = Set<String>()

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\t", with: " ")
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                let email = nsLine.substring(with: match.range).trimmingCharacters(in: .whitespaces)
                let key = email.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)

                // Take the text preceding the address on this line as a name guess.
                let before = nsLine.substring(to: match.range.location)
                let name = guessName(from: before)
                rows.append([name, email])
            }
        }
        return RecipientTable(headers: ["Name", "Email"], rows: rows)
    }

    /// Pulls a name-like fragment from text preceding an email address: strips
    /// separators (`<`, `:`, `-`, `,`) and keeps the last few capitalized words.
    private static func guessName(from prefix: String) -> String {
        let cleaned = prefix
            .replacingOccurrences(of: "<", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let words = cleaned.split(separator: " ").map(String.init)
        let tail = words.suffix(3).filter { word in
            guard let first = word.first else { return false }
            return first.isUppercase
        }
        return tail.joined(separator: " ")
    }
}
