[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

$issues = @()
$warnings = [System.Collections.ArrayList]::new()

function New-EmptyControlTaskReportSet {
  return [ordered]@{
    start   = New-EmptyServiceControlTaskStatusReport -Action 'start'
    stop    = New-EmptyServiceControlTaskStatusReport -Action 'stop'
    restart = New-EmptyServiceControlTaskStatusReport -Action 'restart'
  }
}

try {
  $currentWindowsIdentityName = Get-CurrentWindowsIdentityName
  $emptyWarnings = [System.Collections.ArrayList]::new()
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

    $actualExecutablePath = Get-ServiceExecutablePathFromPathName -PathName $service.pathName
    $identity = @{
      configuredMode   = $null
      deprecatedAlias  = $false
      expectedStartName = $null
      actualStartName  = if ($service.installed) { $service.startName } else { $null }
      matches          = $false
      installLayout    = Get-ServiceInstallLayoutFromExecutablePath -ExecutablePath $actualExecutablePath
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
      restartTask = New-EmptyServiceRestartTaskStatusReport
      controlTasks = (New-EmptyControlTaskReportSet)
      controlState = $null
      runtime = $null
      proxy = New-EmptyWrapperProxyStatusReport
      identity = $identity
      warnings = $emptyWarnings
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
      Write-Host "Run as            : $($identity.actualStartName)"
      Write-Host "Install layout    : $($identity.installLayout)"
      Write-Host ''
      Write-Host 'Issues'
      Write-Host "- $($selection.invalidReason)"
    }

    exit 1
  }

  $bootstrapConfig = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
  $service = Get-ServiceDetails -ServiceName $bootstrapConfig.serviceName
  $inspectionIdentityContext = Resolve-InspectionIdentityContext -Config $bootstrapConfig -ServiceDetails $service -CurrentWindowsIdentityName $currentWindowsIdentityName
  $config = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext $inspectionIdentityContext
  $config.configSource = $selection.configSource
  $config.rememberedPath = $selection.rememberedPath
  $layout = Get-ServiceArtifactLayout -Config $config
  $runtimeState = Read-RunState -Config $config
  $recoveryContext = Get-ServiceRecoveryContext -Config $config
  $identity = Get-ServiceIdentityReport -Config $config -ServiceDetails $service -CurrentWindowsIdentityName $currentWindowsIdentityName
  $restartTask = Get-ServiceRestartTaskStatus -Config $config
  $controlTasks = Get-ServiceControlTaskStatuses -Config $config
  $controlState = Read-ServiceControlState -Config $config
  $proxy = Get-WrapperProxyStatusReport -Config $config
  $reportedWinSWExecutable = if ($service.installed -and -not [string]::IsNullOrWhiteSpace($service.pathName)) {
    Get-ServiceExecutablePathFromPathName -PathName $service.pathName
  } elseif ($identity.installLayout -eq 'legacyRoot') {
    $layout.legacyExecutablePath
  } else {
    $layout.generatedExecutablePath
  }
  $reportedWinSWXml = if ($identity.installLayout -eq 'legacyRoot') {
    $layout.legacyXmlPath
  } else {
    $layout.generatedXmlPath
  }
  $listeners = @(Get-PortListeners -Port $config.port)
  $health = Invoke-HealthCheck -Url $config.healthUrl -TimeoutSec 8
  $openclawCommand = $null

  try {
    $openclawCommand = Resolve-OpenClawCommandPath -Config $config -IdentityContext $inspectionIdentityContext
  } catch {
    $issues += $_.Exception.Message
  }

  if ($identity.deprecatedAlias) {
    [void]$warnings.Add("serviceAccountMode 'currentUser' is deprecated. Use 'credential' for Windows Service installs.")
  }

  if ($service.installed -and $identity.installLayout -eq 'legacyRoot' -and $identity.configuredMode -eq 'currentUser' -and [string]::IsNullOrWhiteSpace($identity.expectedStartName)) {
    [void]$warnings.Add("Service '$($config.serviceName)' uses the legacy root WinSW layout and does not expose an explicit service account in XML, so the expected account cannot be inferred reliably. Reinstall with the current wrapper to capture service account metadata.")
  }

  if (-not (Test-Path -LiteralPath $config.stateDir)) {
    $issues += "State directory does not exist: $($config.stateDir)"
  }

  $issues += @(Get-GatewayConfigValidationIssues -Config $config)

  if ($service.installed -and $identity.installLayout -eq 'legacyRoot') {
    $issues += "Service '$($config.serviceName)' is still using the legacy root WinSW layout. Reinstall with the current wrapper so service account settings and explicit ConfigPath are preserved."
  }

  $hasExpectedIdentity = -not [string]::IsNullOrWhiteSpace($identity.expectedStartName)
  $actualIsBuiltInServiceAccount = $service.installed -and (Test-IsBuiltInServiceAccount -AccountName $identity.actualStartName)

  if ($actualIsBuiltInServiceAccount -and -not ($hasExpectedIdentity -and $identity.matches) -and -not $hasExpectedIdentity -and $identity.configuredMode -eq 'credential') {
    $issues += "Service '$($config.serviceName)' is running as built-in account '$($identity.actualStartName)'. credential mode requires an explicit Windows account. Reinstall with explicit credentials."
  } elseif ($actualIsBuiltInServiceAccount -and -not ($hasExpectedIdentity -and $identity.matches) -and $hasExpectedIdentity) {
    $issues += "Service '$($config.serviceName)' is running as built-in account '$($identity.actualStartName)' but the configured model expects user account '$($identity.expectedStartName)'. Reinstall with explicit credentials."
  } elseif ($service.installed -and $hasExpectedIdentity -and -not $identity.matches) {
    $issues += "Service '$($config.serviceName)' is running as '$($identity.actualStartName)' but expected '$($identity.expectedStartName)'. Reinstall with explicit credentials."
  }

  if (-not $service.installed) {
    $issues += "Service '$($config.serviceName)' is not installed."
  }

  if ($service.installed -and $service.status -ne 'Running') {
    $issues += "Service '$($config.serviceName)' is not running."
  }

  if ($service.installed -and -not $restartTask.exists) {
    $issues += "Restart task '$($restartTask.fullTaskName)' is missing. Reinstall the service to restore intentional restart bridging."
  } elseif ($service.installed -and -not $restartTask.matches) {
    $issues += "Restart task '$($restartTask.fullTaskName)' does not match the expected wrapper action. Reinstall the service to restore intentional restart bridging."
  }

  foreach ($action in @('start', 'stop')) {
    $controlTask = $controlTasks[$action]
    if ($service.installed -and -not $controlTask.exists) {
      $issues += "Control task '$($controlTask.fullTaskName)' for '$action' is missing. Reinstall the service to restore SYSTEM-backed lifecycle control."
    } elseif ($service.installed -and -not $controlTask.matches) {
      $issues += "Control task '$($controlTask.fullTaskName)' for '$action' does not match the expected wrapper action. Reinstall the service to restore SYSTEM-backed lifecycle control."
    }
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
    restartTask = $restartTask
    controlTasks = $controlTasks
    controlState = $controlState
    runtime = @{
      launchMode               = if ($null -ne $runtimeState -and $runtimeState.ContainsKey('launchMode')) { $runtimeState.launchMode } else { $null }
      requestedCommandPath     = if ($null -ne $runtimeState -and $runtimeState.ContainsKey('openclawCommand')) { $runtimeState.openclawCommand } else { $null }
      effectiveExecutablePath  = if ($null -ne $runtimeState -and $runtimeState.ContainsKey('effectiveExecutablePath')) { $runtimeState.effectiveExecutablePath } else { $null }
      entryScriptPath          = if ($null -ne $runtimeState -and $runtimeState.ContainsKey('entryScriptPath')) { $runtimeState.entryScriptPath } else { $null }
      wrapperProcessId         = if ($null -ne $runtimeState -and $runtimeState.ContainsKey('wrapperProcessId')) { $runtimeState.wrapperProcessId } else { 0 }
      gatewayProcessId         = if ($null -ne $runtimeState -and $runtimeState.ContainsKey('gatewayProcessId')) { $runtimeState.gatewayProcessId } else { 0 }
      liveListenerProcessIds   = @($recoveryContext.listenerProcessIds)
      recordedListenerProcessIds = @($recoveryContext.recordedListenerProcessIds)
    }
    proxy = $proxy
    identity = $identity
    warnings = $warnings
    dependencies = @{
      openclawCommand = $openclawCommand
      winswExecutable = $reportedWinSWExecutable
      winswXml        = $reportedWinSWXml
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
    Write-Host "Configured mode   : $($identity.configuredMode)"
    Write-Host "Deprecated alias  : $($identity.deprecatedAlias)"
    Write-Host "Expected run as   : $($identity.expectedStartName)"
    Write-Host "Actual run as     : $($identity.actualStartName)"
    Write-Host "Install layout    : $($identity.installLayout)"
    Write-Host "Gateway config    : $($config.gatewayConfigPath)"
    Write-Host "OpenClaw command  : $openclawCommand"
    Write-Host "WinSW executable  : $reportedWinSWExecutable"
    Write-Host "WinSW XML         : $reportedWinSWXml"
    Write-Host "Restart task      : $($restartTask.fullTaskName)"
    Write-Host "Task status       : $($restartTask.state)"
    Write-Host "Task matches      : $($restartTask.matches)"
    Write-Host "Start task        : $($controlTasks.start.fullTaskName)"
    Write-Host "Start task ok     : $($controlTasks.start.matches)"
    Write-Host "Stop task         : $($controlTasks.stop.fullTaskName)"
    Write-Host "Stop task ok      : $($controlTasks.stop.matches)"
    Write-Host "Control state     : $(if ($null -ne $controlState) { $controlState.status } else { $null })"
    Write-Host "Launch mode       : $($report.runtime.launchMode)"
    Write-Host "Gateway PID       : $($report.runtime.gatewayProcessId)"
    Write-Host "Live listeners    : $((@($report.runtime.liveListenerProcessIds) -join ','))"
    Write-Host "Recorded listeners: $((@($report.runtime.recordedListenerProcessIds) -join ','))"
    Write-Host "HTTP proxy        : $($proxy.httpProxy.value) [$($proxy.httpProxy.source)]"
    Write-Host "HTTPS proxy       : $($proxy.httpsProxy.value) [$($proxy.httpsProxy.source)]"
    Write-Host "ALL proxy         : $($proxy.allProxy.value) [$($proxy.allProxy.source)]"
    Write-Host "NO_PROXY          : $($proxy.noProxy.value) [$($proxy.noProxy.source)]"
    Write-Host "Service installed : $($service.installed)"
    Write-Host "Service status    : $($service.status)"
    Write-Host "Port listeners    : $($listeners.Count)"
    Write-Host "Health OK         : $($health.ok)"
    if ($warnings.Count -gt 0) {
      Write-Host ''
      Write-Host 'Warnings'
      foreach ($warning in $warnings) {
        Write-Host "- $warning"
      }
    }
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
