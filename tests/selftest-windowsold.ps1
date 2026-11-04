#requires -Version 5.1
<#
    selftest-windowsold.ps1
    Builds a fake C:\Windows.old tree, imports it into a temp vault, restores it
    into a fake "new" profile, and verifies the result. Nothing real is touched.
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules\GSV.Core.psm1') -Force
Import-Module (Join-Path $root 'modules\GSV.Vault.psm1') -Force

$sandbox = Join-Path $env:TEMP ('gsv-oldtest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$oldRoot = Join-Path $sandbox 'Windows.old'
$oldProfile = Join-Path $oldRoot 'Users\Tester'
$newProfile = Join-Path $sandbox 'new-profile'
$vault = Join-Path $sandbox 'vault'

function New-FakeSave {
    param([string]$Base, [string]$Relative, [string]$Content)
    $p = Join-Path $Base $Relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $p) -Force | Out-Null
    Set-Content -LiteralPath $p -Value $Content -Encoding UTF8
}

try {
    Write-Host '=== GameSaveVault Windows.old self-test ===' -ForegroundColor Cyan
    Write-Host "Sandbox: $sandbox"

    New-FakeSave -Base $oldProfile -Relative 'Documents\My Games\FakeGame\Saves\slot1.sav' -Content 'old-slot1'
    New-FakeSave -Base $oldProfile -Relative 'Saved Games\FakeGame\checkpoint.sav' -Content 'old-checkpoint'
    New-FakeSave -Base $oldProfile -Relative 'AppData\LocalLow\FakeStudio\FakeGame\profile.json' -Content '{"level":7}'
    New-FakeSave -Base $oldProfile -Relative 'AppData\Roaming\FakeGame\Saves\settings.ini' -Content 'old-settings'
    New-FakeSave -Base $oldProfile -Relative 'AppData\Local\FakeGame\Saved\SaveGames\auto.sav' -Content 'old-auto'
    New-FakeSave -Base $oldProfile -Relative 'AppData\Roaming\Goldberg SteamEmu Saves\12345\remote\save.dat' -Content 'old-goldberg'
    New-FakeSave -Base $oldRoot -Relative 'Users\Public\Documents\Steam\CODEX\999\save.dat' -Content 'old-codex'
    New-FakeSave -Base $oldProfile -Relative 'AppData\Local\Steam\userdata\111\222\remote\save.dat' -Content 'old-steam'
    New-FakeSave -Base $oldRoot -Relative 'ProgramData\Steam\CODEX\999\save.dat' -Content 'old-codex-pd'

    $locs = @(Get-GSVWindowsOldLocations -Root $oldRoot -NoSize)
    Write-Host ("  discovered {0} locations in fake Windows.old" -f $locs.Count) -ForegroundColor Green
    if ($locs.Count -lt 7) { throw "Expected at least 7 locations, got $($locs.Count)" }

    $result = Import-GSVFromWindowsOld -BackupRoot $vault -WindowsOldRoot $oldRoot -NoRestore
    if (-not $result.Snapshot) { throw 'No snapshot produced.' }
    Write-Host ("  imported {0} files into {1}" -f $result.Snapshot.TotalFiles, $result.Snapshot.SnapshotPath) -ForegroundColor Green
    if ($result.Snapshot.TotalFiles -lt 7) { throw "Expected at least 7 imported files, got $($result.Snapshot.TotalFiles)" }

    $newTable = Get-GSVTokenTable -Override @{
        'USERPROFILE'   = $newProfile
        'APPDATA'       = (Join-Path $newProfile 'AppData\Roaming')
        'LOCALAPPDATA'  = (Join-Path $newProfile 'AppData\Local')
        'LOCALLOW'      = (Join-Path $newProfile 'AppData\LocalLow')
        'DOCUMENTS'     = (Join-Path $newProfile 'Documents')
        'SAVEDGAMES'    = (Join-Path $newProfile 'Saved Games')
        'PUBLIC'        = (Join-Path $sandbox 'new-public')
        'PUBLICDOCS'    = (Join-Path $sandbox 'new-public\Documents')
        'PROGRAMDATA'   = (Join-Path $sandbox 'new-programdata')
        'STEAMUSERDATA' = (Join-Path $sandbox 'new-steam\userdata')
    }

    $restore = Restore-GSVSnapshot -BackupRoot $vault -Snapshot $result.Snapshot.SnapshotPath -TokenTable $newTable -NoRollback
    if ($restore.Failed -gt 0) { throw "Restore had $($restore.Failed) failures." }

    $checks = @(
        @{ Path = (Join-Path $newProfile 'Documents\My Games\FakeGame\Saves\slot1.sav'); Text = 'old-slot1' }
        @{ Path = (Join-Path $newProfile 'Saved Games\FakeGame\checkpoint.sav');           Text = 'old-checkpoint' }
        @{ Path = (Join-Path $newProfile 'AppData\LocalLow\FakeStudio\FakeGame\profile.json'); Text = '{"level":7}' }
        @{ Path = (Join-Path $newProfile 'AppData\Roaming\FakeGame\Saves\settings.ini');   Text = 'old-settings' }
        @{ Path = (Join-Path $newProfile 'AppData\Local\FakeGame\Saved\SaveGames\auto.sav'); Text = 'old-auto' }
        @{ Path = (Join-Path $newProfile 'AppData\Roaming\Goldberg SteamEmu Saves\12345\remote\save.dat'); Text = 'old-goldberg' }
    )
    foreach ($c in $checks) {
        if (-not (Test-Path -LiteralPath $c.Path)) { throw "Missing after restore: $($c.Path)" }
        $actual = (Get-Content -LiteralPath $c.Path -Raw).Trim()
        if ($actual -ne $c.Text) { throw "Mismatch in $($c.Path): '$actual' != '$($c.Text)'" }
        Write-Host ("  verified {0}" -f $c.Path.Substring($sandbox.Length + 1)) -ForegroundColor Green
    }

    Write-Host ''
    Write-Host 'WINDOWS.OLD SELF-TEST PASSED' -ForegroundColor Green
    exit 0
} catch {
    Write-Host ''
    Write-Host "WINDOWS.OLD SELF-TEST FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
} finally {
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}
