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
blocked and reported instead of sent. A *malformed* field — `{{Company` with no
closing braces — isn't a placeholder at all, so it can't be stripped. Two things
catch it, exactly as on the Mac and iPhone: the run warns you about unbalanced
braces in the template before drafting anything, and every merged subject and
body is scanned for leftover braces so any row still carrying them is blocked,
with the offending text quoted back to you. That second check is what catches
braces arriving in a spreadsheet *value* rather than the template. Both apply on
`-DryRun` too.

## Easy mode — the clickable window (no commands)

If you don't want to touch PowerShell at all, use the point-and-click window.
It does everything the command line does, with Browse buttons and three big
buttons — **Preview**, **Create Drafts**, **Send** — instead of typed commands.

1. Make sure these files are together in one folder: **`HighRise.cmd`**,
   **`HighRise-GUI.ps1`**, **`HighRise-Merge.ps1`**, **`HighRise-Templates.ps1`**,
   **`HighRise-DoNotContact.ps1`**, and **`templates.json`**.
2. **Double-click `HighRise.cmd`.** The HighRise window opens.
3. In the window: **Browse** to your recipients list, then click **Starter
   templates…** to pick one of the 95 ready-made templates the Mac and iPhone
   apps ship (see below), **Browse** to a template file you already have, or
   **New template…** to write one from scratch in Notepad. Optionally type your
   own address in the BCC box.
4. Click **Preview** to see every message safely (nothing is created), then
   **Create Drafts** to drop one draft per recipient into Outlook. Click
   **Open Outlook** to review and send them.

Want it even faster? Right-click `HighRise.cmd` → **Send to ▸ Desktop (create
shortcut)**, then rename the desktop shortcut to "HighRise" — now it's a
double-click icon on your desktop. (You can also right-click that shortcut →
**Pin to taskbar**.)

## Do not contact

Some people ask not to be emailed. HighRise keeps a list of those addresses —
and whole domains — and **holds them back from every merge automatically**.
Your CSV is never edited; the row simply doesn't send.

It's the same list the Mac and iPhone apps keep, in the same file format, so
you can copy `do-not-contact.json` between machines and it behaves identically.
By default it lives at `%APPDATA%\HighRise\do-not-contact.json`.

**In the window:** click **Do not contact** to see who's blocked, add someone,
or unblock them.

**From the command line:**

```powershell
.\HighRise-DoNotContact.ps1                              # see the list
.\HighRise-DoNotContact.ps1 -Add someone@example.com     # block one person
.\HighRise-DoNotContact.ps1 -Add acme.com -Note "Asked"  # block a whole company
.\HighRise-DoNotContact.ps1 -Test someone@example.com    # would this be blocked?
.\HighRise-DoNotContact.ps1 -Remove someone@example.com  # let them through again
```

Every merge reports how many entries it loaded, and each held-back row says
so in the results. To use a list stored somewhere else — a shared drive, or
one copied off a Mac — pass `-DoNotContact <path>` to either script.

If the list file is corrupt, the merge **stops** rather than continuing: a
list it can't read must never silently become "email everyone."

## If a run is interrupted

A long send can be cut short — the machine sleeps, Outlook falls over, someone
closes the window. HighRise writes a **run journal** as it goes, one line per
recipient, so the record of who was already reached survives whatever killed
the run. It lives at `%APPDATA%\HighRise\last-run.json`.

Start the same list and template again and HighRise notices the previous
attempt never finished, tells you so, and **skips the people it already
reached** — so nobody gets the same email twice:

```
The previous run of this list started 08/12/2026 09:14:22 and did not finish.
Skipping the 312 recipient(s) it already reached.
[SKIPPED] Sam Rivera <sam@acme.com> - already sent by the unfinished previous run
```

```powershell
.\HighRise-Merge.ps1 -ShowLastRun         # who was already reached?
.\HighRise-Merge.ps1 ... -IgnorePreviousRun   # contact them again anyway
.\HighRise-Merge.ps1 ... -NoRunLog            # keep no journal at all
.\HighRise-Merge.ps1 ... -RunLog D:\logs\run.json   # keep it somewhere else
```

Skipping only ever happens for an **unfinished** run of the *same* list and
template. A run that ended normally never causes skips, so re-sending to a
list you've already mailed still works exactly as before. If the journal file
is corrupt, the merge **stops** rather than guessing — the same rule the
do-not-contact list follows, and for the same reason.

## Starter templates

The same 95 ready-made templates the Mac and iPhone apps ship come with the
Windows folder, in `templates.json`. Every one is a working example of the
merge syntax, so they double as a tutorial.

**In the window:** click **Starter templates…** for a browser with a search
box and three dropdowns — **Industry** (the twelve major North American
sectors), **Audience** (prospects, customers, partners, job candidates), and
**Task** (Grow, Connect, Get paid, Retain, Announce, Recruit). Pick an
industry and the ones written for that trade come first; the general-purpose
ones stay underneath, so you're never left with an empty list. Click a
template to read it in full, then **Use this template** to save it and load it
into the merge.

**From the command line**, `HighRise-Templates.ps1` does the same thing:

```powershell
.\HighRise-Templates.ps1                                     # list all 95
.\HighRise-Templates.ps1 -Industry Construction              # one sector
.\HighRise-Templates.ps1 -Industry Transport -Audience cand  # sector + reader
.\HighRise-Templates.ps1 -Search "invoice overdue"           # free-text search
.\HighRise-Templates.ps1 -Id invoice-reminder -Full          # read one in full
.\HighRise-Templates.ps1 -Id invoice-reminder -Save .\mine.txt
```

That last one writes a normal template file you then pass to the merge:

```powershell
.\HighRise-Merge.ps1 -Csv .\my-list.csv -Template .\mine.txt -DryRun
```

`-Industry`, `-Audience` and `-Category` match on any part of the name, so
`-Industry const` finds Construction and `-Audience cand` finds Job Candidates.

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
- `-ReportCsv run-report.csv` writes a per-recipient outcome log at the end. The run journal above is the one that survives a crash.

## What the Windows tool doesn't do

The Mac app is the full product; this is the merge-and-send core, the
starter-template catalog, and the do-not-contact list. Not here:
`.xlsx`/`.docx`/PDF import (export to CSV instead), Apple/Outlook contacts
import, A/B template variants, scheduled send, merge-to-PDF, and the
unsubscribe footer. If you need one of these on Windows, open an issue.

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
