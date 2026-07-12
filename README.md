# HighRise

A native macOS app that personalizes an email template against a list of
recipients and creates or sends one message per recipient through **Apple Mail**
or **Microsoft Outlook** — no SMTP credentials, no servers, no third-party
runtime dependencies.

Built to the Bryan's Notes stack rules: Swift + SwiftUI, Apple SDK only,
`os.Logger` logging, Swift Testing.

---

## What it does

1. **Compose** an email template (plain text or HTML) with `{{Field}}` merge
   placeholders — `{{Name}}`, `{{Company}}`, or any column from your list.
2. **Import recipients** from any of:
   - CSV / TSV files — delimiter (comma/semicolon/tab), a UTF-8 BOM, and
     non-UTF-8 encodings are handled automatically
   - Excel `.xlsx` files (parsed natively; multi-sheet workbooks show a picker)
   - Word `.docx` / PDF files (best-effort address scraping)
   - your iCloud / Mac **Contacts**
   - **Outlook** contacts (via automation)
   - (Apple **Numbers** files can't be read directly — export to CSV first; the
     app tells you so.)

   Messy exports are **auto-tidied on import**: stray/invisible whitespace,
   spreadsheet junk (`#N/A`, `NULL`, `-`), repeated header rows, and mangled
   addresses (`mailto:`, `Name <addr@x.com>`, stray punctuation) are repaired
   mechanically — every fix disclosed on the import screen and undoable in one
   click ("Show Original Data"). Riskier repairs — misspelled mail domains
   (`gmial.com`), ALL-CAPS names/companies, `Last, First` name order — are
   *suggested* with counts and examples, applied only when you click. Try it:
   `Examples/messy-recipients.csv`.
3. **Review** every personalized message. Recipients with missing data or an
   invalid address are flagged and excluded automatically.
4. **Send** — *draft-first by default*: each message is created in your client's
   Drafts so you can eyeball and send them yourself (no per-email prompt). An
   explicit "Send immediately" mode is available behind a confirmation.

## Merge syntax

Wrap any column name in double braces: `Hi {{FirstName}}, I wanted to reach out
about {{Company}}…`. Matching is case- and whitespace-insensitive (`{{ company }}`
≡ `{{Company}}`). If a recipient is missing a field the template uses, that
message is blocked from sending rather than going out with a blank or a literal
`{{…}}`.

**Filters.** After a pipe you can add filters, chained left to right:

- **Fallback** for empty values: `{{FirstName|there}}` uses "there" when the row
  has no value (and `{{FirstName|}}` renders nothing) instead of blocking. Written
  in full this is the `default:` filter — `{{FirstName|default:there}}`.
- **Dates**: `{{Renewal Date|date:MMMM d, yyyy}}` reformats ISO, common written
  dates, and even Excel's raw serial numbers (the notorious `46195`).
- **Currency / numbers**: `{{Amount|currency:USD}}` → `$24,500.00`;
  `{{Seats|number}}` groups digits.
- **Casing**: `upper`, `lower`, `capitalize`, and `fixcaps` (repairs ALL-CAPS
  names like `JORDAN AVERY` → `Jordan Avery`); also `trim`.

Filters combine: `{{First Name|there|capitalize}}` falls back to "There". A value
that can't be parsed (e.g. a non-date in a `date:` filter) passes through
unchanged. In HTML templates, substituted values — field data, fallbacks, and
formatted output alike — are HTML-escaped automatically.

---

## Building (requires a Mac with Xcode)

This repo carries source only; the Xcode project is generated with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) so it never goes stale:

```sh
brew install xcodegen
cd HighRise
xcodegen generate
open HighRise.xcodeproj
```

Then set your signing team (Xcode ▸ Signing & Capabilities, or `DEVELOPMENT_TEAM`
in `project.yml`) and build/run. To run the tests:

```sh
xcodebuild test -scheme HighRise -destination 'platform=macOS'
```

> **Note:** The code in this branch was authored in a Linux CI environment
> without Xcode, so it has **not yet been compiled**. Generate the project and
> run a build/test pass on a Mac before relying on it.

## Trying the pipeline without a build

You don't need to launch the app (or Mail) to see the merge work. `Tools/dry-run.sh`
compiles the real, Foundation-only core and prints the AppleScript that *would*
be sent for each recipient — and why blocked rows are held back. Nothing is sent:

