<#
.SYNOPSIS
HighRise mail merge for Windows: personalizes an email template per CSV row
and creates one draft per recipient in classic Outlook (or sends, on request).

.DESCRIPTION
This is the Windows companion to HighRise (the native macOS app in this repo).
It ports the app's I/O-free core - {{Field}} placeholder merging with filters,
email validation, duplicate/missing-data blocking, HTML escaping - to
PowerShell, and swaps the delivery layer from AppleScript (Apple Mail/Outlook
on macOS) to COM automation of *classic* Outlook for Windows. Same philosophy
as the app: no SMTP credentials, no servers, draft-first by default.

Works on Windows PowerShell 5.1 (preinstalled on every Windows 10/11 machine)
and PowerShell 7+.

Merge syntax (mirrors the macOS app; see the repo README):
  {{Field}}                     substitute a CSV column (case/space-insensitive)
  {{First Name|there}}          fallback when the row's value is empty/missing
  {{First Name|default:there}}  same, written in full
  {{Renewal Date|date:MMMM d, yyyy}}   reformat dates (.NET date patterns);
                                also parses Excel serial numbers like 46195
  {{Amount|currency:USD}}       $24,500.00
  {{Seats|number}}              group digits: 1234567 -> 1,234,567
  {{Name|fixcaps}}              repair ALL-CAPS: JORDAN AVERY -> Jordan Avery
  {{Tag|upper}} / lower / capitalize / trim
Filters chain left to right: {{First Name|there|capitalize}}.

A row is blocked (never drafted/sent) when it has an invalid or missing email,
is on the do-not-contact list, still shows merge-field braces after merging, is
missing data for a placeholder that has no fallback, repeats an earlier row's
address, or names a per-recipient attachment file that doesn't exist.
Unresolved placeholders are removed from the output - a raw {{...}} never
reaches a recipient. A malformed one - "{{Company" with no closing braces - is
not a placeholder at all and so cannot be stripped, so the merged subject and
body are scanned for leftover braces and any row still carrying them is
blocked, whether the braces came from the template or from a CSV value. The run
also warns about unbalanced braces in the template up front, before anything is
drafted. Both apply under -DryRun.

.PARAMETER Csv
Path to the recipients list (.csv). Comma, semicolon, and tab delimiters are
auto-detected; UTF-8 (with or without BOM) and UTF-16 are handled.

.PARAMETER Template
Path to the template file. Format:
    Subject: Quick question about {{Company}}
    Format: plain                <- optional line; "plain" (default) or "html"
    <blank line>
    Hi {{Name}},
    ...body, may use {{Field}} placeholders...

.PARAMETER EmailColumn
Column to treat as the email address. Auto-detected when omitted (a header
containing "email", else the column with the most valid-looking addresses).

.PARAMETER Delimiter
CSV delimiter override. Auto-detected when omitted.

.PARAMETER Cc
CC addresses applied to every message. Comma/semicolon-separated; may contain
{{Field}} placeholders (e.g. {{Manager Email}}). Invalid addresses are dropped.

.PARAMETER Bcc
BCC addresses applied to every message; same rules as -Cc.

.PARAMETER BccSelf
One fixed address BCC'd on every message - a privacy-respecting delivery
record, no tracking pixel.

.PARAMETER Attach
File(s) attached to every message. The run stops if any is missing, and warns
when the total size is likely to bounce (> 20 MB).

Per-recipient attachments work like the Mac app: add a CSV column named
"attachment" (or attachments/file/files) whose cell holds one or more paths
separated by ";". A missing file blocks that row only.

.PARAMETER Send
Send each message immediately instead of saving drafts. Asks for confirmation
first unless -Force is also given.

.PARAMETER Force
Skip the confirmation prompt that -Send shows.

.PARAMETER DryRun
Print what would be drafted/sent - full To/Cc/Subject/body per recipient and
every blocked row's reason - without starting Outlook. Safe anywhere.

.PARAMETER ThrottleSeconds
Pause this many seconds between messages when sending (default 0).

.PARAMETER ReportCsv
Also write a per-recipient outcome report (name, email, status, detail) to
this CSV path.

.PARAMETER RunLog
Where to keep the durable run journal. Defaults to
%APPDATA%\HighRise\last-run.json. The journal is written record-by-record as
the run progresses, so a crash, a closed window or Ctrl-C partway through a
long run still leaves a record of who was already reached.

.PARAMETER NoRunLog
Do not read or write the run journal at all.

.PARAMETER IgnorePreviousRun
Deliver to everyone, including the recipients an unfinished previous run of
this same list and template already reached. Deliberately awkward to reach:
skipping them is what stops a second attempt from emailing people twice.

.PARAMETER ShowLastRun
Print the run journal - who was already reached, and whether the run finished
- then exit without touching Outlook.

.EXAMPLE
.\HighRise-Merge.ps1 -Csv contacts.csv -Template letter.txt -DryRun

.EXAMPLE
.\HighRise-Merge.ps1 -Csv contacts.csv -Template letter.txt
Creates one Outlook draft per sendable recipient; review them in Drafts.

.EXAMPLE
.\HighRise-Merge.ps1 -Csv contacts.csv -Template letter.txt -Send -BccSelf me@example.com
#>
[CmdletBinding(DefaultParameterSetName = 'Merge')]
param(
    [Parameter(ParameterSetName = 'Merge', Mandatory = $true, Position = 0)]
    [string]$Csv,

    [Parameter(ParameterSetName = 'Merge', Mandatory = $true, Position = 1)]
    [string]$Template,

    [string]$EmailColumn,
    [string]$Delimiter,
    [string]$Cc = '',
    [string]$Bcc = '',
    [string]$BccSelf = '',
    [string[]]$Attach = @(),
    [switch]$Send,
    [switch]$Force,
    [switch]$DryRun,
    [int]$ThrottleSeconds = 0,
    [string]$ReportCsv,
    # Path to the do-not-contact list. Defaults to the shared location
    # %APPDATA%\HighRise\do-not-contact.json; point it at a Mac's exported
    # file to use the same list.
    [string]$DoNotContact,
    # Ignore the do-not-contact list entirely. Deliberately awkward to reach:
    # it exists for testing, not for routine sending.
    [switch]$IgnoreDoNotContact,
    # Durable run journal. Defaults to %APPDATA%\HighRise\last-run.json.
    [string]$RunLog,
    [switch]$NoRunLog,
    # Re-deliver to people an unfinished previous run already reached.
    # Deliberately awkward to reach, like -IgnoreDoNotContact.
    [switch]$IgnorePreviousRun,
    [Parameter(ParameterSetName = 'ShowLastRun', Mandatory = $true)]
    [switch]$ShowLastRun
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Text / file helpers
# ---------------------------------------------------------------------------

# BOM-aware text reading (UTF-8 default, UTF-16 both endians), falling back to
# Windows-1252 when the bytes aren't valid UTF-8 - mirrors the Mac app's
# tolerant CSV ingestion.
function Read-TextFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found: $Path"
    }
    $bytes = [System.IO.File]::ReadAllBytes((Convert-Path -LiteralPath $Path))
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        return $strictUtf8.GetString($bytes)
    } catch {
        try { return [System.Text.Encoding]::GetEncoding(1252).GetString($bytes) }
        catch { return [System.Text.Encoding]::Default.GetString($bytes) }
    }
}

