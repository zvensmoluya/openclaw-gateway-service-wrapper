Describe 'run-gateway environment handling' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:runGatewayScriptText = Get-Content (Join-Path $script:repoRoot 'run-gateway.ps1') -Raw
  }

  It 'keeps the real Windows user profile environment intact' {
    $script:runGatewayScriptText | Should -Not -Match '\$env:USERPROFILE\s*='
    $script:runGatewayScriptText | Should -Not -Match '\$env:HOME\s*='
    $script:runGatewayScriptText | Should -Not -Match '\$env:LOCALAPPDATA\s*='
    $script:runGatewayScriptText | Should -Not -Match '\$env:APPDATA\s*='
    $script:runGatewayScriptText | Should -Not -Match '\$env:TEMP\s*='
    $script:runGatewayScriptText | Should -Not -Match '\$env:TMP\s*='
    $script:runGatewayScriptText | Should -Not -Match '\$env:TMPDIR\s*='
  }
}