```sh
./Tools/dry-run.sh                         # uses Examples/sample-recipients.csv
./Tools/dry-run.sh path/to/your-list.csv   # or your own list
```

The bundled `Examples/sample-recipients.csv` deliberately includes the tricky
cases (a quoted comma, embedded `""` quotes, HTML-special characters, a row
missing a referenced field, and an invalid address) so you can watch the
escaping and the send-blocking behave. To actually exercise Mail, pipe one of
the printed scripts to `osascript` — it'll create a real draft.

## Using it from Windows

The app itself is Mac-only, but the merge core is ported:
`Windows/HighRise-Merge.ps1` is a self-contained PowerShell script (nothing to
install — PowerShell ships with Windows) that runs the same CSV → `{{Field}}`
merge → **drafts in classic Outlook** pipeline via COM automation, with the
same template syntax, filters, and send-blocking rules. Draft-first by
default, `-DryRun` to preview without touching Outlook. Setup, examples, and
troubleshooting live in [`Windows/README.md`](Windows/README.md).

## Using it on iOS

`HighRiseMobile` is a separate iOS/iPadOS app target (`xcodebuild -scheme
HighRiseMobile`) sharing the macOS app's Foundation-only import/merge core
(CSV parsing, cleanup, `{{Field}}` templating). It's a smaller app by
necessity: iOS has no AppleScript/Apple Events, so there's no way to drive
Mail or Outlook unattended the way the macOS app does. Instead it hands each
ready recipient to `MFMailComposeViewController` — the user reviews and taps
Send themselves, one recipient at a time — so there's no batch/background
send or throttling on iOS. See `HighRiseMobile/HighRiseMobileApp.swift` for
the flow (import → template → review → send queue).

## App icons

`Icons/make-icons.sh` turns master artwork into app icons for macOS, iOS/iPadOS,
and Windows in one command (run on a Mac). See `Icons/README.md` for the framing
rules per platform and how to wire the macOS icon into the build.

## Releasing (Developer ID + notarization)

Distribution outside the Mac App Store needs a Developer ID-signed, notarized,
stapled build. `.github/workflows/release.yml` does this on a macOS runner:

- **Push a tag** like `v1.2.0` → it archives, signs, notarizes via `notarytool`,
  staples, verifies with `spctl`, and attaches the `.zip` to a GitHub Release
  (the version is taken from the tag).
- **Run it manually** (workflow_dispatch) → same build, uploaded as a run
  artifact instead of a release.

It expects these repository secrets: `BUILD_CERTIFICATE_BASE64` + `P12_PASSWORD`
(the Developer ID Application cert as a base64 `.p12`), `KEYCHAIN_PASSWORD`,
`DEVELOPMENT_TEAM`, and an App Store Connect API key for notarization
(`AC_API_KEY_BASE64`, `AC_API_KEY_ID`, `AC_API_ISSUER_ID`). To sign/notarize
locally instead, archive with `CODE_SIGN_IDENTITY="Developer ID Application"`
and `--options=runtime`, then `xcrun notarytool submit … --wait` and
`xcrun stapler staple`.

> First launch on any Mac still shows the one-time **Automation** (and, for
> address-book import, **Contacts**) consent prompts — notarization doesn't
> remove those, by design.

### iOS (`HighRiseMobile` → TestFlight)

The same workflow's `release-ios` job builds `HighRiseMobile`, signs it for
App Store distribution, and uploads straight to TestFlight via
`xcodebuild -exportArchive` with `destination: upload` (Apple-native, no
`altool`/fastlane). Same triggers as above (tag push or manual run).

It needs everything the macOS job needs (`DEVELOPMENT_TEAM` and the
`AC_API_*` App Store Connect API key) plus iOS-specific secrets:
`IOS_DISTRIBUTION_CERTIFICATE_BASE64` + `IOS_P12_PASSWORD` (an **Apple
Distribution** cert — not the Developer ID one used for macOS) and
`IOS_PROVISIONING_PROFILE_BASE64` (an App Store profile for
`com.bryansnotes.highrise.mobile`). Until those are set, the job detects
they're missing, logs a notice, and skips itself — it won't fail the
workflow or block the macOS release. See the secrets block at the top of
`.github/workflows/release.yml` for the full one-time App Store Connect
setup (registering the bundle ID, creating the app record, and generating
the certificate/profile — none of which can be done without a Mac and an
Apple Developer account).

