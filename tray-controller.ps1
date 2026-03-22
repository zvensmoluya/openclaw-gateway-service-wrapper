[CmdletBinding()]
param(
  [string]$ConfigPath,
  [switch]$NoRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

function ConvertTo-PlainHashtable {
  param(
    [AllowNull()]
    $InputObject
  )

  if ($null -eq $InputObject) {
    return $null
  }

  if ($InputObject -is [System.Collections.IDictionary]) {
    $table = @{}
    foreach ($key in $InputObject.Keys) {
      $table[$key] = ConvertTo-PlainHashtable -InputObject $InputObject[$key]
    }

    return $table
  }

  if ($InputObject -is [pscustomobject]) {
    $table = @{}
    foreach ($property in $InputObject.PSObject.Properties) {
      $table[$property.Name] = ConvertTo-PlainHashtable -InputObject $property.Value
    }

    return $table
  }

  if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
    $items = @()
    foreach ($item in $InputObject) {
      $items += ,(ConvertTo-PlainHashtable -InputObject $item)
    }

    return $items
  }

  return $InputObject
}

function Get-WindowsPowerShellExecutablePath {
  $command = Get-Command -Name 'powershell.exe' -CommandType Application -ErrorAction SilentlyContinue
  if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
    return $command.Source
  }

  return (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
}

function ConvertTo-ArgumentString {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $quoted = foreach ($argument in $Arguments) {
    if ($argument -match '[\s"]') {
      '"{0}"' -f $argument.Replace('"', '\"')
      continue
    }

    $argument
  }

  return ($quoted -join ' ')
}

function Get-TrayStateFromStatusReport {
  param(
    [AllowNull()]
    $Report,
    [AllowNull()]
    [string]$ErrorMessage
  )

  if ($null -eq $Report) {
    $resolvedErrorMessage = if ([string]::IsNullOrWhiteSpace($ErrorMessage)) { 'No status report was returned.' } else { $ErrorMessage }
    $snapshot = New-TrayStatusSnapshot -ServiceName 'OpenClaw' -DisplayName 'OpenClaw' -Installed $false -Service $null -Health $null -RefreshKind 'deep' -ErrorMessage $resolvedErrorMessage
  } else {
    $reportTable = ConvertTo-PlainHashtable -InputObject $Report
    $config = if ($null -ne $reportTable -and $reportTable.ContainsKey('config')) { $reportTable.config } else { @{} }
    $warnings = if ($null -ne $reportTable -and $reportTable.ContainsKey('warnings')) { @($reportTable.warnings) } else { @() }
    $issues = if ($null -ne $reportTable -and $reportTable.ContainsKey('issues')) { @($reportTable.issues) } else { @() }
    $configSource = if ($config.ContainsKey('configSource')) { $config.configSource } else { $null }
    $configPathValue = if ($config.ContainsKey('sourcePath')) { $config.sourcePath } else { $null }
    $rememberedPath = if ($config.ContainsKey('rememberedPath')) { $config.rememberedPath } else { $null }
    $resolvedErrorMessage = $ErrorMessage
    if ([string]::IsNullOrWhiteSpace($resolvedErrorMessage)) {
      $resolvedErrorMessage = $issues | Where-Object { "$_" -like 'Remembered config path not found:*' } | Select-Object -First 1
    }
    $snapshot = New-TrayStatusSnapshot `
      -ServiceName "$($reportTable.serviceName)" `
      -DisplayName $(if ($reportTable.ContainsKey('displayName')) { "$($reportTable.displayName)" } else { "$($reportTable.serviceName)" }) `
      -Installed ([bool]$reportTable.installed) `
      -Service $reportTable.service `
      -Health $reportTable.health `
      -Issues $issues `
      -Warnings $warnings `
      -RefreshKind 'deep' `
      -ConfigSource $configSource `
      -ConfigPath $configPathValue `
      -RememberedPath $rememberedPath `
      -ErrorMessage $resolvedErrorMessage
  }

  $snapshot.canStart = [bool]$snapshot.actions.canStart
  $snapshot.canStop = [bool]$snapshot.actions.canStop
  $snapshot.canRestart = [bool]$snapshot.actions.canRestart
  return $snapshot
}

