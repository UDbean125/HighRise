import Foundation

/// Classifies each `{{merge field}}` a template references against the columns
/// of the imported list, so Compose can show — before the user ever reaches
/// Review — which fields are backed by real data, which fall back safely, and
/// which will hold rows back for lack of a column. Pure and deterministic; the
/// view just colors chips from the report.
enum FieldCoverage {

    /// How an imported list covers one referenced field.
    enum Status: Equatable {
        /// A column with this name exists — the field resolves for those rows.
        case matched
        /// No column, but every use carries a fallback (`{{Field|there}}`), so
        /// it can't block a send — it just substitutes the fallback.
        case fallback
        /// No column *and* used at least once without a fallback — rows missing
        /// this data are held back until a column or fallback is added.
        case missing
    }

    struct Field: Identifiable, Equatable {
        let name: String
        let status: Status
        var id: String { name }
    }

    struct Report: Equatable {
        let fields: [Field]

        var matched: [Field]      { fields.filter { $0.status == .matched } }
        var fallbackOnly: [Field] { fields.filter { $0.status == .fallback } }
        var missing: [Field]      { fields.filter { $0.status == .missing } }
        var total: Int { fields.count }

        /// True when nothing is missing — every field either has a column or a
        /// safe fallback, so no row is held back for missing merge data.
        var allBacked: Bool { missing.isEmpty }
    }

    /// Core classification over primitives.
    ///
    /// - Parameters:
    ///   - referenced: every distinct field the template mentions, in order.
    ///   - requiring: the subset used at least once *without* a fallback (from
    ///     `EmailTemplate.fieldsRequiringData`).
    ///   - headers: the imported list's column headers.
    static func assess(referenced: [String], requiring: [String], headers: [String]) -> Report {
        let available = Set(headers.map(normalize))
        let required = Set(requiring.map(normalize))
        let fields = referenced.map { name -> Field in
            let key = normalize(name)
            if available.contains(key) { return Field(name: name, status: .matched) }
            return Field(name: name, status: required.contains(key) ? .missing : .fallback)
        }
        return Report(fields: fields)
    }

    /// Convenience over a real template.
    static func assess(template: EmailTemplate, headers: [String]) -> Report {
        assess(referenced: template.referencedFields,
               requiring: template.fieldsRequiringData,
               headers: headers)
    }

    /// A compact one-line summary — "All 7 fields backed by your list" or
    /// "5 of 7 backed · 2 need a column".
    static func line(_ report: Report) -> String {
        guard report.total > 0 else { return "No merge fields yet" }
        if report.allBacked {
            return "All \(report.total) field\(report.total == 1 ? "" : "s") backed by your list"
        }
        let need = report.missing.count
        return "\(report.matched.count) of \(report.total) backed · \(need) need\(need == 1 ? "s" : "") a column"
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
