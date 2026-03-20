[CmdletBinding()]
param(
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'install.ps1') -ConfigPath $ConfigPath -Force
exit $LASTEXITCODE
