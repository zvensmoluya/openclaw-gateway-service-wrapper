[CmdletBinding()]
param(
  [string]$ConfigPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'service-config.local.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedConfigPath = $ConfigPath
. (Join-Path $repoRoot 'tests\TestHelpers.ps1')
. (Join-Path $repoRoot 'tray-controller.ps1') -NoRun

$degraded = Get-TrayStateFromStatusReport -Report ([pscustomobject]@{
  serviceName = 'OpenClawService'
  installed   = $true
  service     = [pscustomobject]@{ status = 'Running' }
  health      = [pscustomobject]@{ ok = $true; error = $null }
  issues      = @('Restart task is missing.')
  warnings    = @('Deprecated mode.')
  config      = [pscustomobject]@{
    configSource   = 'explicit'
    sourcePath     = $resolvedConfigPath
    rememberedPath = $resolvedConfigPath
  }
})

Assert-Equal -Actual $degraded.state -Expected 'degraded'
Assert-Equal -Actual $degraded.canStop -Expected $true

$deepOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'status.ps1') -Json -TraySnapshot -RefreshKind deep -ConfigPath $resolvedConfigPath
$deepSnapshot = $deepOutput | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace("$($deepSnapshot.serviceName)")) {
  throw 'Deep tray snapshot did not include a service name.'
}

$fastOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'status.ps1') -Json -TraySnapshot -RefreshKind fast -ConfigPath $resolvedConfigPath
$fastSnapshot = $fastOutput | ConvertFrom-Json

Assert-Equal -Actual $fastSnapshot.refreshKind -Expected 'fast'
Assert-Equal -Actual $fastSnapshot.health.source -Expected 'cache'
if ([string]::IsNullOrWhiteSpace("$($fastSnapshot.lastDeepObservedAt)")) {
  throw 'Fast tray snapshot did not preserve lastDeepObservedAt.'
}

Write-Host 'Tray controller smoke checks passed.'
