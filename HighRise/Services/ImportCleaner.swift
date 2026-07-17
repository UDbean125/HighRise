import Foundation

/// Repairs the messy realities of real-world contact/company exports at import
/// time, so a large list is usable without a spreadsheet-cleaning detour.
///
/// Two tiers, mirroring the app's "never silently break data" ethos:
///
/// - **Auto-clean** (`autoClean`): mechanical fixes no one would object to —
///   stray/invisible whitespace, spreadsheet junk tokens (`#N/A`, `NULL`),
///   repeated header rows from concatenated exports, and unambiguous email
///   repairs (`mailto:`, `Name <addr>`, stray edge punctuation). Every fix is
///   counted and reported, and the caller keeps the raw table so cleanup can
///   be turned off entirely.
/// - **Suggestions** (`suggestions(for:emailColumn:)`): judgment calls —
///   misspelled mail domains, SHOUTING-case names/companies, "Last, First"
///   name order — surfaced with counts and examples but applied only when the
///   user asks (`apply(_:to:)`).
///
/// Everything here is pure and Foundation-only so it is unit-testable and
/// shared by every import source (CSV, Excel, Word/PDF, Contacts, Outlook).
enum ImportCleaner {

    // MARK: - Report

    /// One category of auto-applied repair, with a small sample of what
    /// changed so the import screen can show its work.
    struct Change: Equatable, Identifiable {
        enum Kind: String, CaseIterable {
            case whitespace
            case junkValue
            case emailRepair
            case repeatedHeaderRow
        }

        let kind: Kind
        let count: Int
        let examples: [Example]

        var id: String { kind.rawValue }

        /// User-facing one-liner for the import screen.
        var summary: String {
            let s = count == 1 ? "" : "s"
            switch kind {
            case .whitespace:
                return "Removed stray spaces and invisible characters from \(count) value\(s)."
            case .junkValue:
                return "Cleared \(count) spreadsheet junk value\(s) (like “#N/A” and “NULL”) so those rows are held for real data instead of merging junk."
            case .emailRepair:
                return "Repaired \(count) email address\(s) (removed “mailto:”, brackets, or stray punctuation)."
            case .repeatedHeaderRow:
                return "Removed \(count) repeated header row\(s) mixed into the data."
            }
        }
    }

    /// A before → after sample of one repaired value.
    struct Example: Equatable {
        let before: String
        let after: String
    }

    /// Everything `autoClean` changed, for the import screen to disclose.
    struct Report: Equatable {
        let changes: [Change]

        var totalFixes: Int { changes.reduce(0) { $0 + $1.count } }
        var isEmpty: Bool { changes.isEmpty }

        static let empty = Report(changes: [])
    }

    /// Accumulates per-kind counts and up to `maxExamples` samples, preserving
    /// a stable kind order in the final report.
    private struct ChangeCollector {
        private static let maxExamples = 3
        private var counts: [Change.Kind: Int] = [:]
        private var examples: [Change.Kind: [Example]] = [:]

        mutating func record(_ kind: Change.Kind, before: String, after: String, withExample: Bool = true) {
            counts[kind, default: 0] += 1
            if withExample, examples[kind, default: []].count < Self.maxExamples {
                examples[kind, default: []].append(Example(before: before, after: after))
            }
        }

        var report: Report {
            let changes = Change.Kind.allCases.compactMap { kind -> Change? in
                guard let count = counts[kind], count > 0 else { return nil }
                return Change(kind: kind, count: count, examples: examples[kind] ?? [])
            }
            return Report(changes: changes)
        }
    }

    // MARK: - Auto-clean

