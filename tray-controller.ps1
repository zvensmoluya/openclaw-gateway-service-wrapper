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

function Test-IsRememberedConfigError {
  param(
    [AllowNull()]
    $Report
  )

  if ($null -eq $Report) {
    return $false
  }

  foreach ($issue in @($Report.issues)) {
    if ("$issue" -like 'Remembered config path not found:*') {
      return $true
    }
  }

  return $false
}

function Get-TrayStateFromStatusReport {
  param(
    [AllowNull()]
    $Report,
    [AllowNull()]
    [string]$ErrorMessage
  )

  if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
    return @{
      state       = 'error'
      summary     = 'Status unavailable'
      detail      = $ErrorMessage
      tooltipText = 'OpenClaw tray: status unavailable'
      canStart    = $false
      canStop     = $false
      canRestart  = $false
    }
  }

  if ($null -eq $Report) {
    return @{
      state       = 'error'
      summary     = 'Status unavailable'
      detail      = 'No status report was returned.'
      tooltipText = 'OpenClaw tray: status unavailable'
      canStart    = $false
      canStop     = $false
      canRestart  = $false
    }
  }

  if (Test-IsRememberedConfigError -Report $Report) {
    return @{
      state       = 'error'
      summary     = 'Config error'
      detail      = "$($Report.health.error)"
      tooltipText = 'OpenClaw tray: config error'
      canStart    = $false
      canStop     = $false
      canRestart  = $false
    }
  }

  $serviceStatus = if ($null -ne $Report.service) { "$($Report.service.status)" } else { '' }
  $installed = [bool]$Report.installed
  $healthOk = ($null -ne $Report.health) -and [bool]$Report.health.ok
  $serviceName = if ([string]::IsNullOrWhiteSpace("$($Report.serviceName)")) { 'OpenClaw' } else { "$($Report.serviceName)" }

  if ($installed -and $serviceStatus -eq 'Running' -and $healthOk) {
    return @{
      state       = 'healthy'
      summary     = 'Running'
      detail      = "$serviceName is healthy."
      tooltipText = "${serviceName}: Running"
      canStart    = $false
      canStop     = $true
      canRestart  = $true
    }
  }

  if ($installed -and $serviceStatus -eq 'Running' -and -not $healthOk) {
    $detail = if (-not [string]::IsNullOrWhiteSpace("$($Report.health.error)")) {
      "$($Report.health.error)"
    } else {
      "$serviceName is running but unhealthy."
    }

    return @{
      state       = 'unhealthy'
      summary     = 'Running with issues'
      detail      = $detail
      tooltipText = "${serviceName}: Unhealthy"
      canStart    = $false
      canStop     = $true
      canRestart  = $true
    }
  }

  if ($installed -and $serviceStatus -ne 'Running') {
    return @{
      state       = 'stopped'
      summary     = 'Stopped'
      detail      = "$serviceName is installed but not running."
      tooltipText = "${serviceName}: Stopped"
      canStart    = $true
      canStop     = $false
      canRestart  = $false
    }
  }

  return @{
    state       = 'stopped'
    summary     = 'Not installed'
    detail      = "$serviceName is not installed."
    tooltipText = "${serviceName}: Not installed"
    canStart    = $false
    canStop     = $false
    canRestart  = $false
  }
}

function Get-NotifyIconForState {
  param(
    [Parameter(Mandatory = $true)]
    [string]$State
  )

  switch ($State) {
    'healthy' { return [System.Drawing.SystemIcons]::Information }
    'unhealthy' { return [System.Drawing.SystemIcons]::Warning }
    'stopped' { return [System.Drawing.SystemIcons]::Application }
    default { return [System.Drawing.SystemIcons]::Error }
  }
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

function Invoke-StatusReport {
  $statusScript = Join-Path $PSScriptRoot 'status.ps1'
  $arguments = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $statusScript,
    '-Json'
  )

  if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $arguments += @('-ConfigPath', $ConfigPath)
  }

  try {
    $output = & (Get-WindowsPowerShellExecutablePath) @arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = (($output | ForEach-Object { "$_" }) -join [Environment]::NewLine).Trim()
  } catch {
    return @{
      report       = $null
      exitCode     = 1
      errorMessage = Get-PrimaryOutputMessage -Lines @($_.Exception.Message) -Fallback 'status.ps1 invocation failed.'
    }
  }

  if ([string]::IsNullOrWhiteSpace($text)) {
    return @{
      report      = $null
      exitCode    = $exitCode
      errorMessage = 'status.ps1 returned no JSON output.'
    }
  }

  try {
    return @{
      report      = ($text | ConvertFrom-Json)
      exitCode    = $exitCode
      errorMessage = $null
    }
  } catch {
    return @{
      report      = $null
      exitCode    = $exitCode
      errorMessage = 'status.ps1 returned invalid JSON.'
    }
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

  $script:notifyIcon.BalloonTipTitle = $Title
  $script:notifyIcon.BalloonTipText = $Text
  $script:notifyIcon.ShowBalloonTip(4000)
}

