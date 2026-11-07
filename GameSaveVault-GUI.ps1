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

# Make the app DPI-aware so it stays crisp on high-DPI displays.
try {
    Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();' -Name DpiAware -Namespace GSV -ErrorAction Stop
    [GSV.DpiAware]::SetProcessDPIAware() | Out-Null
} catch { }

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
$script:AllGames = @()
$script:GameFilter = ''
$script:SortColumn = 0
$script:SortAsc = $true

try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class GsvNative {
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, string lParam);
    public static void SetCue(IntPtr h, string text) { SendMessage(h, 0x1501, (IntPtr)1, text); }
}
"@ -ErrorAction Stop
} catch { }

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
        [void]$cbFrom.Items.Add(("{0} ({1})" -f $def.Name, $def.Console))
    }

    $script:MigrateToDefs = @()
    $populateTo = {
        $cbTo.Items.Clear()
        $script:MigrateToDefs = @()
        if ($cbFrom.SelectedIndex -lt 0) { return }
        $srcDef = $defs[$cbFrom.SelectedIndex]
        $srcFamily = Get-GSVEmulatorFamily -Definition $srcDef
        $same = New-Object System.Collections.Generic.List[object]
        foreach ($d in $defs) {
            if ($d.Id -eq $srcDef.Id) { continue }
            if ((Get-GSVEmulatorFamily -Definition $d) -ne $srcFamily) { continue }
            $same.Add($d)
            [void]$cbTo.Items.Add(("{0} ({1})" -f $d.Name, $d.Console))
        }
        $script:MigrateToDefs = $same.ToArray()
        if ($cbTo.Items.Count -gt 0) { $cbTo.SelectedIndex = 0 }
        if ($btnGo) { $btnGo.Enabled = ($cbTo.Items.Count -gt 0) }
    }

    $cbFrom.Add_SelectedIndexChanged({
        & $populateTo
        $lv.Items.Clear()
        $script:MigrateEntries = @()
    })

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

    # Pick a source, then offer only emulators of the same console as targets.
    if ($cbFrom.Items.Count -gt 0) { $cbFrom.SelectedIndex = 0 }
    & $populateTo

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
        if ($cbTo.SelectedIndex -lt 0 -or $script:MigrateToDefs.Count -eq 0) {
            Show-Warn ("No other {0} emulator is installed to migrate to." -f $srcDef.Console)
            return
        }
        $dstDef = $script:MigrateToDefs[$cbTo.SelectedIndex]
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

#region ---------------------------------------------------------------- helpers (polished UI)

$script:ColorBg        = [System.Drawing.ColorTranslator]::FromHtml('#F3F5F9')
$script:ColorSurface   = [System.Drawing.Color]::White
$script:ColorBorder    = [System.Drawing.ColorTranslator]::FromHtml('#E2E8F0')
$script:ColorText      = [System.Drawing.ColorTranslator]::FromHtml('#0F172A')
$script:ColorMuted     = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$script:ColorAccent    = [System.Drawing.ColorTranslator]::FromHtml('#2563EB')
$script:ColorAccentDk  = [System.Drawing.ColorTranslator]::FromHtml('#1D4ED8')
$script:ColorSuccess   = [System.Drawing.ColorTranslator]::FromHtml('#059669')
$script:ColorSuccessDk = [System.Drawing.ColorTranslator]::FromHtml('#047857')
$script:ColorHeaderBg  = [System.Drawing.ColorTranslator]::FromHtml('#0F172A')
$script:ColorHeaderFg  = [System.Drawing.Color]::White
$script:ColorHeaderSub = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')

$script:AppFont        = New-Object System.Drawing.Font('Segoe UI', 9)
$script:AppFontBold    = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$script:AppFontSmall   = New-Object System.Drawing.Font('Segoe UI', 8)
$script:AppFontStat    = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
$script:Tip            = New-Object System.Windows.Forms.ToolTip
$script:Tip.AutoPopDelay = 10000
$script:Tip.InitialDelay = 400

$script:GameFilter    = ''
$script:SortColumn   = 0
$script:SortAsc      = $true
$script:AllGames     = @()
$script:statGamesVal = $null
$script:statLocsVal  = $null
$script:statSizeVal  = $null
$script:statSelVal   = $null

function New-AppIcon {
    $bmp = New-Object System.Drawing.Bitmap(32, 32, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush($script:ColorAccent)
    $g.FillRectangle($brush, 2, 2, 28, 28)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 3)
    $g.DrawLine($pen, 9, 12, 16, 19)
    $g.DrawLine($pen, 16, 19, 23, 12)
    $g.DrawLine($pen, 16, 19, 16, 7)
    $pen2 = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 3)
    $g.DrawLine($pen2, 8, 24, 24, 24)
    $g.Dispose(); $brush.Dispose(); $pen.Dispose(); $pen2.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

