[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ConfigPath,
  [switch]$TraySnapshot,
  [ValidateSet('fast', 'deep')]
  [string]$RefreshKind = 'deep'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

function New-EmptyControlTaskReportSet {
  return [ordered]@{
    start   = New-EmptyServiceControlTaskStatusReport -Action 'start'
    stop    = New-EmptyServiceControlTaskStatusReport -Action 'stop'
    restart = New-EmptyServiceControlTaskStatusReport -Action 'restart'
  }
}

function Get-RecoveryContextProcessIdList {
  param(
    [AllowNull()]
    $Context,
    [Parameter(Mandatory = $true)]
    [string]$PropertyName
  )

  if ($null -eq $Context) {
    return @()
  }

  if (($Context -is [System.Collections.IDictionary]) -and $Context.Contains($PropertyName)) {
    return @($Context[$PropertyName])
  }

  if ($Context.PSObject.Properties.Name -contains $PropertyName) {
    return @($Context.$PropertyName)
  }

  return @()
}

function New-StatusErrorReport {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Selection
  )

  $service = if ([string]::IsNullOrWhiteSpace($Selection.rememberedServiceName)) {
    @{
      installed = $false
      name      = $null
      status    = $null
      startType = $null
      processId = 0
      startName = $null
      pathName  = $null
      transitionStatus = $null
      pending = $false
      stuckStopping = $false
      wrapperProcessId = 0
      listenerProcessIds = @()
    }
  } else {
    Get-ServiceDetails -ServiceName $Selection.rememberedServiceName
  }

  $actualExecutablePath = Get-ServiceExecutablePathFromPathName -PathName $service.pathName
  $identity = @{
    configuredMode    = $null
    deprecatedAlias   = $false
    expectedStartName = $null
    actualStartName   = if ($service.installed) { $service.startName } else { $null }
    matches           = $false
    installLayout     = Get-ServiceInstallLayoutFromExecutablePath -ExecutablePath $actualExecutablePath
  }

  return @{
    serviceName = $Selection.rememberedServiceName
    displayName = if ([string]::IsNullOrWhiteSpace($Selection.rememberedServiceName)) { 'OpenClaw' } else { $Selection.rememberedServiceName }
    installed   = $service.installed
    service     = $service
    restartTask = New-EmptyServiceRestartTaskStatusReport
    controlTasks = (New-EmptyControlTaskReportSet)
    controlState = $null
    runtime    = $null
    proxy       = New-EmptyWrapperProxyStatusReport
    health      = @{
      ok         = $false
      statusCode = $null
      body       = $null
      error      = $Selection.invalidReason
    }
    healthUrl   = $null
    port        = $null
    config      = @{
      configSource   = $Selection.configSource
      sourcePath     = $Selection.sourcePath
      rememberedPath = $Selection.rememberedPath
    }
    identity    = $identity
    warnings    = [System.Collections.ArrayList]::new()
    issues      = @($Selection.invalidReason)
  }
}

