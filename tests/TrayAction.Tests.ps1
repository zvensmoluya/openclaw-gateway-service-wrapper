Describe 'invoke-tray-action.ps1' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:actionScript = Join-Path $script:repoRoot 'invoke-tray-action.ps1'
    . $script:actionScript -Action start -NoInvoke
  }

  It 'resolves the shared service action invoker path' {
    (Resolve-ServiceActionInvokerPath) | Should -Be (Join-Path $script:repoRoot 'invoke-service-action.ps1')
  }

  It 'rejects unsupported actions before invocation' {
    & cmd.exe /c ('"{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}" -Action invalid >nul 2>nul' -f 'powershell.exe', $script:actionScript)

    $LASTEXITCODE | Should -Not -Be 0
  }
}