function Set-GuiBusy {
    param([bool]$Busy, [string]$Text)
    if ($Text) { $statusLabel.Text = $Text }
    if ($Busy) {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $progressBar.Visible = $true
        $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
        $progressBar.MarqueeAnimationSpeed = 30
    } else {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $progressBar.Visible = $false
        $progressBar.MarqueeAnimationSpeed = 0
    }
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

function Style-Button {
    param($Button, [string]$Style = 'secondary', [int]$Height = 34)
    $Button.Height = $Height
    $Button.Font = $script:AppFontBold
    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.UseVisualStyleBackColor = $false
    $Button.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    switch ($Style) {
        'primary' {
            $Button.BackColor = $script:ColorAccent
            $Button.ForeColor = [System.Drawing.Color]::White
            $Button.FlatAppearance.BorderSize = 0
            $Button.FlatAppearance.MouseOverBackColor = $script:ColorAccentDk
            $Button.FlatAppearance.MouseDownBackColor = $script:ColorAccentDk
        }
        'success' {
            $Button.BackColor = $script:ColorSuccess
            $Button.ForeColor = [System.Drawing.Color]::White
            $Button.FlatAppearance.BorderSize = 0
            $Button.FlatAppearance.MouseOverBackColor = $script:ColorSuccessDk
            $Button.FlatAppearance.MouseDownBackColor = $script:ColorSuccessDk
        }
        'ghost' {
            $Button.BackColor = [System.Drawing.Color]::Transparent
            $Button.ForeColor = [System.Drawing.Color]::White
            $Button.FlatAppearance.BorderSize = 0
            $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(40,255,255,255)
            $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(60,255,255,255)
        }
        default {
            $Button.BackColor = $script:ColorSurface
            $Button.ForeColor = $script:ColorText
            $Button.FlatAppearance.BorderSize = 1
            $Button.FlatAppearance.BorderColor = $script:ColorBorder
            $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.ColorTranslator]::FromHtml('#F1F5F9')
            $Button.FlatAppearance.MouseDownBackColor = $script:ColorBorder
        }
    }
}

function New-StatCard {
    param([string]$Caption, [ref]$ValueVar)
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $script:ColorSurface
    $p.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $p.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)
    $cap = New-Object System.Windows.Forms.Label
    $cap.Text = $Caption.ToUpper()
    $cap.Font = $script:AppFontSmall
    $cap.ForeColor = $script:ColorMuted
    $cap.AutoSize = $true
    $cap.Location = New-Object System.Drawing.Point(12, 8)
    $val = New-Object System.Windows.Forms.Label
    $val.Text = '0'
    $val.Font = $script:AppFontStat
    $val.ForeColor = $script:ColorText
    $val.AutoSize = $true
    $val.Location = New-Object System.Drawing.Point(10, 26)
    $p.Controls.Add($cap)
    $p.Controls.Add($val)
    $ValueVar.Value = $val
    return $p
}

function Update-GuiStats {
    $games = @($script:AllGames)
    $locs = 0
    $bytes = [int64]0
    foreach ($g in $games) {
        $locs += @($g.Locations).Count
        if ($g.Bytes) { $bytes += [int64]$g.Bytes }
    }
    $checked = @($games | Where-Object { $_.Checked }).Count
    $script:statGamesVal.Text = [string]$games.Count
    $script:statLocsVal.Text = [string]$locs
    $script:statSizeVal.Text = (Format-GSVSize $bytes)
    $script:statSelVal.Text = [string]$checked
    if ($btnBackup) { $btnBackup.Enabled = ($checked -gt 0) }
}

