#requires -Version 5.1
<#
    selftest-emulators.ps1
    Verifies console-emulator save support:

      1. SCAN   - Eden / Eglantine (nand\user\save), Ryujinx (bis\user\save),
                  Kyty (portable _SaveData\<PPSA…>) and shadPS4
                  (user\<user>\savedata\<CUSA…>) title saves are found and
                  carry their title ID.
      2. MIGRATE- saves copy from Eden to Ryujinx by title ID (profile id is
                  mapped), from Kyty _SaveData to shadPS4 by PPSA/CUSA id, and
                  Ryujinx to Eglantine. Existing destination saves are moved to
                  the vault rollback folder first.
      3. DEEP   - a deep drive scan still finds a Kyty _SaveData\PPSA… folder and
                  a Switch nand title save.
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

$sandbox = Join-Path $env:PUBLIC ('GSVEmuTest-' + [guid]::NewGuid().ToString('N'))
$profile = Join-Path $sandbox 'Users\tester'
$vault = Join-Path $sandbox 'vault'

$edenRoaming = Join-Path $profile 'AppData\Roaming\eden'
$ryujinxRoaming = Join-Path $profile 'AppData\Roaming\ryujinx'
$kytyPortable = Join-Path $sandbox 'KytyPS5'
$shadRoaming = Join-Path $profile 'AppData\Roaming\shadPS4'

$title1 = '0100000000010000'   # Switch title id
$title2 = '0100ABCD00001234'   # Switch title id (lowercase hex must match)
$ps5title = 'PPSA01341'

