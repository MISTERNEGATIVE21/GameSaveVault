<#
.SYNOPSIS
    GameSaveVault - back up and restore PC game saves (including repack / Steam-emu
    saves) so they survive a Windows reinstall.

.EXAMPLES
    .\GameSaveVault.ps1 scan
    .\GameSaveVault.ps1 scan -Detailed
    .\GameSaveVault.ps1 backup -All
    .\GameSaveVault.ps1 backup -Game Skyrim,Palworld
    .\GameSaveVault.ps1 snapshots
    .\GameSaveVault.ps1 restore -Snapshot latest -DryRun
    .\GameSaveVault.ps1 restore -Snapshot latest
    .\GameSaveVault.ps1 from-old -DryRun
    .\GameSaveVault.ps1 from-old
    .\GameSaveVault.ps1 add "My Game" -Paths "%DOCUMENTS%\MyGame\Saves"
    .\GameSaveVault.ps1 doctor
    .\GameSaveVault.ps1 gui
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'scan',

    [Parameter(Position = 1)]
    [string]$Target,

    [string]$BackupRoot,

    [string[]]$Game = @(),

    [string]$Snapshot = 'latest',

    [string]$WindowsOldRoot,

    [string[]]$Paths = @(),

    [string[]]$Registry = @(),

    [string[]]$Drive = @(),

    [int]$MaxDepth = 10,

    [int]$MaxResults = 500,

    [string]$Label = '',

    [int]$Keep = 0,

    [switch]$All,
    [switch]$Detailed,
    [switch]$DryRun,
    [switch]$WhatIf,
    [switch]$Hash,
    [switch]$SkipRegistry,
    [switch]$KeepExisting,
    [switch]$NoGlobal,
    [switch]$NoRestore,
    [switch]$AllDrives,
    [switch]$Backup,
    [switch]$NoSize,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$script:Root = $PSScriptRoot

