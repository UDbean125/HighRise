# HighRise for Windows (.NET + WinUI 3)

A native Windows port of HighRise — the mail-merge app that personalizes one
message per recipient. The macOS app drives Apple Mail/Outlook via AppleScript;
Windows has no such automation, so the Windows edition sends through **email
provider APIs over OAuth** (Gmail API + Microsoft Graph) — no SMTP credentials
stored, no servers.

## Layout

```
windows/
  HighRise.sln
  src/
    HighRise.Core/          .NET class library — pure, cross-platform logic
      Models/   Contact, RecipientTable, EmailTemplate, MergePreview, BodyFormat
      Services/ CsvParser, TemplateMergeEngine, EmailValidator
  tests/
    HighRise.Core.Tests/    xUnit tests mirroring the Swift core's test suite
```

`HighRise.Core` is a plain `net8.0` library with **no Windows dependencies**, so
it builds and unit-tests on any OS (and in CI on Ubuntu — see
`.github/workflows/windows-core-ci.yml`). It is a faithful C# port of the Swift
core (`HighRise/Services` + `HighRise/Models`), pinned by the same test cases so
behaviour matches across platforms.

## Roadmap

- [x] **`HighRise.Core`** — CSV parse, native `.xlsx` reader, `{{Field}}` merge,
      HTML escaping, email validation, send-gating.
- [x] **`HighRise.Mail`** — Gmail API + Microsoft Graph senders over OAuth
      (per-recipient draft/send), MIME building with header-injection guarding.
      Token acquisition is abstracted (`IAccessTokenProvider`) so the library is
      dependency-light and CI-verifiable; the WinUI app wires MSAL / Google OAuth.
- [ ] **`HighRise.App`** (WinUI 3) — Compose → Import → Review → Send UI.

`Core` and `Mail` are CI-verified on Ubuntu. The WinUI app requires the Windows
App SDK and is built on Windows.

## OAuth setup (to actually send)

Sending uses OAuth — no passwords stored. Client IDs are read at runtime from a
local file that is **never committed** (the repo is public):

`%LOCALAPPDATA%\HighRise\oauth.json` — see `src/HighRise.App/oauth.example.json`
for the shape:

```json
{
  "google":    { "clientId": "…apps.googleusercontent.com", "clientSecret": "…" },
  "microsoft": { "clientId": "…" }
}
```

* **Gmail** — Google Cloud → enable the Gmail API → OAuth consent screen
  (External, add yourself as a Test user) → create an **OAuth client ID** of type
  **Desktop app** → copy the client ID + secret. Scope used: `gmail.compose`
  (drafts + send). The loopback sign-in opens your browser on first send.
* **Outlook** — Azure Portal → **App registrations** → new registration
  (multitenant + personal accounts), redirect URI `http://localhost`,
  **Allow public client flows = Yes**, delegated Graph permissions `Mail.Send` +
  `Mail.ReadWrite`. Copy the **Application (client) ID** (no secret needed).

Provide only the providers you use; an unconfigured provider fails with a clear
message rather than sending. The `microsoft` block is optional.

## Build & test (any OS)

```sh
dotnet test windows/tests/HighRise.Core.Tests/HighRise.Core.Tests.csproj
```
