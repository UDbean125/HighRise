import Foundation

/// Reads the first worksheet of an `.xlsx` workbook into a `RecipientTable`.
///
/// `.xlsx` is an Open Packaging zip: shared text lives in `xl/sharedStrings.xml`
/// and cells in `xl/worksheets/sheet1.xml` reference it by index. We unzip those
/// two entries (`ZipEntryReader`) and parse them with Foundation's `XMLParser`.
/// No third-party libraries.
///
/// Scope note: reads the **first** worksheet, treats its first row as headers,
/// and renders every cell as text. That covers the "names and emails"
/// spreadsheet case; multi-sheet selection is a future enhancement.
enum XLSXReader {

    enum XLSXError: LocalizedError {
        case noWorksheet
        case empty
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .noWorksheet:      return "Couldn't find a worksheet in the workbook."
            case .empty:            return "The first worksheet is empty."
            case .malformed(let m): return "The workbook couldn't be read: \(m)"
            }
        }
    }

    static func read(_ url: URL) throws -> RecipientTable {
        // Shared strings are optional — a sheet of pure numbers has none.
        let sharedStrings: [String]
        if let data = try? ZipEntryReader.entry("xl/sharedStrings.xml", in: url) {
            sharedStrings = SharedStringsParser.parse(data)
        } else {
            sharedStrings = []
        }

        let sheetData = try ZipEntryReader.entry("xl/worksheets/sheet1.xml", in: url)
        let grid = SheetParser.parse(sheetData, sharedStrings: sharedStrings)
        guard let headerRow = grid.first else { throw XLSXError.empty }

        let headers = headerRow.map { $0.trimmingCharacters(in: .whitespaces) }
        guard headers.contains(where: { !$0.isEmpty }) else { throw XLSXError.empty }

        let dataRows = grid.dropFirst().filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return RecipientTable(headers: headers, rows: Array(dataRows))
    }

    /// Converts a spreadsheet cell reference's column letters to a 0-based index
    /// ("A" → 0, "B" → 1, "AA" → 26).
    static func columnIndex(fromCellRef ref: String) -> Int {
        var index = 0
        for ch in ref {
            guard ch.isLetter, let value = ch.uppercased().unicodeScalars.first?.value else { break }
            index = index * 26 + Int(value - 64) // 'A' (65) → 1
        }
        return max(0, index - 1)
    }

    // MARK: - Shared strings

    private final class SharedStringsParser: NSObject, XMLParserDelegate {
        private var strings: [String] = []
        private var current = ""
        private var inText = false

        static func parse(_ data: Data) -> [String] {
            let parser = XMLParser(data: data)
            let delegate = SharedStringsParser()
            parser.delegate = delegate
            parser.parse()
            return delegate.strings
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            switch elementName {
            case "si": current = ""
            case "t":  inText = true
            default:   break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { current += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case "t":  inText = false
            case "si": strings.append(current)
            default:   break
            }
        }
    }

    // MARK: - Worksheet

    private final class SheetParser: NSObject, XMLParserDelegate {
        private let sharedStrings: [String]
        private var rows: [[Int: String]] = []
        private var maxColumn = 0

        private var currentRow: [Int: String] = [:]
        private var currentColumn = 0
        private var currentType = ""
        private var currentValue = ""
        private var inValue = false
        private var inInlineText = false

        init(sharedStrings: [String]) { self.sharedStrings = sharedStrings }

        static func parse(_ data: Data, sharedStrings: [String]) -> [[String]] {
            let parser = XMLParser(data: data)
            let delegate = SheetParser(sharedStrings: sharedStrings)
            parser.delegate = delegate
            parser.parse()
            return delegate.normalizedRows()
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            switch elementName {
            case "row":
                currentRow = [:]
            case "c":
                currentType = attributeDict["t"] ?? ""
                currentColumn = XLSXReader.columnIndex(fromCellRef: attributeDict["r"] ?? "")
                currentValue = ""
            case "v":
                inValue = true
                currentValue = ""
            case "t":
                inInlineText = true // inline string <is><t>
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inValue || inInlineText { currentValue += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case "v":
                inValue = false
            case "t":
                inInlineText = false
            case "c":
                let resolved: String
                if currentType == "s", let idx = Int(currentValue), idx >= 0, idx < sharedStrings.count {
                    resolved = sharedStrings[idx]
                } else {
                    resolved = currentValue
                }
                currentRow[currentColumn] = resolved
                maxColumn = max(maxColumn, currentColumn)
            case "row":
                rows.append(currentRow)
            default:
                break
            }
        }

        /// Flattens the sparse per-row dictionaries into dense, equal-width rows.
        func normalizedRows() -> [[String]] {
            let width = maxColumn + 1
            return rows.map { dict in
                (0..<width).map { dict[$0] ?? "" }
            }
        }
    }
}