# ---------------------------------------------------------------------------
# Email validation (same pragmatic regex as EmailValidator.swift)
# ---------------------------------------------------------------------------

$script:EmailRegex = [regex]'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'

function Test-EmailAddress {
    param([string]$Candidate)
    if ($null -eq $Candidate) { return $false }
    $trimmed = $Candidate.Trim()
    return ($trimmed -ne '' -and $script:EmailRegex.IsMatch($trimmed))
}

# ---------------------------------------------------------------------------
# Do-not-contact list (mirrors DoNotContactStore.swift)
# ---------------------------------------------------------------------------
#
# Addresses and whole domains that must never be emailed. The Mac and iPhone
# apps keep the same list in the same JSON shape - an array of
# {kind, value, dateAdded, note} - so the file can be copied between machines
# and behaves identically. Entries are already normalized (trimmed,
# lowercased) by whichever app wrote them; we re-normalize on read anyway so a
# hand-edited file still works.

function Get-DoNotContactPath {
    param([string]$Override)
    if ($Override) { return $Override }
    if ($env:APPDATA) { return (Join-Path $env:APPDATA 'HighRise\do-not-contact.json') }
    return (Join-Path $HOME 'HighRise\do-not-contact.json')
}

function Import-DoNotContact {
    param([string]$Path)
    # Deliberately NOT a property called Count: PowerShell exposes an
    # intrinsic .Count on every object, so a note property of that name never
    # sticks and the list silently reads as empty - which would mean emailing
    # people who opted out. The hashtables carry their own real counts.
    $addresses = @{}
    $domains = @{}
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        try {
            $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
            if ($null -ne $raw) {
                $raw = $raw.TrimStart([char]0xFEFF, [char]0xFFFE).Trim()
            }
            $entries = if ($raw) { @(ConvertFrom-Json -InputObject $raw) } else { @() }
        } catch {
            # A corrupt list must never silently mean "email everyone" - say so
            # loudly and stop, rather than sending to someone who opted out.
            throw "The do-not-contact list at $Path could not be read: $($_.Exception.Message)"
        }
        foreach ($e in $entries) {
            if ($null -eq $e) { continue }
            $value = ([string]$e.value).Trim().ToLowerInvariant()
            if (-not $value) { continue }
            switch (([string]$e.kind).ToLowerInvariant()) {
                'address' { $addresses[$value] = $true }
                'domain'  { $domains[$value.TrimStart('@')] = $true }
            }
        }
    }
    return [pscustomobject]@{ Addresses = $addresses; Domains = $domains }
}

# ---------------------------------------------------------------------------
# Durable run journal (mirrors SendRunLog.swift / SendRunLogStore)
# ---------------------------------------------------------------------------
#
# $outcomes lives only in memory and is only written out at the very end, and
# only when -ReportCsv was passed. So a crash, a closed console or Ctrl-C 300
# recipients into a 1,000-recipient run used to destroy the only record of who
# had already been emailed - which made an innocent "just run it again" a
# silent double-send to those 300 people.
#
# The journal is written record-by-record as the run progresses and is only
# marked finished once the delivery loop ends normally. An unfinished journal
# for this same CSV + template therefore means "the last attempt died partway
# through", and the addresses it already delivered to are skipped.
#
# Dates are ISO-8601 round-trip strings. This file is per-machine; unlike the
# do-not-contact list it is not a cross-platform format.

function Get-RunLogPath {
    param([string]$Override)
    if ($Override) { return $Override }
    if ($env:APPDATA) { return (Join-Path $env:APPDATA 'HighRise\last-run.json') }
    return (Join-Path $HOME 'HighRise\last-run.json')
}

function Import-RunLog {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ($null -ne $raw) { $raw = $raw.TrimStart([char]0xFEFF, [char]0xFFFE).Trim() }
        if (-not $raw) { return $null }
        $log = ConvertFrom-Json -InputObject $raw
    } catch {
        # A corrupt journal must never quietly read as "nobody was reached" -
        # that is exactly the double-send this file exists to prevent.
        throw "The run journal at $Path could not be read: $($_.Exception.Message). Delete it or pass -NoRunLog once you are sure who was already emailed."
    }
    if ($null -eq $log) { return $null }
    # ConvertFrom-Json unwraps a one-element array, so re-wrap defensively.
    $records = @()
    if ($null -ne $log.records) { $records = @($log.records) }
    return [pscustomobject]@{
        StartedAt = [string]$log.startedAt
        Mode      = [string]$log.mode
        Csv       = [string]$log.csv
        Template  = [string]$log.template
        Total     = [int]$log.total
        Finished  = [bool]$log.finished
        Records   = $records
    }
}

function Save-RunLog {
    param($Log, [string]$Path)
    if (-not $Path) { return }
    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            [void](New-Item -ItemType Directory -Path $dir -Force)
        }
        $payload = [pscustomobject]@{
            startedAt = $Log.StartedAt
            mode      = $Log.Mode
            csv       = $Log.Csv
            template  = $Log.Template
            total     = $Log.Total
            finished  = [bool]$Log.Finished
            records   = @($Log.Records)
        }
        $json = $payload | ConvertTo-Json -Depth 5
        # Write beside the target and swap, so a kill mid-write cannot leave a
        # half-written journal in place of a good one.
        $tmp = "$Path.tmp"
        Set-Content -LiteralPath $tmp -Value $json -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } catch {
        # Journaling must never be the thing that stops a run.
        Write-Warning "Could not update the run journal at ${Path}: $($_.Exception.Message)"
    }
}

function Add-RunLogRecord {
    param($Log, [string]$Path, [string]$Email, [string]$Name,
          [string]$Status, [string]$Reason = '')
    if ($null -eq $Log) { return }
    $Log.Records = @($Log.Records) + , [pscustomobject]@{
        email  = $Email
        name   = $Name
        status = $Status
        reason = $Reason
        at     = (Get-Date).ToString('o')
    }
    Save-RunLog -Log $Log -Path $Path
}

