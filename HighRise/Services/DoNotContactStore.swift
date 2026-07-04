import Foundation

/// The on-device do-not-contact list: addresses and whole domains that are
/// silently skipped in every merge.
///
/// Persisted as JSON in Application Support (the app is unsandboxed, so this is
/// a plain file write). Matching, normalization, and mutation are pure and
/// file-I/O is injectable (`fileURL: nil` gives an in-memory store), so the
/// behavior that decides whether someone gets emailed is fully unit-tested.
final class DoNotContactStore {

    private(set) var entries: [SuppressionEntry]
    private let fileURL: URL?

    init(fileURL: URL? = DoNotContactStore.defaultFileURL) {
        self.fileURL = fileURL
        self.entries = DoNotContactStore.load(from: fileURL)
    }

    /// `~/Library/Application Support/HighRise/do-not-contact.json`.
    static var defaultFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("HighRise/do-not-contact.json")
    }

    // MARK: - Matching

    /// Whether `email` is suppressed by an address entry (exact, case-insensitive)
    /// or a domain entry (its `@…` part). Blank input is never suppressed.
    func isSuppressed(_ email: String) -> Bool {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !address.isEmpty else { return false }
        let domain = address.firstIndex(of: "@").map { String(address[address.index(after: $0)...]) }
        return entries.contains { entry in
            switch entry.kind {
            case .address: return entry.value == address
            case .domain:  return entry.value == domain
            }
        }
    }

    // MARK: - Normalization

    /// A normalized address (trimmed, lowercased) if it's a valid email, else nil.
    static func normalizeAddress(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailValidator.isValid(trimmed) else { return nil }
        return trimmed.lowercased()
    }

    /// A normalized domain (trimmed, lowercased, leading `@` dropped) if it looks
    /// like a domain — has a dot, no spaces, no `@` — else nil.
    static func normalizeDomain(_ input: String) -> String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("@") { value.removeFirst() }
        guard value.contains("."), !value.contains("@"),
              !value.contains(where: { $0.isWhitespace }),
              !value.hasPrefix("."), !value.hasSuffix(".") else { return nil }
        return value
    }

    // MARK: - Mutation

    /// Adds an address entry. Returns false if the input isn't a valid address
    /// or is already present (so callers can report bad input).
    @discardableResult
    func addAddress(_ input: String, note: String? = nil, now: Date = Date()) -> Bool {
        guard let value = Self.normalizeAddress(input) else { return false }
        return insert(SuppressionEntry(kind: .address, value: value, dateAdded: now, note: note))
    }

    /// Adds a domain entry (e.g. `acme.com` or `@acme.com`).
    @discardableResult
    func addDomain(_ input: String, note: String? = nil, now: Date = Date()) -> Bool {
        guard let value = Self.normalizeDomain(input) else { return false }
        return insert(SuppressionEntry(kind: .domain, value: value, dateAdded: now, note: note))
    }

    func remove(_ entry: SuppressionEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    private func insert(_ entry: SuppressionEntry) -> Bool {
        guard !entries.contains(where: { $0.id == entry.id }) else { return false }
        entries.append(entry)
        persist()
        return true
    }

    // MARK: - Persistence

    private static func load(from url: URL?) -> [SuppressionEntry] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SuppressionEntry].self, from: data)) ?? []
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.csv.error("Could not save do-not-contact list: \(error.localizedDescription, privacy: .public)")
        }
    }
}
