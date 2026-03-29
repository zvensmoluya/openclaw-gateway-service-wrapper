Describe 'cleanup-v2-legacy.ps1' {
  BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
  }

  It 'removes legacy artifacts without requiring a live service' {
    $tempRoot = Join-Path $env:TEMP ("openclaw-legacy-cleanup-test-" + [guid]::NewGuid().ToString('N'))
    $startupPath = Join-Path $tempRoot 'startup'
    $winswRoot = Join-Path $tempRoot 'winsw'
    $runtimeDir = Join-Path $tempRoot '.runtime'
    $runtimeSelectionPath = Join-Path $runtimeDir 'active-config.json'
    $wrapperConfigPath = Join-Path $tempRoot 'service-config.local.json'
    $legacyWinSWPath = Join-Path $winswRoot 'OpenClawService'

    try {
      New-Item -ItemType Directory -Force -Path $startupPath | Out-Null
      New-Item -ItemType Directory -Force -Path $legacyWinSWPath | Out-Null
      New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
      Set-Content -LiteralPath (Join-Path $startupPath 'OpenClawService Tray Controller.lnk') -Value 'stub'
      Set-Content -LiteralPath (Join-Path $startupPath 'OpenClawService Tray Controller.lnk.disabled-v2') -Value 'stub'
      Set-Content -LiteralPath (Join-Path $legacyWinSWPath 'OpenClawService.exe') -Value 'stub'
      Set-Content -LiteralPath $wrapperConfigPath -Value '{ "serviceName": "OpenClawService" }'
      Set-Content -LiteralPath $runtimeSelectionPath -Value ('{ "serviceName": "OpenClawService", "sourceConfigPath": "' + $wrapperConfigPath.Replace('\', '\\') + '" }')

      & (Join-Path $repoRoot 'cleanup-v2-legacy.ps1') -WrapperConfigPath $wrapperConfigPath -StartupPath $startupPath -WinSWRoot $winswRoot -RuntimeSelectionPath $runtimeSelectionPath -NoServiceUninstall

      Test-Path $legacyWinSWPath | Should -BeFalse
      Test-Path (Join-Path $startupPath 'OpenClawService Tray Controller.lnk') | Should -BeFalse
      Test-Path (Join-Path $startupPath 'OpenClawService Tray Controller.lnk.disabled-v2') | Should -BeFalse
      Test-Path $runtimeSelectionPath | Should -BeFalse
    } finally {
      if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
      }
    }
  }

  It 'is idempotent when no legacy artifacts exist' {
    $tempRoot = Join-Path $env:TEMP ("openclaw-legacy-cleanup-empty-" + [guid]::NewGuid().ToString('N'))
    $startupPath = Join-Path $tempRoot 'startup'
    $winswRoot = Join-Path $tempRoot 'winsw'
    $runtimeSelectionPath = Join-Path $tempRoot '.runtime\active-config.json'
    $wrapperConfigPath = Join-Path $tempRoot 'service-config.local.json'

    try {
      New-Item -ItemType Directory -Force -Path $startupPath | Out-Null
      New-Item -ItemType Directory -Force -Path $winswRoot | Out-Null
      Set-Content -LiteralPath $wrapperConfigPath -Value '{ "serviceName": "OpenClawService" }'

      & (Join-Path $repoRoot 'cleanup-v2-legacy.ps1') -WrapperConfigPath $wrapperConfigPath -StartupPath $startupPath -WinSWRoot $winswRoot -RuntimeSelectionPath $runtimeSelectionPath -NoServiceUninstall

      $LASTEXITCODE | Should -Be 0
    } finally {
      if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
      }
    }
  }
}