# The addresses a journal records as actually reached. "would send"/"would
# draft" rows from a dry run are not deliveries and never cause a skip.
function Get-RunLogDelivered {
    param($Log)
    $delivered = @{}
    if ($null -eq $Log) { return $delivered }
    foreach ($r in @($Log.Records)) {
        if ($null -eq $r) { continue }
        $status = ([string]$r.status).ToLowerInvariant()
        if ($status -ne 'sent' -and $status -ne 'drafted') { continue }
        $address = ([string]$r.email).Trim().ToLowerInvariant()
        if ($address) { $delivered[$address] = [string]$r.status }
    }
    return $delivered
}

function Show-RunLog {
    param($Log, [string]$Path)
    if ($null -eq $Log) {
        Write-Host "No run journal at $Path - nothing has been recorded yet."
        return
    }
    $delivered = Get-RunLogDelivered $Log
    $state = 'finished normally'
    if (-not $Log.Finished) { $state = 'DID NOT FINISH' }
    Write-Host "Run journal: $Path"
    Write-Host "Started:  $($Log.StartedAt)   Mode: $($Log.Mode)   $state"
    Write-Host "List:     $($Log.Csv)"
    Write-Host "Template: $($Log.Template)"
    Write-Host "Reached $($delivered.Count) of $($Log.Total) recipient(s)."
    Write-Host ''
    foreach ($r in @($Log.Records)) {
        if ($null -eq $r) { continue }
        $detail = ''
        if ($r.reason) { $detail = " - $($r.reason)" }
        Write-Host ("  [{0}] {1} <{2}>{3}" -f ([string]$r.status).ToUpperInvariant(), $r.name, $r.email, $detail)
    }
    if (-not $Log.Finished) {
        Write-Host ''
        Write-Host 'This run did not finish. Re-running the same list and template will skip the recipients above.' -ForegroundColor Yellow
    }
}

function Get-SuppressionCount {
    param($List)
    if (-not $List) { return 0 }
    return ($List.Addresses.Count + $List.Domains.Count)
}