function Update-GameList {
    if (-not $list) { return }
    $games = @($script:AllGames)
    if ($script:GameFilter) {
        $games = @($games | Where-Object {
            ([string]$_.Name -like "*$($script:GameFilter)*") -or
            ([string]$_.Source -like "*$($script:GameFilter)*") -or
            ([string]$_.AppId -like "*$($script:GameFilter)*") -or
            ([string]$_.Preview -like "*$($script:GameFilter)*")
        })
    }

    switch ($script:SortColumn) {
        1 { $games = @($games | Sort-Object Source, Name) }
        2 { $games = @($games | Sort-Object { @($_.Locations).Count }, Name) }
        3 { $games = @($games | Sort-Object Bytes, Name) }
        4 { $games = @($games | Sort-Object Preview, Name) }
        default { $games = @($games | Sort-Object Name) }
    }
    if (-not $script:SortAsc) { [array]::Reverse($games) }

    $list.BeginUpdate()
    $list.Items.Clear()
    $i = 0
    foreach ($g in $games) {
        $item = New-Object System.Windows.Forms.ListViewItem([string]$g.Name)
        [void]$item.SubItems.Add([string]$g.Source)
        [void]$item.SubItems.Add([string]@($g.Locations).Count)
        [void]$item.SubItems.Add((Format-GSVSize ([int64](0 + $g.Bytes))))
        [void]$item.SubItems.Add([string]$g.Preview)
        $item.Tag = $g
        $item.Checked = [bool]$g.Checked
        if ($g.Missing -eq 'all') { $item.ForeColor = $script:ColorMuted }
        $item.BackColor = if ($i % 2 -eq 1) { [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC') } else { $script:ColorSurface }
        $item.ToolTipText = [string]$g.Preview
        [void]$list.Items.Add($item)
        $i++
    }
    $list.EndUpdate()

    if ($emptyPanel) {
        if ($list.Items.Count -eq 0) {
            $emptyPanel.Visible = $true
            $list.Visible = $false
            if (@($script:AllGames).Count -eq 0) {
                $emptyTitle.Text = 'No saves loaded yet'
                $emptyText.Text = 'Choose the folders you want GameSaveVault to search. It only scans the folders you pick, and remembers the result.'
                if ($emptyScanBtn) { $emptyScanBtn.Visible = $true }
                if ($emptyClearBtn) { $emptyClearBtn.Visible = $false }
            } else {
                $emptyTitle.Text = 'No games match this filter'
                $emptyText.Text = 'Try a different search term, or clear the filter.'
                if ($emptyScanBtn) { $emptyScanBtn.Visible = $false }
                if ($emptyClearBtn) { $emptyClearBtn.Visible = $true }
            }
        } else {
            $emptyPanel.Visible = $false
            $list.Visible = $true
        }
    }

    Update-GuiStats
}

function Open-SelectedGameFolder {
    if ($list.SelectedItems.Count -eq 0) { return }
    $g = $list.SelectedItems[0].Tag
    if (-not $g) { return }
    $loc = @($g.Locations | Where-Object { $_.Kind -ne 'Registry' -and $_.ResolvedPath -and (Test-Path -LiteralPath $_.ResolvedPath) } | Select-Object -First 1)
    if ($loc.Count -eq 0) { Show-Warn 'No existing save folder for this entry.'; return }
    $target = if (Test-Path -LiteralPath $loc[0].ResolvedPath -PathType Leaf) { Split-Path -Parent $loc[0].ResolvedPath } else { $loc[0].ResolvedPath }
    Start-Process explorer.exe -ArgumentList ('"' + $target + '"')
}

#endregion

#endregion

#region ---------------------------------------------------------------- form
#region ---------------------------------------------------------------- form

$form = New-Object System.Windows.Forms.Form
$form.Text = 'GameSaveVault - Game Save Backup & Restore'
$form.Size = New-Object System.Drawing.Size(1280, 800)
$form.MinimumSize = New-Object System.Drawing.Size(1040, 640)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Font = $script:AppFont
$form.BackColor = $script:ColorBg
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
try { $form.Icon = New-AppIcon } catch { }

# Root table layout
$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = 'Fill'
$root.ColumnCount = 1
$root.RowCount = 6
$root.BackColor = $script:ColorBg
$root.Padding = New-Object System.Windows.Forms.Padding(0)
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 64)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 96)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

# Header panel
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Fill'
$header.BackColor = $script:ColorHeaderBg
$iconBox = New-Object System.Windows.Forms.PictureBox
$iconBox.Size = New-Object System.Drawing.Size(36, 36)
$iconBox.Location = New-Object System.Drawing.Point(18, 14)
$iconBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
try { $iconBox.Image = (New-AppIcon).ToBitmap() } catch { }
$header.Controls.Add($iconBox)
$titleLbl = New-Object System.Windows.Forms.Label
$titleLbl.Text = 'GameSaveVault'
$titleLbl.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$titleLbl.ForeColor = $script:ColorHeaderFg
$titleLbl.AutoSize = $true
$titleLbl.Location = New-Object System.Drawing.Point(62, 10)
$header.Controls.Add($titleLbl)
$subLbl = New-Object System.Windows.Forms.Label
$subLbl.Text = 'Back up and restore your PC game saves'
$subLbl.Font = $script:AppFont
$subLbl.ForeColor = $script:ColorHeaderSub
$subLbl.AutoSize = $true
$subLbl.Location = New-Object System.Drawing.Point(64, 36)
$header.Controls.Add($subLbl)
$verLbl = New-Object System.Windows.Forms.Label
$verLbl.Text = ('v{0}' -f (Get-GSVVersion))
$verLbl.Font = $script:AppFontSmall
$verLbl.ForeColor = $script:ColorHeaderSub
$verLbl.AutoSize = $true
$verLbl.Location = New-Object System.Drawing.Point(210, 38)
$header.Controls.Add($verLbl)
$headerActions = New-Object System.Windows.Forms.FlowLayoutPanel
$headerActions.Dock = 'Right'
$headerActions.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
$headerActions.WrapContents = $false
$headerActions.AutoSize = $true
$headerActions.Padding = New-Object System.Windows.Forms.Padding(0, 14, 14, 0)
$header.Controls.Add($headerActions)

