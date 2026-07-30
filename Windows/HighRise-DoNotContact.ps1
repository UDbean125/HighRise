<#
.SYNOPSIS
Manage the do-not-contact list HighRise-Merge.ps1 honors.

.DESCRIPTION
Addresses and whole domains that must never be emailed. Every merge checks
this list and holds back matching rows, without editing anyone's CSV.

The file is the same JSON the Mac and iPhone apps keep
({kind, value, dateAdded, note}), so it can be copied between machines and
behaves identically. Default location:
    %APPDATA%\HighRise\do-not-contact.json

Show the list:
    .\HighRise-DoNotContact.ps1

Block one person, or everyone at a company:
    .\HighRise-DoNotContact.ps1 -Add someone@example.com
    .\HighRise-DoNotContact.ps1 -Add acme.com -Note "Asked to be removed"

Let someone through again:
    .\HighRise-DoNotContact.ps1 -Remove someone@example.com

Check whether an address would be blocked:
    .\HighRise-DoNotContact.ps1 -Test someone@example.com

Use a list stored somewhere else (a shared drive, or one copied off a Mac):
    .\HighRise-DoNotContact.ps1 -Path D:\shared\do-not-contact.json
#>

param(
    [string]$Add,
    [string]$Remove,
    [string]$Test,
    [string]$Note,
    [string]$Path
)

$ErrorActionPreference = 'Stop'

$listPath = if ($Path) { $Path }
            elseif ($env:APPDATA) { Join-Path $env:APPDATA 'HighRise\do-not-contact.json' }
            else { Join-Path $HOME 'HighRise\do-not-contact.json' }

$EmailRegex = [regex]'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'

# Emits entries one at a time rather than returning an array. Returning an
# array from a PowerShell function is a trap: `return ,@(...)` hands back an
# array wrapped in an array, and each save then nests the whole previous list
# inside itself instead of appending to it. Callers collect with @(Read-List),
# which yields an empty array when nothing is emitted.
function Read-List {
    if (-not (Test-Path -LiteralPath $listPath)) { return }
    $raw = Get-Content -LiteralPath $listPath -Raw -Encoding UTF8
    if ($null -eq $raw) { return }
    # A UTF-8 BOM ahead of the '[' makes ConvertFrom-Json fail on 5.1.
    $raw = $raw.TrimStart([char]0xFEFF, [char]0xFFFE).Trim()
    if (-not $raw) { return }
    try { $parsed = ConvertFrom-Json -InputObject $raw }
    catch { throw "The list at $listPath is not valid JSON: $($_.Exception.Message)" }
    # ConvertFrom-Json hands back a bare object when the file holds one entry.
    # Anything without a kind and value is skipped rather than trusted.
    foreach ($item in @($parsed)) {
        if ($null -eq $item) { continue }
        if (-not $item.PSObject.Properties['kind']) { continue }
        if (-not $item.PSObject.Properties['value']) { continue }
        if (-not ([string]$item.value).Trim()) { continue }
        $item
    }
}

function Write-List {
    param([object[]]$Entries)
    $dir = Split-Path -Parent $listPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }
    $items = @($Entries | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) {
        $json = '[]'
    } else {
        $json = ConvertTo-Json -InputObject $items -Depth 4
        # Windows PowerShell 5.1's ConvertTo-Json unwraps a one-element array
        # into a bare object, so re-wrap it to keep the file a JSON array the
        # Mac and iPhone apps can decode.
        if (-not $json.TrimStart().StartsWith('[')) { $json = '[' + $json + ']' }
    }
    Set-Content -LiteralPath $listPath -Value $json -Encoding UTF8
}

# Apple encodes Date as seconds since 2001-01-01 UTC, so a list written here
# decodes cleanly in the Mac and iPhone apps.
function Get-AppleTimestamp {
    $epoch = [datetime]::SpecifyKind([datetime]'2001-01-01', [System.DateTimeKind]::Utc)
    return ([datetime]::UtcNow - $epoch).TotalSeconds
}

