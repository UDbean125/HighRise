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
is missing data for a placeholder that has no fallback, repeats an earlier
row's address, or names a per-recipient attachment file that doesn't exist.
Unresolved placeholders are removed from the output - a raw {{...}} never
reaches a recipient.

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

.EXAMPLE
.\HighRise-Merge.ps1 -Csv contacts.csv -Template letter.txt -DryRun

.EXAMPLE
.\HighRise-Merge.ps1 -Csv contacts.csv -Template letter.txt
Creates one Outlook draft per sendable recipient; review them in Drafts.

.EXAMPLE
.\HighRise-Merge.ps1 -Csv contacts.csv -Template letter.txt -Send -BccSelf me@example.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Csv,

    [Parameter(Mandatory = $true, Position = 1)]
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
    [string]$ReportCsv
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

# 1. Template.
$templateSpec = Read-TemplateFile $Template

# 2. Recipients.
$csvText = Read-TextFile $Csv
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

    $hasValidEmail = Test-EmailAddress $email
    $isDuplicate = $false
    if ($hasValidEmail) { $isDuplicate = -not $seenEmails.Add($email.ToLower()) }

    # Blocking mirrors MergePreview.blockingReason on the Mac.
    $reason = $null
    if (-not $hasValidEmail) {
        if ($email -eq '') { $reason = 'No email address.' }
        else { $reason = "Invalid email address: $email" }
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

# 6. Confirm before a real immediate send.
if ($Send -and -not $DryRun -and -not $Force) {
    Write-Host "About to SEND $($sendable.Count) message(s) immediately (no draft review)." -ForegroundColor Yellow
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
foreach ($preview in $previews) {
    $label = "$($preview.DisplayName) <$($preview.Email)>"
    if ($null -ne $preview.BlockingReason) {
        Write-Host "[BLOCKED] $($preview.DisplayName) - $($preview.BlockingReason)" -ForegroundColor Yellow
        $outcomes += , [pscustomobject]@{
            Name = $preview.DisplayName; Email = $preview.Email
            Status = 'blocked'; Detail = $preview.BlockingReason
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
            if ($ThrottleSeconds -gt 0) { Start-Sleep -Seconds $ThrottleSeconds }
        } else {
            Write-Host "[DRAFTED] $label" -ForegroundColor Green
            $outcomes += , [pscustomobject]@{
                Name = $preview.DisplayName; Email = $preview.Email; Status = 'drafted'; Detail = ''
            }
        }
    } catch {
        $failures++
        Write-Host "[FAILED] $label - $($_.Exception.Message)" -ForegroundColor Red
        $outcomes += , [pscustomobject]@{
            Name = $preview.DisplayName; Email = $preview.Email
            Status = 'failed'; Detail = $_.Exception.Message
        }
    }
}

# 8. Summary + optional report.
Write-Host ''
if ($DryRun) {
    $verb = 'drafted'
    if ($Send) { $verb = 'sent' }
    Write-Host "Summary: $successes message(s) would be $verb, $($blocked.Count) blocked. No mail was touched."
} elseif ($Send) {
    Write-Host "Summary: $successes sent, $failures failed, $($blocked.Count) blocked."
} else {
    Write-Host "Summary: $successes draft(s) created in Outlook's Drafts folder, $failures failed, $($blocked.Count) blocked."
    if ($successes -gt 0) {
        Write-Host 'Open Outlook > Drafts to review and send them.'
    }
}

if ($ReportCsv) {
    $outcomes | Export-Csv -Path $ReportCsv -NoTypeInformation
    Write-Host "Run report written to $ReportCsv"
}

if ($failures -gt 0) { exit 1 }