# Menu strip
$menu = New-Object System.Windows.Forms.MenuStrip
$menu.BackColor = $script:ColorSurface
$menu.RenderMode = [System.Windows.Forms.ToolStripRenderMode]::System
$menu.Font = $script:AppFont
$menu.Dock = 'Fill'

function New-Menu {
    param([string]$Text)
    $m = New-Object System.Windows.Forms.ToolStripMenuItem $Text
    [void]$menu.Items.Add($m)
    return $m
}
function Add-MenuItem {
    param($Parent, [string]$Text, $Button, [string]$Shortcut = '', [switch]$Separator)
    if ($Separator) { [void]$Parent.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator)) ; return }
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem $Text
    $mi.Tag = $Button
    $mi.Add_Click({ if ($this.Tag) { $this.Tag.PerformClick() } })
    if ($Shortcut) {
        try {
            $kc = New-Object System.Windows.Forms.KeysConverter
            $mi.ShortcutKeys = [System.Windows.Forms.Keys]$kc.ConvertFromString($Shortcut)
            $mi.ShowShortcutKeys = $true
        } catch { }
    }
    [void]$Parent.DropDownItems.Add($mi)
    return $mi
}

$mFile = New-Menu 'File'
$mScan = New-Menu 'Scan'
$mEmu  = New-Menu 'Emulators'
$mGames = New-Menu 'Games'
$mHelp = New-Menu 'Help'

# Action bar
$actions = New-Object System.Windows.Forms.Panel
$actions.Dock = 'Fill'
$actions.BackColor = $script:ColorSurface
$actions.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)
$actions.Add_Paint({
    param($s,$e)
    $pen = New-Object System.Drawing.Pen($script:ColorBorder)
    $e.Graphics.DrawLine($pen, 0, $s.Height - 1, $s.Width, $s.Height - 1)
    $pen.Dispose()
})

$actionGrid = New-Object System.Windows.Forms.TableLayoutPanel
$actionGrid.Dock = 'Fill'
$actionGrid.ColumnCount = 2
$actionGrid.RowCount = 1
$actionGrid.BackColor = $script:ColorSurface
[void]$actionGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$actionGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$actionGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 320)))
$actions.Controls.Add($actionGrid)

$leftActions = New-Object System.Windows.Forms.FlowLayoutPanel
$leftActions.Dock = 'Fill'
$leftActions.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$leftActions.WrapContents = $false
$leftActions.AutoScroll = $false
$leftActions.Padding = New-Object System.Windows.Forms.Padding(0)
$actionGrid.Controls.Add($leftActions, 0, 0)

$rightActions = New-Object System.Windows.Forms.FlowLayoutPanel
$rightActions.Dock = 'Fill'
$rightActions.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
$rightActions.WrapContents = $false
$rightActions.Padding = New-Object System.Windows.Forms.Padding(0)
$actionGrid.Controls.Add($rightActions, 1, 0)

# Buttons
$btnScan     = New-Object System.Windows.Forms.Button
$btnScan.Text = 'Scan folders...'
$btnRescan   = New-Object System.Windows.Forms.Button
$btnRescan.Text = 'Rescan'
$btnBackup   = New-Object System.Windows.Forms.Button
$btnBackup.Text = 'Backup selected'
$btnBackupAll = New-Object System.Windows.Forms.Button
$btnBackupAll.Text = 'Backup all'
$btnRestore  = New-Object System.Windows.Forms.Button
$btnRestore.Text = 'Restore...'
$btnRestoreFile = New-Object System.Windows.Forms.Button
$btnRestoreFile.Text = 'Restore file...'
$btnExportDb = New-Object System.Windows.Forms.Button
$btnExportDb.Text = 'Export DB...'
$btnOld      = New-Object System.Windows.Forms.Button
$btnOld.Text = 'Windows.old...'
$btnDeep     = New-Object System.Windows.Forms.Button
$btnDeep.Text = 'Deep scan...'
$btnMigrate  = New-Object System.Windows.Forms.Button
$btnMigrate.Text = 'Migrate...'
$btnAdd      = New-Object System.Windows.Forms.Button
$btnAdd.Text = 'Add game...'
$btnRules    = New-Object System.Windows.Forms.Button
$btnRules.Text = 'Save rules...'
$btnVault    = New-Object System.Windows.Forms.Button
$btnVault.Text = 'Open vault'
$btnVaultLoc = New-Object System.Windows.Forms.Button
$btnVaultLoc.Text = 'Backup location...'
$btnDoctor   = New-Object System.Windows.Forms.Button
$btnDoctor.Text = 'Doctor'
$btnSelectAll = New-Object System.Windows.Forms.Button
$btnSelectAll.Text = 'Select all'
$btnSelectNone = New-Object System.Windows.Forms.Button
$btnSelectNone.Text = 'Clear'
$btnClearFilter = New-Object System.Windows.Forms.Button
$btnClearFilter.Text = 'x'

