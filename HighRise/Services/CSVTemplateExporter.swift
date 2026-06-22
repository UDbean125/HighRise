import Foundation

/// Produces a ready-to-fill CSV starter file from the recommended merge fields.
///
/// This is the easy on-ramp for a large list: the user downloads a spreadsheet
/// that already has every recommended column plus one example row showing the
/// expected shape, fills in their 100 contacts in Excel/Numbers, saves as CSV,
/// and imports. Pure string generation so the escaping is unit-tested.
enum CSVTemplateExporter {

    /// Example values for the recommended headers, so the template isn't blank.
    /// Realistic sample data — never `[brackets]` or placeholder tokens.
    private static let exampleValues: [String: String] = [
        "First Name": "Jordan",
        "Last Name": "Avery",
        "Full Name": "Jordan Avery",
        "Job Title": "Director of Procurement",
        "Email": "jordan.avery@northwind.example",
        "Company": "Northwind Traders",
        "Department": "Operations",
        "Website": "https://northwind.example",
        "Industry": "Logistics",
        "Phone": "+1 555 0148",
        "Address": "200 Harbor Way",
        "City": "Seattle",
        "State": "WA",
        "ZIP": "98101",
        "Country": "USA",
        "Product Name": "Fleet Analytics Suite",
        "Quote Number": "Q-2026-0417",
        "Invoice Number": "INV-88213",
        "PO Number": "PO-55012",
        "Amount": "$24,500",
        "Currency": "USD",
        "Quantity": "25",
        "Discount": "10%",
        "Quote Date": "2026-06-22",
        "Due Date": "2026-07-22",
        "Renewal Date": "2027-06-22",
        "Meeting Date": "2026-06-30",
        "Account Manager": "Riley Chen",
        "Sales Rep": "Sam Patel",
        "Next Step": "Schedule a 30-minute renewal review"
    ]

    /// The full CSV text: a header row of recommended fields plus one example row.
    static func templateCSV() -> String {
        let headers = MergeFieldCatalog.templateHeaders
        let example = headers.map { exampleValues[$0] ?? "" }
        return csvLine(headers) + "\n" + csvLine(example) + "\n"
    }

    /// Joins one row of values into an RFC-4180 CSV line, quoting fields that
    /// contain a comma, quote, or newline and doubling any internal quotes.
    static func csvLine(_ values: [String]) -> String {
        values.map(escapeField).joined(separator: ",")
    }

    static func escapeField(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"")
            || value.contains("\n") || value.contains("\r")
        guard needsQuoting else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
