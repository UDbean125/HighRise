# HighRise on Windows

The HighRise app itself is macOS-native (SwiftUI + AppleScript) and cannot run
on Windows. What *does* run on Windows is the part that matters: this folder
contains **`HighRise-Merge.ps1`**, a self-contained PowerShell script that
ports HighRise's mail-merge core to Windows and delivers through **classic
Microsoft Outlook** — same philosophy as the Mac app: no SMTP passwords, no
servers, no third-party installs, **draft-first by default** so you review
every message before it goes out.

It uses the same template syntax and the same safety rules as the Mac app: a
raw `{{placeholder}}` is never leaked to a recipient, and rows with missing
data, an invalid address, a duplicate address, or a missing attachment file are
blocked and reported instead of sent.

## Easy mode — the clickable window (no commands)

If you don't want to touch PowerShell at all, use the point-and-click window.
It does everything the command line does, with Browse buttons and three big
buttons — **Preview**, **Create Drafts**, **Send** — instead of typed commands.

1. Make sure these three files are together in one folder: **`HighRise.cmd`**,
   **`HighRise-GUI.ps1`**, and **`HighRise-Merge.ps1`**.
2. **Double-click `HighRise.cmd`.** The HighRise window opens.
3. In the window: **Browse** to your recipients list, then **Browse** to your
   template (or click **New template…** to create one — it opens in Notepad
   with instructions). Optionally type your own address in the BCC box.
4. Click **Preview** to see every message safely (nothing is created), then
   **Create Drafts** to drop one draft per recipient into Outlook. Click
   **Open Outlook** to review and send them.

Want it even faster? Right-click `HighRise.cmd` → **Send to ▸ Desktop (create
shortcut)**, then rename the desktop shortcut to "HighRise" — now it's a
double-click icon on your desktop. (You can also right-click that shortcut →
**Pin to taskbar**.)

The rest of this page is the command-line reference — you only need it if you
want the extra options (per-recipient attachments, CC, throttling, reports).

## What you need

- Windows 10 or 11 — PowerShell 5.1 is already preinstalled; nothing to install.
- **Classic Outlook** for Windows (Microsoft 365, or Outlook 2016 or newer),
  signed in to your mail account. The "new Outlook" doesn't support automation
  yet — see Troubleshooting below.
- Two files of your own: a recipients CSV and a template text file.

To get the files: on the GitHub repo page choose **Code ▸ Download ZIP** (or
clone), then copy the whole `Windows\` folder anywhere you like — for the
clickable window keep `HighRise.cmd`, `HighRise-GUI.ps1`, and
`HighRise-Merge.ps1` together. There are no other dependencies. If Windows
marks a downloaded file as blocked, right-click it → **Properties** → tick
**Unblock**, or run `Unblock-File .\HighRise-*.ps1` once.

## Quick start

1. **Recipients CSV** — any columns you like; one must hold email addresses
   (auto-detected, or pass `-EmailColumn "Work Email"`). Comma, semicolon, and
   tab delimiters are auto-detected. From Excel, use
   **File ▸ Save As ▸ CSV UTF-8**.

   ```csv
   Name,Company,Email
   Sam,"Acme, Inc.",sam@acme.com
   ```

2. **Template file** — a `Subject:` line, an optional `Format:` line
   (`plain` is the default, `html` for HTML bodies), a blank line, then the
   body. See `Examples\sample-template.txt`:

   ```text
   Subject: Quick question about {{Company}}

   Hi {{Name}},

   I wanted to reach out about {{Company}}.

   Best,
   Bryan
   ```

3. **Preview first** (touches nothing, doesn't even need Outlook):

   ```powershell
   cd path\to\HighRise\Windows
   powershell -ExecutionPolicy Bypass -File .\HighRise-Merge.ps1 -Csv ..\Examples\sample-recipients.csv -Template .\Examples\sample-template.txt -DryRun
   ```

4. **Create drafts** — one per sendable recipient, in Outlook's Drafts folder,
   where you review and send them yourself:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\HighRise-Merge.ps1 -Csv mylist.csv -Template letter.txt
   ```