foreach ($b in @($btnScan,$btnRescan,$btnBackup,$btnBackupAll,$btnRestore,$btnRestoreFile,$btnDeep,$btnVault,$btnVaultLoc)) {
    $b.Width = 120; $b.Height = 34
}
$btnScan.Width = 132; $btnBackup.Width = 140; $btnRestoreFile.Width = 118; $btnVaultLoc.Width = 150
Style-Button $btnScan 'primary'
Style-Button $btnBackup 'success'
foreach ($b in @($btnRescan,$btnBackupAll,$btnRestore,$btnRestoreFile,$btnDeep,$btnVault,$btnVaultLoc)) { Style-Button $b 'secondary' }

# Ghost header buttons
Style-Button $btnVault 'ghost' 30
Style-Button $btnVaultLoc 'ghost' 30
$btnVault.Height = 30; $btnVaultLoc.Height = 30
$btnVault.Width = 96; $btnVaultLoc.Width = 120
$headerActions.Controls.Add($btnVaultLoc)
$headerActions.Controls.Add($btnVault)

# Left action bar
$leftActions.Controls.Add($btnScan)
$sep1 = New-Object System.Windows.Forms.Panel
$sep1.Size = New-Object System.Drawing.Size(1, 26)
$sep1.BackColor = $script:ColorBorder
$sep1.Margin = New-Object System.Windows.Forms.Padding(4, 4, 12, 4)
$leftActions.Controls.Add($sep1)
$leftActions.Controls.Add($btnBackup)
$leftActions.Controls.Add($btnBackupAll)
$sep2 = New-Object System.Windows.Forms.Panel
$sep2.Size = New-Object System.Drawing.Size(1, 26)
$sep2.BackColor = $script:ColorBorder
$sep2.Margin = New-Object System.Windows.Forms.Padding(4, 4, 12, 4)
$leftActions.Controls.Add($sep2)
$leftActions.Controls.Add($btnRescan)
$leftActions.Controls.Add($btnRestore)
$leftActions.Controls.Add($btnRestoreFile)
$leftActions.Controls.Add($btnDeep)

# Right action bar: filter
$lblFilter = New-Object System.Windows.Forms.Label
$lblFilter.Text = 'Filter'
$lblFilter.Font = $script:AppFontSmall
$lblFilter.ForeColor = $script:ColorMuted
$lblFilter.AutoSize = $true
$lblFilter.Margin = New-Object System.Windows.Forms.Padding(0, 10, 6, 0)
$rightActions.Controls.Add($lblFilter)
$txtFilter = New-Object System.Windows.Forms.TextBox
$txtFilter.Width = 180
$txtFilter.Height = 26
$txtFilter.Font = $script:AppFont
$txtFilter.Margin = New-Object System.Windows.Forms.Padding(0, 4, 6, 0)
$rightActions.Controls.Add($txtFilter)
$btnClearFilter.Width = 26; $btnClearFilter.Height = 26
Style-Button $btnClearFilter 'secondary' 26
$btnClearFilter.Text = 'x'
$btnClearFilter.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
$rightActions.Controls.Add($btnClearFilter)
$btnSelectAll.Width = 74; $btnSelectAll.Height = 26
Style-Button $btnSelectAll 'secondary' 26
$btnSelectAll.Margin = New-Object System.Windows.Forms.Padding(12, 4, 4, 0)
$rightActions.Controls.Add($btnSelectAll)
$btnSelectNone.Width = 62; $btnSelectNone.Height = 26
Style-Button $btnSelectNone 'secondary' 26
$btnSelectNone.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
$rightActions.Controls.Add($btnSelectNone)

# Stats row
$stats = New-Object System.Windows.Forms.TableLayoutPanel
$stats.Dock = 'Fill'
$stats.ColumnCount = 4
$stats.RowCount = 1
$stats.BackColor = $script:ColorBg
$stats.Padding = New-Object System.Windows.Forms.Padding(12, 0, 12, 8)
for ($c = 0; $c -lt 4; $c++) {
    [void]$stats.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
}
[void]$stats.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$statGamesCard = New-StatCard 'Games' ([ref]$script:statGamesVal)
$statLocsCard  = New-StatCard 'Save locations' ([ref]$script:statLocsVal)
$statSizeCard  = New-StatCard 'Total size' ([ref]$script:statSizeVal)
$statSelCard   = New-StatCard 'Selected' ([ref]$script:statSelVal)
foreach ($card in @($statGamesCard,$statLocsCard,$statSizeCard,$statSelCard)) {
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
}
$statSelCard.Margin = New-Object System.Windows.Forms.Padding(0)
$stats.Controls.Add($statGamesCard, 0, 0)
$stats.Controls.Add($statLocsCard, 1, 0)
$stats.Controls.Add($statSizeCard, 2, 0)
$stats.Controls.Add($statSelCard, 3, 0)

