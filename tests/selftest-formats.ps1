#requires -Version 5.1
<#
    selftest-formats.ps1
    Verifies restore "formats":

      profile  - saves land in the current (new) profile, current Steam account
      verbatim - saves land in the ORIGINAL absolute path (old drive + old user)
      folder   - saves land under <Root>\<TOKEN>\<relative path>

    The save-rule database is redirected to a throw-away config folder so the
    real config\save-rules.json can never influence (or be touched by) the test.
#>

$ErrorActionPreference = 'Stop'
$env:GSV_CONFIG_DIR = Join-Path $env:TEMP ('gsv-formatscfg-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

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

$sandbox = Join-Path $env:TEMP ('gsv-formats-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$oldProfile = Join-Path $sandbox 'C\Users\OldUser'
$oldPublic = Join-Path $sandbox 'C\Users\Public'
$vault = Join-Path $sandbox 'vault'

$oldAccount = '76561198654321098'
$newAccount = '76561198012345678'
$appid = '816020'

try {
    # --- old machine: three JUMP FORCE save flavours ------------------------
    # 1. UE4 save inside the normal per-user folder
    New-TestFile (Join-Path $oldProfile 'AppData\Local\JUMP FORCE\Saved\SaveGames\slot.sav') 'ue4-save'
    # 2. Steam userdata (account id must be remapped on the new OS)
    New-TestFile (Join-Path $sandbox ('C\Steam\userdata\{0}\{1}\remote\jfsavedata.dat' -f $oldAccount, $appid)) 'steam-save'
    # 3. scene / crack save in Public Documents
    New-TestFile (Join-Path $oldPublic 'Documents\Steam\CODEX\816020\remote\jfsavedata.dat') 'codex-save'
    # 4. CPY save in Documents
    New-TestFile (Join-Path $oldProfile 'Documents\CPY_SAVES\816020\save.sav') 'cpy-save'

    $oldTable = Get-GSVTokenTable -Override @{
        'USERPROFILE'   = $oldProfile
        'APPDATA'       = (Join-Path $oldProfile 'AppData\Roaming')
        'LOCALAPPDATA'  = (Join-Path $oldProfile 'AppData\Local')
        'LOCALLOW'      = (Join-Path $oldProfile 'AppData\LocalLow')
        'DOCUMENTS'     = (Join-Path $oldProfile 'Documents')
        'SAVEDGAMES'    = (Join-Path $oldProfile 'Saved Games')
        'PUBLIC'        = $oldPublic
        'PUBLICDOCS'    = (Join-Path $oldPublic 'Documents')
        'PROGRAMDATA'   = (Join-Path $sandbox 'C\ProgramData')
        'STEAMUSERDATA' = (Join-Path $sandbox 'C\Steam\userdata')
    }

    $game = [pscustomobject]@{
        Id = "steam-$appid"; Name = 'JUMP FORCE'; Source = 'Steam'
        AppId = $appid; InstallDir = 'JUMP FORCE'
        GameDir = (Join-Path $sandbox 'C\Steam\steamapps\common\JUMP FORCE')
    }
    $entry = @(Get-GSVCatalog | Where-Object { $_.Id -eq 'jumpforce' })
    Assert-True ($entry.Count -eq 1) 'catalog must have a Jump Force entry'
    $jf = $entry[0]
    $locs = @(Get-GSVGameSaveLocations -Game $game -CatalogEntry $jf -TokenTable $oldTable -NoSize -IncludeMissing)
    $existing = @($locs | Where-Object { $_.Exists })
    Write-Host ("  scan found {0} location(s) ({1} existing)" -f $locs.Count, $existing.Count)

    foreach ($l in $locs) { Write-Host ("    {0}\{1} exists={2} -> {3}" -f $l.Token, $l.RelativePath, $l.Exists, $l.ResolvedPath) }
    Assert-True ($existing.Count -ge 3) ("expected at least 3 existing locations, got {0}" -f $existing.Count)

    $snap = New-GSVSnapshot -Locations $existing -BackupRoot $vault -Label 'formats'
    Assert-True ($snap.EntryCount -ge 3) ("snapshot must have >=3 entries, got {0}" -f $snap.EntryCount)

    # ==========================================================================
    # format: folder
    # ==========================================================================
    $staged = Join-Path $sandbox 'staged'
    $r = Restore-GSVSnapshot -BackupRoot $vault -Snapshot $snap.SnapshotPath -RestoreFormat folder -RestoreRoot $staged -NoRollback
    Assert-True ($r.Failed -eq 0) ("folder restore had {0} failures" -f $r.Failed)
    Assert-True ($r.Format -eq 'folder') 'result must report Format=folder'
    Assert-True ((Get-Content-Under -Base $staged -Relative 'LOCALAPPDATA\JUMP FORCE\Saved\SaveGames\slot.sav') -eq 'ue4-save') `
        'folder format must keep LOCALAPPDATA\<relative> structure'
    Assert-True ((Get-Content-Under -Base $staged -Relative ("STEAMUSERDATA\{0}\{1}\remote\jfsavedata.dat" -f $oldAccount, $appid)) -eq 'steam-save') `
        'folder format must keep STEAMUSERDATA\<account>\<appid> structure'
    Assert-True ((Get-Content-Under -Base $staged -Relative 'PUBLICDOCS\Steam\CODEX\816020\remote\jfsavedata.dat') -eq 'codex-save') `
        'folder format must keep PUBLICDOCS\<relative> structure'

    # ==========================================================================
    # format: verbatim - original absolute layout (old drive + old user)
    # ==========================================================================
    $r2 = Restore-GSVSnapshot -BackupRoot $vault -Snapshot $snap.SnapshotPath -RestoreFormat verbatim -NoRollback
    Assert-True ($r2.Failed -eq 0) ("verbatim restore had {0} failures" -f $r2.Failed)
    Assert-True ((Get-Content-Under -Base (Join-Path $oldProfile 'AppData\Local') -Relative 'JUMP FORCE\Saved\SaveGames\slot.sav') -eq 'ue4-save') `
        'verbatim restore must write to the original absolute path'
    Assert-True ((Get-Content-Under -Base (Join-Path $sandbox 'C\Steam\userdata\76561198654321098\816020') -Relative 'remote\jfsavedata.dat') -eq 'steam-save') `
        'verbatim restore must not remap the Steam account id'
    Assert-True ((Get-Content-Under -Base (Join-Path $oldPublic 'Documents\Steam\CODEX\816020') -Relative 'remote\jfsavedata.dat') -eq 'codex-save') `
        'verbatim restore must keep the original Public Documents path'

    # ==========================================================================
    # format: profile - new user, new Steam account id
    # ==========================================================================
    $newProfile = Join-Path $sandbox 'NEWOS\Users\NewUser'
    $newSteam = Join-Path $sandbox 'NEWOS\Steam'
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
    $r3 = Restore-GSVSnapshot -BackupRoot $vault -Snapshot $snap.SnapshotPath -TokenTable $newTable -NoRollback
    Assert-True ($r3.Failed -eq 0) ("profile restore had {0} failures" -f $r3.Failed)
    Assert-True ($r3.Format -eq 'profile') 'result must report Format=profile'
    Assert-True ((Get-Content-Under -Base (Join-Path $newProfile 'AppData\Local') -Relative 'JUMP FORCE\Saved\SaveGames\slot.sav') -eq 'ue4-save') `
        'profile restore must write into the new user LocalAppData'
    Assert-True ((Get-Content-Under -Base (Join-Path $newProfile 'Documents') -Relative 'CPY_SAVES\816020\save.sav') -eq 'cpy-save') `
        'profile restore must write into the new user Documents'
    Assert-True ((Get-Content-Under -Base (Join-Path $sandbox 'NEWOS\Users\Public\Documents') -Relative 'Steam\CODEX\816020\remote\jfsavedata.dat') -eq 'codex-save') `
        'profile restore must write into the new Public Documents'
    Assert-True ((Get-Content-Under -Base (Join-Path $newSteam ('userdata\{0}\{1}' -f $newAccount, $appid)) -Relative 'remote\jfsavedata.dat') -eq 'steam-save') `
        'profile restore must remap the Steam account id to the current one'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $newSteam ('userdata\{0}' -f $oldAccount)))) `
        'profile restore must not recreate the old Steam account folder'
}
finally {
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($env:GSV_CONFIG_DIR -and (Test-Path -LiteralPath $env:GSV_CONFIG_DIR)) {
        Remove-Item -LiteralPath $env:GSV_CONFIG_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }
    $env:GSV_CONFIG_DIR = $null
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host ('FORMATS SELF-TEST FAILED ({0} checks, {1} failure(s))' -f $checks, $failures.Count) -ForegroundColor Red
    foreach ($f in $failures) { Write-Host ("  - {0}" -f $f) -ForegroundColor Red }
    exit 1
}

Write-Host ''
Write-Host ('Formats self-test passed: {0} checks. profile / verbatim (original C: layout) / folder restore.' -f $checks) -ForegroundColor Green
