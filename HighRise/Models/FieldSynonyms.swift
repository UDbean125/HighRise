import Foundation

/// Recognizes common business-contact field names that mean the same thing
/// under different labels — "Company" and "Account" are the same concept in
/// most CRM exports, as are "First Name" and "Given Name". Used wherever a
/// template field is matched against an imported column, so a template
/// written with the app's vocabulary (see `MergeFieldCatalog`) still resolves
/// against a list exported with someone else's — a HubSpot/Dynamics/
/// Salesforce "Accounts" export names the company column "Account Name", not
/// "Company", and a template shouldn't have to be rewritten to match.
///
/// Deliberately a curated list of exact phrases per concept, not fuzzy or
/// substring matching — "Company Status" and "Account Manager" must NOT match
/// "Company" (they're different fields entirely), and substring matching
/// would get both wrong. Every phrase is compared only after the same
/// trim + lowercase normalization used everywhere else field names are
/// matched.
enum FieldSynonyms {
    /// Each inner array is one concept; every phrase in it is treated as
    /// interchangeable with every other phrase in the same array. The first
    /// phrase in each group is the one `MergeFieldCatalog` promotes.
    private static let groups: [[String]] = [
        ["company", "company name", "account", "account name", "organization",
         "organization name", "org", "org name", "business name", "employer"],
        ["first name", "firstname", "first", "given name", "givenname"],
        ["last name", "lastname", "last", "surname", "family name", "familyname"],
        ["full name", "fullname", "name", "contact name", "contact"],
        ["job title", "title", "position", "role"],
        ["phone", "phone number", "telephone", "telephone number", "mobile",
         "mobile phone", "cell", "cell phone", "work phone"],
        ["email", "e-mail", "email address", "e-mail address"],
        ["website", "web site", "url", "site", "web"],
        ["address", "street address", "mailing address", "address 1", "address line 1"],
        ["city", "town"],
        ["state", "province", "state/province", "region"],
        ["zip", "zip code", "postal code", "postcode"],
        ["country", "nation"],
        ["department", "dept"],
        ["industry", "sector", "vertical"],
    ]

    /// Normalized phrase → the index of the concept group it belongs to.
    private static let index: [String: Int] = {
        var map: [String: Int] = [:]
        for (i, group) in groups.enumerated() {
            for phrase in group { map[phrase] = i }
        }
        return map
    }()

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// True when `a` and `b` name the same field, either literally (after
    /// trim + lowercase) or as a recognized synonym pair ("Company" ~
    /// "Account"). Unrecognized names only ever match themselves literally.
    static func match(_ a: String, _ b: String) -> Bool {
        let na = normalize(a), nb = normalize(b)
        if na == nb { return true }
        guard let ga = index[na], let gb = index[nb] else { return false }
        return ga == gb
    }
}