# Content panel (list + empty state)
$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
$content.BackColor = $script:ColorBg
$content.Padding = New-Object System.Windows.Forms.Padding(12, 0, 12, 12)

$list = New-Object System.Windows.Forms.ListView
$list.Dock = 'Fill'
$list.View = [System.Windows.Forms.View]::Details
$list.CheckBoxes = $true
$list.FullRowSelect = $true
$list.GridLines = $false
$list.HideSelection = $false
$list.MultiSelect = $true
$list.Font = $script:AppFont
$list.BackColor = $script:ColorSurface
$list.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$list.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Clickable
$list.ShowItemToolTips = $true
$rowIcons = New-Object System.Windows.Forms.ImageList
$rowIcons.ImageSize = New-Object System.Drawing.Size(1, 22)
$rowIcons.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit
$rowIcons.Images.Add((New-Object System.Drawing.Bitmap(1, 22)))
$list.SmallImageList = $rowIcons

[void]$list.Columns.Add('Game', 300)
[void]$list.Columns.Add('Source', 90)
[void]$list.Columns.Add('Saves', 70, [System.Windows.Forms.HorizontalAlignment]::Center)
[void]$list.Columns.Add('Size', 90, [System.Windows.Forms.HorizontalAlignment]::Right)
[void]$list.Columns.Add('Save folders (first 3)', 420)

# Empty state panel
$emptyPanel = New-Object System.Windows.Forms.Panel
$emptyPanel.Dock = 'Fill'
$emptyPanel.BackColor = $script:ColorSurface
$emptyPanel.Visible = $false
$emptyInner = New-Object System.Windows.Forms.TableLayoutPanel
$emptyInner.Dock = 'Fill'
$emptyInner.ColumnCount = 1
$emptyInner.RowCount = 5
$emptyInner.BackColor = $script:ColorSurface
[void]$emptyInner.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 35)))
[void]$emptyInner.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$emptyInner.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$emptyInner.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$emptyInner.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 65)))
[void]$emptyInner.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$emptyTitle = New-Object System.Windows.Forms.Label
$emptyTitle.Text = 'No saves loaded yet'
$emptyTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
$emptyTitle.ForeColor = $script:ColorText
$emptyTitle.AutoSize = $true
$emptyTitle.Anchor = [System.Windows.Forms.AnchorStyles]::None
$emptyTitle.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
$emptyInner.Controls.Add($emptyTitle, 0, 1)
$emptyText = New-Object System.Windows.Forms.Label
$emptyText.Text = 'Choose the folders you want GameSaveVault to search.'
$emptyText.Font = $script:AppFont
$emptyText.ForeColor = $script:ColorMuted
$emptyText.AutoSize = $true
$emptyText.Anchor = [System.Windows.Forms.AnchorStyles]::None
$emptyText.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 16)
$emptyInner.Controls.Add($emptyText, 0, 2)
$emptyBtns = New-Object System.Windows.Forms.FlowLayoutPanel
$emptyBtns.AutoSize = $true
$emptyBtns.Anchor = [System.Windows.Forms.AnchorStyles]::None
$emptyBtns.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$emptyInner.Controls.Add($emptyBtns, 0, 3)
$emptyScanBtn = New-Object System.Windows.Forms.Button
$emptyScanBtn.Text = 'Scan folders...'
$emptyScanBtn.Width = 140; $emptyScanBtn.Height = 36
Style-Button $emptyScanBtn 'primary' 36
$emptyBtns.Controls.Add($emptyScanBtn)
$emptyClearBtn = New-Object System.Windows.Forms.Button
$emptyClearBtn.Text = 'Clear filter'
$emptyClearBtn.Width = 110; $emptyClearBtn.Height = 36
Style-Button $emptyClearBtn 'secondary' 36
$emptyClearBtn.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
$emptyClearBtn.Visible = $false
$emptyBtns.Controls.Add($emptyClearBtn)
$emptyPanel.Controls.Add($emptyInner)
$content.Controls.Add($emptyPanel)
$content.Controls.Add($list)

