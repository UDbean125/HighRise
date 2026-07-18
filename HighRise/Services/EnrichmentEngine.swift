import Foundation

/// Orchestrates a "Find & Fill Online" pass: builds one `EnrichmentQuery` per
/// row from the imported table, asks a provider, and turns what comes back
/// into reviewable cell fills — never applying anything itself.
///
/// The rules mirror (and extend) `ContactDataFiller`'s contract:
/// - Blank cells can be **filled**.
/// - An **invalid** email can be **corrected** (shown as before → after).
/// - A **valid** email is never touched, and no other populated cell is ever
///   overwritten. Online data is a suggestion, not an authority.
enum EnrichmentEngine {

    /// One proposed cell write, kept reviewable: the row (0-based within the
    /// current table), the target column, what's there now, what would be
    /// written, and a human label for the row ("Kimley-Horn").
    struct CellFill: Equatable, Identifiable, Sendable {
        let row: Int
        let column: String
        let before: String
        let after: String
        let rowLabel: String

        var id: String { "\(row)·\(column.lowercased())" }
        var isCorrection: Bool { !before.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The outcome of a run: the fills worth offering plus how many rows were
    /// queried and how many the provider knew nothing about.
    struct RunResult: Equatable, Sendable {
        var fills: [CellFill] = []
        var queried = 0
        var noMatch = 0
        var skippedUnaskable = 0
    }

    /// Rows per run — a safety valve so one click can't burn through an
    /// entire Apollo credit balance. Disclosed in the UI when it bites.
    static let maxRowsPerRun = 100

    /// Runs the provider over every row that needs something (missing/invalid
    /// email, or blank name/company/website cells), up to `maxRowsPerRun`.
    /// `onProgress` fires on the calling task after each row completes.
    static func run(table: RecipientTable, emailColumn: String?,
                    provider: EnrichmentProvider,
                    onProgress: @escaping @Sendable (Int, Int) -> Void = { _, _ in })
    async throws -> RunResult {
        let emailIndex = emailColumnIndex(in: table, named: emailColumn)
        let targets = rowsNeedingHelp(table, emailIndex: emailIndex)
        let capped = Array(targets.prefix(maxRowsPerRun))
        var result = RunResult()
        result.skippedUnaskable = targets.count - capped.count

        var done = 0
        for rowIndex in capped {
            try Task.checkCancellation()
            let query = query(for: rowIndex, in: table, emailIndex: emailIndex)
            guard query.isAskable else {
                result.skippedUnaskable += 1
                continue
            }
            result.queried += 1
            if let finding = try await provider.enrich(query) {
                result.fills.append(contentsOf: fills(from: finding, rowIndex: rowIndex,
                                                      table: table, emailIndex: emailIndex))
            } else {
                result.noMatch += 1
            }
            done += 1
            onProgress(done, capped.count)
        }
        return result
    }

    /// Applies accepted fills. Each fill only lands if its cell still holds
    /// exactly the `before` it was computed against (or is blank) — a stale
    /// fill is skipped, never blindly written. Returns the new table and how
    /// many cells actually changed.
    static func apply(_ fills: [CellFill], to table: RecipientTable) -> (table: RecipientTable, applied: Int) {
        var rows = table.rows
        var applied = 0
        for fill in fills {
            guard let columnIndex = index(of: fill.column, in: table.headers),
                  fill.row < rows.count, columnIndex < rows[fill.row].count
            else { continue }
            let current = rows[fill.row][columnIndex]
            guard current == fill.before
                    || current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            rows[fill.row][columnIndex] = fill.after
            applied += 1
        }
        return (RecipientTable(headers: table.headers, rows: rows), applied)
    }

    // MARK: - Row selection & query building

    /// A row qualifies when its email is missing/invalid or when any mapped
    /// name/company/website cell is blank.
    static func rowsNeedingHelp(_ table: RecipientTable, emailIndex: Int?) -> [Int] {
        let fillable = [
            index(matching: ContactDataFiller.firstNameKeys, in: table.headers),
            index(matching: ContactDataFiller.lastNameKeys, in: table.headers),
            index(matching: ContactDataFiller.fullNameKeys, in: table.headers),
            index(matching: ContactDataFiller.companyKeys, in: table.headers),
            index(matching: ContactDataFiller.websiteKeys, in: table.headers)
        ].compactMap { $0 }

        return table.rows.indices.filter { r in
            let row = table.rows[r]
            if let emailIndex {
                let email = emailIndex < row.count ? row[emailIndex] : ""
                if !EmailValidator.isValid(email.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return true
                }
            }
            return fillable.contains { c in c < row.count && isBlank(row[c]) }
        }
    }

    static func query(for rowIndex: Int, in table: RecipientTable, emailIndex: Int?) -> EnrichmentQuery {
        func cell(_ keys: Set<String>) -> String? {
            guard let c = index(matching: keys, in: table.headers),
                  c < table.rows[rowIndex].count else { return nil }
            let v = table.rows[rowIndex][c].trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }

        let email = emailIndex.flatMap { c -> String? in
            guard c < table.rows[rowIndex].count else { return nil }
            let v = table.rows[rowIndex][c].trimmingCharacters(in: .whitespacesAndNewlines)
            return EmailValidator.isValid(v) ? v : nil
        }
        var domain = email.flatMap { ContactDataFiller.workDomain(ofEmail: $0) }
        if domain == nil, let site = cell(ContactDataFiller.websiteKeys) {
            domain = Self.domain(fromWebsite: site)
        }

        return EnrichmentQuery(firstName: cell(ContactDataFiller.firstNameKeys),
                               lastName: cell(ContactDataFiller.lastNameKeys),
                               fullName: cell(ContactDataFiller.fullNameKeys),
                               company: cell(ContactDataFiller.companyKeys),
                               domain: domain,
                               title: cell(titleKeys),
                               email: email)
    }

    /// Turns one finding into concrete cell fills for that row, honoring the
    /// never-overwrite rules.
    private static func fills(from finding: EnrichmentFinding, rowIndex: Int,
                              table: RecipientTable, emailIndex: Int?) -> [CellFill] {
        let row = table.rows[rowIndex]
        let label = rowLabel(row, table: table, emailIndex: emailIndex)
        var out: [CellFill] = []

        func offer(_ keys: Set<String>, _ value: String?, blanksOnly: Bool = true) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
                  let c = index(matching: keys, in: table.headers), c < row.count
            else { return }
            let current = row[c]
            if isBlank(current) || !blanksOnly {
                guard current != value else { return }
                out.append(CellFill(row: rowIndex, column: table.headers[c],
                                    before: current, after: value, rowLabel: label))
            }
        }

        // Email: fill a blank, or correct an invalid value — never a valid one.
        if let emailIndex, emailIndex < row.count, let found = finding.email {
            let current = row[emailIndex]
            let valid = EmailValidator.isValid(current.trimmingCharacters(in: .whitespacesAndNewlines))
            if !valid, current != found {
                out.append(CellFill(row: rowIndex, column: table.headers[emailIndex],
                                    before: current, after: found, rowLabel: label))
            }
        }
        offer(ContactDataFiller.firstNameKeys, finding.firstName)
        offer(ContactDataFiller.lastNameKeys, finding.lastName)
        offer(ContactDataFiller.fullNameKeys, finding.fullName)
        offer(ContactDataFiller.companyKeys, finding.company)
        offer(ContactDataFiller.websiteKeys, finding.website)
        offer(titleKeys, finding.title)
        return out
    }

