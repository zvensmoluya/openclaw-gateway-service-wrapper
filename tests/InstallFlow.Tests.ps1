Describe 'install.ps1 restart-task flow' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:repoRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking
    $script:installScript = Join-Path $script:repoRoot 'install.ps1'

    function script:New-InstallTestConfig {
      param(
        [hashtable]$Overrides = @{}
      )

      $serviceName = "InstallTest-$([guid]::NewGuid().ToString('N'))"
      $configPath = Join-Path $env:TEMP "$serviceName-wrapper.json"
      $config = @{
        serviceName        = $serviceName
        displayName        = $serviceName
        description        = "Install test for $serviceName"
        serviceAccountMode = 'localSystem'
        port               = 19120
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

  It 'fails closed when restart task registration fails' {
    $configPath = New-InstallTestConfig
    $script:testPaths += $configPath
    $config = Get-ServiceConfig -ConfigPath $configPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
    $commands = [System.Collections.Generic.List[string]]::new()

    Mock Resolve-ServiceAccountPlan {
      @{
        configuredMode     = 'localSystem'
        effectiveMode      = 'localSystem'
        deprecatedAlias    = $false
        expectedStartName  = 'LocalSystem'
        identityContext    = (Get-ServiceAccountIdentityContext -AccountName 'LocalSystem')
        credential         = $null
        requiresCredential = $false
        promptUserName     = $null
      }
    }
    Mock Resolve-OpenClawCommandPath { 'powershell.exe' }
    Mock Get-ServiceDetails {
      @{
        installed = $false
        name      = $config.serviceName
        status    = $null
        startType = $null
        processId = 0
        startName = $null
        pathName  = $null
      }
    }
    Mock Get-PortListeners { @() }
    Mock Ensure-WinSWBinary { 'winsw.exe' }
    Mock Write-WinSWServiceXml { 'winsw.xml' }
    Mock Invoke-WinSWCommand {
      param($Config, $Command)
      [void]$commands.Add($Command)
    }
    Mock Register-ServiceRestartTask { throw 'simulated restart-task registration failure' }
    Mock Wait-ForServiceStatus { $true }
    Mock Get-ServiceInstallValidationIssues { @() }
    Mock Write-RememberedServiceConfigSelection { 'remembered.json' }
    Mock Invoke-HealthCheck {
      @{
        ok         = $true
        statusCode = 200
        body       = '{"ok":true}'
        error      = $null
      }
    }
    Mock Install-TrayStartupShortcut { 'shortcut.lnk' }

    & $script:installScript -ConfigPath $configPath -SkipTray

    $LASTEXITCODE | Should -Be 1
    @($commands) | Should -Contain 'install'
    @($commands) | Should -Contain 'uninstall'
    @($commands) | Should -Not -Contain 'start'
  }
}
