import Foundation

/// Builds a safe, per-recipient PDF filename from a `{{Field}}` pattern.
///
/// Pure and filesystem-agnostic so the naming — the part that can collide,
/// escape a folder, or produce an illegal name — is unit-tested. Rendering the
/// PDF itself lives in `PDFComposer`.
enum PDFFilename {

    /// Resolves `pattern` against `contact`, sanitizes it into a legal single
    /// filename, and guarantees a `.pdf` extension. Falls back to `fallback`
    /// (also sanitized) when the resolved name is empty.
    static func make(pattern: String, contact: Contact, fallback: String) -> String {
        let resolved = TemplateMergeEngine.resolvePlaceholders(in: pattern, with: contact)
        let base = sanitize(resolved)
        let safeBase = base.isEmpty ? sanitize(fallback) : base
        let finalBase = safeBase.isEmpty ? "recipient" : safeBase
        return ensurePDFExtension(finalBase)
    }

    /// Strips path separators and illegal/control characters, collapses
    /// whitespace, trims leading dots, and caps the length.
    static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\0")
        var cleaned = name.components(separatedBy: illegal).joined(separator: "-")
        cleaned = cleaned.components(separatedBy: .controlCharacters).joined()
        cleaned = cleaned.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if cleaned.count > 120 { cleaned = String(cleaned.prefix(120)).trimmingCharacters(in: .whitespaces) }
        return cleaned
    }

    private static func ensurePDFExtension(_ base: String) -> String {
        base.lowercased().hasSuffix(".pdf") ? base : base + ".pdf"
    }
}
