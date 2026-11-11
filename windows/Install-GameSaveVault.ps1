#requires -Version 5.1
<#
.SYNOPSIS
    One-line installer for GameSaveVault.

.DESCRIPTION
    Downloads the latest GameSaveVault from GitHub, installs it into
    %LOCALAPPDATA%\GameSaveVault (by default), and runs Install.ps1 to create
    the desktop / Start-menu shortcuts.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/MISTERNEGATIVE21/GameSaveVault/main/Install-GameSaveVault.ps1 | iex"

.EXAMPLE
    $s = irm 'https://raw.githubusercontent.com/MISTERNEGATIVE21/GameSaveVault/main/Install-GameSaveVault.ps1'
    & ([scriptblock]::Create($s)) -ScheduledTask -Time 21:30
#>

[CmdletBinding()]
param(
    [string]$InstallDir = $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'GameSaveVault' } else { Join-Path $env:USERPROFILE 'GameSaveVault' }),
    [string]$Repo = 'MISTERNEGATIVE21/GameSaveVault',
    [string]$Branch = 'main',
    [switch]$NoShortcut,
    [switch]$ScheduledTask,
    [string]$Time = '20:00'
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Text)
    Write-Host ('  ' + $Text) -ForegroundColor Gray
}

$zipUrl = "https://github.com/$Repo/archive/refs/heads/$Branch.zip"
$temp = Join-Path $env:TEMP ('gsv-install-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$zip = Join-Path $temp 'GameSaveVault.zip'

try {
    Write-Host ''
    Write-Host 'GameSaveVault installer' -ForegroundColor Cyan
    Write-Step "Repository : $Repo ($Branch)"
    Write-Step "Install to : $InstallDir"

    # Windows PowerShell 5.1 may default to TLS 1.0, which GitHub rejects.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch { }

    New-Item -ItemType Directory -Path $temp -Force | Out-Null

    Write-Step 'Downloading the latest release...'
    Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing

    Write-Step 'Extracting...'
    Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force

    $src = Get-ChildItem -LiteralPath $temp -Directory |
        Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName 'GameSaveVault.ps1')) -or
            (Test-Path -LiteralPath (Join-Path $_.FullName 'windows\GameSaveVault.ps1'))
        } |
        Select-Object -First 1
    if (-not $src) {
        throw 'The downloaded archive does not contain GameSaveVault.ps1.'
    }

    if (-not (Test-Path -LiteralPath $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    Write-Step "Copying files to $InstallDir..."
    Copy-Item -Path (Join-Path $src.FullName '*') -Destination $InstallDir -Recurse -Force

    $installer = Join-Path $InstallDir 'windows\Install.ps1'
    if (-not (Test-Path -LiteralPath $installer)) {
        $installer = Join-Path $InstallDir 'Install.ps1'
    }
    if (-not (Test-Path -LiteralPath $installer)) {
        throw "Install.ps1 was not found in $InstallDir."
    }

    Write-Step 'Creating shortcuts...'
    $installArgs = @{}
    if ($NoShortcut) { $installArgs['NoShortcut'] = $true }
    if ($ScheduledTask) {
        $installArgs['ScheduledTask'] = $true
        $installArgs['Time'] = $Time
    }
    & $installer @installArgs

    Write-Host ''
    Write-Host 'GameSaveVault is installed.' -ForegroundColor Green
    Write-Host ('  Folder : {0}' -f $InstallDir)
    Write-Host ('  CLI    : powershell -ExecutionPolicy Bypass -File "{0}" scan' -f (Join-Path $InstallDir 'GameSaveVault.ps1'))
    Write-Host ('  GUI    : powershell -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $InstallDir 'GameSaveVault-GUI.ps1'))
    Write-Host ''
}
catch {
    Write-Host ''
    Write-Host ('Installation failed: {0}' -f $_.Exception.Message) -ForegroundColor Red
    Write-Host 'You can also download the ZIP manually from:' -ForegroundColor Yellow
    Write-Host ('  https://github.com/{0}' -f $Repo)
    throw
}
finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