    /// Applies every safe, mechanical repair to `table` and reports what
    /// changed. `emailColumn` names the address column when the caller already
    /// knows it; otherwise it is auto-detected for the email-repair pass.
    static func autoClean(_ table: RecipientTable,
                          emailColumn: String? = nil) -> (table: RecipientTable, report: Report) {
        var collector = ChangeCollector()

        // Headers get the same whitespace scrub as values (Excel headers often
        // carry non-breaking spaces that break {{placeholder}} matching).
        let headers = table.headers.map { header -> String in
            let cleaned = normalizeWhitespace(header)
            if cleaned != header { collector.record(.whitespace, before: header, after: cleaned) }
            return cleaned
        }

        var rows: [[String]] = []
        rows.reserveCapacity(table.rows.count)
        for row in table.rows {
            if isRepeatedHeaderRow(row, headers: headers) {
                collector.record(.repeatedHeaderRow, before: "", after: "", withExample: false)
                continue
            }
            rows.append(row.map { cell in
                var value = normalizeWhitespace(cell)
                if value != cell { collector.record(.whitespace, before: cell, after: value) }
                if isJunkValue(value) {
                    collector.record(.junkValue, before: value, after: "")
                    value = ""
                }
                return value
            })
        }

        // Email repair runs on the one column we know holds addresses.
        var cleaned = RecipientTable(headers: headers, rows: rows)
        let named = emailColumn ?? CSVParser.detectEmailColumn(in: cleaned)
        if let emailIndex = index(of: named, in: headers) {
            var repairedRows = cleaned.rows
            for r in repairedRows.indices where emailIndex < repairedRows[r].count {
                let value = repairedRows[r][emailIndex]
                if let fixed = repairedEmail(value) {
                    collector.record(.emailRepair, before: value, after: fixed)
                    repairedRows[r][emailIndex] = fixed
                }
            }
            cleaned = RecipientTable(headers: headers, rows: repairedRows)
        }

        return (cleaned, collector.report)
    }

    // MARK: - Value-level repairs

    /// Characters that should not exist in a contact list at all: zero-width
    /// spaces/joiners, BOMs, soft hyphens, and word joiners — invisible in a
    /// spreadsheet but fatal to placeholder matching and email validity.
    private static let invisibles: Set<Character> = [
        "\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}", "\u{00AD}", "\u{2060}"
    ]

    /// Exotic horizontal whitespace that should read as a plain space:
    /// non-breaking and narrow no-break spaces, figure/en/em spaces, tabs.
    private static let spaceLikes: Set<Character> = [
        "\u{00A0}", "\u{202F}", "\u{2007}", "\u{2002}", "\u{2003}", "\u{2009}", "\t"
    ]

    /// Trims the ends, deletes invisible characters, converts exotic spaces to
    /// plain ones, and collapses runs of spaces — while preserving intentional
    /// line breaks inside a value (multi-line addresses).
    static func normalizeWhitespace(_ value: String) -> String {
        guard !value.isEmpty else { return value }
        let unified = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = unified.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var out = ""
            out.reserveCapacity(line.count)
            var pendingSpace = false
            for ch in line {
                if invisibles.contains(ch) { continue }
                if ch == " " || spaceLikes.contains(ch) {
                    pendingSpace = !out.isEmpty
                    continue
                }
                if pendingSpace {
                    out.append(" ")
                    pendingSpace = false
                }
                out.append(ch)
            }
            return out
        }
        while let first = lines.first, first.isEmpty { lines.removeFirst() }
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// Spreadsheet placeholder/error tokens that mean "no data". Cleared to an
    /// empty value so the merge holds those rows back instead of greeting
    /// someone as "#N/A". Deliberately conservative — ambiguous strings like
    /// "NA" or "0" are left alone.
    private static let junkTokens: Set<String> = [
        "#n/a", "#n/a!", "#ref!", "#value!", "#name?", "#div/0!", "#num!", "#null!",
        "#error!", "#getting_data", "null", "n/a", "n.a.", "n/a.", "-", "--", "—", "#error"
    ]

    static func isJunkValue(_ value: String) -> Bool {
        junkTokens.contains(value.lowercased())
    }

    /// A data row that is just the header row again (a classic artifact of
    /// concatenating exports). Every non-empty cell must equal its header
    /// (empty cells are fine — partial header repeats lose trailing columns),
    /// with at least two matches so ordinary data can't be misread.
    static func isRepeatedHeaderRow(_ row: [String], headers: [String]) -> Bool {
        guard !headers.isEmpty, !row.isEmpty else { return false }
        var matches = 0
        for (index, cell) in row.enumerated() {
            let c = normalizeWhitespace(cell).lowercased()
            if c.isEmpty { continue }
            let h = index < headers.count ? normalizeWhitespace(headers[index]).lowercased() : ""
            guard h == c else { return false }
            matches += 1
        }
        return matches >= 2
    }

