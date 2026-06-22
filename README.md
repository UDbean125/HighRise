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
   - CSV / TSV files
   - Excel `.xlsx` files (parsed natively)
   - Word `.docx` / PDF files (best-effort address scraping)
   - your iCloud / Mac **Contacts**
   - **Outlook** contacts (via automation)
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
`{{…}}`. In HTML templates, field values are HTML-escaped automatically.

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
  TemplateMergeEngine.swift  Pure {{Field}} substitution + HTML escaping
  AppleScriptBuilder.swift   Builds escaped AppleScript per client/mode
  MailSender.swift         Runs AppleScript (NSAppleScript), per-message delivery
  HighRiseCoordinator.swift  ObservableObject orchestrating the whole flow
Views/
  ContentView / TemplateEditorView / ContactsImportView / ReviewView / SendView
```

The I/O-free core (parsing, merging, escaping, validation) is fully unit-tested
in `HighRiseTests` — including the AppleScript escaping that is this app's
security boundary.

## Known limitations / roadmap

- **Apple Mail + HTML:** Mail's AppleScript only reliably sets a plain-text body.
  HTML is full-fidelity in Outlook; the UI warns when Mail + HTML are combined.
- **Excel:** reads the first worksheet only.
- **Word/PDF:** address scraping is best-effort; always review before sending.
- **Attachments** and an **undo/scheduled-send** window are not yet implemented.
