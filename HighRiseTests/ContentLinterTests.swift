import Testing
import Foundation
@testable import HighRise

/// The content check nudges users away from spam-filter bait, so each rule is
/// pinned — including the placeholder-stripping that keeps `{{PO Number}}`
/// from being mistaken for shouting.
struct ContentLinterTests {

    private func template(subject: String, body: String) -> EmailTemplate {
        EmailTemplate(subject: subject, body: body)
    }

    private func messages(_ findings: [ContentLinter.Finding]) -> [String] {
        findings.map(\.message)
    }

    @Test("A clean personalized template passes with a perfect score")
    func cleanTemplate() {
        let clean = template(subject: "Quick idea for {{Company}}",
                             body: "Hi {{First Name|there}},\n\nA thought about your work. Worth a short call?\n\nBest,\nSam")
        let findings = ContentLinter.lint(template: clean)
        #expect(findings.isEmpty, "unexpected findings: \(messages(findings))")
        #expect(ContentLinter.score(for: findings) == 100)
        #expect(ContentLinter.grade(for: 100) == "Looking great")
    }

    @Test("Empty subject is a warning")
    func emptySubject() {
        let findings = ContentLinter.lint(template: template(subject: "  ", body: "Hi {{Name}}"))
        #expect(findings.contains { $0.severity == .warning && $0.message.contains("subject") })
    }

    @Test("Overlong subject is a tip")
    func longSubject() {
        let long = String(repeating: "word ", count: 16)   // ~80 chars
        let findings = ContentLinter.lint(template: template(subject: long, body: "Hi {{Name}}"))
        #expect(findings.contains { $0.severity == .tip && $0.message.contains("Long subject") })
    }

    @Test("Repeated exclamation marks in the subject warn")
    func subjectExclamations() {
        let findings = ContentLinter.lint(template: template(subject: "Open now!! Please!", body: "Hi {{Name}}"))
        #expect(findings.contains { $0.message.contains("spam trigger") })
    }

    @Test("ALL-CAPS subject words warn, but {{PLACEHOLDER}} tokens don't")
    func shouting() {
        let shouty = ContentLinter.lint(template: template(subject: "AMAZING deal inside", body: "Hi {{Name}}"))
        #expect(shouty.contains { $0.message.contains("ALL-CAPS") })

        let tokenOnly = ContentLinter.lint(template: template(subject: "Invoice {{INVOICE NUMBER}} attached",
                                                              body: "Hi {{Name}}"))
        #expect(!tokenOnly.contains { $0.message.contains("ALL-CAPS") },
                "placeholder contents must not count as shouting")
    }

    @Test("Known spam phrases are called out")
    func spamPhrases() {
        let findings = ContentLinter.lint(template: template(subject: "One chance",
                                                             body: "Act now — this is 100% free for {{Name}}."))
        #expect(findings.contains { $0.severity == .warning && $0.message.contains("Spam-filter bait") })
    }

    @Test("Link-heavy bodies get a tip")
    func manyLinks() {
        let body = "See https://a.com https://b.com https://c.com and http://d.com — {{Name}}"
        let findings = ContentLinter.lint(template: template(subject: "Links", body: body))
        #expect(findings.contains { $0.severity == .tip && $0.message.contains("links") })
    }

    @Test("No merge fields yields a personalization tip")
    func notPersonalized() {
        let findings = ContentLinter.lint(template: template(subject: "Hello", body: "Same email for everyone."))
        #expect(findings.contains { $0.message.contains("merge fields") })
    }

    @Test("Scores floor at zero and grades follow the bands")
    func scoring() {
        let warning = ContentLinter.Finding(severity: .warning, message: "w", systemImage: "x")
        let tip = ContentLinter.Finding(severity: .tip, message: "t", systemImage: "x")
        #expect(ContentLinter.score(for: []) == 100)
        #expect(ContentLinter.score(for: [warning]) == 85)
        #expect(ContentLinter.score(for: [warning, tip]) == 80)
        #expect(ContentLinter.score(for: Array(repeating: warning, count: 10)) == 0)
        #expect(ContentLinter.grade(for: 85) == "Good — minor tweaks")
        #expect(ContentLinter.grade(for: 60) == "Needs attention")
        #expect(ContentLinter.grade(for: 10) == "High spam risk")
    }

    @Test("shoutedWords ignores short words and mixed case")
    func shoutedWordsHelper() {
        #expect(ContentLinter.shoutedWords(in: "The BIG DEAL is OK now") == ["DEAL"])
        #expect(ContentLinter.shoutedWords(in: "nothing here").isEmpty)
    }
}
