# HighRise Distribution Plan — Developer ID now, Mac App Store variant next

> Decision (Bryan, 2026-07-08): ship HighRise via **Developer ID + notarization
> immediately** with full features, and build a **sandboxed Mac App Store (MAS)
> variant as a separate effort** with a reduced feature set.
>
> Context: an App Store Connect validation of the 1.0 (1) archive failed with
> "App sandbox not enabled." That failure is by design — `HighRise.entitlements`
> deliberately sets `com.apple.security.app-sandbox` to `false` because two core
> capabilities are incompatible with the sandbox as currently implemented:
> Apple Events automation of Mail/Outlook, and (until 2026-07-16) spawning
> `/usr/bin/unzip` to read `.xlsx`/`.docx`.
>
> Structure decision, take two (2026-07-16, later the same day): a
> configuration-based approach (same `HighRise` target, an extra build
> configuration) was proposed as less confusing than a second target — but
> real, already-working implementation of the second-target approach (a
> `HighRise-MAS` target, its own entitlements file, `MAS_BUILD` gating across
> `MailClient`/`AppleScriptBuilder`/`OutlookContactsImporter`/`PreSendReport`/
> the Views) landed before that reconsideration could happen. Reworking
> working code into the configuration shape for a naming preference wasn't
> worth it, so **the second-target approach is what's actually implemented**
> below. Sandboxing is still an all-or-nothing, per-build-product setting
> (baked into the code signature), so the Developer ID build and the MAS
> build are two separate build products regardless of which XcodeGen shape
> holds them.

---

## Track 1 — Ship v1.0.0 via Developer ID (blocked only on credentials)

The pipeline already exists: `.github/workflows/release.yml` signs with
Developer ID, notarizes with `notarytool`, staples, and publishes the zip on a
`v*` tag (or uploads a run artifact on manual dispatch). CI on `main` is green.

**Status as of 2026-07-08:** the repo has **zero Actions secrets** configured,
and the Mac's keychain has no Developer ID Application certificate — only
Apple Development certs. Everything else is ready.

One-time setup (owner only — requires the Apple Developer Account Holder role):

1. **Create the Developer ID Application certificate**: Xcode → Settings →
   Accounts → (team) → Manage Certificates → **+** → *Developer ID
   Application*. Then export it from Keychain Access as a password-protected
   `.p12`.
2. **Create an App Store Connect API key** (App Store Connect → Users and
   Access → Integrations → App Store Connect API) with the *Developer* role;
   download the `AuthKey_XXXXXX.p8` and note the Key ID and Issuer ID.
3. **Set the seven repository secrets** (names documented in the
   `release.yml` header):

   ```sh
   gh secret set BUILD_CERTIFICATE_BASE64 -R UDbean125/HighRise --body "$(base64 -i cert.p12)"
   gh secret set P12_PASSWORD             -R UDbean125/HighRise
   gh secret set KEYCHAIN_PASSWORD        -R UDbean125/HighRise --body "$(uuidgen)"
   gh secret set DEVELOPMENT_TEAM         -R UDbean125/HighRise   # 10-char Team ID
   gh secret set AC_API_KEY_BASE64        -R UDbean125/HighRise --body "$(base64 -i AuthKey_XXXXXX.p8)"
   gh secret set AC_API_KEY_ID            -R UDbean125/HighRise
   gh secret set AC_API_ISSUER_ID         -R UDbean125/HighRise
   ```

4. **Release**:

   ```sh
   git tag v1.0.0 && git push origin v1.0.0
   ```

   The workflow builds, notarizes, staples, and attaches
   the zip to a GitHub Release. Subsequent releases: bump `MARKETING_VERSION` /
   `CURRENT_PROJECT_VERSION` in `project.yml`, merge, tag.

---

## Track 2 — Sandboxed Mac App Store variant (separate effort)

### What breaks under the sandbox, and the replacement for each

