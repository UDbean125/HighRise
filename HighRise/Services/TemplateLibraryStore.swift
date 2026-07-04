import Foundation

/// The on-device template library plus a crash-safe autosave of the working
/// draft, both persisted as JSON in Application Support.
///
/// The library is an explicit save/load/delete list of named templates; the
/// autosave silently preserves whatever the user is composing so it survives a
/// quit or crash. File I/O is injectable (`directory: nil` → in-memory) so the
/// store is unit-testable without touching the real Application Support folder.
final class TemplateLibraryStore {

    private(set) var templates: [SavedTemplate]
    private let libraryURL: URL?
    private let autosaveURL: URL?

    init(directory: URL? = TemplateLibraryStore.defaultDirectory) {
        libraryURL = directory?.appendingPathComponent("templates.json")
        autosaveURL = directory?.appendingPathComponent("autosave.json")
        templates = TemplateLibraryStore.decode([SavedTemplate].self, from: libraryURL) ?? []
    }

    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("HighRise")
    }

    // MARK: - Library

    /// Saves `template` under `name`. If a template with that name already
    /// exists (case-insensitive) it's overwritten in place; otherwise a new one
    /// is appended. Returns the saved record.
    @discardableResult
    func save(_ template: EmailTemplate, as name: String, now: Date = Date()) -> SavedTemplate {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = templates.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            let updated = SavedTemplate(id: templates[index].id, name: trimmed,
                                        template: template, savedAt: now)
            templates[index] = updated
            persistLibrary()
            return updated
        }
        let record = SavedTemplate(name: trimmed, template: template, savedAt: now)
        templates.append(record)
        persistLibrary()
        return record
    }

    func delete(id: UUID) {
        templates.removeAll { $0.id == id }
        persistLibrary()
    }

    // MARK: - Autosave

    func saveAutosave(_ template: EmailTemplate) {
        guard let autosaveURL else { return }
        try? Self.encode(template, to: autosaveURL)
    }

    func loadAutosave() -> EmailTemplate? {
        Self.decode(EmailTemplate.self, from: autosaveURL)
    }

    // MARK: - Persistence

    private func persistLibrary() {
        guard let libraryURL else { return }
        try? Self.encode(templates, to: libraryURL)
    }

    private static func encode<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
