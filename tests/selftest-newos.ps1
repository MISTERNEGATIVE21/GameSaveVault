#requires -Version 5.1
<#
    selftest-newos.ps1
    Verifies the full "new OS" restore path, including Steam IDs.

    Fully self-contained: the OLD OS is simulated with an overridden token
    table, so it never depends on the real Steam install or profile.

      1. SCAN   - a Steam game (AppId known from appmanifest) finds Steam
                  userdata, GSE, Goldberg, CPY, CODEX, RUNE, SmartSteamEmu.
      2. SAVE   - the manifest stores Token + RelativePath + AppId
                  (never an absolute path for Steam saves).
      3. RESTORE TO A NEW OS - different Windows user, different Steam
                  account id, different Steam library path, different vault
                  drive. Everything must still land in the right place, and
                  the old Steam account folder must not be recreated.
      4. Idempotent restore.
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules\GSV.Core.psm1') -Force
Import-Module (Join-Path $root 'modules\GSV.Vault.psm1') -Force

$failures = New-Object System.Collections.Generic.List[string]
$checks = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:checks++
    if (-not $Condition) { $script:failures.Add($Message) }
}

function New-TestFile {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Get-Content-Under {
    param([string]$Base, [string]$Relative)
    $p = Join-Path $Base $Relative
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    return (Get-Content -LiteralPath $p -Raw).Trim()
}

# ---------------------------------------------------------------------------
# OLD OS (simulated with an overridden token table)
# ---------------------------------------------------------------------------
$sandbox = Join-Path $env:TEMP ('gsv-newos-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$oldProfile = Join-Path $sandbox 'OLDOS\Users\Tester'
$oldSteam = Join-Path $sandbox 'OLDOS\Steam'
$oldVault = Join-Path $sandbox 'OLDOS\GameSaveVault'
$oldPublic = Join-Path $sandbox 'OLDOS\Users\Public'
$oldProgramData = Join-Path $sandbox 'OLDOS\ProgramData'

# NEW OS: different user, different Steam account id, different Steam path
$newProfile = Join-Path $sandbox 'NEWOS\Users\Nova'
$newSteam = Join-Path $sandbox 'NEWOS\Steam'
$newAccount = '76561198012345678'
$oldAccount = '76561198654321098'

$appid = '816020'      # JUMP FORCE
$appid2 = '1275750'    # second Steam game (GSE saves)

try {
    # --- OLD OS Steam saves -------------------------------------------------
    $userData = Join-Path $oldSteam ('userdata\{0}\{1}' -f $oldAccount, $appid)
    New-TestFile (Join-Path $userData 'remote\remotecache.vdf') 'old-remote-cache'
    New-TestFile (Join-Path $userData 'remote\jfsavedata.dat') 'old-savedata'
    New-TestFile (Join-Path $userData 'local\EpicGameSave.sav') 'old-local-save'

    # --- OLD OS scene / emulator saves (under the OLD profile) --------------
    New-TestFile (Join-Path $oldProfile 'Documents\CPY_SAVES\816020\save.sav') 'old-cpy'
    New-TestFile (Join-Path $oldProfile 'Documents\CPY_SAVES\816020\remote\save.sav') 'old-cpy-remote'
    New-TestFile (Join-Path $oldProfile 'AppData\Roaming\GSE Saves\1275750\remote\KntProfileSaveFile\data.save') 'old-gse'
    New-TestFile (Join-Path $oldProfile 'AppData\Roaming\Goldberg SteamEmu Saves\816020\remote\save.dat') 'old-goldberg'
    New-TestFile (Join-Path $oldProfile 'AppData\Local\GSE Saves\816020\remote\save.sav') 'old-gse-local'
    New-TestFile (Join-Path $oldProfile 'AppData\Roaming\SmartSteamEmu\816020\remote\save.dat') 'old-smart'
    New-TestFile (Join-Path $oldProfile 'AppData\Local\JUMP FORCE\Saved\SaveGames\slot.sav') 'old-ue4'

    # --- OLD OS Public / ProgramData scene saves ----------------------------
    New-TestFile (Join-Path $oldPublic 'Documents\Steam\CODEX\816020\remote\jfsavedata.dat') 'old-codex'
    New-TestFile (Join-Path $oldPublic 'Documents\Steam\RUNE\816020\remote\save.dat') 'old-rune'
    New-TestFile (Join-Path $oldProgramData 'Steam\CODEX\816020\remote\save.dat') 'old-codex-pd'

    $oldTable = Get-GSVTokenTable -Override @{
        'USERPROFILE'   = $oldProfile
        'APPDATA'       = (Join-Path $oldProfile 'AppData\Roaming')
        'LOCALAPPDATA'  = (Join-Path $oldProfile 'AppData\Local')
        'LOCALLOW'      = (Join-Path $oldProfile 'AppData\LocalLow')
        'DOCUMENTS'     = (Join-Path $oldProfile 'Documents')
        'SAVEDGAMES'    = (Join-Path $oldProfile 'Saved Games')
        'PUBLIC'        = $oldPublic
        'PUBLICDOCS'    = (Join-Path $oldPublic 'Documents')
        'PROGRAMDATA'   = $oldProgramData
        'STEAMUSERDATA' = (Join-Path $oldSteam 'userdata')
    }

    # ==========================================================================
    # 1. SCAN
    # ==========================================================================
    $game = [pscustomobject]@{
        Id = "steam-$appid"; Name = 'JUMP FORCE'; Source = 'Steam'
        AppId = $appid; InstallDir = 'JUMP FORCE'
        GameDir = (Join-Path $oldSteam 'steamapps\common\JUMP FORCE')
    }
    $locs = @(Get-GSVGameSaveLocations -Game $game -TokenTable $oldTable -NoSize)
    $found = @($locs | Where-Object { $_.Exists })
    Write-Host ("  scan found {0} existing location(s) for AppId {1}" -f $found.Count, $appid)

    Assert-True ($found.Count -ge 6) ("expected >=6 existing scan results, got {0}" -f $found.Count)

    $mapped = New-Object System.Collections.Generic.List[string]
    foreach ($f in $found) { $mapped.Add(("{0}|{1}" -f $f.Token, $f.RelativePath)) }

    $must = @(
        @{ T = 'STEAMUSERDATA'; R = "$oldAccount\$appid" }
        @{ T = 'DOCUMENTS';     R = 'CPY_SAVES\816020' }
        @{ T = 'APPDATA';       R = 'Goldberg SteamEmu Saves\816020' }
        @{ T = 'APPDATA';       R = 'SmartSteamEmu\816020' }
        @{ T = 'LOCALAPPDATA';  R = 'GSE Saves\816020' }
        @{ T = 'PUBLICDOCS';    R = 'Steam\CODEX\816020' }
        @{ T = 'PUBLICDOCS';    R = 'Steam\RUNE\816020' }
        @{ T = 'PROGRAMDATA';   R = 'Steam\CODEX\816020' }
        @{ T = 'LOCALAPPDATA';  R = 'JUMP FORCE' }
    )
    foreach ($m in $must) {
        $key = "{0}|{1}" -f $m.T, $m.R
        Assert-True ($mapped -contains $key) ("scan must find {0}\{1} (got: {2})" -f $m.T, $m.R, ($mapped -join ', '))
    }

    Assert-True (@($found | Where-Object { -not $_.Token }).Count -eq 0) 'every scan result must be token-anchored (no absolute paths)'
    Assert-True (@($found | Where-Object { [string]$_.AppId -ne $appid }).Count -eq 0) 'every scan result must carry the Steam AppId'

    # A second, unrelated Steam AppId: GSE Saves\<appid> must be found by name.
    $game2 = [pscustomobject]@{
        Id = "steam-$appid2"; Name = 'Other Steam Game'; Source = 'Steam'
        AppId = $appid2; InstallDir = 'Other Steam Game'
        GameDir = (Join-Path $oldSteam 'steamapps\common\Other Steam Game')
    }
    $locs2 = @(Get-GSVGameSaveLocations -Game $game2 -TokenTable $oldTable -NoSize)
    $found2 = @($locs2 | Where-Object { $_.Exists })
    Write-Host ("  scan found {0} existing location(s) for AppId {1}" -f $found2.Count, $appid2)
    Assert-True (@($found2 | Where-Object { $_.Token -eq 'APPDATA' -and $_.RelativePath -eq 'GSE Saves\1275750' }).Count -ge 1) `
        'GSE Saves\1275750 must be found by AppId alone (the game name does not match the folder)'
    Assert-True (@($found2 | Where-Object { $_.Token -eq 'APPDATA' -and $_.RelativePath -eq 'GSE Saves\1275750' -and $_.AppId -eq $appid2 }).Count -ge 1) `
        'GSE Saves\1275750 result must carry AppId 1275750'

    # ==========================================================================
    # 2. SAVE
    # ==========================================================================
    $snap = New-GSVSnapshot -Locations $found -BackupRoot $oldVault -Label 'newos'
    Write-Host ("  snapshot: {0} files -> {1}" -f $snap.TotalFiles, $snap.SnapshotPath)

    Assert-True ($snap.EntryCount -ge 6) ("snapshot should have >=6 entries, got {0}" -f $snap.EntryCount)
    Assert-True (-not [string]::IsNullOrWhiteSpace($snap.SnapshotPath)) 'snapshot path must be set'

    $noToken = @($snap.Manifest.Entries | Where-Object { $_.Kind -ne 'Registry' -and -not $_.Token })
    Assert-True ($noToken.Count -eq 0) ("Steam saves must have a token anchor, not an absolute path ({0} bad)" -f $noToken.Count)

    $steamEntries = @($snap.Manifest.Entries | Where-Object { $_.Token -eq 'STEAMUSERDATA' })
    Assert-True ($steamEntries.Count -ge 1) 'snapshot must contain a STEAMUSERDATA entry'
    if ($steamEntries.Count -ge 1) {
        Assert-True ($steamEntries[0].AppId -eq $appid) ("STEAMUSERDATA AppId must be {0}, got '{1}'" -f $appid, $steamEntries[0].AppId)
        Assert-True ($steamEntries[0].RelativePath -eq "$oldAccount\$appid") 'STEAMUSERDATA relative path must keep the original account id so restore can remap it'
    }

    # ==========================================================================
    # 3. RESTORE TO THE NEW OS
    # ==========================================================================
    New-Item -ItemType Directory -Path (Join-Path $newSteam 'userdata') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $newSteam 'userdata\loginusers.vdf') -Value @"
"users"
{
	"$newAccount"
	{
		"MostRecent"		"1"
	}
}
"@
    Write-Host "  new Steam account id: $newAccount  (old: $oldAccount)"

    $newTable = Get-GSVTokenTable -Override @{
        'USERPROFILE'   = $newProfile
        'APPDATA'       = (Join-Path $newProfile 'AppData\Roaming')
        'LOCALAPPDATA'  = (Join-Path $newProfile 'AppData\Local')
        'LOCALLOW'      = (Join-Path $newProfile 'AppData\LocalLow')
        'DOCUMENTS'     = (Join-Path $newProfile 'Documents')
        'SAVEDGAMES'    = (Join-Path $newProfile 'Saved Games')
        'PUBLIC'        = (Join-Path $sandbox 'NEWOS\Users\Public')
        'PUBLICDOCS'    = (Join-Path $sandbox 'NEWOS\Users\Public\Documents')
        'PROGRAMDATA'   = (Join-Path $sandbox 'NEWOS\ProgramData')
        'STEAMUSERDATA' = (Join-Path $newSteam 'userdata')
    }

    $restore = Restore-GSVSnapshot -BackupRoot $oldVault -Snapshot $snap.SnapshotPath -TokenTable $newTable -NoRollback
    Assert-True ($restore.Failed -eq 0) ("restore to new OS had {0} failures" -f $restore.Failed)
    Assert-True ($restore.Restored -ge 6) ("restore should write >=6 entries, wrote {0}" -f $restore.Restored)
    Write-Host ("  restored {0} entries ({1} skipped, {2} failed)" -f $restore.Restored, $restore.Skipped, $restore.Failed)

    $newUD = Join-Path $newSteam ('userdata\{0}\{1}' -f $newAccount, $appid)
    Assert-True ((Get-Content-Under -Base $newUD -Relative 'remote\jfsavedata.dat') -eq 'old-savedata') `
        "Steam save must land under the NEW account id ($newAccount), not the old one"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $newSteam ('userdata\{0}' -f $oldAccount)))) `
        'the OLD Steam account folder must not be recreated on the new OS'
    Assert-True ((Get-Content-Under -Base $newUD -Relative 'local\EpicGameSave.sav') -eq 'old-local-save') 'Steam "local" save must also restore'
    Assert-True ((Get-Content-Under -Base (Join-Path $newProfile 'Documents') -Relative 'CPY_SAVES\816020\save.sav') -eq 'old-cpy') 'CPY save must restore into the new profile Documents'
    Assert-True ((Get-Content-Under -Base (Join-Path $newProfile 'AppData\Roaming') -Relative 'Goldberg SteamEmu Saves\816020\remote\save.dat') -eq 'old-goldberg') 'Goldberg save must restore'
    Assert-True ((Get-Content-Under -Base (Join-Path $newProfile 'AppData\Roaming') -Relative 'SmartSteamEmu\816020\remote\save.dat') -eq 'old-smart') 'SmartSteamEmu save must restore'
    Assert-True ((Get-Content-Under -Base (Join-Path $newProfile 'AppData\Local') -Relative 'GSE Saves\816020\remote\save.sav') -eq 'old-gse-local') 'Local GSE save must restore'
    Assert-True ((Get-Content-Under -Base (Join-Path $sandbox 'NEWOS\Users\Public\Documents') -Relative 'Steam\CODEX\816020\remote\jfsavedata.dat') -eq 'old-codex') 'CODEX scene save must restore to Public\Documents'
    Assert-True ((Get-Content-Under -Base (Join-Path $sandbox 'NEWOS\Users\Public\Documents') -Relative 'Steam\RUNE\816020\remote\save.dat') -eq 'old-rune') 'RUNE scene save must restore'
    Assert-True ((Get-Content-Under -Base (Join-Path $sandbox 'NEWOS\ProgramData') -Relative 'Steam\CODEX\816020\remote\save.dat') -eq 'old-codex-pd') 'ProgramData scene save must restore'
    Assert-True ((Get-Content-Under -Base (Join-Path $newProfile 'AppData\Local') -Relative 'JUMP FORCE\Saved\SaveGames\slot.sav') -eq 'old-ue4') 'UE4 local save must restore (inside the JUMP FORCE folder)'

    # ==========================================================================
    # 4. Idempotent restore
    # ==========================================================================
    $again = Restore-GSVSnapshot -BackupRoot $oldVault -Snapshot $snap.SnapshotPath -TokenTable $newTable -NoRollback
    Assert-True ($again.Failed -eq 0) ("second restore had {0} failures" -f $again.Failed)
    Assert-True ((Get-Content-Under -Base $newUD -Relative 'remote\jfsavedata.dat') -eq 'old-savedata') 'second restore must keep the save intact'
}
finally {
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host ('NEW-OS SELF-TEST FAILED ({0} checks, {1} failure(s))' -f $checks, $failures.Count) -ForegroundColor Red
    foreach ($f in $failures) { Write-Host ("  - {0}" -f $f) -ForegroundColor Red }
    exit 1
}

Write-Host ''
Write-Host ('New-OS self-test passed: {0} checks. SCAN (Steam AppId) -> SAVE (token + AppId) -> RESTORE to a different user/Steam account/drive.' -f $checks) -ForegroundColor Green
