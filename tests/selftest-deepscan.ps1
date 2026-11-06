#requires -Version 5.1
<#
    selftest-deepscan.ps1
    Builds a fake Windows-like tree containing CPY / GSE / Goldberg / scene /
    UWP / LocalLow / Steam userdata / My Games saves and checks that
    Get-GSVDeepScanLocations finds them.

    The sandbox is created under C:\Users\Public (not %TEMP%) because the deep
    scan intentionally prunes the AppData\Local\Temp subtree.
#>

$ErrorActionPreference = 'Stop'
# Isolate the settings / save-rule database from the real config folder.
$env:GSV_CONFIG_DIR = Join-Path $env:TEMP ('gsv-deepcfg-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules\GSV.Core.psm1') -Force

$failures = New-Object System.Collections.Generic.List[string]
$checks = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:checks++
    if (-not $Condition) { $script:failures.Add($Message) }
}

function New-TestFile {
    param([string]$Path)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $Path -Value 'save' -Encoding ASCII
}

$sandbox = Join-Path $env:PUBLIC ('GSVDeepTest-' + [guid]::NewGuid().ToString('N'))
$user = Join-Path $sandbox 'Users\tester'
$appdata = Join-Path $user 'AppData\Roaming'
$local = Join-Path $user 'AppData\Local'
$localLow = Join-Path $user 'AppData\LocalLow'
$docs = Join-Path $user 'Documents'
$saved = Join-Path $user 'Saved Games'
$programData = Join-Path $sandbox 'ProgramData'
$publicDocs = Join-Path $sandbox 'Users\Public\Documents'

$expected = @(
    (Join-Path $appdata 'GSE Saves\816020'),
    (Join-Path $appdata 'Goldberg SteamEmu Saves\1227500'),
    (Join-Path $local 'CPY_SAVES\1984490'),
    (Join-Path $docs 'CPY_SAVES\816020'),
    (Join-Path $localLow "Aggro Crab\Another Crab's Treasure"),
    (Join-Path $local 'Packages\Microsoft.Game_8wekyb3d8bbwe\SystemAppData\wgs'),
    (Join-Path $local 'Packages\Some.Game_8wekyb3d8bbwe\LocalState'),
    (Join-Path $programData 'Steam'),
    (Join-Path $publicDocs 'Steam'),
    (Join-Path $docs 'My Games\Skyrim Special Edition'),
    (Join-Path $saved 'CD Projekt Red\Cyberpunk 2077'),
    (Join-Path $sandbox 'Steam\userdata\111111\816020')
)

try {
    # --- fake save tree -----------------------------------------------------
    New-TestFile (Join-Path $appdata 'GSE Saves\816020\remote\save.dat')
    New-TestFile (Join-Path $appdata 'GSE Saves\settings\config.ini')          # must be ignored
    New-TestFile (Join-Path $appdata 'Goldberg SteamEmu Saves\1227500\remote\slot.sav')
    New-TestFile (Join-Path $local 'CPY_SAVES\1984490\save.sav')
    New-TestFile (Join-Path $docs 'CPY_SAVES\816020\save.sav')
    New-TestFile (Join-Path $localLow "Aggro Crab\Another Crab's Treasure\save.sav")
    New-TestFile (Join-Path $local 'Packages\Microsoft.Game_8wekyb3d8bbwe\SystemAppData\wgs\save.dat')
    New-TestFile (Join-Path $local 'Packages\Some.Game_8wekyb3d8bbwe\LocalState\Saves\slot.sav')
    New-TestFile (Join-Path $programData 'Steam\CODEX\1778820\remote\save.sav')
    New-TestFile (Join-Path $publicDocs 'Steam\RUNE\816020\remote\save.sav')
    New-TestFile (Join-Path $docs 'My Games\Skyrim Special Edition\Saves\save1.ess')
    New-TestFile (Join-Path $saved 'CD Projekt Red\Cyberpunk 2077\sav.dat')
    New-TestFile (Join-Path $sandbox 'Steam\userdata\111111\816020\remote\save.sav')
    New-TestFile (Join-Path $appdata 'NotAGame\random.txt')                     # must be ignored

    # --- run the deep scan --------------------------------------------------
    $results = @(Get-GSVDeepScanLocations -Roots @($sandbox) -MaxDepth 12 -MaxResults 200 -NoSize)

    Assert-True ($results.Count -ge $expected.Count) ("expected at least {0} results, got {1}" -f $expected.Count, $results.Count)

    foreach ($e in $expected) {
        $hit = @($results | Where-Object { $_.ResolvedPath -ieq $e })
        Assert-True ($hit.Count -ge 1) ("missing expected save location: {0}" -f $e)
    }

    $bad = @($results | Where-Object { $_.ResolvedPath -match '(?i)\\GSE Saves\\settings($|\\)' })
    Assert-True ($bad.Count -eq 0) 'GSE settings folder should not be reported as a save location'

    $bad2 = @($results | Where-Object { $_.ResolvedPath -match '(?i)\\NotAGame($|\\)' })
    Assert-True ($bad2.Count -eq 0) 'random non-game folder should not be reported'

    # --- catalog contains Jump Force ---------------------------------------
    $jf = @(Get-GSVCatalog | Where-Object { $_.Id -eq 'jumpforce' })
    Assert-True ($jf.Count -eq 1) 'catalog is missing the Jump Force entry'
    if ($jf.Count -eq 1) {
        Assert-True (@($jf[0].SteamAppIds) -contains 816020) 'Jump Force Steam app id should be 816020'
        $joined = (@($jf[0].Paths) -join '|')
        Assert-True ($joined -match '816020') 'Jump Force catalog paths should include app id 816020'
        Assert-True ($joined -match 'GSE Saves') 'Jump Force catalog paths should include GSE saves'
        Assert-True ($joined -match 'CPY_SAVES') 'Jump Force catalog paths should include CPY saves'
    }

    # --- deep results are restorable (token or absolute anchor) ------------
    $unanchored = @($results | Where-Object { -not $_.Token -and -not $_.AbsolutePath })
    Assert-True ($unanchored.Count -eq 0) 'every deep-scan result must have a token or absolute path'
}
finally {
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    Write-Host ("DEEP SCAN SELFTEST FAILED ({0} checks, {1} failure(s))" -f $checks, $failures.Count) -ForegroundColor Red
    foreach ($f in $failures) { Write-Host ("  - {0}" -f $f) -ForegroundColor Red }
    exit 1
}

Write-Host ("Deep scan self-test passed: {0} checks." -f $checks) -ForegroundColor Green
exit 0
