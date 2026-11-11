#requires -Version 5.1
<#
    selftest-structure.ps1 - Validates directory structure and root shims
    for GameSaveVault platform separation.
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$failures = New-Object System.Collections.Generic.List[string]

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
        Write-Host "  FAIL: $Message" -ForegroundColor Red
    } else {
        Write-Host "  OK:   $Message" -ForegroundColor Green
    }
}

Write-Host "=== Testing Directory Structure and Shims ===" -ForegroundColor Cyan

# 1. Check windows/ directory exists
$windowsDir = Join-Path $root 'windows'
Assert-Condition (Test-Path -LiteralPath $windowsDir -PathType Container) "Directory 'windows/' exists"

# 2. Check files in windows/
$expectedWindowsFiles = @(
    'GameSaveVault.ps1',
    'GameSaveVault-GUI.ps1',
    'Install-GameSaveVault.ps1',
    'Install.ps1',
    'Register-ScheduledBackup.ps1'
)

foreach ($f in $expectedWindowsFiles) {
    $p = Join-Path $windowsDir $f
    Assert-Condition (Test-Path -LiteralPath $p -PathType Leaf) "File 'windows/$f' exists"
}

# 3. Check root shims exist
$expectedRootShims = @(
    'GameSaveVault.ps1',
    'GameSaveVault-GUI.ps1',
    'Install.ps1',
    'Install-GameSaveVault.ps1'
)

foreach ($f in $expectedRootShims) {
    $p = Join-Path $root $f
    Assert-Condition (Test-Path -LiteralPath $p -PathType Leaf) "Root shim '$f' exists"
}

# 4. Syntax check on all scripts
$allScripts = @()
if (Test-Path -LiteralPath $windowsDir) {
    $allScripts += (Get-ChildItem -LiteralPath $windowsDir -Filter '*.ps1' | ForEach-Object { $_.FullName })
}
foreach ($f in $expectedRootShims) {
    $allScripts += (Join-Path $root $f)
}

foreach ($scriptPath in $allScripts) {
    if (Test-Path -LiteralPath $scriptPath) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
        $relPath = $scriptPath.Substring($root.Length).TrimStart('/', '\')
        Assert-Condition ($parseErrors.Count -eq 0) "Script '$relPath' has valid PowerShell syntax"
        if ($parseErrors.Count -gt 0) {
            foreach ($err in $parseErrors) {
                Write-Host "    $err" -ForegroundColor Red
            }
        }
    }
}

# 5. Verify root shim forwarding functionality
$rootCli = Join-Path $root 'GameSaveVault.ps1'
if (Test-Path -LiteralPath $rootCli) {
    # Run GameSaveVault.ps1 help via pwsh and verify it forwards to windows/GameSaveVault.ps1
    $env:SystemDrive = 'C:'
    $env:USERPROFILE = [System.IO.Path]::GetTempPath()
    try {
        $output = & pwsh -NoProfile -File $rootCli help 2>&1
        $exitCode = $LASTEXITCODE
        $outputStr = ($output -join "`n")
        $hasUsage = $outputStr -match 'USAGE' -or $outputStr -match 'GameSaveVault'
        Assert-Condition ($exitCode -eq 0 -and $hasUsage) "Root GameSaveVault.ps1 forwards to windows/ and executes successfully"
    } catch {
        Assert-Condition $false "Root GameSaveVault.ps1 execution failed: $($_.Exception.Message)"
    }
}

$rootInstall = Join-Path $root 'Install.ps1'
if (Test-Path -LiteralPath $rootInstall) {
    $installContent = Get-Content -LiteralPath $rootInstall -Raw
    $hasForward = $installContent -match 'windows.*Install\.ps1'
    Assert-Condition $hasForward "Root Install.ps1 forwards to windows/Install.ps1"
}

$rootInstallGsv = Join-Path $root 'Install-GameSaveVault.ps1'
if (Test-Path -LiteralPath $rootInstallGsv) {
    $installGsvContent = Get-Content -LiteralPath $rootInstallGsv -Raw
    $hasForward = $installGsvContent -match 'windows.*Install-GameSaveVault\.ps1'
    Assert-Condition $hasForward "Root Install-GameSaveVault.ps1 forwards to windows/Install-GameSaveVault.ps1"
}

# 6. Check that windows/GameSaveVault.ps1 resolves repo root correctly
$windowsCli = Join-Path $windowsDir 'GameSaveVault.ps1'
if (Test-Path -LiteralPath $windowsCli) {
    $content = Get-Content -LiteralPath $windowsCli -Raw
    $hasRootFix = $content -match '\$script:Root\s*=\s*(Split-Path|\(Resolve-Path)'
    Assert-Condition $hasRootFix "windows/GameSaveVault.ps1 resolves parent repository root for modules/config"
}

$windowsGui = Join-Path $windowsDir 'GameSaveVault-GUI.ps1'
if (Test-Path -LiteralPath $windowsGui) {
    $content = Get-Content -LiteralPath $windowsGui -Raw
    $hasRootFix = $content -match '\$script:Root\s*=\s*(Split-Path|\(Resolve-Path)'
    Assert-Condition $hasRootFix "windows/GameSaveVault-GUI.ps1 resolves parent repository root for modules/config"
}

# 7. Check internal script references in windows/Install.ps1 and windows/Register-ScheduledBackup.ps1
$installScript = Join-Path $windowsDir 'Install.ps1'
if (Test-Path -LiteralPath $installScript) {
    $installContent = Get-Content -LiteralPath $installScript -Raw
    $guiRefResolved = (Join-Path $windowsDir 'GameSaveVault-GUI.ps1')
    $schedRefResolved = (Join-Path $windowsDir 'Register-ScheduledBackup.ps1')
    
    $hasGuiCheck = $installContent -match 'Join-Path \$PSScriptRoot ''GameSaveVault-GUI\.ps1'''
    $hasSchedCheck = $installContent -match 'Join-Path \$PSScriptRoot ''Register-ScheduledBackup\.ps1'''
    
    Assert-Condition ($hasGuiCheck -and (Test-Path -LiteralPath $guiRefResolved)) "windows/Install.ps1 references GameSaveVault-GUI.ps1 in windows/ directory"
    Assert-Condition ($hasSchedCheck -and (Test-Path -LiteralPath $schedRefResolved)) "windows/Install.ps1 references Register-ScheduledBackup.ps1 in windows/ directory"
}

$registerScript = Join-Path $windowsDir 'Register-ScheduledBackup.ps1'
if (Test-Path -LiteralPath $registerScript) {
    $registerContent = Get-Content -LiteralPath $registerScript -Raw
    $cliRefResolved = (Join-Path $windowsDir 'GameSaveVault.ps1')
    $hasCliCheck = $registerContent -match 'Join-Path \$PSScriptRoot ''GameSaveVault\.ps1'''
    Assert-Condition ($hasCliCheck -and (Test-Path -LiteralPath $cliRefResolved)) "windows/Register-ScheduledBackup.ps1 references GameSaveVault.ps1 in windows/ directory"
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "FAILED: $($failures.Count) assertion(s) failed." -ForegroundColor Red
    exit 1
} else {
    Write-Host "ALL CHECKS PASSED!" -ForegroundColor Green
    exit 0
}
