#requires -Version 5.1
<#
    GameSaveVault-GUI.ps1
    WinForms front-end for GameSaveVault.
#>

param(
    [switch]$SmokeTest
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$ErrorActionPreference = 'Stop'
$script:Root = $PSScriptRoot

Import-Module (Join-Path $script:Root 'modules\GSV.Core.psm1') -Force
Import-Module (Join-Path $script:Root 'modules\GSV.Vault.psm1') -Force

$script:Settings = Get-GSVSettings
if (-not (Test-Path -LiteralPath (Join-Path $script:Root 'config\settings.json'))) {
    try { Save-GSVSettings -Settings $script:Settings } catch { }
}
$script:Vault = $script:Settings.BackupRoot
$script:Games = @()
$script:Global = @()
$script:Emulators = @()

#region ---------------------------------------------------------------- tiny dialogs

function Show-Info {
    param([string]$Text, [string]$Title = 'GameSaveVault')
    [System.Windows.Forms.MessageBox]::Show($Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Show-Warn {
    param([string]$Text, [string]$Title = 'GameSaveVault')
    [System.Windows.Forms.MessageBox]::Show($Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
}

function Show-Error {
    param([string]$Text, [string]$Title = 'GameSaveVault')
    [System.Windows.Forms.MessageBox]::Show($Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}

function Read-GuiText {
    param([string]$Title, [string]$Prompt, [string]$Default = '')
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $Title
    $dlg.Size = New-Object System.Drawing.Size(460, 170)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Prompt
    $lbl.Location = New-Object System.Drawing.Point(14, 14)
    $lbl.Size = New-Object System.Drawing.Size(420, 40)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(14, 56)
    $tb.Size = New-Object System.Drawing.Size(420, 24)
    $tb.Text = $Default

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.DialogResult = 'OK'
    $ok.Location = New-Object System.Drawing.Point(268, 94)
    $ok.Size = New-Object System.Drawing.Size(78, 28)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = 'Cancel'
    $cancel.Location = New-Object System.Drawing.Point(356, 94)
    $cancel.Size = New-Object System.Drawing.Size(78, 28)

    $dlg.Controls.AddRange(@($lbl, $tb, $ok, $cancel))
    $dlg.AcceptButton = $ok
    $dlg.CancelButton = $cancel

    if ($dlg.ShowDialog() -eq 'OK') { return $tb.Text.Trim() }
    return $null
}

function Select-Folder {
    param([string]$Description = 'Select folder', [string]$InitialPath = '')
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $Description
    $dlg.ShowNewFolderButton = $true
    if ($InitialPath -and (Test-Path -LiteralPath $InitialPath)) { $dlg.SelectedPath = $InitialPath }
    if ($dlg.ShowDialog() -eq 'OK') { return $dlg.SelectedPath }
    return $null
}

function Show-VaultLocationDialog {
    $current = [string]$script:Vault

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Where should backups be stored?'
    $dlg.Size = New-Object System.Drawing.Size(720, 380)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Backups (snapshots) are stored in this folder. Pick a drive that survives a Windows reinstall - D:, E:, USB or another disk, NOT C:."
    $lbl.Location = New-Object System.Drawing.Point(14, 12)
    $lbl.Size = New-Object System.Drawing.Size(690, 30)

    $currentLabel = New-Object System.Windows.Forms.Label
    $currentLabel.Text = 'Current:  ' + $current
    $currentLabel.Location = New-Object System.Drawing.Point(14, 46)
    $currentLabel.Size = New-Object System.Drawing.Size(690, 20)
    $currentLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

    $pathBox = New-Object System.Windows.Forms.TextBox
    $pathBox.Location = New-Object System.Drawing.Point(14, 74)
    $pathBox.Size = New-Object System.Drawing.Size(500, 24)
    $pathBox.Text = $current

    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = 'Browse...'
    $btnBrowse.Location = New-Object System.Drawing.Point(522, 72)
    $btnBrowse.Size = New-Object System.Drawing.Size(96, 28)

    $btnDrives = New-Object System.Windows.Forms.Button
    $btnDrives.Text = 'Use drive'
    $btnDrives.Location = New-Object System.Drawing.Point(624, 72)
    $btnDrives.Size = New-Object System.Drawing.Size(80, 28)

    $driveList = New-Object System.Windows.Forms.ListBox
    $driveList.Location = New-Object System.Drawing.Point(14, 108)
    $driveList.Size = New-Object System.Drawing.Size(690, 120)
    $driveList.Font = New-Object System.Drawing.Font('Consolas', 9)

    foreach ($d in @(Get-GSVFixedDriveRoots)) {
        $extra = ''
        try {
            $di = Get-PSDrive -Name $d.Substring(0, 1) -ErrorAction SilentlyContinue
            if ($di) {
                $free = if ($di.Free) { [math]::Round($di.Free / 1GB, 1) } else { 0 }
                $extra = "  ({0} GB free)" -f $free
            }
        } catch { }

        $leaf = Split-Path -Leaf $d.TrimEnd('\')
        $warn = if ($d.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)) { '  <-- WARNING: system drive, erased by a clean install' } else { '' }
        $text = '{0}  =  {1}{2}{3}' -f $leaf, $d, $extra, $warn
        [void]$driveList.Items.Add($text)
        $driveList.Items[$driveList.Items.Count - 1] = [pscustomobject]@{ FullPath = (Join-Path $d 'GameSaveVault'); Display = $text }
    }
    $driveList.SelectedIndex = 0

    $btnBrowse.Add_Click({
        $picked = Select-Folder 'Choose the folder where backups are stored' $pathBox.Text
        if ($picked) { $pathBox.Text = $picked }
    })

    $btnDrives.Add_Click({
        if ($driveList.SelectedIndex -ge 0) {
            $pathBox.Text = $driveList.SelectedItem.FullPath
        }
    })

    $driveList.Add_DoubleClick({
        if ($driveList.SelectedIndex -ge 0) { $pathBox.Text = $driveList.SelectedItem.FullPath }
    })

    $chkMove = New-Object System.Windows.Forms.CheckBox
    $chkMove.Text = 'Move existing snapshots to the new location too'
    $chkMove.AutoSize = $true
    $chkMove.Location = New-Object System.Drawing.Point(14, 236)
    $chkMove.Checked = ($current -and (Test-Path -LiteralPath $current))

    $btnMake = New-Object System.Windows.Forms.Button
    $btnMake.Text = 'Make default'
    $btnMake.DialogResult = 'OK'
    $btnMake.Location = New-Object System.Drawing.Point(430, 280)
    $btnMake.Size = New-Object System.Drawing.Size(110, 34)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.DialogResult = 'Cancel'
    $btnCancel.Location = New-Object System.Drawing.Point(546, 280)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 34)

    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'The choice is saved in config\settings.json, so the GUI and CLI use it from now on.'
    $note.Location = New-Object System.Drawing.Point(14, 286)
    $note.Size = New-Object System.Drawing.Size(400, 20)
    $note.ForeColor = [System.Drawing.Color]::DimGray

    $dlg.Controls.AddRange(@($lbl, $currentLabel, $pathBox, $btnBrowse, $btnDrives, $driveList, $chkMove, $btnMake, $btnCancel, $note))
    $dlg.AcceptButton = $btnMake
    $dlg.CancelButton = $btnCancel

    if ($dlg.ShowDialog() -ne 'OK') { $dlg.Dispose(); return }

    $newPath = $pathBox.Text.Trim()
    $dlg.Dispose()
    if (-not $newPath) { Show-Warn 'Please pick a backup folder first.'; return }
    if ($newPath -ieq $current) { Show-Info ('Backups are already stored in:' + "`n`n" + $current); return }

    $oldPath = $current
    $move = $chkMove.Checked

    try {
        if (-not (Test-Path -LiteralPath $newPath)) {
            New-Item -ItemType Directory -Path $newPath -Force | Out-Null
        }

        $moved = 0
        if ($move -and (Test-Path -LiteralPath $oldPath)) {
            foreach ($item in @(Get-ChildItem -LiteralPath $oldPath -Force -ErrorAction SilentlyContinue)) {
                $dest = Join-Path $newPath $item.Name
                if (-not (Test-Path -LiteralPath $dest)) {
                    try { Move-Item -LiteralPath $item.FullName -Destination $dest -Force -ErrorAction Stop; $moved++ } catch { }
                }
            }
        }

        $script:Vault = $newPath
        $script:Settings.BackupRoot = $newPath
        $script:Settings | Add-Member -NotePropertyName BackupRoot -NotePropertyValue $newPath -Force
        Save-GSVSettings -Settings $script:Settings
        Update-VaultLabel

        $msg = "Backups will now be stored in:`n`n$newPath`n`nThe choice is saved, so the GUI and CLI use it from now on."
        if ($moved -gt 0) { $msg += "`n`nMoved $moved item(s) from the old location." }
        elseif ($move -and (Test-Path -LiteralPath $oldPath)) { $msg += "`n`nNothing was moved (old location empty or items already there)." }

        Show-Info $msg 'Backup location changed'
        $statusLabel.Text = 'Backup location: ' + $newPath
    } catch {
        Show-Error "Could not change the backup location: $($_.Exception.Message)"
    }
}

function Select-SnapshotDialog {
    $snaps = @(Get-GSVSnapshots -BackupRoot $script:Vault)
    if ($snaps.Count -eq 0) {
        Show-Warn 'No snapshots yet. Run a backup first.'
        return $null
    }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Choose a snapshot to restore'
    $dlg.Size = New-Object System.Drawing.Size(720, 430)
    $dlg.StartPosition = 'CenterParent'
    $dlg.MinimizeBox = $false

    $lb = New-Object System.Windows.Forms.ListBox
    $lb.Location = New-Object System.Drawing.Point(12, 12)
    $lb.Size = New-Object System.Drawing.Size(680, 330)
    $lb.Font = New-Object System.Drawing.Font('Consolas', 9)

    foreach ($s in $snaps) {
        $created = ([datetime]$s.CreatedUtc).ToLocalTime().ToString('yyyy-MM-dd HH:mm')
        $lb.Items.Add(('{0}  |  {1,-18}  |  {2,4} files  |  {3,8}' -f $created, $s.Label, $s.TotalFiles, (Format-GSVSize $s.TotalBytes))) | Out-Null
    }
    $lb.SelectedIndex = 0

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Restore this'
    $ok.DialogResult = 'OK'
    $ok.Location = New-Object System.Drawing.Point(512, 352)
    $ok.Size = New-Object System.Drawing.Size(96, 30)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = 'Cancel'
    $cancel.Location = New-Object System.Drawing.Point(614, 352)
    $cancel.Size = New-Object System.Drawing.Size(78, 30)

    $dlg.Controls.AddRange(@($lb, $ok, $cancel))
    $dlg.AcceptButton = $ok
    $dlg.CancelButton = $cancel

    if ($dlg.ShowDialog() -eq 'OK' -and $lb.SelectedIndex -ge 0) {
        return $snaps[$lb.SelectedIndex]
    }
    return $null
}

function Show-DeepScanDialog {
    $drive = Read-GuiText 'Deep scan' 'Drive to search (C:, D: ...) or type ALL for every fixed drive:' $env:SystemDrive
    if (-not $drive) { return }

    $roots = New-Object System.Collections.Generic.List[string]
    if ($drive -ieq 'all' -or $drive -ieq '*') {
        foreach ($r in @(Get-GSVFixedDriveRoots)) { $roots.Add($r) }
    } else {
        $p = [string]$drive
        if ($p -match '^[A-Za-z]$') { $p = $p + ':\' }
        elseif ($p -match '^[A-Za-z]:$') { $p = $p + '\' }
        if (-not $p.EndsWith('\')) { $p += '\' }
        $roots.Add($p)
    }

    if ($roots.Count -eq 0) { Show-Warn 'No drive to scan.'; return }

    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $statusLabel.Text = ('Deep scanning {0}...' -f ($roots -join ', '))
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    $progress = {
        param($folders, $path)
        $statusLabel.Text = ('Deep scan: {0:N0} folders... {1}' -f $folders, $path)
        [System.Windows.Forms.Application]::DoEvents()
    }

    try {
        $locs = @(Get-GSVDeepScanLocations -Roots $roots.ToArray() -MaxDepth 12 -MaxResults 1000 -Progress $progress)
    } catch {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        Show-Error "Deep scan failed: $($_.Exception.Message)"
        $statusLabel.Text = 'Deep scan failed.'
        return
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }

    $statusLabel.Text = ('Deep scan found {0} save location(s).' -f $locs.Count)
    if ($locs.Count -eq 0) {
        Show-Warn 'No save folders found. Try another drive or run as administrator.'
        return
    }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = ('Deep scan results  -  {0} save location(s)' -f $locs.Count)
    $dlg.Size = New-Object System.Drawing.Size(1120, 620)
    $dlg.StartPosition = 'CenterParent'
    $dlg.MinimizeBox = $false

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Dock = 'Fill'
    $lv.View = 'Details'
    $lv.CheckBoxes = $true
    $lv.FullRowSelect = $true
    $lv.GridLines = $false
    $lv.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    [void]$lv.Columns.Add('Game', 260)
    [void]$lv.Columns.Add('AppId', 80)
    [void]$lv.Columns.Add('Files', 70, [System.Windows.Forms.HorizontalAlignment]::Right)
    [void]$lv.Columns.Add('Size', 90, [System.Windows.Forms.HorizontalAlignment]::Right)
    [void]$lv.Columns.Add('Save folder', 620)

    foreach ($l in ($locs | Sort-Object GameName, ResolvedPath)) {
        $item = New-Object System.Windows.Forms.ListViewItem([string]$l.GameName)
        [void]$item.SubItems.Add([string]$l.AppId)
        [void]$item.SubItems.Add($(if ($null -ne $l.FileCount) { [string]$l.FileCount } else { '' }))
        [void]$item.SubItems.Add($(if ($null -ne $l.Bytes) { Format-GSVSize $l.Bytes } else { '' }))
        [void]$item.SubItems.Add([string]$l.ResolvedPath)
        $item.Tag = $l
        $item.Checked = $true
        [void]$lv.Items.Add($item)
    }

    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.Dock = 'Bottom'
    $panel.Height = 46
    $panel.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 6)
    $panel.WrapContents = $false

    $btnAll = New-TopButton 'Select all' 90
    $btnNone = New-TopButton 'Select none' 100
    $btnBackup = New-TopButton 'Backup checked' 120 'Back up every checked save folder'
    $btnClose = New-TopButton 'Close' 80

    $btnAll.Add_Click({ foreach ($i in $lv.Items) { $i.Checked = $true } })
    $btnNone.Add_Click({ foreach ($i in $lv.Items) { $i.Checked = $false } })
    $btnClose.Add_Click({ $dlg.Close() })
    $btnBackup.Add_Click({
        $chosen = New-Object System.Collections.Generic.List[object]
        foreach ($i in $lv.CheckedItems) { $chosen.Add($i.Tag) }
        if ($chosen.Count -eq 0) { Show-Warn 'Nothing checked.'; return }
        $dlg.Close()
        Invoke-GuiBackup -Locations $chosen.ToArray() -Label 'gui-deep-scan'
    })

    $panel.Controls.AddRange(@($btnAll, $btnNone, $btnBackup, $btnClose))
    $dlg.Controls.Add($lv)
    $dlg.Controls.Add($panel)
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

function Show-MigrateDialog {
    $defs = @(Get-GSVEmulatorDefinitions)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Migrate console emulator saves'
    $dlg.Size = New-Object System.Drawing.Size(880, 560)
    $dlg.StartPosition = 'CenterParent'
    $dlg.MinimizeBox = $false

    $lblFrom = New-Object System.Windows.Forms.Label
    $lblFrom.Text = 'From'
    $lblFrom.Location = New-Object System.Drawing.Point(14, 14)
    $lblFrom.Size = New-Object System.Drawing.Size(40, 20)

    $cbFrom = New-Object System.Windows.Forms.ComboBox
    $cbFrom.DropDownStyle = 'DropDownList'
    $cbFrom.Location = New-Object System.Drawing.Point(56, 10)
    $cbFrom.Size = New-Object System.Drawing.Size(280, 24)

    $lblTo = New-Object System.Windows.Forms.Label
    $lblTo.Text = 'To'
    $lblTo.Location = New-Object System.Drawing.Point(350, 14)
    $lblTo.Size = New-Object System.Drawing.Size(30, 20)

    $cbTo = New-Object System.Windows.Forms.ComboBox
    $cbTo.DropDownStyle = 'DropDownList'
    $cbTo.Location = new-Object System.Drawing.Point(382, 10)
    $cbTo.Size = New-Object System.Drawing.Size(280, 24)

    foreach ($def in $defs) {
        $label = "{0} ({1})" -f $def.Name, $def.Console
        [void]$cbFrom.Items.Add($label)
        [void]$cbTo.Items.Add($label)
    }
    $cbFrom.SelectedIndex = 0
    $cbTo.SelectedIndex = 1

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Dock = 'Fill'
    $lv.View = 'Details'
    $lv.CheckBoxes = $true
    $lv.FullRowSelect = $true
    $lv.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    [void]$lv.Columns.Add('Title ID', 220)
    [void]$lv.Columns.Add('Profile', 150)
    [void]$lv.Columns.Add('Save folder', 480)

    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.Dock = 'Bottom'
    $panel.Height = 48
    $panel.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 6)
    $panel.WrapContents = $false

    $btnRefresh = New-TopButton 'Refresh list' 100 'Re-scan the source emulator for saves'
    $btnGo = New-TopButton 'Migrate checked' 130 'Copy the checked saves into the other emulator'
    $btnClose = New-TopButton 'Close' 80

    $script:MigrateEntries = @()

    $btnRefresh.Add_Click({
        $srcDef = $defs[$cbFrom.SelectedIndex]
        $lv.Items.Clear()
        $script:MigrateEntries = @(Get-GSVEmulatorSaveIndex -EmulatorIds @($srcDef.Id) -IncludePortable)
        foreach ($e in ($script:MigrateEntries | Sort-Object TitleId)) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$e.TitleId)
            [void]$item.SubItems.Add([string]$e.ProfileId)
            [void]$item.SubItems.Add([string]$e.Path)
            $item.Tag = $e
            $item.Checked = $true
            [void]$lv.Items.Add($item)
        }
        if ($script:MigrateEntries.Count -eq 0) {
            Show-Warn ("No saves found for {0}." -f $srcDef.Name)
        }
    })

    $btnGo.Add_Click({
        $srcDef = $defs[$cbFrom.SelectedIndex]
        $dstDef = $defs[$cbTo.SelectedIndex]
        if ($srcDef.Id -eq $dstDef.Id) { Show-Warn 'Source and destination are the same emulator.'; return }

        $chosen = New-Object System.Collections.Generic.List[object]
        foreach ($i in $lv.CheckedItems) { $chosen.Add($i.Tag) }
        if ($chosen.Count -eq 0) { Show-Warn 'Nothing checked.'; return }

        try {
            $r = Copy-GSVEmulatorSaves -Entries $chosen.ToArray() -DestinationEmulatorId $dstDef.Id -BackupRoot $script:Vault
            $msg = "Migration complete.`n`nFrom: $($srcDef.Name)`nTo: $($dstDef.Name)`nCopied: $($r.Migrated)`nSkipped: $($r.Skipped)`nFailed: $($r.Failed)"
            if (@($r.Messages).Count -gt 0) { $msg += "`n`n" + (($r.Messages | Select-Object -First 5) -join "`n") }
            Show-Info $msg 'Migration complete'
            $statusLabel.Text = ("Migrated {0} save(s) to {1}" -f $r.Migrated, $dstDef.Name)
            Load-Games
        } catch {
            Show-Error "Migration failed: $($_.Exception.Message)"
        }
    })

    $btnClose.Add_Click({ $dlg.Close() })

    $panel.Controls.AddRange(@($btnRefresh, $btnGo, $btnClose))
    $dlg.Controls.Add($lv)
    $dlg.Controls.Add($panel)
    $dlg.Controls.Add($lblFrom)
    $dlg.Controls.Add($cbFrom)
    $dlg.Controls.Add($lblTo)
    $dlg.Controls.Add($cbTo)

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

#endregion

#region ---------------------------------------------------------------- form

$form = New-Object System.Windows.Forms.Form
$form.Text = 'GameSaveVault  -  game save backup & restore'
$form.Size = New-Object System.Drawing.Size(1120, 700)
$form.MinimumSize = New-Object System.Drawing.Size(900, 520)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$top = New-Object System.Windows.Forms.FlowLayoutPanel
$top.Dock = 'Top'
$top.Height = 46
$top.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 4)
$top.WrapContents = $false
$top.AutoSize = $false

function New-TopButton {
    param([string]$Text, [int]$Width = 120, [string]$Tip = '')
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Width = $Width
    $b.Height = 30
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
    $b.FlatStyle = 'System'
    if ($Tip) {
        $tt = New-Object System.Windows.Forms.ToolTip
        $tt.SetToolTip($b, $Tip)
    }
    return $b
}

$btnScan     = New-TopButton 'Rescan' 90 'Detect installed games and save folders'
$btnBackup   = New-TopButton 'Backup selected' 130 'Back up the checked games'
$btnBackupAll = New-TopButton 'Backup all' 100 'Back up every detected game'
$btnRestore  = New-TopButton 'Restore...' 100 'Restore a snapshot from the vault'
$btnOld      = New-TopButton 'Windows.old...' 120 'Recover saves from C:\Windows.old'
$btnDeep     = New-TopButton 'Deep scan...' 110 'Search a whole drive for CPY / GSE / scene / Steam / UWP saves'
$btnMigrate  = New-TopButton 'Migrate...' 90 'Copy console-emulator saves between emulators (Eden / Ryujinx / Eglantine / Kyty)'
$btnAdd      = New-TopButton 'Add game...' 100 'Register a custom save folder'
$btnVault    = New-TopButton 'Open vault' 100 'Open the backup folder'
$btnVaultLoc = New-TopButton 'Backup location...' 150 'Choose where backups are stored (default vault folder)'
$btnDoctor   = New-TopButton 'Doctor' 80 'Check vault health'

$top.Controls.AddRange(@($btnScan, $btnBackup, $btnBackupAll, $btnRestore, $btnOld, $btnDeep, $btnMigrate, $btnAdd, $btnVault, $btnVaultLoc, $btnDoctor))

$list = New-Object System.Windows.Forms.ListView
$list.Dock = 'Fill'
$list.View = 'Details'
$list.CheckBoxes = $true
$list.FullRowSelect = $true
$list.GridLines = $false
$list.HideSelection = $false
$list.MultiSelect = $true
$list.Font = New-Object System.Drawing.Font('Segoe UI', 9)

[void]$list.Columns.Add('Game', 330)
[void]$list.Columns.Add('Source', 70)
[void]$list.Columns.Add('Saves', 55, [System.Windows.Forms.HorizontalAlignment]::Center)
[void]$list.Columns.Add('Size', 85, [System.Windows.Forms.HorizontalAlignment]::Right)
[void]$list.Columns.Add('Save folders (first 3)', 520)

$status = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Ready'
$statusLabel.Spring = $true
$statusLabel.TextAlign = 'MiddleLeft'
$vaultLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$vaultLabel.Text = 'Vault: ' + $script:Vault
$vaultLabel.ForeColor = [System.Drawing.Color]::DimGray
[void]$status.Items.Add($statusLabel)
[void]$status.Items.Add($vaultLabel)

$form.Controls.Add($list)
$form.Controls.Add($top)
$form.Controls.Add($status)

#endregion

#region ---------------------------------------------------------------- data

function Get-CheckedLocations {
    $locs = New-Object System.Collections.Generic.List[object]
    foreach ($item in $list.CheckedItems) {
        $g = $item.Tag
        if ($g -and $g.Locations) {
            foreach ($l in @($g.Locations)) { $locs.Add($l) }
        }
    }
    # De-duplicate by resolved path / registry key.
    $seen = @{}
    $unique = New-Object System.Collections.Generic.List[object]
    foreach ($l in $locs) {
        $key = if ($l.Kind -eq 'Registry') { 'reg|' + [string]$l.RegistryKey } else { 'path|' + ([string]$l.ResolvedPath).ToLowerInvariant() }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $unique.Add($l)
    }
    return $unique.ToArray()
}

function Update-VaultLabel {
    $vaultLabel.Text = 'Vault: ' + $script:Vault
}

function Load-Games {
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $statusLabel.Text = 'Scanning installed games and save folders...'
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $script:Games = @(Get-GSVAllGames -Settings $script:Settings)
        $script:Global = @(Get-GSVGlobalSaveLocations -Settings $script:Settings -NoSize)
        $script:Emulators = @(Get-GSVEmulatorSaveLocations -Settings $script:Settings -NoSize)

        $list.BeginUpdate()
        $list.Items.Clear()

        if ($script:Global.Count -gt 0) {
            $files = 0; $bytes = [int64]0
            foreach ($l in $script:Global) { $files += [int](0 + $l.FileCount); $bytes += [int64](0 + $l.Bytes) }
            $item = New-Object System.Windows.Forms.ListViewItem('Global launcher / emulator saves')
            [void]$item.SubItems.Add('Global')
            [void]$item.SubItems.Add([string]$script:Global.Count)
            [void]$item.SubItems.Add((Format-GSVSize $bytes))
            [void]$item.SubItems.Add('Ubisoft Connect / Goldberg / scene release save folders')
            $item.Tag = [pscustomobject]@{ Name = 'Global launcher / emulator saves'; Source = 'Global'; Locations = $script:Global }
            $item.Checked = $true
            $item.Font = New-Object System.Drawing.Font($list.Font, [System.Drawing.FontStyle]::Bold)
            [void]$list.Items.Add($item)
        }

        foreach ($group in @($script:Emulators | Group-Object Source | Sort-Object Name)) {
            $groupLocs = @($group.Group)
            $bytes = [int64]0
            foreach ($l in $groupLocs) { $bytes += [int64](0 + $l.Bytes) }
            $paths = @($groupLocs | ForEach-Object { $_.ResolvedPath })
            $preview = ($paths | Select-Object -First 3) -join '; '
            $item = New-Object System.Windows.Forms.ListViewItem(("{0} emulator saves ({1} titles)" -f $group.Name, $groupLocs.Count))
            [void]$item.SubItems.Add('Emulator')
            [void]$item.SubItems.Add([string]$groupLocs.Count)
            [void]$item.SubItems.Add((Format-GSVSize $bytes))
            [void]$item.SubItems.Add($preview)
            $item.Tag = [pscustomobject]@{ Name = $group.Name; Source = 'Emulator'; Locations = $groupLocs }
            $item.Checked = $true
            $item.Font = New-Object System.Drawing.Font($list.Font, [System.Drawing.FontStyle]::Bold)
            [void]$list.Items.Add($item)
        }

        $withSaves = @($script:Games | Where-Object { @($_.Locations).Count -gt 0 })
        $without = @($script:Games | Where-Object { @($_.Locations).Count -eq 0 })

        foreach ($g in @($withSaves + $without)) {
            $locs = @($g.Locations)
            $files = 0; $bytes = [int64]0
            foreach ($l in $locs) { $files += [int](0 + $l.FileCount); $bytes += [int64](0 + $l.Bytes) }

            $paths = @($locs | Where-Object { $_.Kind -ne 'Registry' } | ForEach-Object { $_.ResolvedPath })
            $preview = if ($paths.Count -eq 0) { '(no save folder found)' } else { ($paths | Select-Object -First 3) -join '; ' }

            $item = New-Object System.Windows.Forms.ListViewItem([string]$g.Name)
            [void]$item.SubItems.Add([string]$g.Source)
            [void]$item.SubItems.Add([string]$locs.Count)
            [void]$item.SubItems.Add((Format-GSVSize $bytes))
            [void]$item.SubItems.Add($preview)
            $item.Tag = $g
            $item.Checked = ($locs.Count -gt 0)
            if ($locs.Count -eq 0) { $item.ForeColor = [System.Drawing.Color]::Gray }
            [void]$list.Items.Add($item)
        }

        $list.EndUpdate()
        $statusLabel.Text = ('{0} games detected, {1} with save folders. Vault: {2}' -f $script:Games.Count, $withSaves.Count, $script:Vault)
    } catch {
        Show-Error "Scan failed: $($_.Exception.Message)"
        $statusLabel.Text = 'Scan failed.'
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

function Invoke-GuiBackup {
    param([object[]]$Locations, [string]$Label)

    if (-not $Locations -or $Locations.Count -eq 0) {
        Show-Warn 'Nothing selected to back up.'
        return
    }

    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $statusLabel.Text = ('Backing up {0} save locations...' -f $Locations.Count)
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $r = New-GSVSnapshot -Locations $Locations -BackupRoot $script:Vault -Label $Label
        $msg = "Backup complete.`n`nFiles: $($r.TotalFiles)`nSize: $(Format-GSVSize $r.TotalBytes)`nSnapshot: $($r.SnapshotPath)"
        if (@($r.Errors).Count -gt 0) { $msg += "`n`nWarnings: $(@($r.Errors).Count) (see logs folder)" }
        Show-Info $msg 'Backup complete'
        $statusLabel.Text = ('Backup complete: {0} files, {1}' -f $r.TotalFiles, (Format-GSVSize $r.TotalBytes))
    } catch {
        Show-Error "Backup failed: $($_.Exception.Message)"
        $statusLabel.Text = 'Backup failed.'
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

#endregion

#region ---------------------------------------------------------------- events

$btnScan.Add_Click({
    Load-Games
})

$btnDeep.Add_Click({
    Show-DeepScanDialog
})

$btnMigrate.Add_Click({
    Show-MigrateDialog
})

$btnBackup.Add_Click({
    $locs = @(Get-CheckedLocations)
    Invoke-GuiBackup -Locations $locs -Label 'gui-selected'
})

$btnBackupAll.Add_Click({
    $locs = New-Object System.Collections.Generic.List[object]
    foreach ($g in $script:Games) { foreach ($l in @($g.Locations)) { $locs.Add($l) } }
    foreach ($l in $script:Global) { $locs.Add($l) }
    foreach ($l in $script:Emulators) { $locs.Add($l) }

    $seen = @{}
    $unique = New-Object System.Collections.Generic.List[object]
    foreach ($l in $locs) {
        $key = if ($l.Kind -eq 'Registry') { 'reg|' + [string]$l.RegistryKey } else { 'path|' + ([string]$l.ResolvedPath).ToLowerInvariant() }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $unique.Add($l)
    }
    Invoke-GuiBackup -Locations $unique.ToArray() -Label 'gui-all'
})

$btnRestore.Add_Click({
    $snap = Select-SnapshotDialog
    if (-not $snap) { return }

    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Restore this snapshot?`n`n$($snap.Name)`nEntries: $($snap.EntryCount)`nFiles: $($snap.TotalFiles)`n`nExisting saves are moved to the vault's rollback folder first.",
        'Confirm restore',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne 'Yes') { return }

    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $statusLabel.Text = 'Restoring...'
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $r = Restore-GSVSnapshot -BackupRoot $script:Vault -Snapshot $snap.Path
        $msg = "Restore complete.`n`nRestored: $($r.Restored)`nRegistry keys: $($r.Registry)`nSkipped: $($r.Skipped)`nFailed: $($r.Failed)"
        if (@($r.Messages).Count -gt 0) {
            $msg += "`n`nDetails:`n" + (($r.Messages | Select-Object -First 8) -join "`n")
        }
        Show-Info $msg 'Restore complete'
        $statusLabel.Text = ('Restore complete: {0} entries, {1} failed' -f $r.Restored, $r.Failed)
    } catch {
        Show-Error "Restore failed: $($_.Exception.Message)"
        $statusLabel.Text = 'Restore failed.'
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
})

$btnOld.Add_Click({
    $roots = @(Get-GSVWindowsOldRoots)
    $root = if ($roots.Count -gt 0) { $roots[0] } else { $null }

    if (-not $root) {
        Show-Warn 'No Windows.old folder was found on any drive. Select it manually if it exists elsewhere.'
        $root = Select-Folder 'Select the Windows.old folder'
        if (-not $root) { return }
    }

    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Scan this folder for game saves?`n`n$root`n`nThe saves are first imported into the vault, then restored into the current user profile.",
        'Recover from Windows.old',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne 'Yes') { return }

    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $statusLabel.Text = 'Scanning Windows.old...'
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $r = Import-GSVFromWindowsOld -BackupRoot $script:Vault -WindowsOldRoot $root
        if (-not $r.Snapshot) {
            Show-Warn 'Nothing that looks like game saves was found.'
            return
        }
        $msg = "Windows.old recovery finished.`n`nLocations found: $($r.Locations)`nFiles imported: $($r.Snapshot.TotalFiles)`nSnapshot: $($r.Snapshot.SnapshotPath)"
        if ($r.Restore) { $msg += "`nRestored: $($r.Restore.Restored)`nSkipped: $($r.Restore.Skipped)`nFailed: $($r.Restore.Failed)" }
        Show-Info $msg 'Windows.old recovery'
        $statusLabel.Text = ('Recovered {0} locations from Windows.old' -f $r.Locations)
        Load-Games
    } catch {
        Show-Error "Windows.old recovery failed: $($_.Exception.Message)"
        $statusLabel.Text = 'Windows.old recovery failed.'
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
})

$btnAdd.Add_Click({
    $name = Read-GuiText 'Add a game' 'Game name (as you want it to appear):'
    if (-not $name) { return }

    $folder = Select-Folder 'Select the save folder for this game'
    if (-not $folder) { return }

    try {
        # Merge with an existing custom entry of the same name.
        $existingPaths = @()
        $custom = @(Get-GSVCustomGames)
        $match = $custom | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($match) { $existingPaths = @($match.Paths) }

        $paths = @($existingPaths + $folder | Select-Object -Unique)
        $entry = Save-GSVCustomGame -Name $name -Paths $paths -Notes 'Added from GUI'
        Show-Info "Saved '$($entry.Name)' with $($paths.Count) save path(s).`nIt is included in the next backup."
        Load-Games
    } catch {
        Show-Error "Could not add the game: $($_.Exception.Message)"
    }
})

$btnVault.Add_Click({
    if (-not (Test-Path -LiteralPath $script:Vault)) {
        try { New-Item -ItemType Directory -Path $script:Vault -Force | Out-Null } catch { }
    }
    if (Test-Path -LiteralPath $script:Vault) {
        Start-Process explorer.exe -ArgumentList ('"' + $script:Vault + '"')
    } else {
        Show-Warn "Vault folder does not exist yet: $script:Vault"
    }
})

$btnVaultLoc.Add_Click({
    Show-VaultLocationDialog
})

$btnDoctor.Add_Click({
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('GameSaveVault diagnostics')
    $lines.Add('-----------------------')
    $lines.Add('PowerShell      : ' + $PSVersionTable.PSVersion)
    $lines.Add('Vault           : ' + $script:Vault)
    $lines.Add('Vault on C:     : ' + $script:Vault.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase))
    $lines.Add('Catalog entries : ' + (@(Get-GSVCatalog).Count))
    $lines.Add('Custom games    : ' + (@(Get-GSVCustomGames).Count))
    $lines.Add('Installed games : ' + $script:Games.Count)
    $lines.Add('Snapshots       : ' + (@(Get-GSVSnapshots -BackupRoot $script:Vault).Count))
    $old = @(Get-GSVWindowsOldRoots)
    $lines.Add('Windows.old     : ' + $(if ($old.Count) { $old -join '; ' } else { 'none' }))

    if ($script:Vault.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)) {
        $lines.Add('')
        $lines.Add('WARNING: the vault is on the system drive.')
        $lines.Add('A clean Windows install can erase it. Use D:\ or an external disk.')
    }

    Show-Info ($lines -join "`r`n") 'Diagnostics'
})

$list.Add_DoubleClick({
    if ($list.SelectedItems.Count -eq 0) { return }
    $g = $list.SelectedItems[0].Tag
    if (-not $g) { return }
    $loc = @($g.Locations | Where-Object { $_.Kind -ne 'Registry' -and $_.ResolvedPath -and (Test-Path -LiteralPath $_.ResolvedPath) } | Select-Object -First 1)
    if ($loc.Count -eq 0) { Show-Warn 'No existing save folder for this entry.'; return }
    $target = if (Test-Path -LiteralPath $loc[0].ResolvedPath -PathType Leaf) { Split-Path -Parent $loc[0].ResolvedPath } else { $loc[0].ResolvedPath }
    Start-Process explorer.exe -ArgumentList ('"' + $target + '"')
})

$list.Add_ItemCheck({
    $item = $this.Items[$_.Index]
    if ($_.NewValue -eq [System.Windows.Forms.CheckState]::Checked) {
        $g = $item.Tag
        if ($g -and @($g.Locations).Count -eq 0) {
            $_.NewValue = [System.Windows.Forms.CheckState]::Unchecked
        }
    }
})

$form.Add_Shown({
    Load-Games
})

#endregion

if ($SmokeTest) {
    Write-Host ("GUI smoke test OK: form='{0}', controls={1}, columns={2}, vault={3}" -f $form.Text, $form.Controls.Count, $list.Columns.Count, $script:Vault)
    $form.Dispose()
    exit 0
}

[void]$form.ShowDialog()
