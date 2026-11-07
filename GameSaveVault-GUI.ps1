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

function Show-ScanFoldersDialog {
    $candidates = @(Get-GSVScanRootCandidates)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Where should GameSaveVault look for game saves?'
    $dlg.Size = New-Object System.Drawing.Size(900, 660)
    $dlg.MinimumSize = New-Object System.Drawing.Size(700, 460)
    $dlg.StartPosition = 'CenterParent'
    $dlg.MinimizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Choose the drives or folders to search. GameSaveVault scans only the folders you tick (and their subfolders), then stores what it finds in the scan database. Nothing is scanned automatically."
    $lbl.Location = New-Object System.Drawing.Point(14, 12)
    $lbl.Size = New-Object System.Drawing.Size(860, 36)
    $lbl.Anchor = 'Top,Left,Right'

    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.Location = New-Object System.Drawing.Point(14, 54)
    $clb.Size = New-Object System.Drawing.Size(860, 470)
    $clb.Anchor = 'Top,Bottom,Left,Right'
    $clb.CheckOnClick = $true
    $clb.IntegralHeight = $false
    $clb.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $clb.DisplayMember = 'Display'

    if ($candidates.Count -eq 0) {
        [void]$clb.Items.Add([pscustomobject]@{ Path = ''; Kind = ''; Note = ''; Display = '(no drives or folders found)'; Selected = $false })
    } else {
        foreach ($c in $candidates) {
            $idx = $clb.Items.Add($c)
            $clb.SetItemChecked($idx, [bool]$c.Selected)
        }
    }

    $chkStandard = New-Object System.Windows.Forms.CheckBox
    $chkStandard.Text = 'Also include standard launcher / emulator save folders (Steam userdata, AppData, Saved Games, emulator saves)'
    $chkStandard.Location = New-Object System.Drawing.Point(14, 530)
    $chkStandard.Size = New-Object System.Drawing.Size(860, 24)
    $chkStandard.Anchor = 'Bottom,Left,Right'
    $chkStandard.Checked = $true
    $existingDb = Read-GSVScanDatabase
    if ($existingDb -and ($existingDb.PSObject.Properties.Name -contains 'IncludeStandard')) {
        $chkStandard.Checked = [bool]$existingDb.IncludeStandard
    }

    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.Dock = 'Bottom'
    $panel.Height = 48
    $panel.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 6)
    $panel.WrapContents = $false

    $btnBrowse = New-TopButton 'Browse folder...' 120 'Add a folder that is not in the list'
    $btnAll = New-TopButton 'Check all' 90
    $btnNone = New-TopButton 'Uncheck all' 100
    $btnScan = New-TopButton 'Scan selected' 120 'Scan the ticked folders and store the results'
    $btnCancel = New-TopButton 'Cancel' 80

    $btnAll.Add_Click({ for ($i = 0; $i -lt $clb.Items.Count; $i++) { $clb.SetItemChecked($i, $true) } })
    $btnNone.Add_Click({ for ($i = 0; $i -lt $clb.Items.Count; $i++) { $clb.SetItemChecked($i, $false) } })

    $btnBrowse.Add_Click({
        $picked = Select-Folder 'Choose a folder to scan'
        if (-not $picked) { return }
        try { $full = (Get-Item -LiteralPath $picked -ErrorAction Stop).FullName } catch { return }

        for ($i = 0; $i -lt $clb.Items.Count; $i++) {
            $it = $clb.Items[$i]
            if ($it -and $it.Path -and ([string]$it.Path).TrimEnd('\') -ieq $full.TrimEnd('\')) {
                $clb.SetItemChecked($i, $true)
                return
            }
        }

        $obj = [pscustomobject]@{
            Path     = $full
            Kind     = 'Folder'
            Note     = 'custom folder'
            Display  = ('{0}  -  custom folder' -f $full)
            Selected = $true
        }
        $idx = $clb.Items.Add($obj)
        $clb.SetItemChecked($idx, $true)
    })

    $btnScan.Add_Click({
        $picked = New-Object System.Collections.Generic.List[string]
        foreach ($it in $clb.CheckedItems) {
            if ($it -and $it.Path) { $picked.Add([string]$it.Path) }
        }
        if ($picked.Count -eq 0) {
            Show-Warn 'Tick at least one folder to scan.'
            return
        }
        $dlg.Tag = [pscustomobject]@{
            Roots           = $picked.ToArray()
            IncludeStandard = [bool]$chkStandard.Checked
        }
        $dlg.Close()
    })

    $btnCancel.Add_Click({ $dlg.Close() })

    $panel.Controls.AddRange(@($btnBrowse, $btnAll, $btnNone, $btnScan, $btnCancel))
    $dlg.Controls.Add($clb)
    $dlg.Controls.Add($chkStandard)
    $dlg.Controls.Add($lbl)
    $dlg.Controls.Add($panel)

    [void]$dlg.ShowDialog()
    $result = $dlg.Tag
    $dlg.Dispose()

    if ($result -and $result.Roots -and @($result.Roots).Count -gt 0) { return $result }
    return $null
}

