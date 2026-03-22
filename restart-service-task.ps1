[CmdletBinding()]
param(
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'control-service-task.ps1') -Action 'restart' -ConfigPath $ConfigPath
exit $LASTEXITCODE