function New-LoadingTraySnapshot {
  param(
    [string]$ServiceName = 'OpenClaw',
    [string]$DisplayName = $ServiceName
  )

  return @{
    serviceName        = $ServiceName
    displayName        = $DisplayName
    observedAt         = (Get-Date).ToString('o')
    refreshKind        = 'fast'
    lastDeepObservedAt = $null
    state              = 'loading'
    summary            = 'Starting...'
    detail             = 'Tray controller is starting.'
    tooltipText        = "${DisplayName}: Starting..."
    stale              = $false
    staleReason        = $null
    config             = @{
      configSource   = $null
      sourcePath     = $null
      rememberedPath = $null
    }
    service            = @{
      installed = $false
      status    = $null
      name      = $ServiceName
      startType = $null
    }
    health             = @{
      ok         = $null
      statusCode = $null
      body       = $null
      error      = $null
      observedAt = $null
      source     = 'none'
    }
    actions            = @{
      canStart   = $false
      canStop    = $false
      canRestart = $false
    }
    issues             = @()
    warnings           = @()
    issuesSummary      = $null
    warningsSummary    = $null
    summaryLine        = 'Refreshing tray status in the background.'
  }
}

function ConvertFrom-IsoDateTime {
  param(
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $null
  }

  $parsed = [DateTime]::MinValue
  if ([DateTime]::TryParse($Value, [ref]$parsed)) {
    return $parsed
  }

  return $null
}

function Get-TrayInstanceMutexName {
  param(
    [string]$ServiceName
  )

  $resolvedServiceName = if ([string]::IsNullOrWhiteSpace($ServiceName)) { 'OpenClawService' } else { $ServiceName }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($resolvedServiceName.ToLowerInvariant())
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = [System.BitConverter]::ToString($algorithm.ComputeHash($bytes)).Replace('-', '')
  } finally {
    $algorithm.Dispose()
  }

  return "Local\OpenClaw.Tray.$hash"
}

function Initialize-TrayContext {
  $currentWindowsIdentityName = Get-CurrentWindowsIdentityName
  $script:trayContext = Resolve-TrayControllerContext -ConfigPath $ConfigPath -CurrentWindowsIdentityName $currentWindowsIdentityName -AllowInvalidRemembered
  $script:trayPaths = $script:trayContext.paths
  $script:trayLogPath = $script:trayPaths.logPath
  $script:trayConfig = if ($null -ne $script:trayContext.config -and $script:trayContext.config.ContainsKey('tray') -and ($script:trayContext.config.tray -is [hashtable])) {
    $script:trayContext.config.tray
  } else {
    $fallbackTrayConfig = Get-DefaultTrayConfig
    $fallbackTrayConfig.title = $script:trayContext.serviceName
    $fallbackTrayConfig
  }
  $script:trayDisplayName = if ([string]::IsNullOrWhiteSpace($script:trayConfig.title)) {
    $script:trayContext.serviceName
  } else {
    $script:trayConfig.title
  }
  $script:fastRefreshInterval = [TimeSpan]::FromSeconds($script:trayConfig.refresh.fastSeconds)
  $script:deepRefreshInterval = [TimeSpan]::FromSeconds($script:trayConfig.refresh.deepSeconds)
  $script:menuRefreshInterval = [TimeSpan]::FromSeconds($script:trayConfig.refresh.menuSeconds)
  Ensure-Directory -Path $script:trayPaths.runtimeStateDirectory
  Ensure-Directory -Path $script:trayPaths.logsDirectory
}

function Write-TrayLog {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message,
    [ValidateSet('INFO', 'WARN', 'ERROR')]
    [string]$Level = 'INFO'
  )

  if ([string]::IsNullOrWhiteSpace($script:trayLogPath)) {
    return
  }

  try {
    Ensure-Directory -Path (Split-Path -Parent $script:trayLogPath)
    Add-Content -LiteralPath $script:trayLogPath -Value ("{0} [{1}] {2}" -f (Get-Date).ToString('o'), $Level, $Message)
  } catch {
  }
}

function Get-TrayDisplayName {
  param(
    [AllowNull()]
    [hashtable]$Snapshot
  )

  if ($null -ne $Snapshot -and -not [string]::IsNullOrWhiteSpace("$($Snapshot.displayName)")) {
    return "$($Snapshot.displayName)"
  }

  if (-not [string]::IsNullOrWhiteSpace($script:trayDisplayName)) {
    return $script:trayDisplayName
  }

  return $script:trayContext.serviceName
}

function Get-TrayBalloonTitle {
  return (Get-TrayDisplayName -Snapshot $script:lastSnapshot)
}

