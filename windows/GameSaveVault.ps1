<#
.SYNOPSIS
    GameSaveVault - back up and restore PC game saves (including repack / Steam-emu
    saves) so they survive a Windows reinstall.

.EXAMPLES
    .\GameSaveVault.ps1 roots
    .\GameSaveVault.ps1 scan-folders -Directory "D:\Games;C:\PS5GAMES"
    .\GameSaveVault.ps1 scan-db
    .\GameSaveVault.ps1 backup -All
    .\GameSaveVault.ps1 export-db -File D:\GameSaveVault.gsvdb
    .\GameSaveVault.ps1 restore-db -File D:\GameSaveVault.gsvdb
    .\GameSaveVault.ps1 scan -Detailed
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

    [string[]]$Directory = @(),

    [string[]]$Drive = @(),

    [int]$MaxDepth = 10,

    [int]$MaxResults = 500,

    [string]$Label = '',

    [string]$From = '',

    [string]$To = '',

    [string]$RestoreFormat = 'profile',

    [string]$RestoreRoot = '',

    [string[]]$Title = @(),

    [Alias('Pattern','Patterns','SavePatterns')]
    [string[]]$SavePattern = @(),

    [string[]]$Alias = @(),

    [string[]]$InstallDir = @(),

    [ValidateSet('auto','token','gamedir','absolute')]
    [string]$Mode = 'auto',

    [string]$Notes = '',

    [string]$File = '',

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
$script:Root = Split-Path -Parent $PSScriptRoot

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

    $emulators = @(Get-GSVEmulatorSaveLocations -Settings $settings -NoSize)
    if ($emulators.Count -gt 0) {
        Write-Host ''
        Write-Host ("  Console emulator saves (Switch / 3DS / PSP / PS3 / Vita / Xbox 360 / Wii / PS5 / PS4): {0} save folder(s)" -f $emulators.Count) -ForegroundColor DarkYellow
        foreach ($l in $emulators) { Write-Host ("    DIR  {0}   ({1})" -f $l.ResolvedPath, $l.Note) -ForegroundColor DarkGray }
        Write-Host '  Copy saves between emulators:  .\GameSaveVault.ps1 migrate -From eden -To ryujinx' -ForegroundColor DarkGray
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

    $dbLocations = @(Get-GSVScanDatabaseLocations -OnlyExisting)
    $useScanDb = ($Game.Count -eq 0 -and $dbLocations.Count -gt 0)

    $locations = New-Object System.Collections.Generic.List[object]
    $selectedCount = 0
    $sourceLabel = 'catalog scan'

    if ($useScanDb) {
        foreach ($l in $dbLocations) { $locations.Add($l) }
        $selectedCount = @($dbLocations | Group-Object { [string]$_.GameName }).Count
        $sourceLabel = 'scan database'
    } else {
        $games = @(Get-GSVAllGames -Settings $settings)
        $selected = @(Select-GSVGamesByFilter -Games $games -Filter $Game)

        if ($Game.Count -gt 0 -and $selected.Count -eq 0) {
            throw "No installed game matched: $($Game -join ', ')"
        }
        if ($selected.Count -eq 0 -and $NoGlobal) {
            throw 'No games detected and -NoGlobal was specified. Nothing to back up.'
        }

        foreach ($g in $selected) {
            foreach ($l in @($g.Locations)) { $locations.Add($l) }
        }
        $selectedCount = $selected.Count
    }

    if (-not $NoGlobal) {
        foreach ($l in @(Get-GSVGlobalSaveLocations -Settings $settings)) { $locations.Add($l) }
        foreach ($l in @(Get-GSVEmulatorSaveLocations -Settings $settings)) { $locations.Add($l) }
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
        Write-Kv 'Games selected' $selectedCount
        Write-Kv 'Source' $sourceLabel
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

    $fmt = if ($RestoreFormat) { $RestoreFormat.ToLowerInvariant() } else { 'profile' }
    if ($fmt -notin @('profile', 'verbatim', 'folder')) {
        throw "Unknown -RestoreFormat '$RestoreFormat'. Use profile, verbatim or folder."
    }
    if ($fmt -eq 'folder' -and -not $RestoreRoot) {
        throw '-RestoreRoot is required with -RestoreFormat folder (the folder every save is copied into).'
    }

    if (-not $Quiet) {
        Write-Kv 'Restore format' $fmt
        if ($fmt -eq 'verbatim') {
            Write-Host '  Saves are written back exactly where they were stored (the original drive layout, e.g. C:).' -ForegroundColor DarkGray
        } elseif ($fmt -eq 'folder') {
            Write-Kv 'Into folder' $RestoreRoot 'Yellow'
            Write-Host '  Entries keep their format: <folder>\<TOKEN>\<relative path>.' -ForegroundColor DarkGray
        } else {
            Write-Host '  Saves are written into the current user profile.' -ForegroundColor DarkGray
        }
    }

    $result = Restore-GSVSnapshot -BackupRoot $vault -Snapshot $Snapshot -GameFilter $Game `
        -DryRun:$isDryRun -SkipRegistry:$SkipRegistry -KeepExisting:$KeepExisting -LogFile $logFile `
        -RestoreFormat $fmt -RestoreRoot $RestoreRoot

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

    $fmt = if ($RestoreFormat) { $RestoreFormat.ToLowerInvariant() } else { 'profile' }
    if ($fmt -notin @('profile', 'verbatim', 'folder')) { throw "Unknown -RestoreFormat '$RestoreFormat'." }
    if ($fmt -eq 'folder' -and -not $RestoreRoot) { throw '-RestoreRoot is required with -RestoreFormat folder.' }
    if ($fmt -ne 'profile' -and -not $Quiet) {
        Write-Kv 'Restore format' $fmt
        if ($RestoreRoot) { Write-Kv 'Into folder' $RestoreRoot 'Yellow' }
    }

    $result = Import-GSVFromWindowsOld -BackupRoot $vault -WindowsOldRoot $WindowsOldRoot `
        -GameFilter $Game -DryRun:$isDryRun -NoRestore:$NoRestore -Label 'windows-old' -RestoreFormat $fmt -RestoreRoot $RestoreRoot

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

function Show-Rules {
    Write-Title 'Save rules (portable save-location patterns)'
    $rules = @(Get-GSVRules)
    Write-Kv 'Database' (Get-GSVRulesPath) 'Yellow'

    if ($rules.Count -eq 0) {
        Write-Host '  No rules yet. Add one with:' -ForegroundColor Yellow
        Write-Host '    .\GameSaveVault.ps1 rule-add "My Game" -Paths "D:\Games\My Game\Saves" -SavePattern *.sav' -ForegroundColor DarkGray
        Write-Host '    .\GameSaveVault.ps1 rule-add "My Game" -Paths "%LOCALAPPDATA%\MyGame\Saved" -InstallDir "My Game"' -ForegroundColor DarkGray
        return
    }

    Write-Kv 'Rules' $rules.Count
    foreach ($r in $rules) {
        Write-Host ''
        Write-Host ("  {0}" -f $r.Name) -ForegroundColor Cyan
        Write-Kv '    id' $r.Id
        if (@($r.SteamAppIds).Count -gt 0) { Write-Kv '    app ids' (@($r.SteamAppIds) -join ', ') }
        if (@($r.InstallDirNames).Count -gt 0) { Write-Kv '    install dir names' (@($r.InstallDirNames) -join ', ') }
        if (@($r.FilePatterns).Count -gt 0) { Write-Kv '    save file patterns' (@($r.FilePatterns) -join ', ') }
        if (@($r.FolderPatterns).Count -gt 0) { Write-Kv '    save folder patterns' (@($r.FolderPatterns) -join ', ') }
        foreach ($p in @($r.Paths)) {
            $pat = if ($p -is [string]) { $p } else { $p.Pattern }
            $mode = if ($p -is [string]) { 'auto' } else { $p.Mode }
            Write-Host ("      - {0}  [{1}]" -f $pat, $mode) -ForegroundColor DarkGray
        }
        if ($r.Notes) { Write-Kv '    notes' $r.Notes 'DarkGray' }
    }
}

function Invoke-RuleAdd {
    if (-not $Target) {
        throw 'Usage: .\GameSaveVault.ps1 rule-add "Game name" -Paths "D:\Games\Game\Saves","%APPDATA%\Game" [-SavePattern *.sav]'
    }
    if (-not $Paths -or @($Paths).Count -eq 0) {
        throw 'Provide at least one -Paths value (a folder, a wildcard, or a %TOKEN% pattern).'
    }

    $installNames = @($InstallDir | Where-Object { $_ })
    if ($installNames.Count -eq 0) { $installNames = @($Target) }

    $entry = Save-GSVRule -Name $Target -Paths $Paths -FilePatterns $SavePattern `
        -Aliases $Alias -SteamAppIds $AppId -InstallDirNames $installNames `
        -Mode $Mode -Notes $Notes

    Write-Host ''
    Write-Kv 'Saved rule' $entry.Name 'Green'
    Write-Kv 'id' $entry.Id
    foreach ($p in @($entry.Paths)) {
        Write-Kv 'path' ('{0}  [{1}]' -f $p.Pattern, $p.Mode)
    }
    if (@($entry.FilePatterns).Count -gt 0) { Write-Kv 'save patterns' (@($entry.FilePatterns) -join ', ') }
    Write-Host '  Stored in config\save-rules.json as portable token paths.' -ForegroundColor DarkGray
    Write-Host '  Run "discover" to check what it finds on this machine.' -ForegroundColor DarkGray
}

function Invoke-RuleRemove {
    if (-not $Target) { throw 'Usage: .\GameSaveVault.ps1 rule-remove "Game name or rule id"' }
    $n = Remove-GSVRule -Name $Target
    Write-Kv 'Removed' $n
}

function Invoke-RuleImport {
    if (-not $File) { throw 'Usage: .\GameSaveVault.ps1 rule-import -File rules.json' }
    $n = Import-GSVRules -Path $File
    Write-Kv 'Imported' $n 'Green'
    Write-Kv 'Database' (Get-GSVRulesPath)
}

function Invoke-RuleExport {
    $out = if ($File) { $File } else { Join-Path (Get-Location) 'save-rules.export.json' }
    $p = Export-GSVRules -Path $out
    Write-Kv 'Exported' $p 'Green'
}

function Invoke-Discover {
    Write-Title 'Discover games and saves from save rules'
    $rules = @(Get-GSVRules)
    if ($rules.Count -eq 0) {
        Write-Host '  No save rules yet. Add one with:' -ForegroundColor Yellow
        Write-Host '    .\GameSaveVault.ps1 rule-add "My Game" -Paths "D:\Games\My Game\Saves" -SavePattern *.sav' -ForegroundColor DarkGray
        return
    }

    $all = New-Object System.Collections.Generic.List[object]
    foreach ($rule in $rules) {
        $locs = @(Resolve-GSVRulePaths -Rule $rule -NoSize:$NoSize)
        $gameDir = Find-GSVRuleGameDir -Names @($rule.InstallDirNames)

        Write-Host ''
        Write-Host ("  {0}" -f $rule.Name) -ForegroundColor Cyan
        if ($gameDir) { Write-Kv '  install folder' $gameDir 'Green' }
        else { Write-Kv '  install folder' 'not found on this machine' 'DarkYellow' }

        if ($locs.Count -eq 0) {
            Write-Kv '  saves' 'none found' 'DarkYellow'
            continue
        }

        Write-Kv '  saves' $locs.Count 'Green'
        foreach ($l in $locs) {
            $tag = if ($l.RestoreMode) { $l.RestoreMode } else { '-' }
            Write-Host ("    [{0}] {1}" -f $tag, $l.ResolvedPath) -ForegroundColor Gray
            $all.Add($l)
        }
    }

    if ($Backup -and $all.Count -gt 0) {
        if ($isDryRun) {
            Write-Host ''
            Write-Host '  DRY RUN - nothing will be written.' -ForegroundColor Yellow
            return
        }
        $snap = New-GSVSnapshot -Locations $all.ToArray() -BackupRoot $vault -Label 'discover' -LogFile $logFile
        Write-Host ''
        Write-Kv 'Snapshot' $snap.SnapshotPath 'Green'
        Write-Kv 'Entries' $snap.EntryCount
        Write-Kv 'Size' (Format-GSVSize $snap.TotalBytes)
    }
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
    $scanDb = Read-GSVScanDatabase
    Write-Kv 'Scan database' ($(if ($scanDb) { '{0} locations from {1} root(s)' -f (@(Get-GSVScanDatabaseLocations).Count), (@($scanDb.Roots).Count) } else { 'none (run: roots, then scan-folders)' }))
    Write-Kv 'Steam roots' ((@(Get-GSVSteamRoots)) -join '; ')
    Write-Kv 'Steam libraries' (@(Get-GSVSteamLibraries).Count)
    Write-Kv 'Installed games found' (@(Get-GSVAllGames -Settings $settings -NoLocations).Count)
    Write-Kv 'Console emulator saves' (@(Get-GSVEmulatorSaveLocations -Settings $settings -NoSize).Count)
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
        foreach ($d in $Directory) { if ($d) { $wanted += $d } }
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

function Resolve-GSVScanFolderRoots {
    param([string[]]$Values)
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($v in @($Values)) {
        if (-not $v) { continue }
        foreach ($part in ([string]$v -split '[;,]')) {
            $p = $part.Trim()
            if (-not $p) { continue }
            if ($p -match '^[A-Za-z]$') { $p = $p + ':\' }
            elseif ($p -match '^[A-Za-z]:$') { $p = $p + '\' }
            if (-not (Test-Path -LiteralPath $p)) {
                throw "Folder does not exist: $p"
            }
            $full = (Get-Item -LiteralPath $p -ErrorAction Stop).FullName
            if (-not $roots.Contains($full)) { $roots.Add($full) }
        }
    }
    return $roots.ToArray()
}

function Show-ScanRoots {
    Write-Title 'Folders available for scanning'
    $candidates = @(Get-GSVScanRootCandidates)
    if ($candidates.Count -eq 0) {
        Write-Host '  No drives or game folders found.' -ForegroundColor Yellow
        return
    }

    $i = 0
    foreach ($c in $candidates) {
        $i++
        $mark = if ($c.Selected) { '*' } else { ' ' }
        Write-Host ('  {0,2}. [{1}] {2}' -f $i, $mark, $c.Display) -ForegroundColor Gray
    }
    Write-Host ''
    Write-Host '  * = suggested default. Nothing is scanned until you choose folders.' -ForegroundColor DarkGray
    Write-Kv 'Scan database' (Get-GSVScanDatabasePath) 'Yellow'
    Write-Host '  Scan chosen folders:  .\GameSaveVault.ps1 scan-folders -Directory "D:\Games;C:\PS5GAMES"' -ForegroundColor DarkGray
    Write-Host '  Scan every drive:     .\GameSaveVault.ps1 scan-folders -AllDrives' -ForegroundColor DarkGray
    Write-Host '  Show stored results:  .\GameSaveVault.ps1 scan-db' -ForegroundColor DarkGray
}

function Show-ScanDatabase {
    Write-Title 'Stored scan database'
    $db = Read-GSVScanDatabase
    if (-not $db) {
        Write-Host '  No scan database yet.' -ForegroundColor Yellow
        Write-Host '  Choose folders first:  .\GameSaveVault.ps1 roots' -ForegroundColor DarkGray
        return
    }

    $locs = @(Get-GSVScanDatabaseLocations)
    Write-Kv 'Database' (Get-GSVScanDatabasePath) 'Yellow'
    Write-Kv 'Last updated' ([string]$db.UpdatedUtc)
    Write-Kv 'Roots' (@($db.Roots).Count)
    Write-Kv 'Save locations' $locs.Count

    foreach ($r in @($db.Roots)) {
        if (-not $r) { continue }
        Write-Host ('    ROOT  {0}  ({1} locations, {2})' -f $r.Path, $r.LocationCount, $r.ScannedUtc) -ForegroundColor DarkGray
    }

    if ($locs.Count -eq 0) {
        Write-Host '  The database is empty. Run scan-folders.' -ForegroundColor Yellow
        return
    }

    Write-Host ''
    $rows = foreach ($l in ($locs | Sort-Object GameName, ResolvedPath)) {
        [pscustomobject]@{
            Game    = $l.GameName
            AppId   = $l.AppId
            Exists  = if ($l.Exists) { 'yes' } else { 'no' }
            Files   = if ($null -ne $l.FileCount) { $l.FileCount } else { '' }
            Path    = if ($l.Kind -eq 'Registry') { $l.RegistryKey } else { $l.ResolvedPath }
        }
    }
    $rows | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
}

function Invoke-ScanFolders {
    Write-Title 'Scan selected folders for game saves'

    $wanted = New-Object System.Collections.Generic.List[string]
    if ($AllDrives) {
        foreach ($r in @(Get-GSVFixedDriveRoots)) { $wanted.Add($r) }
    }
    if ($Target) { $wanted.Add($Target) }
    foreach ($d in @($Drive)) { if ($d) { $wanted.Add($d) } }
    foreach ($d in @($Directory)) { if ($d) { $wanted.Add($d) } }

    if ($wanted.Count -eq 0) {
        Write-Host '  Choose at least one folder or drive.' -ForegroundColor Yellow
        Write-Host '  List folders:  .\GameSaveVault.ps1 roots' -ForegroundColor DarkGray
        Write-Host '  Example:       .\GameSaveVault.ps1 scan-folders -Directory "D:\Games;C:\PS5GAMES"' -ForegroundColor DarkGray
        return
    }

    $roots = @(Resolve-GSVScanFolderRoots -Values $wanted.ToArray())
    if ($roots.Count -eq 0) { throw 'No valid folders to scan.' }

    if (-not $Quiet) {
        Write-Kv 'Scanning' ($roots -join '; ') 'Yellow'
        Write-Kv 'Max depth' $MaxDepth
        Write-Kv 'Max results' $MaxResults
        Write-Host '  Only the chosen folders and their subfolders are searched.' -ForegroundColor DarkGray
    }

    $progress = {
        param($folders, $path)
        if (-not $Quiet) { Write-Host ("  ... {0:N0} folders | {1}" -f $folders, $path) -ForegroundColor DarkGray }
    }

    $locations = @(Get-GSVDeepScanLocations -Roots $roots -MaxDepth $MaxDepth `
        -MaxResults $MaxResults -NoSize:$NoSize -Progress $progress)

    $saved = Update-GSVScanDatabase -Roots $roots -Locations $locations

    Write-Host ''
    Write-Kv 'Folders scanned' $roots.Count
    Write-Kv 'Save locations' $locations.Count
    Write-Kv 'Scan database' $saved.Path 'Green'
    Write-Kv 'Stored total' $saved.Total

    if ($locations.Count -eq 0) {
        Write-Host '  No save folders found in those folders.' -ForegroundColor Yellow
        return
    }

    $rows = foreach ($l in ($locations | Sort-Object GameName, ResolvedPath)) {
        [pscustomobject]@{
            Game   = $l.GameName
            AppId  = $l.AppId
            Path   = $l.ResolvedPath
        }
    }
    $rows | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
    Write-Host '  Back up the stored results:  .\GameSaveVault.ps1 backup -All' -ForegroundColor DarkGray
}

