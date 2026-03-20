[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'status.ps1') -ConfigPath $ConfigPath -Json:$Json
exit $LASTEXITCODE
