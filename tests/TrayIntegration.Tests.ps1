Describe 'tray integration wiring' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:installScriptText = Get-Content (Join-Path $script:repoRoot 'install.ps1') -Raw
    $script:uninstallScriptText = Get-Content (Join-Path $script:repoRoot 'uninstall.ps1') -Raw
    $script:buildReleaseScriptText = Get-Content (Join-Path $script:repoRoot 'build-release.ps1') -Raw
  }

  It 'adds a SkipTray parameter and tray registration to install.ps1' {
    $script:installScriptText | Should -Match '\[switch\]\$SkipTray'
    $script:installScriptText | Should -Match 'Install-TrayStartupShortcut'
    $script:installScriptText | Should -Match 'Tray startup'
  }

  It 'removes the tray shortcut during uninstall' {
    $script:uninstallScriptText | Should -Match 'Remove-TrayStartupShortcut'
  }

  It 'includes tray scripts in release packaging' {
    $script:buildReleaseScriptText | Should -Match 'control-service-task\.ps1'
    $script:buildReleaseScriptText | Should -Match 'invoke-service-action\.ps1'
    $script:buildReleaseScriptText | Should -Match 'invoke-tray-action\.ps1'
    $script:buildReleaseScriptText | Should -Match 'tray-controller\.ps1'
    $script:buildReleaseScriptText | Should -Match "'assets'"
  }

  It 'keeps tray snapshot support in status.ps1' {
    $statusScriptText = Get-Content (Join-Path $script:repoRoot 'status.ps1') -Raw

    $statusScriptText | Should -Match '\[switch\]\$TraySnapshot'
    $statusScriptText | Should -Match 'RefreshKind'
    $statusScriptText | Should -Match 'Write-TrayStateCache'
  }

  It 'keeps tray actions asynchronous so the UI thread is not blocked' {
    $trayControllerScriptText = Get-Content (Join-Path $script:repoRoot 'tray-controller.ps1') -Raw

    $trayControllerScriptText | Should -Match 'function Complete-ActionIfReady'
    $trayControllerScriptText | Should -Match '\$script:refreshTimer\.add_Tick\(\{\s+Complete-ActionIfReady'
    $trayControllerScriptText | Should -Not -Match 'Invoke-TrayAction[\s\S]*?-PassThru\s+`?\s*-Wait'
  }
}
