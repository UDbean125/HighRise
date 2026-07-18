import Foundation

/// Fills in *missing* contact data across an imported list — the app's answer
/// to a CRM export where half the First Name cells are blank and Company is
/// hit-or-miss.
///
/// Same contract as `ImportCleaner`'s suggestions tier: every fill is a
/// judgment call, so nothing is ever applied automatically. The import screen
/// surfaces each proposal with a count and examples; the user opts in per
/// proposal. Two invariants hold everywhere:
///
/// - **Only blank cells are ever written.** A value someone typed is never
///   overwritten, however confident the inference.
/// - **Everything is derived from the list itself** (plus the email address) —
///   no lookups leave the machine, matching the app's no-servers design.
///
/// The fill sources, roughly ordered from most to least confident:
///
/// 1. **Duplicate rows** — the same address appears twice and one row has the
///    value the other is missing.
/// 2. **Splitting/joining name columns** — a blank First/Last filled from a
///    populated Full Name, or vice versa.
/// 3. **The email address** — `jordan.avery@…` encodes a first and last name;
///    `…@acme-corp.com` encodes an employer and website (for non-consumer
///    domains only). Company is preferred from *other rows on the same
///    domain* before falling back to prettifying the domain itself.
///
/// Pure and Foundation-only so it is unit-testable and shared by every import
/// source and both platforms.
enum ContactDataFiller {

    // MARK: - Proposal

    /// One category of fill worth offering — applied only when the user asks.
    struct Proposal: Equatable, Identifiable {
        enum Kind: String {
            /// Same email address on several rows; copy values between them.
            case fromDuplicates
            /// Blank First/Last Name filled by splitting a populated Full Name.
            case splitFullName
            /// Blank Full Name assembled from populated First + Last Name.
            case joinFirstLast
            /// Blank First Name inferred from the email's local part.
            case firstNameFromEmail
            /// Blank Last Name inferred from a `first.last@` local part.
            case lastNameFromEmail
            /// Blank Company copied from other rows on the same work domain.
            case companyFromColleagues
            /// Blank Company guessed by prettifying the work domain itself.
            case companyFromDomain
            /// Blank Website derived from the work domain.
            case websiteFromDomain
        }

        let kind: Kind
        /// Display name of the column the fill writes into (the full-name
        /// column for `splitFullName`, which writes First and Last).
        let column: String
        /// How many blank cells this proposal would fill.
        let count: Int
        /// Up to three source → filled-value samples.
        let examples: [ImportCleaner.Example]

        var id: String { kind.rawValue + "·" + column.lowercased() }

        /// User-facing one-liner for the import screen.
        var title: String {
            let s = count == 1 ? "" : "s"
            switch kind {
            case .fromDuplicates:
                return "Copy \(count) missing value\(s) between rows that share an email address"
            case .splitFullName:
                return "Fill \(count) blank first/last name\(s) by splitting “\(column)”"
            case .joinFirstLast:
                return "Fill \(count) blank “\(column)” value\(s) from the first and last name columns"
            case .firstNameFromEmail:
                return "Fill \(count) blank “\(column)” value\(s) from the email address"
            case .lastNameFromEmail:
                return "Fill \(count) blank “\(column)” value\(s) from the email address"
            case .companyFromColleagues:
                return "Fill \(count) blank “\(column)” value\(s) from other contacts at the same company domain"
            case .companyFromDomain:
                return "Guess \(count) blank “\(column)” value\(s) from the email domain"
            case .websiteFromDomain:
                return "Fill \(count) blank “\(column)” value\(s) from the email domain"
            }
        }
    }

    // MARK: - Public API

