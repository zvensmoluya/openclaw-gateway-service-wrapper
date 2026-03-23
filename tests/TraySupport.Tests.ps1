Describe 'tray controller support' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:repoRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking
    $script:trayControllerScript = Join-Path $script:repoRoot 'tray-controller.ps1'
    . $script:trayControllerScript -NoRun
  }

  BeforeEach {
    $script:testPaths = @()
    $script:trayConfig = @{
      title         = 'OpenClaw Service'
      notifications = 'all'
      refresh       = @{
        fastSeconds = 30
        deepSeconds = 180
        menuSeconds = 10
      }
      icons         = @{
        default      = $null
        healthy      = $null
        degraded     = $null
        unhealthy    = $null
        stopped      = $null
        error        = $null
        loading      = $null
        notInstalled = $null
      }
    }
    $script:trayDisplayName = 'OpenClaw Service'
    $script:trayContext = @{
      serviceName = 'OpenClawService'
    }
    $script:lastSnapshot = $null
    $script:refreshProcess = $null
    $script:refreshKind = $null
    $script:queuedRefreshKind = $null
    $script:isActionBusy = $false
    $script:lastFastCompletedAt = $null
    $script:lastDeepCompletedAt = $null
    $script:fastRefreshInterval = [TimeSpan]::FromSeconds(30)
    $script:deepRefreshInterval = [TimeSpan]::FromSeconds(180)
    $script:menuRefreshInterval = [TimeSpan]::FromSeconds(10)
  }

  AfterEach {
    foreach ($path in $script:testPaths) {
      if (Test-Path -LiteralPath $path) {
        if ((Get-Item -LiteralPath $path).PSIsContainer) {
          Remove-Item -LiteralPath $path -Recurse -Force
        } else {
          Remove-Item -LiteralPath $path -Force
        }
      }
    }
  }

  It 'builds hidden tray launch arguments' {
    $arguments = Get-TrayControllerLaunchArguments -ScriptPath (Join-Path $script:repoRoot 'tray-controller.ps1') -ConfigPath '.\service-config.local.json'

    $arguments | Should -Match '-WindowStyle Hidden'
    $arguments | Should -Match 'tray-controller\.ps1'
    $arguments | Should -Match '-ConfigPath'
    $arguments | Should -Match 'service-config\.local\.json'
  }

  It 'builds launcher arguments for the tray shortcut' {
    $arguments = Get-TrayControllerLauncherArguments -LauncherPath (Join-Path $script:repoRoot 'tray-controller-launcher.vbs') -ConfigPath '.\service-config.local.json'

    $arguments | Should -Match 'tray-controller-launcher\.vbs'
    $arguments | Should -Match 'service-config\.local\.json'
  }

  It 'creates and removes the tray startup shortcut' {
    $startupDirectory = Join-Path $env:TEMP "openclaw-startup-$([guid]::NewGuid().ToString('N'))"
    $script:testPaths += $startupDirectory
    $config = @{
      serviceName = 'TraySupportTest'
      displayName = 'Tray Support Test'
    }

    $shortcutPath = Install-TrayStartupShortcut -Config $config -ConfigPath '.\service-config.local.json' -StartupDirectory $startupDirectory

    Test-Path -LiteralPath $shortcutPath | Should -BeTrue
    $shortcutPath | Should -Be (Join-Path $startupDirectory 'TraySupportTest Tray Controller.lnk')

    $shell = New-Object -ComObject WScript.Shell
    try {
      $shortcut = $shell.CreateShortcut($shortcutPath)
      $shortcut.TargetPath | Should -Match 'wscript\.exe$'
      $shortcut.Arguments | Should -Match 'tray-controller-launcher\.vbs'
      $shortcut.Arguments | Should -Match 'service-config\.local\.json'
      $shortcut.Arguments | Should -Not -Match 'powershell\.exe'
    } finally {
      if ($null -ne $shortcut) {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut)
      }

      [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }

    Remove-TrayStartupShortcut -Config $config -StartupDirectory $startupDirectory | Should -BeTrue
    Test-Path -LiteralPath $shortcutPath | Should -BeFalse
  }

  It 'maps status reports to the expected tray states' {
    $healthy = Get-TrayStateFromStatusReport -Report ([pscustomobject]@{
      serviceName = 'OpenClawService'
      installed   = $true
      service     = [pscustomobject]@{ status = 'Running' }
      health      = [pscustomobject]@{ ok = $true; error = $null }
      issues      = @()
    })
    $degraded = Get-TrayStateFromStatusReport -Report ([pscustomobject]@{
      serviceName = 'OpenClawService'
      installed   = $true
      service     = [pscustomobject]@{ status = 'Running' }
      health      = [pscustomobject]@{ ok = $true; error = $null }
      issues      = @('Restart task is missing.')
      warnings    = @('Deprecated mode.')
    })
    $unhealthy = Get-TrayStateFromStatusReport -Report ([pscustomobject]@{
      serviceName = 'OpenClawService'
      installed   = $true
      service     = [pscustomobject]@{ status = 'Running' }
      health      = [pscustomobject]@{ ok = $false; error = 'Health endpoint is not healthy.' }
      issues      = @()
    })
    $stopped = Get-TrayStateFromStatusReport -Report ([pscustomobject]@{
      serviceName = 'OpenClawService'
      installed   = $true
      service     = [pscustomobject]@{ status = 'Stopped' }
      health      = [pscustomobject]@{ ok = $false; error = 'Service is stopped.' }
      issues      = @()
    })
    $error = Get-TrayStateFromStatusReport -Report ([pscustomobject]@{
      serviceName = 'OpenClawService'
      installed   = $false
      service     = [pscustomobject]@{ status = $null }
      health      = [pscustomobject]@{ ok = $false; error = 'Remembered config path not found: C:\missing.json' }
      issues      = @('Remembered config path not found: C:\missing.json')
    })
    $pending = Get-TrayStateFromStatusReport -Report ([pscustomobject]@{
      serviceName = 'OpenClawService'
      installed   = $true
      service     = [pscustomobject]@{ status = 'StopPending' }
      health      = [pscustomobject]@{ ok = $true; error = $null }
      issues      = @("Service 'OpenClawService' is stuck in StopPending while the gateway process is still alive. Clear the residual service process tree before starting again.")
    })

    $healthy.state | Should -Be 'healthy'
    $healthy.canRestart | Should -BeTrue
    $degraded.state | Should -Be 'degraded'
    $degraded.canStop | Should -BeTrue
    $degraded.issuesSummary | Should -Be 'Restart task is missing.'
    $unhealthy.state | Should -Be 'unhealthy'
    $unhealthy.canStop | Should -BeTrue
    $stopped.state | Should -Be 'stopped'
    $stopped.canStart | Should -BeTrue
    $error.state | Should -Be 'error'
    $error.canStart | Should -BeFalse
    $pending.state | Should -Be 'pending'
    $pending.canStart | Should -BeTrue
    $pending.canStop | Should -BeFalse
  }

  It 'prefers tray title over service name for display text' {
    $snapshot = New-LoadingTraySnapshot -ServiceName 'OpenClawService' -DisplayName 'OpenClaw Console'

    Get-TrayDisplayName -Snapshot $snapshot | Should -Be 'OpenClaw Console'
    $snapshot.tooltipText | Should -Be 'OpenClaw Console: Starting...'
  }

  It 'honors tray notification policy' {
    $script:trayConfig = @{
      notifications = 'errorsOnly'
    }

    Should-ShowTrayBalloon -Icon ([System.Windows.Forms.ToolTipIcon]::Info) | Should -BeFalse
    Should-ShowTrayBalloon -Icon ([System.Windows.Forms.ToolTipIcon]::Warning) | Should -BeTrue
    Should-ShowTrayBalloon -Icon ([System.Windows.Forms.ToolTipIcon]::Error) | Should -BeTrue

    $script:trayConfig.notifications = 'off'
    Should-ShowTrayBalloon -Icon ([System.Windows.Forms.ToolTipIcon]::Error) | Should -BeFalse
  }

  It 'orders configured tray icons before bundled assets' {
    $script:trayConfig = @{
      icons = @{
        default   = 'C:\icons\default.ico'
        unhealthy = 'C:\icons\unhealthy.ico'
      }
    }

    $candidatePaths = Get-TrayIconCandidatePaths -State 'unhealthy'

    $candidatePaths[0] | Should -Be 'C:\icons\unhealthy.ico'
    $candidatePaths[1] | Should -Be 'C:\icons\default.ico'
    $candidatePaths | Should -Contain (Join-Path $script:repoRoot 'assets\tray\openclaw-unhealthy.ico')
    $candidatePaths | Should -Contain (Join-Path $script:repoRoot 'assets\tray\openclaw.ico')
  }

  It 'skips scheduled fast refresh for healthy idle snapshots' {
    $script:lastSnapshot = @{
      state              = 'healthy'
      stale              = $false
      observedAt         = (Get-Date).AddMinutes(-5).ToString('o')
      lastDeepObservedAt = (Get-Date).AddMinutes(-1).ToString('o')
    }
    $script:lastFastCompletedAt = (Get-Date).AddMinutes(-5)
    $script:fastRefreshInterval = [TimeSpan]::FromSeconds(30)

    Should-RequestFastRefresh | Should -BeFalse
  }

  It 'does not queue a duplicate deep refresh while deep is already running' {
    $script:isActionBusy = $false
    $script:refreshKind = 'deep'
    $script:refreshProcess = [pscustomobject]@{
      HasExited = $false
    }
    $script:queuedRefreshKind = $null

    Request-TrayRefresh -Kind 'deep' -Reason 'menu-opening'

    $script:queuedRefreshKind | Should -Be $null
  }

  It 'promotes a queued refresh to deep when fast is in progress' {
    $script:isActionBusy = $false
    $script:refreshKind = 'fast'
    $script:refreshProcess = [pscustomobject]@{
      HasExited = $false
    }
    $script:queuedRefreshKind = $null

    Request-TrayRefresh -Kind 'deep' -Reason 'scheduled'

    $script:queuedRefreshKind | Should -Be 'deep'
  }

  It 'keeps pending summary text neutral instead of surfacing the raw issue' {
    $summary = Get-SummaryMenuText -Snapshot @{
      state         = 'pending'
      issuesSummary = "Service 'OpenClawService' is stuck in StopPending while the gateway process is still alive."
      summaryLine   = "Service 'OpenClawService' is stuck in StopPending while the gateway process is still alive."
    }

    $summary | Should -Be 'Info: Recovery may be required before starting again.'
  }

  It 'shows feedback when a tray action is already busy' {
    $script:isActionBusy = $true

    Mock Write-TrayLog {}
    Mock Show-TrayBalloon {}

    Invoke-TrayAction -Action 'start'

    Should -Invoke Write-TrayLog -Times 1 -Exactly
    Should -Invoke Show-TrayBalloon -Times 1 -Exactly
  }
}
