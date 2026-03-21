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
    Assert-Equal $config.serviceAccountMode 'credential'
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

  It 'rejects non-string proxy config values' {
    $tempConfig = Join-Path $env:TEMP 'openclaw-wrapper-test-invalid-proxy-config.json'
    @'
{
  "httpProxy": 123,
  "logPolicy": {
    "mode": "rotate"
  }
}
'@ | Set-Content -LiteralPath $tempConfig -Encoding UTF8

    try {
      $identity = Get-ServiceIdentityContext -Mode 'currentUser'
      { Get-ServiceConfig -ConfigPath $tempConfig -IdentityContext $identity } | Should -Throw '*httpProxy must be a string when provided.*'
    } finally {
      if (Test-Path -LiteralPath $tempConfig) {
        Remove-Item -LiteralPath $tempConfig -Force
      }
    }
  }

  It 'preserves proxy config presence and trims proxy values' {
    $tempConfig = Join-Path $env:TEMP 'openclaw-wrapper-test-proxy-config.json'
    @'
{
  "httpProxy": "  http://proxy.example:8080  ",
  "noProxy": " localhost,127.0.0.1 ",
  "logPolicy": {
    "mode": "rotate"
  }
}
'@ | Set-Content -LiteralPath $tempConfig -Encoding UTF8

    try {
      $identity = Get-ServiceIdentityContext -Mode 'currentUser'
      $config = Get-ServiceConfig -ConfigPath $tempConfig -IdentityContext $identity

      $config.httpProxy | Should -Be 'http://proxy.example:8080'
      $config.noProxy | Should -Be 'localhost,127.0.0.1'
      $config.proxyConfigPresence.httpProxy | Should -BeTrue
      $config.proxyConfigPresence.noProxy | Should -BeTrue
      $config.proxyConfigPresence.httpsProxy | Should -BeFalse
      $config.proxyConfigPresence.allProxy | Should -BeFalse
    } finally {
      if (Test-Path -LiteralPath $tempConfig) {
        Remove-Item -LiteralPath $tempConfig -Force
      }
    }
  }

  It 'injects wrapper proxy values into the process environment' {
    $originalHttp = [System.Environment]::GetEnvironmentVariable('HTTP_PROXY', 'Process')
    $originalHttps = [System.Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Process')
    $originalAll = [System.Environment]::GetEnvironmentVariable('ALL_PROXY', 'Process')
    $originalNo = [System.Environment]::GetEnvironmentVariable('NO_PROXY', 'Process')

    try {
      [System.Environment]::SetEnvironmentVariable('HTTP_PROXY', $null, 'Process')
      [System.Environment]::SetEnvironmentVariable('HTTPS_PROXY', $null, 'Process')
      [System.Environment]::SetEnvironmentVariable('ALL_PROXY', $null, 'Process')
      [System.Environment]::SetEnvironmentVariable('NO_PROXY', $null, 'Process')

      $config = @{
        httpProxy = $null
        httpsProxy = $null
        allProxy = $null
        noProxy = $null
      }
      $config.proxyConfigPresence = @{
        httpProxy  = $true
        httpsProxy = $true
        allProxy   = $true
        noProxy    = $true
      }
      $config.httpProxy = 'http://proxy.example:8080'
      $config.httpsProxy = 'http://secure-proxy.example:8443'
      $config.allProxy = 'socks5://proxy.example:1080'
      $config.noProxy = 'localhost,127.0.0.1'

      [void](Set-WrapperProxyEnvironment -Config $config)

      [System.Environment]::GetEnvironmentVariable('HTTP_PROXY', 'Process') | Should -Be 'http://proxy.example:8080'
      [System.Environment]::GetEnvironmentVariable('http_proxy', 'Process') | Should -Be 'http://proxy.example:8080'
      [System.Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Process') | Should -Be 'http://secure-proxy.example:8443'
      [System.Environment]::GetEnvironmentVariable('https_proxy', 'Process') | Should -Be 'http://secure-proxy.example:8443'
      [System.Environment]::GetEnvironmentVariable('ALL_PROXY', 'Process') | Should -Be 'socks5://proxy.example:1080'
      [System.Environment]::GetEnvironmentVariable('all_proxy', 'Process') | Should -Be 'socks5://proxy.example:1080'
      [System.Environment]::GetEnvironmentVariable('NO_PROXY', 'Process') | Should -Be 'localhost,127.0.0.1'
      [System.Environment]::GetEnvironmentVariable('no_proxy', 'Process') | Should -Be 'localhost,127.0.0.1'
    } finally {
      [System.Environment]::SetEnvironmentVariable('HTTP_PROXY', $originalHttp, 'Process')
      [System.Environment]::SetEnvironmentVariable('HTTPS_PROXY', $originalHttps, 'Process')
      [System.Environment]::SetEnvironmentVariable('ALL_PROXY', $originalAll, 'Process')
      [System.Environment]::SetEnvironmentVariable('NO_PROXY', $originalNo, 'Process')
    }
  }

  It 'does not overwrite ambient proxy values when wrapper proxy fields are omitted' {
    $originalHttp = [System.Environment]::GetEnvironmentVariable('HTTP_PROXY', 'Process')

    try {
      [System.Environment]::SetEnvironmentVariable('HTTP_PROXY', 'http://ambient.example:3128', 'Process')

      $config = @{
        httpProxy = $null
        httpsProxy = $null
        allProxy = $null
        noProxy = $null
      }
      $config.proxyConfigPresence = @{
        httpProxy  = $false
        httpsProxy = $false
        allProxy   = $false
        noProxy    = $false
      }

      [void](Set-WrapperProxyEnvironment -Config $config)

      [System.Environment]::GetEnvironmentVariable('HTTP_PROXY', 'Process') | Should -Be 'http://ambient.example:3128'
      $plan = Resolve-WrapperProxyEnvironmentPlan -Config $config
      $plan.httpProxy.source | Should -Be 'ambientEnvironment'
      $plan.httpProxy.value | Should -Be 'http://ambient.example:3128'
    } finally {
      [System.Environment]::SetEnvironmentVariable('HTTP_PROXY', $originalHttp, 'Process')
    }
  }

  It 'clears ambient proxy values when wrapper proxy fields are explicitly empty' {
    $originalHttp = [System.Environment]::GetEnvironmentVariable('HTTP_PROXY', 'Process')

    try {
      [System.Environment]::SetEnvironmentVariable('HTTP_PROXY', 'http://ambient.example:3128', 'Process')

      $config = @{
        httpProxy = $null
        httpsProxy = $null
        allProxy = $null
        noProxy = $null
      }
      $config.proxyConfigPresence = @{
        httpProxy  = $true
        httpsProxy = $false
        allProxy   = $false
        noProxy    = $false
      }
      $config.httpProxy = ''

      [void](Set-WrapperProxyEnvironment -Config $config)

      [System.Environment]::GetEnvironmentVariable('HTTP_PROXY', 'Process') | Should -Be $null
      $plan = Resolve-WrapperProxyEnvironmentPlan -Config $config
      $plan.httpProxy.source | Should -Be 'wrapperConfig'
      $plan.httpProxy.clearRequested | Should -BeTrue
    } finally {
      [System.Environment]::SetEnvironmentVariable('HTTP_PROXY', $originalHttp, 'Process')
    }
  }
}
