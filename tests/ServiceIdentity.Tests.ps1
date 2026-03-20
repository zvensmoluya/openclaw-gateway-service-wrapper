Describe 'Service identity planning' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:repoRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking
    $script:currentWindowsIdentityName = Get-CurrentWindowsIdentityName

    function script:New-ServiceIdentityConfigFile {
      param(
        [hashtable]$Overrides = @{}
      )

      $serviceName = if ($Overrides.ContainsKey('serviceName')) {
        $Overrides.serviceName
      } else {
        "IdentityTest-$([guid]::NewGuid().ToString('N'))"
      }

      $data = @{
        serviceName        = $serviceName
        displayName        = $serviceName
        description        = "Identity test for $serviceName"
        stateDir           = (Join-Path $env:TEMP "$serviceName-state")
        configPath         = (Join-Path $env:TEMP "$serviceName-openclaw.json")
        tempDir            = (Join-Path $env:TEMP "$serviceName-temp")
        openclawCommand    = 'powershell.exe'
        winswHome          = (Join-Path $env:TEMP "$serviceName-winsw")
        serviceAccountMode = 'credential'
        logPolicy          = @{
          mode = 'rotate'
        }
      }

      foreach ($key in $Overrides.Keys) {
        $data[$key] = $Overrides[$key]
      }

      $configPath = Join-Path $env:TEMP "$serviceName-wrapper.json"
      Set-Content -LiteralPath $configPath -Value ($data | ConvertTo-Json -Depth 10) -Encoding UTF8
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

  It 'treats currentUser as a deprecated alias for the current Windows identity' {
    $configPath = New-ServiceIdentityConfigFile -Overrides @{ serviceAccountMode = 'currentUser' }
    $script:testPaths += $configPath
    $config = Get-ServiceConfig -ConfigPath $configPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')

    $plan = Resolve-ServiceAccountPlan -Config $config -CurrentWindowsIdentityName $script:currentWindowsIdentityName

    $plan.configuredMode | Should -Be 'currentUser'
    $plan.effectiveMode | Should -Be 'credential'
    $plan.deprecatedAlias | Should -BeTrue
    $plan.requiresCredential | Should -BeTrue
    $plan.expectedStartName | Should -Be $script:currentWindowsIdentityName
    $plan.identityContext.profileRoot | Should -Not -BeNullOrEmpty
  }

  It 'rejects a mismatched credential in currentUser mode' {
    $configPath = New-ServiceIdentityConfigFile -Overrides @{ serviceAccountMode = 'currentUser' }
    $script:testPaths += $configPath
    $config = Get-ServiceConfig -ConfigPath $configPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
    $secure = ConvertTo-SecureString 'example-password' -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential('CONTOSO\someone-else', $secure)

    { Resolve-ServiceAccountPlan -Config $config -Credential $credential -CurrentWindowsIdentityName $script:currentWindowsIdentityName } | Should -Throw '*deprecated and only supports the current Windows identity*'
  }

  It 'does not infer an expected account for legacy currentUser installs without serviceaccount metadata' {
    $configPath = New-ServiceIdentityConfigFile -Overrides @{ serviceAccountMode = 'currentUser'; serviceName = 'OpenClawService' }
    $script:testPaths += $configPath
    $config = Get-ServiceConfig -ConfigPath $configPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
    $serviceDetails = @{
      installed = $true
      name      = $config.serviceName
      status    = 'Running'
      startType = 'Automatic'
      processId = 1
      startName = 'LocalSystem'
      pathName  = ('"{0}"' -f (Join-Path $script:repoRoot 'OpenClawService.exe'))
    }

    $identity = Get-ServiceIdentityReport -Config $config -ServiceDetails $serviceDetails -CurrentWindowsIdentityName $script:currentWindowsIdentityName

    $identity.configuredMode | Should -Be 'currentUser'
    $identity.installLayout | Should -Be 'legacyRoot'
    $identity.expectedStartName | Should -Be $null
  }

  It 'allows arbitrary credentials in credential mode' {
    $configPath = New-ServiceIdentityConfigFile
    $script:testPaths += $configPath
    $config = Get-ServiceConfig -ConfigPath $configPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
    $secure = ConvertTo-SecureString 'example-password' -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential('CONTOSO\svc-openclaw', $secure)

    $plan = Resolve-ServiceAccountPlan -Config $config -Credential $credential -CurrentWindowsIdentityName $script:currentWindowsIdentityName

    $plan.configuredMode | Should -Be 'credential'
    $plan.deprecatedAlias | Should -BeFalse
    $plan.requiresCredential | Should -BeFalse
    $plan.expectedStartName | Should -Be 'CONTOSO\svc-openclaw'
  }

  It 'flags a LocalSystem install result as invalid for a credential-backed service' {
    $configPath = New-ServiceIdentityConfigFile
    $script:testPaths += $configPath
    $config = Get-ServiceConfig -ConfigPath $configPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
    $secure = ConvertTo-SecureString 'example-password' -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential('CONTOSO\svc-openclaw', $secure)

    Write-WinSWServiceXml -Config $config -ServiceAccountMode 'credential' -Credential $credential | Out-Null
    $script:testPaths += (Join-Path $env:TEMP "$($config.serviceName)-winsw")
    $serviceDetails = @{
      installed = $true
      name      = $config.serviceName
      status    = 'Running'
      startType = 'Automatic'
      processId = 1
      startName = 'LocalSystem'
      pathName  = ('"{0}"' -f (Join-Path $config.winswHome "$($config.serviceName)\$($config.serviceName).exe"))
    }

    $issues = @(Get-ServiceInstallValidationIssues -Config $config -ServiceDetails $serviceDetails -CurrentWindowsIdentityName $script:currentWindowsIdentityName)

    $issues.Count | Should -Be 1
    $issues[0] | Should -Match 'was installed as built-in account'
  }

  It 'flags a mismatched user account after install' {
    $configPath = New-ServiceIdentityConfigFile
    $script:testPaths += $configPath
    $config = Get-ServiceConfig -ConfigPath $configPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
    $secure = ConvertTo-SecureString 'example-password' -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential('CONTOSO\svc-openclaw', $secure)

    Write-WinSWServiceXml -Config $config -ServiceAccountMode 'credential' -Credential $credential | Out-Null
    $script:testPaths += (Join-Path $env:TEMP "$($config.serviceName)-winsw")
    $serviceDetails = @{
      installed = $true
      name      = $config.serviceName
      status    = 'Running'
      startType = 'Automatic'
      processId = 1
      startName = 'CONTOSO\somebody-else'
      pathName  = ('"{0}"' -f (Join-Path $config.winswHome "$($config.serviceName)\$($config.serviceName).exe"))
    }

    $issues = @(Get-ServiceInstallValidationIssues -Config $config -ServiceDetails $serviceDetails -CurrentWindowsIdentityName $script:currentWindowsIdentityName)

    $issues.Count | Should -Be 1
    $issues[0] | Should -Match 'planned service account'
  }

  It 'reports the legacy root layout from the installed service path' {
    $configPath = New-ServiceIdentityConfigFile -Overrides @{ serviceAccountMode = 'currentUser'; serviceName = 'OpenClawService' }
    $script:testPaths += $configPath
    $config = Get-ServiceConfig -ConfigPath $configPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
    $serviceDetails = @{
      installed = $true
      name      = $config.serviceName
      status    = 'Running'
      startType = 'Automatic'
      processId = 1
      startName = 'LocalSystem'
      pathName  = ('"{0}"' -f (Join-Path $script:repoRoot 'OpenClawService.exe'))
    }

    $identity = Get-ServiceIdentityReport -Config $config -ServiceDetails $serviceDetails -CurrentWindowsIdentityName $script:currentWindowsIdentityName

    $identity.installLayout | Should -Be 'legacyRoot'
    $identity.actualStartName | Should -Be 'LocalSystem'
  }
}
