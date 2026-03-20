[CmdletBinding()]
param(
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $ConfigPath = Join-Path $PSScriptRoot 'service-config.json'
}

& (Join-Path $PSScriptRoot 'install.ps1') -ConfigPath $ConfigPath -Force
exit $LASTEXITCODE