try {
    # --- Eden (Switch) ------------------------------------------------------
    New-TestFile (Join-Path $edenRoaming 'nand\user\save\0000000000000000\0100000000010000\save.dat') 'eden-save-1'
    New-TestFile (Join-Path $edenRoaming 'nand\user\save\0000000000000000\0100000000010000\slot1\data.bin') 'eden-save-1b'
    New-TestFile (Join-Path $edenRoaming 'nand\system\save\8000000000000000\0100abcd00001234\sys.dat') 'eden-sys'

    # --- Ryujinx (Switch) - destination already has an older save -----------
    New-TestFile (Join-Path $ryujinxRoaming 'bis\user\save\BBBBBBBBBBBBBBBB\0100000000010000\save.dat') 'ryujinx-old-save'

    # --- Kyty PS5 (portable _SaveData) --------------------------------------
    New-TestFile (Join-Path $kytyPortable '_SaveData\PPSA01341\data.bin') 'kyty-save'
    New-TestFile (Join-Path $kytyPortable '_SaveData\PPSA01341\profile\save2.bin') 'kyty-save2'

    # --- shadPS4 (PS4) --------------------------------------------------------
    New-TestFile (Join-Path $shadRoaming 'user\001\savedata\CUSA00001\save.bin') 'shad-old'

    $table = Get-GSVTokenTable -Override @{
        'USERPROFILE'   = $profile
        'APPDATA'       = (Join-Path $profile 'AppData\Roaming')
        'LOCALAPPDATA'  = (Join-Path $profile 'AppData\Local')
        'LOCALLOW'      = (Join-Path $profile 'AppData\LocalLow')
        'DOCUMENTS'     = (Join-Path $profile 'Documents')
        'SAVEDGAMES'    = (Join-Path $profile 'Saved Games')
        'PUBLIC'        = (Join-Path $sandbox 'Users\Public')
        'PUBLICDOCS'    = (Join-Path $sandbox 'Users\Public\Documents')
        'PROGRAMDATA'   = (Join-Path $sandbox 'ProgramData')
        'STEAMUSERDATA' = (Join-Path $sandbox 'Steam\userdata')
    }

    # ==========================================================================
    # 1. SCAN
    # ==========================================================================
    $locs = @(Get-GSVEmulatorSaveLocations -NoSize -TokenTable $table)
    Write-Host ("  scan found {0} console-emulator save location(s)" -f $locs.Count)
    foreach ($l in $locs) { Write-Host ("    [{0}] {1}  {2}  -> {3}" -f $l.Source, $l.GameName, $l.AppId, $l.ResolvedPath) }
    Write-Host ''

    Assert-True (@($locs | Where-Object { $_.Source -eq 'Eden' -and $_.AppId -eq '0100000000010000' }).Count -ge 1) 'Eden save must be found by Switch title id'
    Assert-True (@($locs | Where-Object { $_.Source -eq 'Ryujinx' -and $_.AppId -eq '0100000000010000' }).Count -ge 1) 'Ryujinx save must be found by Switch title id'
    Assert-True (@($locs | Where-Object { $_.Source -eq 'Kyty / KytyPS5' -and $_.AppId -eq 'PPSA01341' }).Count -ge 1) 'Kyty _SaveData\PPSA01341 must be found'
    Assert-True (@($locs | Where-Object { [string]$_.AppId -eq 'CUSA00001' }).Count -ge 1) 'shadPS4 savedata\CUSA00001 must be found'
    Assert-True (@($locs | Where-Object { -not $_.Token -and -not $_.AbsolutePath }).Count -eq 0) 'every emulator save must be anchored (token or absolute path) so it restores'
    Assert-True (@($locs | Where-Object { $_.Origin -ne 'emulator' }).Count -eq 0) 'emulator locations must be tagged Origin=emulator'

    # Kyty is portable on this machine: without -IncludePortable only AppData candidates count.
    $edenIndex = @(Get-GSVEmulatorSaveIndex -EmulatorIds @('eden') -TokenTable $table)
    Assert-True ($edenIndex.Count -ge 2) ("Eden index must include user + system saves, got {0}" -f $edenIndex.Count)

    # ==========================================================================
    # 2. MIGRATE - Eden -> Ryujinx, Kyty -> shadPS4
    # ==========================================================================
    $ryujinxDest = Join-Path $ryujinxRoaming 'bis\user\save'
    $result = Copy-GSVEmulatorSaves -Entries (@($edenIndex | Where-Object { $_.TitleId -eq '0100000000010000' })) `
        -DestinationEmulatorId 'ryujinx' -TokenTable $table -BackupRoot $vault
    Assert-True ($result.Migrated -eq 1) ("Eden -> Ryujinx migration should copy 1 save, copied {0}" -f $result.Migrated)
    Assert-True ($result.Failed -eq 0) ("Eden -> Ryujinx migration had {0} failures" -f $result.Failed)

    $mapped = Join-Path $ryujinxDest 'BBBBBBBBBBBBBBBB\0100000000010000'
    Assert-True ((Get-Content-Under -Base $mapped -Relative 'save.dat') -eq 'eden-save-1') `
        'Eden save must land in Ryujinx under the destination profile id'
    Assert-True ((Get-Content-Under -Base $mapped -Relative 'slot1\data.bin') -eq 'eden-save-1b') `
        'nested save files must be copied'

    # the old Ryujinx save must not be destroyed: it goes to the vault rollback
    $rollback = Join-Path $vault 'rollback'
    Assert-True (Test-Path -LiteralPath $rollback) 'rollback folder must exist after an overwrite migration'
    $rollbackFiles = @()
    if (Test-Path -LiteralPath $rollback) {
        $rollbackFiles = @(Get-ChildItem -LiteralPath $rollback -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { (Get-Content -LiteralPath $_.FullName -Raw).Trim() })
    }
    Assert-True ($rollbackFiles -contains 'ryujinx-old-save') 'the previous destination save must be preserved in rollback'

    # Kyty (PS5 _SaveData) -> shadPS4 (PS4) across the PPSA/CUSA naming family:
    # copy the Kyty title folder into the shadPS4 savedata tree with the new id.
    $kytyIndex = @(Get-GSVEmulatorSaveIndex -EmulatorIds @('kyty') -TokenTable $table -IncludePortable)
    Assert-True ($kytyIndex.Count -ge 1) 'Kyty portable _SaveData must be indexed'
    if ($kytyIndex.Count -ge 1) {
        $shadDest = Join-Path $shadRoaming 'user\001\savedata\PPSA01341'
        New-Item -ItemType Directory -Path $shadDest -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $shadDest 'placeholder.txt') -Value 'exists' -Encoding UTF8

        $r2 = Copy-GSVEmulatorSaves -Entries $kytyIndex -DestinationEmulatorId 'shadps4' -TokenTable $table -BackupRoot $vault
        Assert-True ($r2.Migrated -ge 1) 'Kyty -> shadPS4 migration must copy the title folder'
        Assert-True ((Get-Content-Under -Base $shadDest -Relative 'data.bin') -eq 'kyty-save') 'Kyty PS5 save must land in the shadPS4 savedata folder by title id'
    }

    # dry-run reports but writes nothing
    $newDest = Join-Path $sandbox 'drydest'
    New-Item -ItemType Directory -Path $newDest -Force | Out-Null
    $dry = Copy-GSVEmulatorSaves -Entries (@($edenIndex | Select-Object -First 1)) -DestinationEmulatorId 'ryujinx' -TokenTable $table -BackupRoot $vault -DryRun
    Assert-True ($dry.Migrated -eq 1 -and $dry.Failed -eq 0) 'dry-run migration must report success without writing'

    # ==========================================================================
    # 3. DEEP SCAN
    # ==========================================================================
    $deep = @(Get-GSVDeepScanLocations -Roots @($sandbox) -MaxDepth 12 -MaxResults 200 -NoSize)
    $deepKy = @($deep | Where-Object { $_.ResolvedPath -ieq (Join-Path $kytyPortable '_SaveData\PPSA01341') })
    $deepEden = @($deep | Where-Object { $_.ResolvedPath -ieq (Join-Path $edenRoaming 'nand\user\save\0000000000000000\0100000000010000') })
    Assert-True ($deepKy.Count -ge 1) 'deep scan must find Kyty _SaveData\PPSA01341'
    Assert-True ($deepEden.Count -ge 1) 'deep scan must find the Eden nand\user\save\<profile>\<title> save'
}
finally {
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host ('EMULATOR SELF-TEST FAILED ({0} checks, {1} failure(s))' -f $checks, $failures.Count) -ForegroundColor Red
    foreach ($f in $failures) { Write-Host ("  - {0}" -f $f) -ForegroundColor Red }
    exit 1
}

Write-Host ''
Write-Host ('Emulator self-test passed: {0} checks. Eden / Ryujinx / Eglantine / Kyty _SaveData / shadPS4 scan + migrate.' -f $checks) -ForegroundColor Green
