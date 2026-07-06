<#
.SYNOPSIS
A point-and-click window for HighRise-Merge.ps1 - no commands to type.

.DESCRIPTION
A small desktop window (built with the Windows Forms toolkit that ships with
every Windows machine - nothing to install) that wraps HighRise-Merge.ps1:
pick your recipients CSV and your template with Browse buttons, then click
Preview, Create Drafts, or Send. The merge itself is still done by the tested
HighRise-Merge.ps1 sitting next to this file, so behavior is identical to the
command line - this is just a friendlier front door.

Launch it by double-clicking HighRise.cmd (which starts this with the right
options). You can also run it directly:
    powershell -NoProfile -ExecutionPolicy Bypass -STA -File HighRise-GUI.ps1
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$mergeScript = Join-Path $scriptDir 'HighRise-Merge.ps1'

function Show-Info    { param([string]$Text) [void][System.Windows.Forms.MessageBox]::Show($Text, 'HighRise', 'OK', 'Information') }
function Show-Warn    { param([string]$Text) [void][System.Windows.Forms.MessageBox]::Show($Text, 'HighRise', 'OK', 'Warning') }

if (-not (Test-Path -LiteralPath $mergeScript)) {
    Show-Warn "Can't find HighRise-Merge.ps1 in this folder:`n$scriptDir`n`nKeep HighRise-GUI.ps1 and HighRise-Merge.ps1 together in the same folder."
    return
}

# ---------------------------------------------------------------------------
# Window
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'HighRise - Mail Merge for Outlook'
$form.Size = New-Object System.Drawing.Size(780, 660)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.MinimumSize = New-Object System.Drawing.Size(700, 560)

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 400, [bool]$Bold = $false)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size = New-Object System.Drawing.Size($W, 20)
    if ($Bold) { $l.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold) }
    $form.Controls.Add($l)
    return $l
}

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 130, [int]$H = 30)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, $H)
    $form.Controls.Add($b)
    return $b
}

# Recipients CSV -----------------------------------------------------------
[void](New-Label -Text 'Step 1 - Your recipients list (a .csv from Excel):' -X 15 -Y 15 -W 500 -Bold $true)
$csvBox = New-Object System.Windows.Forms.TextBox
$csvBox.Location = New-Object System.Drawing.Point(15, 38)
$csvBox.Size = New-Object System.Drawing.Size(600, 24)
$csvBox.ReadOnly = $true
$csvBox.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($csvBox)
$csvBtn = New-Button -Text 'Browse...' -X 625 -Y 37 -W 120

# Template -----------------------------------------------------------------
[void](New-Label -Text 'Step 2 - Your message template (subject + body, with {{Fields}}):' -X 15 -Y 78 -W 560 -Bold $true)
$tplBox = New-Object System.Windows.Forms.TextBox
$tplBox.Location = New-Object System.Drawing.Point(15, 101)
$tplBox.Size = New-Object System.Drawing.Size(475, 24)
$tplBox.ReadOnly = $true
$tplBox.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($tplBox)
$tplBtn = New-Button -Text 'Browse...' -X 500 -Y 100 -W 110
$tplNewBtn = New-Button -Text 'New template...' -X 625 -Y 100 -W 120

# BCC self -----------------------------------------------------------------
[void](New-Label -Text 'Optional - BCC a copy of every message to yourself:' -X 15 -Y 141 -W 500)
$bccBox = New-Object System.Windows.Forms.TextBox
$bccBox.Location = New-Object System.Drawing.Point(15, 164)
$bccBox.Size = New-Object System.Drawing.Size(360, 24)
$form.Controls.Add($bccBox)

# Output -------------------------------------------------------------------
[void](New-Label -Text 'Result:' -X 15 -Y 200 -W 200 -Bold $true)
$outBox = New-Object System.Windows.Forms.TextBox
$outBox.Location = New-Object System.Drawing.Point(15, 223)
$outBox.Size = New-Object System.Drawing.Size(730, 330)
$outBox.Multiline = $true
$outBox.ReadOnly = $true
$outBox.ScrollBars = 'Vertical'
$outBox.WordWrap = $false
$outBox.BackColor = [System.Drawing.Color]::White
$outBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$outBox.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($outBox)

# Action buttons -----------------------------------------------------------
$previewBtn = New-Button -Text '1. Preview (safe)' -X 15  -Y 570 -W 150 -H 34
$draftBtn   = New-Button -Text '2. Create Drafts'  -X 175 -Y 570 -W 150 -H 34
$sendBtn    = New-Button -Text 'Send Now...'       -X 335 -Y 570 -W 120 -H 34
$outlookBtn = New-Button -Text 'Open Outlook'      -X 495 -Y 570 -W 120 -H 34
$closeBtn   = New-Button -Text 'Close'             -X 625 -Y 570 -W 120 -H 34
$previewBtn.Anchor = 'Bottom,Left'; $draftBtn.Anchor = 'Bottom,Left'
$sendBtn.Anchor = 'Bottom,Left'; $outlookBtn.Anchor = 'Bottom,Left'; $closeBtn.Anchor = 'Bottom,Right'
$draftBtn.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

