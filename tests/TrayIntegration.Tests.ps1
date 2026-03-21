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
    $script:buildReleaseScriptText | Should -Match 'invoke-tray-action\.ps1'
    $script:buildReleaseScriptText | Should -Match 'tray-controller\.ps1'
  }
}
