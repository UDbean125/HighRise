import Foundation

/// Reads a worksheet of an `.xlsx` workbook into a `RecipientTable`.
///
/// `.xlsx` is an Open Packaging zip: shared text lives in `xl/sharedStrings.xml`
/// and each sheet's cells (in `xl/worksheets/sheetN.xml`) reference it by index.
/// The mapping from a visible tab *name* to its part path is declared in
/// `xl/workbook.xml` (sheet order + relationship id) and resolved through
/// `xl/_rels/workbook.xml.rels`. We unzip those entries (`ZipEntryReader`) and
/// parse them with Foundation's `XMLParser`. No third-party libraries.
///
/// Scope note: treats the first row as headers and renders every cell as text.
/// That covers the "names and emails" spreadsheet case. `read(_:)` picks the
/// first worksheet in the workbook's declared order; `worksheets(in:)` +
/// `read(_:sheetName:)` let the UI offer a tab picker for multi-sheet books.
enum XLSXReader {

    enum XLSXError: LocalizedError {
        case noWorksheet
        case empty
        case sheetNotFound(String)
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .noWorksheet:      return "Couldn't find a worksheet in the workbook."
            case .empty:            return "The worksheet is empty."
            case .sheetNotFound(let s): return "The workbook has no worksheet named “\(s)”."
            case .malformed(let m): return "The workbook couldn't be read: \(m)"
            }
        }
    }

    /// One visible worksheet: its tab name and the zip part path holding its cells.
    struct Worksheet: Equatable {
        let name: String
        /// Path inside the archive, e.g. `xl/worksheets/sheet3.xml`.
        let path: String
    }

    /// The workbook's worksheets in tab order, excluding hidden/very-hidden ones.
    ///
    /// Reads `xl/workbook.xml` for the ordered `<sheet name r:id state>` list and
    /// `xl/_rels/workbook.xml.rels` for the id → target mapping. The declared
    /// order — not filename numbering — is authoritative: `sheet1.xml` is not
    /// guaranteed to be the first tab once sheets are reordered or deleted.
    static func worksheets(in url: URL) throws -> [Worksheet] {
        guard let workbookData = try? ZipEntryReader.entry("xl/workbook.xml", in: url) else {
            throw XLSXError.noWorksheet
        }
        let sheets = WorkbookParser.parse(workbookData)
        guard !sheets.isEmpty else { throw XLSXError.noWorksheet }

        let rels: [String: String]
        if let relsData = try? ZipEntryReader.entry("xl/_rels/workbook.xml.rels", in: url) {
            rels = RelationshipsParser.parse(relsData)
        } else {
            rels = [:]
        }

        return sheets.compactMap { sheet -> Worksheet? in
            guard sheet.state.isEmpty else { return nil } // skip hidden / veryHidden
            guard let target = rels[sheet.relationshipID] else { return nil }
            return Worksheet(name: sheet.name, path: normalizedPart(target))
        }
    }

    /// Resolves a relationship target (which may be `worksheets/sheet1.xml`,
    /// `/xl/worksheets/sheet1.xml`, or already `xl/…`) to an archive-root path.
    static func normalizedPart(_ target: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        if target.hasPrefix("xl/") { return target }
        return "xl/" + target
    }

    // Test hooks: the workbook/relationships XML parsing is pure and worth
    // pinning directly, without needing a real .xlsx fixture on disk.
    static func WorkbookParser_forTesting(_ data: Data) -> [WorkbookSheet] {
        WorkbookParser.parse(data)
    }
    static func RelationshipsParser_forTesting(_ data: Data) -> [String: String] {
        RelationshipsParser.parse(data)
    }

    /// Reads the first worksheet in the workbook's declared tab order.
    static func read(_ url: URL) throws -> RecipientTable {
        let sheet = try worksheets(in: url).first
        // Fall back to the conventional path only if the workbook part is
        // unreadable, preserving behavior for minimal/hand-written archives.
        let path = sheet?.path ?? "xl/worksheets/sheet1.xml"
        return try read(url, sheetPath: path)
    }

    /// Reads the worksheet with the given visible tab name.
    static func read(_ url: URL, sheetName: String) throws -> RecipientTable {
        guard let sheet = try worksheets(in: url).first(where: { $0.name == sheetName }) else {
            throw XLSXError.sheetNotFound(sheetName)
        }
        return try read(url, sheetPath: sheet.path)
    }

    /// Reads the worksheet stored at `sheetPath` (e.g. `xl/worksheets/sheet2.xml`).
    static func read(_ url: URL, sheetPath: String) throws -> RecipientTable {
        // Shared strings are optional — a sheet of pure numbers has none.
        let sharedStrings: [String]
        if let data = try? ZipEntryReader.entry("xl/sharedStrings.xml", in: url) {
            sharedStrings = SharedStringsParser.parse(data)
        } else {
            sharedStrings = []
        }

        let sheetData = try ZipEntryReader.entry(sheetPath, in: url)
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

    // MARK: - Workbook (sheet order + names)

    /// A `<sheet>` entry as declared in `xl/workbook.xml`.
    struct WorkbookSheet: Equatable {
        let name: String
        let relationshipID: String
        /// "hidden" / "veryHidden" for concealed tabs; empty for visible.
        let state: String
    }

    private final class WorkbookParser: NSObject, XMLParserDelegate {
        private var sheets: [WorkbookSheet] = []

        static func parse(_ data: Data) -> [WorkbookSheet] {
            let parser = XMLParser(data: data)
            let delegate = WorkbookParser()
            parser.delegate = delegate
            parser.parse()
            return delegate.sheets
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            // Match on the local name so namespace prefixes (e.g. `x:sheet`) work.
            guard elementName.hasSuffix("sheet"), !elementName.hasSuffix("sheets") else { return }
            let name = attributeDict["name"] ?? ""
            // The relationship id attribute is namespaced (`r:id`); XMLParser
            // reports it with whatever prefix the document used.
            let rid = attributeDict["r:id"]
                ?? attributeDict.first(where: { $0.key.hasSuffix(":id") || $0.key == "id" })?.value
                ?? ""
            let state = (attributeDict["state"] ?? "").lowercased()
            guard !name.isEmpty, !rid.isEmpty else { return }
            sheets.append(WorkbookSheet(name: name, relationshipID: rid,
                                        state: state == "visible" ? "" : state))
        }
    }

    // MARK: - Relationships (rId → part path)

    private final class RelationshipsParser: NSObject, XMLParserDelegate {
        private var map: [String: String] = [:]

        static func parse(_ data: Data) -> [String: String] {
            let parser = XMLParser(data: data)
            let delegate = RelationshipsParser()
            parser.delegate = delegate
            parser.parse()
            return delegate.map
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            guard elementName.hasSuffix("Relationship") else { return }
            if let id = attributeDict["Id"], let target = attributeDict["Target"] {
                map[id] = target
            }
        }
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
