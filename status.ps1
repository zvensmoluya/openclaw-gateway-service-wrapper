[CmdletBinding()]
param(
  [switch]$Json,
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
  $service = Get-ServiceDetails -ServiceName $config.serviceName
  $health = Invoke-HealthCheck -Url $config.healthUrl -TimeoutSec 8

  $report = @{
    serviceName = $config.serviceName
    installed   = $service.installed
    service     = $service
    health      = $health
    healthUrl   = $config.healthUrl
    port        = $config.port
  }

  if ($Json) {
    $report | ConvertTo-Json -Depth 10
  } else {
    Write-Host "Service name : $($config.serviceName)"
    Write-Host "Installed    : $($service.installed)"
    Write-Host "Status       : $($service.status)"
    Write-Host "Start type   : $($service.startType)"
    Write-Host "Health URL   : $($config.healthUrl)"
    if ($health.ok) {
      Write-Host "Health       : OK ($($health.statusCode))"
      Write-Host $health.body
    } else {
      Write-Host 'Health       : FAILED'
      Write-Host $health.error
    }
  }

  if ($service.installed -and $service.status -eq 'Running' -and $health.ok) {
    exit 0
  }

  exit 1
} catch {
  Write-Error $_
  exit 1
}
