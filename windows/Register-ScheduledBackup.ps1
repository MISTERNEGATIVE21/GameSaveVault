<#
.SYNOPSIS
    Registers (or removes) a daily GameSaveVault backup task.

.EXAMPLE
    .\Register-ScheduledBackup.ps1
    .\Register-ScheduledBackup.ps1 -Time 21:30 -RunNow
    .\Register-ScheduledBackup.ps1 -Unregister
#>

[CmdletBinding()]
param(
    [string]$Time = '20:00',
    [string]$TaskName = 'GameSaveVault Daily Backup',
    [switch]$RunNow,
    [switch]$Unregister
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $PSScriptRoot 'GameSaveVault.ps1'
if (-not (Test-Path -LiteralPath $cli)) {
    $cli = Join-Path $root 'GameSaveVault.ps1'
}

if ($Unregister) {
    & schtasks.exe /Delete /TN $TaskName /F
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Scheduled task removed: $TaskName" -ForegroundColor Green
    } else {
        Write-Host "Could not remove task '$TaskName' (it may not exist)." -ForegroundColor Yellow
    }
    exit $LASTEXITCODE
}

if (-not (Test-Path -LiteralPath $cli)) { throw "GameSaveVault.ps1 not found next to this script." }

# schtasks is used instead of Register-ScheduledTask because it works for the
# current user without an elevated PowerShell session.
$action = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $cli + '" backup -All -Quiet'

& schtasks.exe /Create /SC DAILY /TN $TaskName /TR $action /ST $Time /F
if ($LASTEXITCODE -ne 0) {
    throw "schtasks failed with exit code $LASTEXITCODE."
}

Write-Host "Daily backup scheduled at $Time : $TaskName" -ForegroundColor Green
Write-Host 'The vault location comes from config\settings.json (BackupRoot).' -ForegroundColor DarkGray

if ($RunNow) {
    & schtasks.exe /Run /TN $TaskName
    Write-Host 'Task started now.' -ForegroundColor Green
}
