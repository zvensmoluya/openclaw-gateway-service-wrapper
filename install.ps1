[CmdletBinding()]
param(
  [string]$ConfigPath,
  [pscredential]$Credential,
  [switch]$Force,
  [switch]$SkipTray,
  [switch]$Elevated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

function Get-InstallElevationArguments {
  [CmdletBinding()]
  param()

  $arguments = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    (Join-Path $PSScriptRoot 'install.ps1'),
    '-Elevated'
  )

  if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $arguments += @('-ConfigPath', $ConfigPath)
  }

  if ($Force) {
    $arguments += '-Force'
  }

  if ($SkipTray) {
    $arguments += '-SkipTray'
  }

  return $arguments
}

try {
  $bootstrapIdentity = Get-ServiceIdentityContext -Mode 'currentUser'
  $selection = Resolve-ServiceConfigSelection -ConfigPath $ConfigPath
  $bootstrapConfig = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext $bootstrapIdentity

  if (-not $Elevated -and -not (Test-IsCurrentProcessElevated)) {
    if ($null -ne $Credential -and $bootstrapConfig.serviceAccountMode -eq 'localSystem') {
      throw "serviceAccountMode 'localSystem' does not accept -Credential."
    }

    if ($null -ne $Credential) {
      throw "install.ps1 cannot forward -Credential through UAC self-elevation. Re-run from an elevated PowerShell if you need to pass -Credential explicitly, or omit -Credential and let the elevated installer prompt for it."
    }

    $elevatedProcess = Start-Process `
      -FilePath (Get-WindowsPowerShellExecutablePath) `
      -ArgumentList (Join-ProcessArgumentString -Arguments (Get-InstallElevationArguments)) `
      -Verb RunAs `
      -Wait `
      -PassThru
    exit $elevatedProcess.ExitCode
  }

  $currentWindowsIdentityName = Get-CurrentWindowsIdentityName
  $serviceAccountPlan = Resolve-ServiceAccountPlan -Config $bootstrapConfig -Credential $Credential -CurrentWindowsIdentityName $currentWindowsIdentityName -PromptForCredential
  $installCredential = $serviceAccountPlan.credential
  if ($serviceAccountPlan.deprecatedAlias) {
    Write-Warning "serviceAccountMode 'currentUser' is deprecated. The service will be installed for the explicit Windows account '$($serviceAccountPlan.expectedStartName)'."
  }

  $identityContext = $serviceAccountPlan.identityContext
  $config = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext $identityContext
  $config.configSource = $selection.configSource
  $config.rememberedPath = $selection.rememberedPath
  $layout = Get-ServiceArtifactLayout -Config $config

  Ensure-Directory -Path $config.logsDirectory
  Ensure-Directory -Path $config.runtimeStateDirectory
  Ensure-Directory -Path $config.stateDir
  Ensure-Directory -Path (Split-Path -Parent $config.gatewayConfigPath)

  $openclawCommand = Resolve-OpenClawCommandPath -Config $config -IdentityContext $identityContext
  Write-Host "Resolved openclaw command: $openclawCommand"

  $serviceDetails = Get-ServiceDetails -ServiceName $config.serviceName
  if ($serviceDetails.installed) {
    Write-Host "Reinstalling existing service '$($config.serviceName)'."
    Write-Host "Preparing SYSTEM control bridge for safe reinstall."

    $existingControlTaskNames = Register-ServiceControlTasks -Config $config

    [void](Disable-ServiceStartForReinstall -ServiceName $config.serviceName)
    $stopBridgeResult = Invoke-ServiceControlAction -Config $config -Action 'stop' -TimeoutSec 60
    if (-not $stopBridgeResult.success) {
      throw $stopBridgeResult.message
    }

    try {
      Invoke-WinSWCommand -Config $config -Command 'uninstall'
    } catch {
      Write-Warning "Standard uninstall failed, removing the service with sc.exe."
      & sc.exe delete $config.serviceName *> $null
    }

    if (-not (Wait-ForServiceRemoval -ServiceName $config.serviceName -TimeoutSec 30)) {
      throw "Service '$($config.serviceName)' still exists after uninstall. Reboot the machine or delete the stale service entry before reinstalling."
    }
  }

  $listeners = @(Get-PortListeners -Port $config.port)
  if ($listeners.Count -gt 0 -and -not $config.allowForceBind) {
    $details = $listeners | ForEach-Object { (($_ | Out-String).Trim()) }
    throw "Port $($config.port) is already in use. Either stop the listed listeners first or set allowForceBind to true. Listeners: $($details -join ', ')"
  }

  Ensure-WinSWBinary -Config $config -Force:$Force | Out-Null
  Write-WinSWServiceXml -Config $config -ServiceAccountMode $serviceAccountPlan.effectiveMode -Credential $installCredential | Out-Null

  Invoke-WinSWCommand -Config $config -Command 'install'
  try {
    $controlTaskNames = Register-ServiceControlTasks -Config $config
    $restartTaskName = $controlTaskNames.restart
  } catch {
    try {
      Invoke-WinSWCommand -Config $config -Command 'uninstall'
    } catch {
      Write-Warning "Service '$($config.serviceName)' was installed but restart task registration failed and automatic rollback also failed."
    }

    throw "Failed to register SYSTEM control tasks for service '$($config.serviceName)': $($_.Exception.Message)"
  }

  Invoke-WinSWCommand -Config $config -Command 'start'

  if (-not (Wait-ForServiceStatus -ServiceName $config.serviceName -DesiredStatus 'Running' -TimeoutSec 30)) {
    throw "Service '$($config.serviceName)' did not reach the Running state within 30 seconds."
  }

  $installedService = Get-ServiceDetails -ServiceName $config.serviceName
  $identityValidationIssues = @(Get-ServiceInstallValidationIssues -Config $config -ServiceDetails $installedService -CurrentWindowsIdentityName $currentWindowsIdentityName)
  if ($identityValidationIssues.Count -gt 0) {
    throw ($identityValidationIssues -join ' ')
  }

  Write-RememberedServiceConfigSelection -SourceConfigPath $config.sourceConfigPath -ServiceName $config.serviceName | Out-Null
  $health = Invoke-HealthCheck -Url $config.healthUrl -TimeoutSec 8
  $trayStatus = 'Skipped'

  if (-not $SkipTray) {
    try {
      $trayShortcutPath = Install-TrayStartupShortcut -Config $config
      $trayStatus = "Registered ($trayShortcutPath)"
    } catch {
      $trayStatus = "Failed ($($_.Exception.Message))"
      Write-Warning "Tray startup shortcut registration failed: $($_.Exception.Message)"
    }
  }

  Write-Host ''
  Write-Host "Service name : $($config.serviceName)"
  Write-Host "Config       : $($config.sourceConfigPath) [$($config.configSource)]"
  Write-Host "Run as       : $($installedService.startName)"
  Write-Host "Port         : $($config.port)"
  Write-Host "WinSW home   : $($layout.generatedDirectory)"
  Write-Host "Start task   : $($controlTaskNames.start)"
  Write-Host "Stop task    : $($controlTaskNames.stop)"
  Write-Host "Restart task : $restartTaskName"
  Write-Host "Health URL   : $($config.healthUrl)"
  Write-Host "Tray startup : $trayStatus"
  if ($health.ok) {
    Write-Host "Health       : OK ($($health.statusCode))"
  } else {
    Write-Warning "Health check failed after install: $($health.error)"
  }

  exit 0
} catch {
  [Console]::Error.WriteLine($_.Exception.Message)
  exit 1
}