# Status strip
$status = New-Object System.Windows.Forms.StatusStrip
$status.BackColor = $script:ColorSurface
$status.Dock = 'Fill'
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Ready'
$statusLabel.Spring = $true
$statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$statusLabel.ForeColor = $script:ColorText
$progressBar = New-Object System.Windows.Forms.ToolStripProgressBar
$progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
$progressBar.Visible = $false
$progressBar.Width = 120
$vaultLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$vaultLabel.Text = 'Vault: ' + $script:Vault
$vaultLabel.ForeColor = $script:ColorMuted
[void]$status.Items.Add($statusLabel)
[void]$status.Items.Add($progressBar)
$vaultLabel.Add_Click({ $btnVault.PerformClick() })

# Assemble
$root.Controls.Add($header, 0, 0)
$root.Controls.Add($menu, 0, 1)
$root.Controls.Add($actions, 0, 2)
$root.Controls.Add($stats, 0, 3)
$root.Controls.Add($content, 0, 4)
$root.Controls.Add($status, 0, 5)
$form.Controls.Add($root)

# Context menu for the list
$ctx = New-Object System.Windows.Forms.ContextMenuStrip
$ctxmiOpen = New-Object System.Windows.Forms.ToolStripMenuItem 'Open save folder'
$ctxmiBackup = New-Object System.Windows.Forms.ToolStripMenuItem 'Back up this game'
$ctxmiCopy = New-Object System.Windows.Forms.ToolStripMenuItem 'Copy save path'
[void]$ctx.Items.Add($ctxmiOpen)
[void]$ctx.Items.Add($ctxmiBackup)
[void]$ctx.Items.Add($ctxmiCopy)
[void]$ctx.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$ctxmiSelAll = New-Object System.Windows.Forms.ToolStripMenuItem 'Select all'
$ctxmiClear = New-Object System.Windows.Forms.ToolStripMenuItem 'Clear selection'
[void]$ctx.Items.Add($ctxmiSelAll)
[void]$ctx.Items.Add($ctxmiClear)
$list.ContextMenuStrip = $ctx

#endregion

#region ---------------------------------------------------------------- data

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
    Set-GuiBusy -Busy $true -Text 'Loading stored scan database...'

    try {
        $db = Read-GSVScanDatabase
        $locs = @(Get-GSVScanDatabaseLocations)
        $script:Games = @()
        $script:Global = @()
        $script:Emulators = @()

        if (-not $db -or $locs.Count -eq 0) {
            $script:AllGames = @()
            Update-GameList
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

            $missing = @($groupLocs | Where-Object { -not $_.Exists })
            $checked = ($missing.Count -lt $groupLocs.Count)

            $game = [pscustomobject]@{
                Name      = [string]$first.GameName
                Source    = [string]$first.Source
                AppId     = [string]$first.AppId
                Locations = $groupLocs
                Files     = $files
                Bytes     = $bytes
                Preview   = $preview
                Missing   = if ($missing.Count -eq $groupLocs.Count) { 'all' } else { '' }
                Checked   = $checked
            }
            $games.Add($game)
        }

        $script:Games = $games.ToArray()
        $script:AllGames = $script:Games

        $updated = if ($db.UpdatedUtc) { ([datetime]$db.UpdatedUtc).ToLocalTime().ToString('yyyy-MM-dd HH:mm') } else { 'unknown' }
        Update-GameList
        $statusLabel.Text = ('{0} games, {1} save locations from scan database (updated {2}). Vault: {3}' -f $script:Games.Count, $locs.Count, $updated, $script:Vault)
    } catch {
        Show-Error "Could not load the scan database: $($_.Exception.Message)"
        $statusLabel.Text = 'Could not load the scan database.'
    } finally {
        Set-GuiBusy -Busy $false -Text ''
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

    Set-GuiBusy -Busy $true -Text ('Scanning {0} folder(s)...' -f $roots.Count)

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
        Set-GuiBusy -Busy $false -Text ''
    }
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

    Set-GuiBusy -Busy $true -Text ('Backing up {0} save locations...' -f $Locations.Count)

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
        Set-GuiBusy -Busy $false -Text ''
    }
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
    $g = $item.Tag
    if ($g) {
        if ($_.NewValue -eq [System.Windows.Forms.CheckState]::Checked -and @($g.Locations).Count -eq 0) {
            $_.NewValue = [System.Windows.Forms.CheckState]::Unchecked
        } else {
            $g.Checked = ($_.NewValue -eq [System.Windows.Forms.CheckState]::Checked)
            Update-GuiStats
        }
    }
})