function Read-GuiRestoreFormat {
    param([string]$Title = 'Restore location')

    $format = Read-GuiText $Title "Restore to:`n  profile    = current Windows profile (default)`n  verbatim   = the original C: layout, exactly as saved`n  folder     = the folder you pick below, keeping <TOKEN>\<path> structure`nType one:" 'profile'
    if (-not $format) { return $null }

    $fmt = $format.Trim().ToLowerInvariant()
    if ($fmt -notin @('profile', 'verbatim', 'folder')) {
        Show-Warn "Unknown restore format: $format. Use profile, verbatim or folder."
        return $null
    }

    $root = ''
    if ($fmt -eq 'folder') {
        $root = Select-Folder 'Choose the folder every save should be copied into'
        if (-not $root) { return $null }
    }

    return [pscustomobject]@{ Format = $fmt; Root = $root }
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
    $roots = New-Object System.Collections.Generic.List[string]

    # mode picker: search a drive, or one or more specific directories
    $mode = Read-GuiText 'Deep scan - what to search?' "Type a drive letter (C:), ALL for every fixed drive,`nor a folder path (D:\Games, C:\PS5GAMES, ...):" $env:SystemDrive
    if (-not $mode) { return }

    if ($mode -ieq 'all' -or $mode -ieq '*') {
        foreach ($r in @(Get-GSVFixedDriveRoots)) { $roots.Add($r) }
    } else {
        # accept several paths separated by ';'
        foreach ($part in ($mode -split ';')) {
            $p = $part.Trim()
            if (-not $p) { continue }
            if ($p -match '^[A-Za-z]$') { $p = $p + ':\' }
            elseif ($p -match '^[A-Za-z]:$') { $p = $p + '\' }
            if (-not $p.EndsWith('\')) { $p += '\' }
            $roots.Add($p)
        }
        # also offer a folder browser for a custom directory
        if (($roots.Count -eq 0) -or (-not (Test-Path -LiteralPath ($roots[0].TrimEnd('\'))))) {
            $picked = Select-Folder 'Choose a directory to deep-scan'
            if ($picked) { $roots.Add($picked.TrimEnd('\') + '\') }
        }
    }

    if ($roots.Count -eq 0) { Show-Warn 'No drive or directory to scan.'; return }

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

    # Keep the stored database in sync with this ad-hoc deep scan.
    try { $null = Update-GSVScanDatabase -Roots $roots.ToArray() -Locations $locs } catch { }

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
    Load-ScanDatabase
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

#region ---------------------------------------------------------------- save rules editor

function Format-RulePathEntry {
    param($Entry)
    if ($null -eq $Entry) { return '' }
    $pat = if ($Entry -is [string]) { [string]$Entry } else { [string]$Entry.Pattern }
    $mode = if ($Entry -is [string]) { 'auto' } else { [string]$Entry.Mode }
    return ('{0}   [{1}]' -f $pat, $mode)
}

function Show-RuleEditor {
    param($Rule = $null)

    $script:RuleEditorSaved = $false

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = if ($Rule) { 'Edit save rule' } else { 'Add save rule' }
    $dlg.Size = New-Object System.Drawing.Size(780, 650)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    function New-EditorLabel {
        param([string]$Text, [int]$X, [int]$Y)
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $Text
        $l.Location = New-Object System.Drawing.Point($X, $Y)
        $l.Size = New-Object System.Drawing.Size(105, 20)
        return $l
    }

    function New-EditorBox {
        param([int]$X, [int]$Y, [int]$W, [string]$Text = '')
        $t = New-Object System.Windows.Forms.TextBox
        $t.Location = New-Object System.Drawing.Point($X, $Y)
        $t.Size = New-Object System.Drawing.Size($W, 24)
        $t.Text = $Text
        return $t
    }

    $lblName = New-EditorLabel 'Game name' 12 15
    $tbName = New-EditorBox 120 12 300

    $lblApp = New-EditorLabel 'Steam AppIDs' 12 45
    $tbApp = New-EditorBox 120 42 300

    $lblAlias = New-EditorLabel 'Aliases' 12 75
    $tbAlias = New-EditorBox 120 72 620

    $lblInstall = New-EditorLabel 'Install folders' 12 105
    $tbInstall = New-EditorBox 120 102 620

    $lblFiles = New-EditorLabel 'Save file globs' 12 135
    $tbFiles = New-EditorBox 120 132 300

    $lblFolders = New-EditorLabel 'Save folder globs' 12 165
    $tbFolders = New-EditorBox 120 162 300

    $lblMode = New-EditorLabel 'Restore mode' 440 135
    $cbMode = New-Object System.Windows.Forms.ComboBox
    $cbMode.Location = New-Object System.Drawing.Point(540, 132)
    $cbMode.Size = New-Object System.Drawing.Size(200, 24)
    $cbMode.DropDownStyle = 'DropDownList'
    [void]$cbMode.Items.AddRange(@('auto', 'token', 'gamedir', 'absolute'))
    $cbMode.SelectedItem = 'auto'

    $lblNotes = New-EditorLabel 'Notes' 12 195
    $tbNotes = New-EditorBox 120 192 620

    $lblPaths = New-Object System.Windows.Forms.Label
    $lblPaths.Text = 'Save locations (folders, wildcards, or %TOKEN% patterns)'
    $lblPaths.Location = New-Object System.Drawing.Point(12, 230)
    $lblPaths.Size = New-Object System.Drawing.Size(500, 20)

    $lbPaths = New-Object System.Windows.Forms.ListBox
    $lbPaths.Location = New-Object System.Drawing.Point(12, 254)
    $lbPaths.Size = New-Object System.Drawing.Size(600, 230)
    $lbPaths.HorizontalScrollbar = $true

    $btnAddFolder = New-Object System.Windows.Forms.Button
    $btnAddFolder.Text = 'Add folder...'
    $btnAddFolder.Location = New-Object System.Drawing.Point(624, 254)
    $btnAddFolder.Size = New-Object System.Drawing.Size(130, 30)

    $btnAddPattern = New-Object System.Windows.Forms.Button
    $btnAddPattern.Text = 'Add pattern...'
    $btnAddPattern.Location = New-Object System.Drawing.Point(624, 292)
    $btnAddPattern.Size = New-Object System.Drawing.Size(130, 30)

    $btnRemovePath = New-Object System.Windows.Forms.Button
    $btnRemovePath.Text = 'Remove'
    $btnRemovePath.Location = New-Object System.Drawing.Point(624, 330)
    $btnRemovePath.Size = New-Object System.Drawing.Size(130, 30)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = "Token paths are portable: %LOCALAPPDATA%, %APPDATA%, %DOCUMENTS%, %SAVEDGAMES%, %PUBLICDOCS%, %PROGRAMDATA%, %STEAMUSERDATA%, %GAMEDIR%." + "`r`n" +
        "Use gamedir mode (or %GAMEDIR%) so the save is restored next to the game found on the new PC."
    $hint.Location = New-Object System.Drawing.Point(12, 492)
    $hint.Size = New-Object System.Drawing.Size(740, 40)
    $hint.ForeColor = [System.Drawing.Color]::DimGray

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = 'Save rule'
    $btnSave.Location = New-Object System.Drawing.Point(560, 560)
    $btnSave.Size = New-Object System.Drawing.Size(100, 32)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Location = New-Object System.Drawing.Point(670, 560)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 32)

    $dlg.AcceptButton = $btnSave
    $dlg.CancelButton = $btnCancel

    $paths = New-Object System.Collections.Generic.List[object]

    # Pre-fill when editing.
    if ($Rule) {
        $tbName.Text = [string]$Rule.Name
        $tbApp.Text = (@($Rule.SteamAppIds) -join ', ')
        $tbAlias.Text = (@($Rule.Aliases) -join ', ')
        $tbInstall.Text = (@($Rule.InstallDirNames) -join ', ')
        $tbFiles.Text = (@($Rule.FilePatterns) -join ', ')
        $tbFolders.Text = (@($Rule.FolderPatterns) -join ', ')
        $tbNotes.Text = [string]$Rule.Notes
        if ($Rule.Paths -and @($Rule.Paths).Count -gt 0) {
            $first = @($Rule.Paths)[0]
            $m = if ($first -is [string]) { 'auto' } else { [string]$first.Mode }
            if ($m -and $cbMode.Items.Contains($m)) { $cbMode.SelectedItem = $m }
        }
        foreach ($p in @($Rule.Paths)) {
            $paths.Add($p)
            [void]$lbPaths.Items.Add((Format-RulePathEntry $p))
        }
    }

    $getInstallNames = {
        @($tbInstall.Text -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    $btnAddFolder.Add_Click({
        $folder = Select-Folder 'Select a save folder for this game' $env:USERPROFILE
        if (-not $folder) { return }
        $install = & $getInstallNames
        if (-not $install -or @($install).Count -eq 0) { $install = @($tbName.Text.Trim()) }
        $obj = ConvertTo-GSVRulePathEntry -Path $folder -Mode ([string]$cbMode.SelectedItem) -InstallDirNames $install
        if ($obj) {
            $paths.Add($obj)
            [void]$lbPaths.Items.Add((Format-RulePathEntry $obj))
        }
    })

    $btnAddPattern.Add_Click({
        $p = Read-GuiText 'Add save path pattern' "Enter a folder / wildcard pattern.`nExamples: %LOCALAPPDATA%\MyGame\Saved   or   D:\Games\MyGame\Saves   or   %APPDATA%\GSE Saves\1234" '%LOCALAPPDATA%\MyGame\Saved'
        if (-not $p) { return }
        $install = & $getInstallNames
        if (-not $install -or @($install).Count -eq 0) { $install = @($tbName.Text.Trim()) }
        $obj = ConvertTo-GSVRulePathEntry -Path $p -Mode ([string]$cbMode.SelectedItem) -InstallDirNames $install
        if ($obj) {
            $paths.Add($obj)
            [void]$lbPaths.Items.Add((Format-RulePathEntry $obj))
        }
    })

    $btnRemovePath.Add_Click({
        if ($lbPaths.SelectedIndex -lt 0) { return }
        $i = $lbPaths.SelectedIndex
        $paths.RemoveAt($i)
        $lbPaths.Items.RemoveAt($i)
    })

    $btnSave.Add_Click({
        $name = $tbName.Text.Trim()
        if (-not $name) { Show-Warn 'Game name is required.'; return }
        if ($paths.Count -eq 0) { Show-Warn 'Add at least one save folder or pattern.'; return }

        $splitList = {
            param([string]$Text)
            @($Text -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }

        $appIds = & $splitList $tbApp.Text
        $aliases = & $splitList $tbAlias.Text
        $install = & $splitList $tbInstall.Text
        if (-not $install -or @($install).Count -eq 0) { $install = @($name) }
        $files = & $splitList $tbFiles.Text
        $folders = & $splitList $tbFolders.Text

        $patterns = @()
        foreach ($p in $paths) { $patterns += (if ($p -is [string]) { [string]$p } else { [string]$p.Pattern }) }

        try {
            $null = Save-GSVRule -Name $name -Paths $patterns -FilePatterns $files -FolderPatterns $folders `
                -Aliases $aliases -SteamAppIds $appIds -InstallDirNames $install `
                -Mode ([string]$cbMode.SelectedItem) -Notes $tbNotes.Text
            $script:RuleEditorSaved = $true
            $dlg.Close()
        } catch {
            Show-Error "Could not save the rule: $($_.Exception.Message)"
        }
    })

    $btnCancel.Add_Click({ $dlg.Close() })

    $dlg.Controls.AddRange(@(
        $lblName, $tbName, $lblApp, $tbApp, $lblAlias, $tbAlias, $lblInstall, $tbInstall,
        $lblFiles, $tbFiles, $lblFolders, $tbFolders, $lblMode, $cbMode, $lblNotes, $tbNotes,
        $lblPaths, $lbPaths, $btnAddFolder, $btnAddPattern, $btnRemovePath, $hint, $btnSave, $btnCancel
    ))

    [void]$dlg.ShowDialog()
    $dlg.Dispose()
    return [bool]$script:RuleEditorSaved
}

function Show-RulesDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Save rules - portable save locations (config\save-rules.json)'
    $dlg.Size = New-Object System.Drawing.Size(980, 620)
    $dlg.StartPosition = 'CenterParent'
    $dlg.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Location = New-Object System.Drawing.Point(12, 12)
    $lv.Size = New-Object System.Drawing.Size(940, 330)
    $lv.View = 'Details'
    $lv.FullRowSelect = $true
    $lv.GridLines = $false
    $lv.HideSelection = $false
    $lv.MultiSelect = $false

    [void]$lv.Columns.Add('Game', 230)
    [void]$lv.Columns.Add('AppIDs', 110)
    [void]$lv.Columns.Add('Paths', 60, [System.Windows.Forms.HorizontalAlignment]::Center)
    [void]$lv.Columns.Add('Install folder names', 200)
    [void]$lv.Columns.Add('Save patterns', 300)

    $detail = New-Object System.Windows.Forms.TextBox
    $detail.Location = New-Object System.Drawing.Point(12, 352)
    $detail.Size = New-Object System.Drawing.Size(940, 160)
    $detail.Multiline = $true
    $detail.ReadOnly = $true
    $detail.ScrollBars = 'Vertical'
    $detail.Font = New-Object System.Drawing.Font('Consolas', 9)

    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Text = 'Add rule...'
    $btnAdd.Location = New-Object System.Drawing.Point(12, 524)
    $btnAdd.Size = New-Object System.Drawing.Size(100, 32)

    $btnEdit = New-Object System.Windows.Forms.Button
    $btnEdit.Text = 'Edit...'
    $btnEdit.Location = New-Object System.Drawing.Point(120, 524)
    $btnEdit.Size = New-Object System.Drawing.Size(80, 32)

    $btnRemove = New-Object System.Windows.Forms.Button
    $btnRemove.Text = 'Remove'
    $btnRemove.Location = New-Object System.Drawing.Point(208, 524)
    $btnRemove.Size = New-Object System.Drawing.Size(80, 32)

    $btnDiscover = New-Object System.Windows.Forms.Button
    $btnDiscover.Text = 'Discover now'
    $btnDiscover.Location = New-Object System.Drawing.Point(296, 524)
    $btnDiscover.Size = New-Object System.Drawing.Size(110, 32)

    $btnExport = New-Object System.Windows.Forms.Button
    $btnExport.Text = 'Export...'
    $btnExport.Location = New-Object System.Drawing.Point(414, 524)
    $btnExport.Size = New-Object System.Drawing.Size(90, 32)

    $btnImport = New-Object System.Windows.Forms.Button
    $btnImport.Text = 'Import...'
    $btnImport.Location = New-Object System.Drawing.Point(512, 524)
    $btnImport.Size = New-Object System.Drawing.Size(90, 32)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Location = New-Object System.Drawing.Point(872, 524)
    $btnClose.Size = New-Object System.Drawing.Size(80, 32)

    $status = New-Object System.Windows.Forms.Label
    $status.Location = New-Object System.Drawing.Point(614, 532)
    $status.Size = New-Object System.Drawing.Size(250, 20)
    $status.ForeColor = [System.Drawing.Color]::DimGray

    function Refresh-RuleList {
        $lv.BeginUpdate()
        $lv.Items.Clear()
        $rules = @(Get-GSVRules -Refresh)
        foreach ($r in $rules) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$r.Name)
            [void]$item.SubItems.Add((@($r.SteamAppIds) -join ', '))
            [void]$item.SubItems.Add([string](@($r.Paths).Count))
            [void]$item.SubItems.Add((@($r.InstallDirNames) -join ', '))
            [void]$item.SubItems.Add((@($r.FilePatterns) -join ', '))
            $item.Tag = $r
            [void]$lv.Items.Add($item)
        }
        $lv.EndUpdate()
        $status.Text = ('{0} rule(s)' -f $rules.Count)
    }

    $showDetail = {
        if ($lv.SelectedItems.Count -eq 0) { $detail.Text = ''; return }
        $r = $lv.SelectedItems[0].Tag
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add(('Game       : {0}' -f $r.Name))
        $lines.Add(('Rule id    : {0}' -f $r.Id))
        if (@($r.Aliases).Count -gt 0) { $lines.Add(('Aliases    : {0}' -f (@($r.Aliases) -join ', '))) }
        if (@($r.SteamAppIds).Count -gt 0) { $lines.Add(('AppIDs     : {0}' -f (@($r.SteamAppIds) -join ', '))) }
        if (@($r.InstallDirNames).Count -gt 0) { $lines.Add(('Install dir: {0}' -f (@($r.InstallDirNames) -join ', '))) }
        if (@($r.FilePatterns).Count -gt 0) { $lines.Add(('Save files : {0}' -f (@($r.FilePatterns) -join ', '))) }
        if (@($r.FolderPatterns).Count -gt 0) { $lines.Add(('Save folders: {0}' -f (@($r.FolderPatterns) -join ', '))) }
        if ($r.Notes) { $lines.Add(('Notes      : {0}' -f $r.Notes)) }
        $lines.Add('')
        $lines.Add('Paths:')
        foreach ($p in @($r.Paths)) { $lines.Add('  - ' + (Format-RulePathEntry $p)) }
        $detail.Text = ($lines -join "`r`n")
    }

    $lv.Add_SelectedIndexChanged($showDetail)

    $btnAdd.Add_Click({
        if (Show-RuleEditor) {
            Refresh-RuleList
            Load-Games
        }
    })

    $btnEdit.Add_Click({
        if ($lv.SelectedItems.Count -eq 0) { Show-Warn 'Select a rule first.'; return }
        if (Show-RuleEditor -Rule $lv.SelectedItems[0].Tag) {
            Refresh-RuleList
            Load-Games
        }
    })

    $btnRemove.Add_Click({
        if ($lv.SelectedItems.Count -eq 0) { Show-Warn 'Select a rule first.'; return }
        $r = $lv.SelectedItems[0].Tag
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "Remove the save rule '$($r.Name)'?`n`nThe backup snapshots are not touched.",
            'Remove rule', [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -ne 'Yes') { return }
        $null = Remove-GSVRule -Id $r.Id
        Refresh-RuleList
        Load-Games
    })

    $btnDiscover.Add_Click({
        $all = New-Object System.Collections.Generic.List[object]
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($r in @(Get-GSVRules)) {
            $locs = @(Resolve-GSVRulePaths -Rule $r -NoSize)
            $dir = Find-GSVRuleGameDir -Names @($r.InstallDirNames)
            $lines.Add(('{0}: {1} save(s){2}' -f $r.Name, $locs.Count, $(if ($dir) { '  [installed: ' + $dir + ']' } else { '  [install folder not found]' })))
            foreach ($l in $locs) { $lines.Add('    ' + $l.ResolvedPath); $all.Add($l) }
        }
        if ($lines.Count -eq 0) { $lines.Add('No rules defined yet.') }
        $msg = "Discovered $($all.Count) save folder(s).`n`n" + (($lines | Select-Object -First 30) -join "`n")
        Show-Info $msg 'Discover save rules'
        if ($all.Count -gt 0) { Load-Games }
    })

    $btnExport.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Title = 'Export save rules'
        $sfd.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
        $sfd.FileName = 'save-rules.json'
        if ($sfd.ShowDialog() -eq 'OK') {
            try {
                $p = Export-GSVRules -Path $sfd.FileName
                Show-Info "Exported to:`n$p"
            } catch { Show-Error "Export failed: $($_.Exception.Message)" }
        }
    })

    $btnImport.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Title = 'Import save rules'
        $ofd.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
        if ($ofd.ShowDialog() -eq 'OK') {
            try {
                $n = Import-GSVRules -Path $ofd.FileName
                Refresh-RuleList
                Load-Games
                Show-Info "Imported $n rule(s)."
            } catch { Show-Error "Import failed: $($_.Exception.Message)" }
        }
    })

    $btnClose.Add_Click({ $dlg.Close() })

    $dlg.Controls.AddRange(@($lv, $detail, $btnAdd, $btnEdit, $btnRemove, $btnDiscover, $btnExport, $btnImport, $btnClose, $status))

    Refresh-RuleList
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

#endregion

#endregion

#region ---------------------------------------------------------------- form

$form = New-Object System.Windows.Forms.Form
$form.Text = 'GameSaveVault  -  game save backup & restore'
$form.Size = New-Object System.Drawing.Size(1240, 720)
$form.MinimumSize = New-Object System.Drawing.Size(1000, 560)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$top = New-Object System.Windows.Forms.FlowLayoutPanel
$top.Dock = 'Top'
$top.Height = 84
$top.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 4)
$top.WrapContents = $true
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

$btnScan     = New-TopButton 'Scan folders...' 120 'Choose drives/folders to scan; results are stored in the scan database'
$btnRescan   = New-TopButton 'Rescan' 80 'Re-scan the folders already stored in the scan database'
$btnBackup   = New-TopButton 'Backup selected' 130 'Back up the checked games'
$btnBackupAll = New-TopButton 'Backup all' 100 'Back up every detected game'
$btnRestore  = New-TopButton 'Restore...' 100 'Restore a snapshot from this PC''s vault'
$btnRestoreFile = New-TopButton 'Restore file...' 110 'Restore saves on another PC from a portable .gsvdb database file'
$btnExportDb = New-TopButton 'Export DB...' 110 'Write one portable .gsvdb file containing saves + the scan database'
$btnOld      = New-TopButton 'Windows.old...' 120 'Recover saves from C:\Windows.old'
$btnDeep     = New-TopButton 'Deep scan...' 110 'Search a whole drive for CPY / GSE / scene / Steam / UWP saves'
$btnMigrate  = New-TopButton 'Migrate...' 90 'Copy console-emulator saves between emulators (Eden / Ryujinx / Eglantine / Kyty)'
$btnAdd      = New-TopButton 'Add game...' 100 'Register a custom save folder'
$btnRules    = New-TopButton 'Save rules...' 110 'Manage the portable save-location database (config\save-rules.json)'
$btnVault    = New-TopButton 'Open vault' 100 'Open the backup folder'
$btnVaultLoc = New-TopButton 'Backup location...' 150 'Choose where backups are stored (default vault folder)'
$btnDoctor   = New-TopButton 'Doctor' 80 'Check vault health'

$top.Controls.AddRange(@($btnScan, $btnRescan, $btnBackup, $btnBackupAll, $btnRestore, $btnRestoreFile, $btnExportDb, $btnOld, $btnDeep, $btnMigrate, $btnAdd, $btnRules, $btnVault, $btnVaultLoc, $btnDoctor))

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

function Load-ScanDatabase {
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $statusLabel.Text = 'Loading stored scan database...'
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $db = Read-GSVScanDatabase
        $locs = @(Get-GSVScanDatabaseLocations)
        $script:Games = @()
        $script:Global = @()
        $script:Emulators = @()

        $list.BeginUpdate()
        $list.Items.Clear()

        if (-not $db -or $locs.Count -eq 0) {
            $list.EndUpdate()
            $statusLabel.Text = 'No scan database yet. Click "Scan folders..." to choose where to look.'
            return
        }

        $groups = @($locs | Group-Object { '{0}|{1}' -f [string]$_.GameName, [string]$_.AppId })
        $games = New-Object System.Collections.Generic.List[object]

        foreach ($group in ($groups | Sort-Object Name)) {
            $groupLocs = @($group.Group)
            if ($groupLocs.Count -eq 0) { continue }
            $first = $groupLocs[0]

            $files = 0; $bytes = [int64]0
            foreach ($l in $groupLocs) {
                $files += [int](0 + $l.FileCount)
                $bytes += [int64](0 + $l.Bytes)
            }

            $paths = @($groupLocs | Where-Object { $_.Kind -ne 'Registry' -and $_.ResolvedPath } | ForEach-Object { [string]$_.ResolvedPath })
            $preview = if ($paths.Count -eq 0) { '(registry only)' } else { ($paths | Select-Object -First 3) -join '; ' }

            $item = New-Object System.Windows.Forms.ListViewItem([string]$first.GameName)
            [void]$item.SubItems.Add([string]$first.Source)
            [void]$item.SubItems.Add([string]$groupLocs.Count)
            [void]$item.SubItems.Add((Format-GSVSize $bytes))
            [void]$item.SubItems.Add($preview)

            $game = [pscustomobject]@{
                Name      = [string]$first.GameName
                Source    = [string]$first.Source
                AppId     = [string]$first.AppId
                Locations = $groupLocs
            }
            $item.Tag = $game

            $missing = @($groupLocs | Where-Object { -not $_.Exists })
            $item.Checked = ($missing.Count -lt $groupLocs.Count)
            if ($missing.Count -eq $groupLocs.Count) { $item.ForeColor = [System.Drawing.Color]::Gray }

            [void]$list.Items.Add($item)
            $games.Add($game)
        }

        $script:Games = $games.ToArray()
        $list.EndUpdate()

        $updated = if ($db.UpdatedUtc) { ([datetime]$db.UpdatedUtc).ToLocalTime().ToString('yyyy-MM-dd HH:mm') } else { 'unknown' }
        $statusLabel.Text = ('{0} games, {1} save locations from scan database (updated {2}). Vault: {3}' -f $script:Games.Count, $locs.Count, $updated, $script:Vault)
    } catch {
        Show-Error "Could not load the scan database: $($_.Exception.Message)"
        $statusLabel.Text = 'Could not load the scan database.'
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

# Kept as a compatibility alias: the app now loads the stored database instead
# of scanning automatically.
function Load-Games {
    Load-ScanDatabase
}

function Invoke-GuiScanRoots {
    param([string[]]$Roots, [bool]$IncludeStandard = $true)

    $roots = @($Roots | Where-Object { $_ })
    if ($roots.Count -eq 0) { return }

    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $statusLabel.Text = ('Scanning {0} folder(s)...' -f $roots.Count)
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    $progress = {
        param($folders, $path)
        $statusLabel.Text = ('Scanning: {0:N0} folders... {1}' -f $folders, $path)
        [System.Windows.Forms.Application]::DoEvents()
    }

    try {
        $locs = @(Get-GSVDeepScanLocations -Roots $roots -MaxDepth 12 -MaxResults 2000 -NoSize -Progress $progress)

        $all = New-Object System.Collections.Generic.List[object]
        foreach ($l in $locs) { $all.Add($l) }

        if ($IncludeStandard) {
            $statusLabel.Text = 'Checking standard launcher / emulator save folders...'
            [System.Windows.Forms.Application]::DoEvents()

            foreach ($g in @(Get-GSVAllGames -Settings $script:Settings)) {
                foreach ($l in @($g.Locations)) {
                    if (-not $l) { continue }
                    $l | Add-Member -NotePropertyName ScanRoot -NotePropertyValue 'standard' -Force
                    $all.Add($l)
                }
            }
            foreach ($l in @(Get-GSVGlobalSaveLocations -Settings $script:Settings -NoSize)) {
                if (-not $l) { continue }
                $l | Add-Member -NotePropertyName ScanRoot -NotePropertyValue 'standard' -Force
                $all.Add($l)
            }
            foreach ($l in @(Get-GSVEmulatorSaveLocations -Settings $script:Settings -NoSize)) {
                if (-not $l) { continue }
                $l | Add-Member -NotePropertyName ScanRoot -NotePropertyValue 'standard' -Force
                $all.Add($l)
            }
        }

        $saved = Update-GSVScanDatabase -Roots $roots -Locations $all.ToArray() -IncludeStandard:$IncludeStandard
        Load-ScanDatabase

        if ($all.Count -eq 0) {
            Show-Warn "No save folders were found in the selected folders.`n`nTry selecting a whole drive or another game folder.`n`nDatabase: $($saved.Path)"
        } else {
            Show-Info ("Scan complete.`n`nFolders scanned: {0}`nSave locations found: {1}`nStored in database: {2}`n`n{3}" -f $roots.Count, $all.Count, $saved.Total, $saved.Path) 'Scan complete'
        }
    } catch {
        Show-Error "Scan failed: $($_.Exception.Message)"
        $statusLabel.Text = 'Scan failed.'
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

function Rescan-StoredRoots {
    $db = Read-GSVScanDatabase
    $roots = @(Get-GSVScanDatabaseRoots | ForEach-Object { [string]$_.Path })
    if ($roots.Count -eq 0) {
        $choice = Show-ScanFoldersDialog
        if ($choice) {
            Invoke-GuiScanRoots -Roots $choice.Roots -IncludeStandard:$choice.IncludeStandard
        } else {
            Load-ScanDatabase
        }
        return
    }

    $includeStandard = if ($db -and ($db.PSObject.Properties.Name -contains 'IncludeStandard')) { [bool]$db.IncludeStandard } else { $true }
    Invoke-GuiScanRoots -Roots $roots -IncludeStandard:$includeStandard
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

function Invoke-GuiExportDatabase {
    $db = Read-GSVScanDatabase
    $locs = @(Get-GSVScanDatabaseLocations -OnlyExisting)
    $snaps = @(Get-GSVSnapshots -BackupRoot $script:Vault)

    if ($locs.Count -eq 0 -and $snaps.Count -eq 0) {
        Show-Warn 'Nothing to export yet. Scan your game folders and back them up first.'
        return
    }

    if ($snaps.Count -eq 0) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "No backup snapshot exists yet.`n`nCreate one now from the scan database ($($locs.Count) save location(s)), then write the portable database?",
            'Export portable database',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $statusLabel.Text = 'Creating backup snapshot...'
        $form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
        try {
            $null = New-GSVSnapshot -Locations $locs -BackupRoot $script:Vault -Label 'portable-db'
        } catch {
            Show-Error "Could not create the backup snapshot: $($_.Exception.Message)"
            return
        } finally {
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    }

    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title = 'Save the portable GameSaveVault database'
    $sfd.Filter = 'GameSaveVault database (*.gsvdb)|*.gsvdb|Zip archive (*.zip)|*.zip'
    $sfd.DefaultExt = 'gsvdb'
    $sfd.AddExtension = $true
    $sfd.FileName = ('GameSaveVault-{0}.gsvdb' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $statusLabel.Text = 'Writing portable database...'
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $r = New-GSVPortableDatabase -BackupRoot $script:Vault -Snapshot 'latest' -OutputPath $sfd.FileName -IncludeScanDatabase -Force
        Show-Info ("Portable database created.`n`nFile: {0}`nSize: {1}`nSnapshot: {2}`nEntries: {3}`nFiles: {4}`n`nCopy this one file to the other PC, then click ""Restore file..."" there." -f $r.Path, (Format-GSVSize $r.Bytes), $r.SnapshotName, $r.EntryCount, $r.TotalFiles) 'Export complete'
        $statusLabel.Text = ('Portable database written: {0}' -f $r.Path)
    } catch {
        Show-Error "Export failed: $($_.Exception.Message)"
        $statusLabel.Text = 'Export failed.'
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

function Invoke-GuiRestoreFromFile {
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Title = 'Select a GameSaveVault database file'
    $ofd.Filter = 'GameSaveVault database (*.gsvdb;*.zip)|*.gsvdb;*.zip|Scan database (*.json)|*.json|All files (*.*)|*.*'
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $path = $ofd.FileName
    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()

    # A plain scan-database.json only lists paths. Import it so the list is
    # available on this PC, but explain that the .gsvdb file carries the saves.
    if ($ext -eq '.json') {
        try {
            $imp = Import-GSVScanDatabaseFile -Path $path
            Load-ScanDatabase
            Show-Info ("Imported the scan database.`n`nLocations in file: {0}`nStored total: {1}`n`nThis file lists where saves belong. To restore the save files themselves, use the portable .gsvdb file created with ""Export DB...""." -f $imp.Imported, $imp.Total) 'Scan database imported'
        } catch {
            Show-Error "Could not import the scan database: $($_.Exception.Message)"
        }
        return
    }

    try {
        $info = Get-GSVPortableDatabaseInfo -Path $path
    } catch {
        Show-Error "This is not a readable GameSaveVault database: $($_.Exception.Message)"
        return
    }

    $choice = Read-GuiRestoreFormat -Title 'Restore from database file'
    if (-not $choice) { return }

    $where = if ($choice.Format -eq 'profile') { 'your current Windows profile' }
        elseif ($choice.Format -eq 'verbatim') { 'the original drive layout (verbatim)' }
        else { "the folder:`n$($choice.Root)`n(keeps the <TOKEN>\<path> structure)" }

    $answer = [System.Windows.Forms.MessageBox]::Show(
        ("Restore this portable database?`n`nFile: {0}`nFrom PC: {1}`nEntries: {2}`nFiles: {3}`n`nRestore to:`n{4}`n`nExisting saves are moved to the vault's rollback folder first." -f $info.Path, $info.Machine, $info.EntryCount, $info.TotalFiles, $where),
        'Confirm restore from file',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $statusLabel.Text = 'Restoring from portable database...'
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $r = Restore-GSVPortableDatabase -BundlePath $path -BackupRoot $script:Vault `
            -RestoreFormat $choice.Format -RestoreRoot $choice.Root
        $msg = "Restore complete.`n`nRestored: $($r.Restored)`nRegistry keys: $($r.Registry)`nSkipped: $($r.Skipped)`nFailed: $($r.Failed)`nScan database imported: $($r.ImportedDatabase)"
        if (@($r.Messages).Count -gt 0) {
            $msg += "`n`nDetails:`n" + (($r.Messages | Select-Object -First 8) -join "`n")
        }
        Show-Info $msg 'Restore from file complete'
        Load-ScanDatabase
        $statusLabel.Text = ('Restore from file complete: {0} restored, {1} failed' -f $r.Restored, $r.Failed)
    } catch {
        Show-Error "Restore from file failed: $($_.Exception.Message)"
        $statusLabel.Text = 'Restore from file failed.'
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

#endregion

#region ---------------------------------------------------------------- events

$btnScan.Add_Click({
    $choice = Show-ScanFoldersDialog
    if ($choice) { Invoke-GuiScanRoots -Roots $choice.Roots -IncludeStandard:$choice.IncludeStandard }
})

$btnRescan.Add_Click({
    Rescan-StoredRoots
})

$btnExportDb.Add_Click({
    Invoke-GuiExportDatabase
})

$btnRestoreFile.Add_Click({
    Invoke-GuiRestoreFromFile
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

    # --- where to restore? choose a format (and a folder for "folder" format)
    $format = Read-GuiText 'Restore location' "Restore to:`n  profile    = current Windows profile (default)`n  verbatim   = the original C: layout, exactly as saved`n  folder     = the folder you pick below, keeping <TOKEN>\<path> structure`nType one:" 'profile'
    if (-not $format) { return }

    $restoreRoot = ''
    $restoreFormat = $format.Trim().ToLowerInvariant()

    if ($restoreFormat -eq 'folder') {
        $restoreRoot = Select-Folder 'Choose the folder every save should be copied into'
        if (-not $restoreRoot) { return }
    }

    $restoreWhat = if ($restoreFormat -eq 'profile') { 'your current Windows profile' }
        elseif ($restoreFormat -eq 'verbatim') { 'the original drive layout (verbatim, e.g. back to C:)' }
        elseif ($restoreFormat -eq 'folder') { "the folder:`n$restoreRoot`n(keeps the <TOKEN>\<path> structure)" }
        else { $null }

    if (-not $restoreWhat) {
        Show-Warn "Unknown restore format: $format. Use profile, verbatim or folder."
        return
    }

    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Restore this snapshot?`n`n$($snap.Name)`nEntries: $($snap.EntryCount)`nFiles: $($snap.TotalFiles)`n`nRestore to:`n$restoreWhat`n`nExisting saves are moved to the vault's rollback folder first.",
        'Confirm restore',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -ne 'Yes') { return }

    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $statusLabel.Text = 'Restoring...'
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $r = Restore-GSVSnapshot -BackupRoot $script:Vault -Snapshot $snap.Path -RestoreFormat $restoreFormat -RestoreRoot $restoreRoot
        $msg = "Restore complete.`n`nRestored: $($r.Restored)`nRegistry keys: $($r.Registry)`nSkipped: $($r.Skipped)`nFailed: $($r.Failed)`nFormat: $($r.Format)"
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
    if (Show-RuleEditor) {
        Show-Info "Save rule stored in config\save-rules.json.`n`nIt is included in the next scan / backup, and restore will use it on a new PC."
        Load-Games
    }
})

$btnRules.Add_Click({
    Show-RulesDialog
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
    $scanDb = Read-GSVScanDatabase
    $scanLocs = if ($scanDb) { @(Get-GSVScanDatabaseLocations).Count } else { 0 }
    $lines.Add('Scan database   : ' + $(if ($scanDb) { "$scanLocs locations" } else { 'none' }))
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
    $db = Read-GSVScanDatabase
    if ($db -and @($db.Locations).Count -gt 0) {
        Load-ScanDatabase
    } else {
        $choice = Show-ScanFoldersDialog
        if ($choice) {
            Invoke-GuiScanRoots -Roots $choice.Roots -IncludeStandard:$choice.IncludeStandard
        } else {
            $statusLabel.Text = 'No folders selected. Click "Scan folders..." to choose where to look.'
        }
    }
})

#endregion

if ($SmokeTest) {
    Write-Host ("GUI smoke test OK: form='{0}', controls={1}, columns={2}, vault={3}" -f $form.Text, $form.Controls.Count, $list.Columns.Count, $script:Vault)
    $form.Dispose()
    exit 0
}

[void]$form.ShowDialog()
