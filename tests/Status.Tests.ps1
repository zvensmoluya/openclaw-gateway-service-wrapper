Describe 'status.ps1' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:repoRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking
    $script:statusScript = Join-Path $script:repoRoot 'status.ps1'

    function script:New-StatusTestConfig {
      $serviceName = "StatusTest-$([guid]::NewGuid().ToString('N'))"
      $configPath = Join-Path $env:TEMP "$serviceName-wrapper.json"
      $config = @{
        serviceName        = $serviceName
        displayName        = $serviceName
        description        = "Status test for $serviceName"
        serviceAccountMode = 'credential'
        port               = 19110
        stateDir           = (Join-Path $env:TEMP "$serviceName-state")
        configPath         = (Join-Path $env:TEMP "$serviceName-openclaw.json")
        tempDir            = (Join-Path $env:TEMP "$serviceName-temp")
        openclawCommand    = 'powershell.exe'
        logPolicy          = @{
          mode = 'rotate'
        }
      }

      Set-Content -LiteralPath $configPath -Value ($config | ConvertTo-Json -Depth 10) -Encoding UTF8
      return $configPath
    }

    function script:Invoke-StatusJson {
      param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
      )

      $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:statusScript -Json -ConfigPath $ConfigPath
      return @{
        exitCode = $LASTEXITCODE
        report   = ($output | ConvertFrom-Json)
      }
    }

    function script:Invoke-StatusWithMocks {
      param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$ServiceDetails,
        [Parameter(Mandatory = $true)]
        [hashtable]$Health
      )

      Mock Get-ServiceDetails { $ServiceDetails }
      Mock Invoke-HealthCheck { $Health }
      Mock Resolve-OpenClawCommandPath { 'powershell.exe' }

      & $script:statusScript -ConfigPath $ConfigPath -Json
      $report = $null
      if ($output) { }
    }
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

  It 'includes the identity report in JSON output' {
    $configPath = New-StatusTestConfig
    $script:testPaths += $configPath

    $result = Invoke-StatusJson -ConfigPath $configPath

    $result.exitCode | Should -Be 1
    $result.report.config.configSource | Should -Be 'explicit'
    $result.report.identity.configuredMode | Should -Be 'credential'
    $result.report.identity.installLayout | Should -Be 'generated'
    $result.report.identity.actualStartName | Should -Be $null
    $result.report.PSObject.Properties.Name | Should -Contain 'warnings'
    @($result.report.warnings).Count | Should -Be 0
    @($result.report.issues) | Should -Contain "Service '$($result.report.serviceName)' is not installed."
  }

  It 'returns success when only warnings are present' {
    $configPath = New-StatusTestConfig
    $script:testPaths += $configPath

    $config = Get-ServiceConfig -ConfigPath $configPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
    $serviceDetails = @{
      installed = $true
      name      = $config.serviceName
      status    = 'Running'
      startType = 'Automatic'
      processId = 1
      startName = 'CONTOSO\svc-openclaw'
      pathName  = ('"{0}"' -f (Join-Path $script:repoRoot 'tools\winsw\OpenClawService\OpenClawService.exe'))
    }
    $health = @{
      ok         = $true
      statusCode = 200
      body       = '{"ok":true}'
      error      = $null
    }

    Mock Get-ServiceDetails { $serviceDetails }
    Mock Invoke-HealthCheck { $health }
    Mock Resolve-OpenClawCommandPath { 'powershell.exe' }
    Mock Get-ServiceIdentityReport {
      @{
        configuredMode   = 'currentUser'
        deprecatedAlias  = $true
        expectedStartName = 'CONTOSO\svc-openclaw'
        actualStartName  = 'CONTOSO\svc-openclaw'
        matches          = $true
        installLayout    = 'generated'
      }
    }
    Mock Resolve-InspectionIdentityContext { Get-ServiceIdentityContext -Mode 'currentUser' }

    $output = & $script:statusScript -ConfigPath $configPath -Json
    $LASTEXITCODE | Should -Be 0
    $report = $output | ConvertFrom-Json

    $report.PSObject.Properties.Name | Should -Contain 'warnings'
    @($report.warnings).Count | Should -Be 1
    @($report.issues).Count | Should -Be 0
  }
}
