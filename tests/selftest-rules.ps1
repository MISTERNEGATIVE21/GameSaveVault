#requires -Version 5.1
<#
    selftest-rules.ps1
    Verifies the portable save-rule database (config\save-rules.json):

      1. TOKENIZE - an absolute path under a known root becomes %TOKEN%\...,
                    and a path inside the game install becomes %GAMEDIR%\...
      2. SAVE     - the rule is written to JSON with a stable id.
      3. DISCOVER - Resolve-GSVRulePaths finds the real folders on this machine.
      4. SCAN     - Get-GSVGameSaveLocations merges rule paths for the game.
      5. SNAPSHOT - manifest entries carry RuleId / RestoreMode / install names.
      6. NEW PC   - a gamedir rule restores next to the game found on the new
                    machine (different drive/folder) and token paths land in the
                    new user profile.
      7. IMPORT/EXPORT round-trip.
      8. The JSON Schema and the generated document are structurally valid.

    Everything runs in %TEMP%; the real config folder is never touched.
#>

$ErrorActionPreference = 'Stop'

$sandbox = Join-Path $env:TEMP ('gsv-rules-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$env:GSV_CONFIG_DIR = Join-Path $sandbox 'config'

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

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    $script:checks++
    if ([string]$Expected -ne [string]$Actual) {
        $script:failures.Add(("{0} (expected '{1}', got '{2}')" -f $Message, $Expected, $Actual))
    }
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

function Get-Pattern {
    param($PathEntry)
    if ($null -eq $PathEntry) { return '' }
    if ($PathEntry -is [string]) { return [string]$PathEntry }
    return [string]$PathEntry.Pattern
}

function Get-Mode {
    param($PathEntry)
    if ($null -eq $PathEntry) { return '' }
    if ($PathEntry -is [string]) { return 'auto' }
    return [string]$PathEntry.Mode
}

# --- old machine layout -----------------------------------------------------
$oldProfile  = Join-Path $sandbox 'OLDOS\Users\Tester'
$oldLocal    = Join-Path $oldProfile 'AppData\Local'
$oldDocs     = Join-Path $oldProfile 'Documents'
$oldPublic   = Join-Path $sandbox 'OLDOS\Users\Public'
$oldPubDocs  = Join-Path $oldPublic 'Documents'
$oldGames    = Join-Path $sandbox 'OLDOS\Games'
$oldGame     = Join-Path $oldGames 'TestQuest'

# --- new machine layout -----------------------------------------------------
$newProfile  = Join-Path $sandbox 'NEWOS\Users\Nova'
$newLocal    = Join-Path $newProfile 'AppData\Local'
$newDocs     = Join-Path $newProfile 'Documents'
$newPublic   = Join-Path $sandbox 'NEWOS\Users\Public'
$newPubDocs  = Join-Path $newPublic 'Documents'
$newGames    = Join-Path $sandbox 'NEWOS\Games'
$newGame     = Join-Path $newGames 'TestQuest'

$vault = Join-Path $sandbox 'vault'

try {
    # ======================================================================
    # 0. auto-seed from the shipped example
    # ======================================================================
    New-Item -ItemType Directory -Path $env:GSV_CONFIG_DIR -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'config\save-rules.example.json') `
        -Destination (Join-Path $env:GSV_CONFIG_DIR 'save-rules.example.json') -Force
    $seeded = @(Get-GSVRules -Refresh)
    Assert-True ($seeded.Count -ge 2) ("example rules must seed the DB (got {0})" -f $seeded.Count)
    Assert-True (@($seeded | Where-Object { $_.Name -eq 'JUMP FORCE' }).Count -eq 1) 'seeded DB must contain the JUMP FORCE rule'

    # ======================================================================
    # 1. old machine saves
    # ======================================================================
    New-TestFile (Join-Path $oldLocal 'TestQuest\Saved\SaveGames\slot1.sav') 'local-save'
    New-TestFile (Join-Path $oldDocs 'TestQuest\saves\profile.json') '{"level":3}'
    New-TestFile (Join-Path $oldGame 'Saves\portable.sav') 'portable-save'
    New-TestFile (Join-Path $oldPubDocs 'Steam\CODEX\999999\remote\save.dat') 'codex-save'

    $oldTable = Get-GSVTokenTable -Override @{
        'USERPROFILE'   = $oldProfile
        'APPDATA'       = (Join-Path $oldProfile 'AppData\Roaming')
        'LOCALAPPDATA'  = $oldLocal
        'LOCALLOW'      = (Join-Path $oldProfile 'AppData\LocalLow')
        'DOCUMENTS'     = $oldDocs
        'SAVEDGAMES'    = (Join-Path $oldProfile 'Saved Games')
        'PUBLIC'        = $oldPublic
        'PUBLICDOCS'    = $oldPubDocs
        'PROGRAMDATA'   = (Join-Path $sandbox 'OLDOS\ProgramData')
        'STEAMUSERDATA' = (Join-Path $sandbox 'OLDOS\Steam\userdata')
    }

    # The test "machine" only knows its own Games folder.
    $settings = Get-GSVSettings
    $settings.GameScanRoots = @($oldGames)
    Save-GSVSettings -Settings $settings

    # ======================================================================
    # 1. TOKENIZE
    # ======================================================================
    $localEntry = ConvertTo-GSVRulePathEntry -Path (Join-Path $oldLocal 'TestQuest\Saved\SaveGames') -TokenTable $oldTable
    Assert-Equal '%LOCALAPPDATA%\TestQuest\Saved\SaveGames' (Get-Pattern $localEntry) 'LocalAppData path must tokenize'
    Assert-Equal 'auto' (Get-Mode $localEntry) 'tokenized path keeps the requested mode'

    $docsEntry = ConvertTo-GSVRulePathEntry -Path (Join-Path $oldDocs 'TestQuest\saves') -TokenTable $oldTable
    Assert-Equal '%DOCUMENTS%\TestQuest\saves' (Get-Pattern $docsEntry) 'Documents path must tokenize'

    $pubEntry = ConvertTo-GSVRulePathEntry -Path (Join-Path $oldPubDocs 'Steam\CODEX\999999') -TokenTable $oldTable
    Assert-Equal '%PUBLICDOCS%\Steam\CODEX\999999' (Get-Pattern $pubEntry) 'Public Documents path must tokenize'

    $gameEntry = ConvertTo-GSVRulePathEntry -Path (Join-Path $oldGame 'Saves') -InstallDirNames @('TestQuest') -TokenTable $oldTable
    Assert-Equal '%GAMEDIR%\Saves' (Get-Pattern $gameEntry) 'path inside the install must become %GAMEDIR%'
    Assert-Equal 'gamedir' (Get-Mode $gameEntry) 'gamedir path must use gamedir restore mode'

    # ======================================================================
    # 2. SAVE the rule
    # ======================================================================
    $rule = Save-GSVRule -Name 'Test Quest' -Paths @(
        (Join-Path $oldLocal 'TestQuest\Saved\SaveGames'),
        (Join-Path $oldDocs 'TestQuest\saves'),
        (Join-Path $oldPubDocs 'Steam\CODEX\999999'),
        (Join-Path $oldGame 'Saves')
    ) -FilePatterns @('*.sav', '*.json') -FolderPatterns @('SaveGames') `
      -Aliases @('TestQuest') -SteamAppIds @('999999') -InstallDirNames @('TestQuest') `
      -Notes 'selftest rule' -TokenTable $oldTable

    Assert-Equal 'rule-test-quest' $rule.Id 'rule id must be stable and readable'
    Assert-Equal 'Test Quest' $rule.Name 'rule name must round-trip'
    Assert-True (@($rule.Paths).Count -eq 4) ("rule must store 4 paths, got {0}" -f @($rule.Paths).Count)
    Assert-True (@($rule.Paths | Where-Object { (Get-Mode $_) -eq 'gamedir' }).Count -eq 1) 'rule must keep one gamedir path'

    $allRules = @(Get-GSVRules)
    Assert-True (@($allRules | Where-Object { $_.Id -eq 'rule-test-quest' }).Count -eq 1) 'saved rule must be listed'

    $dbPath = Get-GSVRulesPath
    Assert-True (Test-Path -LiteralPath $dbPath) 'rules database file must exist'
    $db = Get-Content -LiteralPath $dbPath -Raw | ConvertFrom-Json
    Assert-Equal 1 $db.schemaVersion 'database schemaVersion must be 1'
    Assert-True (@($db.rules | Where-Object { $_.id -eq 'rule-test-quest' }).Count -eq 1) 'database JSON must contain the rule'
    $storedRule = @($db.rules | Where-Object { $_.id -eq 'rule-test-quest' })[0]
    Assert-True (@($storedRule.paths | Where-Object { $_.pattern -eq '%LOCALAPPDATA%\TestQuest\Saved\SaveGames' }).Count -eq 1) `
        'database must store the tokenized LocalAppData pattern'

    # ======================================================================
    # 3. DISCOVER / RESOLVE on this machine
    # ======================================================================
    $foundDir = Find-GSVRuleGameDir -Names @('TestQuest')
    Assert-Equal $oldGame $foundDir 'the game install folder must be rediscovered'

    $resolved = @(Resolve-GSVRulePaths -Rule $rule -TokenTable $oldTable -Settings $settings -NoSize)
    Assert-True ($resolved.Count -ge 4) ("resolved paths must include all 4 locations, got {0}" -f $resolved.Count)
    Assert-True (@($resolved | Where-Object { $_.ResolvedPath -eq (Join-Path $oldGame 'Saves') -and $_.RestoreMode -eq 'gamedir' }).Count -eq 1) `
        'gamedir path must resolve next to the discovered install'
    Assert-True (@($resolved | Where-Object { $_.ResolvedPath -eq (Join-Path $oldLocal 'TestQuest\Saved\SaveGames') -and $_.RestoreMode -eq 'token' }).Count -eq 1) `
        'LocalAppData path must resolve with token restore mode'
    Assert-True (@($resolved | Where-Object { $_.RuleId -ne 'rule-test-quest' }).Count -eq 0) 'all rule locations must carry RuleId'

    # ======================================================================
    # 4. SCAN merges rule paths into the game
    # ======================================================================
    $game = [pscustomobject]@{
        Id = 'steam-999999'; Name = 'Test Quest'; Source = 'Steam'; AppId = '999999'
        InstallDir = 'TestQuest'; GameDir = $oldGame
    }
    $scan = @(Get-GSVGameSaveLocations -Game $game -TokenTable $oldTable -Settings $settings -NoSize)
    $ruleLocs = @($scan | Where-Object { $_.RuleId -eq 'rule-test-quest' })
    Assert-True ($ruleLocs.Count -ge 4) ("scan must include the rule paths (got {0})" -f $ruleLocs.Count)
    Assert-True (@($ruleLocs | Where-Object { $_.ResolvedPath -eq (Join-Path $oldGame 'Saves') }).Count -eq 1) `
        'scan must include the install-relative save folder'

    # ======================================================================
    # 5. SNAPSHOT keeps the rule metadata
    # ======================================================================
    $existing = @($scan | Where-Object { $_.Exists })
    Assert-True ($existing.Count -ge 4) ("expected 4 existing save locations, got {0}" -f $existing.Count)
    $snap = New-GSVSnapshot -Locations $existing -BackupRoot $vault -Label 'rules'
    Assert-True ($snap.EntryCount -ge 4) ("snapshot must contain the rule saves, got {0}" -f $snap.EntryCount)

    $ruleEntries = @($snap.Manifest.Entries | Where-Object { $_.RuleId -eq 'rule-test-quest' })
    Assert-True ($ruleEntries.Count -ge 4) ("manifest must keep RuleId (got {0})" -f $ruleEntries.Count)
    $gdEntries = @($ruleEntries | Where-Object { $_.RestoreMode -eq 'gamedir' })
    Assert-True ($gdEntries.Count -eq 1) 'manifest must keep the gamedir restore mode'
    if ($gdEntries.Count -eq 1) {
        Assert-Equal 'GAMEDIR' $gdEntries[0].Token 'gamedir entry must be token-anchored'
        Assert-Equal 'Saves' $gdEntries[0].RelativePath 'gamedir entry must keep its relative path'
        Assert-True (@($gdEntries[0].InstallDirNames) -contains 'TestQuest') 'manifest must keep install dir names'
        Assert-True (@($gdEntries[0].FilePatterns) -contains '*.sav') 'manifest must keep file patterns'
    }

    # ======================================================================
    # 6. RESTORE on a "new PC": game moved, new user profile
    # ======================================================================
    Remove-Item -LiteralPath $oldGame -Recurse -Force
    New-Item -ItemType Directory -Path $newGame -Force | Out-Null

    $settings = Get-GSVSettings
    $settings.GameScanRoots = @($newGames)
    Save-GSVSettings -Settings $settings

    $newTable = Get-GSVTokenTable -Override @{
        'USERPROFILE'   = $newProfile
        'APPDATA'       = (Join-Path $newProfile 'AppData\Roaming')
        'LOCALAPPDATA'  = $newLocal
        'LOCALLOW'      = (Join-Path $newProfile 'AppData\LocalLow')
        'DOCUMENTS'     = $newDocs
        'SAVEDGAMES'    = (Join-Path $newProfile 'Saved Games')
        'PUBLIC'        = $newPublic
        'PUBLICDOCS'    = $newPubDocs
        'PROGRAMDATA'   = (Join-Path $sandbox 'NEWOS\ProgramData')
        'STEAMUSERDATA' = (Join-Path $sandbox 'NEWOS\Steam\userdata')
    }

    $restore = Restore-GSVSnapshot -BackupRoot $vault -Snapshot $snap.SnapshotPath -TokenTable $newTable -NoRollback
    Assert-True ($restore.Failed -eq 0) ("new-PC restore had {0} failures" -f $restore.Failed)
    Assert-True ((Get-Content-Under -Base $newGame -Relative 'Saves\portable.sav') -eq 'portable-save') `
        'gamedir save must land inside the game install found on the new PC'
    Assert-True ((Get-Content-Under -Base $newLocal -Relative 'TestQuest\Saved\SaveGames\slot1.sav') -eq 'local-save') `
        'token save must land in the new user LocalAppData'
    Assert-True ((Get-Content-Under -Base $newDocs -Relative 'TestQuest\saves\profile.json') -eq '{"level":3}') `
        'token save must land in the new user Documents'
    Assert-True ((Get-Content-Under -Base $newPubDocs -Relative 'Steam\CODEX\999999\remote\save.dat') -eq 'codex-save') `
        'scene save must land in the new Public Documents'
    Assert-True (-not (Test-Path -LiteralPath $oldGame)) 'the old install folder must not be recreated'

    # ======================================================================
    # 7. EXPORT / REMOVE / IMPORT round-trip
    # ======================================================================
    $exportPath = Join-Path $sandbox 'exported-rules.json'
    $null = Export-GSVRules -Path $exportPath
    Assert-True (Test-Path -LiteralPath $exportPath) 'export must create a JSON file'
    $exported = Get-Content -LiteralPath $exportPath -Raw | ConvertFrom-Json
    Assert-True (@($exported.rules | Where-Object { $_.id -eq 'rule-test-quest' }).Count -eq 1) 'export must contain the rule'

    $removed = Remove-GSVRule -Id 'rule-test-quest'
    Assert-Equal 1 $removed 'removing the rule must report one deletion'
    Assert-True (@(Get-GSVRules | Where-Object { $_.Id -eq 'rule-test-quest' }).Count -eq 0) 'rule must be gone from the DB'

    $imported = Import-GSVRules -Path $exportPath
    Assert-True ($imported -ge 1) ("import must report at least one rule, got {0}" -f $imported)
    $back = @(Get-GSVRules | Where-Object { $_.Id -eq 'rule-test-quest' })
    Assert-True ($back.Count -eq 1) 'rule must be restored by import'
    if ($back.Count -eq 1) {
        Assert-True (@($back[0].Paths | Where-Object { (Get-Pattern $_) -eq '%GAMEDIR%\Saves' }).Count -eq 1) `
            'import must preserve the gamedir pattern'
        Assert-Equal 'imported' $back[0].Source 'imported rules must be tagged'
    }

    # ======================================================================
    # 8. JSON Schema sanity
    # ======================================================================
    $schemaPath = Get-GSVRulesSchemaPath
    Assert-True (Test-Path -LiteralPath $schemaPath) 'schema file must exist'
    $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    Assert-Equal 1 $schema.properties.schemaVersion.const 'schema must pin schemaVersion 1'
    $required = @($schema.definitions.rule.required)
    foreach ($r in @('id', 'name', 'paths')) {
        Assert-True ($required -contains $r) ("schema rule must require '{0}'" -f $r)
    }
    $modes = @($schema.definitions.path.properties.mode.enum)
    foreach ($m in @('auto', 'token', 'gamedir', 'absolute')) {
        Assert-True ($modes -contains $m) ("schema must allow restore mode '{0}'" -f $m)
    }
    $patternDoc = $schema.definitions.path.properties.pattern.description
    Assert-True ($patternDoc -match '%GAMEDIR%') 'schema must document the %GAMEDIR% token'

    # Validate the generated DB against the important schema rules by hand.
    $doc = Get-Content -LiteralPath (Get-GSVRulesPath) -Raw | ConvertFrom-Json
    $valid = $true
    foreach ($r in @($doc.rules)) {
        if (-not $r.id -or -not $r.name -or $null -eq $r.paths) { $valid = $false; break }
        foreach ($p in @($r.paths)) {
            if (-not $p.pattern) { $valid = $false; break }
            if ($modes -notcontains [string]$p.mode) { $valid = $false; break }
        }
    }
    Assert-True $valid 'every rule in the generated DB must satisfy the schema essentials'
}
finally {
    if (Test-Path -LiteralPath $sandbox) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
    $env:GSV_CONFIG_DIR = $null
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host ('RULES SELF-TEST FAILED ({0} checks, {1} failure(s))' -f $checks, $failures.Count) -ForegroundColor Red
    foreach ($f in $failures) { Write-Host ("  - {0}" -f $f) -ForegroundColor Red }
    exit 1
}

Write-Host ''
Write-Host ('Rules self-test passed: {0} checks. tokenize -> save -> discover -> scan -> snapshot -> new-PC restore -> import/export -> schema.' -f $checks) -ForegroundColor Green