    /// "Kimley-Horn" / "Jordan Avery" / "row 12" — whatever best identifies
    /// the row in the review list.
    private static func rowLabel(_ row: [String], table: RecipientTable, emailIndex: Int?) -> String {
        let labelKeys = [ContactDataFiller.fullNameKeys, ContactDataFiller.companyKeys,
                         ContactDataFiller.firstNameKeys]
        for keys in labelKeys {
            if let c = index(matching: keys, in: table.headers), c < row.count, !isBlank(row[c]) {
                return row[c]
            }
        }
        if let emailIndex, emailIndex < row.count, !isBlank(row[emailIndex]) {
            return row[emailIndex]
        }
        return "(unnamed row)"
    }

    // MARK: - Columns

    static let titleKeys: Set<String> = [
        "title", "jobtitle", "job", "position", "role", "designation",
        "directortitle", "contacttitle"
    ]

    private static func index(matching keys: Set<String>, in headers: [String]) -> Int? {
        ContactDataFiller.index(matching: keys, in: headers)
    }

    private static func index(of header: String, in headers: [String]) -> Int? {
        headers.firstIndex { $0.lowercased() == header.lowercased() }
    }

    static func emailColumnIndex(in table: RecipientTable, named: String?) -> Int? {
        let name = named ?? CSVParser.detectEmailColumn(in: table)
        guard let name else { return nil }
        return index(of: name, in: table.headers)
    }

    /// "https://www.acme.com/about" → "acme.com"
    static func domain(fromWebsite site: String) -> String? {
        var s = site.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        if s.hasPrefix("www.") { s = String(s.dropFirst(4)) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        guard s.contains("."), !s.contains(" "), !s.isEmpty else { return nil }
        return s
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