function Get-TrayIconCandidatePaths {
  param(
    [Parameter(Mandatory = $true)]
    [string]$State
  )

  $paths = @()
  if ($null -ne $script:trayConfig -and $script:trayConfig.ContainsKey('icons') -and ($script:trayConfig.icons -is [hashtable])) {
    if (-not [string]::IsNullOrWhiteSpace("$($script:trayConfig.icons[$State])")) {
      $paths += "$($script:trayConfig.icons[$State])"
    }

    if (-not [string]::IsNullOrWhiteSpace("$($script:trayConfig.icons.default)")) {
      $paths += "$($script:trayConfig.icons.default)"
    }
  }

  $paths += @(
    (Join-Path $PSScriptRoot "assets\tray\openclaw-$State.ico"),
    (Join-Path $PSScriptRoot 'assets\tray\openclaw.ico'),
    (Join-Path $PSScriptRoot "assets\openclaw-$State.ico"),
    (Join-Path $PSScriptRoot 'assets\openclaw.ico')
  )

  return @($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Should-ShowTrayBalloon {
  param(
    [System.Windows.Forms.ToolTipIcon]$Icon = [System.Windows.Forms.ToolTipIcon]::Info
  )

  $notifications = if ($null -ne $script:trayConfig) { "$($script:trayConfig.notifications)" } else { 'all' }
  switch ($notifications) {
    'off' { return $false }
    'errorsOnly' { return ($Icon -ne [System.Windows.Forms.ToolTipIcon]::Info) }
    default { return $true }
  }
}

function Acquire-TrayMutex {
  $script:trayMutexName = Get-TrayInstanceMutexName -ServiceName $script:trayContext.serviceName
  $createdNew = $false
  $script:trayMutex = New-Object System.Threading.Mutex($true, $script:trayMutexName, [ref]$createdNew)
  $script:ownsTrayMutex = $createdNew
  if (-not $createdNew) {
    Write-TrayLog -Level 'WARN' -Message "Another tray controller instance is already running for '$($script:trayContext.serviceName)'."
    return $false
  }

  return $true
}

function Get-PrimaryOutputMessage {
  param(
    [AllowNull()]
    [string[]]$Lines,
    [string]$Fallback
  )

  $message = $Lines |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Select-Object -First 1

  if ([string]::IsNullOrWhiteSpace($message)) {
    return $Fallback
  }

  return $message.Trim()
}

function Get-NotifyIconForState {
  param(
    [Parameter(Mandatory = $true)]
    [string]$State
  )

  if ($script:customIcons.ContainsKey($State)) {
    return $script:customIcons[$State]
  }

  foreach ($candidatePath in (Get-TrayIconCandidatePaths -State $State)) {
    if (-not (Test-Path -LiteralPath $candidatePath)) {
      continue
    }

    try {
      $icon = New-Object System.Drawing.Icon($candidatePath)
      $script:customIcons[$State] = $icon
      return $icon
    } catch {
      Write-TrayLog -Level 'WARN' -Message "Failed to load custom tray icon '$candidatePath': $($_.Exception.Message)"
    }
  }

  switch ($State) {
    'healthy' { return [System.Drawing.SystemIcons]::Information }
    'degraded' { return [System.Drawing.SystemIcons]::Warning }
    'unhealthy' { return [System.Drawing.SystemIcons]::Warning }
    'pending' { return (Get-NotifyIconForState -State 'loading') }
    'stopped' { return [System.Drawing.SystemIcons]::Application }
    'notInstalled' { return [System.Drawing.SystemIcons]::Application }
    'loading' { return [System.Drawing.SystemIcons]::Application }
    default { return [System.Drawing.SystemIcons]::Error }
  }
}

function Show-TrayBalloon {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Title,
    [Parameter(Mandatory = $true)]
    [string]$Text,
    [System.Windows.Forms.ToolTipIcon]$Icon = [System.Windows.Forms.ToolTipIcon]::Info
  )

  if (-not (Should-ShowTrayBalloon -Icon $Icon)) {
    return
  }

  $script:notifyIcon.BalloonTipTitle = $Title
  $script:notifyIcon.BalloonTipText = $Text
  $script:notifyIcon.ShowBalloonTip(4000)
}

function Format-TrayTimestamp {
  param(
    [string]$Value
  )

  $parsed = ConvertFrom-IsoDateTime -Value $Value
  if ($null -eq $parsed) {
    return 'unknown'
  }

  return $parsed.ToLocalTime().ToString('HH:mm:ss')
}

function Get-RefreshStatusText {
  if ($null -eq $script:refreshProcess) {
    return $null
  }

  if ($script:refreshKind -eq 'deep') {
    return 'Refreshing full status in background...'
  }

  return 'Refreshing status in background...'
}

function Get-UpdatedMenuText {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Snapshot
  )

  $parts = @((Format-TrayTimestamp -Value "$($Snapshot.observedAt)"))
  if (-not [string]::IsNullOrWhiteSpace("$($Snapshot.refreshKind)")) {
    $parts += "$($Snapshot.refreshKind)"
  }

  if ([bool]$Snapshot.stale) {
    $parts += 'stale'
  }

  if ($null -ne $script:refreshProcess) {
    $parts += 'refreshing'
  }

  return "Updated: $($parts -join ' | ')"
}

