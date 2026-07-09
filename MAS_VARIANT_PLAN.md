# HighRise Distribution Plan — Developer ID now, Mac App Store variant next

> Decision (Bryan, 2026-07-08): ship HighRise via **Developer ID + notarization
> immediately** with full features, and build a **sandboxed Mac App Store (MAS)
> variant as a separate effort** with a reduced feature set.
>
> Context: an App Store Connect validation of the 1.0 (1) archive failed with
> "App sandbox not enabled." That failure is by design — `HighRise.entitlements`
> deliberately sets `com.apple.security.app-sandbox` to `false` because two core
> capabilities are incompatible with the sandbox as currently implemented:
> Apple Events automation of Mail/Outlook, and spawning `/usr/bin/unzip` to read
> `.xlsx`/`.docx`. Do **not** "fix" the validation error by flipping that flag.

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

| Capability today | Why the sandbox blocks it | MAS replacement |
|---|---|---|
| Spawn `/usr/bin/unzip` to read `.xlsx`/`.docx` | Child processes don't inherit the user-selected-file sandbox extension reliably; writing extracted files outside the container is denied | In-process ZIP reading: parse the ZIP central directory in Swift and inflate entries with `libcompression` (`COMPRESSION_ZLIB`). Office files are plain DEFLATE zips — no encryption/zip64 needed. Pure-logic, unit-testable, no third-party deps. The Windows port already has an in-process `XlsxReader.cs` to crib the container logic from. |
| Apple Events automation of **Mail** | `com.apple.security.automation.apple-events` alone is a hardened-runtime entitlement; sandboxed apps need scripting-target entitlements | `com.apple.security.scripting-targets` with Mail's `com.apple.mail.compose` access group. **Needs a spike**: confirm the compose access group covers `send` (not just draft creation) on current macOS. If send is not covered, MAS mode falls back to "create drafts in Mail" + user presses send, which is still a coherent product. |
| Apple Events automation of **Outlook** | Outlook publishes no scripting access groups; the only route is `com.apple.security.temporary-exception.apple-events`, which App Review generally rejects | **Dropped from the MAS variant.** Outlook users are served by the Developer ID build (and the Windows companion). The MAS UI must hide the Outlook path entirely — no dead buttons. |
| File writes (CSV template export, logs) | Arbitrary-path writes denied | Already user-driven via save panels → automatically granted; audit for any hardcoded paths. |

### Build-system shape (XcodeGen)

- New entitlements file `HighRise/HighRise-MAS.entitlements`: `app-sandbox: true`,
  `com.apple.security.files.user-selected.read-write: true`, scripting-targets
  for Mail. No network entitlement needed (no SMTP by design).
- New XcodeGen target **`HighRise-MAS`** in `project.yml` sharing all sources,
  differing only in entitlements, `SWIFT_ACTIVE_COMPILATION_CONDITIONS:
  MAS_BUILD`, and provisioning. Same bundle ID (`com.bryansnotes.highrise`) —
  Apple permits the same ID for MAS + Developer ID distribution.
- Feature gating in code via `#if MAS_BUILD` **only at the capability seams**
  (mail-provider picker, Office import path); merge/template logic stays shared
  and unconditional.

### Work items, in order

1. **Spike (½ day): Mail scripting-targets.** Minimal sandboxed test app that
   composes and sends via Apple Events with `com.apple.mail.compose`. The
   result (send vs. draft-only) decides the MAS product story.
2. **In-process ZIP reader** (`ZipArchiveReader.swift`, ~250 LOC + tests with
   real `.xlsx`/`.docx` fixtures). Land it in the **main** target first and
   delete the `unzip` spawn everywhere — it makes the Developer ID build better
   too (no process spawn, works on locked-down Macs).
3. **`HighRise-MAS` target + entitlements + `MAS_BUILD` gating** of the
   provider picker; hide Outlook; empty-state copy pointing Outlook users at
   the website build.
4. **CI job** building the MAS target with a post-build assertion that
   `codesign -d --entitlements` shows `app-sandbox = true`.
5. **App Store metadata + upload** — screenshots, privacy questionnaire
   (no data collection; everything is local), then archive/upload. *Approval
   gate: submission itself waits for Bryan's go.*

### Sequencing note

Item 2 is the only substantial engineering and is channel-neutral — do it
first, ship it to the Developer ID build, and the MAS variant becomes mostly
configuration plus the Mail spike outcome.

---

## Housekeeping flagged while setting this up

- The repo tracks both `Windows/README.md` and `windows/README.md`
  (old PowerShell companion vs. new .NET app). On case-insensitive macOS
  volumes these collide and one file perpetually shows as modified. Merge the
  old `Windows/` content into `windows/` (or delete the stale copy) from the
  Linux container, where the paths are distinct.
