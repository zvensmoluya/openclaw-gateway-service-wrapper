[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

try {
  $selection = Resolve-ServiceConfigSelection -ConfigPath $ConfigPath -AllowInvalidRemembered
  if ($selection.ContainsKey('invalidReason')) {
    $service = if ([string]::IsNullOrWhiteSpace($selection.rememberedServiceName)) {
      @{
        installed = $false
        name      = $null
        status    = $null
        startType = $null
        processId = 0
        startName = $null
        pathName  = $null
      }
    } else {
      Get-ServiceDetails -ServiceName $selection.rememberedServiceName
    }

    $report = @{
      serviceName = $selection.rememberedServiceName
      installed   = $service.installed
      service     = $service
      health      = @{
        ok         = $false
        statusCode = $null
        body       = $null
        error      = $selection.invalidReason
      }
      healthUrl   = $null
      port        = $null
      config      = @{
        configSource  = $selection.configSource
        sourcePath    = $selection.sourcePath
        rememberedPath = $selection.rememberedPath
      }
      issues      = @($selection.invalidReason)
    }

    if ($Json) {
      $report | ConvertTo-Json -Depth 10
    } else {
      Write-Host "Service name : $($selection.rememberedServiceName)"
      Write-Host "Config       : $($selection.sourcePath) [$($selection.configSource)]"
      Write-Host "Remembered   : $($selection.rememberedPath)"
      Write-Host 'Health       : FAILED'
      Write-Host $selection.invalidReason
    }

    exit 1
  }

  $config = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
  $config.configSource = $selection.configSource
  $config.rememberedPath = $selection.rememberedPath
  $service = Get-ServiceDetails -ServiceName $config.serviceName
  $health = Invoke-HealthCheck -Url $config.healthUrl -TimeoutSec 8
  $issues = @()

  if (-not $service.installed) {
    $issues += "Service '$($config.serviceName)' is not installed."
  }

  if ($service.installed -and $service.status -ne 'Running') {
    $issues += "Service '$($config.serviceName)' is not running."
  }

  if (-not $health.ok) {
    $issues += "Health endpoint is not healthy: $($health.error)"
  }

  $report = @{
    serviceName = $config.serviceName
    installed   = $service.installed
    service     = $service
    health      = $health
    healthUrl   = $config.healthUrl
    port        = $config.port
    config      = @{
      configSource  = $config.configSource
      sourcePath    = $config.sourceConfigPath
      rememberedPath = $config.rememberedPath
    }
    issues      = $issues
  }

  if ($Json) {
    $report | ConvertTo-Json -Depth 10
  } else {
    Write-Host "Service name : $($config.serviceName)"
    Write-Host "Config       : $($config.sourceConfigPath) [$($config.configSource)]"
    Write-Host "Remembered   : $($config.rememberedPath)"
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

    if ($issues.Count -gt 0) {
      Write-Host ''
      Write-Host 'Issues'
      foreach ($issue in $issues) {
        Write-Host "- $issue"
      }
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