function Get-SummaryMenuText {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Snapshot
  )

  $refreshText = Get-RefreshStatusText
  if (-not [string]::IsNullOrWhiteSpace($refreshText)) {
    return "Info: $refreshText"
  }

  switch ("$($Snapshot.state)") {
    'pending' {
      return 'Info: Recovery may be required before starting again.'
    }
    'degraded' {
      return 'Info: Attention needed.'
    }
    'unhealthy' {
      return 'Info: Health check is failing.'
    }
  }

  return "Info: $($Snapshot.summaryLine)"
}

function Refresh-TrayPresentation {
  if ($null -eq $script:lastSnapshot) {
    return
  }

  $snapshot = $script:lastSnapshot
  $displayName = Get-TrayDisplayName -Snapshot $snapshot
  $script:statusMenuItem.Text = "${displayName}: $($snapshot.summary)"
  $script:statusMenuItem.ToolTipText = "$($snapshot.detail)"
  $script:updatedMenuItem.Text = Get-UpdatedMenuText -Snapshot $snapshot
  $script:updatedMenuItem.ToolTipText = "Last deep refresh for ${displayName}: $(Format-TrayTimestamp -Value "$($snapshot.lastDeepObservedAt)")"
  $script:summaryMenuItem.Text = Get-SummaryMenuText -Snapshot $snapshot
  $script:summaryMenuItem.ToolTipText = "$($snapshot.detail)"

  $script:startMenuItem.Enabled = ([bool]$snapshot.actions.canStart) -and -not $script:isActionBusy
  $script:stopMenuItem.Enabled = ([bool]$snapshot.actions.canStop) -and -not $script:isActionBusy
  $script:restartMenuItem.Enabled = ([bool]$snapshot.actions.canRestart) -and -not $script:isActionBusy
  $script:refreshMenuItem.Enabled = -not $script:isActionBusy
  $script:notifyIcon.Icon = Get-NotifyIconForState -State "$($snapshot.state)"
  $tooltipText = if ([string]::IsNullOrWhiteSpace("$($snapshot.tooltipText)")) {
    "${displayName}: $($snapshot.summary)"
  } else {
    "$($snapshot.tooltipText)"
  }
  $script:notifyIcon.Text = if ($tooltipText.Length -gt 63) {
    $tooltipText.Substring(0, 63)
  } else {
    $tooltipText
  }
}

function Apply-TraySnapshot {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Snapshot
  )

  $script:lastSnapshot = ConvertTo-PlainHashtable -InputObject $Snapshot
  if ([string]::IsNullOrWhiteSpace("$($script:lastSnapshot.displayName)")) {
    $script:lastSnapshot.displayName = Get-TrayDisplayName -Snapshot $null
    if (-not [string]::IsNullOrWhiteSpace("$($script:lastSnapshot.summary)")) {
      $script:lastSnapshot.tooltipText = "$($script:lastSnapshot.displayName): $($script:lastSnapshot.summary)"
    }
  }
  Refresh-TrayPresentation
}

function Read-InitialTraySnapshot {
  try {
    return (Read-TrayStateCache -CachePath $script:trayPaths.cachePath)
  } catch {
    Write-TrayLog -Level 'WARN' -Message "Failed to read tray cache '$($script:trayPaths.cachePath)': $($_.Exception.Message)"
    return $null
  }
}

function Queue-RefreshKind {
  param(
    [ValidateSet('fast', 'deep')]
    [string]$Kind
  )

  if ($script:queuedRefreshKind -eq $null) {
    $script:queuedRefreshKind = $Kind
    return
  }

  if ($script:queuedRefreshKind -eq $Kind -or $script:queuedRefreshKind -eq 'deep') {
    return
  }

  if ($Kind -eq 'deep') {
    $script:queuedRefreshKind = 'deep'
  }
}

function Start-RefreshProcess {
  param(
    [ValidateSet('fast', 'deep')]
    [string]$Kind,
    [string]$Reason
  )

  $script:refreshOutputPath = Join-Path $env:TEMP "openclaw-tray-refresh-$([guid]::NewGuid().ToString('N')).json"
  $script:refreshErrorPath = Join-Path $env:TEMP "openclaw-tray-refresh-$([guid]::NewGuid().ToString('N')).err.txt"

  $statusScript = Join-Path $PSScriptRoot 'status.ps1'
  $arguments = @(
    '-NoProfile',
    '-WindowStyle',
    'Hidden',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $statusScript,
    '-Json',
    '-TraySnapshot',
    '-RefreshKind',
    $Kind
  )

  if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $arguments += @('-ConfigPath', $ConfigPath)
  }

  $script:refreshProcess = Start-Process `
    -FilePath (Get-WindowsPowerShellExecutablePath) `
    -ArgumentList (ConvertTo-ArgumentString -Arguments $arguments) `
    -WindowStyle Hidden `
    -RedirectStandardOutput $script:refreshOutputPath `
    -RedirectStandardError $script:refreshErrorPath `
    -PassThru
  $script:refreshKind = $Kind
  $script:lastRefreshRequestAt = Get-Date
  if ($Kind -eq 'deep') {
    $script:lastDeepRequestAt = $script:lastRefreshRequestAt
  } else {
    $script:lastFastRequestAt = $script:lastRefreshRequestAt
  }

  Write-TrayLog -Message "Started $Kind refresh ($Reason)."
  Refresh-TrayPresentation
}

