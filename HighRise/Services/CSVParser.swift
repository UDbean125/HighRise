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

    /// Splits raw CSV text into a header row plus data rows.
    static func parse(_ text: String) throws -> RecipientTable {
        let allRows = parseRows(text)
        guard let header = allRows.first else { throw ParseError.empty }
        let headers = header.map { $0.trimmingCharacters(in: .whitespaces) }
        guard headers.contains(where: { !$0.isEmpty }) else { throw ParseError.noHeaderRow }

        // Drop fully-empty trailing rows (common with a trailing newline).
        let dataRows = allRows.dropFirst().filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return RecipientTable(headers: headers, rows: Array(dataRows))
    }

    /// The state-machine tokenizer. Returns one `[String]` per record.
    static func parseRows(_ text: String) -> [[String]] {
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
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    endField()
                case "\r":
                    // Swallow CR; a following LF is handled as the record break.
                    if i + 1 < scalars.count && scalars[i + 1] == "\n" {
                        i += 1
                    }
                    endRecord()
                case "\n":
                    endRecord()
                default:
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
