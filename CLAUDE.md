# HighRise — project notes for Claude

Native macOS mail-merge app (Swift + SwiftUI, Apple SDK only). Personalizes an
email template per recipient and drafts/sends via Apple Mail or Outlook through
AppleScript automation — no SMTP, no servers, no third-party runtime deps.
Read `README.md` first; this file captures repeatable workflows.

## Environment reality
- This repo is often worked on from a **Linux container with no Xcode, no Mac,
  and no image tools** (`sips`/`iconutil`/ImageMagick absent). The Swift app
  cannot be built or run here; Mac-only steps are authored here and run on a Mac.
- XcodeGen generates the project at the repo root (`xcodegen generate`), matching
  `.github/workflows/ci.yml`. The README's `cd HighRise` is stale.

## App icon workflow  (macOS / iOS / iPadOS / Windows)
Everything lives in `Icons/` and never touches the compiled target until wired,
so it can't break CI before the artwork exists.

1. **Master artwork** lives on the user's Mac at
   `/Volumes/Satechi/HenSolutions/Apps/HighRise/HighRise iCons` (an external
   drive — not visible from the Linux container, not committed to the repo).
   The icon source is `HighRise App iCon 1280x768.jpg` (landscape skyline JPEG);
   the two `HighRise Icon …720.jpg` files are wide logo banners, NOT icon art.
2. **Generate** on the Mac (source is landscape + JPEG, so the script
   square-crops it; `--crop left|right|center` picks which part to keep):
   ```sh
   ICONS="/Volumes/Satechi/HenSolutions/Apps/HighRise/HighRise iCons"
   ./Icons/make-icons.sh --macos "$ICONS/HighRise App iCon 1280x768.jpg"
   ```
   `make-icons.sh` resizes via `sips` (Windows `.ico` + anchored crop need
   ImageMagick). JPEG has no alpha, so macOS gets a full square tile, not the
   transparent-margin squircle (a PNG-with-alpha master would fix that). It
   writes:
   - `Icons/AppIcon-macOS.appiconset/` — 16–512 @1x/@2x PNGs + Contents.json
   - `Icons/AppIcon-iOS.appiconset/` — single 1024 universal (iPhone+iPad) + Contents.json
   - `Icons/windows/HighRise.ico` — 16/24/32/48/64/128/256
3. **Framing rules** (wrong framing looks broken):
   - macOS: rounded-square **glass** art *with* transparent margins (drawn as-is).
   - iOS/iPadOS & Windows: **full-bleed opaque square** (OS masks corners).
4. **Wire macOS** (full steps in `Icons/README.md` §3): copy
   `Icons/AppIcon-macOS.appiconset` → `HighRise/Assets.xcassets/AppIcon.appiconset`,
   add `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` to `project.yml` and
   `CFBundleIconName = AppIcon` to `Info.plist`, then `xcodegen generate`.
5. **Liquid Glass**: a real `Icons/HighRise.icon` (Icon Composer) exists and
   **builds clean on Xcode 27** locally. It's **staged out of the build**: the
   hosted CI/release runners only have **Xcode 26.3**, whose `actool` *crashes*
   compiling a 27-authored `.icon`. So the shipping icon is the static
   `AppIcon.appiconset` (same 2048px master) — keeps all pipelines green. Flip
   to the `.icon` (move into `HighRise/`, retire the catalog, point
   `ASSETCATALOG_COMPILER_APPICON_NAME`/`CFBundleIconName` at `HighRise`) once
   GitHub runners ship Xcode 27 GA, or for a local-only Xcode 27 build. The CI
   `Select Xcode 26+` guard already prefers the newest 26–29 on the runner.
   Exact flip steps in `Icons/README.md`.