function Get-Normalized {
    param([string]$Value)
    $v = ([string]$Value).Trim().ToLowerInvariant()
    if (-not $v) { return $null }
    if ($EmailRegex.IsMatch($v)) {
        return [pscustomobject]@{ kind = 'address'; value = $v }
    }
    $domain = $v.TrimStart('@')
    if ($domain.Contains('.') -and -not $domain.Contains('@') -and
        -not $domain.Contains(' ') -and -not $domain.StartsWith('.') -and
        -not $domain.EndsWith('.')) {
        return [pscustomobject]@{ kind = 'domain'; value = $domain }
    }
    return $null
}

# --- Add ------------------------------------------------------------------
if ($Add) {
    $parsed = Get-Normalized $Add
    if (-not $parsed) {
        throw "'$Add' is not a valid email address or domain. Use name@example.com or example.com."
    }
    $entries = @(Read-List)
    $already = @($entries | Where-Object {
        ([string]$_.kind).ToLowerInvariant() -eq $parsed.kind -and
        ([string]$_.value).ToLowerInvariant() -eq $parsed.value
    })
    if ($already.Count -gt 0) {
        Write-Host "$($parsed.value) is already on the list. Nothing to do."
        return
    }
    $new = [pscustomobject]@{
        kind      = $parsed.kind
        value     = $parsed.value
        dateAdded = Get-AppleTimestamp
    }
    if ($Note) { $new | Add-Member -NotePropertyName note -NotePropertyValue $Note }
    Write-List (@($entries) + @($new))
    $what = if ($parsed.kind -eq 'domain') { "everyone at $($parsed.value)" } else { $parsed.value }
    Write-Host "Blocked $what. Future merges will hold those rows back." -ForegroundColor Green
    return
}

# --- Remove ---------------------------------------------------------------
if ($Remove) {
    $parsed = Get-Normalized $Remove
    if (-not $parsed) { throw "'$Remove' is not a valid email address or domain." }
    $entries = @(Read-List)
    $kept = @($entries | Where-Object {
        -not (([string]$_.kind).ToLowerInvariant() -eq $parsed.kind -and
              ([string]$_.value).ToLowerInvariant() -eq $parsed.value)
    })
    if ($kept.Count -eq $entries.Count) {
        Write-Host "$($parsed.value) was not on the list."
        return
    }
    Write-List $kept
    Write-Host "Unblocked $($parsed.value). They can receive mail again." -ForegroundColor Green
    return
}

# --- Test -----------------------------------------------------------------
if ($Test) {
    $address = ([string]$Test).Trim().ToLowerInvariant()
    $entries = @(Read-List)
    $domain = ''
    $at = $address.IndexOf('@')
    if ($at -ge 0) { $domain = $address.Substring($at + 1) }
    $hit = @($entries | Where-Object {
        $k = ([string]$_.kind).ToLowerInvariant()
        $v = ([string]$_.value).ToLowerInvariant()
        ($k -eq 'address' -and $v -eq $address) -or ($k -eq 'domain' -and $v -eq $domain)
    })
    if ($hit.Count -gt 0) {
        $by = $hit[0]
        $reason = if (([string]$by.kind).ToLowerInvariant() -eq 'domain') { "the domain rule $($by.value)" } else { 'an address rule' }
        Write-Host "BLOCKED - $address is on the list via $reason." -ForegroundColor Yellow
    } else {
        Write-Host "Allowed - $address is not on the list." -ForegroundColor Green
    }
    return
}

# --- List (default) -------------------------------------------------------
$entries = @(Read-List)
if ($entries.Count -eq 0) {
    Write-Host "Nobody is blocked. The list lives at $listPath"
    Write-Host "Add someone with:  .\HighRise-DoNotContact.ps1 -Add name@example.com"
    return
}

Write-Host ""
Write-Host "$($entries.Count) blocked  ($listPath)" -ForegroundColor Cyan
foreach ($e in $entries) {
    $label = if (([string]$e.kind).ToLowerInvariant() -eq 'domain') { "everyone @$($e.value)" } else { [string]$e.value }
    $line = "  {0,-42}" -f $label
    if ($e.PSObject.Properties['note'] -and $e.note) { $line += "  $($e.note)" }
    Write-Host $line
}
Write-Host ""
Write-Host "Every merge holds these back automatically. Remove one with -Remove <value>."
