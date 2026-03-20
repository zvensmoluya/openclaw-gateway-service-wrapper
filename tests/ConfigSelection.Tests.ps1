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
        [int]$Port = 19001
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

      Set-Content -LiteralPath $path -Value ($config | ConvertTo-Json -Depth 10) -Encoding UTF8
      return $path
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

    $selection.configSource | Should -Be 'repoDefault'
    $selection.sourcePath | Should -Be (Join-Path $script:repoRoot 'service-config.json')
    $selection.rememberedPath | Should -Be $null
  }

  It 'prefers the remembered config over the repository default' {
    $rememberedConfig = New-TestWrapperConfig -ServiceName 'RememberedWrapperConfig' -Port 19002
    $script:testPaths += $rememberedConfig

    Write-RememberedServiceConfigSelection -SourceConfigPath $rememberedConfig -ServiceName 'RememberedWrapperConfig' | Out-Null
    $selection = Resolve-ServiceConfigSelection

    $selection.configSource | Should -Be 'remembered'
    $selection.sourcePath | Should -Be $rememberedConfig
    $selection.rememberedPath | Should -Be $rememberedConfig
  }

  It 'prefers an explicit config over the remembered config' {
    $rememberedConfig = New-TestWrapperConfig -ServiceName 'RememberedWrapperConfig' -Port 19003
    $explicitConfig = New-TestWrapperConfig -ServiceName 'ExplicitWrapperConfig' -Port 19004
    $script:testPaths += @($rememberedConfig, $explicitConfig)

    Write-RememberedServiceConfigSelection -SourceConfigPath $rememberedConfig -ServiceName 'RememberedWrapperConfig' | Out-Null
    $selection = Resolve-ServiceConfigSelection -ConfigPath $explicitConfig

    $selection.configSource | Should -Be 'explicit'
    $selection.sourcePath | Should -Be $explicitConfig
    $selection.rememberedPath | Should -Be $rememberedConfig
  }

  It 'reports a missing remembered config instead of silently falling back' {
    $missingConfig = Join-Path $env:TEMP "missing-wrapper-config-$([guid]::NewGuid()).json"
    Write-RememberedServiceConfigSelection -SourceConfigPath $missingConfig -ServiceName 'MissingRememberedConfig' | Out-Null

    { Resolve-ServiceConfigSelection } | Should -Throw '*Pass -ConfigPath explicitly or reinstall the service.*'

    $selection = Resolve-ServiceConfigSelection -AllowInvalidRemembered
    $selection.configSource | Should -Be 'remembered'
    $selection.sourcePath | Should -Be $missingConfig
    $selection.rememberedPath | Should -Be $missingConfig
    $selection.invalidReason | Should -Match 'Pass -ConfigPath explicitly or reinstall the service'
  }

  It 'writes and clears remembered config metadata' {
    $rememberedConfig = New-TestWrapperConfig -ServiceName 'RememberedWrapperConfig' -Port 19005
    $script:testPaths += $rememberedConfig

    Write-RememberedServiceConfigSelection -SourceConfigPath $rememberedConfig -ServiceName 'RememberedWrapperConfig' | Out-Null
    $record = Read-RememberedServiceConfigSelection

    $record.sourceConfigPath | Should -Be $rememberedConfig
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
    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -ConfigPath $missingConfig 2>&1

    $LASTEXITCODE | Should -Be 1

    $after = Read-RememberedServiceConfigSelection
    $after.sourceConfigPath | Should -Be $before.sourceConfigPath
    $after.serviceName | Should -Be $before.serviceName
  }
}
