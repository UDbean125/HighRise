import Foundation

/// The line of business a starter was written for.
///
/// The twelve sectors that drive the North American economy, aligned with
/// NAICS groupings and ordered by economic output and employment. Most
/// starters are deliberately industry-neutral (an empty set — they read well
/// anywhere); the tagged ones speak an industry's own working vocabulary and
/// get their own "Made for …" section when that industry is chosen, with the
/// task groups (Grow, Connect, Get paid, …) as subsections inside it.
enum TemplateIndustry: String, CaseIterable, Identifiable {
    case finance = "Finance, Insurance & Real Estate"
    case professionalServices = "Professional & Business Services"
    case manufacturing = "Manufacturing"
    case healthcare = "Healthcare & Social Assistance"
    case technology = "Information & Technology"
    case wholesale = "Wholesale Trade"
    case retail = "Retail Trade"
    case education = "Educational Services"
    case hospitality = "Leisure & Hospitality"
    case construction = "Construction"
    case transportation = "Transportation & Warehousing"
    case naturalResources = "Natural Resources & Mining"

    var id: String { rawValue }

    /// SF Symbol for the sector, shown on the "Made for …" section header.
    var systemImage: String {
        switch self {
        case .finance:              return "building.columns"
        case .professionalServices: return "briefcase"
        case .manufacturing:        return "gearshape.2"
        case .healthcare:           return "cross.case"
        case .technology:           return "cpu"
        case .wholesale:            return "shippingbox.and.arrow.backward"
        case .retail:               return "cart"
        case .education:            return "graduationcap"
        case .hospitality:          return "fork.knife"
        case .construction:         return "hammer"
        case .transportation:       return "truck.box"
        case .naturalResources:     return "leaf"
        }
    }
}

/// Who a starter is addressed to. An empty set on a template means it suits
/// any reader (a holiday-hours note, a reschedule).
enum TemplateAudience: String, CaseIterable, Identifiable {
    case prospects = "Prospects & Leads"
    case customers = "Customers & Clients"
    case partners = "Partners & Vendors"
    case candidates = "Job Candidates"

