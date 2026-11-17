<#
.SYNOPSIS
    GameSaveVault install root forwarding shim for Windows PowerShell.
.DESCRIPTION
    Forwards execution to windows/Install-GameSaveVault.ps1 preserving all arguments and exit code.
    When run through "irm ... | iex" there is no script root, so the real installer
    is downloaded from the repository instead.
#>

$scriptPath = if ($PSScriptRoot) { Join-Path (Join-Path $PSScriptRoot 'windows') 'Install-GameSaveVault.ps1' } else { $null }
if ($scriptPath -and (Test-Path -LiteralPath $scriptPath)) {
    & $scriptPath @args
    if ($null -ne $LASTEXITCODE) {
        exit $LASTEXITCODE
    }
    return
}

$url = 'https://raw.githubusercontent.com/MISTERNEGATIVE21/GameSaveVault/main/windows/Install-GameSaveVault.ps1'
$code = Invoke-RestMethod -Uri $url -UseBasicParsing
$block = [scriptblock]::Create([string]$code)
& $block @args
