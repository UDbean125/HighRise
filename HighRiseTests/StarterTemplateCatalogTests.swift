import Testing
import Foundation
@testable import HighRise

/// The starter gallery is a new user's first impression *and* their tutorial in
/// the merge syntax, so the catalog is pinned: it must be well-formed, and — the
/// load-bearing guarantee — every fallback placeholder it ships must resolve so
/// a starter previewed against the sample never shows the user a raw `{{token}}`.
struct StarterTemplateCatalogTests {

    private var all: [StarterTemplate] { StarterTemplateCatalog.all }

    @Test("Ships a non-trivial, well-formed catalog")
    func wellFormed() {
        #expect(all.count >= 6)
        #expect(Set(all.map(\.id)).count == all.count, "IDs must be unique")
        #expect(Set(all.map(\.name)).count == all.count, "Names must be unique")
        for starter in all {
            #expect(!starter.id.isEmpty)
            #expect(!starter.name.isEmpty)
            #expect(!starter.category.isEmpty)
            #expect(!starter.systemImage.isEmpty)
            #expect(!starter.blurb.isEmpty)
            #expect(!starter.subject.isEmpty, "\(starter.id) has an empty subject")
            #expect(!starter.body.isEmpty, "\(starter.id) has an empty body")
        }
    }

    @Test("emailTemplate round-trips the starter's content")
    func emailTemplateRoundTrips() {
        for starter in all {
            let template = starter.emailTemplate
            #expect(template.subject == starter.subject)
            #expect(template.body == starter.body)
            #expect(template.format == starter.format)
        }
    }

    @Test("Never leaks a raw placeholder, even with no data at all")
    func neverLeaksAPlaceholder() {
        // The load-bearing guarantee: whatever the row, a raw `{{token}}` must
        // never reach the rendered output. Merging against a contact with *no*
        // fields is the worst case — every placeholder must still be stripped
        // (to its fallback, a formatted value, or empty).
        let empty = Contact(fields: [:], email: "nobody@example.com")
        for starter in all {
            let preview = TemplateMergeEngine.merge(template: starter.emailTemplate, with: empty)
            #expect(!preview.resolvedSubject.contains("{{"),
                    "\(starter.id) subject leaked a placeholder")
            #expect(!preview.resolvedBody.contains("{{"),
                    "\(starter.id) body leaked a placeholder")
        }
    }

    @Test("Previews cleanly against the built-in sample recipient")
    func mergesAgainstSample() {
        // Each starter is authored to line up with `Contact.sample`, so the very
        // first preview a newcomer sees looks like a genuine send: no "missing
        // for this recipient" warnings, no blank spots.
        for starter in all {
            let preview = TemplateMergeEngine.merge(template: starter.emailTemplate, with: .sample)
            #expect(preview.unresolvedFields.isEmpty,
                    "\(starter.id) references fields the sample can't fill: \(preview.unresolvedFields)")
        }
    }
}