try {
    Import-Module (Join-Path $script:Root 'modules\GSV.Core.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $script:Root 'modules\GSV.Vault.psm1') -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to load GameSaveVault modules: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$isDryRun = [bool]($DryRun -or $WhatIf)
$settings = Get-GSVSettings
if (-not (Test-Path -LiteralPath (Join-Path $script:Root 'config\settings.json'))) {
    try { Save-GSVSettings -Settings $settings } catch { }
}
$vault = if ($BackupRoot) { $BackupRoot } else { $settings.BackupRoot }
$logDir = Join-Path $vault 'logs'
$logFile = Join-Path $logDir ('gsv-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))

function Write-Title {
    param([string]$Text)
    if ($Quiet) { return }
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('-' * $Text.Length) -ForegroundColor DarkCyan
}

function Write-Kv {
    param([string]$Key, [object]$Value, [string]$Color = 'Gray')
    Write-Host ('  {0,-22} {1}' -f $Key, $Value) -ForegroundColor $Color
}

function Select-GSVGamesByFilter {
    param(
        [object[]]$Games,
        [string[]]$Filter
    )
    if (-not $Filter -or $Filter.Count -eq 0) { return @($Games) }
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($g in $Games) {
        $hit = $false
        foreach ($f in $Filter) {
            if (-not $f) { continue }
            if ($g.Name -and $g.Name.IndexOf($f, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true; break }
            if ($g.Id -and $g.Id.IndexOf($f, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true; break }
            if (Test-GSVNameSimilar -A $g.Name -B $f) { $hit = $true; break }
        }
        if ($hit) { $result.Add($g) }
    }
    return $result.ToArray()
}

function Show-Scan {
    Write-Title 'Installed games'
    $games = @(Get-GSVAllGames -Settings $settings)

    if ($games.Count -eq 0) {
        Write-Host '  No installed games detected.' -ForegroundColor Yellow
        Write-Host '  Add your game folders to GameScanRoots in config\settings.json,' -ForegroundColor DarkGray
        Write-Host '  or register a save path manually:  .\GameSaveVault.ps1 add "Game" -Paths "..."' -ForegroundColor DarkGray
    } else {
        $rows = foreach ($g in $games) {
            $locs = @($g.Locations)
            $files = 0; $bytes = [int64]0
            foreach ($l in $locs) { $files += [int](0 + $l.FileCount); $bytes += [int64](0 + $l.Bytes) }
            [pscustomobject]@{
                Game    = $g.Name
                Source  = $g.Source
                SaveLocs = $locs.Count
                Files   = $files
                Size    = Format-GSVSize $bytes
                Paths   = ($locs | Where-Object { $_.Kind -ne 'Registry' } | Select-Object -First 1).ResolvedPath
            }
        }
        $rows | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Host

        if ($Detailed) {
            foreach ($g in $games) {
                Write-Host ''
                Write-Host ("  {0}  [{1}]" -f $g.Name, $g.Source) -ForegroundColor White
                if ($g.GameDir) { Write-Host ("    install: {0}" -f $g.GameDir) -ForegroundColor DarkGray }
                foreach ($l in @($g.Locations)) {
                    $kind = if ($l.Kind -eq 'Registry') { 'REG ' } else { 'FILE' }
                    if ($l.Kind -eq 'Directory') { $kind = 'DIR ' }
                    $p = if ($l.Kind -eq 'Registry') { $l.RegistryKey } else { $l.ResolvedPath }
                    Write-Host ("    {0} {1}" -f $kind, $p) -ForegroundColor Gray
                    Write-Host ("         {0} | {1} files | {2}" -f $l.Note, $l.FileCount, (Format-GSVSize $l.Bytes)) -ForegroundColor DarkGray
                }
            }
        }
    }

    $global = @(Get-GSVGlobalSaveLocations -Settings $settings -NoSize)
    if ($global.Count -gt 0) {
        Write-Host ''
        Write-Host ("  Global launcher / emulator saves: {0} folders" -f $global.Count) -ForegroundColor DarkYellow
        foreach ($l in $global) { Write-Host ("    DIR  {0}   ({1})" -f $l.ResolvedPath, $l.Note) -ForegroundColor DarkGray }
    }

    Write-Host ''
    Write-Kv 'Vault location' $vault 'Yellow'
    Write-Kv 'Games detected' $games.Count
    if ($vault -and $env:SystemDrive -and $vault.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host '  WARNING: the vault is on the system drive. A clean Windows install can erase it.' -ForegroundColor Red
        Write-Host '           Move it to another drive:  .\GameSaveVault.ps1 backup -BackupRoot D:\GameSaveVault' -ForegroundColor DarkYellow
    }
}

function Invoke-Backup {
    Write-Title 'Backup game saves'

    $games = @(Get-GSVAllGames -Settings $settings)
    $selected = @(Select-GSVGamesByFilter -Games $games -Filter $Game)

    if ($Game.Count -gt 0 -and $selected.Count -eq 0) {
        throw "No installed game matched: $($Game -join ', ')"
    }
    if ($selected.Count -eq 0 -and $NoGlobal) {
        throw 'No games detected and -NoGlobal was specified. Nothing to back up.'
    }

    $locations = New-Object System.Collections.Generic.List[object]
    foreach ($g in $selected) {
        foreach ($l in @($g.Locations)) { $locations.Add($l) }
    }

    if (-not $NoGlobal) {
        foreach ($l in @(Get-GSVGlobalSaveLocations -Settings $settings)) { $locations.Add($l) }
    }

    # De-duplicate identical paths across games (e.g. shared Ubisoft folder).
    $seen = @{}
    $unique = New-Object System.Collections.Generic.List[object]
    foreach ($l in $locations) {
        if ($l.Kind -eq 'Registry') {
            $key = 'reg|' + [string]$l.RegistryKey
        } else {
            $key = 'path|' + ([string]$l.ResolvedPath).ToLowerInvariant()
        }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $unique.Add($l)
    }

    if ($unique.Count -eq 0) { throw 'Nothing to back up.' }

    if (-not $Quiet) {
        Write-Kv 'Games selected' $selected.Count
        Write-Kv 'Save locations' $unique.Count
        Write-Kv 'Vault' $vault 'Yellow'
        if ($isDryRun) { Write-Host '  DRY RUN - no files will be written.' -ForegroundColor Yellow }
    }

    if (-not (Test-Path -LiteralPath $vault) -and -not $isDryRun) {
        New-Item -ItemType Directory -Path $vault -Force | Out-Null
    }

    $label = if ($Label) { $Label } else { 'manual' }
    $result = New-GSVSnapshot -Locations $unique.ToArray() -BackupRoot $vault -Label $label -HashFiles:$Hash -DryRun:$isDryRun -LogFile $logFile

    Write-Host ''
    Write-Kv 'Snapshot' $result.SnapshotPath 'Green'
    Write-Kv 'Entries' $result.EntryCount
    Write-Kv 'Files' $result.TotalFiles
    Write-Kv 'Size' (Format-GSVSize $result.TotalBytes)
    if (@($result.Errors).Count -gt 0) {
        Write-Host ("  {0} item(s) had problems (see log)." -f @($result.Errors).Count) -ForegroundColor Yellow
    }

    if (-not $isDryRun) {
        $keep = if ($Keep -gt 0) { $Keep } else { [int]$settings.KeepSnapshots }
        if ($keep -gt 0) { $null = Remove-GSVOldSnapshots -BackupRoot $vault -Keep $keep }
    }
}

function Invoke-Restore {
    Write-Title 'Restore game saves'
    if (-not (Test-Path -LiteralPath $vault)) { throw "Vault not found: $vault" }
    if ($isDryRun) { Write-Host '  DRY RUN - nothing will be changed.' -ForegroundColor Yellow }

    $result = Restore-GSVSnapshot -BackupRoot $vault -Snapshot $Snapshot -GameFilter $Game `
        -DryRun:$isDryRun -SkipRegistry:$SkipRegistry -KeepExisting:$KeepExisting -LogFile $logFile

    Write-Host ''
    Write-Kv 'Snapshot' $result.SnapshotPath 'Green'
    Write-Kv 'Restored' $result.Restored
    Write-Kv 'Registry keys' $result.Registry
    Write-Kv 'Skipped' $result.Skipped
    Write-Kv 'Failed' $result.Failed ($(if ($result.Failed -gt 0) { 'Red' } else { 'Gray' }))
    Write-Kv 'Size' (Format-GSVSize $result.Bytes)

    if (@($result.Messages).Count -gt 0) {
        Write-Host ''
        foreach ($m in @($result.Messages)) { Write-Host "  - $m" -ForegroundColor DarkYellow }
    }
}

function Invoke-FromOld {
    Write-Title 'Recover saves from Windows.old'
    if ($isDryRun) { Write-Host '  DRY RUN - nothing will be changed.' -ForegroundColor Yellow }

    $result = Import-GSVFromWindowsOld -BackupRoot $vault -WindowsOldRoot $WindowsOldRoot `
        -GameFilter $Game -DryRun:$isDryRun -NoRestore:$NoRestore -Label 'windows-old'

    Write-Host ''
    Write-Kv 'Locations found' $result.Locations
    if ($result.Snapshot) {
        Write-Kv 'Snapshot' $result.Snapshot.SnapshotPath 'Green'
        Write-Kv 'Files' $result.Snapshot.TotalFiles
        Write-Kv 'Size' (Format-GSVSize $result.Snapshot.TotalBytes)
    }
    if ($result.Restore) {
        Write-Kv 'Restored' $result.Restore.Restored
        Write-Kv 'Skipped' $result.Restore.Skipped
        Write-Kv 'Failed' $result.Restore.Failed
    } elseif ($NoRestore) {
        Write-Host '  Imported into the vault only (-NoRestore).' -ForegroundColor DarkGray
    }
}

function Show-Snapshots {
    Write-Title 'Snapshots'
    $snaps = @(Get-GSVSnapshots -BackupRoot $vault)
    if ($snaps.Count -eq 0) {
        Write-Host '  No snapshots yet. Run:  .\GameSaveVault.ps1 backup -All' -ForegroundColor Yellow
        return
    }
    $snaps |
        Select-Object @{ n = 'Created'; e = { ([datetime]$_.CreatedUtc).ToLocalTime().ToString('yyyy-MM-dd HH:mm') } },
                      Label,
                      @{ n = 'Entries'; e = { $_.EntryCount } },
                      @{ n = 'Files'; e = { $_.TotalFiles } },
                      @{ n = 'Size'; e = { Format-GSVSize $_.TotalBytes } },
                      @{ n = 'Errors'; e = { $_.Errors } },
                      Name |
        Format-Table -AutoSize | Out-String -Width 200 | Write-Host

    Write-Host ("  Vault: {0}" -f $vault) -ForegroundColor DarkGray
    Write-Host '  Restore newest:  .\GameSaveVault.ps1 restore -Snapshot latest' -ForegroundColor DarkGray
    Write-Host '  Restore one:     .\GameSaveVault.ps1 restore -Snapshot <name> -Game "Skyrim"' -ForegroundColor DarkGray
}

function Invoke-Add {
    if (-not $Target) { throw 'Usage: .\GameSaveVault.ps1 add "Game name" -Paths "%DOCUMENTS%\Game\Saves"' }
    if (-not $Paths -or $Paths.Count -eq 0) { throw 'Provide at least one -Paths value.' }

    $normalized = @()
    foreach ($p in $Paths) {
        if (-not $p) { continue }
        $expanded = Expand-GSVToken -Path $p
        if (-not (Test-Path -LiteralPath $expanded)) {
            Write-GSVLog -Level Warn -Message "path does not exist yet: $expanded"
        }
        $normalized += $p
    }

    $entry = Save-GSVCustomGame -Name $Target -Paths $normalized -RegistryKeys $Registry -Notes 'Added manually'
    Write-Host ''
    Write-Kv 'Saved game' $entry.Name 'Green'
    Write-Kv 'Paths' ($normalized -join '; ')
    Write-Host '  It will be included in the next backup.' -ForegroundColor DarkGray
}

function Invoke-Prune {
    Write-Title 'Prune old snapshots'
    $keep = if ($Keep -gt 0) { $Keep } else { [int]$settings.KeepSnapshots }
    $removed = @(Remove-GSVOldSnapshots -BackupRoot $vault -Keep $keep -DryRun:$isDryRun)
    Write-Kv 'Kept' $keep
    Write-Kv 'Removed' $removed.Count
}

function Show-Stats {
    Write-Title 'Vault status'
    $stats = Get-GSVVaultStats -BackupRoot $vault
    Write-Kv 'Vault' $stats.BackupRoot 'Yellow'
    Write-Kv 'Snapshots' $stats.SnapshotCount
    Write-Kv 'Snapshot size' (Format-GSVSize $stats.SnapshotBytes)
    Write-Kv 'Rollback size' (Format-GSVSize $stats.RollbackBytes)
    if ($stats.Latest) {
        Write-Kv 'Latest' (([datetime]$stats.Latest.CreatedUtc).ToLocalTime().ToString('yyyy-MM-dd HH:mm'))
        Write-Kv 'Latest label' $stats.Latest.Label
    }
    $drive = [System.IO.Path]::GetPathRoot($vault)
    if ($drive) {
        try {
            $d = Get-PSDrive -Name $drive.Substring(0, 1) -ErrorAction SilentlyContinue
            if ($d) { Write-Kv 'Free on vault drive' (Format-GSVSize $d.Free) }
        } catch { }
    }
}

function Show-Doctor {
    Write-Title 'Diagnostics'
    Write-Kv 'PowerShell' $PSVersionTable.PSVersion.ToString()
    Write-Kv '64-bit process' ([Environment]::Is64BitProcess)
    Write-Kv 'Windows' ([Environment]::OSVersion.VersionString)
    Write-Kv 'Vault' $vault 'Yellow'
    Write-Kv 'Catalog entries' (@(Get-GSVCatalog).Count)
    Write-Kv 'Custom games' (@(Get-GSVCustomGames).Count)
    Write-Kv 'Steam roots' ((@(Get-GSVSteamRoots)) -join '; ')
    Write-Kv 'Steam libraries' (@(Get-GSVSteamLibraries).Count)
    Write-Kv 'Installed games found' (@(Get-GSVAllGames -Settings $settings -NoLocations).Count)
    Write-Kv 'Snapshots' (@(Get-GSVSnapshots -BackupRoot $vault).Count)

    $old = @(Get-GSVWindowsOldRoots)
    Write-Kv 'Windows.old folders' ($(if ($old.Count) { $old -join '; ' } else { 'none' }))

    Write-Host ''
    if ($vault.StartsWith($env:SystemDrive, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host '  [!] Vault is on the system drive. Move it to D:\ or an external disk.' -ForegroundColor Red
    } else {
        Write-Host '  [ok] Vault is not on the system drive.' -ForegroundColor Green
    }

    if (Test-Path -LiteralPath $vault) {
        $probe = Join-Path $vault '.write-test'
        try {
            Set-Content -LiteralPath $probe -Value 'ok' -ErrorAction Stop
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
            Write-Host '  [ok] Vault is writable.' -ForegroundColor Green
        } catch {
            Write-Host '  [!] Vault is NOT writable.' -ForegroundColor Red
        }
    } else {
        Write-Host '  [i] Vault folder does not exist yet (created on first backup).' -ForegroundColor DarkGray
    }

    if ($old.Count -gt 0) {
        Write-Host '  [i] Windows.old found. You can run: .\GameSaveVault.ps1 from-old -DryRun' -ForegroundColor DarkYellow
        Write-Host '      Windows removes Windows.old automatically after about 10 days.' -ForegroundColor DarkGray
    }
}

function Show-DeepScan {
    Write-Title 'Deep scan for game saves'

    $roots = New-Object System.Collections.Generic.List[string]
    if ($AllDrives) {
        foreach ($r in @(Get-GSVFixedDriveRoots)) { $roots.Add($r) }
    } else {
        $wanted = @($Drive)
        if (($wanted.Count -eq 0) -and $Target) { $wanted = @($Target) }
        if ($wanted.Count -eq 0) { $wanted = @($env:SystemDrive) }

        foreach ($d in $wanted) {
            if (-not $d) { continue }
            $p = [string]$d
            if ($p -match '^[A-Za-z]$') { $p = $p + ':\' }
            elseif ($p -match '^[A-Za-z]:$') { $p = $p + '\' }
            if (-not $p.EndsWith('\')) { $p += '\' }
            $roots.Add($p)
        }
    }

    if ($roots.Count -eq 0) { throw 'No scan drive given.' }

    if (-not $Quiet) {
        Write-Kv 'Scanning' ($roots -join '; ') 'Yellow'
        Write-Kv 'Max depth' $MaxDepth
        Write-Kv 'Max results' $MaxResults
        Write-Host '  Looking for CPY_SAVES, GSE / Goldberg, scene "remote", UWP, LocalLow,' -ForegroundColor DarkGray
        Write-Host '  Steam userdata, My Games, Saved Games and publisher folders...' -ForegroundColor DarkGray
    }

    $progress = {
        param($folders, $path)
        if (-not $Quiet) { Write-Host ("  ... {0:N0} folders | {1}" -f $folders, $path) -ForegroundColor DarkGray }
    }

    $locations = @(Get-GSVDeepScanLocations -Roots $roots.ToArray() -MaxDepth $MaxDepth `
        -MaxResults $MaxResults -NoSize:$NoSize -Progress $progress)

    Write-Host ''
    if ($locations.Count -eq 0) {
        Write-Host '  No save folders found in that location.' -ForegroundColor Yellow
        Write-Host '  Try:  .\GameSaveVault.ps1 deep-scan -AllDrives -MaxDepth 12' -ForegroundColor DarkGray
        return
    }

    $rows = foreach ($l in $locations) {
        [pscustomobject]@{
            Game   = $l.GameName
            Origin = $l.Origin
            AppId  = $l.AppId
            Files  = if ($null -ne $l.FileCount) { $l.FileCount } else { '' }
            Size   = if ($null -ne $l.Bytes) { Format-GSVSize $l.Bytes } else { '' }
            Path   = $l.ResolvedPath
        }
    }
    $rows | Sort-Object Game, Path | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host

    Write-Host ("  {0} save location(s) found." -f $locations.Count) -ForegroundColor Green

    if ($Backup) {
        if ($isDryRun) { Write-Host '  DRY RUN - no files will be written.' -ForegroundColor Yellow }
        if (-not (Test-Path -LiteralPath $vault) -and -not $isDryRun) {
            New-Item -ItemType Directory -Path $vault -Force | Out-Null
        }
        $label = if ($Label) { $Label } else { 'deep-scan' }
        $result = New-GSVSnapshot -Locations $locations -BackupRoot $vault -Label $label `
            -HashFiles:$Hash -DryRun:$isDryRun -LogFile $logFile

        Write-Host ''
        Write-Kv 'Snapshot' $result.SnapshotPath 'Green'
        Write-Kv 'Entries' $result.EntryCount
        Write-Kv 'Files' $result.TotalFiles
        Write-Kv 'Size' (Format-GSVSize $result.TotalBytes)
        if (-not $isDryRun) {
            $keep = if ($Keep -gt 0) { $Keep } else { [int]$settings.KeepSnapshots }
            if ($keep -gt 0) { $null = Remove-GSVOldSnapshots -BackupRoot $vault -Keep $keep }
        }
    } else {
        Write-Host '  Back up everything found:  .\GameSaveVault.ps1 deep-scan -Backup' -ForegroundColor DarkGray
    }
}

function Show-Help {
    Write-Host @'
GameSaveVault - save/restore PC game saves across Windows reinstalls

USAGE
  .\GameSaveVault.ps1 <command> [options]

COMMANDS
  scan                 List installed games and the save folders found (default)
  deep-scan            Search a whole drive for every save folder (CPY / GSE /
                       Goldberg / scene "remote" / UWP / Steam userdata / LocalLow)
  backup               Snapshot saves into the vault
  restore              Copy saves from the newest (or chosen) snapshot back
  from-old             Recover saves from C:\Windows.old after a reinstall
  snapshots            List snapshots in the vault
  stats                Vault size / latest snapshot
  add                  Register a custom game + save path
  prune                Delete old snapshots
  doctor               Environment and vault diagnostics
  gui                  Open the graphical app

COMMON OPTIONS
  -Game <name[,name]>  Limit to matching games (substring or fuzzy name)
  -BackupRoot <path>   Override the vault location
  -DryRun / -WhatIf    Show what would happen, change nothing
  -Detailed            (scan) show every save path
  -Hash                (backup) also store SHA256 for each file (slower)
  -Snapshot <name>     (restore) snapshot folder name, or 'latest'
  -SkipRegistry        (restore) do not import registry settings
  -KeepExisting        (restore) never overwrite a save that already exists
  -NoGlobal            (backup) skip launcher-wide / emulator save folders
  -Keep <n>            (backup/prune) how many snapshots to keep
  -Drive <C:>          (deep-scan) drive(s) to search, default is the system drive
  -AllDrives           (deep-scan) search every fixed drive
  -MaxDepth <n>        (deep-scan) folder depth to walk, default 10
  -MaxResults <n>      (deep-scan) stop after this many save folders, default 500
  -NoSize              (deep-scan) skip file counting / sizing (much faster)
  -Backup              (deep-scan) snapshot everything the scan found

EXAMPLES
  .\GameSaveVault.ps1 deep-scan
  .\GameSaveVault.ps1 deep-scan -AllDrives -MaxDepth 12
  .\GameSaveVault.ps1 deep-scan -Drive C: -Backup
  .\GameSaveVault.ps1 backup -All
  .\GameSaveVault.ps1 backup -Game Skyrim,Palworld
  .\GameSaveVault.ps1 restore -Snapshot latest -DryRun
  .\GameSaveVault.ps1 from-old -DryRun
  .\GameSaveVault.ps1 add "My Game" -Paths "%DOCUMENTS%\MyGame\Saves"
'@ -ForegroundColor Gray
}

# ---------------------------------------------------------------- dispatch

$cmd = $Command.ToLowerInvariant()
if ($cmd -in @('help', '-h', '--help', '?')) { $cmd = 'help' }

try {
    switch ($cmd) {
        'scan'      { Show-Scan }
        'list'      { Show-Scan }
        'backup'    { Invoke-Backup }
        'restore'   { Invoke-Restore }
        'from-old'  { Invoke-FromOld }
        'fromold'   { Invoke-FromOld }
        'deep-scan' { Show-DeepScan }
        'deepscan'  { Show-DeepScan }
        'deep'      { Show-DeepScan }
        'search'    { Show-DeepScan }
        'snapshots' { Show-Snapshots }
        'stats'     { Show-Stats }
        'add'       { Invoke-Add }
        'prune'     { Invoke-Prune }
        'doctor'    { Show-Doctor }
        'gui'       {
            $gui = Join-Path $script:Root 'GameSaveVault-GUI.ps1'
            if (-not (Test-Path -LiteralPath $gui)) { throw "GUI not found: $gui" }
            & $gui
        }
        'help'      { Show-Help }
        default {
            Write-Host "Unknown command: $Command" -ForegroundColor Red
            Show-Help
            exit 1
        }
    }
} catch {
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if (-not $Quiet) {
        Write-Host ("  at {0}:{1}" -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber) -ForegroundColor DarkGray
    }
    exit 1
}

exit 0