# ---------------------------------------------------------------------------
# Behavior
# ---------------------------------------------------------------------------
$csvBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Spreadsheet lists (*.csv;*.tsv;*.txt)|*.csv;*.tsv;*.txt|All files (*.*)|*.*'
    $dlg.Title = 'Choose your recipients list'
    if ($dlg.ShowDialog() -eq 'OK') { $csvBox.Text = $dlg.FileName }
})

$tplBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Template files (*.txt)|*.txt|All files (*.*)|*.*'
    $dlg.Title = 'Choose your message template'
    if ($dlg.ShowDialog() -eq 'OK') { $tplBox.Text = $dlg.FileName }
})

$tplNewBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'Template files (*.txt)|*.txt'
    $dlg.Title = 'Save a new template'
    $dlg.FileName = 'my-template.txt'
    if ($dlg.ShowDialog() -eq 'OK') {
        $starter = @'
Subject: Quick question about {{Company}}

Hi {{First Name|there}},

I wanted to reach out about {{Company}}.

(Write your message here. Anything in {{double braces}} is replaced with that
person's column from your CSV - {{Name}}, {{Company}}, or any header you have.
Use {{First Name|there}} to fall back to "there" when a row has no first name.)

Best regards,
(paste your email signature here so it appears on every message)
'@
        Set-Content -LiteralPath $dlg.FileName -Value $starter -Encoding UTF8
        $tplBox.Text = $dlg.FileName
        Start-Process notepad.exe -ArgumentList $dlg.FileName
        Show-Info "A starter template opened in Notepad. Edit the subject and body, save it (Ctrl+S), then come back and click Preview."
    }
})

$outlookBtn.Add_Click({
    try { Start-Process outlook.exe } catch { Show-Warn "Couldn't launch Outlook automatically - open it from the Start menu and look in your Drafts folder." }
})

$closeBtn.Add_Click({ $form.Close() })

function Set-Busy {
    param([bool]$Busy)
    $form.Cursor = if ($Busy) { 'WaitCursor' } else { 'Default' }
    foreach ($b in @($previewBtn, $draftBtn, $sendBtn, $csvBtn, $tplBtn, $tplNewBtn)) { $b.Enabled = -not $Busy }
}

function Invoke-Merge {
    param([ValidateSet('preview', 'draft', 'send')][string]$Mode)

    if (-not $csvBox.Text) { Show-Warn 'Pick your recipients list first (Step 1, Browse).'; return }
    if (-not $tplBox.Text) { Show-Warn 'Pick or create a message template first (Step 2).'; return }
    if (-not (Test-Path -LiteralPath $csvBox.Text)) { Show-Warn "That CSV no longer exists:`n$($csvBox.Text)"; return }
    if (-not (Test-Path -LiteralPath $tplBox.Text)) { Show-Warn "That template no longer exists:`n$($tplBox.Text)"; return }

    if ($Mode -eq 'send') {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "This SENDS every message immediately - they go out now, with no chance to review them in Drafts first.`n`nAre you sure?",
            'Confirm send', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { return }
    }

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $mergeScript,
                 '-Csv', $csvBox.Text, '-Template', $tplBox.Text)
    if ($bccBox.Text.Trim()) { $argList += @('-BccSelf', $bccBox.Text.Trim()) }
    switch ($Mode) {
        'preview' { $argList += '-DryRun' }
        'send'    { $argList += @('-Send', '-Force') }
    }

    $outBox.Text = "Working - please wait..." + [Environment]::NewLine
    Set-Busy $true
    $form.Refresh()
    try {
        $result = & powershell.exe @argList 2>&1 | Out-String
    } catch {
        $result = "Something went wrong launching the merge:`r`n$($_.Exception.Message)"
    }
    Set-Busy $false
    $outBox.Text = $result

    if ($Mode -eq 'draft' -and $result -match 'draft\(s\) created') {
        Show-Info "Done. Your drafts are in Outlook's Drafts folder - click 'Open Outlook' to review and send them."
    }
}

$previewBtn.Add_Click({ Invoke-Merge -Mode 'preview' })
$draftBtn.Add_Click({ Invoke-Merge -Mode 'draft' })
$sendBtn.Add_Click({ Invoke-Merge -Mode 'send' })

[void]$form.ShowDialog()