function Test-Suppressed {
    param($List, [string]$Email)
    if (-not $List) { return $false }
    if ((Get-SuppressionCount $List) -eq 0) { return $false }
    $address = ([string]$Email).Trim().ToLowerInvariant()
    if (-not $address) { return $false }
    if ($List.Addresses.ContainsKey($address)) { return $true }
    $at = $address.IndexOf('@')
    if ($at -ge 0) {
        $domain = $address.Substring($at + 1)
        if ($List.Domains.ContainsKey($domain)) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Merge filters (mirrors MergeValueFormatter.swift)
# ---------------------------------------------------------------------------

$script:EnUS = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
$script:Invariant = [System.Globalization.CultureInfo]::InvariantCulture

# Currency-code -> symbol map (Foundation looks these up from ICU; .NET has no
# equivalent API, so common codes are mapped and anything else renders as
# "CODE 1,234.50"). Symbols are built from code points so this file stays ASCII.
$script:CurrencySymbols = @{
    'USD' = '$'
    'EUR' = [string][char]0x20AC
    'GBP' = [string][char]0x00A3
    'JPY' = [string][char]0x00A5
    'CNY' = [string][char]0x00A5
    'INR' = [string][char]0x20B9
    'KRW' = [string][char]0x20A9
    'CAD' = 'CA$'
    'AUD' = 'A$'
    'NZD' = 'NZ$'
    'HKD' = 'HK$'
    'MXN' = 'MX$'
    'BRL' = 'R$'
}
$script:ZeroDecimalCurrencies = @('JPY', 'KRW', 'VND', 'CLP', 'ISK')

# Extracts a number from text that may carry symbols or separators
# ("$1,234.50" -> 1234.5). Returns $null when nothing numeric remains.
function ConvertTo-MergeNumber {
    param([string]$Value)
    $allowed = -join ($Value.ToCharArray() | Where-Object {
        [char]::IsDigit($_) -or $_ -eq '.' -or $_ -eq '-'
    })
    $number = 0.0
    $ok = [double]::TryParse($allowed, [System.Globalization.NumberStyles]::Float,
                             $script:Invariant, [ref]$number)
    if ($ok) { return $number }
    return $null
}

# Best-effort date parsing: ISO 8601, common written formats, and Excel serial
# day numbers (days since 1899-12-30). Returns a UTC [datetime] or $null.
function ConvertTo-MergeDate {
    param([string]$Value)
    $trimmed = $Value.Trim()
    if ($trimmed -eq '') { return $null }

    $formats = @(
        "yyyy-MM-dd'T'HH:mm:ssK", "yyyy-MM-dd'T'HH:mm:ss.FFFK",
        'yyyy-MM-dd', 'yyyy/MM/dd', 'MM/dd/yyyy', 'M/d/yyyy',
        'dd-MM-yyyy', 'dd/MM/yyyy', "yyyy-MM-dd'T'HH:mm:ss"
    )
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
              [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact($trimmed, [string[]]$formats, $script:Invariant,
                                  $styles, [ref]$parsed)) {
        return $parsed
    }

    $serial = 0.0
    if ([double]::TryParse($trimmed, [System.Globalization.NumberStyles]::Float,
                           $script:Invariant, [ref]$serial)) {
        if ($serial -gt 0 -and $serial -lt 600000) {
            $epoch = New-Object datetime 1899, 12, 30, 0, 0, 0, ([System.DateTimeKind]::Utc)
            return $epoch.AddSeconds($serial * 86400)
        }
    }
    return $null
}

function Remove-WrappingQuotes {
    param([string]$Value)
    if ($Value.Length -ge 2) {
        $first = $Value[0]
        $last = $Value[$Value.Length - 1]
        if ($first -eq $last -and ($first -eq '"' -or $first -eq "'")) {
            return $Value.Substring(1, $Value.Length - 2)
        }
    }
    return $Value
}

# Parses one pipe-separated filter segment. An unrecognized segment is bare
# fallback text, preserving the simple {{First Name|there}} form.
function ConvertTo-MergeFilter {
    param([string]$Segment)
    $trimmed = $Segment.Trim()
    $name = $trimmed
    $arg = $null
    $colon = $trimmed.IndexOf(':')
    if ($colon -ge 0) {
        $name = $trimmed.Substring(0, $colon).Trim()
        $arg = Remove-WrappingQuotes ($trimmed.Substring($colon + 1).Trim())
    }
    switch ($name.ToLower()) {
        { $_ -in 'upper', 'uppercase' }              { return @{ Kind = 'upper' } }
        { $_ -in 'lower', 'lowercase' }              { return @{ Kind = 'lower' } }
        { $_ -in 'capitalize', 'title', 'titlecase' } { return @{ Kind = 'capitalize' } }
        { $_ -in 'fixcaps', 'fixcase' }              { return @{ Kind = 'fixcaps' } }
        'trim'                                       { return @{ Kind = 'trim' } }
        { $_ -in 'number', 'comma' }                 { return @{ Kind = 'number' } }
        'date'     { if ($null -ne $arg) { return @{ Kind = 'date'; Arg = $arg } } }
        'currency' { if ($null -ne $arg) { return @{ Kind = 'currency'; Arg = $arg } } }
        'default'  { if ($null -eq $arg) { $arg = '' }; return @{ Kind = 'default'; Arg = $arg } }
    }
    return @{ Kind = 'default'; Arg = $trimmed }
}

# Applies one transforming filter. Unknown/unparseable input passes through
# unchanged - formatting never throws away the underlying data.
function Invoke-MergeFilter {
    param([hashtable]$Filter, [string]$Value)
    switch ($Filter.Kind) {
        'default' { return $Value }  # fallbacks are handled during resolution
        'upper'   { return $Value.ToUpper($script:EnUS) }
        'lower'   { return $Value.ToLower($script:EnUS) }
        'trim'    { return $Value.Trim() }
        'capitalize' {
            return $script:EnUS.TextInfo.ToTitleCase($Value.ToLower($script:EnUS))
        }
        'fixcaps' {
            # Repair shouty ALL-CAPS, leave already-mixed-case text untouched.
            if ([regex]::IsMatch($Value, '\p{L}') -and
                -not [regex]::IsMatch($Value, '[\p{Ll}\p{Lt}]')) {
                return $script:EnUS.TextInfo.ToTitleCase($Value.ToLower($script:EnUS))
            }
            return $Value
        }
        'number' {
            $n = ConvertTo-MergeNumber $Value
            if ($null -eq $n) { return $Value }
            return $n.ToString('#,##0.##', $script:EnUS)
        }
        'currency' {
            $n = ConvertTo-MergeNumber $Value
            if ($null -eq $n) { return $Value }
            $code = $Filter.Arg.ToUpper()
            $pattern = '#,##0.00'
            if ($script:ZeroDecimalCurrencies -contains $code) { $pattern = '#,##0' }
            $magnitude = [math]::Abs($n).ToString($pattern, $script:EnUS)
            $sign = ''
            if ($n -lt 0) { $sign = '-' }
            if ($script:CurrencySymbols.ContainsKey($code)) {
                return $sign + $script:CurrencySymbols[$code] + $magnitude
            }
            return $sign + $code + ' ' + $magnitude
        }
        'date' {
            $d = ConvertTo-MergeDate $Value
            if ($null -eq $d) { return $Value }
            try { return $d.ToString($Filter.Arg, $script:EnUS) }
            catch { return $Value }
        }
    }
    return $Value
}

# ---------------------------------------------------------------------------
# Placeholder engine (mirrors EmailTemplate + TemplateMergeEngine)
# ---------------------------------------------------------------------------

$script:PlaceholderRegex = [regex]'\{\{\s*([^{}]+?)\s*\}\}'

# The placeholder regex deliberately refuses to match across a brace, so an
# unbalanced token like "{{Company" is never seen as a placeholder at all: it
# is not resolved, not recorded as unresolved, and not stripped - it survives
# verbatim into the subject or body the recipient reads. Counting the braces
# catches the common case early, before anything is drafted; the rendered-text
# scan below is what actually blocks the row. Mirrors
# PlaceholderCheck.malformedWarning on macOS/iOS, message included, so the three
# platforms say the same thing.
function Get-MalformedPlaceholderWarning {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    $opens = ([regex]::Matches($Text, '\{\{')).Count
    $closes = ([regex]::Matches($Text, '\}\}')).Count
    if ($opens -eq $closes) { return $null }
    return $script:MalformedPlaceholderMessage
}

# The one wording used everywhere braces don't line up, so the up-front template
# warning and the per-row block say the same thing. Matches PlaceholderCheck.message
# on macOS/iOS, transliterated to ASCII (Windows PowerShell 5.1 requirement).
$script:MalformedPlaceholderMessage =
    'Unclosed merge field - check your {{ }} braces so every field fills in.'

# Brace fragments still present in *already merged* text.
#
# The count check above is a template-level heuristic and can be fooled: two
# typos that happen to balance ("{{A }}B{{") slip past it, and it says nothing
# at all about braces that arrive in a CSV *value* rather than the template.
# Scanning what actually rendered is the check that cannot be fooled, and it is
# what lets a row be blocked rather than merely warned about.
#
# Returns short quotable snippets (deduplicated, in order) for the blocking
# reason, and nothing at all when the merged text is clean. A faithful port of
# PlaceholderCheck.leftoverBraceFragments on macOS/iOS - keep the two in step.
#
# The list is returned bare, NOT comma-wrapped: PowerShell unrolls it into zero,
# one, or many strings, and every call site wraps the call in @(...) to get an
# array back. Comma-wrapping here would hand each caller a single element - the
# list object itself - so a clean row would look like it had one fragment and
# be blocked over an empty quote.
function Get-LeftoverBraceFragments {
    param([string]$Text, [int]$Limit = 3)

    $fragments = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrEmpty($Text)) { return $fragments }
    if (-not ($Text.Contains('{{') -or $Text.Contains('}}'))) { return $fragments }

    $snippetLength = 24
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $characters = $Text.ToCharArray()
    $index = 0

    while ($index + 1 -lt $characters.Count -and $fragments.Count -lt $Limit) {
        $pair = [string]$characters[$index] + [string]$characters[$index + 1]
        if ($pair -cne '{{' -and $pair -cne '}}') {
            $index++
            continue
        }
        # Quote from the marker up to a line break or the next brace marker,
        # capped so a whole paragraph never lands in a one-line blocking
        # reason. Stopping at the next marker keeps each fragment tight and
        # lets repeats of the same typo collapse together.
        $end = [Math]::Min($index + $snippetLength, $characters.Count)
        $snippet = New-Object System.Text.StringBuilder
        [void]$snippet.Append($pair)
        $scan = $index + 2
        while ($scan -lt $end) {
            $character = $characters[$scan]
            if ($character -eq "`n" -or $character -eq "`r") { break }
            if ($scan + 1 -lt $characters.Count) {
                $ahead = [string]$characters[$scan] + [string]$characters[$scan + 1]
                if ($ahead -ceq '{{' -or $ahead -ceq '}}') { break }
            }
            [void]$snippet.Append($character)
            $scan++
        }
        $trimmed = $snippet.ToString().Trim()
        if ($trimmed -ne '' -and $seen.Add($trimmed)) { $fragments.Add($trimmed) }
        $index += 2
    }
    return $fragments
}

# Parses the inner text of one {{ ... }} into a name, an optional fallback
# (first default: / bare-text filter), and the transforming filters in order.
function ConvertTo-PlaceholderToken {
    param([string]$Inner)
    $pieces = $Inner -split '\|'
    $name = $pieces[0].Trim()
    $fallback = $null
    $hasFallback = $false
    $transforms = @()
    for ($i = 1; $i -lt $pieces.Count; $i++) {
        $filter = ConvertTo-MergeFilter $pieces[$i]
        if ($filter.Kind -eq 'default') {
            if (-not $hasFallback) { $fallback = $filter.Arg; $hasFallback = $true }
        } else {
            $transforms += , $filter
        }
    }
    return @{ Name = $name; HasFallback = $hasFallback; Fallback = $fallback; Transforms = $transforms }
}

function ConvertTo-HtmlEscaped {
    param([string]$Value)
    return $Value.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&#39;')
}

# Case-insensitive, whitespace-tolerant field lookup: {{ company }} and
# {{Company}} resolve the same. Returns the raw value, or $null when the field
# is absent or blank.
function Get-ContactValue {
    param([System.Collections.IDictionary]$Fields, [string]$Name)
    $wanted = $Name.Trim().ToLower()
    foreach ($key in $Fields.Keys) {
        if ($key.ToLower() -eq $wanted) {
            $value = [string]$Fields[$key]
            if ($value.Trim() -ne '') { return $value }
            return $null
        }
    }
    return $null
}

# Substitutes every {{Field}} in $Text against $Fields. Unresolved placeholders
# (no matching non-empty field and no fallback) are removed from the output -
# no raw {{...}} ever reaches a recipient - and their names are appended to
# $Unresolved (when given) so the row can be blocked.
function Resolve-MergeText {
    param(
        [string]$Text,
        [System.Collections.IDictionary]$Fields,
        [bool]$EscapeHtml = $false,
        [System.Collections.Generic.List[string]]$Unresolved = $null,
        [System.Collections.Generic.HashSet[string]]$SeenUnresolved = $null
    )
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $sb = New-Object System.Text.StringBuilder
    $lastEnd = 0
    foreach ($match in $script:PlaceholderRegex.Matches($Text)) {
        [void]$sb.Append($Text.Substring($lastEnd, $match.Index - $lastEnd))
        $lastEnd = $match.Index + $match.Length

        $token = ConvertTo-PlaceholderToken $match.Groups[1].Value
        $base = Get-ContactValue -Fields $Fields -Name $token.Name
        if ($null -eq $base) {
            if ($token.HasFallback) {
                $base = $token.Fallback
            } else {
                if ($null -ne $Unresolved) {
                    if ($SeenUnresolved.Add($token.Name.ToLower())) {
                        $Unresolved.Add($token.Name)
                    }
                }
                continue
            }
        }
        $resolved = $base
        foreach ($filter in $token.Transforms) {
            $resolved = Invoke-MergeFilter -Filter $filter -Value $resolved
        }
        if ($EscapeHtml) { $resolved = ConvertTo-HtmlEscaped $resolved }
        [void]$sb.Append($resolved)
    }
    [void]$sb.Append($Text.Substring($lastEnd))
    return $sb.ToString()
}

# Resolves a CC/BCC address list for one contact: merge {{Field}} references,
# split on commas/semicolons, keep only valid addresses, de-duplicate.
function Resolve-AddressList {
    param([string]$Raw, [System.Collections.IDictionary]$Fields)
    $result = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Raw)) { return , $result }
    $merged = Resolve-MergeText -Text $Raw -Fields $Fields
    $seen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($piece in ($merged -split '[,;]')) {
        $address = $piece.Trim()
        if (-not (Test-EmailAddress $address)) { continue }
        if ($seen.Add($address.ToLower())) { $result.Add($address) }
    }
    return , $result
}

