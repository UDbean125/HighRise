import Testing
@testable import HighRise

/// Routing decides which subject/body a recipient gets, so the predicate logic
/// and first-match-wins selection are pinned, including through the merge engine.
struct TemplateVariantTests {

    private func contact(_ fields: [String: String], email: String = "a@b.com") -> Contact {
        Contact(fields: fields, email: email)
    }

    @Test("is filled in / is empty predicates")
    func emptiness() {
        let filled = RoutingRule(field: "Region", predicate: .isNotEmpty)
        #expect(filled.matches(contact(["Region": "EMEA"])))
        #expect(!filled.matches(contact(["Region": "  "])))
        #expect(!filled.matches(contact([:])))

        let empty = RoutingRule(field: "Region", predicate: .isEmpty)
        #expect(empty.matches(contact([:])))
        #expect(!empty.matches(contact(["Region": "EMEA"])))
    }

    @Test("equals / is-not predicates are case-insensitive")
    func equality() {
        let eq = RoutingRule(field: "Plan", predicate: .equals, value: "pro")
        #expect(eq.matches(contact(["Plan": "Pro"])))
        #expect(!eq.matches(contact(["Plan": "Free"])))

        let ne = RoutingRule(field: "Plan", predicate: .notEquals, value: "pro")
        #expect(ne.matches(contact(["Plan": "Free"])))
        #expect(!ne.matches(contact(["Plan": "PRO"])))
    }

    @Test("effective() returns the first matching variant, else the base")
    func firstMatchWins() {
        let template = EmailTemplate(
            subject: "Base subject", body: "Base body",
            variants: [
                TemplateVariant(rule: RoutingRule(field: "Plan", predicate: .equals, value: "Pro"),
                                subject: "Pro subject", body: "Pro body"),
                TemplateVariant(rule: RoutingRule(field: "Region", predicate: .isNotEmpty),
                                subject: "Region subject", body: "Region body"),
            ])

        #expect(template.effective(for: contact(["Plan": "Pro"])).subject == "Pro subject")
        // No Plan match, but Region is filled → second variant.
        #expect(template.effective(for: contact(["Region": "EMEA"])).body == "Region body")
        // Neither matches → base.
        #expect(template.effective(for: contact(["Plan": "Free"])).subject == "Base subject")
    }

    @Test("The merge engine renders the routed variant with placeholders")
    func routedMerge() {
        let template = EmailTemplate(
            subject: "Hi {{Name}}", body: "Base",
            variants: [
                TemplateVariant(rule: RoutingRule(field: "Plan", predicate: .equals, value: "Pro"),
                                subject: "Hi {{Name}}", body: "Thanks for being a Pro, {{Name}}!"),
            ])
        let pro = TemplateMergeEngine.merge(template: template, with: contact(["Name": "Ada", "Plan": "Pro"]))
        #expect(pro.resolvedBody == "Thanks for being a Pro, Ada!")
        let base = TemplateMergeEngine.merge(template: template, with: contact(["Name": "Bo", "Plan": "Free"]))
        #expect(base.resolvedBody == "Base")
    }

    @Test("referencedFields spans base, variants, and rule fields")
    func referencedFieldsAcrossVariants() {
        let template = EmailTemplate(
            subject: "{{Name}}", body: "{{Company}}",
            variants: [
                TemplateVariant(rule: RoutingRule(field: "Plan", predicate: .isNotEmpty),
                                subject: "{{Tier}}", body: "{{Perk}}"),
            ])
        let fields = template.referencedFields.map { $0.lowercased() }
        #expect(fields.contains("name"))
        #expect(fields.contains("company"))
        #expect(fields.contains("tier"))
        #expect(fields.contains("perk"))
        #expect(fields.contains("plan"))     // rule field is recognized
    }

    @Test("A routing-rule field alone doesn't block a send")
    func ruleFieldNotRequired() {
        let template = EmailTemplate(
            subject: "Hi", body: "Base",
            variants: [
                TemplateVariant(rule: RoutingRule(field: "Region", predicate: .isNotEmpty),
                                subject: "Hi", body: "Regional"),
            ])
        // No Region column at all, but nothing references {{Region}} as data.
        #expect(!template.fieldsRequiringData.map { $0.lowercased() }.contains("region"))
        let preview = TemplateMergeEngine.merge(template: template, with: contact([:]))
        #expect(preview.isSendable)
    }
}
