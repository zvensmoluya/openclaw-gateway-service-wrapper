[CmdletBinding()]
param(
  [switch]$PurgeTools,
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $ConfigPath = Join-Path $PSScriptRoot 'service-config.json'
}

& (Join-Path $PSScriptRoot 'uninstall.ps1') -ConfigPath $ConfigPath -PurgeTools:$PurgeTools
exit $LASTEXITCODE
