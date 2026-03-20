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
        [string]$StateDir
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
    $script:testPaths += @($stateDir, $gatewayDir, $configPath)

    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    New-Item -ItemType Directory -Path $gatewayDir -Force | Out-Null

    $result = Invoke-DoctorJson -ConfigPath $configPath

    $result.exitCode | Should -Be 1
    $result.report.config.configSource | Should -Be 'explicit'
    $result.report.config.sourcePath | Should -Be $configPath
    $result.report.identity.configuredMode | Should -Be 'credential'
    $result.report.identity.installLayout | Should -Be 'generated'
    $result.report.PSObject.Properties.Name | Should -Contain 'warnings'
    @($result.report.warnings).Count | Should -Be 0
    @($result.report.issues) | Should -Contain "Gateway config file does not exist: $gatewayConfigPath"
  }

  It 'reports invalid OpenClaw config JSON' {
    $stateDir = Join-Path $env:TEMP "doctor-state-$([guid]::NewGuid())"
    $gatewayDir = Join-Path $env:TEMP "doctor-gateway-$([guid]::NewGuid())"
    $gatewayConfigPath = Join-Path $gatewayDir 'openclaw.json'
    $configPath = New-DoctorTestConfig -GatewayConfigPath $gatewayConfigPath -StateDir $stateDir
    $script:testPaths += @($stateDir, $gatewayDir, $gatewayConfigPath, $configPath)

    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    New-Item -ItemType Directory -Path $gatewayDir -Force | Out-Null
    Set-Content -LiteralPath $gatewayConfigPath -Value '{ invalid json' -Encoding UTF8

    $result = Invoke-DoctorJson -ConfigPath $configPath

    $result.exitCode | Should -Be 1
    (@($result.report.issues) | Where-Object { $_ -like "Gateway config file is not valid JSON: $gatewayConfigPath*" }).Count | Should -Be 1
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
}