function Request-TrayRefresh {
  param(
    [ValidateSet('fast', 'deep')]
    [string]$Kind,
    [string]$Reason
  )

  if ($null -ne $script:refreshProcess -and $script:refreshProcess.HasExited) {
    Complete-RefreshIfReady
  }

  if ($script:isActionBusy) {
    Queue-RefreshKind -Kind $Kind
    return
  }

  if ($null -ne $script:refreshProcess -and -not $script:refreshProcess.HasExited) {
    if ($script:refreshKind -eq 'deep') {
      return
    }

    if ($script:refreshKind -eq $Kind) {
      return
    }

    Queue-RefreshKind -Kind $Kind
    return
  }

  Start-RefreshProcess -Kind $Kind -Reason $Reason
}

function Cleanup-RefreshArtifacts {
  foreach ($path in @($script:refreshOutputPath, $script:refreshErrorPath)) {
    if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
      Remove-Item -LiteralPath $path -Force
    }
  }

  $script:refreshOutputPath = $null
  $script:refreshErrorPath = $null
}

function Cleanup-ActionArtifacts {
  if (-not [string]::IsNullOrWhiteSpace($script:actionResultPath) -and (Test-Path -LiteralPath $script:actionResultPath)) {
    Remove-Item -LiteralPath $script:actionResultPath -Force
  }

  $script:actionResultPath = $null
}

function Start-QueuedRefreshIfNeeded {
  if ([string]::IsNullOrWhiteSpace($script:queuedRefreshKind)) {
    return
  }

  $queuedKind = $script:queuedRefreshKind
  $script:queuedRefreshKind = $null
  Request-TrayRefresh -Kind $queuedKind -Reason 'queued'
}

function Get-LastRefreshCompletionTime {
  param(
    [ValidateSet('fast', 'deep')]
    [string]$Kind
  )

  $completedAt = if ($Kind -eq 'deep') { $script:lastDeepCompletedAt } else { $script:lastFastCompletedAt }
  if ($null -ne $completedAt) {
    return $completedAt
  }

  if ($null -eq $script:lastSnapshot) {
    return $null
  }

  if ($Kind -eq 'deep') {
    return (ConvertFrom-IsoDateTime -Value "$($script:lastSnapshot.lastDeepObservedAt)")
  }

  return (ConvertFrom-IsoDateTime -Value "$($script:lastSnapshot.observedAt)")
}

function Get-CurrentSnapshotAge {
  if ($null -eq $script:lastSnapshot) {
    return $null
  }

  $observedAt = ConvertFrom-IsoDateTime -Value "$($script:lastSnapshot.observedAt)"
  if ($null -eq $observedAt) {
    return $null
  }

  return ((Get-Date) - $observedAt)
}