    /// Attempts a mechanical repair of a mangled address — `mailto:` prefixes,
    /// `Name <addr@x.com>` display forms, wrapping quotes/brackets, stray edge
    /// punctuation, and spaces inside the address. Returns nil when the value
    /// is empty, already valid, or can't be fixed with confidence; a repair is
    /// only returned when the result passes `EmailValidator`.
    static func repairedEmail(_ raw: String) -> String? {
        let start = normalizeWhitespace(raw)
        guard !start.isEmpty, !EmailValidator.isValid(start) else { return nil }

        var candidate = start
        // "Jordan Avery <jordan@acme.com>" → the bracketed address.
        if let open = candidate.lastIndex(of: "<"),
           let close = candidate.lastIndex(of: ">"), open < close {
            candidate = String(candidate[candidate.index(after: open)..<close])
        }
        if candidate.lowercased().hasPrefix("mailto:") {
            candidate = String(candidate.dropFirst("mailto:".count))
        }
        candidate = candidate.trimmingCharacters(
            in: CharacterSet(charactersIn: " \"'`‘’“”()[]{}<>,;:"))
        while candidate.hasSuffix(".") { candidate.removeLast() }
        // A space snuck into the address ("jordan @acme.com") — collapse it
        // only when that yields something valid.
        if candidate.contains(" ") {
            let collapsed = candidate.replacingOccurrences(of: " ", with: "")
            if EmailValidator.isValid(collapsed) { candidate = collapsed }
        }
        guard candidate != start, EmailValidator.isValid(candidate) else { return nil }
        return candidate
    }

    // MARK: - Suggestions

    /// A repair worth offering but not assuming — applied only on request.
    struct Suggestion: Equatable, Identifiable {
        enum Kind: String {
            /// `laura@gmial.com` → `laura@gmail.com`
            case domainTypo
            /// `ACME HOLDINGS` / `jordan avery` → `Acme Holdings` / `Jordan Avery`
            case shoutingCase
            /// `Avery, Jordan` → `Jordan Avery`
            case nameOrder
        }

        let kind: Kind
        /// Display name of the column the fix applies to.
        let column: String
        let count: Int
        let examples: [Example]

        var id: String { kind.rawValue + "·" + column.lowercased() }

        /// User-facing one-liner for the import screen.
        var title: String {
            let s = count == 1 ? "" : "s"
            switch kind {
            case .domainTypo:
                return "Fix \(count) misspelled email domain\(s) in “\(column)”"
            case .shoutingCase:
                return "Fix capitalization of \(count) ALL-CAPS or lowercase value\(s) in “\(column)”"
            case .nameOrder:
                return "Flip \(count) “Last, First” name\(s) in “\(column)” to “First Last”"
            }
        }
    }

    /// Scans a (cleaned) table for repairs worth offering. `emailColumn` names
    /// the address column when known; otherwise it is auto-detected.
    static func suggestions(for table: RecipientTable,
                            emailColumn: String? = nil) -> [Suggestion] {
        var result: [Suggestion] = []

        let named = emailColumn ?? CSVParser.detectEmailColumn(in: table)
        if let emailIndex = index(of: named, in: table.headers) {
            let found = matches(in: table, column: emailIndex) { correctedDomainEmail($0) }
            if found.count > 0 {
                result.append(Suggestion(kind: .domainTypo,
                                         column: table.headers[emailIndex],
                                         count: found.count, examples: found.examples))
            }
        }

        for (index, header) in table.headers.enumerated() {
            if isFullNameColumn(header) {
                let found = matches(in: table, column: index) { flippedName($0) }
                if found.count > 0 {
                    result.append(Suggestion(kind: .nameOrder, column: header,
                                             count: found.count, examples: found.examples))
                }
            }
            if isCasingColumn(header) {
                let found = matches(in: table, column: index) { fixedCasing($0) }
                if found.count > 0 {
                    result.append(Suggestion(kind: .shoutingCase, column: header,
                                             count: found.count, examples: found.examples))
                }
            }
        }
        return result
    }

    /// Applies one suggestion to the table, re-deriving the per-value repairs
    /// (the function is pure, so re-application after a re-clean is safe).
    /// Returns the updated table and how many values actually changed.
    static func apply(_ suggestion: Suggestion,
                      to table: RecipientTable) -> (table: RecipientTable, fixed: Int) {
        guard let column = index(of: suggestion.column, in: table.headers) else {
            return (table, 0)
        }
        var fixed = 0
        let rows = table.rows.map { row -> [String] in
            guard column < row.count, let replacement = replacementValue(row[column], kind: suggestion.kind)
            else { return row }
            fixed += 1
            var updated = row
            updated[column] = replacement
            return updated
        }
        return (RecipientTable(headers: table.headers, rows: rows), fixed)
    }

