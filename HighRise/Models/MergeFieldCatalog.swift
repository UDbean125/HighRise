import Foundation

/// A merge field the user can drop into a template, rendered as `{{Name}}`.
struct MergeField: Identifiable, Hashable {
    let name: String
    let detail: String
    var id: String { name }
    var token: String { "{{\(name)}}" }
}

/// A named group of related merge fields, for display in the field palette.
struct MergeFieldGroup: Identifiable, Hashable {
    let title: String
    let fields: [MergeField]
    var id: String { title }
}

/// A curated catalog of common professional merge fields.
///
/// Fields are *not* a fixed schema — any column in an imported list is usable as
/// a merge field automatically. This catalog exists so the user has a sensible
/// starting set to compose against (and to seed the downloadable CSV template)
/// without having to invent column names. The matching column header just has
/// to share the field's name (case/whitespace-insensitive).
enum MergeFieldCatalog {

    static let groups: [MergeFieldGroup] = [
        MergeFieldGroup(title: "Identity", fields: [
            MergeField(name: "First Name", detail: "Recipient's given name"),
            MergeField(name: "Last Name", detail: "Recipient's family name"),
            MergeField(name: "Full Name", detail: "Complete name, if you store it as one column"),
            MergeField(name: "Job Title", detail: "Role, e.g. “VP of Operations”"),
            MergeField(name: "Email", detail: "Recipient's email address")
        ]),
        MergeFieldGroup(title: "Company", fields: [
            MergeField(name: "Company", detail: "Organization name"),
            MergeField(name: "Department", detail: "Team or division"),
            MergeField(name: "Website", detail: "Company URL"),
            MergeField(name: "Industry", detail: "Sector, e.g. “Healthcare”")
        ]),
        MergeFieldGroup(title: "Contact info", fields: [
            MergeField(name: "Phone", detail: "Phone number"),
            MergeField(name: "Address", detail: "Street address"),
            MergeField(name: "City", detail: "City"),
            MergeField(name: "State", detail: "State / province"),
            MergeField(name: "ZIP", detail: "Postal code"),
            MergeField(name: "Country", detail: "Country")
        ]),
        MergeFieldGroup(title: "Deal & quote", fields: [
            MergeField(name: "Product Name", detail: "Product or service — varies per recipient"),
            MergeField(name: "Quote Number", detail: "Quote / estimate reference"),
            MergeField(name: "Invoice Number", detail: "Invoice reference"),
            MergeField(name: "PO Number", detail: "Purchase order reference"),
            MergeField(name: "Amount", detail: "Dollar value, e.g. “$12,500”"),
            MergeField(name: "Currency", detail: "Currency code, e.g. “USD”"),
            MergeField(name: "Quantity", detail: "Units / seats / licenses"),
            MergeField(name: "Discount", detail: "Discount applied, e.g. “10%”")
        ]),
        MergeFieldGroup(title: "Dates", fields: [
            MergeField(name: "Quote Date", detail: "Date the quote was issued"),
            MergeField(name: "Due Date", detail: "Payment or response due date"),
            MergeField(name: "Renewal Date", detail: "Contract / subscription renewal date"),
            MergeField(name: "Meeting Date", detail: "Scheduled meeting or call date")
        ]),
        MergeFieldGroup(title: "Ownership & follow-up", fields: [
            MergeField(name: "Account Manager", detail: "Your rep / owner for this account"),
            MergeField(name: "Sales Rep", detail: "Assigned salesperson"),
            MergeField(name: "Next Step", detail: "The specific follow-up action for this recipient")
        ])
    ]

    /// A flat list of every recommended field.
    static var allFields: [MergeField] { groups.flatMap(\.fields) }

    /// The recommended column headers, used to seed the CSV template (email first
    /// so the importer's auto-detection lands on it immediately).
    static var templateHeaders: [String] {
        let headers = ["First Name", "Last Name", "Company", "Email"]
        let rest = allFields.map(\.name).filter { !headers.contains($0) }
        return headers + rest
    }
}
