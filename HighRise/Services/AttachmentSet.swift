import Foundation

/// Pure helpers for the campaign-wide attachment list: which files are missing,
/// and whether the combined size is likely to bounce.
///
/// Kept separate from the coordinator so the size math and the oversize
/// threshold are unit-testable without touching AppKit or a mail client.
enum AttachmentSet {

    /// Providers reject large messages; base64 encoding inflates attachments by
    /// ~33%, so warn well before common 25 MB hard limits.
    static let warningThresholdBytes: Int64 = 20 * 1_024 * 1_024

    /// The paths that don't exist on disk (so the run can be blocked before it
    /// starts rather than failing per-recipient).
    static func missing(_ urls: [URL],
                        existsAt: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [URL] {
        urls.filter { !existsAt($0.path) }
    }

    /// Sum of the given file sizes in bytes; unreadable files count as 0.
    static func totalBytes(_ urls: [URL],
                           sizeOf: (URL) -> Int64? = { url in
                               (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
                           }) -> Int64 {
        urls.reduce(0) { $0 + (sizeOf($1) ?? 0) }
    }

    /// A human-readable oversize warning when the total exceeds the threshold,
    /// else nil.
    static func oversizeWarning(totalBytes: Int64) -> String? {
        guard totalBytes > warningThresholdBytes else { return nil }
        let mb = Double(totalBytes) / (1_024 * 1_024)
        return String(format: "Attachments total about %.0f MB. Many mail servers reject messages over ~25 MB "
            + "(encoding adds ~33%%) — consider a link instead for large files.", mb)
    }

    /// Parses a per-recipient attachment cell into POSIX paths: split on `;`,
    /// trim, drop blanks, and expand a leading `~` to the home directory. Pure,
    /// so the parsing is unit-tested; existence is checked separately.
    static func paths(fromColumnValue value: String,
                      homeDirectory: String = NSHomeDirectory()) -> [String] {
        value.split(separator: ";").compactMap { piece in
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed == "~" { return homeDirectory }
            if trimmed.hasPrefix("~/") { return homeDirectory + String(trimmed.dropFirst()) }
            return trimmed
        }
    }
}
