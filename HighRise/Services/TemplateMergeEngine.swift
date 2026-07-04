import Foundation

/// Substitutes `{{Field}}` placeholders in a template with a contact's values.
///
/// Pure and deterministic: the same template and contact always produce the
/// same `MergePreview`. All the I/O (talking to Mail/Outlook) lives elsewhere,
/// which keeps this — the part where a personalization bug would embarrass the
/// user in front of a customer — fully unit-testable.
enum TemplateMergeEngine {

    /// Merges `template` against one `contact`.
    ///
    /// A placeholder is "unresolved" when the contact has no matching field (or
    /// the matching field is empty) *and* the placeholder carries no fallback —
    /// `{{First Name|there}}` substitutes its fallback instead of blocking.
    /// Unresolved placeholders are removed from the rendered output (so no raw
    /// `{{…}}` ever reaches a recipient) and reported on the preview so the
    /// review screen can block the send.
    static func merge(template: EmailTemplate, with contact: Contact,
                      isDuplicate: Bool = false, isSuppressed: Bool = false,
                      attachments: (paths: [String], missing: [String]) = ([], [])) -> MergePreview {
        var unresolved: [String] = []
        var seenUnresolved = Set<String>()

        // `escaping` is true only for the HTML body: substituted values — field
        // data and fallback text alike — may contain `<`, `>`, `&` and must be
        // neutralized so substituted text can never inject or break markup.
        // Subjects are always plain text, so they're never escaped.
        let substitute: (_ text: String, _ escaping: Bool) -> String = { text, escaping in
            replacePlaceholders(in: text) { token in
                // Resolve the base value: the contact's field, else the token's
                // fallback (from a `default:`/bare filter), else unresolved.
                let base: String
                if let value = contact.value(for: token.name),
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    base = value
                } else if let fallback = token.fallback {
                    base = fallback
                } else {
                    let key = token.name.lowercased()
                    if !seenUnresolved.contains(key) {
                        seenUnresolved.insert(key)
                        unresolved.append(token.name)
                    }
                    return "" // never leak a placeholder into outgoing mail
                }
                // Apply formatting filters (date, currency, casing, …) in order.
                let formatted = token.transforms.reduce(base) { MergeValueFormatter.apply($1, to: $0) }
                return escaping ? htmlEscape(formatted) : formatted
            }
        }

        // Pick the variant (if any) whose rule matches this contact.
        let effective = template.effective(for: contact)
        let subject = substitute(effective.subject, false)
        let body = substitute(effective.body, template.format == .html)

        return MergePreview(
            id: contact.id,
            contact: contact,
            resolvedSubject: subject,
            resolvedBody: body,
            unresolvedFields: unresolved,
            hasValidEmail: EmailValidator.isValid(contact.email),
            isDuplicate: isDuplicate,
            isSuppressed: isSuppressed,
            attachmentPaths: attachments.paths,
            missingAttachmentPaths: attachments.missing
        )
    }

    /// Merges the template against every contact, preserving order, flagging
    /// rows whose address repeats an earlier one, marking suppressed rows, and
    /// attaching per-recipient files resolved by `attachments` (a missing file
    /// blocks that row).
    static func mergeAll(template: EmailTemplate, contacts: [Contact],
                         isSuppressed: (Contact) -> Bool = { _ in false },
                         attachments: (Contact) -> (paths: [String], missing: [String]) = { _ in ([], []) }
    ) -> [MergePreview] {
        let duplicateIDs = DuplicateDetector.duplicateIDs(in: contacts)
        return contacts.map {
            merge(template: template, with: $0,
                  isDuplicate: duplicateIDs.contains($0.id),
                  isSuppressed: isSuppressed($0),
                  attachments: attachments($0))
        }
    }

    /// Resolves `{{Field}}` placeholders in a standalone string (e.g. a CC field
    /// that references `{{Manager Email}}`) against one contact. Unlike `merge`,
    /// this neither HTML-escapes nor reports unresolved fields — envelope
    /// addresses are validated separately by the caller. Fallbacks still apply.
    static func resolvePlaceholders(in text: String, with contact: Contact) -> String {
        replacePlaceholders(in: text) { token in
            let base: String
            if let value = contact.value(for: token.name),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                base = value
            } else {
                base = token.fallback ?? ""
            }
            return token.transforms.reduce(base) { MergeValueFormatter.apply($1, to: $0) }
        }
    }

    /// Escapes the five characters that are significant in HTML text/attributes.
    static func htmlEscape(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for ch in value {
            switch ch {
            case "&":  out += "&amp;"
            case "<":  out += "&lt;"
            case ">":  out += "&gt;"
            case "\"": out += "&quot;"
            case "'":  out += "&#39;"
            default:   out.append(ch)
            }
        }
        return out
    }

    /// Walks every `{{ … }}` occurrence and replaces it with `resolver`'s output.
    private static func replacePlaceholders(in text: String,
                                            resolver: (EmailTemplate.PlaceholderToken) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: EmailTemplate.placeholderPattern) else {
            return text
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var result = ""
        var lastEnd = 0
        for match in matches {
            let full = match.range
            result += nsText.substring(with: NSRange(location: lastEnd, length: full.location - lastEnd))
            let inner = nsText.substring(with: match.range(at: 1))
            result += resolver(EmailTemplate.token(fromRawPlaceholder: inner))
            lastEnd = full.location + full.length
        }
        result += nsText.substring(from: lastEnd)
        return result
    }
}
