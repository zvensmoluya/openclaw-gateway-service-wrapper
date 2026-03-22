[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('start', 'stop', 'restart')]
  [string]$Action,
  [string]$ConfigPath,
  [string]$ResultPath,
  [switch]$NoInvoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ServiceActionInvokerPath {
  param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot 'invoke-service-action.ps1')
  )

  return $ScriptPath
}

if ($NoInvoke) {
  return
}

& (Resolve-ServiceActionInvokerPath) -Action $Action -ConfigPath $ConfigPath -ResultPath $ResultPath
exit $LASTEXITCODE