function Update-TrayState {
  if ($script:isBusy) {
    return
  }

  $status = Invoke-StatusReport
  $stateInfo = Get-TrayStateFromStatusReport -Report $status.report -ErrorMessage $status.errorMessage

  $script:lastStateInfo = $stateInfo
  $script:statusMenuItem.Text = "Status: $($stateInfo.summary)"
  $script:statusMenuItem.ToolTipText = $stateInfo.detail
  $script:startMenuItem.Enabled = $stateInfo.canStart
  $script:stopMenuItem.Enabled = $stateInfo.canStop
  $script:restartMenuItem.Enabled = $stateInfo.canRestart
  $script:notifyIcon.Icon = Get-NotifyIconForState -State $stateInfo.state
  $script:notifyIcon.Text = if ($stateInfo.tooltipText.Length -gt 63) {
    $stateInfo.tooltipText.Substring(0, 63)
  } else {
    $stateInfo.tooltipText
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

  if ($script:isBusy) {
    return
  }

  $script:isBusy = $true
  $script:statusMenuItem.Text = "Status: ${Action} in progress..."
  $script:startMenuItem.Enabled = $false
  $script:stopMenuItem.Enabled = $false
  $script:restartMenuItem.Enabled = $false

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

    $process = Start-Process -FilePath (Get-WindowsPowerShellExecutablePath) `
      -ArgumentList (ConvertTo-ArgumentString -Arguments $arguments) `
      -Verb RunAs `
      -WindowStyle Hidden `
      -PassThru `
      -Wait

    $exitCode = $process.ExitCode
    $resultMessage = $null
    if (Test-Path -LiteralPath $resultPath) {
      $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
      $resultMessage = "$($result.message)"
    }

    if ($exitCode -eq 0) {
      if ([string]::IsNullOrWhiteSpace($resultMessage)) {
        $resultMessage = "Service action '$Action' completed."
      }

      Show-TrayBalloon -Title 'OpenClaw Service' -Text $resultMessage -Icon ([System.Windows.Forms.ToolTipIcon]::Info)
      return
    }

    if ([string]::IsNullOrWhiteSpace($resultMessage)) {
      $resultMessage = "Service action '$Action' failed."
    }

    Show-TrayBalloon -Title 'OpenClaw Service' -Text $resultMessage -Icon ([System.Windows.Forms.ToolTipIcon]::Error)
  } catch {
    if (Test-IsElevationCanceled -Exception $_.Exception) {
      Show-TrayBalloon -Title 'OpenClaw Service' -Text 'Action canceled at the UAC prompt.' -Icon ([System.Windows.Forms.ToolTipIcon]::Warning)
    } else {
      Show-TrayBalloon -Title 'OpenClaw Service' -Text (Get-PrimaryOutputMessage -Lines @($_.Exception.Message) -Fallback "Service action '$Action' failed.") -Icon ([System.Windows.Forms.ToolTipIcon]::Error)
    }
  } finally {
    if (Test-Path -LiteralPath $resultPath) {
      Remove-Item -LiteralPath $resultPath -Force
    }

    $script:isBusy = $false
    Update-TrayState
  }
}

if ($NoRun) {
  return
}

$script:isBusy = $false
$script:lastStateInfo = $null
$script:applicationContext = New-Object System.Windows.Forms.ApplicationContext
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$script:statusMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:startMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:stopMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:restartMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:refreshMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:refreshTimer = New-Object System.Windows.Forms.Timer

$script:statusMenuItem.Text = 'Status: Checking...'
$script:statusMenuItem.Enabled = $false
$script:startMenuItem.Text = 'Start'
$script:stopMenuItem.Text = 'Stop'
$script:restartMenuItem.Text = 'Restart'
$script:refreshMenuItem.Text = 'Refresh'
$script:exitMenuItem.Text = 'Exit Tray'

[void]$script:contextMenu.Items.Add($script:statusMenuItem)
[void]$script:contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$script:contextMenu.Items.Add($script:startMenuItem)
[void]$script:contextMenu.Items.Add($script:stopMenuItem)
[void]$script:contextMenu.Items.Add($script:restartMenuItem)
[void]$script:contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$script:contextMenu.Items.Add($script:refreshMenuItem)
[void]$script:contextMenu.Items.Add($script:exitMenuItem)

$script:notifyIcon.ContextMenuStrip = $script:contextMenu
$script:notifyIcon.Text = 'OpenClaw tray: starting'
$script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
$script:notifyIcon.Visible = $true

$script:startMenuItem.add_Click({ Invoke-TrayAction -Action 'start' })
$script:stopMenuItem.add_Click({ Invoke-TrayAction -Action 'stop' })
$script:restartMenuItem.add_Click({ Invoke-TrayAction -Action 'restart' })
$script:refreshMenuItem.add_Click({ Update-TrayState })
$script:exitMenuItem.add_Click({
  $script:refreshTimer.Stop()
  $script:notifyIcon.Visible = $false
  $script:applicationContext.ExitThread()
})
$script:contextMenu.add_Opening({ Update-TrayState })
$script:refreshTimer.Interval = 10000
$script:refreshTimer.add_Tick({ Update-TrayState })
$script:refreshTimer.Start()

try {
  Update-TrayState
  [System.Windows.Forms.Application]::Run($script:applicationContext)
} finally {
  $script:refreshTimer.Stop()
  $script:refreshTimer.Dispose()
  $script:contextMenu.Dispose()
  $script:notifyIcon.Dispose()
}