    private static func replacementValue(_ value: String, kind: Suggestion.Kind) -> String? {
        switch kind {
        case .domainTypo:   return correctedDomainEmail(value)
        case .shoutingCase: return fixedCasing(value)
        case .nameOrder:    return flippedName(value)
        }
    }

    private static func matches(in table: RecipientTable, column: Int,
                                transform: (String) -> String?) -> (count: Int, examples: [Example]) {
        var count = 0
        var examples: [Example] = []
        for row in table.rows where column < row.count {
            guard let after = transform(row[column]) else { continue }
            count += 1
            if examples.count < 3 {
                examples.append(Example(before: row[column], after: after))
            }
        }
        return (count, examples)
    }

    // MARK: Domain typos

    /// Misspellings of the big consumer mail domains — common enough to be
    /// worth offering, wrong often enough to never auto-apply.
    private static let domainTypos: [String: String] = [
        "gmial.com": "gmail.com", "gmal.com": "gmail.com", "gamil.com": "gmail.com",
        "gmali.com": "gmail.com", "gnail.com": "gmail.com", "gmaill.com": "gmail.com",
        "gmail.co": "gmail.com", "googlemail.co": "googlemail.com",
        "hotmial.com": "hotmail.com", "hotmal.com": "hotmail.com",
        "hotamil.com": "hotmail.com", "hotmali.com": "hotmail.com",
        "hotmaill.com": "hotmail.com", "hotmail.co": "hotmail.com",
        "yaho.com": "yahoo.com", "yahooo.com": "yahoo.com", "yhaoo.com": "yahoo.com",
        "yahoo.co": "yahoo.com",
        "outlok.com": "outlook.com", "outloook.com": "outlook.com",
        "outllook.com": "outlook.com", "oultook.com": "outlook.com",
        "iclod.com": "icloud.com", "icoud.com": "icloud.com", "icluod.com": "icloud.com",
        "iclould.com": "icloud.com"
    ]

    /// A corrected address when the domain part is a known typo, uses a
    /// non-existent `.con`/`.cmo` ending, or has a comma where a dot belongs —
    /// nil when the domain looks fine (or the fix wouldn't validate).
    static func correctedDomainEmail(_ value: String) -> String? {
        guard let at = value.lastIndex(of: "@"), at != value.startIndex else { return nil }
        let local = String(value[..<at])
        let domain = String(value[value.index(after: at)...]).lowercased()
        guard !domain.isEmpty else { return nil }

        var corrected: String?
        if let known = domainTypos[domain] {
            corrected = known
        } else if domain.contains(",") {
            corrected = domain.replacingOccurrences(of: ",", with: ".")
        } else if domain.hasSuffix(".con") {
            corrected = String(domain.dropLast(4)) + ".com"
        } else if domain.hasSuffix(".cmo") {
            corrected = String(domain.dropLast(4)) + ".com"
        }
        guard let corrected, corrected != domain else { return nil }
        let repaired = "\(local)@\(corrected)"
        guard EmailValidator.isValid(repaired) else { return nil }
        return repaired
    }

    // MARK: Casing

    private static func normalizeKey(_ header: String) -> String {
        header.lowercased().filter { !$0.isWhitespace && $0 != "_" && $0 != "-" }
    }

    /// Columns whose values are people or company names — the ones where
    /// SHOUTING CASE or all-lowercase is worth offering to fix.
    static func isCasingColumn(_ header: String) -> Bool {
        let nameLike: Set<String> = [
            "name", "fullname", "contactname", "contact", "firstname", "lastname",
            "first", "last", "givenname", "surname", "familyname",
            "company", "companyname", "organization", "organisation",
            "account", "accountname", "employer", "business", "firm"
        ]
        return nameLike.contains(normalizeKey(header))
    }

    /// Columns that hold a whole person name in one cell — the only place a
    /// "Last, First" flip makes sense.
    static func isFullNameColumn(_ header: String) -> Bool {
        ["name", "fullname", "contactname", "contact"].contains(normalizeKey(header))
    }

