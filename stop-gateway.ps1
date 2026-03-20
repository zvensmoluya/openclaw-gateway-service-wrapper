[CmdletBinding()]
param(
  [string]$ConfigPath,
  [int]$TimeoutSec = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

try {
  if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'service-config.json'
  }

  $config = Get-ServiceConfig -ConfigPath $ConfigPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
  $stopped = Stop-RecordedServiceProcessTree -Config $config -TimeoutSec $TimeoutSec
  if ($stopped) {
    Update-RunState -Config $config -Patch @{
      stoppedAt = (Get-Date).ToString('o')
      status    = 'stopped'
    }
    Write-Host "Stopped the recorded process tree for '$($config.serviceName)'."
  } else {
    Write-Warning "No recorded process tree was found for '$($config.serviceName)'."
  }

  exit 0
} catch {
  Write-Error $_
  exit 1
}
