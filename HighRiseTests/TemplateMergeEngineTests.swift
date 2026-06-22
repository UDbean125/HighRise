import Testing
import Foundation
@testable import HighRise

/// The merge engine is where a personalization bug embarrasses the user in
/// front of a customer, so its behavior is pinned tightly: correct substitution,
/// no leaked placeholders, missing-field detection, and HTML escaping.
struct TemplateMergeEngineTests {

    private func contact(_ fields: [String: String], email: String = "a@b.com") -> Contact {
        Contact(fields: fields, email: email)
    }

    @Test("Substitutes fields in subject and body")
    func basicSubstitution() {
        let template = EmailTemplate(subject: "Hi {{Name}} at {{Company}}",
                                     body: "Dear {{Name}},\nAbout {{Company}}.")
        let preview = TemplateMergeEngine.merge(template: template,
                                                with: contact(["Name": "Ada", "Company": "Acme"]))
        #expect(preview.resolvedSubject == "Hi Ada at Acme")
        #expect(preview.resolvedBody == "Dear Ada,\nAbout Acme.")
        #expect(preview.unresolvedFields.isEmpty)
    }

    @Test("Placeholder matching is case- and whitespace-insensitive")
    func looseMatching() {
        let template = EmailTemplate(subject: "{{ name }}", body: "{{NAME}}")
        let preview = TemplateMergeEngine.merge(template: template, with: contact(["Name": "Ada"]))
        #expect(preview.resolvedSubject == "Ada")
        #expect(preview.resolvedBody == "Ada")
    }

    @Test("Missing fields are reported and never leaked as raw braces")
    func missingFields() {
        let template = EmailTemplate(subject: "Hi {{Name}}", body: "Re: {{Project}}")
        let preview = TemplateMergeEngine.merge(template: template, with: contact(["Name": "Ada"]))
        #expect(preview.unresolvedFields == ["Project"])
        #expect(!preview.resolvedBody.contains("{{"))
        #expect(preview.resolvedBody == "Re: ")
        #expect(!preview.isSendable) // blocked from sending
    }

    @Test("An empty field counts as unresolved")
    func emptyFieldUnresolved() {
        let template = EmailTemplate(subject: "Hi {{Name}}", body: "x")
        let preview = TemplateMergeEngine.merge(template: template, with: contact(["Name": "   "]))
        #expect(preview.unresolvedFields == ["Name"])
    }

    @Test("Invalid email makes the preview non-sendable")
    func invalidEmailBlocks() {
        let template = EmailTemplate(subject: "Hi", body: "x")
        let preview = TemplateMergeEngine.merge(template: template,
                                                with: contact(["Name": "Ada"], email: "not-an-email"))
        #expect(!preview.hasValidEmail)
        #expect(!preview.isSendable)
    }

    @Test("HTML body escapes substituted field values")
    func htmlEscaping() {
        let template = EmailTemplate(subject: "Hi {{Name}}",
                                     body: "<p>Hello {{Name}} from {{Company}}</p>",
                                     format: .html)
        let preview = TemplateMergeEngine.merge(template: template,
                                                with: contact(["Name": "A<b>", "Company": "S&S"]))
        #expect(preview.resolvedBody == "<p>Hello A&lt;b&gt; from S&amp;S</p>")
        // Subject is plain text and is never escaped.
        #expect(preview.resolvedSubject == "Hi A<b>")
    }

    @Test("Plain-text body does not escape values")
    func plainTextNoEscaping() {
        let template = EmailTemplate(subject: "x", body: "Hello {{Name}}", format: .plainText)
        let preview = TemplateMergeEngine.merge(template: template, with: contact(["Name": "A & B"]))
        #expect(preview.resolvedBody == "Hello A & B")
    }

    @Test("referencedFields lists distinct placeholders in order")
    func referencedFields() {
        let template = EmailTemplate(subject: "{{Name}} {{Company}}", body: "{{Name}} {{Project}}")
        #expect(template.referencedFields == ["Name", "Company", "Project"])
    }
}