# ---------------------------------------------------------------------------
# Template file parsing
# ---------------------------------------------------------------------------

function Read-TemplateFile {
    param([string]$Path)
    $text = Read-TextFile $Path
    $lines = $text -split "`r?`n"
    if ($lines.Count -eq 0 -or $lines[0] -notmatch '^(?i)Subject\s*:\s*(.*)$') {
        throw ("Template file must start with a 'Subject:' line, e.g.`n" +
               "  Subject: Quick question about {{Company}}`n" +
               "  (optional) Format: html`n" +
               "  <blank line>`n" +
               "  Hi {{Name}}, ...body...")
    }
    $subject = $Matches[1].Trim()
    $isHtml = $false
    $index = 1
    if ($index -lt $lines.Count -and $lines[$index] -match '^(?i)Format\s*:\s*(.*)$') {
        $format = $Matches[1].Trim().ToLower()
        if ($format -in 'html', 'htm') { $isHtml = $true }
        elseif ($format -notin 'plain', 'plaintext', 'plain text', 'text', 'txt') {
            throw "Unknown template format '$format' - use 'plain' or 'html'."
        }
        $index++
    }
    if ($index -lt $lines.Count -and $lines[$index].Trim() -eq '') { $index++ }
    $body = ''
    if ($index -lt $lines.Count) {
        $body = ($lines[$index..($lines.Count - 1)] -join "`r`n").TrimEnd()
    }
    return @{ Subject = $subject; Body = $body; IsHtml = $isHtml }
}

# ---------------------------------------------------------------------------
# CSV -> contacts (mirrors CSVParser + HighRiseCoordinator column detection)
# ---------------------------------------------------------------------------

function Get-CsvDelimiter {
    param([string]$Text)
    $firstLine = ($Text -split "`r?`n", 2)[0]
    $counts = @{ ',' = 0; ';' = 0; "`t" = 0 }
    $inQuotes = $false
    foreach ($ch in $firstLine.ToCharArray()) {
        if ($ch -eq '"') { $inQuotes = -not $inQuotes }
        elseif (-not $inQuotes) {
            $key = [string]$ch
            if ($counts.ContainsKey($key)) { $counts[$key] = $counts[$key] + 1 }
        }
    }
    $best = ','
    $bestCount = -1
    foreach ($candidate in @(',', ';', "`t")) {
        if ($counts[$candidate] -gt $bestCount) {
            $best = $candidate
            $bestCount = $counts[$candidate]
        }
    }
    return $best
}

# Picks the most likely email column: first a header that mentions "email",
# else the column whose values look most like addresses.
function Find-EmailColumn {
    param([string[]]$Headers, [object[]]$Rows)
    foreach ($header in $Headers) {
        $h = $header.ToLower()
        if ($h.Contains('email') -or $h.Contains('e-mail') -or $h -eq 'mail') { return $header }
    }
    $best = $null
    $bestCount = 0
    foreach ($header in $Headers) {
        $count = 0
        foreach ($row in $Rows) {
            $value = $row.PSObject.Properties[$header].Value
            if ($null -ne $value -and (Test-EmailAddress ([string]$value))) { $count++ }
        }
        if ($count -gt $bestCount) { $best = $header; $bestCount = $count }
    }
    return $best
}

