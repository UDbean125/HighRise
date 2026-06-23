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
2. **Generate** on the Mac:
   ```sh
   ./Icons/make-icons.sh --macos "<square-glass-icon>.png" --ios "<full-bleed-square>.png"
   ```
   `make-icons.sh` resizes via `sips` (Windows `.ico` needs ImageMagick). It
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
5. **Liquid Glass**: the glass look is baked into the artwork (works on macOS 14+).
   True *dynamic* Liquid Glass = Apple **Icon Composer** `.icon`, which needs
   Xcode 26 + a higher deployment target — a deliberate future upgrade.

## Other repeatable workflows
- **No-Mail dry run**: `./Tools/dry-run.sh [list.csv]` compiles the real
  Foundation-only core and prints the AppleScript each recipient would produce
  (+ why blocked rows are held back). Sample: `Examples/sample-recipients.csv`.
- **Release / notarization**: `.github/workflows/release.yml` (tag `v*` or manual)
  signs with Developer ID, notarizes via `notarytool`, staples, publishes the zip.
  Required secrets are documented in the workflow header and README.

## Conventions
- Branch for this work: `claude/magical-mendel-11m60a`; PR #1 (draft).
- AppleScript string escaping (`AppleScriptBuilder.stringLiteral`) is the app's
  security boundary — keep it unit-tested.
- Never leak a raw `{{placeholder}}` to a recipient; merge blocks unresolved rows.