    var id: String { rawValue }
}

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
    /// Who this starter is addressed to; empty = suits any audience.
    var audiences: Set<TemplateAudience> = []
    /// Industries whose vocabulary this starter speaks; empty = neutral,
    /// shown under every industry.
    var industries: Set<TemplateIndustry> = []

    var emailTemplate: EmailTemplate {
        EmailTemplate(subject: subject, body: body, format: format)
    }

    /// Whether this starter belongs in the gallery when `industry` is the
    /// active filter (nil = no filter). Neutral starters fit everywhere.
    func fits(industry: TemplateIndustry?) -> Bool {
        guard let industry else { return true }
        return industries.isEmpty || industries.contains(industry)
    }

    /// Whether this starter belongs in the gallery when `audience` is the
    /// active filter (nil = no filter). Untagged starters fit everyone.
    func fits(audience: TemplateAudience?) -> Bool {
        guard let audience else { return true }
        return audiences.isEmpty || audiences.contains(audience)
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

    /// `byCategory` narrowed by the gallery's industry/audience dropdowns.
    /// Industry-tailored starters lead their category when an industry is
    /// chosen; neutral starters stay (they fit everywhere), so a filter
    /// combination never empties the whole gallery. Empty groups are dropped.
    static func byCategory(industry: TemplateIndustry?,
                           audience: TemplateAudience?) -> [(category: String, templates: [StarterTemplate])] {
        byCategory.compactMap { group in
            var matching = group.templates.filter {
                $0.fits(industry: industry) && $0.fits(audience: audience)
            }
            guard !matching.isEmpty else { return nil }
            if let industry {
                matching = matching.filter { $0.industries.contains(industry) }
                    + matching.filter { !$0.industries.contains(industry) }
            }
            return (group.category, matching)
        }
    }

    /// One top-level band of the gallery: templates written *for* the chosen
    /// industry, or the neutral ones that work anywhere. Each band keeps the
    /// task groups (Grow, Connect, …) as its subsections, so choosing an
    /// industry re-files the catalog rather than replacing it.
    struct Section: Identifiable {
        /// Nil for the "works for any industry" band.
        let industry: TemplateIndustry?
        let title: String
        let systemImage: String
        let groups: [(category: String, templates: [StarterTemplate])]

        var id: String { title }
        var count: Int { groups.reduce(0) { $0 + $1.templates.count } }
    }

    /// The gallery's sections for the current dropdown state.
    ///
    /// With no industry chosen this is a single unlabeled band (the plain
    /// category-grouped catalog). With one chosen it's two: "Made for
    /// <industry>" first, then "Works for any industry" — each internally
    /// grouped by task group. Empty bands are omitted, and because neutral
    /// starters fit every industry the gallery is never empty.
    static func sections(industry: TemplateIndustry?,
                         audience: TemplateAudience?) -> [Section] {
        func grouped(_ templates: [StarterTemplate]) -> [(category: String, templates: [StarterTemplate])] {
            let byName = Dictionary(grouping: templates, by: \.category)
            return byCategory
                .compactMap { group in
                    guard let matching = byName[group.category], !matching.isEmpty else { return nil }
                    return (group.category, matching)
                }
        }

        let eligible = all.filter { $0.fits(audience: audience) }
        guard let industry else {
            let groups = grouped(eligible)
            return groups.isEmpty ? [] : [Section(industry: nil, title: "All templates",
                                                  systemImage: "square.grid.2x2", groups: groups)]
        }

        let tailored = grouped(eligible.filter { $0.industries.contains(industry) })
        let neutral = grouped(eligible.filter { $0.industries.isEmpty })
        var sections: [Section] = []
        if !tailored.isEmpty {
            sections.append(Section(industry: industry,
                                    title: "Made for \(industry.rawValue)",
                                    systemImage: industry.systemImage, groups: tailored))
        }
        if !neutral.isEmpty {
            sections.append(Section(industry: nil, title: "Works for any industry",
                                    systemImage: "square.grid.2x2", groups: neutral))
        }
        return sections
    }

    /// How many starters are written specifically for `industry` — shown in
    /// the dropdown so the user can see where the depth is.
    static func tailoredCount(for industry: TemplateIndustry) -> Int {
        all.filter { $0.industries.contains(industry) }.count
    }

    /// How many are addressed to `audience`, counting the universal ones —
    /// shown in the audience dropdown for the same reason.
    static func count(for audience: TemplateAudience) -> Int {
        all.filter { $0.fits(audience: audience) }.count
    }

    /// Free-text search across a starter's user-visible text plus its
    /// industry and audience labels, so typing "driver" or "construction"
    /// finds the right card even when the word isn't in its name.
    static func matches(_ template: StarterTemplate, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        // Every whitespace-separated word must appear somewhere, so
        // "retail hiring" narrows rather than widens.
        let haystack = ([template.name, template.blurb, template.category,
                         template.subject, template.body]
                        + template.industries.map(\.rawValue)
                        + template.audiences.map(\.rawValue))
            .joined(separator: " ")
        return trimmed.split(whereSeparator: \.isWhitespace).allSatisfy {
            haystack.localizedCaseInsensitiveContains($0)
        }
    }

    static let all: [StarterTemplate] = grow + connect + getPaid + retain + announce + recruit + industryTailored

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
            """,
            audiences: [.prospects]
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
            """,
            audiences: [.prospects]
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
            """,
            audiences: [.prospects]
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
            """,
            audiences: [.customers]
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
            """,
            audiences: [.prospects]
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
            """,
            audiences: [.prospects]
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
            """,
            audiences: [.prospects]
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
            """,
            audiences: [.prospects, .customers]
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
            """,
            audiences: [.prospects, .customers]
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
            """,
            audiences: [.prospects]
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
            """,
            audiences: [.prospects, .customers]
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
            """,
            audiences: [.prospects, .customers]
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
            """,
            audiences: [.prospects, .partners]
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
            systemImage: "doc.badge.clock",
            blurb: "A polite nudge on an outstanding invoice.",
            subject: "Invoice {{Invoice Number|reminder}} — due {{Due Date|soon|date:MMMM d, yyyy}}",
            body: """
            Hi {{First Name|there}},

            A quick, friendly reminder that invoice {{Invoice Number|from us}} for {{Amount|the balance due|currency:USD}} is due on {{Due Date|the date on the invoice|date:MMMM d, yyyy}}.

            If you've already sent payment, thank you — please disregard this note. If not, you can reply here with any questions and I'll help sort it out.

            Appreciate your business,
            {{Account Manager|Accounts team}}
            """,
            audiences: [.customers]
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
            """,
            audiences: [.customers]
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
            """,
            audiences: [.customers]
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
            """,
            audiences: [.customers]
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
            """,
            audiences: [.customers]
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
            """,
            audiences: [.customers]
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
            """,
            audiences: [.customers]
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
            """,
            audiences: [.customers]
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
            """,
            audiences: [.customers]
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
            """,
            audiences: [.customers]
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
            """,
            audiences: [.customers]
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
            """,
            audiences: [.prospects, .customers]
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
            """,
            audiences: [.customers]
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
            """,
            audiences: [.customers, .partners]
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
            """,
            audiences: [.customers, .partners]
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
            """,
            audiences: [.candidates]
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
            """,
            audiences: [.candidates]
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
            """,
            audiences: [.candidates]
        )
    ]

    // MARK: - Industry-tailored
    //
    // One starter per `TemplateIndustry`, written in that industry's own
    // vocabulary. These float to the top of their category when the gallery's
    // industry dropdown is set; the neutral starters above remain visible for
    // every industry. Grouping is by `category`, so these slot into the
    // existing sections rather than forming their own.

    private static let industryTailored: [StarterTemplate] = [
        StarterTemplate(
            id: "finance-policy-renewal-review",
            name: "Policy renewal review",
            category: "Retain",
            systemImage: "checkmark.shield",
            blurb: "Open the renewal conversation before the terms are set.",
            subject: "{{Policy Number|Your policy}} renews {{Renewal Date|soon|date:MMMM d, yyyy}}",
            body: """
            Hi {{First Name|there}},

            Your {{Product Name|commercial package}} policy — {{Policy Number|the one we placed for you}} — renews on {{Renewal Date|its anniversary date|date:MMMM d, yyyy}}, and I'd like to look at it properly before I take it back to the market.

            What helps most is knowing what changed at {{Company|your operation}} this year: payroll, vehicles, headcount, new locations, work you've taken on that you weren't doing last year. Underwriters price what they know, and the surprises always turn up after binding.

            The other thing worth telling me is where the coverage felt thin. If a limit or a deductible stung at claim time, that's the part to rework rather than roll over.

            Today's premium is {{Amount|the figure on your declarations page|currency:USD}}. I'll bring alternatives to sit alongside the incumbent's terms, not just the renewal on its own.

            If you'd rather I renew it as it stands, say so and it's done — no meeting needed.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.customers],
            industries: [.finance]
        ),
        StarterTemplate(
            id: "finance-closing-timeline",
            name: "Closing week timeline",
            category: "Connect",
            systemImage: "house",
            blurb: "Walk a buyer through the final week before closing.",
            subject: "Closing on {{Property Address|your property}} — what happens this week",
            body: """
            Hi {{First Name|there}},

            We're a week out from closing on {{Property Address|the property}}, so here's the whole run of it in one place.

            Between now and {{Closing Date|closing day|date:EEEE, MMMM d}}: the lender clears the file, title prepares the settlement statement, and I send you the figures to look over as soon as I have them. Nothing needed from you yet.

            Two days out: the final walkthrough. That's the moment to flag anything that isn't as agreed — not the morning of.

            On the day: photo ID, and funds wired in advance. Before you send a dollar, call {{Escrow Officer|the escrow officer}} on a number you already have and confirm the wire instructions out loud. Wire fraud is common in this business and it does not get undone.

            If any of this is unclear, or the timing stops working, call me rather than sitting on it. That's genuinely what I'm here for.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.customers],
            industries: [.finance]
        ),
        StarterTemplate(
            id: "finance-off-market-deal",
            name: "Off-market opportunity",
            category: "Grow",
            systemImage: "key",
            blurb: "Bring an investor a deal before it reaches the market.",
            subject: "An off-market deal in {{City|your market}}",
            body: """
            Hi {{First Name|there}},

            Something came across my desk in {{City|your market}} that looks like the profile {{Company|your group}} buys, and it hasn't hit the market yet.

            Asset: {{Product Name|stabilized multifamily}}
            Units: {{Quantity|on request}}
            Asking: {{Amount|price on request|currency:USD}}
            Cap rate: {{Cap Rate|in line with recent comps}}

            The timing is driven by {{Loan Maturity|a near-term debt maturity}} on the seller's side, which is the only reason it's quiet rather than marketed.

            Say the word and I'll send the rent roll and the trailing twelve. If it doesn't survive your underwriting, tell me plainly — that's more useful to me than a polite maybe.

            And if it's the wrong box entirely — wrong asset class, wrong basis, wrong year — say so and I'll aim better next time.

            Best,
            {{Sales Rep|Your name}}
            """,
            audiences: [.prospects, .customers],
            industries: [.finance]
        ),
        StarterTemplate(
            id: "professional-engagement-letter",
            name: "Engagement letter",
            category: "Grow",
            systemImage: "square.and.pencil",
            blurb: "Send the engagement letter over for signature.",
            subject: "Engagement letter for {{Company|your organization}} — ready to sign",
            body: """
            Hi {{First Name|there}},

            Thanks for the conversation — here's the engagement letter for {{Company|your organization}}, ready for signature.

            Scope: {{Product Name|the work we discussed}}
            Fees: {{Amount|as set out in the letter|currency:USD}}
            Prepared: {{Quote Date|today|date:MMMM d, yyyy}}
            Start: {{Meeting Date|within a week of signature|date:MMMM d, yyyy}}

            The scope section is the part worth reading closely. It's what we hold ourselves to, and anything falling outside it we'd come back to you about before doing the work.

            If a line doesn't match your understanding, tell me before you sign rather than after — redrafting now is a five-minute job.

            No rush at my end if you need to run it past anyone else.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.prospects, .customers],
            industries: [.professionalServices]
        ),
        StarterTemplate(
            id: "professional-scope-change",
            name: "Scope change notice",
            category: "Get paid",
            systemImage: "arrow.triangle.branch",
            blurb: "Flag out-of-scope work before it lands on an invoice.",
            subject: "Extra work for {{Company|your organization}} — your call before we start",
            body: """
            Hi {{First Name|there}},

            Something has come up on the work we're doing for {{Company|your team}} that sits outside the scope we agreed, and I'd rather raise it now than have it turn up on an invoice.

            What's changed: {{Scope Change|the additional work we talked through}}
            Estimated additional fee: {{Amount|a figure I'll confirm before anything starts|currency:USD}}
            Effect on the timetable: {{Timetable Impact|none — we'd still expect to hit the date in the engagement letter}}

            Nothing has started, and nothing will until you say so. If you'd rather we leave it out and hold to the original scope, that's a perfectly reasonable answer and I'll note it on the file.

            A reply saying "go ahead" is all I need.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.customers],
            industries: [.professionalServices]
        ),
        StarterTemplate(
            id: "professional-deliverable-handoff",
            name: "Deliverables issued",
            category: "Retain",
            systemImage: "doc.richtext",
            blurb: "Hand over the finished work and say what happens next.",
            subject: "{{Deliverable|Your final report}} for {{Company|your engagement}}",
            body: """
            Hi {{First Name|there}},

            The {{Deliverable|final report}} for {{Company|your engagement}} is attached. It's been through our internal review, so this is the issued version rather than a draft.

            Worth reading first: {{Key Finding|the summary on page one, which drives everything that follows}}.

            If anything needs correcting, send your comments by {{Due Date|the end of next week|date:MMMM d}} and we'll reissue at no charge.

            We'll keep the working papers on file, so if a question comes up in six months nobody has to go digging.

            Next step from here: {{Next Step|a twenty-minute call to walk through it, if that's easier than reading}}.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.customers],
            industries: [.professionalServices]
        ),
        StarterTemplate(
            id: "manufacturing-rfq-quote",
            name: "RFQ turnaround",
            category: "Grow",
            systemImage: "gearshape.2",
            blurb: "Return pricing, tooling and lead time on an incoming RFQ.",
            subject: "Quote {{Quote Number|for your RFQ}} — {{Part Number|your part}}",
            body: """
            Hi {{First Name|there}},

            Thanks for the RFQ. Here's our number on {{Part Number|the part}}, quoted against {{Drawing Revision|the print you sent}}.

            Quantity: {{Quantity|per your RFQ}}
            Unit price: {{Amount|see the attached quote|currency:USD}}
            Tooling: {{Tooling Cost|quoted separately|currency:USD}}
            Lead time: {{Lead Time|as noted on the quote}}, from receipt of PO and approved print

            Material pricing holds for 30 days — after that I'd want to re-check the mill before we commit to it.

            If the quantity or the tolerances are still moving, send me the change and I'll requote. I'd rather price the real job than the first draft.

            Best,
            {{Sales Rep|Your name}}
            """,
            audiences: [.prospects, .customers],
            industries: [.manufacturing]
        ),
        StarterTemplate(
            id: "manufacturing-first-article",
            name: "First article sign-off",
            category: "Retain",
            systemImage: "ruler",
            blurb: "Send the first-article report and ask for approval before the lot runs.",
            subject: "First article on {{Part Number|your part}} — ready for your sign-off",
            body: """
            Hi {{First Name|there}},

            The first article off the tool for {{Part Number|the part}} is finished, and the dimensional report is attached.

            Everything measures in tolerance to {{Drawing Revision|the print we're building to}}. Two features are flagged on the report — both are inside print, but close enough to the limit that I'd rather you heard it from me.

            We're holding the balance of the lot until you sign off. Once your approval is back we release the rest and still make {{Ship Week|the ship week we committed to}}.

            If you'd sooner have samples in your hands before you approve, say so and they go out today.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.customers],
            industries: [.manufacturing]
        ),
        StarterTemplate(
            id: "manufacturing-lead-time-change",
            name: "Lead time change",
            category: "Announce",
            systemImage: "calendar.badge.clock",
            blurb: "Warn customers a lead time is moving before a ship date slips.",
            subject: "Lead time change on {{Product Name|your parts}}",
            body: """
            Hi {{First Name|there}},

            I'd rather you heard this early enough to plan around it: our lead time on {{Product Name|the parts we run for you}} moves out to {{Lead Time|the revised lead time}} for anything released after {{Due Date|the changeover date|date:MMMM d, yyyy}}.

            The cause is upstream — mill allocation on raw material, not capacity on our floor. The machines are running; the bar simply takes longer to land.

            Anything already on PO {{PO Number|with us}} keeps the ship week we committed to. We're not re-dating work we've already promised.

            If you have releases coming for {{Company|your plant}}, get them to me before that date and I'll book them at the current lead time.

            And if a date is going to hurt a build on your line, call me. We'd sooner look at expediting or splitting a shipment than have you find out at the dock.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.customers, .partners],
            industries: [.manufacturing]
        ),
        StarterTemplate(
            id: "healthcare-intake-paperwork",
            name: "New patient paperwork",
            category: "Connect",
            systemImage: "doc.on.clipboard",
            blurb: "Send new patients their forms before a first appointment.",
            subject: "Before your visit on {{Meeting Date|the day we booked|date:EEEE, MMMM d}}",
            body: """
            Hi {{First Name|there}},

            We have you booked in on {{Meeting Date|the day we agreed|date:EEEE, MMMM d}}, and there's a little paperwork to get out of the way first.

            Please bring, or send back ahead of time: your completed intake and consent forms, a photo ID, and your insurance card. If you'd rather fill the forms in here, come about fifteen minutes early and we'll get you settled at the desk.

            If anything on the forms is unclear, leave it blank and we'll go through it together when you arrive. Please don't write anything about your health in a reply to this email — the forms are the safer place for it.

            And if the time no longer suits, call {{Phone|the office}} and we'll move it. No trouble at all.

            See you soon,
            {{Account Manager|The front desk team}}
            """,
            audiences: [.customers],
            industries: [.healthcare]
        ),
        StarterTemplate(
            id: "healthcare-benefits-verification",
            name: "Benefits verification",
            category: "Get paid",
            systemImage: "checkmark.shield",
            blurb: "Confirm insurance details before a scheduled visit.",
            subject: "Confirming your coverage before {{Meeting Date|your visit|date:MMMM d}}",
            body: """
            Hi {{First Name|there}},

            Ahead of your visit on {{Meeting Date|the scheduled day|date:EEEE, MMMM d}}, we run a benefits check with {{Insurance Plan|your plan}} so there's nothing unexpected waiting at the desk.

            For that we need the current details on file: the member ID from your card, the group number, and the policy holder's name if it isn't you. If nothing has changed since your last visit, reply "no change" and we'll run it as it stands.

            Based on what we hold now, your share on the day comes to {{Amount|whatever your plan sets|currency:USD}}. We'll confirm the figure as soon as the plan comes back to us.

            If coverage has lapsed, or you'd rather be seen as a self-pay patient, say so and we'll agree the cost before you come in rather than after.

            Thank you,
            {{Account Manager|The billing team}}
            """,
            audiences: [.customers],
            industries: [.healthcare]
        ),
        StarterTemplate(
            id: "healthcare-care-plan-review",
            name: "Care plan review",
            category: "Retain",
            systemImage: "calendar.badge.clock",
            blurb: "Arrange a periodic review of a client's care arrangements.",
            subject: "Time to review the care plan, {{First Name|there}}",
            body: """
            Hi {{First Name|there}},

            We're due to sit down and go back over the plan we set up together. These reviews come round every {{Review Interval|few months}}, and yours is due around {{Renewal Date|now|date:MMMM yyyy}}.

            It's a practical conversation more than anything: the visit schedule, the hours currently in place, who the named contacts are, and whether the arrangement still fits how the week actually runs.

            We'll keep anything to do with care itself for the meeting rather than email — in person or by phone, whichever you prefer.

            Would {{Meeting Date|sometime in the next couple of weeks|date:EEEE, MMMM d}} suit, or would another day be easier? If a family member should be there too, send me their name and I'll include them.

            If the timing is wrong altogether, just say so and we'll leave it a while.

            Warm regards,
            {{Account Manager|Your care coordinator}}
            """,
            audiences: [.customers],
            industries: [.healthcare]
        ),
        StarterTemplate(
            id: "technology-api-deprecation",
            name: "API deprecation notice",
            category: "Announce",
            systemImage: "chevron.left.forwardslash.chevron.right",
            blurb: "Give developers early warning that an endpoint or version is going away.",
            subject: "{{API Version|Our current API}} retires on {{Due Date|the date inside|date:MMMM d, yyyy}}",
            body: """
            Hi {{First Name|there}},

            We're retiring {{API Version|the current version of our API}} on {{Due Date|the date in our changelog|date:MMMM d, yyyy}}, and I'd rather you heard it from me than found a 410 in your logs.

            What it means for {{Company|your team}}: the old endpoints keep answering until that date, then stop. The replacement is live now, and the field mapping is short — most integrations are a day's work, not a project.

            Everything you need is in {{Migration Guide|the migration guide linked from our changelog}}.

            If your release calendar is already full, say so and we'll look at an extended window for {{Company|your account}}. We'd sooner move the date than break your integration.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.customers, .partners],
            industries: [.technology]
        ),
        StarterTemplate(
            id: "technology-seat-true-up",
            name: "Seat true-up",
            category: "Retain",
            systemImage: "person.3",
            blurb: "Review license counts with a customer before the subscription auto-renews.",
            subject: "Seats and renewal for {{Company|your team}} — {{Renewal Date|coming up|date:MMMM d, yyyy}}",
            body: """
            Hi {{First Name|there}},

            Your {{Product Name|subscription}} renews on {{Renewal Date|its renewal date|date:MMMM d, yyyy}}, so here's where {{Company|your team}} stands on seats while there's still time to change it.

            Licensed seats: {{Quantity|the count on your current plan}}
            Active in the last 90 days: {{Active Seats|we can pull this for you}}
            Renewal at the current count: {{Amount|the figure on your last invoice|currency:USD}}

            If some of those seats belong to people who have moved on, tell me and we'll take them off rather than quietly bill for them. If you need more, adding them mid-term is prorated.

            Nothing to do if the numbers look right.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.customers],
            industries: [.technology]
        ),
        StarterTemplate(
            id: "technology-incident-follow-up",
            name: "Incident follow-up",
            category: "Connect",
            systemImage: "exclamationmark.triangle",
            blurb: "Explain what went wrong after an outage and offer a real conversation.",
            subject: "What happened on {{Incident Date|the day of the outage|date:MMMM d}}, and what we changed",
            body: """
            Hi {{First Name|there}},

            I want to close this out properly rather than leave you with a status page that has gone green and nothing else.

            {{Product Name|The service}} was degraded on {{Incident Date|the day in question|date:EEEE, MMMM d}} for {{Downtime|the window shown on our status page}}. The cause was on our side: {{Root Cause|a change we shipped that our checks did not catch before it reached production}}.

            What has changed since: {{Fix Shipped|the fix is deployed, and we've added the alert that should have caught this first}}.

            If this cost {{Company|your team}} real time, I'd rather hear it directly than read it later. Reply here, or send me two windows and I'll call you on {{Phone|the number we have for you}}.

            Sorry for the trouble,
            {{Account Manager|Your name}}
            """,
            audiences: [.customers],
            industries: [.technology]
        ),
        StarterTemplate(
            id: "wholesale-volume-tier",
            name: "Next price break",
            category: "Grow",
            systemImage: "chart.bar",
            blurb: "Show an account what fuller drops would save them.",
            subject: "{{Company|Your team}} is one tier off a better price",
            body: """
            Hi {{First Name|there}},

            I went back through {{Company|your account}}'s order history this week and something stood out.

            You're buying {{Product Name|your usual line}} in lots of {{Quantity|half a pallet}}, which sits just under our next volume tier. Consolidating the same annual volume into fewer, fuller drops would take {{Discount|a few points}} off the case price and clear the freight-prepaid minimum, so the landed cost comes down twice over.

            Nothing else changes — same specification, same delivery points, same payment terms. Only the size and spacing of the drops.

            If it's useful, I'll price your last twelve months both ways and send the comparison. And if your racking simply won't take a full pallet, say so and I'll leave it there.

            Best,
            {{Sales Rep|Your name}}
            """,
            audiences: [.customers],
            industries: [.wholesale]
        ),
        StarterTemplate(
            id: "wholesale-price-list",
            name: "New price list",
            category: "Announce",
            systemImage: "list.bullet.rectangle",
            blurb: "Send the new price list before it takes effect.",
            subject: "New price list, effective {{Renewal Date|next quarter|date:MMMM d, yyyy}}",
            body: """
            Hi {{First Name|there}},

            Our new price list takes effect on {{Renewal Date|the date shown on the list|date:MMMM d, yyyy}}, and I'd rather you saw it now than found it on an invoice.

            Most of the list is unchanged. The movement is on {{Product Name|the imported lines}}, where supplier and freight costs have run ahead of the last revision. We've absorbed what we could and passed on the rest.

            Item codes, case packs and minimum order quantities all stay as they are. Only the price column moves.

            Anything shipped before {{Renewal Date|that date|date:MMMM d}} bills at current list, so if {{Company|your team}} had a top-up planned, it's worth bringing forward.

            Send me the lines you buy most and I'll price them old and new, side by side, so nothing catches you out.

            Kind regards,
            {{Account Manager|Your name}}
            """,
            audiences: [.customers, .partners],
            industries: [.wholesale]
        ),
        StarterTemplate(
            id: "wholesale-restock-due",
            name: "Restock reminder",
            category: "Retain",
            systemImage: "archivebox",
            blurb: "Nudge a buyer whose stock is due to run down.",
            subject: "Due a restock on {{Product Name|your usual lines}}?",
            body: """
            Hi {{First Name|there}},

            Your last delivery of {{Product Name|your usual lines}} went out around {{Last Order Date|six weeks ago|date:MMMM d}}, and going by how quickly {{Company|your team}} normally works through it, you'll be running low about now.

            Lead time on that line is currently {{Lead Time|around two weeks}}, so if you want stock on the shelf before month end, this is the week to release the order.

            I can repeat the last one exactly — same item codes, same case pack, same quantity of {{Quantity|what you took last time}}, same delivery point — or adjust it if your usage has shifted. A reply with a PO number is enough.

            And if you're sitting on plenty, or the line has moved elsewhere, tell me straight and I'll stop the reminders.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.customers],
            industries: [.wholesale]
        ),
        StarterTemplate(
            id: "retail-abandoned-cart",
            name: "Left in your cart",
            category: "Grow",
            systemImage: "cart",
            blurb: "Follow up when a customer leaves something in their cart.",
            subject: "Still thinking about {{Product Name|it}}?",
            body: """
            Hi {{First Name|there}},

            You left {{Product Name|something}} in your cart the other day and didn't get as far as the checkout. This is a nudge, not a sales pitch.

            It's still in stock at {{Amount|the price you saw|currency:USD}}, and I can hold one under your name for a few days. No deposit, and nothing owed if you change your mind.

            If it was the size or the color that stopped you, tell me what you were after and I'll check what's due in on the next delivery.

            And if you've already bought it elsewhere, that's genuinely fine — say so and I'll leave you be.

            Best,
            {{Sales Rep|Your name}}
            """,
            audiences: [.prospects, .customers],
            industries: [.retail]
        ),
        StarterTemplate(
            id: "retail-order-pickup",
            name: "Ready for pickup",
            category: "Get paid",
            systemImage: "bag",
            blurb: "Let a customer know their order is waiting at the counter.",
            subject: "Your order is ready to collect, {{First Name|there}}",
            body: """
            Hi {{First Name|there}},

            {{Product Name|Your order}} is packed and waiting behind the counter for you.

            Order: {{Order Number|under your name}}
            Collect by: {{Due Date|the end of next week|date:MMMM d}}
            Still to pay: {{Amount|nothing, it's settled|currency:USD}}

            Give your name at the desk and we'll bring it straight out — nothing to print. We hold collections for seven days, and if you need longer than that, reply and I'll keep it back for you.

            If anything in the order isn't what you expected, say so at the counter and we'll sort it there and then.

            Thanks,
            {{Sales Rep|The store team}}
            """,
            audiences: [.customers],
            industries: [.retail]
        ),
        StarterTemplate(
            id: "retail-loyalty-early-access",
            name: "Early access for regulars",
            category: "Retain",
            systemImage: "star.circle",
            blurb: "Give regular customers first pick before a sale goes public.",
            subject: "Shop the sale a day early, {{First Name|there}}",
            body: """
            Hi {{First Name|there}},

            Our {{Sale Name|end-of-season}} sale opens to everyone on {{Meeting Date|Saturday|date:EEEE, MMMM d}}. You shop with us often enough that you get in a day early.

            The reductions are the same as everyone else's — {{Discount|as marked on the ticket}} — you simply get first pick while the sizes and colors are still on the rail.

            Come in whenever suits, or reply with what you're after and I'll put it aside under your name before the doors open.

            If you'd rather not get these notes, say the word and I'll take you off the early list.

            Thanks for shopping with us,
            {{Account Manager|The store team}}
            """,
            audiences: [.customers],
            industries: [.retail]
        ),
        StarterTemplate(
            id: "education-orientation-details",
            name: "Orientation details",
            category: "Connect",
            systemImage: "building.columns",
            blurb: "Send starting students everything they need for day one.",
            subject: "Orientation details for {{Meeting Date|your first day|date:EEEE, MMMM d}}",
            body: """
            Hi {{First Name|there}},

            You're registered for {{Program Name|your program}}, and orientation is on {{Meeting Date|the date in your enrollment letter|date:EEEE, MMMM d}}.

            Where to go: {{Room|the room listed on your schedule}} at {{Campus|our main campus}}. Doors open half an hour early if you'd rather find it without rushing.

            What to bring: photo ID for your student card, and anything on the pre-course list. Books, logins and parking passes are all handed out on the day.

            If you can no longer start with this cohort, tell me now rather than later — moving you to the next intake is straightforward before day one, and awkward after it.

            See you on the day,
            {{Account Manager|The admissions team}}
            """,
            audiences: [.customers],
            industries: [.education]
        ),
        StarterTemplate(
            id: "education-tuition-balance",
            name: "Tuition balance due",
            category: "Get paid",
            systemImage: "dollarsign.circle",
            blurb: "Remind a student or sponsor of a balance before registration closes.",
            subject: "Your {{Term|term}} balance is due {{Due Date|soon|date:MMMM d, yyyy}}",
            body: """
            Hi {{First Name|there}},

            A quick note on your student account for {{Term|this term}}. The balance is {{Amount|the figure on your statement|currency:USD}} against {{Invoice Number|the invoice we sent}}, and it falls due on {{Due Date|the date shown on your statement|date:MMMM d, yyyy}}.

            Once it clears, registration for next term opens as normal. If it's still outstanding after the due date a hold goes on the account, and I'd much rather help you avoid one than lift one later.

            If an employer or sponsor is covering the cost, send me their billing contact and I'll invoice them directly.

            And if the timing is genuinely difficult, say so — a payment plan is usually possible, but only if we set it up before the due date.

            Thanks,
            {{Account Manager|The bursar's office}}
            """,
            audiences: [.customers],
            industries: [.education]
        ),
        StarterTemplate(
            id: "education-training-seats",
            name: "Unused training seats",
            category: "Retain",
            systemImage: "person.3",
            blurb: "Nudge a client to use the training seats they've already paid for.",
            subject: "Seats still unused on {{Company|your}} training agreement",
            body: """
            Hi {{First Name|there}},

            A heads-up on your training agreement: {{Seats Remaining|several}} of your seats are still unused, and they lapse on {{Renewal Date|your agreement's end date|date:MMMM d, yyyy}}.

            I'd rather you got the value than watched them expire. Two easy routes: add people to the open sessions already on our calendar, or we run a closed cohort just for {{Company|your team}} on a date that suits your operation.

            If the people you originally had in mind have changed roles or moved on, send me the new names and I'll transfer the registrations across.

            And if the training simply isn't landing with your teams, tell me plainly — I'd sooner rework the content than let the seats go quietly to waste.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.customers],
            industries: [.education]
        ),
        StarterTemplate(
            id: "hospitality-group-inquiry",
            name: "Group inquiry reply",
            category: "Grow",
            systemImage: "person.3",
            blurb: "Reply to an inquiry about a group booking or private event.",
            subject: "Holding {{Event Date|your date|date:EEEE, MMMM d}} for {{Company|your group}}",
            body: """
            Hi {{First Name|there}},

            Thanks for the inquiry — we'd be glad to look after {{Company|your group}} on {{Event Date|the date you asked about|date:EEEE, MMMM d}}.

            For {{Party Size|a group of your size}} I'd suggest {{Product Name|the private dining room}}. It seats the whole party on one table, and we can set it for a sit-down meal or something more relaxed.

            Here's the provisional hold, with nothing owed yet:

            Date: {{Event Date|as discussed|date:EEEE, MMMM d}}
            Guests: {{Party Size|as discussed}}
            Space: {{Product Name|the private dining room}}
            Minimum spend: {{Amount|confirmed once the menu is set|currency:USD}}

            I'll keep the date for seven days, no deposit and no obligation. Tell me what you need on menus, timing, AV or step-free access and I'll come back with a full proposal.

            If the date has moved or the numbers have changed, just say so and I'll look again.

            Best,
            {{Sales Rep|Your name}}
            """,
            audiences: [.prospects, .customers],
            industries: [.hospitality]
        ),
        StarterTemplate(
            id: "hospitality-pre-arrival",
            name: "Before your stay",
            category: "Connect",
            systemImage: "bed.double",
            blurb: "Send arrival details a few days before a guest checks in.",
            subject: "Before your stay — {{Arrival Date|a few details|date:EEEE, MMMM d}}",
            body: """
            Hi {{First Name|there}},

            We're looking forward to having you with us on {{Arrival Date|the date on your booking|date:EEEE, MMMM d}}. Your reference is {{Booking Reference|on your confirmation email}}.

            A few practical things, so arrival is the easy part:

            - Check-in is from 3pm. If you'll be getting in after 9pm, reply and we'll arrange a late check-in.
            - Parking is on site and doesn't need booking.
            - Breakfast runs 7 to 10, and a little later on weekends.

            If anyone in the party has a dietary requirement, or would rather be on the ground floor, tell me now and I'll sort it before you arrive.

            Safe travels,
            {{Account Manager|The front desk}}
            """,
            audiences: [.customers],
            industries: [.hospitality]
        ),
        StarterTemplate(
            id: "hospitality-season-opening",
            name: "Opening for the season",
            category: "Announce",
            systemImage: "sun.max",
            blurb: "Tell past guests you're reopening and taking bookings again.",
            subject: "The new season opens on {{Opening Date|the date below|date:EEEE, MMMM d}}",
            body: """
            Hi {{First Name|there}},

            We're back for the season on {{Opening Date|the date we've set|date:EEEE, MMMM d}}, and because you were with us in {{Last Visit|last season|date:MMMM yyyy}}, you get first pick of dates before booking opens to everyone else.

            Two things have changed over the closed months: the terrace is back in use, and {{Product Name|the menu}} has been rewritten from scratch.

            The good weekends tend to go early — most of last summer was spoken for by the end of spring. If you'd like dates held, reply with what you're after and the size of the party, and I'll put your name against them.

            And if you'd rather not hear from us about this sort of thing, say so and I'll take you off the list. No hard feelings.

            Warm regards,
            {{Account Manager|The team}}
            """,
            audiences: [.customers],
            industries: [.hospitality]
        ),
        StarterTemplate(
            id: "construction-bid-invitation",
            name: "Invitation to bid",
            category: "Connect",
            systemImage: "hammer",
            blurb: "Invite a trade partner to price a package before bids close.",
            subject: "Bid invitation — {{Project Name|our next project}}, due {{Due Date|soon|date:MMMM d}}",
            body: """
            Hi {{First Name|there}},

            We're pricing {{Project Name|a new project}} at {{Site Address|the site}} and would like {{Company|your crew}} on the bid list for the {{Trade Package|scope you cover}}.

            Drawings, specs and every addendum issued so far are ready to go — say the word and they're with you today.

            Bids are due {{Due Date|on the date in the bid docs|date:EEEE, MMMM d}}, and the site walk is set for {{Meeting Date|the week before|date:MMMM d}}.

            If your schedule is already full this quarter, just tell me and I'll keep you on the list for the next one. A straight no is more use to me than silence.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.partners],
            industries: [.construction]
        ),
        StarterTemplate(
            id: "construction-change-order",
            name: "Change order approval",
            category: "Get paid",
            systemImage: "doc.badge.plus",
            blurb: "Get written sign-off on added scope before work carries on.",
            subject: "Change order {{Change Order Number|for your approval}} — {{Project Name|your project}}",
            body: """
            Hi {{First Name|there}},

            We ran into something at {{Site Address|the site}} that changes the scope, so I want your sign-off before we go any further.

            What changed: {{Change Description|the condition we found once the work was opened up}}
            Change order: {{Change Order Number|attached}}
            Added cost: {{Amount|see attached|currency:USD}}
            Schedule impact: {{Schedule Impact|a few days on the current phase}}

            Nothing on that item moves until you approve it. I'd rather hold a day than have this turn up as a surprise on the final invoice.

            Reply with your approval, or call me on {{Phone|the number below}} and we'll walk through it.

            Best,
            {{Account Manager|Your project manager}}
            """,
            audiences: [.customers],
            industries: [.construction]
        ),
        StarterTemplate(
            id: "construction-site-work-notice",
            name: "Site work notice",
            category: "Announce",
            systemImage: "calendar.badge.clock",
            blurb: "Tell a client what to expect on site before the crew turns up.",
            subject: "Work at {{Site Address|the site}} starting {{Meeting Date|shortly|date:EEEE, MMMM d}}",
            body: """
            Hi {{First Name|there}},

            Telling you before the trucks show up seems fairer than explaining afterwards. We start {{Work Description|the next phase of work}} at {{Site Address|your property}} on {{Meeting Date|the date below|date:EEEE, MMMM d}}.

            What to expect: an early start, noise through the morning, and the {{Access Note|driveway and front entrance}} kept clear for deliveries.

            The {{Inspection Type|county inspection}} is booked for {{Due Date|later that week|date:MMMM d}}, so we'd rather not give up the slot.

            If that timing lands badly — a delivery of your own, someone working from home — tell me and we'll shift what we can.

            Thanks,
            {{Account Manager|Your site supervisor}}
            """,
            audiences: [.customers],
            industries: [.construction]
        ),
        StarterTemplate(
            id: "transport-lane-rate-quote",
            name: "Lane rate quote",
            category: "Grow",
            systemImage: "map",
            blurb: "Quote a lane with the equipment, transit and all-in rate spelled out.",
            subject: "Rate for {{Origin|the lane you asked about}} — quote {{Quote Number|enclosed}}",
            body: """
            Hi {{First Name|there}},

            Here's our rate on {{Origin|the lane you asked about}} to {{Destination|the delivery point}}, good from {{Quote Date|today|date:MMMM d, yyyy}}.

            Quote: {{Quote Number|enclosed}}
            Equipment: {{Equipment|53-foot dry van}}
            All-in rate: {{Amount|see the quote|currency:USD}}
            Transit: {{Transit Days|two days, door to door}}

            That's fuel included, with two hours free at pick-up and two at delivery. If {{Company|your team}} needs a reefer, a team run or a tighter delivery window, say so and I'll re-price it rather than have you work it out from a tariff.

            We run this lane most weeks, so if the volume is steady I'd sooner agree a contract rate than quote it load by load.

            And if you've already covered it, no trouble — just tell me and I'll check back when it's open again.

            Best,
            {{Sales Rep|Your name}}
            """,
            audiences: [.prospects, .customers],
            industries: [.transportation]
        ),
        StarterTemplate(
            id: "transport-detention-charges",
            name: "Detention charges",
            category: "Get paid",
            systemImage: "stopwatch",
            blurb: "Explain a detention charge before the invoice lands.",
            subject: "Detention on load {{Load Number|from last week}}",
            body: """
            Hi {{First Name|there}},

            Before the invoice reaches you, here's the detention on {{Load Number|the load in question}}, so nothing on it comes as a surprise.

            Stop: {{Destination|the receiver}}
            Free time: {{Free Time|two hours}}
            Time on site: {{Detention Hours|longer than the free window}}
            Detention billed: {{Amount|the charge shown|currency:USD}}

            It will show up on invoice {{Invoice Number|from us}}, due {{Due Date|on our usual terms|date:MMMM d, yyyy}}. The arrival and departure times came straight off the driver's log, and I'm glad to send them over if you'd like to check them against the receiver's gate record.

            If the appointment was moved after dispatch, or the hold-up was ours, tell me and I'll take the charge off. I'd rather settle it now than have it argued over at month end.

            Thanks,
            {{Account Manager|Accounts team}}
            """,
            audiences: [.customers],
            industries: [.transportation]
        ),
        StarterTemplate(
            id: "transport-delivery-delay",
            name: "Delivery running late",
            category: "Announce",
            systemImage: "exclamationmark.triangle",
            blurb: "Tell a customer a load will miss its delivery window.",
            subject: "Load {{Load Number|update}} — running behind",
            body: """
            Hi {{First Name|there}},

            You should hear this from me rather than from the receiver: {{Load Number|your shipment}} is going to miss its delivery window.

            What happened: {{Delay Reason|a closed route and a lost driving day}}. The trailer is secure, the freight hasn't been touched, and we're moving again.

            Revised ETA into {{Destination|the delivery site}}: {{ETA|I'll confirm it the moment I have it|date:EEEE, MMMM d}}.

            If the receiver works to strict dock hours, tell me what they are and we'll rebook the appointment rather than have the driver sit at the gate.

            I'll let you know the moment it's off the trailer. If anything at {{Company|your end}} has to move ahead of it, call rather than email me and I'll pick up.

            Sorry for the disruption,
            {{Account Manager|Your name}}
            """,
            audiences: [.customers],
            industries: [.transportation]
        ),
        StarterTemplate(
            id: "resources-preseason-booking",
            name: "Pre-season booking",
            category: "Grow",
            systemImage: "calendar.badge.clock",
            blurb: "Lock in supply and application windows before the season starts.",
            subject: "Booking the season for {{Company|your operation}}",
            body: """
            Hi {{First Name|there}},

            We're setting the schedule for the coming season, and I wanted to get {{Company|your operation}} on the board before the good windows go.

            If you can give me rough numbers — acres, tonnage, and when you want it on the ground — I'll hold a slot and confirm the delivered price. Today that's {{Amount|last season's rate|currency:USD}} for {{Product Name|the blend you ran last year}}.

            Nothing is binding until you say so. Weather moves and plans change, and I'd rather reshuffle than have you committed to the wrong thing.

            If you're already sorted for this year, just say so and I'll leave you be until autumn.

            Best,
            {{Sales Rep|Your name}}
            """,
            audiences: [.prospects, .customers],
            industries: [.naturalResources]
        ),
        StarterTemplate(
            id: "resources-tonnage-invoice",
            name: "Tonnage invoice",
            category: "Get paid",
            systemImage: "banknote",
            blurb: "Invoice for delivered tonnage with the tickets to match.",
            subject: "Invoice {{Invoice Number|for last month's loads}} — {{Product Name|delivered tonnage}}",
            body: """
            Hi {{First Name|there}},

            Here's the invoice for what went out to {{Company|your site}}, with the scale tickets attached so every load ties back to a ticket number.

            Invoice: {{Invoice Number|enclosed}}
            Against PO: {{PO Number|your order}}
            Material: {{Product Name|as delivered}}
            Net tons: {{Quantity|per the tickets}}
            Due: {{Amount|the total shown|currency:USD}} by {{Due Date|the date on the invoice|date:MMMM d, yyyy}}

            If a ticket is missing or a weight looks off against your gate records, send me the load number and I'll pull the weighbridge copy so we can sort it quickly.

            And if the timing is awkward this month, tell me before the due date rather than after — we can usually work something out.

            Thanks for the steady work,
            {{Account Manager|Accounts team}}
            """,
            audiences: [.customers],
            industries: [.naturalResources]
        ),
        StarterTemplate(
            id: "resources-site-access-notice",
            name: "Site access notice",
            category: "Announce",
            systemImage: "exclamationmark.triangle",
            blurb: "Send access and safety requirements before a crew arrives on site.",
            subject: "Site access for {{Meeting Date|your visit|date:MMMM d}} — what you'll need",
            body: """
            Hi {{First Name|there}},

            Before anyone from {{Company|your crew}} comes through the gate on {{Meeting Date|the scheduled day|date:EEEE, MMMM d}}, here's what you'll need.

            Site induction has to be done beforehand — about twenty minutes online, and nobody gets past the gatehouse without it. Bring photo ID and your {{Certification|current tickets and competency cards}}.

            PPE is hard hat, hi-vis, safety glasses and steel toes, worn from the car park in. Sign in at {{Site Address|the main gatehouse}} and we'll walk you to the muster point and through the site-specific hazards.

            If your dates have shifted or you're sending different people, tell me early. Changing a name on the access list the day before is easy; doing it at the gate is not.

            Anything you're unsure about, reply to this note and I'll sort it before you travel.

            Regards,
            {{Account Manager|Site contact}}
            """,
            audiences: [.partners, .customers],
            industries: [.naturalResources]
        ),
        StarterTemplate(
            id: "finance-referral-partner-check-in",
            name: "Referral partner check-in",
            category: "Connect",
            systemImage: "arrow.left.arrow.right",
            blurb: "Take stock of how the referral flow is running in both directions.",
            subject: "Our referral flow with {{Company|your office}}",
            body: """
            Hi {{First Name|there}},

            We've been sending work back and forth long enough that it's worth looking at properly rather than assuming it's fine.

            From my side, the files that come out of {{Company|your office}} arrive clean — pre-approval attached, expectations already set with the buyer — and it shows in how few of them come apart in underwriting. That's why you get my referrals first.

            Where we still lose days is the handoff. Tell me who at {{Company|your office}} should be copied on the pre-approval and again at clear-to-close, and nobody has to chase paper the morning an offer goes in.

            Two things I'll put in writing, so you can quote them to a client without checking with me first: pre-approvals back inside {{Turn Time|one business day}}, and a call to the listing side on every offer your buyer writes.

            If the flow has been running mostly one way lately, say so plainly. Volume moves around in {{City|this market}}, and I'd rather rebalance it out loud than quietly keep score.

            Worth twenty minutes on {{Meeting Date|a morning that suits you|date:EEEE, MMMM d}} to set how we work this year? If you'd rather leave things exactly as they are, that's a perfectly good answer too.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.partners],
            industries: [.finance]
        ),
        StarterTemplate(
            id: "finance-producer-recruit",
            name: "Bring your book",
            category: "Recruit",
            systemImage: "person.text.rectangle",
            blurb: "Approach a producer about the desk, the book and the split.",
            subject: "About the {{Job Title|producer}} seat we're filling",
            body: """
            Hi {{First Name|there}},

            I'll be straight about why I'm writing. We have a {{Job Title|producer}} seat open, and your name came up more than once when I asked who was worth talking to in {{City|this market}}.

            Here is the honest shape of it. The split is {{Commission Split|at the better end of what's paid around here}}, renewals stay yours, and the desk comes with {{Book Size|house accounts to service from day one}} rather than a phone and a wish.

            What matters more than the comp grid, in my experience: you'd have {{Support Staff|an account manager and a service assistant}} behind you, so your week goes on writing business instead of chasing certificates and endorsements. Carrier appointments are in place and errors and omissions coverage is carried for you.

            I'm not asking you to do anything that puts you sideways with your current agreement. If there's a non-solicit in it, we talk about what a clean move looks like before anything else happens.

            If you want the full picture — the comp, the book, the people you'd sit with — I'd rather do that over coffee than over email. Tell me a day and I'll come to you.

            And if you're settled where you are, say so and I won't circle back. I'd sooner ask you directly and take your answer than hear it secondhand.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.candidates],
            industries: [.finance]
        ),
        StarterTemplate(
            id: "professional-subconsultant-engagement",
            name: "Bringing you in",
            category: "Connect",
            systemImage: "person.2",
            blurb: "Bring a specialist firm onto a file and agree the split up front.",
            subject: "Room for {{Company|your firm}} on {{Matter Name|a file we're running}}",
            body: """
            Hi {{First Name|there}},

            We've taken on {{Matter Name|a piece of work}} that runs straight into {{Specialty|your side of the practice}}, and rather than stretch to cover it ourselves I'd sooner bring {{Company|your firm}} in properly.

            The split I have in mind: we stay prime and hold the client relationship, {{Company|your team}} takes {{Scope Split|the specialist scope end to end}} and signs it off in your own name. You bill us, we bill the client, and your fee comes off {{Rate Schedule|your standard rate schedule}} rather than something I've invented.

            Before either of us spends real time on it, run your conflicts check. The client name and the other parties are in the attachment. If it comes back dirty, tell me and that's the end of it — nothing lost either way.

            The practical bits: the deliverable is due by {{Due Date|the date shown in the attachment|date:MMMM d, yyyy}}, we'd need your certificate of insurance on file before you start, and I'd want one named person at your end I can call rather than a shared inbox.

            I'm asking you ahead of anyone else because the last piece we did together came back clean and on time, and the client noticed. That counts for a good deal more than a panel listing.

            If your bench is full this quarter, say so straight and I'll come back on the next one.

            Thanks,
            {{Account Manager|Your name}}
            """,
            audiences: [.partners],
            industries: [.professionalServices]
        ),
        StarterTemplate(
            id: "professional-associate-outreach",
            name: "Work worth moving for",
            category: "Recruit",
            systemImage: "person.crop.circle.badge.plus",
            blurb: "Describe a role to a candidate the way you'd want it described to you.",
            subject: "The {{Job Title|associate}} work here, described honestly",
            body: """
            Hi {{First Name|there}},

            I came across your work at {{Company|your current firm}} and would rather describe a role to you properly than send you a posting.

            We're hiring {{Job Title|an associate}} into {{Department|the practice group}}. The work is {{Practice Focus|middle-market and hands-on, varied enough that you won't run the same engagement twice}}, and you'd be in front of clients early rather than three years in.

            The parts people usually have to ask about, so I'll say them without being asked: {{Utilization Target|the chargeable-hours expectation}} is set where people actually hit it, busy season is real but properly staffed, and we cover {{Credential Support|exam sittings, the review course and licensing fees}} without turning it into a negotiation.

            Advancement here is written down — what the next step is, who decides it, and roughly when. It isn't a conversation that only happens if you push for one.

            I don't know yet whether this is right for you, and I'd rather work that out on a call than talk you into anything.

            If you're happy where you are, say so and I'll leave it there. If the timing is simply wrong, tell me when to come back and I'll make a note and do exactly that.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.candidates],
            industries: [.professionalServices]
        ),
        StarterTemplate(
            id: "manufacturing-shop-floor-hire",
            name: "Shop floor hire",
            category: "Recruit",
            systemImage: "wrench.and.screwdriver",
            blurb: "Approach a skilled tradesperson about an opening on your floor.",
            subject: "About the {{Job Title|machinist}} opening on our floor",
            body: """
            Hi {{First Name|there}},

            I'm reaching out about a {{Job Title|machinist}} opening on our floor in {{City|our area}}, and I'd rather describe the work honestly than point you at a job posting.

            It's {{Shift|first shift}}, running {{Machine Type|CNC mills and lathes}} on {{Run Type|short-run and prototype work}}. Enough setups to keep the day from blurring together, and tolerances tight enough that reading the print properly still matters. You'd own your own setups and your own first-piece checks rather than hand them off to somebody down the aisle.

            The things people ask me first: {{Pay Range|the rate is competitive and I'll share the band on our first call}}, overtime is there if you want it and never mandatory, and the crib is stocked so you're not hunting for inserts halfway through a run.

            If you're settled where you are, say so plainly and I'll leave it there. I won't keep circling back.

            If you're curious, fifteen minutes on the phone is enough to start, and you're welcome to walk the floor and see the machines before anything formal happens. Reach me on {{Phone|the number below}} whenever suits you.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.candidates],
            industries: [.manufacturing]
        ),
        StarterTemplate(
            id: "healthcare-accepting-new-patients",
            name: "Accepting new patients",
            category: "Grow",
            systemImage: "person.crop.circle.badge.plus",
            blurb: "Let a prospective patient or client know your schedule is open.",
            subject: "We're taking new patients in {{City|your area}}",
            body: """
            Hi {{First Name|there}},

            I'm with {{Practice Name|our practice}} here in {{City|your area}}, and I'm writing for a simple reason: we have room on the schedule and we're taking new patients again.

            If you've been meaning to get established with a local office, or you've moved recently, this is an easy time to do it. Nothing to decide today.

            The practical details: we're at {{Address|our office}}, open {{Office Hours|weekdays with early appointments most mornings}}, and we participate with {{Insurance Plan|most major plans}}. If you'd rather not use insurance, we'll quote a self-pay price up front so you know the number before you come in.

            Getting started is one short call to {{Phone|the front desk}}. We'll take your details, tell you what to bring, and find a time that fits your week. Please don't send anything about your health by email — our secure forms are the right place for that, and we'll hand them to you when you book.

            And if you're happy where you are, that's genuinely good to hear. Say so and I'll leave your name off the list.

            Best,
            {{Account Manager|Our practice manager}}
            """,
            audiences: [.prospects],
            industries: [.healthcare]
        ),
        StarterTemplate(
            id: "healthcare-referral-pathway",
            name: "Referral pathway check-in",
            category: "Connect",
            systemImage: "arrow.left.arrow.right",
            blurb: "Tidy up how referrals move between two offices.",
            subject: "How referrals are moving between us and {{Company|your office}}",
            body: """
            Hi {{First Name|there}},

            We've been taking referrals from {{Company|your office}} for a while now, and I wanted to check the plumbing between us rather than assume it all still works.

            From our side the flow is straightforward: your office sends the referral through {{Referral Channel|the secure portal or our direct line}}, our intake coordinator picks it up the same business day, and we call to schedule. Once the appointment is on the books, we send a confirmation back to your office so nobody is left wondering whether it landed.

            What helps us most is the administrative half — a current contact number, the plan on file, and any authorization your staff have already opened. When that travels with the referral we book faster, and your front desk fields fewer callbacks.

            Two things worth confirming at your end: who we should chase when a referral goes quiet, and whether {{Fax Number|the number we hold for you}} is still right. Names and numbers change far more often than anybody updates them.

            Anything clinical belongs in the record rather than in email to me. I sit on the administrative side, and {{Referral Channel|the portal}} is the proper route for it.

            If the arrangement is working and there's nothing to fix, a one-line reply saying so is a perfectly good answer.

            Thanks,
            {{Account Manager|Our referral coordinator}}
            """,
            audiences: [.partners],
            industries: [.healthcare]
        ),
        StarterTemplate(
            id: "healthcare-care-team-opening",
            name: "Care team opening",
            category: "Recruit",
            systemImage: "stethoscope",
            blurb: "Talk to a nurse, aide or hygienist about a role on your team.",
            subject: "An opening on our care team, {{First Name|there}}",
            body: """
            Hi {{First Name|there}},

            I'm writing about a {{Job Title|nursing}} opening with us in {{City|your area}}, and I'd rather tell you how the job actually runs than send you a posting.

            The schedule is {{Schedule|three twelves with a weekend rotation every third week}}, self-scheduled a month ahead so you can plan a life around it. Assignments are {{Ratio|kept to a size people can genuinely carry}}, and charting time sits inside the shift rather than being something you finish in the parking lot.

            On the practical side: {{Pay Range|the rate is competitive and I'll share the band on our first call}}, differentials for nights and weekends, and {{CEU Support|a continuing education allowance with paid time to use it}}. Orientation is {{Orientation Length|six weeks alongside a named preceptor}}, not two days and good luck.

            I know people in your line of work get approached constantly. If you're settled, tell me and I'll stop there — no follow-ups, no checking back in a few months.

            If you're curious, fifteen minutes whenever your schedule allows is plenty, including straight after a shift. You're also welcome to come see the place and talk to the people you'd be working beside before anything formal starts.

            Thanks,
            {{Account Manager|Your name}}
            """,
            audiences: [.candidates],
            industries: [.healthcare]
        ),
        StarterTemplate(
            id: "technology-legacy-migration",
            name: "Legacy tool migration",
            category: "Grow",
            systemImage: "arrow.left.arrow.right",
            blurb: "Offer a prospect a low-risk look at replacing a tool they have outgrown.",
            subject: "A low-risk look at replacing {{Legacy System|your current tool}}",
            body: """
            Hi {{First Name|there}},

            You're not the first person I've spoken to who's still on {{Legacy System|an older platform}} mainly because moving off it looks like more work than living with it.

            That's usually a fair read. What changes it is whether the data comes across cleanly and whether the new thing talks to everything else — for {{Company|your team}} I'd expect that to mean {{Integration|the systems it has to sit alongside}}, single sign-on, and however you provision users today.

            So the first step I'd suggest isn't a demo. It's a sandbox with a slice of your own data in it, so {{Department|your team}} can judge the fit against something real instead of a slide.

            Run it alongside {{Legacy System|what you have now}} for as long as you want. Nothing gets switched off, and rolling back is just turning us off.

            If none of this is worth thinking about until {{Renewal Date|your current contract comes up|date:MMMM yyyy}}, say so and I'll check back then rather than now.

            Best,
            {{Sales Rep|Your name}}
            """,
            audiences: [.prospects],
            industries: [.technology]
        ),
        StarterTemplate(
            id: "technology-engineer-outreach",
            name: "Engineering role outreach",
            category: "Recruit",
            systemImage: "terminal",
            blurb: "Approach an engineer about a specific role by describing the actual work.",
            subject: "About a {{Role|senior engineer}} opening on my team",
            body: """
            Hi {{First Name|there}},

            I'm hiring for a {{Role|senior engineer}} role on my team, and I'd rather describe the work than send you a job posting.

            You'd own {{Service Area|a service end to end}} — design, review, deploys, and the pager that comes with it. We ship most days, on-call is {{On-Call Rotation|one week in six}}, and every quarter has real time set aside for the things that page people at night, not just for the roadmap.

            The team is {{Team Size|small enough that you'd know what everyone is working on}}, and the stack is {{Tech Stack|mostly what you'd expect, with a couple of older corners we're honest about}}. It's an individual contributor role, and nobody would be steering you toward management unless you asked.

            I'm writing to you rather than to a list because of the work you're doing as {{Job Title|an engineer}}.

            If you're curious, the next step is a call, not an application. {{Meeting Date|Most of next week|date:EEEE, MMMM d}} is open on my end, or tell me what suits you. Pay is {{Salary Band|a band I'll give you plainly on that call, before you spend any more time on this}}.

            And if you're happy where you are, that's a good place to be. Tell me and I won't write again.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.candidates],
            industries: [.technology]
        ),
        StarterTemplate(
            id: "wholesale-line-card-intro",
            name: "Our line card",
            category: "Grow",
            systemImage: "tray.full",
            blurb: "Introduce your line card to a buyer who has never ordered from you.",
            subject: "A second source for {{Product Name|the lines you buy}}",
            body: """
            Hi {{First Name|there}},

            We stock {{Product Name|the lines you buy}} for {{Industry|operations like yours}} out of our warehouse in {{City|our region}}. I'm not writing to move you off your current supplier — I'd like to be the number you call when something goes short.

            Nothing to decide today. What's worth having on file is our line card, and the handful of numbers buyers ask me about before anything else:

            Fill rate: {{Fill Rate|last twelve months, published as it stands}}
            Lead time: {{Lead Time|48 hours on stocked lines from receipt of PO}}
            Case pack and minimum order: {{Case Pack|listed against every item on the card}}
            Terms: {{Payment Terms|net 30 once the credit application clears}}
            Freight: prepaid over {{Freight Minimum|the order minimum shown on the card}}

            Volume tiers start lower than most people expect. The first break lands around {{Quantity|a full pallet}} of a single item; on a mixed order it's {{Amount|the value printed on the line card|currency:USD}}.

            If it's useful, send me the five items {{Company|your team}} buys most and I'll price them landed against what you pay now. If we're not sharper on them, I'll tell you so.

            And if you're well covered already, that's good to hear — say so and I'll leave it there.

            Best,
            {{Sales Rep|Your name}}
            """,
            audiences: [.prospects],
            industries: [.wholesale]
        ),
        StarterTemplate(
            id: "wholesale-warehouse-opening",
            name: "Warehouse floor opening",
            category: "Recruit",
            systemImage: "person.text.rectangle",
            blurb: "Tell someone what a warehouse shift is really like before they apply.",
            subject: "A {{Role|warehouse lead}} job on {{Shift|first shift}}, {{First Name|there}}",
            body: """
            Hi {{First Name|there}},

            We're hiring a {{Role|warehouse lead}} on {{Shift|first shift}}, and since you've done this work before, I'd rather tell you what the day actually looks like than point you at a posting.

            The building moves {{Order Volume|a few hundred orders a day}} on {{System|scanners and a live pick list}}: receiving early, picking and packing through the middle of the day, carriers loaded out by {{Cutoff Time|late afternoon}}. You'd be running that floor and the people on it, not just working it.

            Pay is {{Hourly Rate|a number I'll give you on the phone rather than make you guess at}}, with overtime through peak. Benefits start at {{Benefits Start|sixty days}}, and if you don't already hold the {{Certification|sit-down forklift ticket}}, we pay for it.

            Two things you should hear before you decide rather than after: the building isn't climate controlled, and {{Peak Season|the run-up to the holidays}} means longer weeks for everyone, leads included.

            We'd like someone on the floor by {{Due Date|the start of next month|date:MMMM d}}, so if you're interested the next step is a fifteen-minute phone call. No forms first.

            And if the shift, the pay, or the drive to {{City|our location}} doesn't work for you, just say so. No hard feelings, and I won't keep asking.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.candidates],
            industries: [.wholesale]
        ),
        StarterTemplate(
            id: "retail-vendor-sell-through",
            name: "Sell-through review",
            category: "Retain",
            systemImage: "chart.bar.xaxis",
            blurb: "Share sell-through with a brand rep and settle the reorder.",
            subject: "Sell-through on {{Product Name|your line}} — where we stand",
            body: """
            Hi {{First Name|there}},

            Here's how {{Product Name|your line}} has actually moved through our doors since the {{Season|spring}} delivery, while there's still time to do something about it.

            Sell-through to date: {{Sell Through|ahead of the rest of the category}}
            On hand: {{Quantity|about six weeks of cover}}
            Reorder window closes: {{Due Date|before the next ship window|date:MMMM d}}

            The core sizes are gone and the tail is sitting. If {{Company|your team}} can turn a fill-in on the top three SKUs inside that window, I'll take it. If the cut is closed, tell me now and I'll plan the markdown rather than guess at it.

            Two things would help from your side: {{Markdown Support|an allowance on the slow colors}}, and next season's linesheet early enough to build into the open-to-buy before {{Renewal Date|our buy meeting|date:MMMM d}}.

            You've shipped us complete and on time all year, which is rarer than it should be. I'd like to give the line more space next season, and that decision gets made on the numbers above.

            If the timing doesn't work at your end, say so plainly and we'll set the plan around what you can actually ship.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.partners],
            industries: [.retail]
        ),
        StarterTemplate(
            id: "retail-keyholder-hiring",
            name: "Keyholder opening",
            category: "Recruit",
            systemImage: "key",
            blurb: "Approach someone about a shop floor role, hours and all.",
            subject: "A {{Role|keyholder}} job at our {{City|neighborhood}} store",
            body: """
            Hi {{First Name|there}},

            I'm hiring a {{Role|keyholder}} for our {{City|neighborhood}} store, and your name came up from someone who has watched you work a busy floor.

            The honest shape of the job: {{Hours|around 32 hours a week}}, a mix of opens and closes, and one weekend day. You'd carry keys, run the register through the afternoon rush, reset the front table when the new floor set lands, and hold the floor on the manager's days off.

            Your time on a busy shop floor is the part that interests me — specifically whether you can keep a line moving and still look up at the person in front of you. Product knowledge is teachable. That isn't.

            The hourly rate is {{Amount|a number I'll be straight with you about on the phone|currency:USD}}, with the staff discount, and the schedule posted {{Schedule Notice|two weeks ahead}} so you can plan around it.

            If you're settled where you are, that's a fair answer and I won't keep asking. If you'd like to hear more, send me a couple of times this week and I'll call you on {{Phone|whatever number is easiest}}.

            Thanks,
            {{Account Manager|Your name}}
            """,
            audiences: [.candidates],
            industries: [.retail]
        ),
        StarterTemplate(
            id: "education-program-first-touch",
            name: "Exploring a program",
            category: "Grow",
            systemImage: "graduationcap",
            blurb: "An unhurried first reply to someone weighing up a program.",
            subject: "About {{Program Name|the program you asked about}}",
            body: """
            Hi {{First Name|there}},

            Thanks for asking about {{Program Name|the program}}. Here's the plain version, with no brochure attached.

            It runs {{Format|two evenings a week for sixteen weeks}}, starting with the {{Term|fall}} intake on {{Meeting Date|the first day of term|date:MMMM d, yyyy}}. Most people come in while working full time, so the schedule is built around that rather than the other way round.

            Two things people want to know before anything else. Prerequisites: {{Prerequisites|none beyond a high school diploma, and we'll look at any prior coursework for transfer credit}}. Cost: {{Amount|the current per-credit tuition, before aid|currency:USD}} — and if an employer offers tuition reimbursement, we can bill them directly instead of you.

            If you're deciding between us and somewhere else, that's normal and I won't pretend otherwise. Ask me what our graduates are actually doing a year out, or come sit in on a class before you commit to anything.

            The easiest next step is {{Next Step|a fifteen-minute call with an advisor, no application involved}}. Reply with a time that suits, or leave this here if you've decided to go another way. Either is fine.

            Best,
            {{Account Manager|The admissions team}}
            """,
            audiences: [.prospects],
            industries: [.education]
        ),
        StarterTemplate(
            id: "education-placement-partner",
            name: "Placement partnership",
            category: "Connect",
            systemImage: "briefcase",
            blurb: "Line up the next placement cycle with an employer partner.",
            subject: "Placements for the {{Term|coming}} term at {{Company|your organization}}",
            body: """
            Hi {{First Name|there}},

            Our {{Program Name|program}} is planning placements for the {{Term|spring}} term, and {{Company|your organization}} is the first call I make.

            Last cycle you hosted {{Quantity|two}} of our students, and every one of them finished their hours on site. A couple have since gone to work in the field, one of them for you, which is more or less the point of the arrangement.

            For the coming term I'd ask for the same again: {{Quantity|two}} placements, {{Placement Hours|roughly 120 hours each}}, starting the week of {{Meeting Date|the term start|date:MMMM d}}. We handle the affiliation agreement, the insurance paperwork and the background checks before anyone turns up at your door.

            What you get out of it is first look at people you've already trained, and a say in what we teach them. If you'd sit on the advisory committee this year, {{Next Step|the next meeting is short and mostly about the curriculum you'd change}}.

            Your site supervisors carry the real weight here, so I'd rather size this to what they can absorb. One placement is better than none, and none is better than a bad one.

            Tell me what's realistic and we'll build the term around it.

            Thanks,
            {{Account Manager|Your name}}
            """,
            audiences: [.partners],
            industries: [.education]
        ),
        StarterTemplate(
            id: "education-adjunct-invite",
            name: "Teach a section",
            category: "Recruit",
            systemImage: "book",
            blurb: "Ask a working professional to teach a course section.",
            subject: "Would you teach {{Course Name|a section}} for us in the {{Term|spring}} term?",
            body: """
            Hi {{First Name|there}},

            I'm looking for someone to teach {{Course Name|one of our evening sections}} in the {{Term|spring}} term, and I'd like it to be you.

            Your work as {{Job Title|a practitioner}} is the reason I'm asking. Our students are mostly adults heading into that job, and they can tell inside a week whether the person at the front has actually done it.

            Practically: one section, {{Meeting Days|two evenings a week}}, {{Contact Hours|about six contact hours}}, starting {{Meeting Date|the first week of term|date:MMMM d, yyyy}}. The syllabus and the materials already exist, so you'd be adapting rather than building from nothing. The stipend is {{Amount|the per-section rate, which I'll put in writing|currency:USD}}.

            The part people underestimate is grading and office hours. That's real time, most of it in the evenings, and I'd rather say it now than have you discover it in week four.

            If teaching has never appealed, say so and I'll stop there with no awkwardness at all. If it has, {{Next Step|a half-hour conversation with the department chair}} is the whole of the process before anything is decided.

            Thanks,
            {{Account Manager|Your name}}
            """,
            audiences: [.candidates],
            industries: [.education]
        ),
        StarterTemplate(
            id: "hospitality-allotment-review",
            name: "Season allotment review",
            category: "Retain",
            systemImage: "airplane",
            blurb: "Agree next season's allotment, release dates and commission with a travel trade partner.",
            subject: "Next season's allotment for {{Company|your agency}}",
            body: """
            Hi {{First Name|there}},

            Before we set inventory for {{Season|the coming season}}, I wanted to look at how the last one actually ran for {{Company|your agency}} and agree the shape of the next one with you rather than at you.

            Your pickup against the block came in at {{Pickup|close to where we both expected}}, and most of it landed in the shoulder weeks rather than the peak. That tells me we are holding the wrong dates rather than too much space overall.

            Here is what I would propose:

            Allotment: {{Allotment|the same room count, weighted toward the shoulder weeks}}
            Release: {{Release Date|21 days before arrival|date:MMMM d, yyyy}}
            Net rate: {{Amount|held at this season's level|currency:USD}}
            Commission: {{Commission|unchanged from our current agreement}}

            Rate parity is the one thing worth holding each other to. If you ever see us undercutting what you are selling on another channel, send it to me and I will deal with it at this end. You should not have to compete with our own booking engine.

            If it would help your consultants sell the property, I will host a site visit in a quiet week and cover the rooms. People who have stood in the lobby sell it better than any rate sheet does.

            And if your plans point elsewhere next season, tell me plainly. I would rather rebuild the block around what you can genuinely fill than hold space neither of us sells.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.partners],
            industries: [.hospitality]
        ),
        StarterTemplate(
            id: "hospitality-open-shifts-hiring",
            name: "Hiring for open shifts",
            category: "Recruit",
            systemImage: "fork.knife",
            blurb: "Approach a cook, server or front desk candidate about an open shift.",
            subject: "An open {{Job Title|line cook}} shift, if you want it",
            body: """
            Hi {{First Name|there}},

            I am hiring a {{Job Title|line cook}} at {{Company|our restaurant}} in {{City|town}}, and I would rather tell you what the job actually is than point you at a posting.

            The schedule is {{Shift|five days, mostly evenings}}, and it goes up two weeks ahead so you can plan a life around it. We do not run splits. If you need a fixed day off each week, ask for it now and I will build it into the schedule.

            You would be on {{Station|the grill station}}, running {{Covers|a steady book}} on a busy night. The prep list is honest, the crew closes down together, and nobody gets left alone at the end of a rough service.

            The hourly rate is {{Amount|the number I will give you straight when we talk|currency:USD}}, paid weekly by direct deposit, plus {{Tip Share|a share of the pooled tips}}. Shift meal every shift, uniform provided, and overtime paid rather than quietly expected.

            If it sounds worth a look, come in for a paid trail shift. A few hours on the line, no commitment either way, so you can see the kitchen on a normal night before you decide anything.

            And if the timing is wrong, or you are settled where you are, just say so and I will leave it there.

            Thanks,
            {{Account Manager|Your name}}
            """,
            audiences: [.candidates],
            industries: [.hospitality]
        ),
        StarterTemplate(
            id: "construction-precon-intro",
            name: "Preconstruction introduction",
            category: "Grow",
            systemImage: "building.2",
            blurb: "Introduce your firm to an owner or general contractor before the bid documents go out.",
            subject: "Early budget numbers for {{Project Name|your project}}",
            body: """
            Hi {{First Name|there}},

            I saw that {{Company|your team}} has {{Project Name|a project}} moving in {{City|the area}}, and I would rather introduce us now than show up as one more number when bids come in.

            We self-perform {{Trade Package|the scope you will be putting out}} and we are built for work at this size: bonding in place for {{Bonding Capacity|projects of this value}}, an EMR of {{EMR|well under one}}, and crews who have put up {{Similar Project|this building type before}}. Our prequalification packet can be on your desk the same day you ask for it.

            The useful thing at this stage, though, is numbers. Send whatever you have, schematics included, and we will come back with budget pricing and the assumptions behind it at no cost. Scope gets expensive when the first real number arrives too late to design around.

            If a walk is easier than a set of drawings, I will meet you at {{Site Address|the site}} and talk through the access, staging and sequencing we would expect. An hour, and no pitch at the end of it.

            If your team is already set for this one, that is fine and worth telling me. I would sooner be on the list early for the next project than chase this one.

            Best,
            {{Sales Rep|Your name}}
            """,
            audiences: [.prospects],
            industries: [.construction]
        ),
        StarterTemplate(
            id: "construction-crew-hiring",
            name: "Room on the crew",
            category: "Recruit",
            systemImage: "person.crop.circle.badge.plus",
            blurb: "Reach out to a tradesperson about a spot on the crew.",
            subject: "A spot for a {{Job Title|journeyman}} on our crew",
            body: """
            Hi {{First Name|there}},

            I am looking for a {{Job Title|journeyman electrician}} to come on with us, and I would rather give you the real details than a job ad.

            The work is {{Project Name|a commercial build}} in {{City|the area}}, with {{Backlog|about a year of work}} in front of it and more behind that. We keep our people through the winter rather than hiring for one job and laying off at the end of it.

            The schedule is {{Schedule|four tens, Monday through Thursday}}. Overtime is paid at time and a half past {{Overtime Threshold|forty hours}}, not banked or traded for time off. The hourly rate is {{Amount|at or above area scale|currency:USD}}, paid weekly by direct deposit.

            If a job takes you away from home, per diem is {{Per Diem|paid daily and lands in that week's check}}. The room is on us, so you are not fronting it and waiting on a reimbursement.

            You bring your hand tools. We furnish everything powered, all PPE, and {{Boot Allowance|a boot allowance every year}}. Bring your {{Certification|license and current OSHA card}} and the paperwork takes ten minutes.

            The crew is {{Crew Size|small enough that everyone knows everyone}}, run by a foreman who came up through the tools and still gets on them. That is the part I would want to know about if I were you.

            If you are on a job you would not want to walk away from, tell me when it wraps and I will call you then. If you are not looking at all, say the word and I will not keep at it. Otherwise send me two times that suit and I will call you on {{Phone|whatever number is best}}.

            Thanks,
            {{Account Manager|Your name}}
            """,
            audiences: [.candidates],
            industries: [.construction]
        ),
        StarterTemplate(
            id: "transport-capacity-commitment",
            name: "Lane capacity commitment",
            category: "Retain",
            systemImage: "road.lanes",
            blurb: "Offer a carrier partner committed volume on a lane instead of load-by-load spot freight.",
            subject: "Capacity on {{Origin|our lane}} for {{Quarter|next quarter}}",
            body: """
            Hi {{First Name|there}},

            We're setting the lane plan for {{Quarter|the coming quarter}}, and I'd rather build it around {{Company|your fleet}} than go back to the load board every Monday.

            Lane: {{Origin|the run we've been tendering you}} to {{Destination|the delivery point}}
            Equipment: {{Equipment|53-foot dry van}}
            Committed volume: {{Weekly Loads|the weekly count we've been giving you}}
            Rate: {{Amount|the all-in contract rate|currency:USD}}, held through {{Renewal Date|the end of the term|date:MMMM d, yyyy}}

            You've been running {{On Time Percentage|comfortably inside our on-time target}} on pickup and delivery, your drivers check in without being chased, and the tracking updates arrive without me asking. That is the entire reason this is a committed-freight conversation and not another spot quote.

            What I'd want back is first refusal on the tenders, and a truck under the load in the weeks that get ugly rather than only the easy ones. What you'd get is volume you can plan drivers and equipment against, and payment on {{Payment Terms|our standard terms}} without the rate being re-cut every month.

            If the number doesn't work against today's fuel and driver pay, tell me what does. I'd sooner negotiate it once now than watch the tenders quietly go unanswered.

            And if your capacity is already spoken for this quarter, say so plainly and I'll plan around you instead of filling your inbox with loads you can't take.

            Best,
            {{Account Manager|Your name}}
            """,
            audiences: [.partners],
            industries: [.transportation]
        ),
        StarterTemplate(
            id: "transport-driver-seat-open",
            name: "Open driver seat",
            category: "Recruit",
            systemImage: "steeringwheel",
            blurb: "Approach a driver about an open seat with the miles, home time and pay stated up front.",
            subject: "We have a seat open, {{First Name|there}}",
            body: """
            Hi {{First Name|there}},

            I'm hiring, and I'd rather tell you what the job actually is than send you a posting that says nothing.

            The seat: {{Open Role|company driver, regional}}. The run is {{Lane|out and back, no coast-to-coast}}, and you'd be home {{Home Time|every weekend, plus a night or two midweek}}. Miles sit around {{Weekly Miles|2,400 to 2,700 a week}}, and a short week gets made up rather than shrugged at.

            Pay is {{Pay Per Mile|a rate I'll give you straight over the phone}} per mile, with {{Accessorial Pay|stop pay, detention and layover on top}}. Benefits start {{Benefits Start|on day 31}}, not after half a year of waiting.

            Equipment is {{Truck Model|a late-model automatic}}, average fleet age {{Fleet Age|under three years}}, APU and inverter in every truck. The shop is in-house, so a PM doesn't cost you two days sitting at a vendor.

            Dispatch is a person who picks up the phone and knows your name. That's the part nobody can prove in a job posting, but you'd know inside a week whether it's true.

            If it's worth a conversation, call or text me directly and ask the blunt questions. Evenings are fine — I know you're driving during the day, and there's no application to fill in first.

            And if you're settled where you are, I'll take you at your word and leave it there.

            Thanks,
            {{Account Manager|Your name}}
            """,
            audiences: [.candidates],
            industries: [.transportation]
        ),
        StarterTemplate(
            id: "resources-field-crew-hiring",
            name: "Field crew opening",
            category: "Recruit",
            systemImage: "mountain.2",
            blurb: "Recruit a site or field worker with the rotation, camp and tickets spelled out honestly.",
            subject: "{{Open Role|An operator opening}} — {{Rotation|two weeks on, one week off}}",
            body: """
            Hi {{First Name|there}},

            We're crewing up for {{Season|the coming season}} and I'm looking for {{Open Role|a heavy equipment operator}}. Here's the shape of it up front, so you can decide before either of us spends much time on it.

            Rotation is {{Rotation|two weeks on, one week off}}, working {{Shift|twelve-hour shifts on a day and night swing}}. The site is {{Site Location|about four hours out}}, and we cover {{Travel|the flight and the drive in from the airstrip}}. You'd be in {{Camp|single-room camp with meals included}} — it's clean, the food is decent, and the wifi is honestly mixed.

            What you'd need to hold: {{Certification|a current ticket on the machine, plus first aid and site safety}}. If one has lapsed, say so rather than skip it. We'd sooner pay to renew a card than lose a good operator over it.

            The work is {{Seasonality|steady through the season, with a real chance of carrying on through the shutdown}}. I'd rather say that plainly than promise you twelve months and send you home in {{Layoff Month|the off-season}}.

            Pay is {{Pay Rate|an hourly rate I'll give you over the phone}}, plus {{Allowances|a living-out allowance and overtime past the scheduled hours}}. Benefits start {{Benefits Start|after your first full rotation}}.

            Call me and ask the awkward things — who you'd report to, what the camp is really like, how often a rotation gets extended. I'd rather answer that now than have you find out in week three.

            And if the rotation doesn't work for your family, that's a fair answer and I'll leave it there.

            Thanks,
            {{Account Manager|Your name}}
            """,
            audiences: [.candidates],
            industries: [.naturalResources]
        )
    ]

}
