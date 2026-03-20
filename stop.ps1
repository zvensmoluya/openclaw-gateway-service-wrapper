[CmdletBinding()]
param(
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

try {
  if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'service-config.json'
  }

  $config = Get-ServiceConfig -ConfigPath $ConfigPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
  try {
    Invoke-WinSWCommand -Config $config -Command 'stop'
  } catch {
    Write-Warning "Standard stop failed, falling back to a targeted process-tree stop."
    [void](Stop-RecordedServiceProcessTree -Config $config -TimeoutSec $config.stopTimeoutSeconds)
  }

  if (-not (Wait-ForServiceStatus -ServiceName $config.serviceName -DesiredStatus 'Stopped' -TimeoutSec 30)) {
    throw "Service '$($config.serviceName)' did not stop within 30 seconds."
  }

  Write-Host "Service '$($config.serviceName)' is stopped."
  exit 0
} catch {
  Write-Error $_
  exit 1
}
