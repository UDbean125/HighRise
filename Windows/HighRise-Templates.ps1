<#
.SYNOPSIS
Browse HighRise's built-in starter templates and save one to a .txt file.

.DESCRIPTION
The same catalog the Mac and iOS apps ship, exported to templates.json next to
this script. Filter it by industry, by who you're emailing, and by task group,
or search it by text - then write the one you want to a template file that
HighRise-Merge.ps1 can use.

Run it with no arguments to list everything:
    .\HighRise-Templates.ps1

Narrow it down:
    .\HighRise-Templates.ps1 -Industry Construction -Audience Candidates
    .\HighRise-Templates.ps1 -Search "invoice"
    .\HighRise-Templates.ps1 -Category "Get paid"

Then save one to use with the merge tool:
    .\HighRise-Templates.ps1 -Id construction-crew-hiring -Save .\hiring.txt

Industry, Audience and Category match on any part of the name, so -Industry
const finds "Construction" and -Audience cand finds "Job Candidates".
#>

param(
    [string]$Search,
    [string]$Industry,
    [string]$Audience,
    [string]$Category,
    [string]$Id,
    [string]$Save,
    [switch]$Full
)

$ErrorActionPreference = 'Stop'

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$catalogPath = Join-Path $scriptDir 'templates.json'

if (-not (Test-Path -LiteralPath $catalogPath)) {
    throw "Can't find templates.json next to this script ($scriptDir). Keep the Windows folder together."
}

# -AsHashtable isn't available on Windows PowerShell 5.1, so this stays with
# the default PSCustomObject shape.
$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$templates = @($catalog.templates)

function Test-AnyMatch {
    param([string[]]$Values, [string]$Needle)
    if (-not $Needle) { return $true }
    foreach ($v in $Values) {
        if ($v -and $v.ToLowerInvariant().Contains($Needle.ToLowerInvariant())) { return $true }
    }
    return $false
}

# An industry- or audience-neutral template fits every filter, exactly like the
# Mac gallery: choosing a sector narrows and re-ranks, it never empties.
function Test-Fits {
    param($Template, [string]$Needle, [string]$Property)
    $tags = @($Template.$Property)
    if (-not $Needle) { return $true }
    if ($tags.Count -eq 0) { return $true }
    return (Test-AnyMatch -Values $tags -Needle $Needle)
}

$found = @()
foreach ($t in $templates) {
    if ($Id -and $t.id -ne $Id) { continue }
    if (-not (Test-Fits -Template $t -Needle $Industry -Property 'industries')) { continue }
    if (-not (Test-Fits -Template $t -Needle $Audience -Property 'audiences')) { continue }
    if ($Category -and -not (Test-AnyMatch -Values @($t.category) -Needle $Category)) { continue }
    if ($Search) {
        $hay = @($t.name, $t.blurb, $t.category, $t.subject, $t.body) + @($t.industries) + @($t.audiences)
        $ok = $true
        foreach ($word in ($Search -split '\s+' | Where-Object { $_ })) {
            if (-not (Test-AnyMatch -Values $hay -Needle $word)) { $ok = $false; break }
        }
        if (-not $ok) { continue }
    }
    $found += $t
}

# Templates written for the chosen industry lead, same ordering as the apps.
if ($Industry) {
    $tailored = @($found | Where-Object { @($_.industries).Count -gt 0 })
    $general  = @($found | Where-Object { @($_.industries).Count -eq 0 })
    $found = @($tailored) + @($general)
}

if ($Save) {
    if ($found.Count -eq 0) { throw "Nothing matched, so there's nothing to save." }
    if ($found.Count -gt 1 -and -not $Id) {
        Write-Host "$($found.Count) templates matched. Narrow it down, or pass -Id with one of these:" -ForegroundColor Yellow
        foreach ($t in $found) { Write-Host ("  {0,-38} {1}" -f $t.id, $t.name) }
        return
    }
    $chosen = $found[0]
    $text = "Subject: $($chosen.subject)" + [Environment]::NewLine + [Environment]::NewLine + $chosen.body + [Environment]::NewLine
    Set-Content -LiteralPath $Save -Value $text -Encoding UTF8
    Write-Host "Saved '$($chosen.name)' to $Save" -ForegroundColor Green
    Write-Host "Use it with:" -ForegroundColor Gray
    Write-Host "  .\HighRise-Merge.ps1 -Csv your-list.csv -Template $Save -DryRun" -ForegroundColor Gray
    return
}

if ($found.Count -eq 0) {
    Write-Host "No templates matched. Try fewer filters, or run with no arguments to see all $($templates.Count)."
    return
}

if ($Full) {
    foreach ($t in $found) {
        Write-Host ("=" * 72)
        Write-Host $t.name -ForegroundColor Cyan
        Write-Host ("  id:       {0}" -f $t.id)
        Write-Host ("  task:     {0}" -f $t.category)
        if (@($t.industries).Count) { Write-Host ("  industry: {0}" -f (@($t.industries) -join ', ')) }
        if (@($t.audiences).Count)  { Write-Host ("  audience: {0}" -f (@($t.audiences) -join ', ')) }
        Write-Host ""
        Write-Host ("Subject: {0}" -f $t.subject)
        Write-Host ""
        Write-Host $t.body
        Write-Host ""
    }
    Write-Host ("{0} of {1} templates." -f $found.Count, $templates.Count)
    return
}

$grouped = $found | Group-Object -Property category
foreach ($cat in $catalog.categories) {
    $group = $grouped | Where-Object { $_.Name -eq $cat }
    if (-not $group) { continue }
    Write-Host ""
    Write-Host $cat -ForegroundColor Cyan
    foreach ($t in $group.Group) {
        $tag = if (@($t.industries).Count) { " [" + (@($t.industries) -join ', ') + "]" } else { "" }
        Write-Host ("  {0,-38} {1}{2}" -f $t.id, $t.name, $tag)
        Write-Host ("  {0,-38} {1}" -f "", $t.blurb) -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host ("{0} of {1} templates. Add -Full to read them, or -Id <id> -Save <file.txt> to use one." -f $found.Count, $templates.Count)
