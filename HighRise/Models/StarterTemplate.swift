import Foundation

/// A ready-made template a user can start from with one click. Each one is
/// written to *show off* the merge syntax — fields, `|fallback`s, and
/// `|date:`/`|currency:` formatters — so the gallery doubles as a tutorial.
struct StarterTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    /// SF Symbol shown on the gallery card.
    let systemImage: String
    /// One-line description of when to use it.
    let blurb: String
    let subject: String
    let body: String
    var format: EmailTemplate.BodyFormat = .plainText

    var emailTemplate: EmailTemplate {
        EmailTemplate(subject: subject, body: body, format: format)
    }
}

/// The built-in gallery of starter templates.
enum StarterTemplateCatalog {

    static let all: [StarterTemplate] = [
        StarterTemplate(
            id: "sales-outreach",
            name: "Sales outreach",
            category: "Grow",
            systemImage: "sparkle.magnifyingglass",
            blurb: "A warm first-touch email to a prospect.",
            subject: "Quick idea for {{Company}}",
            body: """
            Hi {{First Name|there}},

            I've been following {{Company}} and had a thought about {{Product Name|your team's goals}} I wanted to share.

            Companies like yours in {{Industry|your space}} are usually trying to do more without adding headcount — and that's exactly where we help. Would a short call next week be worth 15 minutes?

            Either way, keep up the great work.

            Best,
            {{Sales Rep|Your name}}
            """
        ),
        StarterTemplate(
            id: "follow-up",
            name: "Follow-up nudge",
            category: "Grow",
            systemImage: "arrow.uturn.left.circle",
            blurb: "A light, friendly bump when you haven't heard back.",
            subject: "Following up, {{First Name|there}}",
            body: """
            Hi {{First Name|there}},

            Just floating this back to the top of your inbox — no pressure at all. If now isn't the right time for {{Company}}, totally understand; just let me know and I'll check back later.

            If it is, here's the one thing I'd suggest as a next step: {{Next Step|a quick 15-minute call}}.

            Thanks!
            {{Sales Rep|Your name}}
            """
        ),
        StarterTemplate(
            id: "meeting-request",
            name: "Meeting request",
            category: "Connect",
            systemImage: "calendar.badge.plus",
            blurb: "Propose a time to talk.",
            subject: "Time to connect the week of {{Meeting Date|date:MMMM d}}?",
            body: """
            Hi {{First Name|there}},

            I'd love to find 20–30 minutes to walk through how we could help {{Company}}. Would sometime around {{Meeting Date|date:EEEE, MMMM d}} work for you?

            If that's tricky, send me a couple of windows that suit you and I'll make one work.

            Looking forward to it,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "invoice-reminder",
            name: "Invoice reminder",
            category: "Get paid",
            systemImage: "doc.text.badge.clock",
            blurb: "A polite nudge on an outstanding invoice.",
            subject: "Invoice {{Invoice Number}} — due {{Due Date|date:MMMM d, yyyy}}",
            body: """
            Hi {{First Name|there}},

            A quick, friendly reminder that invoice {{Invoice Number}} for {{Amount|currency:USD}} is due on {{Due Date|date:MMMM d, yyyy}}.

            If you've already sent payment, thank you — please disregard this note. If not, you can reply here with any questions and I'll help sort it out.

            Appreciate your business,
            {{Account Manager|Accounts team}}
            """
        ),
        StarterTemplate(
            id: "renewal",
            name: "Renewal reminder",
            category: "Retain",
            systemImage: "arrow.triangle.2.circlepath",
            blurb: "Give customers a heads-up before renewal.",
            subject: "Your {{Product Name|subscription}} renews {{Renewal Date|date:MMMM d, yyyy}}",
            body: """
            Hi {{First Name|there}},

            Just a heads-up that {{Company}}'s {{Product Name|plan}} is set to renew on {{Renewal Date|date:MMMM d, yyyy}} at {{Amount|currency:USD}}.

            There's nothing you need to do to keep everything running. But if you'd like to review your plan or chat about what's next, I'm one reply away.

            Thanks for being with us,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "event-invite",
            name: "Event invitation",
            category: "Connect",
            systemImage: "party.popper",
            blurb: "Invite contacts to a webinar or event.",
            subject: "You're invited, {{First Name|there}} 🎉",
            body: """
            Hi {{First Name|there}},

            We're hosting something we think you'll enjoy, and we'd love for you and the {{Company}} team to join us on {{Meeting Date|date:EEEE, MMMM d}}.

            It's a relaxed, practical session — no hard sell, just useful ideas you can take back to work the same day.

            Save your spot by replying "count me in" and I'll send the details.

            Hope to see you there,
            {{Sales Rep|The team}}
            """
        )
    ]
}
