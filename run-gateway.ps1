[CmdletBinding()]
param(
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

$config = $null

try {
  if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'service-config.json'
  }

  $identityContext = Get-ServiceIdentityContext -Mode 'currentUser'
  $config = Get-ServiceConfig -ConfigPath $ConfigPath -IdentityContext $identityContext
  $openClawCommand = Resolve-OpenClawCommandPath -Config $config -IdentityContext $identityContext

  Ensure-Directory -Path $config.logsDirectory
  Ensure-Directory -Path $config.runtimeStateDirectory
  Ensure-Directory -Path $config.stateDir
  Ensure-Directory -Path (Split-Path -Parent $config.gatewayConfigPath)

  $runtimeHome = if ((Split-Path -Leaf $config.stateDir) -ieq '.openclaw') {
    Split-Path -Parent $config.stateDir
  } else {
    $identityContext.profileRoot
  }
  $runtimeLocalAppData = if ((Split-Path -Leaf $config.tempDir) -ieq 'Temp') {
    Split-Path -Parent $config.tempDir
  } else {
    $identityContext.localAppData
  }
  $runtimeAppData = Join-Path $runtimeHome 'AppData\Roaming'

  $env:OPENCLAW_STATE_DIR = $config.stateDir
  $env:OPENCLAW_CONFIG_PATH = $config.gatewayConfigPath
  $env:OPENCLAW_GATEWAY_PORT = [string]$config.port
  $env:OPENCLAW_SYSTEMD_UNIT = 'openclaw-gateway.service'
  $env:OPENCLAW_WINDOWS_TASK_NAME = 'OpenClaw Gateway'
  $env:OPENCLAW_SERVICE_MARKER = 'openclaw'
  $env:OPENCLAW_SERVICE_KIND = 'gateway'
  $env:USERPROFILE = $runtimeHome
  $env:HOME = $runtimeHome
  $env:LOCALAPPDATA = $runtimeLocalAppData
  $env:APPDATA = $runtimeAppData
  $env:TEMP = $config.tempDir
  $env:TMP = $config.tempDir
  $env:TMPDIR = $config.tempDir

  [void](Set-WrapperProxyEnvironment -Config $config)

  $arguments = @('gateway', 'run', '--bind', $config.bind, '--port', [string]$config.port)
  if ($config.allowForceBind) {
    $arguments += '--force'
  }

  Write-Host "OpenClaw command : $openClawCommand"
  Write-Host "State dir        : $($config.stateDir)"
  Write-Host "Config path      : $($config.gatewayConfigPath)"
  Write-Host "Wrapper PID      : $PID"
  Write-Host "Port             : $($config.port)"

  Write-RunState -Config $config -State @{
    serviceName      = $config.serviceName
    wrapperProcessId = $PID
    openclawCommand  = $openClawCommand
    arguments        = $arguments
    port             = $config.port
    healthUrl        = $config.healthUrl
    startedAt        = (Get-Date).ToString('o')
    status           = 'running'
  } | Out-Null

  & $openClawCommand @arguments
  $exitCode = $LASTEXITCODE

  Update-RunState -Config $config -Patch @{
    stoppedAt = (Get-Date).ToString('o')
    exitCode  = $exitCode
    status    = 'stopped'
  }

  exit $exitCode
} catch {
  if ($null -ne $config) {
    Update-RunState -Config $config -Patch @{
      stoppedAt = (Get-Date).ToString('o')
      exitCode  = 1
      status    = 'failed'
      error     = $_.Exception.Message
    }
  }

  Write-Error $_
  exit 1
}
