import Foundation

/// Guesses a recipient's first name from their email address alone — a local,
/// cloud-free take on GMass's `{auto-first}`. It's deliberately conservative:
/// it returns a suggestion only when the local part clearly looks like a
/// person's name, so it can be offered as a *suggested fill* for a blocked row
/// (missing First Name) rather than silently substituted.
enum NameInference {

    /// Role/shared mailboxes that are never a person's name.
    private static let roleAddresses: Set<String> = [
        "info", "sales", "support", "hello", "hi", "contact", "admin", "office",
        "team", "help", "noreply", "no-reply", "donotreply", "mail", "email",
        "billing", "accounts", "accounting", "hr", "jobs", "careers", "press",
        "marketing", "orders", "service", "enquiries", "inquiries", "webmaster",
        "postmaster", "root", "abuse", "security", "privacy", "legal", "feedback"
    ]

    /// A small set of common given names, used to raise confidence. Not
    /// exhaustive — a token outside it can still be suggested if it otherwise
    /// looks name-like — but a hit here makes the guess reliable. Extend by
    /// bundling a fuller public-domain list as a resource.
    private static let commonNames: Set<String> = [
        "james", "john", "robert", "michael", "william", "david", "richard",
        "joseph", "thomas", "charles", "christopher", "daniel", "matthew",
        "anthony", "mark", "donald", "steven", "paul", "andrew", "joshua",
        "mary", "patricia", "jennifer", "linda", "elizabeth", "barbara",
        "susan", "jessica", "sarah", "karen", "nancy", "lisa", "margaret",
        "betty", "sandra", "ashley", "emily", "donna", "michelle",
        "ada", "grace", "alan", "jordan", "avery", "riley", "sam", "alex",
        "chris", "pat", "taylor", "morgan", "casey", "jamie", "jordan",
        "ana", "maria", "jose", "luis", "carlos", "juan", "wei", "li",
        "chen", "yuki", "hiro", "raj", "priya", "amir", "fatima", "omar"
    ]

    /// A suggested first name, or nil when the address doesn't clearly encode
    /// one. Handles `first.last@`, `first_last@`, `first-last@`, and plus-tags;
    /// rejects role mailboxes, numeric/gibberish local parts, and initials.
    static func suggestedFirstName(from email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let at = trimmed.firstIndex(of: "@") else { return nil }
        var local = String(trimmed[..<at])

        // Drop plus-addressing (ada+news@… → ada).
        if let plus = local.firstIndex(of: "+") { local = String(local[..<plus]) }
        guard !local.isEmpty else { return nil }

        // A whole-local role address (info@, sales@) is never a name.
        if roleAddresses.contains(local) { return nil }

        // Split on the usual separators and take the first meaningful token.
        let tokens = local.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
            .map(String.init)
        guard let first = tokens.first(where: { isNameLike($0) }) else { return nil }

        // A first token that's itself a role word (sales.team@) is rejected.
        guard !roleAddresses.contains(first) else { return nil }

        return capitalizeName(first)
    }

    /// A suggested last name, or nil when the address doesn't clearly encode
    /// one. Much stricter than the first-name guess: it requires a two-plus
    /// token `first.last@` / `first_last@` / `first-last@` local part where
    /// *both* ends look like name words, so `jsmith@` and `sales.team@` yield
    /// nothing.
    static func suggestedLastName(from email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let at = trimmed.firstIndex(of: "@") else { return nil }
        var local = String(trimmed[..<at])
        if let plus = local.firstIndex(of: "+") { local = String(local[..<plus]) }
        guard !local.isEmpty, !roleAddresses.contains(local) else { return nil }

        let tokens = local.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
            .map(String.init)
        guard tokens.count >= 2,
              let first = tokens.first, let last = tokens.last,
              isNameLike(first), !roleAddresses.contains(first),
              isNameLike(last), !roleAddresses.contains(last),
              first != last
        else { return nil }
        return capitalizeName(last)
    }

    /// Whether a token could plausibly be a given name: alphabetic, 2+ letters,
    /// not all-consonant gibberish. A token in `commonNames` always qualifies.
    private static func isNameLike(_ token: String) -> Bool {
        guard token.count >= 2, token.allSatisfy({ $0.isLetter }) else { return false }
        if commonNames.contains(token) { return true }
        // Require at least one vowel so "xkcd"/"qwrtz" don't read as names.
        let vowels = Set("aeiouy")
        return token.contains { vowels.contains($0) }
    }

    /// Whether the inferred name is in the built-in common-name set — a caller
    /// can use this to only surface high-confidence suggestions.
    static func isCommonName(_ name: String) -> Bool {
        commonNames.contains(name.lowercased())
    }

    private static func capitalizeName(_ token: String) -> String {
        token.prefix(1).uppercased() + token.dropFirst()
    }
}
