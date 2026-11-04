#requires -Version 5.1
<#
    selftest.ps1 - end-to-end sanity test for GameSaveVault.
    Creates a fake "old profile" and "new profile" in %TEMP%, backs up the old
    one, restores it into the new one, and verifies the bytes match.
    Nothing outside %TEMP% is touched.
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules\GSV.Core.psm1') -Force
Import-Module (Join-Path $root 'modules\GSV.Vault.psm1') -Force

$sandbox = Join-Path $env:TEMP ('gsv-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$oldProfile = Join-Path $sandbox 'old-profile'
$newProfile = Join-Path $sandbox 'new-profile'
$vault = Join-Path $sandbox 'vault'

function New-FakeSave {
    param([string]$Base, [string]$Relative, [string]$Content)
    $p = Join-Path $Base $Relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $p) -Force | Out-Null
    Set-Content -LiteralPath $p -Value $Content -Encoding UTF8
}

try {
    Write-Host '=== GameSaveVault self-test ===' -ForegroundColor Cyan
    Write-Host "Sandbox: $sandbox"

    # Fake saves in the "old" profile
    New-FakeSave -Base $oldProfile -Relative 'Documents\My Games\FakeGame\Saves\slot1.sav' -Content 'old-save-slot1'
    New-FakeSave -Base $oldProfile -Relative 'AppData\Roaming\FakeGame\settings.ini' -Content 'old-settings'
    New-FakeSave -Base $oldProfile -Relative 'AppData\LocalLow\FakeStudio\FakeGame\profile.json' -Content '{"level":7}'
    New-FakeSave -Base $oldProfile -Relative 'Saved Games\FakeGame\checkpoint.sav' -Content 'old-checkpoint'

    $oldTable = Get-GSVTokenTable -Override @{
        'USERPROFILE'  = $oldProfile
        'APPDATA'      = (Join-Path $oldProfile 'AppData\Roaming')
        'LOCALAPPDATA' = (Join-Path $oldProfile 'AppData\Local')
        'LOCALLOW'     = (Join-Path $oldProfile 'AppData\LocalLow')
        'DOCUMENTS'    = (Join-Path $oldProfile 'Documents')
        'SAVEDGAMES'   = (Join-Path $oldProfile 'Saved Games')
    }

    $game = [pscustomobject]@{
        Id = 'fake'; Name = 'Fake Game'; Source = 'SelfTest'; AppId = ''; GameDir = ''; Exists = $true
    }
    $catalogEntry = [pscustomobject]@{
        Id = 'fake'; Name = 'Fake Game'; Aliases = @(); Engine = 'Test'; SteamAppIds = @()
        Paths = @(
            '%DOCUMENTS%\My Games\FakeGame',
            '%APPDATA%\FakeGame',
            '%LOCALLOW%\FakeStudio\FakeGame',
            '%SAVEDGAMES%\FakeGame'
        )
        RegistryKeys = @(); Notes = ''
    }

    $locs = @(Get-GSVGameSaveLocations -Game $game -CatalogEntry $catalogEntry -TokenTable $oldTable -NoSize)
    if ($locs.Count -lt 4) { throw "Expected 4 save locations, got $($locs.Count)" }
    Write-Host ("  discovered {0} save locations" -f $locs.Count) -ForegroundColor Green

    $snap = New-GSVSnapshot -Locations $locs -BackupRoot $vault -Label 'selftest'
    if ($snap.TotalFiles -lt 4) { throw "Expected at least 4 backed-up files, got $($snap.TotalFiles)" }
    Write-Host ("  snapshot: {0} files, {1}" -f $snap.TotalFiles, (Format-GSVSize $snap.TotalBytes)) -ForegroundColor Green

    $newTable = Get-GSVTokenTable -Override @{
        'USERPROFILE'  = $newProfile
        'APPDATA'      = (Join-Path $newProfile 'AppData\Roaming')
        'LOCALAPPDATA' = (Join-Path $newProfile 'AppData\Local')
        'LOCALLOW'     = (Join-Path $newProfile 'AppData\LocalLow')
        'DOCUMENTS'    = (Join-Path $newProfile 'Documents')
        'SAVEDGAMES'   = (Join-Path $newProfile 'Saved Games')
    }

    $restore = Restore-GSVSnapshot -BackupRoot $vault -Snapshot $snap.SnapshotPath -TokenTable $newTable -NoRollback
    if ($restore.Failed -gt 0) { throw "Restore reported $($restore.Failed) failures." }

    $checks = @(
        @{ Rel = 'Documents\My Games\FakeGame\Saves\slot1.sav';         Text = 'old-save-slot1' }
        @{ Rel = 'AppData\Roaming\FakeGame\settings.ini';               Text = 'old-settings' }
        @{ Rel = 'AppData\LocalLow\FakeStudio\FakeGame\profile.json';   Text = '{"level":7}' }
        @{ Rel = 'Saved Games\FakeGame\checkpoint.sav';                 Text = 'old-checkpoint' }
    )
    foreach ($c in $checks) {
        $p = Join-Path $newProfile $c.Rel
        if (-not (Test-Path -LiteralPath $p)) { throw "Missing after restore: $p" }
        $actual = (Get-Content -LiteralPath $p -Raw).Trim()
        if ($actual -ne $c.Text) { throw "Content mismatch in $p : '$actual' != '$($c.Text)'" }
        Write-Host ("  verified {0}" -f $c.Rel) -ForegroundColor Green
    }

    # Dry-run restore into a third profile must not write anything.
    $dryProfile = Join-Path $sandbox 'dry-profile'
    $dryTable = Get-GSVTokenTable -Override @{
        'USERPROFILE'  = $dryProfile
        'APPDATA'      = (Join-Path $dryProfile 'AppData\Roaming')
        'LOCALAPPDATA' = (Join-Path $dryProfile 'AppData\Local')
        'LOCALLOW'     = (Join-Path $dryProfile 'AppData\LocalLow')
        'DOCUMENTS'    = (Join-Path $dryProfile 'Documents')
        'SAVEDGAMES'   = (Join-Path $dryProfile 'Saved Games')
    }
    $dry = Restore-GSVSnapshot -BackupRoot $vault -Snapshot $snap.SnapshotPath -TokenTable $dryTable -DryRun
    if (Test-Path -LiteralPath $dryProfile) { throw 'Dry-run created files in the target profile.' }
    Write-Host ("  dry-run listed {0} entries and wrote nothing" -f ($dry.DryRun)) -ForegroundColor Green

    Write-Host ''
    Write-Host 'SELF-TEST PASSED' -ForegroundColor Green
    exit 0
} catch {
    Write-Host ''
    Write-Host "SELF-TEST FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
} finally {
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}
