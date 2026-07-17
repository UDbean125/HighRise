# HighRise — Competitive Feature Benchmark

*Compiled July 2026; expanded July 2026 (second pass) with §9–§11: the
mass-market tier (large-install-base apps with strong public ratings), a
dashboard-and-layout study, and a contact-import-cleaning benchmark. Sources:
official product pages, docs, and changelogs of each tool named below (verified
against first-party sources; where a vendor page was unreachable, verification
used domain-restricted search over the vendor's own site). Every recommendation
in §4 was independently fact-checked ("do the named competitors really ship
this today?") and feasibility-reviewed against the HighRise codebase.*

---

## 1. Executive summary

HighRise's core bet — **fully local, no servers, no tracking, send through the
user's own Apple Mail/Outlook** — is validated by the market. The privacy-first
segment demonstrably sustains paid products (SerialMailer $45 one-time,
SecureMailMerge ~$10/user/mo, MaxBulk Mailer ~$50–60), and *no* competitor is
as local as HighRise: even the privacy-positioned ones still route through
Microsoft Graph (SecureMailMerge), speak SMTP directly (SerialMailer/MaxBulk),
or run send/schedule server-side (Mailmeteor). Apple has left this niche
entirely to third parties — Pages "mail merge" cannot email at all, and
Word-on-Mac merge requires Outlook as the default client.

But the benchmark also shows HighRise is missing **eight table-stakes
features** that users of any modern merge tool expect (attachments, fallback
values, test-send, scheduling, quota-aware throttling, delivery report/export,
multi-sheet Excel, HTML in Apple Mail), plus one gap no competitor shares:
**nothing persists between launches** — every surveyed competitor has saved,
reusable templates.

Three platform risks need eyes-open decisions (§5): Apple Mail's AppleScript
cannot set an HTML body (workaround exists but needs a spike), scheduled send
can only ever be "while the app runs and the Mac is awake," and Microsoft's
"new Outlook" for Mac has a drastically reduced AppleScript dictionary that
threatens the existing Outlook path over time.

---

## 2. Where HighRise already beats the market

These are strengths to keep and market, not gaps:

- **Strictly the most private tool in the category.** No vendor cloud, no OAuth
  scopes, no data leaving the Mac. "We physically cannot track you" is a
  marketing line no rival can honestly say.
- **Safest default posture.** Draft-first by default with an explicit
  confirmation gate for immediate send. Most rivals (Word→Outlook, YAMM,
  Direct Mail) send immediately with no review queue.
- **Sent mail lives in the user's real account and Sent folder** — better audit
  trail and deliverability trust than SMTP-direct tools, and it inherits
  Gmail/Outlook undo-send for free.
- **Hard no-leak guarantee.** No raw `{{placeholder}}` or blank ever reaches a
  recipient (blocked rows held back). YAMM and the Thunderbird add-on can leak
  raw tokens; Word silently merges blanks. Only Woodpecker's missing-snippet
  blocking is as strict.
- **Apple Mail support at all** — a first-party-abandoned gap nobody else fills.
- **Native, dependency-free parsing** (CSV/TSV, .xlsx, .docx, .pdf scraping,
  Apple/iCloud Contacts, Outlook contacts) — broader native import than
  SerialMailer or eM Client.
- **Security engineering as a feature**: unit-tested AppleScript escaping and
  automatic HTML-escaping of merged values — a rigor story no lightweight
  competitor tells.
- **No subscription, no credits, no vendor quota** — the only limits are the
  user's own mail provider's.
- **Merge-field palette + CSV starter template** directly address the #1
  documented support issue across all tools (column-header/placeholder
  mismatch), plus the scriptable no-Mail dry run (`Tools/dry-run.sh`).

---

## 3. Competitive landscape (July 2026)

| Tool | Platform / model | Pricing | What to learn from it |
|---|---|---|---|
| **Direct Mail 8** (e3) | Native Mac app + vendor cloud ESP | Freemium; ~$20/mo or pay-per-email | Closest native-Mac rival, very active (AI wave 12/2025, v8.0 4/2026). Per-tag fallbacks, conditionals, adaptive throttling, timezone delivery — but hybrid-cloud, not private. |
| **MaxBulk Mailer 8.9** (Maxprog) | Native Mac+Win, own SMTP | $50–60 one-time | Conditional content, per-recipient attachments via merge-tag filenames, crash-recovery resume, self-hosted tracking option. |
| **SerialMailer 8.5** (Falkon Ware) | Native Mac, own SMTP | $45 one-time | Explicitly "privacy in mind, no tracking." Dry-run simulation, Smart Fields conditionals that can swap attachments, evaluates Excel formulas on import. |
| **eM Client 10.4** | Desktop client (Mac+Win), Mass Mail in Pro | ~$50–60 one-time | `{Variable[fallback]}` syntax; auto-escalates a multi-recipient send with variables into per-recipient sends to prevent token leaks. |
| **Word + Outlook merge** (+ MAPILab Toolkit, Win-only) | Desktop, own account | In M365; Toolkit ~$24+ | The incumbent HighRise replaces. Word: deepest offline conditional logic (9 merge rules, picture-switch formatters, ODBC sources). Natively lacks CC/BCC, attachments, per-recipient subjects — the #1 complaint HighRise can win on. |
| **Apple Pages 15** merge | Native Mac/iOS, free | Free | **Cannot send email at all** — documents/PDF only, Numbers-only input, no conditionals. Confirms the niche is open. |
| **YAMM** | Gmail/Sheets add-on, 10M+ users | Free–$50/yr | Sheet-as-dashboard status writeback, Drive attachment auto-matching, pre-send duplicate alert (2026), managed unsubscribe. Tracking runs on vendor servers. |
| **GMass** | Gmail extension + vendor cloud | $29.95–59.95/mo (2026 prices) | Power ceiling: quota-aware sending, 8-stage sequences, `{auto-first}` name inference, conditional content + spintax, behavior-based re-campaigns. Opposite privacy model. |
| **Mailmeteor** | Gmail/Outlook/Zoho, cloud | Free–$24.99/mo | The privacy-positioned cloud rival: send-only OAuth, aggregate-only tracking. Autopilot throttling, bounce/reply detection, sequences. |
| **Mailsuite** (ex-Mailtrack) | Gmail extension | Free–$9.99/mo | Automatic multi-day batch spreading (2,000/day) with zero user configuration — the throttling UX to imitate. |
| **Quicklution Mail Merge** | Google Docs/Sheets add-ons | ~$30/yr or $80 lifetime | Merge-to-PDF, Avery labels/envelopes/certificates — the print/document pipeline. Conditional fields via spreadsheet formulas. |
| **SecureMailMerge** | Outlook add-in (incl. Mac), local processing | Free personal; ~$10/user/mo | **The architectural twin.** Local-only data processing, zero tracking, full Liquid templating, per-recipient attachments, many-to-one merge, drafts-with-delayed-delivery kill switch. Proof the positioning sells. |
| **Mail Merge 365** | Outlook add-in + vendor relay | ~€108/yr | Same vendor's cloud/analytics sibling — a live A/B test of privacy vs tracking positioning. |
| **Thunderbird Mail Merge 11.5** | Free add-on | Free (GPL) | Randomized inter-message pause, draft-splitting "Mass Mail" mode, batch row-range resume, CSV/JSON/ODS/XLSX. |
| **Python mailmerge CLI 2.3** | Open-source CLI | Free (MIT) | Dry-run-by-default + limit-1-by-default double interlock; full Jinja2; Markdown→multipart authoring. |
| **Lemlist / Mailshake / Woodpecker** | Cloud cold-outreach SaaS | $29–109/user/mo | Feature upper bound (sequences, Liquid, warmup). Notably: **none supports file attachments** (they recommend hosted links) and all require vendor cloud — the two clearest openings for a local desktop tool. |

---

## 4. Verified recommendations

Each item below survived two independent checks: **(a)** the named competitors
really ship it today (per official docs), and **(b)** it is buildable inside
HighRise's architecture (Swift/SwiftUI, Apple SDK only, AppleScript automation,
no servers). Effort is relative to this codebase.

### P0 — table stakes (absence reads as broken)

| # | Feature | Who has it | Feasibility | Effort |
|---|---|---|---|---|
| 1 | Static attachments | Gmail native, GMass, YAMM, Mailmeteor, SecureMailMerge, MAPILab, Thunderbird, MaxBulk | Straightforward | Small |
| 2 | Fallback values `{{First Name\|there}}` | GMass, Mailmeteor, Woodpecker, SecureMailMerge (Liquid `default`), eM Client, Gmail native | Straightforward | Small |
| 3 | One-click test-send-to-self | YAMM, GMass, Mailmeteor, MaxBulk, SerialMailer, SecureMailMerge | Straightforward | Small |
| 4 | Scheduled send | GMass, Mailmeteor, YAMM, MAPILab, MaxBulk, Direct Mail, SecureMailMerge | Feasible **with caveats** (§5.2) | Medium |
| 5 | Quota-aware throttling (batch+pause, jitter, daily-cap warning) | GMass, Mailmeteor, MAPILab, SerialMailer, MaxBulk, Thunderbird, lemlist, Woodpecker | Straightforward | Small |
| 6 | Full-fidelity HTML in Apple Mail | All rivals deliver HTML — by owning the send path (§5.1) | Feasible **with caveats** (§5.1) | Medium |
| 7 | Per-run delivery report + results CSV export, re-run held rows | YAMM (sheet writeback), GMass, Mailmeteor, Direct Mail, MaxBulk, Woodpecker | Straightforward | Medium |
| 8 | Worksheet picker for multi-sheet .xlsx | Word (Select Table), SecureMailMerge, Thunderbird, YAMM/GMass/Mailmeteor (tab selection) | Straightforward | Small |

**Build notes (P0):**

1. **Static attachments** — the #1 complaint about native Word→Outlook merge, which
   lacks it. Add `attachments: [URL]` to the coordinator, `attachmentPaths` to
   `ComposedMessage`; both Mail and Outlook take `make new attachment` inside the
   existing `tell newMessage` block. Include a pre-send total-size warning
   (~10–25 MB) since oversized merges bounce silently.
2. **Fallback values** — the existing placeholder regex already captures
   `First Name|there` as one token; split on the first `|`. Keep
   `referencedFields` returning the base name so the missing-column warning and
   send-blocking stay keyed on the real column. **Block-by-default stays; a
   fallback is an explicit per-field opt-in** — pairing the two is best-in-market
   (stricter than everyone except Woodpecker, friendlier than a hard block alone).
3. **Test-send** — reuse the single-message pipeline with the chosen row's
   already-merged preview, recipient = self, optional `[TEST]` subject prefix.
   ReviewView already tracks a selected row.
4. **Scheduled send** — app-side only (see §5.2): snapshot the run
   (`ScheduledRun`: fire date, client, mode, frozen `ComposedMessage`s) and fire
   the existing send loop at the chosen time. This is also what makes the run
   editable/cancelable — nothing reaches Mail/Outlook until fire time.
5. **Throttling** — scaffolding exists (`perMessageDelay` slider, cancellable
   task). Add randomized jitter (Thunderbird-style humanized pause), batch+pause
   (e.g. 50 then 5 min), and provider presets with a daily-cap warning
   (personal Gmail 500/day, Workspace 2,000/day, Outlook.com ~300/day). For a
   send-through-your-own-account tool, protecting the user's primary mailbox
   from suspension is the single most important safety feature.
6. **Apple Mail HTML** — see §5.1 before committing. Recommended path: a spike
   on `.eml` draft injection for draft-first mode.
7. **Delivery report** — mostly assembly: `SendOutcome` already carries
   per-recipient sent/drafted/failed(reason); blocked rows carry
   `blockingReason`. Add timestamps, an "Export results…" CSV (reuse the
   unit-tested RFC-4180 writer), and "re-run the held rows after fixing data."
   This is the accountability half of campaign reporting and needs zero tracking.
8. **Worksheet picker** — parse `xl/workbook.xml` (+ rels) for sheet names via the
   existing ZipEntryReader/XMLParser pattern. **Also fixes a latent bug**: the
   current reader hardcodes `xl/worksheets/sheet1.xml`, which is not guaranteed
   to be the first tab after reordering/deletion in Excel — `workbook.xml`
   order is authoritative.

### P1 — high value, on-brand

| # | Feature | Who has it | Feasibility | Effort |
|---|---|---|---|---|
| 9 | Per-recipient attachments from a file-path column | YAMM, GMass, Mailmeteor, SecureMailMerge, MAPILab, Thunderbird (local paths), SerialMailer, MaxBulk | Straightforward | Medium |
| 10 | Conditional content (visual routing or if/else) | GMass, Word IF fields, Direct Mail, lemlist/Instantly/SecureMailMerge (Liquid), SerialMailer, MaxBulk Pro | Straightforward | Medium |
| 11 | Merge-field formatters (dates, currency, capitalization) | Word picture switches, MaxBulk, Direct Mail, SendGrid/Klaviyo-class ESPs | Straightforward | Medium |
| 12 | Persistent local do-not-contact list (addresses + domains) | GMass, Woodpecker, MaxBulk, Mailshake, Direct Mail (addresses) | Straightforward | Small |
| 13 | Per-recipient CC/BCC from columns + campaign Reply-To + BCC-me | YAMM, Mailmeteor, SecureMailMerge, Thunderbird, MaxBulk, Quicklution | Straightforward | Small |
| 14 | Duplicate-recipient detection with warning | GMass (silent auto-dedupe), YAMM (pre-send alert, 2026), lemlist, Direct Mail, Mailshake, SerialMailer | Straightforward | Small |
| 15 | Local no-reply detection → approved follow-up re-merge | Sequences: GMass, Mailmeteor Pro, Woodpecker, lemlist. Local variant is **unique to HighRise** | Feasible with caveats | Large |
| 16 | Pause mid-run + delayed-delivery review window | GMass (pause/edit), SecureMailMerge (drafts + delayed delivery), MaxBulk (crash-recovery resume) | Feasible with caveats | Small |

**Build notes (P1):**

- **(9)** The local-path variant is a perfect desktop fit: cloud rivals need Drive
  links; files here never leave the Mac. Mirror the existing `emailColumn`
  picker with an `attachmentColumn`; support `;`-separated multiple files and
  `~` expansion; **a missing file blocks the row** — extending the existing
  "never send a broken row" guarantee. Marketing note: lemlist, Mailshake, and
  Woodpecker don't support attachments *at all*.
- **(10)** Two viable shapes: a Liquid-subset grammar (power users know it) or
  Woodpecker-style visual routing — "rows where {{Field}} is non-empty get
  variant A, else B." **Recommend visual routing first**: covers the dominant
  case with no syntax to learn, matches the safety-first audience, and is pure
  template-engine work in the unit-tested core.
- **(11)** `{{Field|date:long}}`, `{{Amount|currency:USD}}`, `{{Name|capitalize}}`
  via Foundation formatters, including explicit Excel raw-serial-date handling —
  fixes the notorious "44927 instead of a date" problem at render time. Word
  solved this decades ago; most lightweight tools still haven't.
- **(12)** JSON store in `~/Library/Application Support/HighRise/`; suppressed
  rows surface in Review as skipped-with-reason (never silently invisible).
- **(13)** AppleScript sets CC/BCC/Reply-To on drafts in both clients. Per-recipient
  values are just `{{Field}}` placeholders in envelope fields — zero import
  changes. **BCC-yourself doubles as the privacy-honest delivery record** (the
  mailmerge CLI docs recommend exactly this).
- **(14)** Case-insensitive dedupe check at ingest, surfaced in the existing
  review flow. Duplicate sends embarrass the sender; this closes the last
  common self-inflicted failure mode.
- **(15)** The trigger ("no reply in N days") needs only local mailbox reading via
  the same AppleScript pattern the Outlook contacts importer already uses. A
  "nudge me, I approve each follow-up" flow delivers most sequence value with
  zero cloud. Caveats: requires campaign persistence first (see §6), inbox
  scanning over AppleScript is slow on large mailboxes, and it's
  legacy-Outlook-only on the Outlook side (§5.3).
- **(16)** Pause is ~80% built (cancellable task loop exists; add a pause gate).
  The delayed-delivery review window imitates SecureMailMerge's kill-switch
  pattern app-side: "sending begins in 5:00 — Abort." Abort granularity is one
  message (NSAppleScript is synchronous per message).

### P2 — differentiators worth considering

| # | Feature | Who has it | Feasibility | Effort |
|---|---|---|---|---|
| 17 | Merge-to-PDF (per-recipient personalized PDFs, optional password) | MAPILab (PDF+password), Quicklution, YAMM (Doc→PDF), AutoMailMerge | Feasible with caveats | Medium |
| 18 | Offline first-name inference from email address | GMass `{auto-first}` (cloud) | Straightforward | Small |

- **(17)** No mainstream tool ships this natively — it's a paid add-in everywhere —
  yet macOS has first-class PDF rendering (WKWebView print operation for
  paginated output; PDFKit password options). Personalized, locally generated,
  optionally encrypted PDF invoices/offer letters would *deepen* the privacy
  story and quietly cover the print/document use case Pages abandoned.
- **(18)** `john.smith@acme.com → John` via local-part parsing gated by a bundled
  public-domain name list. Offer **as a suggested fill in the blocked-row flow**,
  never an automatic substitution — the GMass idea minus the cloud.

---

## 5. Platform risks — decide with eyes open

**5.1 Apple Mail HTML (affects #6).** Mail's scripting dictionary exposes only a
plain-text `content` property — there is no HTML setter, and none of the 8
competitors that "deliver HTML" do it through Apple Mail; they all own the send
path (SMTP or API). The credible workaround for *draft-first* mode is `.eml`
injection: compose a full RFC 5322 `multipart/alternative` message and use the
long-stable `X-Uniform-Type-Identifier: com.apple.mail-draft` header so Mail
opens it as an editable draft. This is undocumented behavior — run a
**time-boxed spike** on current macOS before promising it; the honest fallback
is what the app does today (warn, and position Outlook for HTML campaigns).

**5.2 Scheduled send (affects #4).** Apple Mail's native Send Later (macOS 13+)
is absent from its AppleScript dictionary, and Outlook for Mac has no
scriptable deferred-delivery property (the README roadmap's assumption
conflates it with Windows COM's `DeferredDeliveryTime`). Scheduling therefore
runs app-side: **HighRise must be running and the Mac awake** (login item +
`NSBackgroundActivityScheduler`/power-assertion mitigations, and a clear UI
statement of the guarantee). That's materially weaker than cloud rivals — ship
it, but never imply the Mac can be off.

**5.3 "New Outlook" for Mac.** Microsoft's new Outlook has a drastically reduced
AppleScript dictionary; the existing send path, contacts import, and the
proposed no-reply scan fully work only in **legacy** Outlook. Document the
supported Outlook mode explicitly, detect and warn in-app, and treat deeper
Mail-side robustness as the strategic hedge while tracking Microsoft's
scripting roadmap.

---

## 6. Additional gaps from the completeness review

Flagged by a final "what did the benchmark miss?" pass. Not adversarially
verified like §4, but several are obvious wins — the first one arguably
belongs in P0:

1. **Saved templates / any persistence at all.** Every surveyed competitor has a
   reusable template library; HighRise currently loses template, list, and
   results on quit (nothing is written to disk). A small Codable store in
   Application Support (template library + last session autosave + campaign
   history) is also the prerequisite for follow-ups (#15) and re-run-held-rows
   (#7).
2. **Signature handling.** AppleScript-created drafts commonly omit or duplicate
   the account signature — this directly degrades the draft-first flow.
   Investigate per-client behavior and either set the signature explicitly or
   document the outcome.
3. **Sender identity.** Choosing the From account/alias per campaign
   (Mail AppleScript supports `sender`; Direct Mail/MaxBulk/SerialMailer all
   offer it). Pairs naturally with #13.
4. **Visible unsubscribe for bulk senders.** The §4 suppression list is
   internal-only. The privacy-honest variant: an optional `mailto:`-based
   unsubscribe footer + one-click import of those replies into the
   do-not-contact list. Never a hosted page (see §7).
5. **Import coverage.** Apple Numbers files (a Mac-first app that parses .xlsx
   but not .numbers is conspicuous), semicolon-delimited European CSVs, UTF-8
   BOM, non-UTF-8 encodings.
6. **macOS platform integration** — the moat only a native app has: Shortcuts
   actions, drag-and-drop import, a Services/Share extension, plus
   VoiceOver/localization audits.
7. **Document the no-tracking stance** as a deliberate decision (README +
   marketing), so its absence reads as a feature, not an oversight (§7).
8. **Benchmark follow-ups for a future pass**: ~~Gmail's built-in multi-send~~
   (now covered in §9), Daylite/Mailbutler (Mac CRM-lite), Mail Designer 365,
   LibreOffice merge, and the Shortcuts/AppleScript DIY path HighRise replaces.

---

## 7. Deliberate non-goals — protect the identity

Competitor features that would betray the architecture. Skipping these is a
decision, not a gap:

- **Open/click tracking** (pixels, link rewriting): needs vendor servers,
  increasingly broken anyway (Apple MPP false opens, ~9% bot clicks), growing
  EU legal risk. *"We physically cannot track" is the marketing line — protect it.*
- **Hosted unsubscribe pages / signup forms / server-side suppression sync** —
  the honest variant is `mailto:` + the local do-not-contact list (§6.4).
- **Bundled ESP / SMTP relays to exceed provider limits** — abandons the
  "your own account, your own Sent folder" model that defines the app.
- **Warm-up networks and inbox rotation** — server-side, ToS-gray spam
  infrastructure for an audience HighRise doesn't serve.
- **Cloud sync / team collaboration tiers** — requires a vendor backend.
- **Server-side campaign execution** (runs with the Mac off, drip
  autoresponders, open/click-triggered sends) — both the execution locus and
  the triggers conflict with the identity. Local scheduling while the app runs
  is fine; cloud orchestration is not.
- **Cloud AI personalization on recipient data** (server icebreakers,
  per-recipient remote images — which are literally tracking pixels). If AI is
  ever added: on-device only (Apple Intelligence), and first-class support for
  AI-generated columns users bring in their CSV.
- **Lead databases / email finders / LinkedIn scraping** — off-mission; users
  bring their own lists.
- **Read-receipt UX** — the feature privacy advocates find creepiest; its
  absence is contrast messaging.
- **Third-party email-verification APIs** — per-address checks leak the
  recipient list; keep validation local.

---

## 8. Suggested build order

Small, pure-Swift, unit-testable wins first; spikes before promises:

1. **Wave 1 — quick wins (all Small):** fallback values (#2) · worksheet picker
   + first-sheet bug fix (#8) · duplicate detection (#14) · test-send (#3) ·
   throttling upgrade (#5) · CC/BCC/Reply-To/BCC-me (#13) · do-not-contact
   list (#12) · static attachments (#1).
2. **Wave 2 — assembly (Medium):** persistence + template library (§6.1) ·
   delivery report + CSV export + re-run held rows (#7) · per-recipient
   attachments (#9) · merge formatters (#11) · conditional content, visual
   routing variant (#10) · scheduled send with honest caveats (#4).
3. **Wave 3 — spikes & flagships:** `.eml` HTML-draft spike for Apple Mail
   (#6, §5.1) · merge-to-PDF (#17) · follow-up detection (#15) · signature &
   sender-identity handling (§6.2–3) · name inference (#18) · macOS
   integration (§6.6).

---

## 9. Mass-market tier — the large-install-base benchmark (July 2026)

§3 profiled HighRise's direct competitors. This tier is different: the most
*successful* apps adjacent to the category — big install bases, strong public
ratings — studied not for feature parity (most are cloud ESPs HighRise should
not imitate, see §7) but for the **interaction patterns that made them easy for
millions of non-experts**. Install/rating figures are from marketplace listings
and G2 as of mid-2026; totals that vary by source are marked ~.

| Tool | Scale & rating signal | What its success teaches |
|---|---|---|
| **Mailchimp** (Intuit) | ~12M+ users (2.4M MAU); G2 ≈4.3–4.4, thousands of reviews; dominant SMB email share | The **campaign checklist page** (§10.2) — an email is 5 labeled rows (To / From / Subject / Send time / Content), each with an Edit button and a checkmark; Send stays disabled until all pass. So core it's an API endpoint ("Send Checklist"). Home = personalized "recommended next steps," not stats. Import = Upload → Match → Organize → Tag wizard. Contact table has a per-row **status badge** (subscribed/cleaned/pending). |
| **Constant Contact** | ~600k SMB customers; G2 4.1 with **7,365 reviews**; "ease of use" cited in 1,000+ | Winter-2025 redesign doubled down on **personalized dashboard + "clear next steps"** and moved everything into a collapsible left rail. Contacts got pinned fields, quick inline-edit views, and a **status column** — the industry keeps converging on status-in-the-row. |
| **Brevo** (ex-Sendinblue) | 500k+ businesses; G2 ≈4.5 | **Modular left rail** ("apps" the user can add/remove — unused modules disappear), a Mailchimp-style single setup page per campaign, advanced options collapsed under "Additional settings," and a 3-item **onboarding checklist with progress** (authenticate → import → first send) that reviewers single out. |
| **HubSpot** (free CRM + marketing email) | 238k+ paying customers; G2 4.4 over **35k+ reviews** | The reference **contacts table**: saved views as tabs, filter chips, "Edit columns," checkbox bulk actions. Import wizard with auto-mapped columns, inline "create property"/"don't import," and a **downloadable per-row error file (code + reason)**. Pre-send **"Review reasons" exclusion accounting**: exactly how many will receive it, and an itemized list of why the rest won't — HighRise's blocked-rows concept, presented as accounting. |
| **YAMM** | **10M+ Marketplace installs, 4.8/5 (19k+ reviews)** | **The spreadsheet IS the dashboard**: one dialog + one writeback status column added to a table users already know. Test-send is a button *inside* the send dialog. Its entire UI surface is smaller than most tools' settings screens — that is the product. |
| **Mailmeteor** | 6M+ users, **4.9/5 (11.5k+ reviews)** | The citable step-count case study: they measured the send flow at 5 steps and **redesigned it to 3**, making templates optional for the fast path. Preview-per-recipient ("Preview emails") before send is the marquee safety feature. |
| **GMass** | G2 **4.8/5 (~1,270 reviews)** | Inbox-as-dashboard: reports are Gmail labels; all power features live behind one expandable settings box next to Send. Maximum capability behind minimum resting UI. |
| **Gmail multi-send** (built-in) | free baseline for a billion-user product | Mode is *loudly* signaled (compose turns purple; Send becomes "Continue"); the confirmation step offers exactly three choices — **Cancel / Send Preview (test-to-self) / Send All**. Test-send as a peer of Send, not a buried menu item. |
| **Word/Outlook merge wizard** | bundled with Office; the incumbent pattern | Dual-mode access to one engine: a 6-step novice wizard *and* the Mailings ribbon laid out left-to-right in workflow order for experts. Record-by-record preview before commit; "Edit Recipient List" had per-row include checkboxes, dedupe and validation 20 years ago. |
| **Direct Mail 8** (Mac) | top-rated native Mac campaign app (MAS ≈4.7) | The native-Mac reference layout: **sidebar of nouns (Messages / Addresses / Reports) + content area + inspector**. No wizard — navigation by object, campaign = message + list + send. |

---

## 10. Dashboard & layout patterns — making HighRise feel intuitive

Cross-tool patterns from §9 (each shipped by 3+ successful products), mapped to
HighRise's current Home → Compose → Contacts → Review → Send flow. The recurring
theme: **the market's most-loved tools show state in the row, put verbs on the
home screen, and make the last screen an accounting of exactly what will
happen.**

1. **Home = recommended next actions, not a menu.** (Mailchimp, Constant
   Contact, Brevo.) HighRise's Home hub should lead with contextual verb cards:
   "Resume your draft," "3 rows are held back — fix them," "Re-run the 2 failed
   sends," "Import a list to preview this template for real." The four stage
   tiles stay, but the *next step* is computed and put first (the `NextStep`
   service already exists — promote it to the hub's primary card).
2. **Review as a send-readiness checklist.** (Mailchimp's checklist page —
   the single most-imitated layout in the category; Brevo's setup page;
   HubSpot's review panel.) Recast Review's summary as labeled checklist rows —
   Template ✓ · Recipients ✓ · Attachments ✓ · Envelope ✓ · Throttle ✓ ·
   **42 of 50 ready** — each row jumping to its editor, with Send disabled until
   green. `SendReadiness`/`ReviewSummary`/`PreSendReport` already compute all of
   it; this is presentation, not new logic.
3. **Status badge in the contact row.** (Mailchimp, Constant Contact, YAMM,
   HubSpot.) The import preview table should carry a per-row status chip —
   Ready / Held: missing {{Company}} / Duplicate / Suppressed / Repaired —
   instead of the current binary valid-email icon. List health stays in the
   rail as aggregates; the *rows* answer "which ones?".
4. **Pre-send exclusion accounting.** (HubSpot's "Review reasons"; Word's
   include-checkboxes; Gmail's forced Cancel/Preview/Send All.) The Send screen
   should lead with "**42 of 50 will receive this**" plus an itemized held-back
   list (already computed as `blockedPreviews` + `HeldReasons`) and put
   **Send Test to Myself** visually beside Send All, Gmail-style.
5. **Keep the user's spreadsheet recognizable.** (YAMM/Mailmeteor — 16M
   combined installs on this one idea.) Show imported columns in their original
   order with the status chip appended, and offer the results CSV as "your file
   plus a Status column" (the `RunReportExporter` already writes per-recipient
   outcomes — align its column order with the import).
6. **Onboarding checklist with progress.** (Brevo, Mailchimp.) Extend the
   welcome tour into a persistent, dismissible 3-item checklist on Home:
   compose (or pick a starter) → import (or load the sample) → test-send to
   yourself. Each item checks itself off from real state.
7. **Progressive disclosure of send options.** (Brevo's "Additional settings,"
   GMass's settings box, Mailmeteor's advanced options.) Throttle, provider
   quota, scheduling, sender identity, and unsubscribe-footer settings collapse
   behind one "Sending options" disclosure; the resting Send screen shows only
   client, mode, and the accounting from #4.
8. **Filter to problem rows.** (HubSpot filter chips; OpenRefine facets.) One
   toggle on the import/review tables: "Show only rows needing attention."
9. **Import = Upload → auto-match → review, never pre-clean-your-file.**
   (Mailchimp, HubSpot, Attio, Pipedrive — universal.) HighRise's auto-detected
   email/attachment columns + the §11 cleanup pipeline already implement this;
   keep any future column-mapping UI to the same shape: auto-map, show the
   guess, one click to override.
10. **Loud mode distinction for live sending.** (Gmail's purple compose.) When
    mode = Send (not Draft), tint the Send screen's header/CTA distinctly so
    "this will really email people" is unmistakable.

Priority order for the "not intuitive enough" complaint: **#1, #2, #3, #4**
first (they re-present existing computed state — low risk, high leverage), then
#6/#7, then the rest.

---

## 11. Contact-import cleaning — benchmark and what HighRise now ships

Second-pass study of how successful products handle **large, badly formatted
contact/company imports** (Mailchimp, HubSpot incl. Breeze AI, Salesforce
Data Import Wizard + matching rules, Pipedrive, Attio, Apollo, ZeroBounce/
NeverBounce, Excel Power Query, Google Sheets Smart Cleanup, OpenRefine,
Google Contacts "Merge & fix"). The industry consensus is a **three-tier
severity model**, and it is exactly the shape shipped in `ImportCleaner`:

| Tier | Industry practice | HighRise (shipped) |
|---|---|---|
| **Auto-apply silently-safe fixes** | HubSpot lowercases emails and trims names on entry; NeverBounce strips bad syntax/duplicates pre-billing; ZeroBounce removes a stray leading period; everyone trims | Whitespace/invisible-character scrub (incl. NBSP — which Excel TRIM and Sheets "Trim whitespace" *don't* handle), spreadsheet junk tokens (`#N/A`, `NULL`, `-`) cleared to empty so rows are **held, not sent broken**, repeated header rows dropped, mechanical email repairs (`mailto:`, `Name <addr>`, wrapping quotes/brackets, stray edge punctuation, inner spaces) — each fix counted and disclosed with before→after examples |
| **Suggest riskier fixes, one click, never automatic** | The industry's hard line: **nobody auto-corrects typo domains** — Mailchimp *removes* gmail-typo addresses outright; ZeroBounce only *suggests* (`did_you_mean`). Sheets Smart Cleanup and OpenRefine clustering are accept-per-suggestion. HubSpot Breeze proposes casing fixes incl. particle names (MacDonald, DeSantos) behind accept/reject | Misspelled mail domains (`gmial.com` → `gmail.com`, dead `.con`/`.cmo` TLDs, comma-for-dot), SHOUTING-CASE / all-lowercase names & companies with particle-aware title casing (O'Brien, McDonald, van der Berg, Ford III), and `Last, First` → `First Last` flips (with company/generational-suffix stop-words) — each with count + examples, applied per suggestion |
| **Block what can't be fixed, with the reason** | HubSpot kills the row on `INVALID_EMAIL` but merely blanks a bad field otherwise ("field-level degradation"); Pipedrive compiles skipped rows into a reason-coded **skip file**; Mailchimp reports categorized counts | Unchanged core behavior: invalid/missing emails and unresolved `{{fields}}` hold the row back with a per-row reason (`HeldReasons`), and the results CSV exports the accounting |

Where HighRise now *leads* the pack:

- **`mailto:` / `Name <addr>` stripping** is documented industry *pre-verification
  practice* but no major CRM or merge tool ships it natively — HighRise does.
- **Particle-aware name casing** ships only in HubSpot's paid, cloud-AI Breeze
  feature; HighRise's is a deterministic exception list, offline, unit-tested.
- **Undo is total and instant**: "Show Original Data" restores the untouched
  import (Mailchimp gives a 24-hour window on additions only; most tools offer
  nothing).
- Everything runs locally on any list size — no upload, no row quotas.

Still open (candidates for a later wave, in rough value order):

1. **Role-address flagging** (`info@`, `sales@`, `admin@`) — flag-only, as
   ZeroBounce/NeverBounce do; Mailchimp's silent *removal* is the anti-pattern.
2. **Import-stage skip/error file** — Pipedrive-style reason-coded CSV of rows
   skipped at import (no email), complementing the existing post-run report.
3. **Fuzzy duplicate clustering** — OpenRefine fingerprint/Salesforce-style
   matching (suffix-normalized company compare, nickname pairs Bob≡Robert) as a
   *suggestion* group; note Salesforce normalizes only inside the comparator and
   never rewrites stored values — the safe pattern to copy.
4. **Per-column profiling** — Sheets-style column stats (top values, anomalies)
   in the health rail, powering "inconsistent value" suggestions.
5. **Attio-style per-value review** — the modern high bar: a raw-vs-mapped diff
   view with in-place edit before commit; heavyweight, only worth it if lists
   regularly exceed what the suggestion cards handle.
6. **Enrich-instead-of-clean** (Apollo/Breeze fill gaps from a vendor DB) —
   requires a cloud lookup of recipient data: a §7 non-goal, listed here only to
   record the decision.

---

*Method: 54 research/verification agents; 12 competitor tool groups profiled +
4 cross-tool feature surveys (personalization; sending & safety; tracking &
follow-up; attachments & data); findings gap-analyzed against the current
codebase; all 18 recommendations fact-checked against official vendor
documentation and feasibility-reviewed against the HighRise sources; a final
completeness critique produced §6. Claims reflect vendor documentation as of
July 2026. Second pass (§9–§11): two further research sweeps over (a) dashboard
layouts, information architecture, and onboarding of the mass-market tools and
(b) import-cleaning behavior across CRMs, ESPs, verification services, and
spreadsheet tooling — verified against vendor help centers and marketplace
listings as of July 2026; install/rating figures quoted from the marketplaces
(Google Workspace Marketplace, Mac App Store) and G2 and marked ~ where sources
disagree.*
