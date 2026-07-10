import Foundation

/// A minimal, dependency-free RFC 4180-style CSV reader.
///
/// Handles the cases real contact exports actually contain: quoted fields,
/// commas and newlines inside quotes, and escaped quotes (`""`). It does not
/// try to be a full CSV engine — it is exactly enough to turn a "names and
/// emails" spreadsheet export into rows we can map onto `Contact`.
enum CSVParser {

    enum ParseError: LocalizedError {
        case empty
        case noHeaderRow

        var errorDescription: String? {
            switch self {
            case .empty:        return "The file is empty."
            case .noHeaderRow:  return "The file has no header row."
            }
        }
    }

    /// Decodes raw file bytes into text, tolerating the encodings real exports
    /// use: UTF-8 (with or without BOM), UTF-16 (BOM-marked), and the common
    /// single-byte Windows/Latin encodings. Returns nil only if every attempt
    /// fails. A leading UTF-8 BOM is stripped so it can't corrupt the first
    /// header name.
    static func decode(_ data: Data) -> String? {
        // UTF-16 only when a BOM marks it — attempting .utf16 on single-byte text
        // (Latin-1/CP1252) can mis-decode into garbage instead of failing, so it
        // must NOT be in the general fallback chain.
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let s = String(data: data, encoding: .utf16) { return stripBOM(s) }
        }
        for encoding: String.Encoding in [.utf8, .windowsCP1252, .isoLatin1] {
            if let s = String(data: data, encoding: encoding) { return stripBOM(s) }
        }
        return nil
    }

    /// Removes a leading Unicode BOM (`U+FEFF`) if present.
    static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    /// The delimiter that best fits `text`: whichever of comma, semicolon, or tab
    /// occurs most on the header line (outside quotes). Semicolon-delimited
    /// European CSVs and tab-separated files are detected automatically.
    /// Defaults to comma when there's no clear winner.
    static func detectDelimiter(in text: String) -> Character {
        let firstLine = stripBOM(text).prefix { $0 != "\n" && $0 != "\r" }
        let candidates: [Character] = [",", ";", "\t"]
        var counts: [Character: Int] = [:]
        var inQuotes = false
        for ch in firstLine {
            if ch == "\"" { inQuotes.toggle() }
            else if !inQuotes, candidates.contains(ch) { counts[ch, default: 0] += 1 }
        }
        let maxCount = counts.values.max() ?? 0
        guard maxCount > 0 else { return "," }
        // Iterate in priority order so comma wins any tie.
        return candidates.first { counts[$0] == maxCount } ?? ","
    }

    /// Splits raw CSV text into a header row plus data rows. The delimiter is
    /// auto-detected (comma / semicolon / tab) unless one is given, and a leading
    /// BOM is stripped.
    static func parse(_ text: String, delimiter: Character? = nil) throws -> RecipientTable {
        let clean = stripBOM(text)
        let sep = delimiter ?? detectDelimiter(in: clean)
        let allRows = parseRows(clean, delimiter: sep)
        guard let header = allRows.first else { throw ParseError.empty }
        let headers = header.map { $0.trimmingCharacters(in: .whitespaces) }
        guard headers.contains(where: { !$0.isEmpty }) else { throw ParseError.noHeaderRow }

        // Drop fully-empty trailing rows (common with a trailing newline).
        let dataRows = allRows.dropFirst().filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return RecipientTable(headers: headers, rows: Array(dataRows))
    }

    /// The state-machine tokenizer. Returns one `[String]` per record, splitting
    /// fields on `delimiter`.
    static func parseRows(_ text: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        let scalars = Array(text)
        var i = 0

        func endField() { record.append(field); field = "" }
        func endRecord() { endField(); rows.append(record); record = [] }

        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    // Doubled quote inside a quoted field → literal quote.
                    if i + 1 < scalars.count && scalars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == delimiter {
                    endField()
                } else if c == "\r" {
                    // Swallow CR; a following LF is handled as the record break.
                    if i + 1 < scalars.count && scalars[i + 1] == "\n" {
                        i += 1
                    }
                    endRecord()
                } else if c == "\n" {
                    endRecord()
                } else {
                    field.append(c)
                }
            }
            i += 1
        }
        // Flush the final record if the file didn't end on a newline.
        if !field.isEmpty || !record.isEmpty {
            endRecord()
        }
        return rows
    }

    /// Maps a parsed table onto `Contact` values.
    ///
    /// - Parameter emailHeader: the column to treat as the email address.
    ///   When `nil`, a best-effort guess is made via `detectEmailColumn`.
    /// - Returns: the contacts plus the header that was actually used for email,
    ///   so the UI can show and let the user override the choice.
    static func contacts(from table: RecipientTable,
                         emailHeader: String? = nil) -> (contacts: [Contact], emailHeader: String?) {
        let chosen = emailHeader ?? detectEmailColumn(in: table)
        guard let emailKey = chosen,
              let emailIndex = table.headers.firstIndex(where: { $0.lowercased() == emailKey.lowercased() })
        else {
            return ([], chosen)
        }

        let contacts: [Contact] = table.rows.compactMap { row in
            var fields: [String: String] = [:]
            for (index, header) in table.headers.enumerated() where !header.isEmpty {
                let value = index < row.count ? row[index] : ""
                fields[header] = value.trimmingCharacters(in: .whitespaces)
            }
            let email = (emailIndex < row.count ? row[emailIndex] : "")
                .trimmingCharacters(in: .whitespaces)
            guard !email.isEmpty else { return nil }
            return Contact(fields: fields, email: email)
        }
        return (contacts, emailKey)
    }

    /// A row dropped from `contacts(from:emailHeader:)` because its email
    /// column was blank — named so the UI can show *which* rows were skipped,
    /// not just a bare count.
    struct SkippedRow: Identifiable, Equatable {
        let id = UUID()
        /// 1-based, counting the header as row 1 — matches how the row would
        /// be numbered if opened in Excel/Numbers.
        let rowNumber: Int
        /// The first couple of non-blank values in the row, so the row is
        /// recognizable without re-opening the source file.
        let preview: String
    }

    /// Rows from `table` that `contacts(from:emailHeader:)` silently drops
    /// because they have no value in the email column.
    static func skippedRows(from table: RecipientTable, emailHeader: String? = nil) -> [SkippedRow] {
        let chosen = emailHeader ?? detectEmailColumn(in: table)
        guard let emailKey = chosen,
              let emailIndex = table.headers.firstIndex(where: { $0.lowercased() == emailKey.lowercased() })
        else {
            return []
        }

        return table.rows.enumerated().compactMap { offset, row in
            let email = (emailIndex < row.count ? row[emailIndex] : "")
                .trimmingCharacters(in: .whitespaces)
            guard email.isEmpty else { return nil }
            let nonBlank = table.headers.enumerated().compactMap { index, header -> String? in
                guard !header.isEmpty, index < row.count else { return nil }
                let value = row[index].trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
            let preview = nonBlank.prefix(2).joined(separator: ", ")
            return SkippedRow(rowNumber: offset + 2,
                               preview: preview.isEmpty ? "(blank row)" : preview)
        }
    }

    /// Picks the most likely email column: first a header that mentions "email",
    /// otherwise the column whose values most often look like addresses.
    static func detectEmailColumn(in table: RecipientTable) -> String? {
        if let named = table.headers.first(where: {
            let h = $0.lowercased()
            return h.contains("email") || h.contains("e-mail") || h == "mail"
        }) {
            return named
        }
        var bestHeader: String?
        var bestScore = 0
        for (index, header) in table.headers.enumerated() where !header.isEmpty {
            let score = table.rows.reduce(0) { acc, row in
                guard index < row.count else { return acc }
                return acc + (EmailValidator.isValid(row[index]) ? 1 : 0)
            }
            if score > bestScore {
                bestScore = score
                bestHeader = header
            }
        }
        return bestHeader
    }
}
