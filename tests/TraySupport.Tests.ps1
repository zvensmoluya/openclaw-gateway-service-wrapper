Describe 'tray controller support' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:repoRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking
    $script:trayControllerScript = Join-Path $script:repoRoot 'tray-controller.ps1'
    . $script:trayControllerScript -NoRun
  }

  BeforeEach {
    $script:testPaths = @()
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

  It 'creates and removes the tray startup shortcut' {
    $startupDirectory = Join-Path $env:TEMP "openclaw-startup-$([guid]::NewGuid().ToString('N'))"
    $script:testPaths += $startupDirectory
    $config = @{
      serviceName = 'TraySupportTest'
      displayName = 'Tray Support Test'
    }

    $shortcutPath = Install-TrayStartupShortcut -Config $config -StartupDirectory $startupDirectory

    Test-Path -LiteralPath $shortcutPath | Should -BeTrue
    $shortcutPath | Should -Be (Join-Path $startupDirectory 'TraySupportTest Tray Controller.lnk')

    $shell = New-Object -ComObject WScript.Shell
    try {
      $shortcut = $shell.CreateShortcut($shortcutPath)
      $shortcut.TargetPath | Should -Match 'powershell\.exe$'
      $shortcut.Arguments | Should -Match 'tray-controller\.ps1'
      $shortcut.Arguments | Should -Match '-WindowStyle Hidden'
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

    $healthy.state | Should -Be 'healthy'
    $healthy.canRestart | Should -BeTrue
    $unhealthy.state | Should -Be 'unhealthy'
    $unhealthy.canStop | Should -BeTrue
    $stopped.state | Should -Be 'stopped'
    $stopped.canStart | Should -BeTrue
    $error.state | Should -Be 'error'
    $error.canStart | Should -BeFalse
  }
}
