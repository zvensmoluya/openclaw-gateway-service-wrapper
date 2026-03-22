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
  $launchSpec = Resolve-OpenClawLaunchSpec -Config $config -IdentityContext $identityContext
  $restartTask = Get-ServiceRestartTaskInfo -Config $config

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
  $env:OPENCLAW_WINDOWS_TASK_NAME = $restartTask.fullTaskName
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
  $effectiveArguments = @($launchSpec.preArguments + $arguments)

  Write-Host "OpenClaw command : $($launchSpec.requestedCommandPath)"
  Write-Host "Launch mode      : $($launchSpec.launchMode)"
  Write-Host "Executable path  : $($launchSpec.executablePath)"
  Write-Host "State dir        : $($config.stateDir)"
  Write-Host "Config path      : $($config.gatewayConfigPath)"
  Write-Host "Wrapper PID      : $PID"
  Write-Host "Port             : $($config.port)"
  Write-Host "Restart task     : $($restartTask.fullTaskName)"

  Write-RunState -Config $config -State @{
    serviceName          = $config.serviceName
    wrapperProcessId     = $PID
    gatewayProcessId     = 0
    listenerProcessIds   = @()
    openclawCommand      = $launchSpec.requestedCommandPath
    effectiveExecutablePath = $launchSpec.executablePath
    entryScriptPath      = $launchSpec.entryScriptPath
    arguments            = $arguments
    effectiveArguments   = $effectiveArguments
    port                 = $config.port
    healthUrl            = $config.healthUrl
    launchMode           = $launchSpec.launchMode
    startedAt            = (Get-Date).ToString('o')
    status               = 'running'
  } | Out-Null

  $gatewayProcess = Start-Process `
    -FilePath $launchSpec.executablePath `
    -ArgumentList (Join-ProcessArgumentString -Arguments ($effectiveArguments | ForEach-Object { "$_" })) `
    -WorkingDirectory $PSScriptRoot `
    -PassThru

  Update-RunState -Config $config -Patch @{
    gatewayProcessId = $gatewayProcess.Id
  }

  $listeners = @(Wait-ForPortListeners -Port ([int]$config.port) -TimeoutSec 10)
  if ($listeners.Count -gt 0) {
    Update-RunState -Config $config -Patch @{
      listenerProcessIds = @($listeners | ForEach-Object { [int]$_.processId } | Sort-Object -Unique)
      listenerObservedAt = (Get-Date).ToString('o')
    }
  }

  $gatewayProcess.WaitForExit()
  $exitCode = $gatewayProcess.ExitCode

  Update-RunState -Config $config -Patch @{
    stoppedAt        = (Get-Date).ToString('o')
    exitCode         = $exitCode
    status           = 'stopped'
    listenerProcessIds = @()
  }

  exit $exitCode
} catch {
  if ($null -ne $config) {
    Update-RunState -Config $config -Patch @{
      stoppedAt        = (Get-Date).ToString('o')
      exitCode         = 1
      status           = 'failed'
      listenerProcessIds = @()
      error            = $_.Exception.Message
    }
  }

  Write-Error $_
  exit 1
}