function Get-FullStatusContext {
  param(
    [string]$ResolvedConfigPath
  )

  $currentWindowsIdentityName = Get-CurrentWindowsIdentityName
  $trayContext = Resolve-TrayControllerContext -ConfigPath $ResolvedConfigPath -CurrentWindowsIdentityName $currentWindowsIdentityName -AllowInvalidRemembered

  if ($trayContext.selection.ContainsKey('invalidReason')) {
    return @{
      report       = (New-StatusErrorReport -Selection $trayContext.selection)
      exitCode     = 1
      config       = $null
      paths        = $trayContext.paths
      errorMessage = $trayContext.selection.invalidReason
    }
  }

  $config = $trayContext.config
  $recoveryContext = Get-ServiceRecoveryContext -Config $config
  $service = $recoveryContext.service
  $runtimeState = Read-RunState -Config $config
  $liveListenerProcessIds = Get-RecoveryContextProcessIdList -Context $recoveryContext -PropertyName 'listenerProcessIds'
  $recordedListenerProcessIds = Get-RecoveryContextProcessIdList -Context $recoveryContext -PropertyName 'recordedListenerProcessIds'
  $identity = Get-ServiceIdentityReport -Config $config -ServiceDetails $service -CurrentWindowsIdentityName $currentWindowsIdentityName
  $restartTask = Get-ServiceRestartTaskStatus -Config $config
  $controlTasks = Get-ServiceControlTaskStatuses -Config $config
  $controlState = Read-ServiceControlState -Config $config
  $proxy = Get-WrapperProxyStatusReport -Config $config
  $health = Invoke-HealthCheck -Url $config.healthUrl -TimeoutSec 8
  $warnings = [System.Collections.ArrayList]::new()
  $issues = @()

  if ($identity.deprecatedAlias) {
    [void]$warnings.Add("serviceAccountMode 'currentUser' is deprecated. Use 'credential' for Windows Service installs.")
  }

  if ($service.installed -and $identity.installLayout -eq 'legacyRoot' -and $identity.configuredMode -eq 'currentUser' -and [string]::IsNullOrWhiteSpace($identity.expectedStartName)) {
    [void]$warnings.Add("Service '$($config.serviceName)' uses the legacy root WinSW layout and does not expose an explicit service account in XML, so the expected account cannot be inferred reliably. Reinstall with the current wrapper to capture service account metadata.")
  }

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

  $recoveryIssue = Get-ServiceRecoveryIssueMessage -Config $config -Context $recoveryContext
  if (-not [string]::IsNullOrWhiteSpace($recoveryIssue)) {
    $issues += $recoveryIssue
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

  if (-not $health.ok) {
    $issues += "Health endpoint is not healthy: $($health.error)"
  }

  $report = @{
    serviceName = $config.serviceName
    displayName = $config.tray.title
    installed   = $service.installed
    service     = $service
    restartTask = $restartTask
    controlTasks = $controlTasks
    controlState = $controlState
    runtime    = @{
      launchMode               = if ($null -ne $runtimeState -and $runtimeState.ContainsKey('launchMode')) { $runtimeState.launchMode } else { $null }
      requestedCommandPath     = if ($null -ne $runtimeState -and $runtimeState.ContainsKey('openclawCommand')) { $runtimeState.openclawCommand } else { $null }
      effectiveExecutablePath  = if ($null -ne $runtimeState -and $runtimeState.ContainsKey('effectiveExecutablePath')) { $runtimeState.effectiveExecutablePath } else { $null }
      entryScriptPath          = if ($null -ne $runtimeState -and $runtimeState.ContainsKey('entryScriptPath')) { $runtimeState.entryScriptPath } else { $null }
      wrapperProcessId         = if ($null -ne $runtimeState -and $runtimeState.ContainsKey('wrapperProcessId')) { $runtimeState.wrapperProcessId } else { 0 }
      gatewayProcessId         = if ($null -ne $runtimeState -and $runtimeState.ContainsKey('gatewayProcessId')) { $runtimeState.gatewayProcessId } else { 0 }
      liveListenerProcessIds   = @($liveListenerProcessIds)
      recordedListenerProcessIds = @($recordedListenerProcessIds)
    }
    proxy       = $proxy
    health      = $health
    healthUrl   = $config.healthUrl
    port        = $config.port
    config      = @{
      configSource   = $config.configSource
      sourcePath     = $config.sourceConfigPath
      rememberedPath = $config.rememberedPath
    }
    identity    = $identity
    warnings    = $warnings
    issues      = $issues
  }

  $exitCode = if ($service.installed -and $service.status -eq 'Running' -and $health.ok -and $issues.Count -eq 0) {
    0
  } else {
    1
  }

  return @{
    report       = $report
    exitCode     = $exitCode
    config       = $config
    paths        = $trayContext.paths
    errorMessage = $null
  }
}

function Get-FastTraySnapshotContext {
  param(
    [string]$ResolvedConfigPath
  )

  $currentWindowsIdentityName = Get-CurrentWindowsIdentityName
  $trayContext = Resolve-TrayControllerContext -ConfigPath $ResolvedConfigPath -CurrentWindowsIdentityName $currentWindowsIdentityName -AllowInvalidRemembered

  if ($trayContext.selection.ContainsKey('invalidReason')) {
    $snapshot = New-TrayStatusSnapshot `
      -ServiceName $trayContext.serviceName `
      -DisplayName $trayContext.serviceName `
      -Installed $false `
      -Service $null `
      -Health $null `
      -Issues @($trayContext.selection.invalidReason) `
      -RefreshKind 'fast' `
      -ConfigSource $trayContext.selection.configSource `
      -ConfigPath $trayContext.selection.sourcePath `
      -RememberedPath $trayContext.selection.rememberedPath `
      -ErrorMessage $trayContext.selection.invalidReason

    return @{
      snapshot = $snapshot
      exitCode = 1
      paths    = $trayContext.paths
    }
  }

  $recoveryContext = Get-ServiceRecoveryContext -Config $trayContext.config
  $service = $recoveryContext.service
  $cachedSnapshot = $null
  try {
    $cachedSnapshot = Read-TrayStateCache -CachePath $trayContext.paths.cachePath
  } catch {
    $cachedSnapshot = $null
  }

  $cachedHealth = if ($null -ne $cachedSnapshot) { $cachedSnapshot.health } else { $null }
  $liveRecoveryIssue = Get-ServiceRecoveryIssueMessage -Config $trayContext.config -Context $recoveryContext
  $cachedIssues = if (-not [string]::IsNullOrWhiteSpace($liveRecoveryIssue)) {
    @($liveRecoveryIssue)
  } elseif ($null -ne $cachedSnapshot) {
    @($cachedSnapshot.issues)
  } else {
    @()
  }
  $cachedWarnings = if ($null -ne $cachedSnapshot) { @($cachedSnapshot.warnings) } else { @() }
  $lastDeepObservedAt = if ($null -ne $cachedSnapshot) { "$($cachedSnapshot.lastDeepObservedAt)" } else { $null }
  $healthObservedAt = if ($null -ne $cachedSnapshot -and $null -ne $cachedSnapshot.health) { "$($cachedSnapshot.health.observedAt)" } else { $null }
  $staleReason = if ($null -ne $cachedSnapshot) { "$($cachedSnapshot.staleReason)" } else { $null }

  $snapshot = New-TrayStatusSnapshot `
    -ServiceName $trayContext.config.serviceName `
    -DisplayName $trayContext.config.tray.title `
    -Installed ([bool]$service.installed) `
    -Service $service `
    -Health $cachedHealth `
    -Issues $cachedIssues `
    -Warnings $cachedWarnings `
    -RefreshKind 'fast' `
    -ConfigSource $trayContext.config.configSource `
    -ConfigPath $trayContext.config.sourceConfigPath `
    -RememberedPath $trayContext.config.rememberedPath `
    -IsStale:([bool]($null -ne $cachedSnapshot -and $cachedSnapshot.stale)) `
    -StaleReason $staleReason `
    -LastDeepObservedAt $lastDeepObservedAt `
    -HealthObservedAt $healthObservedAt

  $exitCode = if ($snapshot.state -eq 'healthy') { 0 } else { 1 }

  return @{
    snapshot = $snapshot
    exitCode = $exitCode
    paths    = $trayContext.paths
  }
}

function Convert-FullStatusToTraySnapshot {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$FullStatusContext
  )

  $report = $FullStatusContext.report
  $paths = if ($null -ne $FullStatusContext.config) {
    Get-TrayControllerPaths -Config $FullStatusContext.config
  } else {
    $FullStatusContext.paths
  }

  $configSource = if ($null -ne $report.config) { $report.config.configSource } else { $null }
  $sourcePath = if ($null -ne $report.config) { $report.config.sourcePath } else { $null }
  $rememberedPath = if ($null -ne $report.config) { $report.config.rememberedPath } else { $null }

  $snapshot = New-TrayStatusSnapshot `
    -ServiceName "$($report.serviceName)" `
    -DisplayName $(if ($null -ne $FullStatusContext.config) { $FullStatusContext.config.tray.title } else { $report.serviceName }) `
    -Installed ([bool]$report.installed) `
    -Service $report.service `
    -Health $report.health `
    -Issues @($report.issues) `
    -Warnings @($report.warnings) `
    -RefreshKind 'deep' `
    -ConfigSource $configSource `
    -ConfigPath $sourcePath `
    -RememberedPath $rememberedPath `
    -ErrorMessage $FullStatusContext.errorMessage

  if ($null -ne $paths -and -not [string]::IsNullOrWhiteSpace($paths.cachePath)) {
    Write-TrayStateCache -CachePath $paths.cachePath -Snapshot $snapshot | Out-Null
  }

  return @{
    snapshot = $snapshot
    exitCode = $FullStatusContext.exitCode
    paths    = $paths
  }
}

function Write-FullStatusReport {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Report
  )

  $config = $Report.config
  $identity = $Report.identity
  $service = $Report.service
  $restartTask = $Report.restartTask
  $controlTasks = $Report.controlTasks
  $controlState = $Report.controlState
  $runtime = $Report.runtime
  $proxy = $Report.proxy
  $health = $Report.health
  $warnings = @($Report.warnings)
  $issues = @($Report.issues)

  Write-Host "Service name : $($Report.serviceName)"
  Write-Host "Config       : $($config.sourcePath) [$($config.configSource)]"
  Write-Host "Remembered   : $($config.rememberedPath)"
  Write-Host "Configured   : $($identity.configuredMode)"
  Write-Host "Deprecated   : $($identity.deprecatedAlias)"
  Write-Host "Expected run : $($identity.expectedStartName)"
  Write-Host "Actual run   : $($identity.actualStartName)"
  Write-Host "Layout       : $($identity.installLayout)"
  Write-Host "Installed    : $($service.installed)"
  Write-Host "Status       : $($service.status)"
  Write-Host "Transition   : $($service.transitionStatus)"
  Write-Host "Start type   : $($service.startType)"
  Write-Host "Restart task : $($restartTask.fullTaskName)"
  Write-Host "Task status  : $($restartTask.state)"
  Write-Host "Task matches : $($restartTask.matches)"
  Write-Host "Start task   : $($controlTasks.start.fullTaskName)"
  Write-Host "Start ok     : $($controlTasks.start.matches)"
  Write-Host "Stop task    : $($controlTasks.stop.fullTaskName)"
  Write-Host "Stop ok      : $($controlTasks.stop.matches)"
  Write-Host "Control run  : $(if ($null -ne $controlState) { $controlState.status } else { $null })"
  Write-Host "Launch mode  : $(if ($null -ne $runtime) { $runtime.launchMode } else { $null })"
  Write-Host "Gateway PID  : $(if ($null -ne $runtime) { $runtime.gatewayProcessId } else { 0 })"
  $listenersText = if ($null -eq $runtime) {
    ''
  } elseif (@($runtime.liveListenerProcessIds).Count -gt 0) {
    @($runtime.liveListenerProcessIds) -join ','
  } else {
    @($runtime.recordedListenerProcessIds) -join ','
  }
  Write-Host "Listeners    : $listenersText"
  Write-Host "HTTP proxy   : $($proxy.httpProxy.value) [$($proxy.httpProxy.source)]"
  Write-Host "HTTPS proxy  : $($proxy.httpsProxy.value) [$($proxy.httpsProxy.source)]"
  Write-Host "ALL proxy    : $($proxy.allProxy.value) [$($proxy.allProxy.source)]"
  Write-Host "NO_PROXY     : $($proxy.noProxy.value) [$($proxy.noProxy.source)]"
  Write-Host "Health URL   : $($Report.healthUrl)"
  if ($health.ok) {
    Write-Host "Health       : OK ($($health.statusCode))"
    Write-Host $health.body
  } else {
    Write-Host 'Health       : FAILED'
    Write-Host $health.error
  }

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

function Write-TraySnapshotReport {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Snapshot
  )

  Write-Host "Service name : $($Snapshot.serviceName)"
  Write-Host "Status       : $($Snapshot.summary)"
  Write-Host "State        : $($Snapshot.state)"
  Write-Host "Updated      : $($Snapshot.observedAt)"
  Write-Host "Refresh kind : $($Snapshot.refreshKind)"
  Write-Host "Summary      : $($Snapshot.summaryLine)"
}

try {
  if ($TraySnapshot) {
    $trayResult = if ($RefreshKind -eq 'fast') {
      Get-FastTraySnapshotContext -ResolvedConfigPath $ConfigPath
    } else {
      Convert-FullStatusToTraySnapshot -FullStatusContext (Get-FullStatusContext -ResolvedConfigPath $ConfigPath)
    }

    if ($Json) {
      $trayResult.snapshot | ConvertTo-Json -Depth 10
    } else {
      Write-TraySnapshotReport -Snapshot $trayResult.snapshot
    }

    exit $trayResult.exitCode
  }

  $fullContext = Get-FullStatusContext -ResolvedConfigPath $ConfigPath
  if ($Json) {
    $fullContext.report | ConvertTo-Json -Depth 10
  } else {
    Write-FullStatusReport -Report $fullContext.report
  }

  exit $fullContext.exitCode
} catch {
  Write-Error $_
  exit 1
}