function Complete-RefreshIfReady {
  if ($null -eq $script:refreshProcess -or -not $script:refreshProcess.HasExited) {
    return
  }

  $currentKind = $script:refreshKind
  $script:refreshProcess.WaitForExit()
  $stdout = if (Test-Path -LiteralPath $script:refreshOutputPath) { Get-Content -LiteralPath $script:refreshOutputPath -Raw } else { '' }
  $stderr = if (Test-Path -LiteralPath $script:refreshErrorPath) { Get-Content -LiteralPath $script:refreshErrorPath -Raw } else { '' }
  $exitCode = $script:refreshProcess.ExitCode

  try {
    if ([string]::IsNullOrWhiteSpace($stdout)) {
      throw "Tray refresh returned no JSON output. $stderr".Trim()
    }

    $snapshot = ConvertTo-PlainHashtable -InputObject ($stdout | ConvertFrom-Json)
    Apply-TraySnapshot -Snapshot $snapshot
    if ($currentKind -eq 'deep') {
      $script:lastDeepCompletedAt = Get-Date
    } else {
      $script:lastFastCompletedAt = Get-Date
    }

    Write-TrayLog -Message "$currentKind refresh completed with exit code $exitCode and state '$($snapshot.state)'."

    if ($script:startPhase -and $currentKind -eq 'deep') {
      $script:startPhase = $false
      if ($snapshot.state -eq 'error' -and -not $script:startupBalloonShown) {
        Show-TrayBalloon -Title (Get-TrayBalloonTitle) -Text "$($snapshot.detail)" -Icon ([System.Windows.Forms.ToolTipIcon]::Error)
        $script:startupBalloonShown = $true
      }
    }
  } catch {
    $failureMessage = Get-PrimaryOutputMessage -Lines @($_.Exception.Message, $stderr) -Fallback "$currentKind refresh failed."
    Write-TrayLog -Level 'ERROR' -Message $failureMessage

    if ($null -ne $script:lastSnapshot) {
      $staleSnapshot = Set-TrayStatusSnapshotStale -Snapshot $script:lastSnapshot -Reason $failureMessage -RefreshKind $currentKind
      Apply-TraySnapshot -Snapshot $staleSnapshot
    } else {
      $errorSnapshot = New-TrayStatusSnapshot -ServiceName $script:trayContext.serviceName -DisplayName $script:trayDisplayName -Installed $false -Service $null -Health $null -RefreshKind $currentKind -ErrorMessage $failureMessage
      Apply-TraySnapshot -Snapshot $errorSnapshot
    }

    if ($script:startPhase -and $currentKind -eq 'deep' -and -not $script:startupBalloonShown) {
      Show-TrayBalloon -Title (Get-TrayBalloonTitle) -Text $failureMessage -Icon ([System.Windows.Forms.ToolTipIcon]::Error)
      $script:startupBalloonShown = $true
      $script:startPhase = $false
    }
  } finally {
    Cleanup-RefreshArtifacts
    $script:refreshProcess.Dispose()
    $script:refreshProcess = $null
    $script:refreshKind = $null
    Refresh-TrayPresentation
    Start-QueuedRefreshIfNeeded
  }
}

function Complete-ActionIfReady {
  if ($null -eq $script:actionProcess -or -not $script:actionProcess.HasExited) {
    return
  }

  $script:actionProcess.WaitForExit()
  $actionName = $script:actionName
  $exitCode = $script:actionProcess.ExitCode
  $resultMessage = $null

  try {
    if (Test-Path -LiteralPath $script:actionResultPath) {
      $result = Get-Content -LiteralPath $script:actionResultPath -Raw | ConvertFrom-Json
      $resultMessage = "$($result.message)"
    }

    if ($exitCode -eq 0) {
      if ([string]::IsNullOrWhiteSpace($resultMessage)) {
        $resultMessage = "Service action '$actionName' completed."
      }

      Write-TrayLog -Message "Tray action '$actionName' completed successfully."
      Show-TrayBalloon -Title (Get-TrayBalloonTitle) -Text $resultMessage -Icon ([System.Windows.Forms.ToolTipIcon]::Info)
    } else {
      if ([string]::IsNullOrWhiteSpace($resultMessage)) {
        $resultMessage = "Service action '$actionName' failed."
      }

      Write-TrayLog -Level 'ERROR' -Message "Tray action '$actionName' failed: $resultMessage"
      Show-TrayBalloon -Title (Get-TrayBalloonTitle) -Text $resultMessage -Icon ([System.Windows.Forms.ToolTipIcon]::Error)
    }
  } catch {
    $message = Get-PrimaryOutputMessage -Lines @($_.Exception.Message) -Fallback "Service action '$actionName' failed."
    Write-TrayLog -Level 'ERROR' -Message "Tray action '$actionName' failed: $message"
    Show-TrayBalloon -Title (Get-TrayBalloonTitle) -Text $message -Icon ([System.Windows.Forms.ToolTipIcon]::Error)
  } finally {
    Cleanup-ActionArtifacts
    $script:actionProcess.Dispose()
    $script:actionProcess = $null
    $script:actionName = $null
    $script:isActionBusy = $false
    Refresh-TrayPresentation
    Request-TrayRefresh -Kind 'deep' -Reason "post-$actionName"
  }
}

function Should-RequestFastRefresh {
  if ($null -eq $script:lastSnapshot) {
    return $false
  }

  if ($script:lastSnapshot.state -eq 'healthy' -and -not [bool]$script:lastSnapshot.stale) {
    return $false
  }

  $reference = Get-LastRefreshCompletionTime -Kind 'fast'
  if ($null -eq $reference) {
    return $true
  }

  return (((Get-Date) - $reference) -ge $script:fastRefreshInterval)
}