5. **Or send immediately** (asks you to type `SEND` to confirm; `-Force` skips
   the prompt, `-ThrottleSeconds 2` paces the sends):

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\HighRise-Merge.ps1 -Csv mylist.csv -Template letter.txt -Send
   ```

Run `Get-Help .\HighRise-Merge.ps1 -Full` for every option, or read the header
of the script itself.

## Merge syntax

Identical to the Mac app (see the repo's main README for the full story):

| Write                                  | Get |
| -------------------------------------- | --- |
| `{{Company}}`                          | that row's Company column (case/space-insensitive match) |
| `{{First Name\|there}}`                | "there" when the row has no First Name (instead of blocking) |
| `{{Renewal Date\|date:MMMM d, yyyy}}`  | `June 22, 2026` — also parses Excel serial numbers like `46195` |
| `{{Amount\|currency:USD}}`             | `$24,500.00` |
| `{{Seats\|number}}`                    | `1,234,567` |
| `{{Name\|fixcaps}}`                    | `JORDAN AVERY` → `Jordan Avery` |
| `{{Tag\|upper}}` / `lower` / `capitalize` / `trim` | casing / whitespace fixes |

Filters chain left to right: `{{First Name|there|capitalize}}` falls back to
"There". A recipient missing a field that has **no** fallback is blocked, not
sent with a hole. In `Format: html` templates, substituted values are
HTML-escaped automatically.

One Windows-flavored difference: `date:` patterns are .NET format strings
(e.g. weekday is `dddd` here vs `EEEE` on the Mac). The common patterns —
`MMMM d, yyyy`, `MM/dd/yyyy`, `yyyy-MM-dd` — mean the same thing on both.

## CC, BCC, and attachments

- `-Cc` / `-Bcc` apply to every message and may contain placeholders:
  `-Cc "{{Manager Email}}"` CCs each row's manager. Invalid addresses are
  dropped silently, never sent to.
- `-BccSelf you@example.com` BCCs you on every message — a delivery record
  with no tracking pixel.
- `-Attach report.pdf, terms.pdf` attaches the same file(s) to every message
  (the run stops if one is missing, and warns when the total is > 20 MB).
- A CSV column named `attachment` (or `attachments` / `file` / `files`) holds
  per-recipient paths, `;`-separated. A missing file blocks that row only.
- `-ReportCsv run-report.csv` writes a per-recipient outcome log.

## What the Windows tool doesn't do

The Mac app is the full product; this is the merge-and-send core. Not here:
the GUI, `.xlsx`/`.docx`/PDF import (export to CSV instead), Apple/Outlook
contacts import, the do-not-contact list, A/B template variants, scheduled
send, merge-to-PDF, and the unsubscribe footer. If you need one of these on
Windows, open an issue.

## Troubleshooting

- **"…running scripts is disabled on this system"** — that's PowerShell's
  execution policy. Either launch as shown above with
  `powershell -ExecutionPolicy Bypass -File .\HighRise-Merge.ps1 …`, or run
  `Unblock-File .\HighRise-Merge.ps1` once after downloading.
- **"Could not start Outlook automation"** — the script needs *classic*
  Outlook. If your Outlook window has a "New Outlook" toggle (top right),
  switch it **off** and try again; the new Outlook doesn't expose COM
  automation yet. Also make sure Outlook has been opened once and has an
  account configured.
- **Outlook shows a security prompt when using `-Send`** — that's Outlook's
  programmatic-access guard (common when no antivirus is registered). Allow
  it, or stick with the default draft mode, which is the recommended flow
  anyway.
- **Accented characters look garbled** — re-save the CSV from Excel as
  **CSV UTF-8 (Comma delimited)**. The script auto-handles UTF-8 (with or
  without BOM), UTF-16, and falls back to Windows-1252.
- **Your email signature isn't on the drafts** — Outlook only auto-appends
  signatures to messages you compose by hand. Put your signature text at the
  bottom of the template instead.
