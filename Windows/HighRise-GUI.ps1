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
$tplPickBtn = New-Button -Text 'Starter templates...' -X 500 -Y 100 -W 140
$tplBtn = New-Button -Text 'Browse...' -X 645 -Y 100 -W 100
$tplNewBtn = New-Button -Text 'New template...' -X 15 -Y 133 -W 130 -H 26
$tplNewBtn.Font = New-Object System.Drawing.Font('Segoe UI', 8)

# BCC self -----------------------------------------------------------------
[void](New-Label -Text 'Optional - BCC a copy of every message to yourself:' -X 15 -Y 166 -W 500)
$bccBox = New-Object System.Windows.Forms.TextBox
$bccBox.Location = New-Object System.Drawing.Point(15, 189)
$bccBox.Size = New-Object System.Drawing.Size(360, 24)
$form.Controls.Add($bccBox)

# Output -------------------------------------------------------------------
[void](New-Label -Text 'Result:' -X 15 -Y 225 -W 200 -Bold $true)
$outBox = New-Object System.Windows.Forms.TextBox
$outBox.Location = New-Object System.Drawing.Point(15, 248)
$outBox.Size = New-Object System.Drawing.Size(730, 305)
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

# Starter-template picker ---------------------------------------------------
# The same catalog the Mac and iOS apps ship (Windows/templates.json, generated
# from the Swift source by Tools/export-templates.py). Search plus the three
# dropdowns - industry, audience, task - mirroring the Mac gallery's filters.
function Show-TemplatePicker {
    $catalogPath = Join-Path $scriptDir 'templates.json'
    if (-not (Test-Path -LiteralPath $catalogPath)) {
        Show-Warn "Can't find templates.json in this folder:`n$scriptDir`n`nKeep the whole Windows folder together."
        return $null
    }
    $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $all = @($catalog.templates)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Start from a template'
    $dlg.Size = New-Object System.Drawing.Size(920, 640)
    $dlg.StartPosition = 'CenterParent'
    $dlg.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $dlg.MinimumSize = New-Object System.Drawing.Size(820, 560)

    $searchLbl = New-Object System.Windows.Forms.Label
    $searchLbl.Text = 'Search'
    $searchLbl.Location = New-Object System.Drawing.Point(15, 18)
    $searchLbl.Size = New-Object System.Drawing.Size(50, 20)
    $dlg.Controls.Add($searchLbl)

    $searchBox = New-Object System.Windows.Forms.TextBox
    $searchBox.Location = New-Object System.Drawing.Point(65, 15)
    $searchBox.Size = New-Object System.Drawing.Size(300, 24)
    $dlg.Controls.Add($searchBox)

    $countLbl = New-Object System.Windows.Forms.Label
    $countLbl.Location = New-Object System.Drawing.Point(375, 18)
    $countLbl.Size = New-Object System.Drawing.Size(150, 20)
    $countLbl.ForeColor = [System.Drawing.Color]::DimGray
    $dlg.Controls.Add($countLbl)

    $clearBtn = New-Object System.Windows.Forms.Button
    $clearBtn.Text = 'Clear filters'
    $clearBtn.Location = New-Object System.Drawing.Point(770, 14)
    $clearBtn.Size = New-Object System.Drawing.Size(110, 26)
    $clearBtn.Anchor = 'Top,Right'
    $dlg.Controls.Add($clearBtn)

    function New-Filter {
        param([string]$Label, [int]$X, [int]$W, [string[]]$Items, [string]$AllText)
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $Label
        $l.Location = New-Object System.Drawing.Point($X, 52)
        $l.Size = New-Object System.Drawing.Size(70, 20)
        $dlg.Controls.Add($l)
        $c = New-Object System.Windows.Forms.ComboBox
        $c.Location = New-Object System.Drawing.Point($X, 74)
        $c.Size = New-Object System.Drawing.Size($W, 24)
        $c.DropDownStyle = 'DropDownList'
        [void]$c.Items.Add($AllText)
        foreach ($i in $Items) { [void]$c.Items.Add($i) }
        $c.SelectedIndex = 0
        $dlg.Controls.Add($c)
        return $c
    }

    $industryBox = New-Filter -Label 'Industry' -X 15  -W 270 -Items @($catalog.industries) -AllText 'All industries'
    $audienceBox = New-Filter -Label 'Audience' -X 300 -W 220 -Items @($catalog.audiences)  -AllText 'All audiences'
    $taskBox     = New-Filter -Label 'Task'     -X 535 -W 170 -Items @($catalog.categories) -AllText 'Any task'

    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Location = New-Object System.Drawing.Point(15, 112)
    $listBox.Size = New-Object System.Drawing.Size(420, 440)
    $listBox.Anchor = 'Top,Bottom,Left'
    $dlg.Controls.Add($listBox)

    $previewBox = New-Object System.Windows.Forms.TextBox
    $previewBox.Location = New-Object System.Drawing.Point(450, 112)
    $previewBox.Size = New-Object System.Drawing.Size(430, 440)
    $previewBox.Multiline = $true
    $previewBox.ReadOnly = $true
    $previewBox.ScrollBars = 'Vertical'
    $previewBox.BackColor = [System.Drawing.Color]::White
    $previewBox.Font = New-Object System.Drawing.Font('Consolas', 9)
    $previewBox.Anchor = 'Top,Bottom,Left,Right'
    $dlg.Controls.Add($previewBox)

    $useBtn = New-Object System.Windows.Forms.Button
    $useBtn.Text = 'Use this template'
    $useBtn.Location = New-Object System.Drawing.Point(15, 565)
    $useBtn.Size = New-Object System.Drawing.Size(170, 32)
    $useBtn.Anchor = 'Bottom,Left'
    $useBtn.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $dlg.Controls.Add($useBtn)

    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = 'Cancel'
    $cancelBtn.Location = New-Object System.Drawing.Point(770, 565)
    $cancelBtn.Size = New-Object System.Drawing.Size(110, 32)
    $cancelBtn.Anchor = 'Bottom,Right'
    $dlg.Controls.Add($cancelBtn)

    # Shown templates, parallel to $listBox items.
    $script:shown = @()

    function Test-Contains {
        param([string[]]$Values, [string]$Needle)
        foreach ($v in $Values) {
            if ($v -and $v.ToLowerInvariant().Contains($Needle)) { return $true }
        }
        return $false
    }

    function Update-List {
        $query = $searchBox.Text.Trim().ToLowerInvariant()
        $ind = if ($industryBox.SelectedIndex -gt 0) { [string]$industryBox.SelectedItem } else { '' }
        $aud = if ($audienceBox.SelectedIndex -gt 0) { [string]$audienceBox.SelectedItem } else { '' }
        $task = if ($taskBox.SelectedIndex -gt 0) { [string]$taskBox.SelectedItem } else { '' }

        $keep = @()
        foreach ($t in $all) {
            $tInd = @($t.industries)
            $tAud = @($t.audiences)
            # A neutral template fits every industry/audience, same as the apps.
            if ($ind -and $tInd.Count -gt 0 -and ($tInd -notcontains $ind)) { continue }
            if ($aud -and $tAud.Count -gt 0 -and ($tAud -notcontains $aud)) { continue }
            if ($task -and $t.category -ne $task) { continue }
            if ($query) {
                $hay = @($t.name, $t.blurb, $t.category, $t.subject, $t.body) + $tInd + $tAud
                $ok = $true
                foreach ($word in ($query -split '\s+' | Where-Object { $_ })) {
                    if (-not (Test-Contains -Values $hay -Needle $word)) { $ok = $false; break }
                }
                if (-not $ok) { continue }
            }
            $keep += $t
        }
        # Industry-specific ones first when an industry is chosen.
        if ($ind) {
            $keep = @($keep | Where-Object { @($_.industries).Count -gt 0 }) +
                    @($keep | Where-Object { @($_.industries).Count -eq 0 })
        }

        $listBox.BeginUpdate()
        $listBox.Items.Clear()
        foreach ($t in $keep) {
            $mark = if (@($t.industries).Count -gt 0) { '* ' } else { '  ' }
            [void]$listBox.Items.Add(("{0}{1}  -  {2}" -f $mark, $t.name, $t.category))
        }
        $listBox.EndUpdate()
        $script:shown = $keep
        $countLbl.Text = ("{0} of {1} shown" -f $keep.Count, $all.Count)
        if ($listBox.Items.Count -gt 0) { $listBox.SelectedIndex = 0 } else { $previewBox.Text = '' }
    }

    $listBox.Add_SelectedIndexChanged({
        $i = $listBox.SelectedIndex
        if ($i -lt 0 -or $i -ge $script:shown.Count) { return }
        $t = $script:shown[$i]
        $lines = @()
        $lines += $t.name
        $lines += $t.blurb
        $lines += ''
        if (@($t.industries).Count) { $lines += ('Industry: ' + (@($t.industries) -join ', ')) }
        if (@($t.audiences).Count)  { $lines += ('Audience: ' + (@($t.audiences) -join ', ')) }
        $lines += ('Task:     ' + $t.category)
        $lines += ''
        $lines += ('Subject: ' + $t.subject)
        $lines += ''
        $lines += $t.body
        $previewBox.Text = ($lines -join [Environment]::NewLine)
    })

    $searchBox.Add_TextChanged({ Update-List })
    $industryBox.Add_SelectedIndexChanged({ Update-List })
    $audienceBox.Add_SelectedIndexChanged({ Update-List })
    $taskBox.Add_SelectedIndexChanged({ Update-List })
    $clearBtn.Add_Click({
        $searchBox.Text = ''
        $industryBox.SelectedIndex = 0
        $audienceBox.SelectedIndex = 0
        $taskBox.SelectedIndex = 0
    })

    $script:picked = $null
    $useBtn.Add_Click({
        $i = $listBox.SelectedIndex
        if ($i -lt 0 -or $i -ge $script:shown.Count) {
            [void][System.Windows.Forms.MessageBox]::Show('Pick a template from the list first.', 'HighRise', 'OK', 'Information')
            return
        }
        $script:picked = $script:shown[$i]
        $dlg.Close()
    })
    $cancelBtn.Add_Click({ $script:picked = $null; $dlg.Close() })
    $listBox.Add_DoubleClick({ $useBtn.PerformClick() })

    Update-List
    [void]$dlg.ShowDialog()
    return $script:picked
}

$tplPickBtn.Add_Click({
    $chosen = Show-TemplatePicker
    if (-not $chosen) { return }
    $save = New-Object System.Windows.Forms.SaveFileDialog
    $save.Filter = 'Template files (*.txt)|*.txt'
    $save.Title = 'Save this template'
    $save.FileName = ($chosen.id + '.txt')
    if ($save.ShowDialog() -ne 'OK') { return }
    $text = 'Subject: ' + $chosen.subject + [Environment]::NewLine + [Environment]::NewLine + $chosen.body + [Environment]::NewLine
    Set-Content -LiteralPath $save.FileName -Value $text -Encoding UTF8
    $tplBox.Text = $save.FileName
    Show-Info ("Loaded '" + $chosen.name + "'. Edit it any time in Notepad, or click Preview to see it merged against your list.")
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
    foreach ($b in @($previewBtn, $draftBtn, $sendBtn, $csvBtn, $tplBtn, $tplNewBtn, $tplPickBtn)) { $b.Enabled = -not $Busy }
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
