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
///
/// Authoring rules (pinned by `StarterTemplateCatalogTests`):
/// - Every referenced field must either exist on `Contact.sample` or carry a
///   `|fallback`, so a newcomer's very first preview is clean.
/// - Prefer a fallback even for common fields: a starter should still read
///   well against a bare two-column list.
/// - Keep the tone warm and human — these are the app's first impression.
enum StarterTemplateCatalog {

    /// Category display order for grouped UI. Any category not listed here
    /// sorts to the end alphabetically.
    static let categoryOrder = ["Grow", "Connect", "Get paid", "Retain", "Announce", "Recruit"]

    /// Templates grouped by category, in `categoryOrder`.
    static var byCategory: [(category: String, templates: [StarterTemplate])] {
        let groups = Dictionary(grouping: all, by: \.category)
        return groups.keys
            .sorted { lhs, rhs in
                let l = categoryOrder.firstIndex(of: lhs) ?? Int.max
                let r = categoryOrder.firstIndex(of: rhs) ?? Int.max
                return l == r ? lhs < rhs : l < r
            }
            .map { ($0, groups[$0] ?? []) }
    }

    static let all: [StarterTemplate] = grow + connect + getPaid + retain + announce + recruit

    // MARK: - Grow

    private static let grow: [StarterTemplate] = [
        StarterTemplate(
            id: "sales-outreach",
            name: "Sales outreach",
            category: "Grow",
            systemImage: "sparkle.magnifyingglass",
            blurb: "A warm first-touch email to a prospect.",
            subject: "Quick idea for {{Company|your team}}",
            body: """
            Hi {{First Name|there}},

            I've been following {{Company|your company}} and had a thought about {{Product Name|your team's goals}} I wanted to share.

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

            Just floating this back to the top of your inbox — no pressure at all. If now isn't the right time for {{Company|your team}}, totally understand; just let me know and I'll check back later.

            If it is, here's the one thing I'd suggest as a next step: {{Next Step|a quick 15-minute call}}.

            Thanks!
            {{Sales Rep|Your name}}
            """
        ),
        StarterTemplate(
            id: "break-up",
            name: "Last check-in",
            category: "Grow",
            systemImage: "hand.wave",
            blurb: "A graceful final note that often gets the reply.",
            subject: "Should I close the loop, {{First Name|there}}?",
            body: """
            Hi {{First Name|there}},

            I've reached out a couple of times about {{Product Name|working together}} and haven't wanted to crowd your inbox, so this is my last note on it.

            If it's simply bad timing for {{Company|your team}}, say the word and I'll follow up next quarter instead. If it's not a fit at all, that's genuinely fine too — I'd rather know than keep guessing.

            Thanks for your time either way,
            {{Sales Rep|Your name}}
            """
        ),
        StarterTemplate(
            id: "referral-request",
            name: "Referral request",
            category: "Grow",
            systemImage: "person.2.badge.plus",
            blurb: "Ask a happy customer to point you to the right person.",
            subject: "Quick favor, {{First Name|there}}?",
            body: """
            Hi {{First Name|there}},

            Working with {{Company|your team}} has been a real pleasure, so I wanted to ask a small favor.

            Is there anyone in your network — a peer at another company, someone in {{Industry|your industry}} — who might get the same value out of {{Product Name|what we do}}? A quick introduction is all it would take, and I'll keep it brief and useful on my end.

            No worries at all if nobody comes to mind.

            Thank you,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "case-study",
            name: "Share a success story",
            category: "Grow",
            systemImage: "chart.line.uptrend.xyaxis",
            blurb: "Lead with proof from a similar customer.",
            subject: "How a team like {{Company|yours}} solved this",
            body: """
            Hi {{First Name|there}},

            I thought of {{Company|your team}} this week. We just wrapped up a project with another group in {{Industry|your industry}} facing the same pressure you're likely feeling — and the results were good enough that I wanted to pass along what worked.

            The short version: they cut the manual back-and-forth almost entirely, and the team stopped dreading the process.

            Want me to send the details, or walk you through it live in 15 minutes?

            Best,
            {{Sales Rep|Your name}}
            """
        ),
        StarterTemplate(
            id: "warm-intro",
            name: "Introduction",
            category: "Grow",
            systemImage: "hand.raised.fingers.spread",
            blurb: "Introduce yourself and what you do, briefly.",
            subject: "Hello from {{Sales Rep|our team}}",
            body: """
            Hi {{First Name|there}},

            I wanted to introduce myself properly rather than land in your inbox out of nowhere.

            I work with {{Industry|companies}} teams on {{Product Name|projects like yours}} — usually where the work is important but the process has grown messy. Sometimes that's a fit, sometimes it isn't.

            If you're open to it, I'd love to hear what {{Company|your team}} is focused on this year. If not, I'll leave you to it with no hard feelings.

            Best,
            {{Sales Rep|Your name}}
            {{Phone|}}
            """
        ),
        StarterTemplate(
            id: "trial-invite",
            name: "Free trial invite",
            category: "Grow",
            systemImage: "gift",
            blurb: "Invite someone to try it before committing.",
            subject: "Want to try {{Product Name|it}} first, {{First Name|there}}?",
            body: """
            Hi {{First Name|there}},

            Rather than talk about {{Product Name|what we do}}, I'd rather you just try it.

            I can set {{Company|your team}} up with full access, no commitment and nothing to cancel. If it earns its place, we can talk. If it doesn't, you've lost nothing but a few minutes.

            Want me to get that started?

            Best,
            {{Sales Rep|Your name}}
            """
        ),
        StarterTemplate(
            id: "quote-send",
            name: "Send a quote",
            category: "Grow",
            systemImage: "doc.text",
            blurb: "Deliver a quote with the numbers spelled out.",
            subject: "Your quote {{Quote Number|is ready}}",
            body: """
            Hi {{First Name|there}},

            Thanks for your time — here's the quote for {{Company|your team}} as promised.

            Quote: {{Quote Number|enclosed}}
            Prepared: {{Quote Date|today|date:MMMM d, yyyy}}
            Item: {{Product Name|as discussed}}
            Quantity: {{Quantity|as discussed}}
            Total: {{Amount|see attached|currency:USD}}

            The pricing holds for 30 days. If anything looks off or you'd like it structured differently, tell me and I'll rework it — that's not a problem at all.

            Best,
            {{Sales Rep|Your name}}
            """
        ),
        StarterTemplate(
            id: "quote-follow-up",
            name: "Quote follow-up",
            category: "Grow",
            systemImage: "doc.text.magnifyingglass",
            blurb: "Check in after sending pricing.",
            subject: "Any questions on quote {{Quote Number|we sent}}?",
            body: """
            Hi {{First Name|there}},

            Checking in on the quote I sent over for {{Product Name|the project}} — {{Amount|the figure we discussed|currency:USD}}.

            No rush at all. I mostly want to make sure nothing in it is confusing, and that you have what you need to take it to whoever else weighs in.

            Happy to jump on a quick call if that's easier than email.

            Best,
            {{Sales Rep|Your name}}
            """
        )
    ]

    // MARK: - Connect

    private static let connect: [StarterTemplate] = [
        StarterTemplate(
            id: "meeting-request",
            name: "Meeting request",
            category: "Connect",
            systemImage: "calendar.badge.plus",
            blurb: "Propose a time to talk.",
            subject: "Time to connect the week of {{Meeting Date|soon|date:MMMM d}}?",
            body: """
            Hi {{First Name|there}},

            I'd love to find 20–30 minutes to walk through how we could help {{Company|your team}}. Would sometime around {{Meeting Date|next week|date:EEEE, MMMM d}} work for you?

            If that's tricky, send me a couple of windows that suit you and I'll make one work.

            Looking forward to it,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "event-invite",
            name: "Event invitation",
            category: "Connect",
            systemImage: "party.popper",
            blurb: "Invite contacts to a webinar or event.",
            subject: "You're invited, {{First Name|there}}",
            body: """
            Hi {{First Name|there}},

            We're hosting something we think you'll enjoy, and we'd love for you and the {{Company|your}} team to join us on {{Meeting Date|the date below|date:EEEE, MMMM d}}.

            It's a relaxed, practical session — no hard sell, just useful ideas you can take back to work the same day.

            Save your spot by replying "count me in" and I'll send the details.

            Hope to see you there,
            {{Sales Rep|The team}}
            """
        ),
        StarterTemplate(
            id: "webinar-invite",
            name: "Webinar invite",
            category: "Connect",
            systemImage: "video",
            blurb: "Invite people to an online session.",
            subject: "30 minutes on {{Product Name|the topic}} — {{Meeting Date|soon|date:MMMM d}}",
            body: """
            Hi {{First Name|there}},

            We're running a short online session on {{Meeting Date|the date below|date:EEEE, MMMM d}}, and given your work at {{Company|your company}} I think it'll be time well spent.

            Half an hour, live, with plenty of room for questions. If you can't make it, register anyway and I'll send you the recording.

            Reply and I'll add you to the list.

            Best,
            {{Sales Rep|Your name}}
            """
        ),
        StarterTemplate(
            id: "conference-meetup",
            name: "Meet at an event",
            category: "Connect",
            systemImage: "figure.wave",
            blurb: "Arrange to meet up at a conference or trade show.",
            subject: "Will you be there, {{First Name|there}}?",
            body: """
            Hi {{First Name|there}},

            I'll be at the event on {{Meeting Date|the dates below|date:MMMM d}} and wondered whether anyone from {{Company|your team}} will be around.

            If so, I'd enjoy putting a face to the name — coffee, 20 minutes, nothing formal. I'm usually easiest to catch in the morning before the sessions start.

            Let me know and I'll find you.

            Best,
            {{Sales Rep|Your name}}
            """
        ),
        StarterTemplate(
            id: "thanks-after-meeting",
            name: "Thanks after a meeting",
            category: "Connect",
            systemImage: "hands.clap",
            blurb: "Follow up with a recap and next step.",
            subject: "Thanks for your time today",
            body: """
            Hi {{First Name|there}},

            Thank you for the conversation — it was genuinely useful to hear how {{Company|your team}} is approaching this.

            Here's what I took away as the next step: {{Next Step|I'll follow up with the details we discussed}}.

            If I've misremembered anything, correct me and I'll fix it on my end.

            Talk soon,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "reschedule",
            name: "Reschedule a meeting",
            category: "Connect",
            systemImage: "calendar.badge.exclamationmark",
            blurb: "Move a meeting without losing momentum.",
            subject: "Need to move our {{Meeting Date|meeting|date:MMMM d}} time",
            body: """
            Hi {{First Name|there}},

            My apologies — I need to move our time on {{Meeting Date|the date we set|date:EEEE, MMMM d}}. Entirely on me, and I'm sorry for the shuffle.

            Could any of these work instead? I'm flexible and happy to fit around your day:

            - Same time, later that week
            - Early morning, any day
            - Late afternoon, any day

            Send whichever suits and I'll lock it in.

            Thanks for your patience,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "meeting-confirm",
            name: "Confirm a meeting",
            category: "Connect",
            systemImage: "checkmark.circle",
            blurb: "Reconfirm the details the day before.",
            subject: "Confirming {{Meeting Date|our meeting|date:EEEE, MMMM d}}",
            body: """
            Hi {{First Name|there}},

            Just confirming our time on {{Meeting Date|the agreed date|date:EEEE, MMMM d}}. I'll call you on {{Phone|the number you shared}} unless you'd prefer a video link.

            Here's what I'd like to cover, so nothing is a surprise:

            - Where {{Company|your team}} is today
            - What "better" would look like
            - Whether we're a fit — honestly, either way

            See you then,
            {{Account Manager|Your name}}
            """
        )
    ]

