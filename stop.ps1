[CmdletBinding()]
param(
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'invoke-service-action.ps1') -Action 'stop' -ConfigPath $ConfigPath
exit $LASTEXITCODE
