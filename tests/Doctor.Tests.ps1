Describe 'doctor.ps1' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:repoRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking
    $script:doctorScript = Join-Path $script:repoRoot 'doctor.ps1'
    $script:rememberedMetadataPath = Get-RememberedConfigMetadataPath
    $script:rememberedMetadataBackup = $null

    if (Test-Path -LiteralPath $script:rememberedMetadataPath) {
      $script:rememberedMetadataBackup = Join-Path $env:TEMP "doctor-active-config-backup-$([guid]::NewGuid()).json"
      Copy-Item -LiteralPath $script:rememberedMetadataPath -Destination $script:rememberedMetadataBackup -Force
    }

    function script:New-DoctorTestConfig {
      param(
        [Parameter(Mandatory = $true)]
        [string]$GatewayConfigPath,
        [Parameter(Mandatory = $true)]
        [string]$StateDir,
        [hashtable]$Overrides = @{}
      )

      $serviceName = "DoctorTest-$([guid]::NewGuid().ToString('N'))"
      $configPath = Join-Path $env:TEMP "$serviceName-wrapper.json"
      $config = @{
        serviceName     = $serviceName
        displayName     = $serviceName
        description     = "Doctor test for $serviceName"
        port            = 19100
        stateDir        = $StateDir
        configPath      = $GatewayConfigPath
        tempDir         = $env:TEMP
        openclawCommand = 'powershell.exe'
        logPolicy       = @{
          mode = 'rotate'
        }
      }

      foreach ($key in $Overrides.Keys) {
        $config[$key] = $Overrides[$key]
      }

      Set-Content -LiteralPath $configPath -Value ($config | ConvertTo-Json -Depth 10) -Encoding UTF8
      return $configPath
    }

    function script:Invoke-DoctorJson {
      param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
      )

      $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:doctorScript -Json -ConfigPath $ConfigPath
      return @{
        exitCode = $LASTEXITCODE
        report   = ($output | ConvertFrom-Json)
      }
    }

    function script:Normalize-TestPath {
      param(
        [Parameter(Mandatory = $true)]
        [string]$Path
      )

      if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
      }

      return [System.IO.Path]::GetFullPath((Join-Path $script:repoRoot $Path))
    }
  }

  BeforeEach {
    [void](Clear-RememberedServiceConfigSelection)
    $script:testPaths = @()
  }

  AfterEach {
    [void](Clear-RememberedServiceConfigSelection)
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

  AfterAll {
    [void](Clear-RememberedServiceConfigSelection)

    if ($null -ne $script:rememberedMetadataBackup -and (Test-Path -LiteralPath $script:rememberedMetadataBackup)) {
      New-Item -ItemType Directory -Path (Split-Path -Parent $script:rememberedMetadataPath) -Force | Out-Null
      Copy-Item -LiteralPath $script:rememberedMetadataBackup -Destination $script:rememberedMetadataPath -Force
      Remove-Item -LiteralPath $script:rememberedMetadataBackup -Force
    }
  }

  It 'reports a missing OpenClaw config file' {
    $stateDir = Join-Path $env:TEMP "doctor-state-$([guid]::NewGuid())"
    $gatewayDir = Join-Path $env:TEMP "doctor-gateway-$([guid]::NewGuid())"
    $gatewayConfigPath = Join-Path $gatewayDir 'openclaw.json'
    $configPath = New-DoctorTestConfig -GatewayConfigPath $gatewayConfigPath -StateDir $stateDir
    $expectedConfigPath = Normalize-TestPath -Path $configPath
    $expectedGatewayConfigPath = Normalize-TestPath -Path $gatewayConfigPath
    $script:testPaths += @($stateDir, $gatewayDir, $configPath)

    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    New-Item -ItemType Directory -Path $gatewayDir -Force | Out-Null

    $result = Invoke-DoctorJson -ConfigPath $configPath

    $result.exitCode | Should -Be 1
    $result.report.config.configSource | Should -Be 'explicit'
    $result.report.config.sourcePath | Should -Be $expectedConfigPath
    $result.report.identity.configuredMode | Should -Be 'credential'
    $result.report.identity.installLayout | Should -Be 'generated'
    $result.report.PSObject.Properties.Name | Should -Contain 'warnings'
    @($result.report.warnings).Count | Should -Be 0
    @($result.report.issues) | Should -Contain "Gateway config file does not exist: $expectedGatewayConfigPath"
  }

  It 'reports invalid OpenClaw config JSON' {
    $stateDir = Join-Path $env:TEMP "doctor-state-$([guid]::NewGuid())"
    $gatewayDir = Join-Path $env:TEMP "doctor-gateway-$([guid]::NewGuid())"
    $gatewayConfigPath = Join-Path $gatewayDir 'openclaw.json'
    $configPath = New-DoctorTestConfig -GatewayConfigPath $gatewayConfigPath -StateDir $stateDir
    $expectedGatewayConfigPath = Normalize-TestPath -Path $gatewayConfigPath
    $script:testPaths += @($stateDir, $gatewayDir, $gatewayConfigPath, $configPath)

    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    New-Item -ItemType Directory -Path $gatewayDir -Force | Out-Null
    Set-Content -LiteralPath $gatewayConfigPath -Value '{ invalid json' -Encoding UTF8

    $result = Invoke-DoctorJson -ConfigPath $configPath

    $result.exitCode | Should -Be 1
    (@($result.report.issues) | Where-Object { $_ -like "Gateway config file is not valid JSON: $expectedGatewayConfigPath*" }).Count | Should -Be 1
  }

  It 'accepts a valid OpenClaw config file' {
    $stateDir = Join-Path $env:TEMP "doctor-state-$([guid]::NewGuid())"
    $gatewayDir = Join-Path $env:TEMP "doctor-gateway-$([guid]::NewGuid())"
    $gatewayConfigPath = Join-Path $gatewayDir 'openclaw.json'
    $configPath = New-DoctorTestConfig -GatewayConfigPath $gatewayConfigPath -StateDir $stateDir
    $script:testPaths += @($stateDir, $gatewayDir, $gatewayConfigPath, $configPath)

    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    New-Item -ItemType Directory -Path $gatewayDir -Force | Out-Null
    Set-Content -LiteralPath $gatewayConfigPath -Value (@{ name = 'test' } | ConvertTo-Json -Depth 10) -Encoding UTF8

    $result = Invoke-DoctorJson -ConfigPath $configPath

    $result.exitCode | Should -Be 1
    (@($result.report.issues) | Where-Object { $_ -like 'Gateway config file*' }).Count | Should -Be 0
    @($result.report.issues) | Should -Contain "Service '$($result.report.serviceName)' is not installed."
  }

  It 'returns success when only warnings are present' {
    $stateDir = Join-Path $env:TEMP "doctor-state-$([guid]::NewGuid())"
    $gatewayDir = Join-Path $env:TEMP "doctor-gateway-$([guid]::NewGuid())"
    $gatewayConfigPath = Join-Path $gatewayDir 'openclaw.json'
    $configPath = New-DoctorTestConfig -GatewayConfigPath $gatewayConfigPath -StateDir $stateDir
    $script:testPaths += @($stateDir, $gatewayDir, $gatewayConfigPath, $configPath)

    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    New-Item -ItemType Directory -Path $gatewayDir -Force | Out-Null
    Set-Content -LiteralPath $gatewayConfigPath -Value (@{ name = 'test' } | ConvertTo-Json -Depth 10) -Encoding UTF8

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
    Mock Get-PortListeners { @() }
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

    $output = & $script:doctorScript -ConfigPath $configPath -Json
    $LASTEXITCODE | Should -Be 0
    $report = $output | ConvertFrom-Json

    $report.PSObject.Properties.Name | Should -Contain 'warnings'
    @($report.warnings).Count | Should -Be 1
    @($report.issues).Count | Should -Be 0
  }

  It 'reports redacted proxy settings and their sources' {
    $originalHttps = [System.Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Process')
    $stateDir = Join-Path $env:TEMP "doctor-state-$([guid]::NewGuid())"
    $gatewayDir = Join-Path $env:TEMP "doctor-gateway-$([guid]::NewGuid())"
    $gatewayConfigPath = Join-Path $gatewayDir 'openclaw.json'
    $configPath = New-DoctorTestConfig -GatewayConfigPath $gatewayConfigPath -StateDir $stateDir -Overrides @{
      httpProxy = 'http://user:secret@proxy.example:8080/path?x=1'
      noProxy   = 'localhost,127.0.0.1'
    }
    $script:testPaths += @($stateDir, $gatewayDir, $gatewayConfigPath, $configPath)

    try {
      New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
      New-Item -ItemType Directory -Path $gatewayDir -Force | Out-Null
      Set-Content -LiteralPath $gatewayConfigPath -Value (@{ name = 'test' } | ConvertTo-Json -Depth 10) -Encoding UTF8
      [System.Environment]::SetEnvironmentVariable('HTTPS_PROXY', 'http://ambient-proxy.example:8443', 'Process')

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
      Mock Get-PortListeners { @() }
      Mock Get-ServiceIdentityReport {
        @{
          configuredMode    = 'credential'
          deprecatedAlias   = $false
          expectedStartName = 'CONTOSO\svc-openclaw'
          actualStartName   = 'CONTOSO\svc-openclaw'
          matches           = $true
          installLayout     = 'generated'
        }
      }
      Mock Resolve-InspectionIdentityContext { Get-ServiceIdentityContext -Mode 'currentUser' }

      $output = & $script:doctorScript -ConfigPath $configPath -Json
      $LASTEXITCODE | Should -Be 0
      $report = $output | ConvertFrom-Json

      $report.proxy.httpProxy.source | Should -Be 'wrapperConfig'
      $report.proxy.httpProxy.value | Should -Be 'http://proxy.example:8080'
      $report.proxy.httpsProxy.source | Should -Be 'ambientEnvironment'
      $report.proxy.httpsProxy.value | Should -Be 'http://ambient-proxy.example:8443'
      $report.proxy.noProxy.source | Should -Be 'wrapperConfig'
      $report.proxy.noProxy.value | Should -Be 'localhost,127.0.0.1'
    } finally {
      [System.Environment]::SetEnvironmentVariable('HTTPS_PROXY', $originalHttps, 'Process')
    }
  }

  It 'accepts a LocalSystem service when configured for localSystem' {
    $stateDir = Join-Path $env:TEMP "doctor-state-$([guid]::NewGuid())"
    $gatewayDir = Join-Path $env:TEMP "doctor-gateway-$([guid]::NewGuid())"
    $gatewayConfigPath = Join-Path $gatewayDir 'openclaw.json'
    $configPath = New-DoctorTestConfig -GatewayConfigPath $gatewayConfigPath -StateDir $stateDir -Overrides @{ serviceAccountMode = 'localSystem' }
    $script:testPaths += @($stateDir, $gatewayDir, $gatewayConfigPath, $configPath)

    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    New-Item -ItemType Directory -Path $gatewayDir -Force | Out-Null
    Set-Content -LiteralPath $gatewayConfigPath -Value (@{ name = 'test' } | ConvertTo-Json -Depth 10) -Encoding UTF8

    $config = Get-ServiceConfig -ConfigPath $configPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
    $serviceDetails = @{
      installed = $true
      name      = $config.serviceName
      status    = 'Running'
      startType = 'Automatic'
      processId = 1
      startName = 'LocalSystem'
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
    Mock Get-PortListeners { @() }
    Mock Get-ServiceIdentityReport {
      @{
        configuredMode   = 'localSystem'
        deprecatedAlias  = $false
        expectedStartName = 'LocalSystem'
        actualStartName  = 'LocalSystem'
        matches          = $true
        installLayout    = 'generated'
      }
    }
    Mock Resolve-InspectionIdentityContext { Get-ServiceAccountIdentityContext -AccountName 'LocalSystem' }

    $output = & $script:doctorScript -ConfigPath $configPath -Json
    $LASTEXITCODE | Should -Be 0
    $report = $output | ConvertFrom-Json

    @($report.warnings).Count | Should -Be 0
    @($report.issues).Count | Should -Be 0
  }
}