    // MARK: - Get paid

    private static let getPaid: [StarterTemplate] = [
        StarterTemplate(
            id: "invoice-reminder",
            name: "Invoice reminder",
            category: "Get paid",
            systemImage: "doc.text.badge.clock",
            blurb: "A polite nudge on an outstanding invoice.",
            subject: "Invoice {{Invoice Number|reminder}} — due {{Due Date|soon|date:MMMM d, yyyy}}",
            body: """
            Hi {{First Name|there}},

            A quick, friendly reminder that invoice {{Invoice Number|from us}} for {{Amount|the balance due|currency:USD}} is due on {{Due Date|the date on the invoice|date:MMMM d, yyyy}}.

            If you've already sent payment, thank you — please disregard this note. If not, you can reply here with any questions and I'll help sort it out.

            Appreciate your business,
            {{Account Manager|Accounts team}}
            """
        ),
        StarterTemplate(
            id: "invoice-overdue",
            name: "Overdue notice",
            category: "Get paid",
            systemImage: "exclamationmark.circle",
            blurb: "Firm but courteous when payment has slipped.",
            subject: "Invoice {{Invoice Number|overdue}} — past due since {{Due Date|its due date|date:MMMM d}}",
            body: """
            Hi {{First Name|there}},

            Our records show invoice {{Invoice Number|from us}} for {{Amount|the outstanding balance|currency:USD}} is now past its due date of {{Due Date|the agreed date|date:MMMM d, yyyy}}.

            I know invoices slip through — it happens to all of us. If there's a hold-up on your end, or if you need it re-sent to a different address, just reply and I'll take care of it.

            If payment is already on its way, please ignore this note and thank you.

            Kind regards,
            {{Account Manager|Accounts team}}
            """
        ),
        StarterTemplate(
            id: "payment-thanks",
            name: "Payment received",
            category: "Get paid",
            systemImage: "checkmark.seal",
            blurb: "Confirm a payment and say thank you.",
            subject: "Payment received — thank you",
            body: """
            Hi {{First Name|there}},

            Confirming we've received payment of {{Amount|your payment|currency:USD}} against invoice {{Invoice Number|from us}}. Everything is settled — nothing further needed from you.

            Thank you for being straightforward to work with; it's noticed and appreciated.

            Best,
            {{Account Manager|Accounts team}}
            """
        ),
        StarterTemplate(
            id: "po-confirmation",
            name: "Order confirmation",
            category: "Get paid",
            systemImage: "shippingbox",
            blurb: "Acknowledge an order or purchase order.",
            subject: "We've got your order {{PO Number|— confirmed}}",
            body: """
            Hi {{First Name|there}},

            Thanks — your order is confirmed and in motion.

            Reference: {{PO Number|your purchase order}}
            Item: {{Product Name|as ordered}}
            Quantity: {{Quantity|as ordered}}
            Total: {{Amount|as quoted|currency:USD}}

            I'll be in touch as soon as there's an update. If anything above looks wrong, tell me now and it's easy to correct.

            Best,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "deposit-request",
            name: "Deposit request",
            category: "Get paid",
            systemImage: "creditcard",
            blurb: "Request a deposit to get work started.",
            subject: "Ready to start on {{Product Name|your project}}",
            body: """
            Hi {{First Name|there}},

            Good news — we're ready to begin on {{Product Name|the work we discussed}} for {{Company|your team}}.

            To get it scheduled, the last step is the deposit of {{Amount|the agreed amount|currency:USD}}, referenced against {{Quote Number|your quote}}. Once that's in, I'll confirm your dates straight away.

            Any questions about the terms, just ask.

            Best,
            {{Account Manager|Your name}}
            """
        )
    ]

    // MARK: - Retain

    private static let retain: [StarterTemplate] = [
        StarterTemplate(
            id: "renewal",
            name: "Renewal reminder",
            category: "Retain",
            systemImage: "arrow.triangle.2.circlepath",
            blurb: "Give customers a heads-up before renewal.",
            subject: "Your {{Product Name|subscription}} renews {{Renewal Date|soon|date:MMMM d, yyyy}}",
            body: """
            Hi {{First Name|there}},

            Just a heads-up that {{Company|your}} {{Product Name|plan}} is set to renew on {{Renewal Date|its renewal date|date:MMMM d, yyyy}} at {{Amount|the current rate|currency:USD}}.

            There's nothing you need to do to keep everything running. But if you'd like to review your plan or chat about what's next, I'm one reply away.

            Thanks for being with us,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "welcome-onboarding",
            name: "Welcome aboard",
            category: "Retain",
            systemImage: "sparkles",
            blurb: "Start a new customer off on the right foot.",
            subject: "Welcome aboard, {{First Name|there}}",
            body: """
            Hi {{First Name|there}},

            Delighted to have {{Company|you}} on board. My job from here is to make sure {{Product Name|this}} actually earns its keep for you.

            Here's what happens next: {{Next Step|I'll reach out to set up your first session}}.

            In the meantime, if anything at all is unclear, reply straight to this email. It comes to me, not a ticket queue.

            Welcome,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "check-in",
            name: "Customer check-in",
            category: "Retain",
            systemImage: "hand.thumbsup",
            blurb: "A no-agenda check-in with an existing customer.",
            subject: "How's it going, {{First Name|there}}?",
            body: """
            Hi {{First Name|there}},

            No agenda here — I just wanted to check in and see how things are going with {{Product Name|everything}} at {{Company|your end}}.

            Anything working especially well? Anything quietly annoying you that we could fix? I'd rather hear about the small stuff early than find out at renewal.

            Always good to hear from you,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "feedback-request",
            name: "Ask for feedback",
            category: "Retain",
            systemImage: "star.bubble",
            blurb: "Request a review or honest feedback.",
            subject: "Two minutes of your honesty, {{First Name|there}}?",
            body: """
            Hi {{First Name|there}},

            Would you be willing to tell me — plainly — how {{Product Name|this}} is working for {{Company|your team}}?

            I'm after the honest version, including anything that's fallen short. Two or three sentences is plenty, and it genuinely shapes what we do next.

            Thanks in advance,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "win-back",
            name: "Win back a lapsed customer",
            category: "Retain",
            systemImage: "arrow.counterclockwise.circle",
            blurb: "Reconnect with someone who drifted away.",
            subject: "It's been a while, {{First Name|there}}",
            body: """
            Hi {{First Name|there}},

            It's been a while since {{Company|your team}} worked with us, and I've been meaning to reach out — not with a pitch, but with an honest question.

            Did we fall short somewhere? If so, I'd like to know; that feedback is worth more to me than the business.

            And if it was simply a change in priorities, no explanation needed. A fair bit has improved since then, so if the timing is better now, I'd be glad to show you.

            Best,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "service-reminder",
            name: "Service reminder",
            category: "Retain",
            systemImage: "wrench.and.screwdriver",
            blurb: "Remind customers that maintenance is due.",
            subject: "{{Product Name|Your service}} is due for a check",
            body: """
            Hi {{First Name|there}},

            Our records show {{Product Name|your equipment}} at {{Company|your site}} is due for its scheduled service around {{Due Date|now|date:MMMM yyyy}}.

            Regular servicing keeps small issues small, so I'd rather book you in early than have you call when something's already stopped.

            Reply with a couple of dates that suit and I'll arrange it.

            Best,
            {{Account Manager|Your name}}
            """
        )
    ]

