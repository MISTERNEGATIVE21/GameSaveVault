#requires -Version 5.1
<#
    selftest-scandb.ps1
    Verifies the scan database + portable .gsvdb database:

      1. folders can be listed for selection
      2. scanning chosen roots stores locations in config\scan-database.json
      3. rescanning the same root replaces its old results (no duplicates)
      4. a scan-database.json can be imported on another PC
      5. a portable .gsvdb contains the save files and the scan database
      6. restore-db restores the contents and imports the scan database
#>

$ErrorActionPreference = 'Stop'
$env:GSV_CONFIG_DIR = Join-Path $env:TEMP ('gsv-scandbcfg-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

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
    param([string]$Path, [string]$Content = 'save')
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function New-Location {
    param([string]$GameName, [string]$Relative, [string]$Resolved)
    return [pscustomobject]@{
        GameId = ('test-' + ($GameName -replace '[^A-Za-z0-9]', ''))
        GameName = $GameName
        Source = 'Deep scan'
        AppId = ''
        InstallDirHint = ''
        Token = 'DOCUMENTS'
        RelativePath = $Relative
        AbsolutePath = $Resolved
        ResolvedPath = $Resolved
        Kind = 'Directory'
        RegistryKey = ''
        Note = 'selftest'
        Origin = 'deep-scan'
        RuleId = ''
        RestoreMode = ''
        InstallDirNames = @()
        FilePatterns = @()
        FileCount = $null
        Bytes = $null
    }
}

$sandbox = Join-Path $env:TEMP ('gsv-scandb-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$save1 = Join-Path $sandbox 'source\Alpha Game\Saves'
$save2 = Join-Path $sandbox 'source\Beta Game\Saves'
$vault = Join-Path $sandbox 'vault'
$bundle = Join-Path $sandbox 'portable\GameSaveVault-test.gsvdb'
$restoreFolder = Join-Path $sandbox 'restored'

try {
    New-TestFile (Join-Path $save1 'slot1.sav') 'alpha-save'
    New-TestFile (Join-Path $save2 'slot2.sav') 'beta-save'

    # --- 1. available folders ------------------------------------------------
    $candidates = @(Get-GSVScanRootCandidates)
    Assert-True ($candidates.Count -gt 0) 'Get-GSVScanRootCandidates should list at least one folder'
    $bad = @($candidates | Where-Object { -not $_.Path -or -not $_.Display })
    Assert-True ($bad.Count -eq 0) 'every scan candidate needs a Path and Display text'

    # --- 2. store scan results ----------------------------------------------
    $loc1 = New-Location 'Alpha Game' 'Alpha Game\Saves' $save1
    $loc2 = New-Location 'Beta Game' 'Beta Game\Saves' $save2

    $r1 = Update-GSVScanDatabase -Roots @($sandbox) -Locations @($loc1)
    Assert-True (Test-Path -LiteralPath (Get-GSVScanDatabasePath)) 'scan-database.json should be created'
    Assert-True ($r1.Total -eq 1) ("expected 1 stored location, got {0}" -f $r1.Total)

    $db = Read-GSVScanDatabase
    Assert-True ($null -ne $db) 'Read-GSVScanDatabase should return the saved database'
    Assert-True (@($db.Roots).Count -eq 1) 'the scanned root should be recorded'
    Assert-True (@($db.Locations).Count -eq 1) 'the discovered location should be recorded'

    # --- 3. rescanning the same root replaces its results -------------------
    $r2 = Update-GSVScanDatabase -Roots @($sandbox) -Locations @($loc1, $loc2)
    Assert-True ($r2.Total -eq 2) ("expected 2 stored locations, got {0}" -f $r2.Total)

    $r3 = Update-GSVScanDatabase -Roots @($sandbox) -Locations @($loc1)
    Assert-True ($r3.Total -eq 1) ("rescan should replace old results, got {0}" -f $r3.Total)

    $r4 = Update-GSVScanDatabase -Roots @($sandbox) -Locations @($loc1, $loc2)
    Assert-True ($r4.Total -eq 2) ("expected 2 stored locations again, got {0}" -f $r4.Total)

    # --- 4. import a scan database on another PC ----------------------------
    $incoming = [pscustomobject]@{
        Version = 1
        Roots = @([pscustomobject]@{ Path = $sandbox; LocationCount = 1; ScannedUtc = (Get-Date).ToUniversalTime().ToString('o') })
        Locations = @(
            [pscustomobject]@{
                GameId = 'test-gamma'
                GameName = 'Gamma Game'
                Source = 'Deep scan'
                AppId = ''
                InstallDirHint = ''
                Token = 'DOCUMENTS'
                RelativePath = 'Gamma Game\Saves'
                AbsolutePath = ''
                ResolvedPath = ''
                Kind = 'Directory'
                RegistryKey = ''
                Note = 'imported'
                Origin = 'deep-scan'
                RuleId = ''
                RestoreMode = ''
                InstallDirNames = @()
                FilePatterns = @()
                FileCount = $null
                Bytes = $null
                ScanRoot = $sandbox
            }
        )
    }
    $incomingPath = Join-Path $sandbox 'other-pc-scan-database.json'
    Set-Content -LiteralPath $incomingPath -Value ($incoming | ConvertTo-Json -Depth 10) -Encoding UTF8

    $import = Import-GSVScanDatabaseFile -Path $incomingPath
    Assert-True ($import.Imported -eq 1) ("expected 1 imported location, got {0}" -f $import.Imported)
    Assert-True ($import.Total -eq 3) ("expected 3 total locations after import, got {0}" -f $import.Total)

    $all = @(Get-GSVScanDatabaseLocations)
    $existing = @(Get-GSVScanDatabaseLocations -OnlyExisting)
    Assert-True ($all.Count -eq 3) 'Get-GSVScanDatabaseLocations should return all stored locations'
    Assert-True ($existing.Count -eq 2) ("only two imported paths exist, got {0}" -f $existing.Count)

    # --- 5. portable database ------------------------------------------------
    $snap = New-GSVSnapshot -Locations @($loc1, $loc2) -BackupRoot $vault -Label 'selftest'
    Assert-True ($snap.TotalFiles -eq 2) ("snapshot should contain 2 files, got {0}" -f $snap.TotalFiles)

    $out = New-GSVPortableDatabase -BackupRoot $vault -Snapshot 'latest' -OutputPath $bundle -IncludeScanDatabase
    Assert-True (Test-Path -LiteralPath $out.Path) 'the portable .gsvdb file should be created'
    Assert-True ($out.Bytes -gt 0) 'the portable .gsvdb file should not be empty'
    Assert-True ($out.ScanDatabase) 'the scan database should be included in the portable file'

    $info = Get-GSVPortableDatabaseInfo -Path $out.Path
    Assert-True ($info.EntryCount -eq 2) ("portable database should have 2 entries, got {0}" -f $info.EntryCount)
    Assert-True ($info.TotalFiles -eq 2) ("portable database should have 2 files, got {0}" -f $info.TotalFiles)
    Assert-True ($info.HasScanDb) 'Get-GSVPortableDatabaseInfo should detect the embedded scan database'

    # --- 6. restore the contents on a "new PC" ------------------------------
    # Forget the local scan database first, like a fresh Windows install.
    Remove-Item -LiteralPath (Get-GSVScanDatabasePath) -Force -ErrorAction SilentlyContinue
    Assert-True (-not (Test-Path -LiteralPath (Get-GSVScanDatabasePath))) 'scan database should be gone before restore'

    $rr = Restore-GSVPortableDatabase -BundlePath $out.Path -BackupRoot $vault -RestoreFormat folder -RestoreRoot $restoreFolder
    Assert-True ($rr.Restored -eq 2) ("expected 2 restored entries, got {0}" -f $rr.Restored)
    Assert-True ($rr.Failed -eq 0) ("expected 0 failed entries, got {0}" -f $rr.Failed)
    Assert-True ($rr.ImportedDatabase) 'restore should import the embedded scan database'

    $restored1 = Join-Path $restoreFolder 'DOCUMENTS\Alpha Game\Saves\slot1.sav'
    $restored2 = Join-Path $restoreFolder 'DOCUMENTS\Beta Game\Saves\slot2.sav'
    Assert-True (Test-Path -LiteralPath $restored1) 'Alpha Game save should be restored under the folder'
    Assert-True (Test-Path -LiteralPath $restored2) 'Beta Game save should be restored under the folder'
    if (Test-Path -LiteralPath $restored1) {
        Assert-True ((Get-Content -LiteralPath $restored1 -Raw).Trim() -eq 'alpha-save') 'restored Alpha save should keep its contents'
    }

    $dbAfter = Read-GSVScanDatabase
    Assert-True ($null -ne $dbAfter) 'restore should recreate the scan database'
    if ($dbAfter) {
        Assert-True (@($dbAfter.Locations).Count -eq 3) 'restore should import all stored scan locations'
    }
} catch {
    $failures.Add("unexpected error: $($_.Exception.Message)")
} finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $env:GSV_CONFIG_DIR -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -eq 0) {
    Write-Host ("PASS: scan database + portable database ({0} checks)" -f $checks) -ForegroundColor Green
    exit 0
}

Write-Host ("FAIL: {0} of {1} checks failed" -f $failures.Count, $checks) -ForegroundColor Red
foreach ($f in $failures) { Write-Host ('  - ' + $f) -ForegroundColor Red }
exit 1
