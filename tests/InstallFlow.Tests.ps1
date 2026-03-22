Describe 'install.ps1 control-task flow' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:repoRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking
    $script:installScript = Join-Path $script:repoRoot 'install.ps1'
    $script:installScriptText = Get-Content $script:installScript -Raw
    $script:uninstallScriptText = Get-Content (Join-Path $script:repoRoot 'uninstall.ps1') -Raw
    $script:rememberedMetadataPath = Get-RememberedConfigMetadataPath
    $script:rememberedMetadataBackup = $null

    if (Test-Path -LiteralPath $script:rememberedMetadataPath) {
      $script:rememberedMetadataBackup = Join-Path $env:TEMP "installflow-active-config-backup-$([guid]::NewGuid()).json"
      Copy-Item -LiteralPath $script:rememberedMetadataPath -Destination $script:rememberedMetadataBackup -Force
    }

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

  AfterAll {
    [void](Clear-RememberedServiceConfigSelection)

    if ($null -ne $script:rememberedMetadataBackup -and (Test-Path -LiteralPath $script:rememberedMetadataBackup)) {
      New-Item -ItemType Directory -Path (Split-Path -Parent $script:rememberedMetadataPath) -Force | Out-Null
      Copy-Item -LiteralPath $script:rememberedMetadataBackup -Destination $script:rememberedMetadataPath -Force
      Remove-Item -LiteralPath $script:rememberedMetadataBackup -Force
    }
  }

  It 'fails closed when SYSTEM control task registration fails' {
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
    Mock Register-ServiceControlTasks { throw 'simulated control-task registration failure' }
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

    & $script:installScript -ConfigPath $configPath -SkipTray -Elevated

    $LASTEXITCODE | Should -Be 1
    @($commands) | Should -Contain 'install'
    @($commands) | Should -Contain 'uninstall'
    @($commands) | Should -Not -Contain 'start'
  }

  It 'uses recovery stop and waits for service removal during reinstall' {
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
        installed = $true
        name      = $config.serviceName
        status    = 'Running'
        startType = 'Automatic'
        processId = 100
        startName = 'LocalSystem'
        pathName  = 'OpenClawService.exe'
      }
    }
    Mock Disable-ServiceStartForReinstall { $true }
    Mock Invoke-ServiceControlAction {
      @{
        success = $true
        busy    = $false
        message = "Service '$($config.serviceName)' is stopped."
      }
    }
    Mock Wait-ForServiceRemoval { $true }
    Mock Get-PortListeners { @() }
    Mock Ensure-WinSWBinary { 'winsw.exe' }
    Mock Write-WinSWServiceXml { 'winsw.xml' }
    Mock Invoke-WinSWCommand {
      param($Config, $Command)
      [void]$commands.Add($Command)
    }
    Mock Register-ServiceControlTasks {
      [ordered]@{
        start   = '\OpenClaw\Test-Start'
        stop    = '\OpenClaw\Test-Stop'
        restart = '\OpenClaw\Test-Restart'
      }
    }
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

    & $script:installScript -ConfigPath $configPath -SkipTray -Elevated

    $LASTEXITCODE | Should -Be 0
    Should -Invoke Disable-ServiceStartForReinstall -Times 1 -Exactly
    Should -Invoke Invoke-ServiceControlAction -Times 1 -Exactly
    Should -Invoke Wait-ForServiceRemoval -Times 1 -Exactly
    Should -Invoke Register-ServiceControlTasks -Times 2 -Exactly
    @($commands) | Should -Contain 'uninstall'
    @($commands) | Should -Contain 'install'
    @($commands) | Should -Contain 'start'
  }

  It 'self-elevates install and uninstall entrypoints before mutating service state' {
    $script:installScriptText | Should -Match '\[switch\]\$Elevated'
    $script:installScriptText | Should -Match 'Test-IsCurrentProcessElevated'
    $script:installScriptText | Should -Match 'Start-Process[\s\S]*-Verb RunAs'

    $script:uninstallScriptText | Should -Match '\[switch\]\$Elevated'
    $script:uninstallScriptText | Should -Match 'Test-IsCurrentProcessElevated'
    $script:uninstallScriptText | Should -Match 'Start-Process[\s\S]*-Verb RunAs'
  }
}