    // MARK: - Announce

    private static let announce: [StarterTemplate] = [
        StarterTemplate(
            id: "product-launch",
            name: "Product announcement",
            category: "Announce",
            systemImage: "megaphone",
            blurb: "Tell customers about something new.",
            subject: "Something new for {{Company|you}}",
            body: """
            Hi {{First Name|there}},

            We've built something I think {{Company|your team}} will actually use, so I wanted you to hear it from me rather than from a newsletter.

            The short version: {{Product Name|the new release}} takes the part of the process everyone complains about and makes it considerably less painful.

            Want a quick look? Reply and I'll walk you through it in ten minutes.

            Best,
            {{Sales Rep|Your name}}
            """
        ),
        StarterTemplate(
            id: "price-change",
            name: "Price change notice",
            category: "Announce",
            systemImage: "tag",
            blurb: "Communicate a price change clearly and early.",
            subject: "A heads-up about pricing, effective {{Renewal Date|soon|date:MMMM d, yyyy}}",
            body: """
            Hi {{First Name|there}},

            I want to give you plenty of notice: our pricing for {{Product Name|your plan}} changes on {{Renewal Date|the date below|date:MMMM d, yyyy}}.

            For {{Company|your account}}, the new rate will be {{Amount|shown on your next invoice|currency:USD}}. Nothing changes before that date, and nothing about your service changes at all.

            I'd rather explain the reasoning directly than have you read it in fine print — so if you'd like that conversation, just reply.

            Thank you for your continued business,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "new-contact",
            name: "New point of contact",
            category: "Announce",
            systemImage: "person.crop.circle.badge.checkmark",
            blurb: "Introduce the new person looking after an account.",
            subject: "A quick introduction for {{Company|your account}}",
            body: """
            Hi {{First Name|there}},

            A small change worth knowing about: I'll be looking after {{Company|your account}} from now on, and I'm glad to be doing it.

            Nothing changes in how things run — same team, same commitments. You just have a different name to email, and that name is mine.

            I'd welcome 15 minutes to hear how things have gone so far, whenever suits.

            Best,
            {{Account Manager|Your name}}
            {{Phone|}}
            """
        ),
        StarterTemplate(
            id: "holiday-hours",
            name: "Holiday hours",
            category: "Announce",
            systemImage: "calendar",
            blurb: "Let customers know about closures or reduced hours.",
            subject: "Our hours over the holidays",
            body: """
            Hi {{First Name|there}},

            A quick note so nothing catches you out: our office hours change over the holiday period, and responses may be slower than usual.

            If you need anything time-sensitive for {{Company|your team}}, send it my way before {{Due Date|the break|date:MMMM d}} and I'll make sure it's handled.

            Wishing you a good break,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "policy-update",
            name: "Policy update",
            category: "Announce",
            systemImage: "doc.badge.gearshape",
            blurb: "Notify contacts of a terms or policy change.",
            subject: "A small change to our terms, effective {{Due Date|soon|date:MMMM d, yyyy}}",
            body: """
            Hi {{First Name|there}},

            We're updating our terms on {{Due Date|the date below|date:MMMM d, yyyy}}, and I'd rather tell you plainly than bury it in an attachment.

            Nothing changes about what {{Company|your team}} pays or receives. The update mostly clarifies language that was vaguer than it should have been.

            If you'd like the specifics or have questions, reply and I'll answer them directly.

            Best,
            {{Account Manager|Your name}}
            """
        )
    ]

