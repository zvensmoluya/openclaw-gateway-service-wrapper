[CmdletBinding()]
param(
  [switch]$PurgeTools,
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
  $serviceDetails = Get-ServiceDetails -ServiceName $config.serviceName

  if ($serviceDetails.installed) {
    try {
      Invoke-WinSWCommand -Config $config -Command 'stop'
    } catch {
      Write-Warning "Standard stop failed, falling back to a targeted process-tree stop."
      [void](Stop-RecordedServiceProcessTree -Config $config -TimeoutSec $config.stopTimeoutSeconds)
    }

    [void](Wait-ForServiceStatus -ServiceName $config.serviceName -DesiredStatus 'Stopped' -TimeoutSec 30)

    try {
      Invoke-WinSWCommand -Config $config -Command 'uninstall'
    } catch {
      Write-Warning "WinSW uninstall failed, removing the service with sc.exe."
      & sc.exe delete $config.serviceName *> $null
    }
  }

  if ($PurgeTools) {
    Remove-GeneratedArtifacts -Config $config
  }

  Write-Host "Service '$($config.serviceName)' has been removed."
  if ($PurgeTools) {
    Write-Host 'Generated WinSW artifacts were purged.'
  }

  exit 0
} catch {
  Write-Error $_
  exit 1
}
