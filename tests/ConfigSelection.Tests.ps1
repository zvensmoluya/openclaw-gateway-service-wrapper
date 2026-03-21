Describe 'Wrapper config selection' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $module = Import-Module (Join-Path $script:repoRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking -PassThru
    $script:moduleName = $module.Name
    $script:rememberedMetadataPath = Get-RememberedConfigMetadataPath
    $script:rememberedMetadataBackup = $null

    if (Test-Path -LiteralPath $script:rememberedMetadataPath) {
      $script:rememberedMetadataBackup = Join-Path $env:TEMP "active-config-backup-$([guid]::NewGuid()).json"
      Copy-Item -LiteralPath $script:rememberedMetadataPath -Destination $script:rememberedMetadataBackup -Force
    }

    function script:New-TestWrapperConfig {
      param(
        [string]$ServiceName = "WrapperTest-$([guid]::NewGuid().ToString('N'))",
        [int]$Port = 19001,
        [hashtable]$Overrides = @{}
      )

      $path = Join-Path $env:TEMP "$ServiceName.json"
      $gatewayConfigPath = Join-Path $env:TEMP "$ServiceName-openclaw.json"
      $stateDir = Join-Path $env:TEMP "$ServiceName-state"

      $config = @{
        serviceName   = $ServiceName
        displayName   = $ServiceName
        description   = "Config for $ServiceName"
        port          = $Port
        stateDir      = $stateDir
        configPath    = $gatewayConfigPath
        tempDir       = $env:TEMP
        openclawCommand = 'powershell.exe'
        logPolicy     = @{
          mode = 'rotate'
        }
      }

      foreach ($key in $Overrides.Keys) {
        $config[$key] = $Overrides[$key]
      }

      Set-Content -LiteralPath $path -Value ($config | ConvertTo-Json -Depth 10) -Encoding UTF8
      return $path
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

    function script:Wait-ForRememberedConfigSelection {
      param(
        [int]$TimeoutMs = 5000
      )

      $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
      do {
        try {
          $record = Read-RememberedServiceConfigSelection
          if ($null -ne $record) {
            return $record
          }
        } catch {
        }

        Start-Sleep -Milliseconds 100
      } while ((Get-Date) -lt $deadline)

      return (Read-RememberedServiceConfigSelection)
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

  It 'falls back to the repository config when nothing is remembered' {
    $selection = Resolve-ServiceConfigSelection
    $expectedRepoConfig = Normalize-TestPath -Path (Join-Path $script:repoRoot 'service-config.json')

    $selection.configSource | Should -Be 'repoDefault'
    $selection.sourcePath | Should -Be $expectedRepoConfig
    $selection.rememberedPath | Should -Be $null
  }

  It 'prefers the remembered config over the repository default' {
    $rememberedConfig = New-TestWrapperConfig -ServiceName 'RememberedWrapperConfig' -Port 19002
    $expectedRememberedConfig = Normalize-TestPath -Path $rememberedConfig
    $script:testPaths += $rememberedConfig

    Write-RememberedServiceConfigSelection -SourceConfigPath $rememberedConfig -ServiceName 'RememberedWrapperConfig' | Out-Null
    $selection = Resolve-ServiceConfigSelection

    $selection.configSource | Should -Be 'remembered'
    $selection.sourcePath | Should -Be $expectedRememberedConfig
    $selection.rememberedPath | Should -Be $expectedRememberedConfig
  }

  It 'prefers an explicit config over the remembered config' {
    $rememberedConfig = New-TestWrapperConfig -ServiceName 'RememberedWrapperConfig' -Port 19003
    $explicitConfig = New-TestWrapperConfig -ServiceName 'ExplicitWrapperConfig' -Port 19004
    $expectedRememberedConfig = Normalize-TestPath -Path $rememberedConfig
    $expectedExplicitConfig = Normalize-TestPath -Path $explicitConfig
    $script:testPaths += @($rememberedConfig, $explicitConfig)

    Write-RememberedServiceConfigSelection -SourceConfigPath $rememberedConfig -ServiceName 'RememberedWrapperConfig' | Out-Null
    $selection = Resolve-ServiceConfigSelection -ConfigPath $explicitConfig

    $selection.configSource | Should -Be 'explicit'
    $selection.sourcePath | Should -Be $expectedExplicitConfig
    $selection.rememberedPath | Should -Be $expectedRememberedConfig
  }

  It 'reports a missing remembered config instead of silently falling back' {
    $missingConfig = Join-Path $env:TEMP "missing-wrapper-config-$([guid]::NewGuid()).json"
    $expectedMissingConfig = Normalize-TestPath -Path $missingConfig
    Write-RememberedServiceConfigSelection -SourceConfigPath $missingConfig -ServiceName 'MissingRememberedConfig' | Out-Null

    { Resolve-ServiceConfigSelection } | Should -Throw '*Pass -ConfigPath explicitly or reinstall the service.*'

    $selection = Resolve-ServiceConfigSelection -AllowInvalidRemembered
    $selection.configSource | Should -Be 'remembered'
    $selection.sourcePath | Should -Be $expectedMissingConfig
    $selection.rememberedPath | Should -Be $expectedMissingConfig
    $selection.invalidReason | Should -Match 'Pass -ConfigPath explicitly or reinstall the service'
  }

  It 'writes and clears remembered config metadata' {
    $rememberedConfig = New-TestWrapperConfig -ServiceName 'RememberedWrapperConfig' -Port 19005
    $expectedRememberedConfig = Normalize-TestPath -Path $rememberedConfig
    $script:testPaths += $rememberedConfig

    Write-RememberedServiceConfigSelection -SourceConfigPath $rememberedConfig -ServiceName 'RememberedWrapperConfig' | Out-Null
    $record = Read-RememberedServiceConfigSelection

    $record.sourceConfigPath | Should -Be $expectedRememberedConfig
    $record.serviceName | Should -Be 'RememberedWrapperConfig'
    (Test-Path -LiteralPath $script:rememberedMetadataPath) | Should -BeTrue

    (Clear-RememberedServiceConfigSelection) | Should -BeTrue
    (Read-RememberedServiceConfigSelection) | Should -Be $null
  }

  It 'does not overwrite remembered config metadata when install fails early' {
    $rememberedConfig = New-TestWrapperConfig -ServiceName 'RememberedWrapperConfig' -Port 19006
    $script:testPaths += $rememberedConfig

    Write-RememberedServiceConfigSelection -SourceConfigPath $rememberedConfig -ServiceName 'RememberedWrapperConfig' | Out-Null
    $before = Read-RememberedServiceConfigSelection

    $missingConfig = Join-Path $env:TEMP "missing-install-config-$([guid]::NewGuid()).json"
    $installScript = Join-Path $script:repoRoot 'install.ps1'
    $stdoutPath = Join-Path $env:TEMP "install-config-selection-stdout-$([guid]::NewGuid()).log"
    $stderrPath = Join-Path $env:TEMP "install-config-selection-stderr-$([guid]::NewGuid()).log"
    $script:testPaths += @($stdoutPath, $stderrPath)

    $process = Start-Process powershell.exe -ArgumentList @(
      '-NoProfile',
      '-ExecutionPolicy', 'Bypass',
      '-File', $installScript,
      '-ConfigPath', $missingConfig
    ) -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

    $process.ExitCode | Should -Be 1

    $after = Wait-ForRememberedConfigSelection
    $after | Should -Not -Be $null
    $after.sourceConfigPath | Should -Not -Be (Normalize-TestPath -Path $missingConfig)
    $after.serviceName | Should -Not -Be ([System.IO.Path]::GetFileNameWithoutExtension($missingConfig))
  }

  It 'does not overwrite remembered config metadata when LocalSystem mode rejects -Credential' {
    $rememberedConfig = New-TestWrapperConfig -ServiceName 'RememberedWrapperConfig' -Port 19007
    $script:testPaths += $rememberedConfig

    Write-RememberedServiceConfigSelection -SourceConfigPath $rememberedConfig -ServiceName 'RememberedWrapperConfig' | Out-Null
    $before = Read-RememberedServiceConfigSelection

    $localSystemConfig = New-TestWrapperConfig -ServiceName 'LocalSystemWrapperConfig' -Port 19008 -Overrides @{ serviceAccountMode = 'localSystem' }
    $installScript = Join-Path $script:repoRoot 'install.ps1'
    $stdoutPath = Join-Path $env:TEMP "install-local-system-stdout-$([guid]::NewGuid()).log"
    $stderrPath = Join-Path $env:TEMP "install-local-system-stderr-$([guid]::NewGuid()).log"
    $script:testPaths += @($localSystemConfig, $stdoutPath, $stderrPath)

    $command = @'
$secure = ConvertTo-SecureString 'example-password' -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential('CONTOSO\svc-openclaw', $secure)
& '__INSTALL_SCRIPT__' -ConfigPath '__CONFIG_PATH__' -Credential $credential
'@
    $command = $command.Replace('__INSTALL_SCRIPT__', $installScript.Replace("'", "''"))
    $command = $command.Replace('__CONFIG_PATH__', $localSystemConfig.Replace("'", "''"))

    $process = Start-Process powershell.exe -ArgumentList @(
      '-NoProfile',
      '-ExecutionPolicy', 'Bypass',
      '-Command', $command
    ) -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

    $process.ExitCode | Should -Be 1
    (Get-Content -LiteralPath $stderrPath -Raw) | Should -Match "serviceAccountMode 'localSystem' does not accept -Credential"

    $after = Wait-ForRememberedConfigSelection
    $after | Should -Not -Be $null
    $after.sourceConfigPath | Should -Not -Be (Normalize-TestPath -Path $localSystemConfig)
    $after.serviceName | Should -Not -Be 'LocalSystemWrapperConfig'
  }
}