function Find-AttachmentColumn {
    param([string[]]$Headers)
    foreach ($header in $Headers) {
        if ($header.Trim().ToLower() -in 'attachment', 'attachments', 'file', 'files') {
            return $header
        }
    }
    return $null
}

# Splits an attachment cell into paths: ";"-separated, trimmed, "~" expanded.
function Get-AttachmentCellPaths {
    param([string]$CellValue)
    $paths = @()
    foreach ($piece in ($CellValue -split ';')) {
        $trimmed = $piece.Trim()
        if ($trimmed -eq '') { continue }
        if ($trimmed -eq '~') { $trimmed = $HOME }
        elseif ($trimmed.StartsWith('~/') -or $trimmed.StartsWith('~\')) {
            $trimmed = Join-Path $HOME $trimmed.Substring(2)
        }
        $paths += , $trimmed
    }
    return , $paths
}

# A human label for a contact: prefers a name-like column, falls back to email.
function Get-DisplayName {
    param([System.Collections.IDictionary]$Fields, [string]$Email)
    foreach ($key in @('name', 'full name', 'fullname', 'contact',
                       'contact name', 'first name', 'firstname', 'company')) {
        $value = Get-ContactValue -Fields $Fields -Name $key
        if ($null -ne $value) { return $value.Trim() }
    }
    return $Email
}

# ---------------------------------------------------------------------------
# Outlook delivery (COM automation of classic Outlook for Windows)
# ---------------------------------------------------------------------------

function Connect-Outlook {
    try {
        return New-Object -ComObject Outlook.Application
    } catch {
        throw (@"
Could not start Outlook automation ($($_.Exception.Message)).

HighRise-Merge drives *classic* Outlook for Windows through COM. Check that:
  1. Outlook (Microsoft 365, or Outlook 2016 or newer) is installed - not just
     the Mail app or outlook.com in a browser.
  2. You are using CLASSIC Outlook. The "new Outlook" (the toggle in the top
     right of the Outlook window) does not support automation yet - switch the
     "New Outlook" toggle OFF, or install classic Outlook from your Microsoft
     365 apps.
  3. Outlook has been launched at least once and has a mail account set up.

You can always preview the merge without Outlook using -DryRun.
"@)
    }
}

function New-OutlookMessage {
    param($OutlookApp, $Preview, [bool]$IsHtml, [string[]]$SharedAttachments, [bool]$SendNow)
    $mail = $OutlookApp.CreateItem(0)  # 0 = olMailItem
    $mail.To = $Preview.Email
    if ($Preview.Cc.Count -gt 0) { $mail.CC = ($Preview.Cc -join '; ') }
    if ($Preview.Bcc.Count -gt 0) { $mail.BCC = ($Preview.Bcc -join '; ') }
    $mail.Subject = $Preview.Subject
    if ($IsHtml) { $mail.HTMLBody = $Preview.Body } else { $mail.Body = $Preview.Body }
    foreach ($path in ($SharedAttachments + $Preview.AttachmentPaths)) {
        [void]$mail.Attachments.Add((Convert-Path -LiteralPath $path))
    }
    if ($SendNow) { $mail.Send() } else { [void]$mail.Save() }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$rule = '-' * 60

$runLogPath = $null
if (-not $NoRunLog) { $runLogPath = Get-RunLogPath $RunLog }

# 0. Just show the journal and stop.
if ($ShowLastRun) {
    if ($NoRunLog) { throw '-ShowLastRun and -NoRunLog contradict each other.' }
    Show-RunLog -Log (Import-RunLog $runLogPath) -Path $runLogPath
    exit 0
}

# 1. Template.
$templateSpec = Read-TemplateFile $Template
$templateFullPath = (Convert-Path -LiteralPath $Template)

# A malformed token is a template-level typo, so it would hit every recipient
# at once. Say so before anything is drafted, and say it on -DryRun too - a dry
# run is exactly where this is meant to be caught. This up-front notice stays a
# warning because the count is a heuristic; the per-row scan of the *merged*
# text below is the hard block, and it is what keeps raw braces out of a
# recipient's inbox.
foreach ($part in @(
    @{ Name = 'Subject'; Text = $templateSpec.Subject },
    @{ Name = 'Body'; Text = $templateSpec.Body }
)) {
    $braceWarning = Get-MalformedPlaceholderWarning $part.Text
    if ($braceWarning) {
        Write-Host ("WARNING: {0}: {1}" -f $part.Name, $braceWarning) -ForegroundColor Yellow
    }
}

# 2. Recipients.
$csvText = Read-TextFile $Csv
$csvFullPath = (Convert-Path -LiteralPath $Csv)
if ($csvText.Trim() -eq '') { throw "The CSV file is empty: $Csv" }
if (-not $Delimiter) { $Delimiter = Get-CsvDelimiter $csvText }
$rows = @($csvText | ConvertFrom-Csv -Delimiter $Delimiter)
if ($rows.Count -eq 0) { throw "No data rows found in $Csv (is it just a header line?)" }
$headers = @($rows[0].PSObject.Properties.Name)

# 3. Column detection.
if ($EmailColumn) {
    $emailHeader = $headers | Where-Object { $_.ToLower() -eq $EmailColumn.Trim().ToLower() } |
                   Select-Object -First 1
    if (-not $emailHeader) {
        throw "Column '$EmailColumn' not found. Headers: $($headers -join ', ')"
    }
} else {
    $emailHeader = Find-EmailColumn -Headers $headers -Rows $rows
    if (-not $emailHeader) {
        throw ("Could not find an email column (no header mentions 'email' and no column " +
               "contains addresses). Pass one explicitly: -EmailColumn 'Work Email'")
    }
}
$attachmentHeader = Find-AttachmentColumn -Headers $headers

# 4. Shared attachments must all exist before anything is composed.
$missingShared = @($Attach | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missingShared.Count -gt 0) {
    throw "Attachment file(s) not found: $($missingShared -join ', ')"
}
if ($Attach.Count -gt 0) {
    $totalBytes = 0
    foreach ($path in $Attach) { $totalBytes += (Get-Item -LiteralPath $path).Length }
    if ($totalBytes -gt 20MB) {
        $mb = [math]::Round($totalBytes / 1MB)
        Write-Warning ("Attachments total about $mb MB. Many mail servers reject messages over " +
                       "~25 MB (encoding adds ~33%) - consider a link instead for large files.")
    }
}

# 5. Merge every row (order preserved; first occurrence of an address wins).
# Load the do-not-contact list first so every row is checked against it.
$script:SuppressionList = $null
if (-not $IgnoreDoNotContact) {
    $dncPath = Get-DoNotContactPath -Override $DoNotContact
    $script:SuppressionList = Import-DoNotContact -Path $dncPath
    $dncCount = Get-SuppressionCount $script:SuppressionList
    if ($dncCount -gt 0) {
        Write-Host "Do-not-contact list: $dncCount entr(y/ies) from $dncPath"
    } elseif ($DoNotContact) {
        # An explicitly named list that turned out to be empty is worth saying
        # out loud - it usually means the wrong path.
        Write-Host "Do-not-contact list at $dncPath is empty."
    }
} else {
    Write-Host "WARNING: -IgnoreDoNotContact was passed - the do-not-contact list is NOT being applied."
}

$previews = @()
$seenEmails = New-Object System.Collections.Generic.HashSet[string]
foreach ($row in $rows) {
    $fields = [ordered]@{}
    foreach ($header in $headers) {
        $value = $row.PSObject.Properties[$header].Value
        if ($null -eq $value) { $value = '' }
        $fields[$header.Trim()] = [string]$value
    }
    $email = ([string]$fields[$emailHeader.Trim()]).Trim()

    $unresolved = New-Object System.Collections.Generic.List[string]
    $seenUnresolved = New-Object System.Collections.Generic.HashSet[string]
    $subject = Resolve-MergeText -Text $templateSpec.Subject -Fields $fields `
                                 -Unresolved $unresolved -SeenUnresolved $seenUnresolved
    $body = Resolve-MergeText -Text $templateSpec.Body -Fields $fields `
                              -EscapeHtml $templateSpec.IsHtml `
                              -Unresolved $unresolved -SeenUnresolved $seenUnresolved

    $attachmentPaths = @()
    if ($attachmentHeader) {
        $cell = Get-ContactValue -Fields $fields -Name $attachmentHeader
        if ($null -ne $cell) { $attachmentPaths = Get-AttachmentCellPaths $cell }
    }
    $missingAttachments = @($attachmentPaths | Where-Object { -not (Test-Path -LiteralPath $_) })

    # Last line of defence for "no raw {{placeholder}} reaches a recipient": the
    # merge regex only sees well-formed fields, so a malformed one survives
    # substitution untouched. Scanning what actually rendered catches it -
    # whether the braces came from a template typo or from a CSV value - and
    # blocks the row. Subject then body, matching TemplateMergeEngine.merge.
    $malformed = @()
    $malformed += @(Get-LeftoverBraceFragments -Text $subject)
    $malformed += @(Get-LeftoverBraceFragments -Text $body)

    $hasValidEmail = Test-EmailAddress $email
    $isDuplicate = $false
    if ($hasValidEmail) { $isDuplicate = -not $seenEmails.Add($email.ToLower()) }
    $isSuppressed = Test-Suppressed -List $script:SuppressionList -Email $email

    # Blocking mirrors MergePreview.blockingReason on the Mac, in the same
    # order - suppression sits right after an unusable address, ahead of
    # missing data, so someone who opted out is reported as opted out rather
    # than as a data problem, and a malformed field outranks missing data
    # because it is a template-level typo rather than a gap in this row.
    $reason = $null
    if (-not $hasValidEmail) {
        if ($email -eq '') { $reason = 'No email address.' }
        else { $reason = "Invalid email address: $email" }
    } elseif ($isSuppressed) {
        $reason = "On your do-not-contact list - $email is skipped."
    } elseif ($malformed.Count -gt 0) {
        $quoted = ($malformed | ForEach-Object { '"' + $_ + '"' }) -join ', '
        $reason = "$script:MalformedPlaceholderMessage Found $quoted."
    } elseif ($unresolved.Count -gt 0) {
        $reason = "Missing data for: $($unresolved -join ', ')"
    } elseif ($missingAttachments.Count -gt 0) {
        $names = @($missingAttachments | ForEach-Object { Split-Path $_ -Leaf })
        $reason = "Attachment file not found: $($names -join ', ')"
    } elseif ($isDuplicate) {
        $reason = "Duplicate of an earlier recipient - held back so $email isn't emailed twice."
    }

    $previews += , [pscustomobject]@{
        DisplayName     = Get-DisplayName -Fields $fields -Email $email
        Email           = $email
        Subject         = $subject
        Body            = $body
        Cc              = Resolve-AddressList -Raw $Cc -Fields $fields
        Bcc             = & {
            $list = Resolve-AddressList -Raw $Bcc -Fields $fields
            $self = $BccSelf.Trim()
            if ((Test-EmailAddress $self) -and -not ($list | Where-Object { $_.ToLower() -eq $self.ToLower() })) {
                $list.Add($self)
            }
            , $list
        }
        AttachmentPaths = $attachmentPaths
        BlockingReason  = $reason
    }
}

$mode = 'draft'
if ($Send) { $mode = 'send' }
Write-Host "Parsed $($previews.Count) contact(s) from $Csv"
Write-Host "Email column: $emailHeader  |  client: Outlook (Windows)  |  mode: $mode"
Write-Host ''

$sendable = @($previews | Where-Object { $null -eq $_.BlockingReason })
$blocked = @($previews | Where-Object { $null -ne $_.BlockingReason })

# 5b. An unfinished journal means the previous attempt died partway through.
#     Skip whoever it already reached, so a second attempt does not email the
#     same people twice.
$previousLog = $null
$alreadyDelivered = @{}
if ($runLogPath) { $previousLog = Import-RunLog $runLogPath }
if ($null -ne $previousLog -and -not $previousLog.Finished) {
    $sameRun = ($previousLog.Csv -eq $csvFullPath -and $previousLog.Template -eq $templateFullPath)
    $reached = Get-RunLogDelivered $previousLog
    if (-not $sameRun) {
        Write-Host "WARNING: the previous run (started $($previousLog.StartedAt)) did not finish, but it used a different list or template - nobody is being skipped." -ForegroundColor Yellow
        Write-Host "         Run -ShowLastRun to see who it reached." -ForegroundColor Yellow
        Write-Host ''
    } elseif ($IgnorePreviousRun) {
        Write-Host "WARNING: -IgnorePreviousRun was passed - the $($reached.Count) recipient(s) the unfinished previous run already reached will be contacted AGAIN." -ForegroundColor Yellow
        Write-Host ''
    } elseif ($reached.Count -gt 0) {
        $alreadyDelivered = $reached
        Write-Host "The previous run of this list started $($previousLog.StartedAt) and did not finish." -ForegroundColor Yellow
        Write-Host "Skipping the $($reached.Count) recipient(s) it already reached. Pass -IgnorePreviousRun to contact them again." -ForegroundColor Yellow
        Write-Host ''
    }
}

# 6. Confirm before a real immediate send.
if ($Send -and -not $DryRun -and -not $Force) {
    $toSend = @($sendable | Where-Object { -not $alreadyDelivered.ContainsKey($_.Email.ToLowerInvariant()) })
    Write-Host "About to SEND $($toSend.Count) message(s) immediately (no draft review)." -ForegroundColor Yellow
    $answer = Read-Host "Type SEND to confirm, anything else to cancel"
    if ($answer -cne 'SEND') {
        Write-Host 'Cancelled - nothing was sent. Re-run without -Send to create drafts instead.'
        exit 0
    }
}

# 7. Deliver (or preview).
$outlook = $null
if (-not $DryRun) { $outlook = Connect-Outlook }

$outcomes = @()
$successes = 0
$failures = 0
$skipped = 0

# Start this run's journal. It is saved again after every single recipient, so
# whatever kills the run, the record of who was already reached survives.
$journal = $null
if ($runLogPath) {
    $journal = [pscustomobject]@{
        StartedAt = (Get-Date).ToString('o')
        Mode      = $mode
        Csv       = $csvFullPath
        Template  = $templateFullPath
        Total     = $previews.Count
        Finished  = $false
        Records   = @()
    }
    if ($DryRun) { $journal.Mode = "would $mode" }
    # Carry the previous attempt's deliveries forward so the journal stays the
    # single answer to "who has already been emailed", across both attempts.
    if ($alreadyDelivered.Count -gt 0) { $journal.Records = @($previousLog.Records) }
    Save-RunLog -Log $journal -Path $runLogPath
}

foreach ($preview in $previews) {
    $label = "$($preview.DisplayName) <$($preview.Email)>"
    if ($null -ne $preview.BlockingReason) {
        Write-Host "[BLOCKED] $($preview.DisplayName) - $($preview.BlockingReason)" -ForegroundColor Yellow
        $outcomes += , [pscustomobject]@{
            Name = $preview.DisplayName; Email = $preview.Email
            Status = 'blocked'; Detail = $preview.BlockingReason
        }
        Add-RunLogRecord -Log $journal -Path $runLogPath -Email $preview.Email `
                         -Name $preview.DisplayName -Status 'blocked' -Reason $preview.BlockingReason
        continue
    }

    $key = ([string]$preview.Email).Trim().ToLowerInvariant()
    if ($alreadyDelivered.ContainsKey($key)) {
        $skipped++
        Write-Host "[SKIPPED] $label - already $($alreadyDelivered[$key]) by the unfinished previous run" -ForegroundColor Cyan
        $outcomes += , [pscustomobject]@{
            Name = $preview.DisplayName; Email = $preview.Email
            Status = 'skipped'; Detail = "already $($alreadyDelivered[$key]) by the unfinished previous run"
        }
        continue
    }

    if ($DryRun) {
        Write-Host "[OK] $label - would $mode this message:" -ForegroundColor Green
        Write-Host $rule
        Write-Host "To:      $($preview.Email)"
        if ($preview.Cc.Count -gt 0) { Write-Host "Cc:      $($preview.Cc -join '; ')" }
        if ($preview.Bcc.Count -gt 0) { Write-Host "Bcc:     $($preview.Bcc -join '; ')" }
        Write-Host "Subject: $($preview.Subject)"
        $allAttachments = @($Attach) + @($preview.AttachmentPaths)
        if ($allAttachments.Count -gt 0) { Write-Host "Attach:  $($allAttachments -join '; ')" }
        Write-Host ''
        Write-Host $preview.Body
        Write-Host $rule
        Write-Host ''
        $successes++
        $outcomes += , [pscustomobject]@{
            Name = $preview.DisplayName; Email = $preview.Email
            Status = "would $mode"; Detail = ''
        }
        Add-RunLogRecord -Log $journal -Path $runLogPath -Email $preview.Email `
                         -Name $preview.DisplayName -Status "would $mode"
        continue
    }

    try {
        New-OutlookMessage -OutlookApp $outlook -Preview $preview -IsHtml $templateSpec.IsHtml `
                           -SharedAttachments $Attach -SendNow $Send.IsPresent
        $successes++
        if ($Send) {
            Write-Host "[SENT] $label" -ForegroundColor Green
            $outcomes += , [pscustomobject]@{
                Name = $preview.DisplayName; Email = $preview.Email; Status = 'sent'; Detail = ''
            }
            # Journal it before the throttle sleep - that pause is the most
            # likely moment for someone to close the window.
            Add-RunLogRecord -Log $journal -Path $runLogPath -Email $preview.Email `
                             -Name $preview.DisplayName -Status 'sent'
            if ($ThrottleSeconds -gt 0) { Start-Sleep -Seconds $ThrottleSeconds }
        } else {
            Write-Host "[DRAFTED] $label" -ForegroundColor Green
            $outcomes += , [pscustomobject]@{
                Name = $preview.DisplayName; Email = $preview.Email; Status = 'drafted'; Detail = ''
            }
            Add-RunLogRecord -Log $journal -Path $runLogPath -Email $preview.Email `
                             -Name $preview.DisplayName -Status 'drafted'
        }
    } catch {
        $failures++
        Write-Host "[FAILED] $label - $($_.Exception.Message)" -ForegroundColor Red
        $outcomes += , [pscustomobject]@{
            Name = $preview.DisplayName; Email = $preview.Email
            Status = 'failed'; Detail = $_.Exception.Message
        }
        Add-RunLogRecord -Log $journal -Path $runLogPath -Email $preview.Email `
                         -Name $preview.DisplayName -Status 'failed' -Reason $_.Exception.Message
    }
}

# The loop ran to the end. Only now is the journal finished - a journal still
# marked unfinished is precisely how the next run knows it was interrupted.
if ($null -ne $journal) {
    $journal.Finished = $true
    Save-RunLog -Log $journal -Path $runLogPath
}

# 8. Summary + optional report.
Write-Host ''
if ($DryRun) {
    $verb = 'drafted'
    if ($Send) { $verb = 'sent' }
    Write-Host "Summary: $successes message(s) would be $verb, $($blocked.Count) blocked. No mail was touched."
} elseif ($Send) {
    Write-Host "Summary: $successes sent, $failures failed, $($blocked.Count) blocked, $skipped already reached by the previous run."
} else {
    Write-Host "Summary: $successes draft(s) created in Outlook's Drafts folder, $failures failed, $($blocked.Count) blocked, $skipped already reached by the previous run."
    if ($successes -gt 0) {
        Write-Host 'Open Outlook > Drafts to review and send them.'
    }
}

if ($ReportCsv) {
    $outcomes | Export-Csv -Path $ReportCsv -NoTypeInformation
    Write-Host "Run report written to $ReportCsv"
}

if ($failures -gt 0) { exit 1 }
