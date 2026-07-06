import Foundation

/// Local, heuristic quality checks for a template: spam-filter triggers,
/// clipped subjects, and missed personalization. Everything runs on-device —
/// no content is sent anywhere — and it's advisory, never blocking.
enum ContentLinter {

    struct Finding: Identifiable, Equatable {
        enum Severity: Equatable {
            /// Likely to hurt delivery or look unprofessional.
            case warning
            /// Worth considering; smaller stakes.
            case tip
        }

        var id: String { message }
        let severity: Severity
        let message: String
        let systemImage: String
    }

    /// Phrases that commonly trip spam filters. Deliberately short and
    /// conservative — this is a nudge, not a spam-scoring engine.
    static let spamPhrases: [String] = [
        "act now", "buy now", "click here", "100% free", "risk-free",
        "limited time", "winner", "cash bonus", "double your", "earn extra",
        "no obligation", "urgent response", "once in a lifetime"
    ]

    /// Lints the template's main subject and body (variants inherit the same
    /// writing, so the main copy is where feedback pays off).
    static func lint(template: EmailTemplate) -> [Finding] {
        var findings: [Finding] = []
        // Strip {{placeholders}} first: tokens like {{PO Number}} aren't
        // shouting, and fallbacks aren't spam phrases.
        let subject = strippingPlaceholders(from: template.subject)
        let body = strippingPlaceholders(from: template.body)
        let subjectTrimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)

        if template.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            findings.append(Finding(severity: .warning,
                                    message: "Add a subject — subjectless emails scream spam.",
                                    systemImage: "envelope.badge.shield.half.filled"))
        } else if subjectTrimmed.count > 65 {
            findings.append(Finding(severity: .tip,
                                    message: "Long subject — inboxes clip around 60 characters.",
                                    systemImage: "scissors"))
        }

        if subject.filter({ $0 == "!" }).count >= 2 {
            findings.append(Finding(severity: .warning,
                                    message: "Multiple “!” in the subject is a classic spam trigger.",
                                    systemImage: "exclamationmark.triangle"))
        }

        if !shoutedWords(in: subject).isEmpty {
            findings.append(Finding(severity: .warning,
                                    message: "ALL-CAPS words in the subject often get flagged.",
                                    systemImage: "textformat.size.larger"))
        }

        let everything = (subject + " " + body).lowercased()
        let hits = spamPhrases.filter { everything.contains($0) }
        if !hits.isEmpty {
            findings.append(Finding(severity: .warning,
                                    message: "Spam-filter bait: “\(hits.prefix(2).joined(separator: "”, “"))”.",
                                    systemImage: "hand.raised"))
        }

        if shoutedWords(in: body).count >= 3 {
            findings.append(Finding(severity: .warning,
                                    message: "Several ALL-CAPS words in the body read as shouting.",
                                    systemImage: "speaker.wave.3"))
        }

        if body.filter({ $0 == "!" }).count > 3 {
            findings.append(Finding(severity: .tip,
                                    message: "Lots of exclamation marks — calmer copy converts better.",
                                    systemImage: "exclamationmark.2"))
        }

        if linkCount(in: body) > 3 {
            findings.append(Finding(severity: .tip,
                                    message: "More than three links makes filters (and readers) wary.",
                                    systemImage: "link"))
        }

        if template.referencedFields.isEmpty &&
            !(template.subject.isEmpty && template.body.isEmpty) {
            findings.append(Finding(severity: .tip,
                                    message: "No merge fields yet — add {{First Name}} to make it personal.",
                                    systemImage: "person.text.rectangle"))
        }

        if !template.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !GreetingCheck.opensWithGreeting(template.body) {
            findings.append(Finding(severity: .tip,
                                    message: "Consider opening with a greeting, like “Hi {{First Name}},”.",
                                    systemImage: "hand.wave"))
        }

        return findings
    }

    /// 0–100: start perfect, warnings cost 15, tips cost 5.
    static func score(for findings: [Finding]) -> Int {
        let penalty = findings.reduce(0) { $0 + ($1.severity == .warning ? 15 : 5) }
        return max(0, 100 - penalty)
    }

    /// A short human label for a score.
    static func grade(for score: Int) -> String {
        switch score {
        case 90...: return "Looking great"
        case 75..<90: return "Good — minor tweaks"
        case 50..<75: return "Needs attention"
        default: return "High spam risk"
        }
    }

    // MARK: - Helpers

    private static func strippingPlaceholders(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{[^{}]*\}\}"#) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    /// Words of 4+ letters written entirely in uppercase (A–Z only).
    static func shoutedWords(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter }).compactMap { word in
            guard word.count >= 4 else { return nil }
            let s = String(word)
            return s == s.uppercased() && s != s.lowercased() ? s : nil
        }
    }

    private static func linkCount(in text: String) -> Int {
        let lower = text.lowercased()
        return lower.components(separatedBy: "http://").count - 1
             + lower.components(separatedBy: "https://").count - 1
    }
}