    /// Scans a (cleaned) table for fills worth offering. `emailColumn` names
    /// the address column when known; otherwise it is auto-detected. Proposals
    /// come back in confidence order, most reliable first.
    static func proposals(for table: RecipientTable,
                          emailColumn: String? = nil) -> [Proposal] {
        let order: [Proposal.Kind] = [
            .fromDuplicates, .splitFullName, .joinFirstLast,
            .firstNameFromEmail, .lastNameFromEmail,
            .companyFromColleagues, .companyFromDomain, .websiteFromDomain
        ]
        return order.compactMap { kind in
            let found = fills(for: kind, in: table, emailColumn: emailColumn)
            guard !found.isEmpty, let column = targetColumnName(for: kind, in: table) else { return nil }
            let examples = found.prefix(3).map {
                ImportCleaner.Example(before: $0.source, after: $0.value)
            }
            return Proposal(kind: kind, column: column,
                            count: found.count, examples: examples)
        }
    }

    /// Applies one proposal, re-deriving the fills from the current table (the
    /// function is pure, so re-application after a re-clean is safe — a cell
    /// that's no longer blank is simply left alone). Returns the updated table
    /// and how many cells were actually filled.
    static func apply(_ proposal: Proposal, to table: RecipientTable,
                      emailColumn: String? = nil) -> (table: RecipientTable, filled: Int) {
        let found = fills(for: proposal.kind, in: table, emailColumn: emailColumn)
        guard !found.isEmpty else { return (table, 0) }
        var rows = table.rows
        var filled = 0
        for fill in found where fill.row < rows.count && fill.column < rows[fill.row].count {
            guard isBlank(rows[fill.row][fill.column]) else { continue }
            rows[fill.row][fill.column] = fill.value
            filled += 1
        }
        return (RecipientTable(headers: table.headers, rows: rows), filled)
    }

    // MARK: - Fill computation

    /// One blank cell and the value that would fill it, plus the source value
    /// the inference came from (for example rows in the UI).
    private struct Fill {
        let row: Int
        let column: Int
        let value: String
        let source: String
    }

    private static func fills(for kind: Proposal.Kind, in table: RecipientTable,
                              emailColumn: String?) -> [Fill] {
        guard !table.rows.isEmpty else { return [] }
        let emailIndex = resolvedEmailIndex(in: table, emailColumn: emailColumn)
        switch kind {
        case .fromDuplicates:        return duplicateFills(table, emailIndex: emailIndex)
        case .splitFullName:         return splitFullNameFills(table)
        case .joinFirstLast:         return joinFirstLastFills(table)
        case .firstNameFromEmail:    return nameFromEmailFills(table, emailIndex: emailIndex, first: true)
        case .lastNameFromEmail:     return nameFromEmailFills(table, emailIndex: emailIndex, first: false)
        case .companyFromColleagues: return companyFills(table, emailIndex: emailIndex, fromColleagues: true)
        case .companyFromDomain:     return companyFills(table, emailIndex: emailIndex, fromColleagues: false)
        case .websiteFromDomain:     return websiteFills(table, emailIndex: emailIndex)
        }
    }