function Invoke-ExportDatabase {
    Write-Title 'Export a portable game-save database'

    $out = $File
    if (-not $out) {
        $out = Join-Path $vault ('GameSaveVault-{0}.gsvdb' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }

    $snaps = @(Get-GSVSnapshots -BackupRoot $vault)
    $snapArg = $Snapshot
    if ($snaps.Count -eq 0) {
        $locs = @(Get-GSVScanDatabaseLocations -OnlyExisting)
        if ($locs.Count -eq 0) {
            throw 'No snapshots and no stored save locations. Run scan-folders and backup first.'
        }
        if ($isDryRun) {
            Write-Host ("  DRY RUN - would snapshot {0} save location(s) and write {1}" -f $locs.Count, $out) -ForegroundColor Yellow
            return
        }
        Write-Host '  No snapshot yet - creating one from the scan database...' -ForegroundColor DarkGray
        $snap = New-GSVSnapshot -Locations $locs -BackupRoot $vault -Label 'portable-db' -HashFiles:$Hash -LogFile $logFile
        $snapArg = $snap.SnapshotPath
    }

    if ($isDryRun) {
        Write-Host ("  DRY RUN - would write portable database: {0}" -f $out) -ForegroundColor Yellow
        return
    }

    $r = New-GSVPortableDatabase -BackupRoot $vault -Snapshot $snapArg -OutputPath $out -IncludeScanDatabase -Force -LogFile $logFile

    Write-Host ''
    Write-Kv 'Portable database' $r.Path 'Green'
    Write-Kv 'Size' (Format-GSVSize $r.Bytes)
    Write-Kv 'Snapshot' $r.SnapshotName
    Write-Kv 'Entries' $r.EntryCount
    Write-Kv 'Files' $r.TotalFiles
    Write-Host '  Copy this one file to the new PC, then run:' -ForegroundColor DarkGray
    Write-Host ('    .\GameSaveVault.ps1 restore-db -File "{0}"' -f $r.Path) -ForegroundColor DarkGray
}

function Invoke-RestoreFromFile {
    Write-Title 'Restore saves from a portable database file'
    if (-not $File) { throw 'Usage: .\GameSaveVault.ps1 restore-db -File D:\GameSaveVault-....gsvdb' }
    if (-not (Test-Path -LiteralPath $File)) { throw "File not found: $File" }

    $ext = [System.IO.Path]::GetExtension($File).ToLowerInvariant()
    if ($ext -eq '.json') {
        if ($isDryRun) {
            Write-Host ("  DRY RUN - would import scan database {0}" -f $File) -ForegroundColor Yellow
            return
        }
        $import = Import-GSVScanDatabaseFile -Path $File
        Write-Kv 'Imported locations' $import.Imported
        Write-Kv 'Stored total' $import.Total
        Write-Kv 'Scan database' $import.Path 'Green'
        Write-Host '  This JSON file lists where saves belong. Use a .gsvdb file to restore the save files too.' -ForegroundColor DarkYellow
        return
    }

    $fmt = if ($RestoreFormat) { $RestoreFormat.ToLowerInvariant() } else { 'profile' }
    if ($fmt -notin @('profile', 'verbatim', 'folder')) {
        throw "Unknown -RestoreFormat '$RestoreFormat'. Use profile, verbatim or folder."
    }
    if ($fmt -eq 'folder' -and -not $RestoreRoot) {
        throw '-RestoreRoot is required with -RestoreFormat folder.'
    }

    if (-not $Quiet) {
        Write-Kv 'Portable database' $File 'Yellow'
        Write-Kv 'Restore format' $fmt
        if ($RestoreRoot) { Write-Kv 'Into folder' $RestoreRoot 'Yellow' }
        if ($isDryRun) { Write-Host '  DRY RUN - nothing will be changed.' -ForegroundColor Yellow }
    }

    $r = Restore-GSVPortableDatabase -BundlePath $File -BackupRoot $vault `
        -RestoreFormat $fmt -RestoreRoot $RestoreRoot -GameFilter $Game `
        -DryRun:$isDryRun -SkipRegistry:$SkipRegistry -KeepExisting:$KeepExisting -LogFile $logFile

    Write-Host ''
    Write-Kv 'Imported scan db' $r.ImportedDatabase
    Write-Kv 'Restored' $r.Restored
    Write-Kv 'Registry keys' $r.Registry
    Write-Kv 'Skipped' $r.Skipped
    Write-Kv 'Failed' $r.Failed ($(if ($r.Failed -gt 0) { 'Red' } else { 'Gray' }))
    foreach ($m in @($r.Messages)) { Write-Host "  - $m" -ForegroundColor DarkYellow }
}

function Invoke-Migrate {
    Write-Title 'Migrate console emulator saves'

    $defs = @(Get-GSVEmulatorDefinitions)
    $known = @($defs | ForEach-Object { $_.Id })
    $emuList = ($defs | ForEach-Object { '{0} ({1})' -f $_.Id, $_.Console }) -join ', '
    if (-not $From -or -not $To) {
        Write-Host '  Usage:  .\GameSaveVault.ps1 migrate -From <source> -To <target> [-Title <id>] [-DryRun]' -ForegroundColor Yellow
        Write-Host ("  Emulators:  {0}" -f $emuList) -ForegroundColor DarkGray
        return
    }
    if ($known -notcontains $From) { throw "Unknown source emulator: $From (use: $($known -join ', '))" }
    if ($known -notcontains $To) { throw "Unknown destination emulator: $To (use: $($known -join ', '))" }
    if ($From -ieq $To) { throw 'Source and destination are the same emulator.' }

    $srcDef = @($defs | Where-Object { $_.Id -eq $From })[0]
    $dstDef = @($defs | Where-Object { $_.Id -eq $To })[0]
    $srcFamily = Get-GSVEmulatorFamily -Definition $srcDef
    $dstFamily = Get-GSVEmulatorFamily -Definition $dstDef
    if ($srcFamily -ne $dstFamily) {
        throw "Cannot migrate between different consoles: $($srcDef.Console) -> $($dstDef.Console)"
    }

    $index = @(Get-GSVEmulatorSaveIndex -EmulatorIds @($From) -IncludePortable)
    $entries = @($index | Where-Object { $_.EmulatorId -eq $From })

    if ($Title.Count -gt 0) {
        $selected = New-Object System.Collections.Generic.List[object]
        foreach ($e in $entries) {
            foreach ($t in $Title) {
                if ($e.TitleId -ieq $t) { $selected.Add($e); break }
            }
        }
        $entries = $selected.ToArray()
    }

    if ($entries.Count -eq 0) {
        Write-Host "  No saves found for $($srcDef.Name)." -ForegroundColor Yellow
        return
    }

    foreach ($e in $entries) { Write-Host ("    {0}  profile {1}  <-  {2}" -f $e.TitleId, $e.ProfileId, $e.Path) -ForegroundColor DarkGray }
    Write-Host ''
    Write-Kv 'From' ("{0}" -f $srcDef.Name) 'Yellow'
    Write-Kv 'To' ("{0}" -f $dstDef.Name) 'Yellow'
    Write-Kv 'Saves to copy' $entries.Count
    if ($isDryRun) { Write-Host '  DRY RUN - nothing will be copied.' -ForegroundColor Yellow }

    $result = Copy-GSVEmulatorSaves -Entries $entries -DestinationEmulatorId $To -BackupRoot $vault -DryRun:$isDryRun

    Write-Host ''
    Write-Kv 'Copied' $result.Migrated 'Green'
    Write-Kv 'Skipped' $result.Skipped
    Write-Kv 'Failed' $result.Failed
    foreach ($m in @($result.Messages)) { Write-Host "  - $m" -ForegroundColor DarkYellow }
    if (-not $isDryRun -and $result.Migrated -gt 0) {
        Write-Host '  Any save that was overwritten is in ' -NoNewline -ForegroundColor DarkGray
        Write-Host (Join-Path $vault 'rollback') -ForegroundColor DarkGray
    }
}

function Show-Help {
    Write-Host @'
GameSaveVault - save/restore PC game saves across Windows reinstalls

USAGE
  .\GameSaveVault.ps1 <command> [options]

COMMANDS
  scan                 List installed games and the save folders found (default)
  roots                List the drives / folders you can choose to scan
  scan-folders         Scan ONLY the folders you choose, and store the results
                       in config\scan-database.json. -Directory, -Drive, -AllDrives
  scan-db              Show the stored scan database (no scanning)
  export-db            Write one portable .gsvdb file (save files + scan database)
  restore-db           Restore saves on another PC from a portable .gsvdb file
  deep-scan            Search a whole drive or a folder for every save folder (CPY /
                       GSE / Goldberg / scene "remote" / UWP / Steam userdata /
                       LocalLow / emulator titles). -Drive, -Directory, -AllDrives
  migrate              Copy console-emulator saves between emulators
                       (-From eden -To ryujinx, -From kyty, -Title ..., -DryRun)
  backup               Snapshot saves into the vault
  restore              Copy saves from the newest (or chosen) snapshot back.
                       -RestoreFormat profile (default) / verbatim / folder,
                       -RestoreRoot <folder> for the folder format
  from-old             Recover saves from C:\Windows.old after a reinstall
  snapshots            List snapshots in the vault
  stats                Vault size / latest snapshot
  add                  Register a custom game + save path
  rules                List save rules (config\save-rules.json)
  rule-add             Add a save rule with portable paths + save patterns
  rule-remove          Remove a save rule
  rule-import          Import save rules from a JSON file
  rule-export          Export save rules to a JSON file
  discover             Find the games + saves described by the rules on THIS PC
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
  -From / -To <emu>    (migrate) emulator ids, e.g. eden, ryujinx, azahar, citra, ppsspp
  -Title <id>          (migrate) only this title id (e.g. 0100… or PPSA…)
  -Directory <path>    (scan-folders/deep-scan) folders to search, e.g. D:\Games
  -RestoreFormat       (restore/from-old/restore-db) profile (default) | verbatim | folder
  -RestoreRoot <folder>    (restore/from-old/restore-db) folder format: <folder>\<TOKEN>\<path>
  -File <path>         (rule-import/export) JSON rules file, or (export-db/restore-db) the .gsvdb file
  -SavePattern <glob>  (rule-add) which files are saves, e.g. *.sav,*.dat
  -Alias <name>        (rule-add) alternative game names for matching
  -InstallDir <name>   (rule-add) install folder name(s) used to find the game
  -Mode <mode>         (rule-add) auto | token | gamedir | absolute
  -Notes <text>        (rule-add) free-form note
  -File <path>         (rule-import/export) JSON rules file
  -Backup              (discover) snapshot everything the rules found

EXAMPLES
  .\GameSaveVault.ps1 roots
  .\GameSaveVault.ps1 scan-folders -Directory "D:\Games;C:\PS5GAMES"
  .\GameSaveVault.ps1 scan-folders -AllDrives -MaxDepth 12
  .\GameSaveVault.ps1 scan-db
  .\GameSaveVault.ps1 export-db -File D:\GameSaveVault.gsvdb
  .\GameSaveVault.ps1 restore-db -File D:\GameSaveVault.gsvdb
  .\GameSaveVault.ps1 deep-scan
  .\GameSaveVault.ps1 deep-scan -AllDrives -MaxDepth 12
  .\GameSaveVault.ps1 deep-scan -Drive C: -Backup
  .\GameSaveVault.ps1 deep-scan -Directory D:\Games,C:\PS5GAMES
  .\GameSaveVault.ps1 migrate -From eden -To ryujinx
  .\GameSaveVault.ps1 migrate -From eden -To ryujinx -Title 0100… -DryRun
  .\GameSaveVault.ps1 backup -All
  .\GameSaveVault.ps1 backup -Game Skyrim,Palworld
  .\GameSaveVault.ps1 restore -Snapshot latest -DryRun
  .\GameSaveVault.ps1 restore -Snapshot latest
  .\GameSaveVault.ps1 restore -RestoreFormat verbatim
  .\GameSaveVault.ps1 restore -RestoreFormat folder -RestoreRoot D:\RestoredSaves
  .\GameSaveVault.ps1 from-old -DryRun
  .\GameSaveVault.ps1 add "My Game" -Paths "%DOCUMENTS%\MyGame\Saves"
  .\GameSaveVault.ps1 rule-add "My Game" -Paths "D:\Games\My Game\Saves" -SavePattern *.sav -InstallDir "My Game"
  .\GameSaveVault.ps1 rule-add "My Game" -Paths "%LOCALAPPDATA%\MyGame\Saved","%APPDATA%\GSE Saves\1234" -SavePattern *.sav,*.dat
  .\GameSaveVault.ps1 discover -Backup
  .\GameSaveVault.ps1 rule-export -File D:\rules.json
  .\GameSaveVault.ps1 rule-import -File D:\rules.json
'@ -ForegroundColor Gray
}

# ---------------------------------------------------------------- dispatch

$cmd = $Command.ToLowerInvariant()
if ($cmd -in @('help', '-h', '--help', '?')) { $cmd = 'help' }

try {
    switch ($cmd) {
        'scan'      { Show-Scan }
        'list'      { Show-Scan }
        'roots'     { Show-ScanRoots }
        'scan-roots' { Show-ScanRoots }
        'scan-folders' { Invoke-ScanFolders }
        'scan-dirs' { Invoke-ScanFolders }
        'scan-db'   { Show-ScanDatabase }
        'export-db' { Invoke-ExportDatabase }
        'restore-db' { Invoke-RestoreFromFile }
        'restore-file' { Invoke-RestoreFromFile }
        'backup'    { Invoke-Backup }
        'restore'   { Invoke-Restore }
        'from-old'  { Invoke-FromOld }
        'fromold'   { Invoke-FromOld }
        'deep-scan' { Show-DeepScan }
        'deepscan'  { Show-DeepScan }
        'deep'      { Show-DeepScan }
        'search'    { Show-DeepScan }
        'migrate'   { Invoke-Migrate }
        'snapshots' { Show-Snapshots }
        'stats'     { Show-Stats }
        'add'       { Invoke-Add }
        'rules'     { Show-Rules }
        'rule-list' { Show-Rules }
        'rule-add'  { Invoke-RuleAdd }
        'rule-remove' { Invoke-RuleRemove }
        'rule-rm'   { Invoke-RuleRemove }
        'rule-import' { Invoke-RuleImport }
        'rule-export' { Invoke-RuleExport }
        'discover'  { Invoke-Discover }
        'prune'     { Invoke-Prune }
        'doctor'    { Show-Doctor }
        'gui'       {
            $gui = Join-Path $PSScriptRoot 'GameSaveVault-GUI.ps1'
            if (-not (Test-Path -LiteralPath $gui)) {
                $gui = Join-Path $script:Root 'GameSaveVault-GUI.ps1'
            }
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
