import Foundation

/// Applies inline formatting filters to a merged value at render time, so users
/// fix Excel's raw serial dates, ALL-CAPS names, and unformatted numbers in the
/// template instead of cleaning the spreadsheet. Pure and Foundation-only.
///
/// Filters are written after a pipe in a placeholder and chained left to right:
/// `{{Amount|currency:USD}}`, `{{Renewal Date|date:MMMM d, yyyy}}`,
/// `{{Name|fixcaps}}`, `{{Tag|upper}}`. A `default:` filter (or a bare
/// `{{Field|there}}`) supplies a fallback for empty values; see `EmailTemplate`.
enum MergeValueFormatter {

    /// One parsed filter in a placeholder's pipe chain.
    enum Filter: Equatable {
        case defaultValue(String)   // fallback text for an empty/missing field
        case upper
        case lower
        case capitalize             // First Letter Of Each Word
        case fixCaps                // repair ALL-CAPS → Title Case, leave mixed case
        case trim
        case date(String)           // reformat a parsed date with this pattern
        case currency(String)       // format a number as this currency code
        case number                 // group digits (1234567 → 1,234,567)

        /// True for filters that only supply a fallback, not a transform.
        var isDefault: Bool {
            if case .defaultValue = self { return true }
            return false
        }
    }

    /// Parses one pipe-separated segment (already split from the placeholder) into
    /// a filter. An unrecognized segment is treated as bare fallback text, which
    /// preserves the simple `{{First Name|there}}` form.
    static func parseFilter(_ segment: String) -> Filter {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        let (nameRaw, argRaw): (String, String?)
        if let colon = trimmed.firstIndex(of: ":") {
            nameRaw = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            argRaw = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        } else {
            nameRaw = trimmed
            argRaw = nil
        }
        let arg = argRaw.map { stripQuotes($0) }

        switch nameRaw.lowercased() {
        case "upper", "uppercase":              return .upper
        case "lower", "lowercase":              return .lower
        case "capitalize", "title", "titlecase": return .capitalize
        case "fixcaps", "fixcase":              return .fixCaps
        case "trim":                            return .trim
        case "number", "comma":                 return .number
        case "date"     where arg != nil:       return .date(arg!)
        case "currency" where arg != nil:       return .currency(arg!)
        case "default":                         return .defaultValue(arg ?? "")
        default:
            // Not a known filter → the whole segment is bare fallback text.
            return .defaultValue(trimmed)
        }
    }

    /// Applies a formatting filter (anything but `default`) to `value`.
    /// Unknown/unparseable input is returned unchanged — formatting never throws
    /// away the underlying data.
    static func apply(_ filter: Filter, to value: String) -> String {
        switch filter {
        case .defaultValue:      return value           // handled during resolution
        case .upper:             return value.localizedUppercase
        case .lower:             return value.localizedLowercase
        case .capitalize:        return value.localizedCapitalized
        case .trim:              return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .fixCaps:           return fixCaps(value)
        case .date(let fmt):     return formatDate(value, pattern: fmt)
        case .currency(let code): return formatCurrency(value, code: code)
        case .number:            return formatNumber(value)
        }
    }

    // MARK: - Transforms

    /// Repairs shouty ALL-CAPS values ("JOHN SMITH" → "John Smith") while leaving
    /// already-mixed-case text ("McDonald") untouched.
    private static func fixCaps(_ value: String) -> String {
        let letters = value.filter { $0.isLetter }
        guard !letters.isEmpty, letters.allSatisfy({ $0.isUppercase }) else { return value }
        return value.localizedCapitalized
    }

    private static func formatNumber(_ value: String) -> String {
        guard let number = parseNumber(value) else { return value }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US") // deterministic grouping
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = number == number.rounded() ? 0 : 2
        return formatter.string(from: NSNumber(value: number)) ?? value
    }

    private static func formatCurrency(_ value: String, code: String) -> String {
        guard let number = parseNumber(value) else { return value }
        let formatter = NumberFormatter()
        // A predictable base locale so USD renders as $24,500.00 regardless of
        // the machine's region; the code drives the symbol.
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = code.uppercased()
        return formatter.string(from: NSNumber(value: number)) ?? value
    }

    /// Extracts a Double from text that may carry currency symbols, spaces, or
    /// thousands separators ("$1,234.50" → 1234.5).
    private static func parseNumber(_ value: String) -> Double? {
        let allowed = value.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(allowed)
    }

    private static func formatDate(_ value: String, pattern: String) -> String {
        guard let date = parseDate(value) else { return value }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        // Parsing anchors dates at UTC midnight; format in UTC too so the day
        // can't drift across a timezone boundary on the running machine.
        out.timeZone = TimeZone(identifier: "UTC")
        out.dateFormat = pattern
        return out.string(from: date)
    }

    /// Best-effort date parsing: ISO 8601, a handful of common written formats,
    /// and Excel's serial-day numbers (the notorious "44927" instead of a date).
    private static func parseDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: trimmed) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for pattern in ["yyyy-MM-dd", "yyyy/MM/dd", "MM/dd/yyyy", "M/d/yyyy",
                        "dd-MM-yyyy", "dd/MM/yyyy", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: trimmed) { return date }
        }

        // Excel serial day: days since 1899-12-30 (accounting for the 1900 bug).
        if let serial = Double(trimmed), serial > 0, serial < 600_000 {
            let epoch = DateComponents(calendar: Calendar(identifier: .gregorian),
                                       timeZone: TimeZone(identifier: "UTC"),
                                       year: 1899, month: 12, day: 30).date
            if let epoch { return epoch.addingTimeInterval(serial * 86_400) }
        }
        return nil
    }

    private static func stripQuotes(_ s: String) -> String {
        guard s.count >= 2 else { return s }
        let quotes: [Character] = ["\"", "'"]
        if let first = s.first, let last = s.last, first == last, quotes.contains(first) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}
