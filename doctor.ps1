[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

$issues = @()

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
      config      = @{
        configSource        = $selection.configSource
        sourcePath          = $selection.sourcePath
        rememberedPath      = $selection.rememberedPath
        serviceAccountMode  = $null
        stateDir            = $null
        gatewayConfigPath   = $null
        tempDir             = $null
        port                = $null
        bind                = $null
      }
      dependencies = @{
        openclawCommand = $null
        winswExecutable = $null
        winswXml        = $null
      }
      service   = $service
      health    = @{
        ok         = $false
        statusCode = $null
        body       = $null
        error      = $selection.invalidReason
      }
      listeners = @()
      issues    = @($selection.invalidReason)
    }

    if ($Json) {
      $report | ConvertTo-Json -Depth 10
    } else {
      Write-Host "Service name      : $($selection.rememberedServiceName)"
      Write-Host "Config path       : $($selection.sourcePath)"
      Write-Host "Config source     : $($selection.configSource)"
      Write-Host "Remembered path   : $($selection.rememberedPath)"
      Write-Host ''
      Write-Host 'Issues'
      Write-Host "- $($selection.invalidReason)"
    }

    exit 1
  }

  $config = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
  $config.configSource = $selection.configSource
  $config.rememberedPath = $selection.rememberedPath
  $layout = Get-ServiceArtifactLayout -Config $config
  $service = Get-ServiceDetails -ServiceName $config.serviceName
  $listeners = @(Get-PortListeners -Port $config.port)
  $health = Invoke-HealthCheck -Url $config.healthUrl -TimeoutSec 8
  $openclawCommand = $null

  try {
    $openclawCommand = Resolve-OpenClawCommandPath -Config $config -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
  } catch {
    $issues += $_.Exception.Message
  }

  if (-not (Test-Path -LiteralPath $config.stateDir)) {
    $issues += "State directory does not exist: $($config.stateDir)"
  }

  $issues += @(Get-GatewayConfigValidationIssues -Config $config)

  if (-not $service.installed) {
    $issues += "Service '$($config.serviceName)' is not installed."
  }

  if ($service.installed -and $service.status -ne 'Running') {
    $issues += "Service '$($config.serviceName)' is not running."
  }

  if ($service.installed -and -not $health.ok) {
    $issues += "Health endpoint is not healthy: $($health.error)"
  }

  if ($listeners.Count -gt 0 -and -not $config.allowForceBind -and -not $service.installed) {
    $issues += "Port $($config.port) is already in use."
  }

  $report = @{
    serviceName = $config.serviceName
    config      = @{
      configSource       = $config.configSource
      sourcePath         = $config.sourceConfigPath
      rememberedPath     = $config.rememberedPath
      serviceAccountMode = $config.serviceAccountMode
      stateDir           = $config.stateDir
      gatewayConfigPath  = $config.gatewayConfigPath
      tempDir            = $config.tempDir
      port               = $config.port
      bind               = $config.bind
    }
    dependencies = @{
      openclawCommand = $openclawCommand
      winswExecutable = $layout.generatedExecutablePath
      winswXml        = $layout.generatedXmlPath
    }
    service   = $service
    health    = $health
    listeners = $listeners
    issues    = $issues
  }

  if ($Json) {
    $report | ConvertTo-Json -Depth 10
  } else {
    Write-Host "Service name      : $($config.serviceName)"
    Write-Host "Config path       : $($config.sourceConfigPath)"
    Write-Host "Config source     : $($config.configSource)"
    Write-Host "Remembered path   : $($config.rememberedPath)"
    Write-Host "Gateway config    : $($config.gatewayConfigPath)"
    Write-Host "OpenClaw command  : $openclawCommand"
    Write-Host "WinSW executable  : $($layout.generatedExecutablePath)"
    Write-Host "WinSW XML         : $($layout.generatedXmlPath)"
    Write-Host "Service installed : $($service.installed)"
    Write-Host "Service status    : $($service.status)"
    Write-Host "Port listeners    : $($listeners.Count)"
    Write-Host "Health OK         : $($health.ok)"
    if ($issues.Count -gt 0) {
      Write-Host ''
      Write-Host 'Issues'
      foreach ($issue in $issues) {
        Write-Host "- $issue"
      }
    }
  }

  if ($issues.Count -eq 0) {
    exit 0
  }

  exit 1
} catch {
  Write-Error $_
  exit 1
}
