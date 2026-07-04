# HighRise — Competitive Feature Benchmark

*Compiled July 2026. Sources: official product pages, docs, and changelogs of each
tool named below (verified against first-party sources; where a vendor page was
unreachable, verification used domain-restricted search over the vendor's own
site). Every recommendation in §4 was independently fact-checked ("do the named
competitors really ship this today?") and feasibility-reviewed against the
HighRise codebase.*

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
8. **Benchmark follow-ups for a future pass**: Gmail's built-in multi-send
   (the free baseline that sets user expectations), Daylite/Mailbutler
   (Mac CRM-lite), Mail Designer 365, LibreOffice merge, and the
   Shortcuts/AppleScript DIY path HighRise replaces.

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

*Method: 54 research/verification agents; 12 competitor tool groups profiled +
4 cross-tool feature surveys (personalization; sending & safety; tracking &
follow-up; attachments & data); findings gap-analyzed against the current
codebase; all 18 recommendations fact-checked against official vendor
documentation and feasibility-reviewed against the HighRise sources; a final
completeness critique produced §6. Claims reflect vendor documentation as of
July 2026.*