# --- polished UI wiring -----------------------------------------------------
$btnSelectAll.Add_Click({
    foreach ($item in $list.Items) { $item.Checked = $true; if ($item.Tag) { $item.Tag.Checked = $true } }
    Update-GuiStats
})
$btnSelectNone.Add_Click({
    foreach ($item in $list.Items) { $item.Checked = $false; if ($item.Tag) { $item.Tag.Checked = $false } }
    Update-GuiStats
})
$btnClearFilter.Add_Click({ $txtFilter.Text = '' })
$txtFilter.Add_TextChanged({
    $script:GameFilter = $txtFilter.Text
    Update-GameList
})
$list.Add_ColumnClick({
    param($s, $e)
    if ($script:SortColumn -eq $e.Column) { $script:SortAsc = -not $script:SortAsc } else { $script:SortColumn = $e.Column; $script:SortAsc = $true }
    Update-GameList
})
$emptyScanBtn.Add_Click({ $btnScan.PerformClick() })
$emptyClearBtn.Add_Click({ $txtFilter.Text = '' })

# context menu
$ctxmiOpen.Add_Click({ Open-SelectedGameFolder })
$ctxmiBackup.Add_Click({
    if ($list.SelectedItems.Count -eq 0) { return }
    $g = $list.SelectedItems[0].Tag
    if ($g) { Invoke-GuiBackup -Locations @($g.Locations) -Label 'gui-context' }
})
$ctxmiCopy.Add_Click({
    if ($list.SelectedItems.Count -eq 0) { return }
    $g = $list.SelectedItems[0].Tag
    if ($g) {
        $paths = @($g.Locations | Where-Object { $_.ResolvedPath } | ForEach-Object { $_.ResolvedPath }) -join "`r`n"
        if ($paths) { [System.Windows.Forms.Clipboard]::SetText($paths) }
    }
})
$ctxmiSelAll.Add_Click({ $btnSelectAll.PerformClick() })
$ctxmiClear.Add_Click({ $btnSelectNone.PerformClick() })

# menu items
Add-MenuItem $mFile 'Backup selected' $btnBackup 'Ctrl+B'
Add-MenuItem $mFile 'Backup all' $btnBackupAll 'Ctrl+Shift+B'
Add-MenuItem $mFile 'Restore snapshot...' $btnRestore 'Ctrl+R'
Add-MenuItem $mFile 'Restore from file...' $btnRestoreFile 'Ctrl+O'
Add-MenuItem $mFile 'Export database...' $btnExportDb 'Ctrl+E'
Add-MenuItem $mFile '' $null -Separator
Add-MenuItem $mFile 'Backup location...' $btnVaultLoc
Add-MenuItem $mFile 'Open vault' $btnVault 'Ctrl+Shift+O'
Add-MenuItem $mFile '' $null -Separator
$miExit = New-Object System.Windows.Forms.ToolStripMenuItem 'Exit'
$miExit.Add_Click({ $form.Close() })
[void]$mFile.DropDownItems.Add($miExit)

Add-MenuItem $mScan 'Scan folders...' $btnScan 'Ctrl+N'
Add-MenuItem $mScan 'Rescan' $btnRescan 'F5'
Add-MenuItem $mScan 'Deep scan...' $btnDeep 'Ctrl+D'
Add-MenuItem $mScan 'Windows.old recovery...' $btnOld
Add-MenuItem $mEmu 'Migrate console saves...' $btnMigrate
Add-MenuItem $mGames 'Add custom game...' $btnAdd
Add-MenuItem $mGames 'Save rules...' $btnRules
Add-MenuItem $mGames '' $null -Separator
$miFind = New-Object System.Windows.Forms.ToolStripMenuItem 'Find / filter'
$miFind.ShortcutKeys = [System.Windows.Forms.Keys]::Control -bor [System.Windows.Forms.Keys]::F
$miFind.Add_Click({ $txtFilter.Focus() })
[void]$mGames.DropDownItems.Add($miFind)
Add-MenuItem $mGames 'Select all' $btnSelectAll 'Ctrl+A'
Add-MenuItem $mGames 'Clear selection' $btnSelectNone

Add-MenuItem $mHelp 'Diagnostics (Doctor)' $btnDoctor
$miAbout = New-Object System.Windows.Forms.ToolStripMenuItem 'About'
$miAbout.Add_Click({
    $msg = "GameSaveVault`r`nVersion {0}`r`n`r`nBack up and restore PC game saves across Windows reinstalls.`r`n`r`nRepository:`r`nhttps://github.com/MISTERNEGATIVE21/GameSaveVault" -f (Get-GSVVersion)
    Show-Info $msg 'About GameSaveVault'
})
[void]$mHelp.DropDownItems.Add($miAbout)

# cue banner for the filter box
$form.Add_Shown({
    try { [GsvNative]::SetCue($txtFilter.Handle, 'Filter games...') } catch { }
})

# resize: keep the path column filling remaining width
$list.Add_Resize({
    if ($list.Columns.Count -lt 5) { return }
    $fixed = 300 + 90 + 70 + 90
    $w = $list.ClientSize.Width - $fixed - 4
    if ($w -lt 200) { $w = 200 }
    $list.Columns[4].Width = $w
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
