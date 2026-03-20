[CmdletBinding()]
param(
  [switch]$PurgeTools,
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'uninstall.ps1') -ConfigPath $ConfigPath -PurgeTools:$PurgeTools
exit $LASTEXITCODE
