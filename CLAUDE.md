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

## Other repeatable workflows
- **No-Mail dry run**: `./Tools/dry-run.sh [list.csv]` compiles the real
  Foundation-only core and prints the AppleScript each recipient would produce
  (+ why blocked rows are held back). Sample: `Examples/sample-recipients.csv`.
- **Release / notarization**: `.github/workflows/release.yml` (tag `v*` or manual)
  signs with Developer ID, notarizes via `notarytool`, staples, publishes the zip.
  Required secrets are documented in the workflow header and README.
- **Windows companion**: `Windows/HighRise-Merge.ps1` re-implements the CSV →
  `{{merge}}` → draft/send pipeline against classic Outlook via COM (docs in
  `Windows/README.md`). It mirrors `TemplateMergeEngine`/`MergeValueFormatter`/
  `EmailValidator` semantics — keep them in sync when merge behavior changes.
  Constraints: must stay Windows PowerShell 5.1-compatible **and pure ASCII**
  (5.1 misreads UTF-8 `.ps1` files without a BOM; symbols like € are built via
  `[char]0x20AC`). Test from any OS with `-DryRun` (works under Linux `pwsh`,
  no Outlook needed); CI's `windows-dry-run` job runs it under real 5.1 + 7.

## Conventions
- Branch for this work: `claude/tool-feature-benchmarking-m241ea`.
- **App-icon CI policy (owner decision):** keep the Liquid Glass `HighRise.icon`
  wired in even though CI's Xcode 26.3 `actool` *intermittently crashes* on it
  (`CompileAssetCatalogVariant` failure). On such a failure, **re-run the CI
  job** — it usually passes — and do NOT revert to the static
  `AppIcon.appiconset` or treat it as a code bug. The owner chose the nicer icon
  over the documented always-green static fallback. Only a failure that is *not*
  the icon crash indicates a real problem.
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
