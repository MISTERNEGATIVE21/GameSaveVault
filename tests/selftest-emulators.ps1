#requires -Version 5.1
<#
    selftest-emulators.ps1
    Verifies console-emulator save support:

      1. SCAN   - Switch (nand/bis), 3DS (sdmc\Nintendo 3DS), PSP, PS3, Vita,
                  Xbox 360, Wii U, Wii, Kyty (portable _SaveData), shadPS4 and
                  shared memory-card folders are found with their title IDs.
      2. MIGRATE- saves copy by title ID between emulators of the same console
                  (Switch, PS5/PS4 and 3DS; profile ids are remapped), and an
                  existing destination save is moved to the vault rollback
                  folder first.
      3. DEEP   - a deep drive scan still finds a Kyty _SaveData\PPSA… folder and
                  a Switch nand title save.
#>

$ErrorActionPreference = 'Stop'
# Isolate the settings / save-rule database from the real config folder.
$env:GSV_CONFIG_DIR = Join-Path $env:TEMP ('gsv-emucfg-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
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
$azaharRoaming = Join-Path $profile 'AppData\Roaming\Azahar'
$citraRoaming = Join-Path $profile 'AppData\Roaming\Citra'
$ppssppRoaming = Join-Path $profile 'AppData\Roaming\PPSSPP'
$rpcs3Roaming = Join-Path $profile 'AppData\Roaming\rpcs3'
$vitaRoaming = Join-Path $profile 'AppData\Roaming\Vita3K'
$xeniaRoaming = Join-Path $profile 'AppData\Roaming\Xenia'
$cemuRoaming = Join-Path $profile 'AppData\Roaming\Cemu'
$dolphinRoaming = Join-Path $profile 'AppData\Roaming\Dolphin Emulator'
$duckRoaming = Join-Path $profile 'AppData\Roaming\DuckStation'

$title1 = '0100000000010000'   # Switch title id
$title2 = '0100ABCD00001234'   # Switch title id (lowercase hex must match)
$ps5title = 'PPSA01341'

# 3DS: id0 / id1 are console profile folders, the title id is split 8+8 hex.
$dsId0 = '00000000000000000000000000000000'
$dsId1 = '11111111111111111111111111111111'
$dsTitle = '000400000017C100'
$dsHigh = $dsTitle.Substring(0, 8)
$dsLow = $dsTitle.Substring(8, 8)
$citraId0 = '22222222222222222222222222222222'
$citraId1 = '33333333333333333333333333333333'

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

    # --- Azahar / Citra (3DS) ------------------------------------------------
    New-TestFile (Join-Path $azaharRoaming ("sdmc\Nintendo 3DS\{0}\{1}\title\{2}\{3}\data\00000001.sav" -f $dsId0, $dsId1, $dsHigh, $dsLow)) 'azahar-save'
    # Citra already has a different title; migration must keep Citra's own profile ids.
    New-TestFile (Join-Path $citraRoaming ("sdmc\Nintendo 3DS\{0}\{1}\title\00040000\00000001\data\00000002.sav" -f $citraId0, $citraId1)) 'citra-old'

    # --- PPSSPP (PSP) --------------------------------------------------------
    New-TestFile (Join-Path $ppssppRoaming 'PSP\SAVEDATA\ULUS10041\SAVEDATA.BIN') 'ppsspp-save'

    # --- RPCS3 (PS3) ---------------------------------------------------------
    New-TestFile (Join-Path $rpcs3Roaming 'dev_hdd0\home\00000001\savedata\BLUS30001\SAVEDATA0.PS3') 'rpcs3-save'

    # --- Vita3K (PS Vita) ----------------------------------------------------
    New-TestFile (Join-Path $vitaRoaming 'ux0\user\00\savedata\PCSE00001\savedata0.bin') 'vita-save'

    # --- Xenia (Xbox 360) ----------------------------------------------------
    New-TestFile (Join-Path $xeniaRoaming 'content\0000000000000000\4D5307E6\00000001\save.bin') 'xenia-save'

    # --- Cemu (Wii U) --------------------------------------------------------
    New-TestFile (Join-Path $cemuRoaming 'mlc01\usr\save\0005000010101C00\user\save.dat') 'cemu-save'

    # --- Dolphin (Wii) -------------------------------------------------------
    New-TestFile (Join-Path $dolphinRoaming 'Wii\titles\SMNE01\data\save.bin') 'dolphin-save'

    # --- shared memory-card folder (DuckStation) -----------------------------
    New-TestFile (Join-Path $duckRoaming 'memcards\memcard1.mcd') 'duck-save'

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

    # --- new emulator families ------------------------------------------------
    Assert-True (@($locs | Where-Object { $_.Source -eq 'Azahar' -and $_.AppId -eq $dsTitle }).Count -ge 1) 'Azahar 3DS save must be found by title id'
    Assert-True (@($locs | Where-Object { $_.Source -eq 'Citra' -and $_.AppId -eq '0004000000000001' }).Count -ge 1) 'Citra 3DS save must be found by title id'
    Assert-True (@($locs | Where-Object { $_.Source -eq 'PPSSPP' -and $_.AppId -eq 'ULUS10041' }).Count -ge 1) 'PPSSPP PSP save must be found'
    Assert-True (@($locs | Where-Object { $_.Source -eq 'RPCS3' -and $_.AppId -eq 'BLUS30001' }).Count -ge 1) 'RPCS3 PS3 save must be found'
    Assert-True (@($locs | Where-Object { $_.Source -eq 'Vita3K' -and $_.AppId -eq 'PCSE00001' }).Count -ge 1) 'Vita3K save must be found'
    Assert-True (@($locs | Where-Object { $_.Source -eq 'Xenia' -and $_.AppId -eq '4D5307E6' }).Count -ge 1) 'Xenia Xbox 360 save must be found'
    Assert-True (@($locs | Where-Object { $_.Source -eq 'Cemu' -and $_.AppId -eq '0005000010101C00' }).Count -ge 1) 'Cemu Wii U save must be found'
    Assert-True (@($locs | Where-Object { $_.Source -eq 'Dolphin' -and $_.AppId -eq 'SMNE01' }).Count -ge 1) 'Dolphin Wii save must be found'
    Assert-True (@($locs | Where-Object { $_.Source -eq 'DuckStation' -and $_.ResolvedPath -like '*\memcards' }).Count -ge 1) 'shared DuckStation memory-card folder must be found'

    Assert-True (@($locs | Where-Object { -not $_.Token -and -not $_.AbsolutePath }).Count -eq 0) 'every emulator save must be anchored (token or absolute path) so it restores'
    Assert-True (@($locs | Where-Object { $_.Origin -ne 'emulator' }).Count -eq 0) 'emulator locations must be tagged Origin=emulator'
    Assert-True (@(Get-GSVEmulatorDefinitions).Count -ge 18) 'the emulator database should cover the major console families'

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
    # Keep the portable walk's real-machine hits out of the test: only migrate the
    # sandbox copy so the run is hermetic and never reads live game saves.
    $kytyIndex = @(Get-GSVEmulatorSaveIndex -EmulatorIds @('kyty') -TokenTable $table -IncludePortable |
        Where-Object { $_.Path.StartsWith($sandbox, [StringComparison]::OrdinalIgnoreCase) })
    Assert-True ($kytyIndex.Count -ge 1) 'Kyty portable _SaveData must be indexed'
    if ($kytyIndex.Count -ge 1) {
        $shadDest = Join-Path $shadRoaming 'user\001\savedata\PPSA01341'
        New-Item -ItemType Directory -Path $shadDest -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $shadDest 'placeholder.txt') -Value 'exists' -Encoding UTF8

        $r2 = Copy-GSVEmulatorSaves -Entries $kytyIndex -DestinationEmulatorId 'shadps4' -TokenTable $table -BackupRoot $vault
        Assert-True ($r2.Migrated -ge 1) 'Kyty -> shadPS4 migration must copy the title folder'
        Assert-True ((Get-Content-Under -Base $shadDest -Relative 'data.bin') -eq 'kyty-save') 'Kyty PS5 save must land in the shadPS4 savedata folder by title id'
    }

    # Azahar (3DS) -> Citra: the 16-hex title id is split into high/low folders
    # and the destination's own id0\id1 profile is reused.
    $azaharIndex = @(Get-GSVEmulatorSaveIndex -EmulatorIds @('azahar') -TokenTable $table)
    Assert-True ($azaharIndex.Count -ge 1) 'Azahar 3DS save must be indexed'
    if ($azaharIndex.Count -ge 1) {
        $r3 = Copy-GSVEmulatorSaves -Entries $azaharIndex -DestinationEmulatorId 'citra' -TokenTable $table -BackupRoot $vault
        Assert-True ($r3.Migrated -ge 1) 'Azahar -> Citra migration must copy the 3DS title'
        Assert-True ($r3.Failed -eq 0) ("Azahar -> Citra migration had {0} failure(s)" -f $r3.Failed)
        $citraDest = Join-Path $citraRoaming ("sdmc\Nintendo 3DS\{0}\{1}\title\{2}\{3}" -f $citraId0, $citraId1, $dsHigh, $dsLow)
        Assert-True ((Get-Content-Under -Base $citraDest -Relative 'data\00000001.sav') -eq 'azahar-save') `
            'Azahar 3DS save must land under Citra''s own profile and title folders'
    }

    # console families: PS4/PS5 share save data, unrelated consoles do not
    $allDefs = @(Get-GSVEmulatorDefinitions)
    $familyOf = { param($id) Get-GSVEmulatorFamily -Definition (@($allDefs | Where-Object { $_.Id -eq $id })[0]) }
    Assert-True ((& $familyOf 'kyty') -eq (& $familyOf 'shadps4')) 'PS4 and PS5 emulators must share a save family'
    Assert-True ((& $familyOf 'eden') -ne (& $familyOf 'azahar')) 'Switch and 3DS must be different save families'
    $refused = $false
    try {
        Copy-GSVEmulatorSaves -Entries (@($edenIndex | Select-Object -First 1)) -DestinationEmulatorId 'ppsspp' -TokenTable $table -BackupRoot $vault -DryRun | Out-Null
    } catch { $refused = $true }
    Assert-True $refused 'migrating between different consoles must be refused'

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
Write-Host ('Emulator self-test passed: {0} checks. Switch / 3DS / PSP / PS3 / Vita / Xbox 360 / Wii U / Wii / PS5 / PS4 scan + migrate.' -f $checks) -ForegroundColor Green
