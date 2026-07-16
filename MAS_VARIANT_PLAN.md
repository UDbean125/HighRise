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
> Structure decision (Bryan, 2026-07-16): the MAS variant is **not** a second
> XcodeGen target. It's an additional **build configuration** on the existing
> `HighRise` target (its own entitlements file + a `MAS_BUILD` compile flag,
> selected via one extra scheme) — same target in the project navigator, same
> source list, no duplication. A second target was the original plan below;
> superseded by this configuration-based approach to keep the project less
> confusing. Sandboxing is still an all-or-nothing, per-build-product setting
> (baked into the code signature), so the Developer ID build and the MAS build
> remain two separate *build products* either way — this only changes how
> Xcode organizes that, not what each build can do.

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
| Apple Events automation of **Outlook** | Outlook publishes no scripting access groups; the only route is `com.apple.security.temporary-exception.apple-events`, which App Review generally rejects | **Dropped from the MAS variant.** Outlook users are served by the Developer ID build (and the Windows companion). The MAS UI must hide the Outlook path entirely — no dead buttons, gated via `#if MAS_BUILD`. | Not started. |
| File writes (CSV template export, logs) | Arbitrary-path writes denied | Already user-driven via save panels → automatically granted; audit for any hardcoded paths. | Not audited yet. |

### Build-system shape (XcodeGen)

- New entitlements file `HighRise/HighRise-MAS.entitlements`: `app-sandbox: true`,
  `com.apple.security.files.user-selected.read-write: true`, scripting-targets
  for Mail. No network entitlement needed (no SMTP by design).
- **One `HighRise` target, an additional build configuration** (e.g.
  `Release-MAS` alongside `Debug`/`Release`) with per-configuration overrides
  in `project.yml` (XcodeGen's `settings.configs.<name>` structure) for
  `CODE_SIGN_ENTITLEMENTS` (the new MAS entitlements file),
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS: MAS_BUILD`, and its own provisioning.
  A dedicated scheme (e.g. `HighRise-MAS`) selects that configuration for its
  Archive action, so choosing which build to produce is a scheme pick, not a
  target pick. Same bundle ID (`com.bryansnotes.highrise`) either way — Apple
  permits the same ID for MAS + Developer ID distribution.
- Feature gating in code via `#if MAS_BUILD` **only at the capability seams**
  (mail-provider picker, Office import path — the latter no longer needs
  gating at all now that `ZipEntryReader` works identically both ways); merge/
  template logic stays shared and unconditional.

### Work items, in order

1. ~~**In-process ZIP reader**~~ — **done.** Landed in the shared `HighRise`
   target; the Developer ID build already benefits (no process spawn).
2. **Spike (½ day): Mail scripting-targets.** Minimal sandboxed test app that
   composes and sends via Apple Events with `com.apple.mail.compose`. The
   result (send vs. draft-only) decides the MAS product story.
3. **`Release-MAS` configuration + `HighRise-MAS.entitlements` + scheme**,
   with `MAS_BUILD` gating of the provider picker; hide Outlook; empty-state
   copy pointing Outlook users at the Developer ID build.
4. **CI job** building with the MAS configuration and a post-build assertion
   that `codesign -d --entitlements` shows `app-sandbox = true`.
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