    /// Rows sharing one (valid) email address fill each other's blanks: the
    /// first non-blank value for a column among the duplicates wins.
    private static func duplicateFills(_ table: RecipientTable, emailIndex: Int?) -> [Fill] {
        guard let emailIndex else { return [] }
        var groups: [String: [Int]] = [:]
        for (r, row) in table.rows.enumerated() where emailIndex < row.count {
            let email = row[emailIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard EmailValidator.isValid(email) else { continue }
            groups[email, default: []].append(r)
        }
        var result: [Fill] = []
        for (email, rows) in groups.sorted(by: { ($0.value.first ?? 0) < ($1.value.first ?? 0) }) {
            guard rows.count > 1 else { continue }
            for c in table.headers.indices where c != emailIndex {
                let donor = rows.lazy
                    .compactMap { r -> String? in
                        guard c < table.rows[r].count, !isBlank(table.rows[r][c]) else { return nil }
                        return table.rows[r][c]
                    }
                    .first
                guard let donor else { continue }
                for r in rows where c < table.rows[r].count && isBlank(table.rows[r][c]) {
                    result.append(Fill(row: r, column: c, value: donor, source: email))
                }
            }
        }
        return result
    }

    /// "Jordan Avery" in a Full Name column splits into blank First/Last cells.
    private static func splitFullNameFills(_ table: RecipientTable) -> [Fill] {
        guard let fullIndex = index(matching: fullNameKeys, in: table.headers) else { return [] }
        let firstIndex = index(matching: firstNameKeys, in: table.headers)
        let lastIndex = index(matching: lastNameKeys, in: table.headers)
        guard firstIndex != nil || lastIndex != nil else { return [] }

        var result: [Fill] = []
        for (r, row) in table.rows.enumerated() where fullIndex < row.count {
            let full = row[fullIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let (first, last) = splitPersonName(full) else { continue }
            if let firstIndex, firstIndex < row.count, isBlank(row[firstIndex]) {
                result.append(Fill(row: r, column: firstIndex, value: first, source: full))
            }
            if let lastIndex, lastIndex < row.count, isBlank(row[lastIndex]) {
                result.append(Fill(row: r, column: lastIndex, value: last, source: full))
            }
        }
        return result
    }

    /// Populated First + Last assemble a blank Full Name.
    private static func joinFirstLastFills(_ table: RecipientTable) -> [Fill] {
        guard let fullIndex = index(matching: fullNameKeys, in: table.headers),
              let firstIndex = index(matching: firstNameKeys, in: table.headers),
              let lastIndex = index(matching: lastNameKeys, in: table.headers)
        else { return [] }

        var result: [Fill] = []
        for (r, row) in table.rows.enumerated()
        where fullIndex < row.count && firstIndex < row.count && lastIndex < row.count {
            guard isBlank(row[fullIndex]) else { continue }
            let first = row[firstIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let last = row[lastIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !first.isEmpty, !last.isEmpty else { continue }
            result.append(Fill(row: r, column: fullIndex,
                               value: "\(first) \(last)", source: "\(first) + \(last)"))
        }
        return result
    }

    /// Blank First (or Last) Name inferred from the email's local part.
    /// Rows whose Full Name column is populated are skipped — splitting the
    /// full name is the better source for those, offered separately.
    private static func nameFromEmailFills(_ table: RecipientTable, emailIndex: Int?,
                                           first: Bool) -> [Fill] {
        guard let emailIndex,
              let target = index(matching: first ? firstNameKeys : lastNameKeys,
                                 in: table.headers)
        else { return [] }
        let fullIndex = index(matching: fullNameKeys, in: table.headers)

        var result: [Fill] = []
        for (r, row) in table.rows.enumerated()
        where emailIndex < row.count && target < row.count {
            guard isBlank(row[target]) else { continue }
            if let fullIndex, fullIndex < row.count,
               splitPersonName(row[fullIndex].trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
                continue
            }
            let email = row[emailIndex]
            guard EmailValidator.isValid(email.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            let name = first
                ? NameInference.suggestedFirstName(from: email)
                : NameInference.suggestedLastName(from: email)
            guard let name else { continue }
            result.append(Fill(row: r, column: target, value: name, source: email))
        }
        return result
    }

    /// Blank Company filled from the email's work domain — either copied from
    /// other rows on the same domain (`fromColleagues`) or, when no such row
    /// exists, guessed by prettifying the domain itself. Consumer mail domains
    /// (gmail.com, icloud.com, …) never say who someone works for and are
    /// skipped entirely.
    private static func companyFills(_ table: RecipientTable, emailIndex: Int?,
                                     fromColleagues: Bool) -> [Fill] {
        guard let emailIndex,
              let companyIndex = index(matching: companyKeys, in: table.headers)
        else { return [] }

        // Most common non-blank company per work domain, from rows that have one.
        var counts: [String: [String: Int]] = [:]
        for row in table.rows where emailIndex < row.count && companyIndex < row.count {
            guard let domain = workDomain(ofEmail: row[emailIndex]), !isBlank(row[companyIndex])
            else { continue }
            counts[domain, default: [:]][row[companyIndex], default: 0] += 1
        }
        let colleagueCompany = counts.mapValues { byName in
            byName.max { ($0.value, $1.key) < ($1.value, $0.key) }!.key
        }

        var result: [Fill] = []
        for (r, row) in table.rows.enumerated()
        where emailIndex < row.count && companyIndex < row.count {
            guard isBlank(row[companyIndex]),
                  let domain = workDomain(ofEmail: row[emailIndex]) else { continue }
            if fromColleagues {
                guard let company = colleagueCompany[domain] else { continue }
                result.append(Fill(row: r, column: companyIndex, value: company, source: row[emailIndex]))
            } else {
                guard colleagueCompany[domain] == nil,
                      let guessed = companyName(fromDomain: domain) else { continue }
                result.append(Fill(row: r, column: companyIndex, value: guessed, source: row[emailIndex]))
            }
        }
        return result
    }

    /// Blank Website derived from the email's work domain.
    private static func websiteFills(_ table: RecipientTable, emailIndex: Int?) -> [Fill] {
        guard let emailIndex,
              let siteIndex = index(matching: websiteKeys, in: table.headers)
        else { return [] }
        var result: [Fill] = []
        for (r, row) in table.rows.enumerated()
        where emailIndex < row.count && siteIndex < row.count {
            guard isBlank(row[siteIndex]),
                  let domain = workDomain(ofEmail: row[emailIndex]) else { continue }
            result.append(Fill(row: r, column: siteIndex, value: "https://\(domain)", source: row[emailIndex]))
        }
        return result
    }

    // MARK: - Name splitting

    /// Splits a plausible "First Last" (or "First Middle Last") person name;
    /// nil for single words, company-looking values, or anything with digits
    /// or odd punctuation.
    static func splitPersonName(_ full: String) -> (first: String, last: String)? {
        let words = full.split(separator: " ").map(String.init)
        guard (2...4).contains(words.count) else { return nil }
        let allowed = words.allSatisfy { word in
            !word.isEmpty && word.count <= 30 && word.allSatisfy {
                $0.isLetter || $0 == "-" || $0 == "'" || $0 == "’" || $0 == "."
            }
        }
        guard allowed else { return nil }
        let lowered = words.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        guard !lowered.contains(where: { companyStopWords.contains($0) }) else { return nil }
        return (words[0], words.dropFirst().joined(separator: " "))
    }

    /// Values containing these are companies or titles, not person names.
    private static let companyStopWords: Set<String> = [
        "inc", "llc", "ltd", "gmbh", "corp", "co", "plc", "llp", "sa", "ag",
        "kg", "bv", "pty", "srl", "oy", "ab", "nv", "group", "holdings",
        "solutions", "services", "systems", "team", "dept", "department"
    ]

    // MARK: - Domains

    /// Consumer/free mail providers — an address there says nothing about the
    /// person's employer or website.
    static let freeMailDomains: Set<String> = [
        "gmail.com", "googlemail.com", "yahoo.com", "yahoo.co.uk", "ymail.com",
        "hotmail.com", "hotmail.co.uk", "outlook.com", "live.com", "msn.com",
        "aol.com", "icloud.com", "me.com", "mac.com", "proton.me",
        "protonmail.com", "pm.me", "gmx.com", "gmx.net", "gmx.de", "web.de",
        "mail.com", "zoho.com", "hey.com", "fastmail.com", "yandex.com",
        "yandex.ru", "qq.com", "163.com", "126.com", "naver.com", "daum.net",
        "comcast.net", "verizon.net", "att.net", "sbcglobal.net", "cox.net",
        "bellsouth.net", "btinternet.com", "sky.com", "orange.fr", "free.fr",
        "wanadoo.fr", "t-online.de", "libero.it", "example.com", "example.org"
    ]

    /// The lowercased domain of a valid, non-consumer address — nil for
    /// invalid addresses and free-mail providers.
    static func workDomain(ofEmail email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard EmailValidator.isValid(trimmed),
              let at = trimmed.lastIndex(of: "@") else { return nil }
        let domain = String(trimmed[trimmed.index(after: at)...])
        guard !domain.isEmpty, !freeMailDomains.contains(domain) else { return nil }
        return domain
    }

    /// Country-code second levels (`co.uk`, `com.au`, …) whose presence means
    /// the organization label is one segment further left.
    private static let secondLevelMarkers: Set<String> = [
        "co", "com", "org", "net", "ac", "gov", "edu", "or", "ne"
    ]

    /// A display-ready company guess from a work domain:
    /// `acme-corp.com` → `Acme Corp`, `northwind.co.uk` → `Northwind`.
    /// Nil when the organization label is too short to be meaningful.
    static func companyName(fromDomain domain: String) -> String? {
        let parts = domain.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }
        var labelIndex = parts.count - 2
        if parts.count >= 3, secondLevelMarkers.contains(parts[parts.count - 2]) {
            labelIndex = parts.count - 3
        }
        let label = parts[labelIndex]
        guard label.count >= 3, label.contains(where: \.isLetter) else { return nil }
        return ImportCleaner.titleCased(label.replacingOccurrences(of: "-", with: " "))
    }

    // MARK: - Columns

    static let firstNameKeys: Set<String> = ["firstname", "first", "givenname"]
    static let lastNameKeys: Set<String> = ["lastname", "last", "surname", "familyname"]
    static let fullNameKeys: Set<String> = ["name", "fullname", "contactname", "contact"]
    static let companyKeys: Set<String> = [
        "company", "companyname", "organization", "organisation",
        "account", "accountname", "employer", "business", "firm"
    ]
    static let websiteKeys: Set<String> = [
        "website", "web", "url", "site", "companywebsite", "webaddress", "homepage"
    ]

    /// The header a proposal's fills write into, for display. Nil only when
    /// the table has no matching column (in which case there are no fills
    /// either).
    private static func targetColumnName(for kind: Proposal.Kind,
                                         in table: RecipientTable) -> String? {
        switch kind {
        case .fromDuplicates:
            return resolvedEmailIndex(in: table, emailColumn: nil).map { table.headers[$0] }
                ?? table.headers.first
        case .splitFullName, .joinFirstLast:
            return index(matching: fullNameKeys, in: table.headers).map { table.headers[$0] }
        case .firstNameFromEmail:
            return index(matching: firstNameKeys, in: table.headers).map { table.headers[$0] }
        case .lastNameFromEmail:
            return index(matching: lastNameKeys, in: table.headers).map { table.headers[$0] }
        case .companyFromColleagues, .companyFromDomain:
            return index(matching: companyKeys, in: table.headers).map { table.headers[$0] }
        case .websiteFromDomain:
            return index(matching: websiteKeys, in: table.headers).map { table.headers[$0] }
        }
    }

    static func normalizeKey(_ header: String) -> String {
        header.lowercased().filter { !$0.isWhitespace && $0 != "_" && $0 != "-" }
    }

    static func index(matching keys: Set<String>, in headers: [String]) -> Int? {
        headers.firstIndex { keys.contains(normalizeKey($0)) }
    }

    /// The email column's index: the named column when given, else auto-detected.
    private static func resolvedEmailIndex(in table: RecipientTable,
                                           emailColumn: String?) -> Int? {
        let named = emailColumn ?? CSVParser.detectEmailColumn(in: table)
        guard let named else { return nil }
        return table.headers.firstIndex { $0.lowercased() == named.lowercased() }
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
