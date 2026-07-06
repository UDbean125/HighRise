import Foundation

/// A single recipient parsed from an imported list.
///
/// A contact is an open bag of named fields (whatever column headers the
/// imported CSV had) plus a designated email address. We keep the raw field
/// dictionary so the template engine can substitute *any* column the user
/// referenced — `{{Company}}`, `{{FirstName}}`, `{{RenewalDate}}` — without the
/// app having to know those names ahead of time.
struct Contact: Identifiable, Hashable {
    let id = UUID()

    /// Field values keyed by their (original-cased) column header.
    /// Lookups are case-insensitive via `value(for:)`.
    var fields: [String: String]

    /// The recipient's email address. Always one of the values in `fields`,
    /// promoted to its own property because every send needs it.
    var email: String

    /// Case-insensitive, whitespace-tolerant field lookup.
    /// `{{ company }}`, `{{Company}}`, and `{{COMPANY}}` all resolve the same.
    func value(for key: String) -> String? {
        let wanted = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for (header, value) in fields where header.lowercased() == wanted {
            return value
        }
        return nil
    }

    /// A human label for this contact, used in previews and result rows.
    /// Prefers a name-like column, falls back to the email address.
    var displayName: String {
        let preferredKeys = ["name", "full name", "fullname", "contact",
                             "contact name", "first name", "firstname", "company"]
        for key in preferredKeys {
            if let v = value(for: key), !v.trimmingCharacters(in: .whitespaces).isEmpty {
                return v
            }
        }
        return email
    }
}

extension Contact {
    /// A realistic placeholder recipient for previewing a template before a real
    /// list is imported. Values mirror the CSV starter template so the preview
    /// looks like a genuine send.
    static let sample = Contact(fields: [
        "First Name": "Jordan", "Last Name": "Avery", "Full Name": "Jordan Avery",
        "Job Title": "Director of Procurement", "Email": "jordan.avery@northwind.example",
        "Company": "Northwind Traders", "Department": "Operations",
        "Website": "https://northwind.example", "Industry": "Logistics",
        "Phone": "+1 555 0148", "Address": "200 Harbor Way", "City": "Seattle",
        "State": "WA", "ZIP": "98101", "Country": "USA",
        "Product Name": "Fleet Analytics Suite", "Quote Number": "Q-2026-0417",
        "Invoice Number": "INV-88213", "PO Number": "PO-55012", "Amount": "$24,500",
        "Currency": "USD", "Quantity": "25", "Discount": "10%",
        "Quote Date": "2026-06-22", "Due Date": "2026-07-22", "Renewal Date": "2027-06-22",
        "Meeting Date": "2026-06-30", "Account Manager": "Riley Chen",
        "Sales Rep": "Sam Patel", "Next Step": "Schedule a 30-minute renewal review"
    ], email: "jordan.avery@northwind.example")
}
