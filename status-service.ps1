[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $ConfigPath = Join-Path $PSScriptRoot 'service-config.json'
}

& (Join-Path $PSScriptRoot 'status.ps1') -ConfigPath $ConfigPath -Json:$Json
exit $LASTEXITCODE
