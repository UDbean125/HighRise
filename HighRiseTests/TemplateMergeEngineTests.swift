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

    // MARK: - Fallback values ({{Field|fallback}})

    @Test("Fallback is used when the field is missing, and the row still sends")
    func fallbackForMissingField() {
        let template = EmailTemplate(subject: "Hi {{First Name|there}}", body: "x")
        let preview = TemplateMergeEngine.merge(template: template, with: contact([:]))
        #expect(preview.resolvedSubject == "Hi there")
        #expect(preview.unresolvedFields.isEmpty)
        #expect(preview.isSendable)
    }

    @Test("Fallback is used when the field is empty or whitespace")
    func fallbackForEmptyField() {
        let template = EmailTemplate(subject: "Hi {{Name|friend}}", body: "x")
        let preview = TemplateMergeEngine.merge(template: template, with: contact(["Name": "   "]))
        #expect(preview.resolvedSubject == "Hi friend")
        #expect(preview.unresolvedFields.isEmpty)
    }

    @Test("A real value always wins over the fallback")
    func valueBeatsFallback() {
        let template = EmailTemplate(subject: "Hi {{Name|there}}", body: "x")
        let preview = TemplateMergeEngine.merge(template: template, with: contact(["Name": "Ada"]))
        #expect(preview.resolvedSubject == "Hi Ada")
    }

    @Test("An explicitly empty fallback renders nothing without blocking")
    func emptyFallbackAllowsBlank() {
        let template = EmailTemplate(subject: "Hi{{ Honorific|}} {{Name}}", body: "x")
        let preview = TemplateMergeEngine.merge(template: template, with: contact(["Name": "Ada"]))
        #expect(preview.resolvedSubject == "Hi Ada")
        #expect(preview.unresolvedFields.isEmpty)
    }

    @Test("Without a fallback a missing field still blocks — opt-in only")
    func noFallbackStillBlocks() {
        let template = EmailTemplate(subject: "Hi {{Name}}", body: "x")
        let preview = TemplateMergeEngine.merge(template: template, with: contact([:]))
        #expect(preview.unresolvedFields == ["Name"])
        #expect(!preview.isSendable)
    }

    @Test("Fallback syntax tolerates whitespace around name and fallback")
    func fallbackWhitespaceTolerant() {
        let template = EmailTemplate(subject: "{{ first name | there }}", body: "x")
        let preview = TemplateMergeEngine.merge(template: template,
                                                with: contact(["First Name": "Ada"]))
        #expect(preview.resolvedSubject == "Ada")
        let missing = TemplateMergeEngine.merge(template: template, with: contact([:]))
        #expect(missing.resolvedSubject == "there")
    }

    @Test("Fallback text is HTML-escaped in HTML bodies, like field values")
    func fallbackHTMLEscaped() {
        let template = EmailTemplate(subject: "x", body: "<p>{{Name|friend & colleague}}</p>",
                                     format: .html)
        let preview = TemplateMergeEngine.merge(template: template, with: contact([:]))
        #expect(preview.resolvedBody == "<p>friend &amp; colleague</p>")
    }

    @Test("Pipes separate filters; a bare first segment is the fallback")
    func pipesSeparateFilters() {
        let token = EmailTemplate.token(fromRawPlaceholder: "Name|there|upper")
        #expect(token.name == "Name")
        #expect(token.fallback == "there")             // first bare segment → default
        #expect(token.transforms == [.upper])          // recognized filter
    }

    @Test("fieldsRequiringData exempts fields whose every use has a fallback")
    func fieldsRequiringData() {
        let template = EmailTemplate(subject: "{{Name|there}} {{Company}}",
                                     body: "{{Name}} {{Project|the project}}")
        // Name appears once WITH and once WITHOUT a fallback → still required.
        #expect(template.fieldsRequiringData == ["Name", "Company"])
        // referencedFields keeps listing every base name.
        #expect(template.referencedFields == ["Name", "Company", "Project"])
    }

    // MARK: - Duplicate detection

    @Test("mergeAll flags later duplicate addresses and keeps the first sendable")
    func duplicatesFlaggedByMergeAll() {
        let template = EmailTemplate(subject: "Hi {{Name}}", body: "x")
        let contacts = [
            Contact(fields: ["Name": "Ada"], email: "dup@x.com"),
            Contact(fields: ["Name": "Bo"], email: "unique@x.com"),
            Contact(fields: ["Name": "Cy"], email: "DUP@x.com "), // same as row 0, cased/spaced
        ]
        let previews = TemplateMergeEngine.mergeAll(template: template, contacts: contacts)
        #expect(previews[0].isDuplicate == false)
        #expect(previews[0].isSendable)          // first occurrence sends
        #expect(previews[1].isDuplicate == false)
        #expect(previews[2].isDuplicate)          // later repeat held back
        #expect(!previews[2].isSendable)
        #expect(previews[2].blockingReason?.contains("Duplicate") == true)
    }

    @Test("A single-merged preview is never a duplicate")
    func singleMergeNeverDuplicate() {
        let template = EmailTemplate(subject: "Hi", body: "x")
        let preview = TemplateMergeEngine.merge(template: template, with: contact([:]))
        #expect(!preview.isDuplicate)
    }
}
