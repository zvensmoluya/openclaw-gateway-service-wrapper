Describe 'Get-ServiceConfig' {
  BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  }

  It 'loads the default repository config' {
    $identity = Get-ServiceIdentityContext -Mode 'currentUser'
    $config = Get-ServiceConfig -ConfigPath (Join-Path $repoRoot 'service-config.json') -IdentityContext $identity

    Assert-Equal $config.serviceName 'OpenClawService'
    Assert-Equal $config.port 18789
    Assert-Equal $config.healthUrl 'http://127.0.0.1:18789/health'
    Assert-MatchPattern $config.stateDir '\\.openclaw$'
  }

  It 'merges overrides from a custom config file' {
    $tempConfig = Join-Path $env:TEMP 'openclaw-wrapper-test-config.json'
    @'
{
  "serviceName": "CustomService",
  "port": 19001,
  "logPolicy": {
    "mode": "rotate"
  }
}
'@ | Set-Content -LiteralPath $tempConfig -Encoding UTF8

    try {
      $identity = Get-ServiceIdentityContext -Mode 'currentUser'
      $config = Get-ServiceConfig -ConfigPath $tempConfig -IdentityContext $identity

      Assert-Equal $config.serviceName 'CustomService'
      Assert-Equal $config.port 19001
      Assert-Equal $config.healthUrl 'http://127.0.0.1:19001/health'
      Assert-Equal $config.logPolicy.mode 'rotate'
    } finally {
      if (Test-Path -LiteralPath $tempConfig) {
        Remove-Item -LiteralPath $tempConfig -Force
      }
    }
  }
}
