<#
.SYNOPSIS
    GameSaveVault install root forwarding shim for Windows PowerShell.
.DESCRIPTION
    Forwards execution to windows/Install.ps1 preserving all arguments and exit code.
#>

$scriptPath = Join-Path (Join-Path $PSScriptRoot 'windows') 'Install.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-Error "Target script not found: $scriptPath"
    exit 1
}

& $scriptPath @args
if ($null -ne $LASTEXITCODE) {
    exit $LASTEXITCODE
}
