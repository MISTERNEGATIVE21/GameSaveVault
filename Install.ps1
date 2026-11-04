<#
.SYNOPSIS
    Installs GameSaveVault shortcuts and an optional daily backup task.

.EXAMPLE
    .\Install.ps1
    .\Install.ps1 -ScheduledTask -Time 21:30
    .\Install.ps1 -NoShortcut
#>

[CmdletBinding()]
param(
    [switch]$NoShortcut,
    [switch]$ScheduledTask,
    [string]$Time = '20:00'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$gui = Join-Path $root 'GameSaveVault-GUI.ps1'

if (-not (Test-Path -LiteralPath $gui)) {
    throw "GameSaveVault-GUI.ps1 not found next to Install.ps1."
}

$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $ps)) { $ps = 'powershell.exe' }

function New-Shortcut {
    param([string]$Path, [string]$Target, [string]$Arguments, [string]$WorkingDirectory, [string]$Description)

    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($Path)
    $sc.TargetPath = $Target
    $sc.Arguments = $Arguments
    $sc.WorkingDirectory = $WorkingDirectory
    $sc.Description = $Description
    $sc.IconLocation = "$env:SystemRoot\System32\shell32.dll,167"
    $sc.Save()
}

if (-not $NoShortcut) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnk = Join-Path $desktop 'GameSaveVault.lnk'
    New-Shortcut -Path $lnk -Target $ps `
        -Arguments ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $gui + '"') `
        -WorkingDirectory $root -Description 'Game save backup and restore'
    Write-Host "Desktop shortcut created: $lnk" -ForegroundColor Green

    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    if (Test-Path -LiteralPath $startMenu) {
        $lnk2 = Join-Path $startMenu 'GameSaveVault.lnk'
        New-Shortcut -Path $lnk2 -Target $ps `
            -Arguments ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $gui + '"') `
            -WorkingDirectory $root -Description 'Game save backup and restore'
        Write-Host "Start menu shortcut created: $lnk2" -ForegroundColor Green
    }
}

if ($ScheduledTask) {
    & (Join-Path $root 'Register-ScheduledBackup.ps1') -Time $Time
}

Write-Host ''
Write-Host 'Installation complete.' -ForegroundColor Green
Write-Host 'Open the app from the desktop shortcut, or run:' -ForegroundColor Gray
Write-Host ('  powershell -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'GameSaveVault.ps1')) -ForegroundColor Gray
