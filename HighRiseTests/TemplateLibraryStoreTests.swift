import Testing
import Foundation
@testable import HighRise

/// The template library and autosave persist user work across launches, so
/// save/overwrite/delete and the JSON round trip (including variants) are pinned.
struct TemplateLibraryStoreTests {

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("highrise-lib-\(UUID().uuidString)")
    }

    @Test("A saved template round-trips through a fresh store, variants included")
    func persistsLibrary() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let template = EmailTemplate(
            subject: "Hi {{Name}}", body: "Base", format: .html,
            variants: [TemplateVariant(rule: RoutingRule(field: "Plan", predicate: .equals, value: "Pro"),
                                       subject: "Pro", body: "Pro body")])
        let first = TemplateLibraryStore(directory: dir)
        first.save(template, as: "Outreach")

        let second = TemplateLibraryStore(directory: dir)
        #expect(second.templates.count == 1)
        let loaded = try #require(second.templates.first)
        #expect(loaded.name == "Outreach")
        #expect(loaded.template.format == .html)
        #expect(loaded.template.variants.first?.rule.value == "Pro")
    }

    @Test("Saving an existing name overwrites in place, not append")
    func overwriteByName() {
        let store = TemplateLibraryStore(directory: nil) // in-memory
        store.save(EmailTemplate(subject: "v1", body: "x"), as: "Promo")
        store.save(EmailTemplate(subject: "v2", body: "y"), as: "promo") // case-insensitive
        #expect(store.templates.count == 1)
        #expect(store.templates.first?.template.subject == "v2")
    }

    @Test("Delete removes the template")
    func deleteTemplate() {
        let store = TemplateLibraryStore(directory: nil)
        let saved = store.save(EmailTemplate(subject: "s", body: "b"), as: "One")
        store.delete(id: saved.id)
        #expect(store.templates.isEmpty)
    }

    @Test("Autosave restores the working draft in a new store")
    func autosaveRoundTrip() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let draft = EmailTemplate(subject: "WIP {{Company}}", body: "Half-written")
        TemplateLibraryStore(directory: dir).saveAutosave(draft)

        let restored = TemplateLibraryStore(directory: dir).loadAutosave()
        #expect(restored?.subject == "WIP {{Company}}")
        #expect(restored?.body == "Half-written")
    }

    @Test("Autosave is nil when nothing was saved")
    func autosaveEmpty() {
        #expect(TemplateLibraryStore(directory: nil).loadAutosave() == nil)
    }
}