function Should-RequestDeepRefresh {
  if ($null -eq $script:lastSnapshot) {
    return $true
  }

  if ([bool]$script:lastSnapshot.stale) {
    return $true
  }

  $reference = Get-LastRefreshCompletionTime -Kind 'deep'
  if ($null -eq $reference) {
    return $true
  }

  return (((Get-Date) - $reference) -ge $script:deepRefreshInterval)
}

function Invoke-ScheduledRefresh {
  if ($script:isActionBusy -or ($null -ne $script:refreshProcess)) {
    return
  }

  if (Should-RequestDeepRefresh) {
    Request-TrayRefresh -Kind 'deep' -Reason 'scheduled'
    return
  }

  if (Should-RequestFastRefresh) {
    Request-TrayRefresh -Kind 'fast' -Reason 'scheduled'
  }
}

function Test-IsElevationCanceled {
  param(
    [Parameter(Mandatory = $true)]
    $Exception
  )

  if ($Exception -is [System.ComponentModel.Win32Exception] -and $Exception.NativeErrorCode -eq 1223) {
    return $true
  }

  if ($Exception.HResult -eq -2147023673) {
    return $true
  }

  return ($Exception.Message -match 'cancel')
}

function Invoke-TrayAction {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop', 'restart')]
    [string]$Action
  )

  if ($script:isActionBusy) {
    Write-TrayLog -Level 'WARN' -Message "Tray action '$Action' ignored because another action is already running."
    Show-TrayBalloon -Title (Get-TrayBalloonTitle) -Text 'Another tray action is already in progress.' -Icon ([System.Windows.Forms.ToolTipIcon]::Warning)
    return
  }

  $script:isActionBusy = $true
  Refresh-TrayPresentation

  $resultPath = Join-Path $env:TEMP "openclaw-tray-action-$([guid]::NewGuid().ToString('N')).json"
  try {
    $helperScript = Join-Path $PSScriptRoot 'invoke-tray-action.ps1'
    $arguments = @(
      '-NoProfile',
      '-WindowStyle',
      'Hidden',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      $helperScript,
      '-Action',
      $Action,
      '-ResultPath',
      $resultPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
      $arguments += @('-ConfigPath', $ConfigPath)
    }

    Write-TrayLog -Message "Starting tray action '$Action'."
    $script:actionProcess = Start-Process -FilePath (Get-WindowsPowerShellExecutablePath) `
      -ArgumentList (ConvertTo-ArgumentString -Arguments $arguments) `
      -Verb RunAs `
      -WindowStyle Hidden `
      -PassThru
    $script:actionName = $Action
    $script:actionResultPath = $resultPath
    Refresh-TrayPresentation
  } catch {
    if (Test-IsElevationCanceled -Exception $_.Exception) {
      Write-TrayLog -Level 'WARN' -Message "Tray action '$Action' was canceled at the UAC prompt."
      Show-TrayBalloon -Title (Get-TrayBalloonTitle) -Text 'Action canceled at the UAC prompt.' -Icon ([System.Windows.Forms.ToolTipIcon]::Warning)
    } else {
      $message = Get-PrimaryOutputMessage -Lines @($_.Exception.Message) -Fallback "Service action '$Action' failed."
      Write-TrayLog -Level 'ERROR' -Message "Tray action '$Action' failed: $message"
      Show-TrayBalloon -Title (Get-TrayBalloonTitle) -Text $message -Icon ([System.Windows.Forms.ToolTipIcon]::Error)
    }
  } finally {
    if ($null -eq $script:actionProcess) {
      if (Test-Path -LiteralPath $resultPath) {
        Remove-Item -LiteralPath $resultPath -Force
      }

      $script:isActionBusy = $false
      Refresh-TrayPresentation
      Request-TrayRefresh -Kind 'deep' -Reason "post-$Action"
    }
  }
}

if ($NoRun) {
  return
}

$script:trayContext = $null
$script:trayPaths = $null
$script:trayLogPath = $null
$script:trayConfig = $null
$script:trayDisplayName = $null
$script:trayMutex = $null
$script:trayMutexName = $null
$script:ownsTrayMutex = $false
$script:lastSnapshot = $null
$script:refreshProcess = $null
$script:refreshKind = $null
$script:refreshOutputPath = $null
$script:refreshErrorPath = $null
$script:actionProcess = $null
$script:actionName = $null
$script:actionResultPath = $null
$script:queuedRefreshKind = $null
$script:lastRefreshRequestAt = $null
$script:lastFastRequestAt = $null
$script:lastDeepRequestAt = $null
$script:lastFastCompletedAt = $null
$script:lastDeepCompletedAt = $null
$script:fastRefreshInterval = [TimeSpan]::FromSeconds(30)
$script:deepRefreshInterval = [TimeSpan]::FromSeconds(180)
$script:menuRefreshInterval = [TimeSpan]::FromSeconds(10)
$script:isActionBusy = $false
$script:startPhase = $true
$script:startupBalloonShown = $false
$script:customIcons = @{}

