Describe 'status.ps1' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:repoRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking
    $script:statusScript = Join-Path $script:repoRoot 'status.ps1'
    $script:rememberedMetadataPath = Get-RememberedConfigMetadataPath
    $script:rememberedMetadataBackup = $null

    if (Test-Path -LiteralPath $script:rememberedMetadataPath) {
      $script:rememberedMetadataBackup = Join-Path $env:TEMP "status-active-config-backup-$([guid]::NewGuid()).json"
      Copy-Item -LiteralPath $script:rememberedMetadataPath -Destination $script:rememberedMetadataBackup -Force
    }

    function script:New-StatusTestConfig {
      param(
        [hashtable]$Overrides = @{}
      )

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

      foreach ($key in $Overrides.Keys) {
        $config[$key] = $Overrides[$key]
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
    Mock Get-ServiceRestartTaskStatus {
      @{
        taskPath       = '\OpenClaw\'
        taskName       = "$($config.serviceName)-Restart"
        fullTaskName   = "\OpenClaw\$($config.serviceName)-Restart"
        scriptPath     = 'restart-service-task.ps1'
        logPath        = "logs\$($config.serviceName).restart-task.log"
        description    = 'restart bridge'
        exists         = $true
        state          = 'Ready'
        matches        = $true
        expectedAction = @{
          execute   = 'powershell.exe'
          arguments = 'expected'
        }
        actualAction   = @{
          execute   = 'powershell.exe'
          arguments = 'expected'
        }
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

  It 'reports redacted proxy settings and their sources' {
    $originalHttps = [System.Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Process')
    $configPath = New-StatusTestConfig -Overrides @{
      httpProxy = 'http://user:secret@proxy.example:8080/path?x=1'
      noProxy   = 'localhost,127.0.0.1'
    }
    $script:testPaths += $configPath

    try {
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
      Mock Get-ServiceRestartTaskStatus {
        @{
          taskPath       = '\OpenClaw\'
          taskName       = "$($config.serviceName)-Restart"
          fullTaskName   = "\OpenClaw\$($config.serviceName)-Restart"
          scriptPath     = 'restart-service-task.ps1'
          logPath        = "logs\$($config.serviceName).restart-task.log"
          description    = 'restart bridge'
          exists         = $true
          state          = 'Ready'
          matches        = $true
          expectedAction = @{
            execute   = 'powershell.exe'
            arguments = 'expected'
          }
          actualAction   = @{
            execute   = 'powershell.exe'
            arguments = 'expected'
          }
        }
      }
      Mock Resolve-InspectionIdentityContext { Get-ServiceIdentityContext -Mode 'currentUser' }

      $output = & $script:statusScript -ConfigPath $configPath -Json
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
    $configPath = New-StatusTestConfig -Overrides @{ serviceAccountMode = 'localSystem' }
    $script:testPaths += $configPath

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
    Mock Get-ServiceRestartTaskStatus {
      @{
        taskPath       = '\OpenClaw\'
        taskName       = "$($config.serviceName)-Restart"
        fullTaskName   = "\OpenClaw\$($config.serviceName)-Restart"
        scriptPath     = 'restart-service-task.ps1'
        logPath        = "logs\$($config.serviceName).restart-task.log"
        description    = 'restart bridge'
        exists         = $true
        state          = 'Ready'
        matches        = $true
        expectedAction = @{
          execute   = 'powershell.exe'
          arguments = 'expected'
        }
        actualAction   = @{
          execute   = 'powershell.exe'
          arguments = 'expected'
        }
      }
    }
    Mock Resolve-InspectionIdentityContext { Get-ServiceAccountIdentityContext -AccountName 'LocalSystem' }

    $output = & $script:statusScript -ConfigPath $configPath -Json
    $LASTEXITCODE | Should -Be 0
    $report = $output | ConvertFrom-Json

    @($report.warnings).Count | Should -Be 0
    @($report.issues).Count | Should -Be 0
  }

  It 'reports a missing restart task for an installed service' {
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
        configuredMode    = 'credential'
        deprecatedAlias   = $false
        expectedStartName = 'CONTOSO\svc-openclaw'
        actualStartName   = 'CONTOSO\svc-openclaw'
        matches           = $true
        installLayout     = 'generated'
      }
    }
    Mock Get-ServiceRestartTaskStatus {
      @{
        taskPath       = '\OpenClaw\'
        taskName       = "$($config.serviceName)-Restart"
        fullTaskName   = "\OpenClaw\$($config.serviceName)-Restart"
        scriptPath     = 'restart-service-task.ps1'
        logPath        = "logs\$($config.serviceName).restart-task.log"
        description    = 'restart bridge'
        exists         = $false
        state          = $null
        matches        = $false
        expectedAction = @{
          execute   = 'powershell.exe'
          arguments = 'expected'
        }
        actualAction   = @{
          execute   = $null
          arguments = $null
        }
      }
    }
    Mock Resolve-InspectionIdentityContext { Get-ServiceIdentityContext -Mode 'currentUser' }

    $output = & $script:statusScript -ConfigPath $configPath -Json
    $LASTEXITCODE | Should -Be 1
    $report = $output | ConvertFrom-Json

    @($report.issues) | Should -Contain "Restart task '\OpenClaw\$($config.serviceName)-Restart' is missing. Reinstall the service to restore intentional restart bridging."
  }

  It 'reports a mismatched restart task action for an installed service' {
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
        configuredMode    = 'credential'
        deprecatedAlias   = $false
        expectedStartName = 'CONTOSO\svc-openclaw'
        actualStartName   = 'CONTOSO\svc-openclaw'
        matches           = $true
        installLayout     = 'generated'
      }
    }
    Mock Get-ServiceRestartTaskStatus {
      @{
        taskPath       = '\OpenClaw\'
        taskName       = "$($config.serviceName)-Restart"
        fullTaskName   = "\OpenClaw\$($config.serviceName)-Restart"
        scriptPath     = 'restart-service-task.ps1'
        logPath        = "logs\$($config.serviceName).restart-task.log"
        description    = 'restart bridge'
        exists         = $true
        state          = 'Ready'
        matches        = $false
        expectedAction = @{
          execute   = 'powershell.exe'
          arguments = 'expected'
        }
        actualAction   = @{
          execute   = 'powershell.exe'
          arguments = 'wrong'
        }
      }
    }
    Mock Resolve-InspectionIdentityContext { Get-ServiceIdentityContext -Mode 'currentUser' }

    $output = & $script:statusScript -ConfigPath $configPath -Json
    $LASTEXITCODE | Should -Be 1
    $report = $output | ConvertFrom-Json

    @($report.issues) | Should -Contain "Restart task '\OpenClaw\$($config.serviceName)-Restart' does not match the expected wrapper action. Reinstall the service to restore intentional restart bridging."
  }
}