    /// Title-cases a value that is entirely upper- or lowercase; nil when the
    /// value already has mixed case (someone typed it that way on purpose),
    /// is too short to judge, or looks like an address/URL rather than a name.
    static func fixedCasing(_ value: String) -> String? {
        guard !value.contains("@"), !value.lowercased().contains("http"),
              !value.lowercased().hasPrefix("www.") else { return nil }
        let letters = value.filter(\.isLetter)
        guard letters.count >= 3 else { return nil }
        let allCaps = letters.allSatisfy(\.isUppercase)
        let allLower = letters.allSatisfy(\.isLowercase)
        guard allCaps || allLower else { return nil }
        let cased = titleCased(value)
        return cased == value ? nil : cased
    }

    /// Lowercase particles that stay lowercase inside a name (Ludwig van
    /// Beethoven), except as the leading word.
    private static let nameParticles: Set<String> = [
        "van", "von", "de", "der", "den", "del", "della", "di", "da", "la", "le",
        "du", "dos", "das", "ten", "ter", "bin", "al", "of", "and", "the"
    ]

    /// Generational/roman suffixes that read best fully uppercase.
    private static let romanNumerals: Set<String> = ["ii", "iii", "iv", "vi", "vii", "viii", "ix"]

    /// Name-aware title casing: `O'BRIEN-SMITH` → `O'Brien-Smith`,
    /// `MCDONALD` → `McDonald`, `LUDWIG VAN BEETHOVEN` → `Ludwig van Beethoven`.
    static func titleCased(_ value: String) -> String {
        let words = value.split(separator: " ", omittingEmptySubsequences: false)
        return words.enumerated()
            .map { index, word in titleCasedWord(String(word), isFirst: index == 0) }
            .joined(separator: " ")
    }

    private static func titleCasedWord(_ word: String, isFirst: Bool) -> String {
        guard !word.isEmpty else { return word }
        let lower = word.lowercased()
        if romanNumerals.contains(lower) { return word.uppercased() }
        if !isFirst, nameParticles.contains(lower) { return lower }

        var result = ""
        result.reserveCapacity(lower.count)
        var capitalizeNext = true
        for ch in lower {
            if ch == "-" || ch == "'" || ch == "’" || ch == "." || ch == "/" || ch == "&" {
                result.append(ch)
                capitalizeNext = true
            } else if capitalizeNext {
                result.append(contentsOf: ch.uppercased())
                capitalizeNext = false
            } else {
                result.append(ch)
            }
        }
        // "Mcdonald" → "McDonald" (but leave the bare word "Mc" alone).
        if result.hasPrefix("Mc"), result.count > 2 {
            let third = result.index(result.startIndex, offsetBy: 2)
            result = "Mc" + result[third...].prefix(1).uppercased()
                + String(result[result.index(after: third)...])
        }
        return result
    }

    // MARK: Name order

    /// Trailing tokens that mark "Last, Suffix" or "Company, Inc" — never flip
    /// those; the comma is not a name-order comma.
    private static let flipStopWords: Set<String> = [
        "inc", "llc", "ltd", "gmbh", "co", "corp", "plc", "llp", "sa", "ag", "kg",
        "bv", "pty", "srl", "oy", "ab", "as", "nv", "jr", "sr", "ii", "iii", "iv",
        "esq", "md", "phd", "dds", "cpa"
    ]

    /// `Avery, Jordan` → `Jordan Avery`; nil when the value has no single
    /// name-order comma or either side doesn't look like part of a person's
    /// name (digits, company suffixes, generational suffixes…).
    static func flippedName(_ value: String) -> String? {
        let parts = value.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let last = parts[0].trimmingCharacters(in: .whitespaces)
        let first = parts[1].trimmingCharacters(in: .whitespaces)
        guard !last.isEmpty, !first.isEmpty, !first.contains(","),
              looksLikeNameFragment(last), looksLikeNameFragment(first),
              first.split(separator: " ").count <= 2,
              last.split(separator: " ").count <= 3
        else { return nil }
        return "\(first) \(last)"
    }

    private static func looksLikeNameFragment(_ fragment: String) -> Bool {
        guard fragment.count <= 40 else { return false }
        let allowed = fragment.allSatisfy { ch in
            ch.isLetter || ch == " " || ch == "." || ch == "-" || ch == "'" || ch == "’"
        }
        guard allowed else { return false }
        let words = fragment.lowercased()
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        return !words.contains { flipStopWords.contains($0) }
    }

    // MARK: - Shared

    /// Case-insensitive header lookup, matching `CSVParser.contacts`.
    private static func index(of header: String?, in headers: [String]) -> Int? {
        guard let header else { return nil }
        return headers.firstIndex { $0.lowercased() == header.lowercased() }
    }
}