    // MARK: - Recruit

    private static let recruit: [StarterTemplate] = [
        StarterTemplate(
            id: "candidate-outreach",
            name: "Candidate outreach",
            category: "Recruit",
            systemImage: "person.badge.plus",
            blurb: "Approach someone about a role.",
            subject: "A role that might interest you, {{First Name|there}}",
            body: """
            Hi {{First Name|there}},

            Your work at {{Company|your current company}} caught my attention — particularly your background in {{Job Title|your field}}.

            We're hiring for a role I think you'd find genuinely interesting, and I'd rather have a real conversation about it than send you a job description.

            Open to a short, no-obligation chat? If you're happy where you are, I completely understand — I'll take you at your word and won't keep asking.

            Best,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "interview-invite",
            name: "Interview invitation",
            category: "Recruit",
            systemImage: "person.crop.rectangle.stack",
            blurb: "Invite a candidate to interview.",
            subject: "Interview invitation — {{Meeting Date|scheduling|date:MMMM d}}",
            body: """
            Hi {{First Name|there}},

            Thank you for applying — we'd like to meet you properly.

            I'd like to arrange a conversation around {{Meeting Date|next week|date:EEEE, MMMM d}}. It'll be about 45 minutes, informal, and mostly about your experience and what you're looking for next.

            Reply with a few times that work and I'll confirm. If you need anything to make the conversation accessible or comfortable, just say so.

            Looking forward to it,
            {{Account Manager|Your name}}
            """
        ),
        StarterTemplate(
            id: "candidate-update",
            name: "Candidate update",
            category: "Recruit",
            systemImage: "clock.arrow.circlepath",
            blurb: "Keep applicants informed while they wait.",
            subject: "An update on your application",
            body: """
            Hi {{First Name|there}},

            A quick update so you're not left wondering: we're still working through applications and haven't made a decision yet.

            You should hear from us by {{Due Date|the end of the process|date:MMMM d}}. I know waiting is the worst part, and I'd rather tell you where things stand than leave you guessing.

            Thanks for your patience,
            {{Account Manager|Your name}}
            """
        )
    ]
}