## Permissions & sandboxing

HighRise runs **unsandboxed** and is meant for direct distribution
(Developer ID + notarization), not the Mac App Store, because two core features
require capabilities the App Sandbox forbids:

- **Automation** — driving Mail/Outlook via Apple Events. macOS will prompt for
  permission the first time (System Settings ▸ Privacy & Security ▸ Automation).
- **Office file import** — `.xlsx`/`.docx` are zip archives read via
  `/usr/bin/unzip`, which a sandboxed app can't spawn.

Reading your address book triggers the standard Contacts permission prompt.

---

## Architecture

```
Models/
  Contact.swift            Recipient with arbitrary fields + email
  RecipientTable.swift     Source-agnostic headers+rows (every importer's output)
  EmailTemplate.swift      Subject/body + {{Field}} parsing + plain/HTML format
  MailClient.swift         Apple Mail / Outlook + SendMode (draft/send)
  MergePreview.swift       Per-recipient merged result + sendability + outcome
Services/
  CSVParser.swift          RFC-4180-ish CSV → RecipientTable, email-column detect
  XLSXReader.swift         Native .xlsx (ZIP + XML) → RecipientTable
  DocumentTextExtractor.swift  .docx/PDF text + LooseContactExtractor scraping
  ContactsImporter.swift   Apple/iCloud Contacts → RecipientTable
  OutlookContactsImporter.swift  Outlook contacts via AppleScript
  ZipEntryReader.swift     Extracts one entry from a zip via /usr/bin/unzip
  EmailValidator.swift     Pragmatic address validation
  ImportCleaner.swift      Auto-fixes + suggested repairs for messy imports
  TemplateMergeEngine.swift  Pure {{Field}} substitution + HTML escaping
  AppleScriptBuilder.swift   Builds escaped AppleScript per client/mode
  MailSender.swift         Runs AppleScript (NSAppleScript), per-message delivery
  HighRiseCoordinator.swift  ObservableObject orchestrating the whole flow
Views/
  ContentView / TemplateEditorView / ContactsImportView / ReviewView / SendView

HighRiseMobile/               iOS/iPadOS target — see "Using it on iOS" above
  HighRiseMobileApp.swift     Entry point
  Coordinator/                MobileCoordinator (import/template/review state) + SendQueue
  Mail/MailComposeView.swift  MFMailComposeViewController wrapper (the iOS send mechanism)
  Views/                      ImportView / TemplateEditorView / ReviewQueueView / SendSessionView
  (reuses Contact, EmailTemplate, RecipientTable, CSVParser, EmailValidator,
   TemplateMergeEngine, MergeValueFormatter, ImportPipeline, ImportCleaner,
   DuplicateDetector, MarkdownToHTML, FieldSynonyms, TemplateVariant from
   above — each file is compiled into both the HighRise and HighRiseMobile
   targets per `project.yml`, not duplicated)
```

The I/O-free core (parsing, merging, escaping, validation) is fully unit-tested
in `HighRiseTests` — including the AppleScript escaping that is this app's
security boundary. `HighRiseMobileTests` covers the iOS send queue's state
machine (`SendQueue`).

## Known limitations / roadmap

- **Apple Mail + HTML:** Mail's AppleScript only reliably sets a plain-text body.
  HTML is full-fidelity in Outlook; the UI warns when Mail + HTML are combined.
  An **experimental** workaround exports one `.eml` draft per recipient (full
  HTML) that opens in Mail on double-click — verify on your Mac before relying
  on it.
- **Merge to PDF:** generate one personalized PDF per recipient (optionally
  password-protected) for invoices/letters — saved locally, sent by nobody.
- **Excel:** a multi-sheet workbook shows a worksheet picker (defaulting to the
  first tab in the workbook's declared order); one sheet is imported at a time.
- **Word/PDF:** address scraping is best-effort; always review before sending.
- **Attachments:** attach the same file(s) to every message (with a pre-send
  size warning), and/or a per-recipient file via an "attachment" column (a
  missing file holds that row back). Large files may still bounce.
- **Scheduled send:** a run can be scheduled for a future time, but scheduling
  runs *inside the app* (Apple Mail/Outlook expose no scriptable Send Later), so
  the Mac must be awake and HighRise open when it fires. An **undo** window is
  not yet implemented.