| Capability today | Why the sandbox blocks it | MAS replacement | Status |
|---|---|---|---|
| Spawn `/usr/bin/unzip` to read `.xlsx`/`.docx` | Child processes don't inherit the user-selected-file sandbox extension reliably; writing extracted files outside the container is denied | In-process ZIP reading: parse the ZIP central directory in Swift and inflate entries with `libcompression` (`COMPRESSION_ZLIB`, which is raw DEFLATE despite the name). Office files are plain DEFLATE zips — no encryption/zip64 needed. | **Done (2026-07-16).** `ZipEntryReader.swift` rewritten pure-Swift, no subprocess. Landed directly in the main `HighRise` target (channel-neutral — it also removes a subprocess spawn from the Developer ID build). Tested against real zip fixtures in `ZipEntryReaderTests.swift`. |
| Apple Events automation of **Mail** | `com.apple.security.automation.apple-events` alone is a hardened-runtime entitlement; sandboxed apps need scripting-target entitlements | `com.apple.security.scripting-targets` with Mail's `com.apple.mail.compose` access group. **Needs a spike**: confirm the compose access group covers `send` (not just draft creation) on current macOS. If send is not covered, MAS mode falls back to "create drafts in Mail" + user presses send, which is still a coherent product. | Not started. |
| Apple Events automation of **Outlook** | Outlook publishes no scripting access groups; the only route is `com.apple.security.temporary-exception.apple-events`, which App Review generally rejects | **Dropped from the MAS variant.** Outlook users are served by the Developer ID build (and the Windows companion). The MAS UI must hide the Outlook path entirely — no dead buttons, gated via `#if MAS_BUILD`. | **Done (2026-07-16).** Every `.outlook` reference in `MailClient`, `AppleScriptBuilder`, `OutlookContactsImporter`, `PreSendReport`, `ContactsImportView`, `HomeView`, and `SendView` is wrapped in `#if !MAS_BUILD`/`#if MAS_BUILD`; `OutlookContactsImporter.fetchTable()` throws `.notInstalled` under `MAS_BUILD` instead of attempting AppleScript. |
| File writes (CSV template export, logs) | Arbitrary-path writes denied | Already user-driven via save panels → automatically granted; audit for any hardcoded paths. | Not audited yet. |

### Build-system shape (XcodeGen)

- New entitlements file `HighRise/HighRise-MAS.entitlements`: `app-sandbox: true`,
  `com.apple.security.files.user-selected.read-write: true`, scripting-targets
  for Mail. No network entitlement needed (no SMTP by design).
- **A second XcodeGen target, `HighRise-MAS`**, compiling the same
  `HighRise` source folder as the main `HighRise` target (see "Structure
  decision, take two" above). It sets `CODE_SIGN_ENTITLEMENTS` to
  `HighRise/HighRise-MAS.entitlements` and `SWIFT_ACTIVE_COMPILATION_CONDITIONS:
  MAS_BUILD`, and deliberately leaves `PRODUCT_NAME` unset — setting it to
  "HighRise" would collide with the main target's Swift module name, since
  both compile the identical source folder (same precedent as
  `HighRiseMobile`). `CFBundleDisplayName` in `Info.plist` is hardcoded to
  "HighRise" already, so the user-visible app name is unaffected. A dedicated
  `HighRise-MAS` scheme builds/archives that target (`HighRiseTests` runs
  against the main target for both schemes — the new CI job below is what
  actually exercises MAS-specific behavior). Same bundle ID
  (`com.bryansnotes.highrise`) either way — Apple permits the same ID for
  MAS + Developer ID distribution.
- Feature gating in code via `#if MAS_BUILD` **only at the capability seams**
  (mail-provider picker, Outlook contacts import, pre-send report — the
  Office import path no longer needs gating at all now that `ZipEntryReader`
  works identically both ways); merge/template logic stays shared and
  unconditional.

### Work items, in order

1. ~~**In-process ZIP reader**~~ — **done.** Landed in the shared `HighRise`
   target; the Developer ID build already benefits (no process spawn).
2. **Spike (½ day): Mail scripting-targets.** Minimal sandboxed test app that
   composes and sends via Apple Events with `com.apple.mail.compose`. The
   result (send vs. draft-only) decides the MAS product story. **Still the
   one open, unverified risk** — requires a real Mac to test; cannot be
   verified from a Linux container.
3. ~~**`HighRise-MAS` target + `HighRise-MAS.entitlements` + scheme**~~ —
   **done.** `MAS_BUILD` gates the provider picker and Outlook contacts
   import; Outlook UI paths are hidden/dead-end to the Developer ID build
   under `MAS_BUILD`.
4. ~~**CI job**~~ — **done.** `.github/workflows/ci.yml`'s "Build HighRise-MAS
   and verify the sandbox entitlement" step builds the `HighRise-MAS` scheme
   ad-hoc signed and asserts via `codesign -d --entitlements` +
   `PlistBuddy` that `com.apple.security.app-sandbox` is `true`.
5. **App Store metadata + upload** — screenshots, privacy questionnaire
   (no data collection; everything is local), then archive/upload via the
   `HighRise-MAS` scheme. *Approval gate: submission itself waits for Bryan's
   go.*

### Sequencing note

Item 1 was the only substantial engineering and was channel-neutral — done
first, shipped to the Developer ID build already. The MAS variant is now
mostly the Mail spike outcome plus configuration/entitlements work.

---

## Housekeeping flagged while setting this up

- The repo used to track both `Windows/README.md` and `windows/README.md`
  (old PowerShell companion vs. a since-abandoned .NET rewrite attempt from
  another session). That collides on case-insensitive macOS volumes. As of
  2026-07-16 only `Windows/` (the PowerShell companion, documented in
  `CLAUDE.md`) is current — if a lowercase `windows/` tree reappears from a
  stale branch merge, delete it rather than reconciling two companions.