## iOS companion (`HighRiseMobile`)
A second XcodeGen target, `HighRiseMobile` (platform iOS, scheme
`HighRiseMobile`), added because AppleScript/Apple Events — how the macOS app
drives Mail/Outlook — don't exist on iOS. It reuses the shared Foundation-only
import/merge files (`Contact`, `EmailTemplate`, `RecipientTable`, `CSVParser`,
`EmailValidator`, `TemplateMergeEngine`, `MergeValueFormatter`,
`ImportPipeline`, `ImportCleaner`, `ContactDataFiller`, `NameInference`,
`EnrichmentProvider`, `ApolloEnrichmentProvider`, `EnrichmentEngine`,
`EnrichmentKeyStore`, `DuplicateDetector`, `MarkdownToHTML`,
`FieldSynonyms`, `TemplateVariant`, `Greeting`, `NextStep` — each listed
individually as a source under both targets in `project.yml`, not moved into
a package) and hands each recipient to `MFMailComposeViewController` instead:
the user reviews and taps Send themselves, one at a time, so there's no
unattended batch send on iOS. `HighRiseMobile/Views/HomeView.swift` is a
smaller version of the macOS Home dashboard (same `Greeting`/`NextStep`
logic, no sending-from picker/scheduled-send/saved-templates/do-not-contact —
none of those exist on iOS). The iOS Import screen surfaces the same
`ContactDataFiller` missing-data fill proposals as the Mac import screen
(tap-to-apply rows + Fill All; `MobileCoordinator` retains the raw table and
replays accepted fills through `ImportPipeline.run`, mirroring the macOS
coordinator's `remapContacts`). See "Using it on iOS" in `README.md` for the
user-facing summary and `HighRiseMobile/HighRiseMobileApp.swift` for the
flow. CI builds+tests it via the `Test iOS app` step in `ci.yml`, picking
whatever simulator destination
the runner reports rather than hardcoding a device name.

**Universal Purchase**: `HighRiseMobile`'s `PRODUCT_BUNDLE_IDENTIFIER` is
deliberately `com.bryansnotes.highrise` — the *same* bundle ID as the macOS
`HighRise` target, not its own. That's what lets both platforms ship under
one App Store Connect app record ("HighRise") as a Universal Purchase app,
rather than iOS needing a separate bundle ID/app record/listing.

**Distribution**: `release.yml`'s `release-ios` job builds + uploads
`HighRiseMobile` to TestFlight on the same tag-push/manual triggers as the
macOS release job, via `xcodebuild -exportArchive -destination upload`
(no altool/fastlane). It needs iOS-specific secrets (`IOS_DISTRIBUTION_CERTIFICATE_BASE64`,
`IOS_P12_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`) on top of the ones the
macOS job already needs — see the secrets block at the top of `release.yml`.
**This requires one-time manual setup only the owner can do** (add the iOS
platform to the existing "HighRise" App Store Connect app record — no new
bundle ID or app record needed, since it reuses `com.bryansnotes.highrise` —
generate an Apple Distribution cert + provisioning profile for that bundle
ID/iOS platform) — no session here has a Mac or Apple Developer account
access to do this. Until those secrets exist, the job detects they're
missing and skips itself rather than failing the workflow; don't treat that
skip as a bug.

## Other repeatable workflows
- **No-Mail dry run**: `./Tools/dry-run.sh [list.csv]` compiles the real
  Foundation-only core and prints the AppleScript each recipient would produce
  (+ why blocked rows are held back). Sample: `Examples/sample-recipients.csv`.
- **Release / notarization**: `.github/workflows/release.yml` (tag `v*` or manual)
  signs with Developer ID, notarizes via `notarytool`, staples, publishes the zip.
  Required secrets are documented in the workflow header and README.
- **Sandboxed Mac App Store variant**: see `MAS_VARIANT_PLAN.md` for the full
  plan and status. Implemented as a second XcodeGen target, `HighRise-MAS`
  (same `HighRise` sources; sandbox entitlements in
  `HighRise/HighRise-MAS.entitlements`; `MAS_BUILD` gates Outlook out; no
  `PRODUCT_NAME` set — it would collide with the main target's Swift module
  name). The in-process ZIP reader is done and benefits the Developer ID
  build too; the one open item is the Mail-automation-under-sandbox spike
  (send vs. draft-only), testable only on a real Mac. **Archive the
  `HighRise-MAS` scheme for Mac App Store uploads** — the plain `HighRise`
  scheme is the unsandboxed Developer ID build and fails App Store
  validation by design.
- **Windows companion**: `Windows/HighRise-Merge.ps1` re-implements the CSV →
  `{{merge}}` → draft/send pipeline against classic Outlook via COM (docs in
  `Windows/README.md`). It mirrors `TemplateMergeEngine`/`MergeValueFormatter`/
  `EmailValidator` semantics — keep them in sync when merge behavior changes.
  Constraints: must stay Windows PowerShell 5.1-compatible **and pure ASCII**
  (5.1 misreads UTF-8 `.ps1` files without a BOM; symbols like € are built via
  `[char]0x20AC`). Test from any OS with `-DryRun` (works under Linux `pwsh`,
  no Outlook needed); CI's `windows-dry-run` job runs it under real 5.1 + 7.

## Conventions
- Branch for this work: `claude/ios-app-feasibility-o929df`.
- **Work ONLY in the primary clone (`~/HighRise` on the Mac mini).** The copy
  at `/Volumes/Satechi/HenSolutions/Apps/HighRise` (external drive) is a stale
  July-2026 snapshot used by an earlier, now-archived agent. On 2026-07-17 a
  force-push of `main` from that lineage wiped PRs #48–#57 (restored the same
  day by a history-reuniting merge) and briefly changed the app's bundle ID to
  `com.hensolutions.HighRise-G2`. Never build from, commit in, or push from
  that folder; never force-push `main`; and the only shipping bundle ID is
  `com.bryansnotes.highrise` (shared across macOS + iOS for Universal
  Purchase).