Initialize-TrayContext
if (-not (Acquire-TrayMutex)) {
  return
}

Write-TrayLog -Message "Tray controller starting for '$($script:trayContext.serviceName)'."

$script:applicationContext = New-Object System.Windows.Forms.ApplicationContext
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$script:statusMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:updatedMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:summaryMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:startMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:stopMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:restartMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:refreshMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:refreshTimer = New-Object System.Windows.Forms.Timer

$script:statusMenuItem.Enabled = $false
$script:updatedMenuItem.Enabled = $false
$script:summaryMenuItem.Enabled = $false
$script:startMenuItem.Text = 'Start'
$script:stopMenuItem.Text = 'Stop'
$script:restartMenuItem.Text = 'Restart'
$script:refreshMenuItem.Text = 'Refresh Now'
$script:exitMenuItem.Text = 'Exit Tray'

[void]$script:contextMenu.Items.Add($script:statusMenuItem)
[void]$script:contextMenu.Items.Add($script:updatedMenuItem)
[void]$script:contextMenu.Items.Add($script:summaryMenuItem)
[void]$script:contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$script:contextMenu.Items.Add($script:startMenuItem)
[void]$script:contextMenu.Items.Add($script:stopMenuItem)
[void]$script:contextMenu.Items.Add($script:restartMenuItem)
[void]$script:contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$script:contextMenu.Items.Add($script:refreshMenuItem)
[void]$script:contextMenu.Items.Add($script:exitMenuItem)

$script:notifyIcon.ContextMenuStrip = $script:contextMenu
$script:notifyIcon.Visible = $true

$initialSnapshot = Read-InitialTraySnapshot
if ($null -eq $initialSnapshot) {
  $initialSnapshot = New-LoadingTraySnapshot -ServiceName $script:trayContext.serviceName -DisplayName $script:trayDisplayName
}

Apply-TraySnapshot -Snapshot $initialSnapshot

$script:startMenuItem.add_Click({ Invoke-TrayAction -Action 'start' })
$script:stopMenuItem.add_Click({ Invoke-TrayAction -Action 'stop' })
$script:restartMenuItem.add_Click({ Invoke-TrayAction -Action 'restart' })
$script:refreshMenuItem.add_Click({ Request-TrayRefresh -Kind 'deep' -Reason 'manual' })
$script:exitMenuItem.add_Click({
  $script:refreshTimer.Stop()
  if ($null -ne $script:refreshProcess -and -not $script:refreshProcess.HasExited) {
    try {
      $script:refreshProcess.Kill()
    } catch {
    }
  }

  Cleanup-ActionArtifacts
  $script:notifyIcon.Visible = $false
  $script:applicationContext.ExitThread()
})
$script:contextMenu.add_Opening({
  if (Should-RequestDeepRefresh) {
    Request-TrayRefresh -Kind 'deep' -Reason 'menu-opening'
    return
  }

  $age = Get-CurrentSnapshotAge
  if ($null -eq $age -or $age -ge $script:menuRefreshInterval) {
    Request-TrayRefresh -Kind 'fast' -Reason 'menu-opening'
  }
})
$script:refreshTimer.Interval = 1000
$script:refreshTimer.add_Tick({
  Complete-ActionIfReady
  Complete-RefreshIfReady
  Invoke-ScheduledRefresh
})
$script:refreshTimer.Start()

try {
  Request-TrayRefresh -Kind 'deep' -Reason 'startup'
  [System.Windows.Forms.Application]::Run($script:applicationContext)
} finally {
  Write-TrayLog -Message 'Tray controller shutting down.'
  $script:refreshTimer.Stop()
  $script:refreshTimer.Dispose()
  $script:contextMenu.Dispose()
  $script:notifyIcon.Dispose()

  foreach ($icon in $script:customIcons.Values) {
    if ($null -ne $icon) {
      $icon.Dispose()
    }
  }

  Cleanup-RefreshArtifacts
  if ($null -ne $script:refreshProcess) {
    $script:refreshProcess.Dispose()
  }

  Cleanup-ActionArtifacts
  if ($null -ne $script:actionProcess) {
    $script:actionProcess.Dispose()
  }

  if ($script:ownsTrayMutex -and $null -ne $script:trayMutex) {
    try {
      $script:trayMutex.ReleaseMutex()
    } catch {
    }
  }

  if ($null -ne $script:trayMutex) {
    $script:trayMutex.Dispose()
  }
}
