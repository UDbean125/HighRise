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

- [x] **`HighRise.Core`** — CSV parse, `{{Field}}` merge, HTML escaping, email
      validation, send-gating.
- [x] **`HighRise.Mail`** — Gmail API + Microsoft Graph senders over OAuth
      (per-recipient draft/send), MIME building with header-injection guarding.
      Token acquisition is abstracted (`IAccessTokenProvider`) so the library is
      dependency-light and CI-verifiable; the WinUI app wires MSAL / Google OAuth.
- [ ] **`HighRise.Mail`** — `.xlsx` reader (next).
- [ ] **`HighRise.App`** (WinUI 3) — Compose → Import → Review → Send UI.

`Core` and `Mail` are CI-verified on Ubuntu. The WinUI app requires the Windows
App SDK and is built on Windows.

## Build & test (any OS)

```sh
dotnet test windows/tests/HighRise.Core.Tests/HighRise.Core.Tests.csproj
```