- **App-icon: static `AppIcon.appiconset`, not the Liquid Glass `.icon` (owner
  decision, reversed 2026-07-12).** `project.yml`/`Info.plist` previously
  pointed `ASSETCATALOG_COMPILER_APPICON_NAME`/`CFBundleIconName` at the
  Liquid Glass `HighRise.icon` (Icon Composer). That's reverted: App Store
  Connect's product-page icon extraction doesn't pull a marketing icon from
  that newer format — a real Mac App Store submission built with it went
  through review with **no icon showing on the store listing**. The static
  `HighRise/Assets.xcassets/AppIcon.appiconset/` (real PNGs, generated from
  `Icons/AppIcon-macOS.appiconset`) is the shipping icon again. `Icons/HighRise.icon`
  (moved to `HighRise/HighRise.icon`) stays in the repo for a future retry once
  Apple's App Store Connect pipeline supports extracting from `.icon` bundles —
  don't delete it, just don't wire it back in without re-confirming that support
  exists.
- **Online enrichment ("Find & Fill Online")** is the app's single, deliberate
  exception to "nothing leaves the machine": `EnrichmentEngine` +
  `ApolloEnrichmentProvider` (user's own Apollo API key, Keychain-stored via
  `EnrichmentKeyStore`) look up missing emails/names/titles/websites, strictly
  user-triggered, results are reviewable proposals, valid emails are never
  overwritten. Still zero third-party deps (plain URLSession). The MAS
  sandbox variant carries `com.apple.security.network.client` for this. A
  future web-search or other-vendor source should conform to
  `EnrichmentProvider` rather than adding a parallel path. Do NOT scrape
  LinkedIn directly (ToS); Apollo is the sanctioned route to that data.
- AppleScript string escaping (`AppleScriptBuilder.stringLiteral`) is the app's
  security boundary — keep it unit-tested.
- Never leak a raw `{{placeholder}}` to a recipient; merge blocks unresolved rows.

## Working preferences (owner-approved)
**Standing, blanket, permanent approval** (reaffirmed by the owner multiple
times): proceed autonomously through the full build loop for this project
without pausing for per-step confirmation — reading/searching the repo, editing
code, `xcodegen generate`, `swift`/`xcodebuild`, committing, pushing to the
feature branch, and opening/updating draft PRs. Keep moving through
implement → test → push → draft PR → confirm CI → build the next thing on merge,
and only stop to ask when something is genuinely destructive, irreversible,
outside this repo, or a real design fork. Do not re-ask for permission to run
this ordinary dev work — it is granted.

**Pre-approved commands/tools (ALWAYS ALLOW — owner-confirmed):**
These run with **no permission prompt**: `permissions.defaultMode` is `"auto"`
and every entry below is in `permissions.allow` (see `.claude/settings.json` and
`.claude/settings.example.json`, which carry the identical list):
- `git` — all subcommands, incl. `commit`, `commit --allow-empty`, `push -u`,
  `fetch`, `checkout -B`, `pull`, `log`, `status`, `diff`, `add`.
- `xcodegen`, `swift`, `swiftc`, `xcodebuild`.
- `npm`, `npx`, `pnpm`, `python3`.
- `ffmpeg`, `ffprobe`, `apt-get install`, `brew`.
- File tools: Read, Edit, Write, Glob, Grep.
- MCP: the GitHub server (`mcp__github__*` — PRs, CI, logs, re-runs) and the
  scheduling server (`mcp__Claude_Code_Remote__*` — triggers/check-ins).
This mirrors `.claude/settings.example.json`; run any of these without asking.

**How that approval is actually enforced (so it never has to be re-litigated):**
the Claude Code harness gates commands via settings files, and *only the owner*
can widen them — an agent cannot self-authorize broader access (writing its own
`.claude/settings.json` is blocked by design). To stop approval prompts:
- **This repo, on a Mac:** `cp .claude/settings.example.json .claude/settings.json`
  (the example carries the full pre-approved allow-list for this project).
- **Every repo, permanently:** put the same `permissions.allow` block in the
  user-level `~/.claude/settings.json` so it applies to all projects/sessions.
- **This web environment:** permissions come from the Claude Code web
  environment config (already permissive here — nothing prompts the agent).
