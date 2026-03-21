[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

try {
  $currentWindowsIdentityName = Get-CurrentWindowsIdentityName
  $emptyWarnings = [System.Collections.ArrayList]::new()
  $selection = Resolve-ServiceConfigSelection -ConfigPath $ConfigPath -AllowInvalidRemembered
  if ($selection.ContainsKey('invalidReason')) {
    $service = if ([string]::IsNullOrWhiteSpace($selection.rememberedServiceName)) {
      @{
        installed = $false
        name      = $null
        status    = $null
        startType = $null
        processId = 0
        startName = $null
        pathName  = $null
      }
    } else {
      Get-ServiceDetails -ServiceName $selection.rememberedServiceName
    }

    $actualExecutablePath = Get-ServiceExecutablePathFromPathName -PathName $service.pathName
    $identity = @{
      configuredMode   = $null
      deprecatedAlias  = $false
      expectedStartName = $null
      actualStartName  = if ($service.installed) { $service.startName } else { $null }
      matches          = $false
      installLayout    = Get-ServiceInstallLayoutFromExecutablePath -ExecutablePath $actualExecutablePath
    }

    $report = @{
      serviceName = $selection.rememberedServiceName
      installed   = $service.installed
      service     = $service
      restartTask = New-EmptyServiceRestartTaskStatusReport
      proxy       = New-EmptyWrapperProxyStatusReport
      health      = @{
        ok         = $false
        statusCode = $null
        body       = $null
        error      = $selection.invalidReason
      }
      healthUrl   = $null
      port        = $null
      config      = @{
        configSource  = $selection.configSource
        sourcePath    = $selection.sourcePath
        rememberedPath = $selection.rememberedPath
      }
      identity    = $identity
      warnings    = $emptyWarnings
      issues      = @($selection.invalidReason)
    }

    if ($Json) {
      $report | ConvertTo-Json -Depth 10
    } else {
      Write-Host "Service name : $($selection.rememberedServiceName)"
      Write-Host "Config       : $($selection.sourcePath) [$($selection.configSource)]"
      Write-Host "Remembered   : $($selection.rememberedPath)"
      Write-Host "Run as       : $($identity.actualStartName)"
      Write-Host "Layout       : $($identity.installLayout)"
      Write-Host 'Health       : FAILED'
      Write-Host $selection.invalidReason
    }

    exit 1
  }

  $bootstrapConfig = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
  $service = Get-ServiceDetails -ServiceName $bootstrapConfig.serviceName
  $inspectionIdentityContext = Resolve-InspectionIdentityContext -Config $bootstrapConfig -ServiceDetails $service -CurrentWindowsIdentityName $currentWindowsIdentityName
  $config = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext $inspectionIdentityContext
  $config.configSource = $selection.configSource
  $config.rememberedPath = $selection.rememberedPath
  $identity = Get-ServiceIdentityReport -Config $config -ServiceDetails $service -CurrentWindowsIdentityName $currentWindowsIdentityName
  $restartTask = Get-ServiceRestartTaskStatus -Config $config
  $proxy = Get-WrapperProxyStatusReport -Config $config
  $health = Invoke-HealthCheck -Url $config.healthUrl -TimeoutSec 8
  $warnings = [System.Collections.ArrayList]::new()
  $issues = @()

  if ($identity.deprecatedAlias) {
    [void]$warnings.Add("serviceAccountMode 'currentUser' is deprecated. Use 'credential' for Windows Service installs.")
  }

  if ($service.installed -and $identity.installLayout -eq 'legacyRoot' -and $identity.configuredMode -eq 'currentUser' -and [string]::IsNullOrWhiteSpace($identity.expectedStartName)) {
    [void]$warnings.Add("Service '$($config.serviceName)' uses the legacy root WinSW layout and does not expose an explicit service account in XML, so the expected account cannot be inferred reliably. Reinstall with the current wrapper to capture service account metadata.")
  }

  if ($service.installed -and $identity.installLayout -eq 'legacyRoot') {
    $issues += "Service '$($config.serviceName)' is still using the legacy root WinSW layout. Reinstall with the current wrapper so service account settings and explicit ConfigPath are preserved."
  }

  $hasExpectedIdentity = -not [string]::IsNullOrWhiteSpace($identity.expectedStartName)
  $actualIsBuiltInServiceAccount = $service.installed -and (Test-IsBuiltInServiceAccount -AccountName $identity.actualStartName)

  if ($actualIsBuiltInServiceAccount -and -not ($hasExpectedIdentity -and $identity.matches) -and -not $hasExpectedIdentity -and $identity.configuredMode -eq 'credential') {
    $issues += "Service '$($config.serviceName)' is running as built-in account '$($identity.actualStartName)'. credential mode requires an explicit Windows account. Reinstall with explicit credentials."
  } elseif ($actualIsBuiltInServiceAccount -and -not ($hasExpectedIdentity -and $identity.matches) -and $hasExpectedIdentity) {
    $issues += "Service '$($config.serviceName)' is running as built-in account '$($identity.actualStartName)' but the configured model expects user account '$($identity.expectedStartName)'. Reinstall with explicit credentials."
  } elseif ($service.installed -and $hasExpectedIdentity -and -not $identity.matches) {
    $issues += "Service '$($config.serviceName)' is running as '$($identity.actualStartName)' but expected '$($identity.expectedStartName)'. Reinstall with explicit credentials."
  }

  if (-not $service.installed) {
    $issues += "Service '$($config.serviceName)' is not installed."
  }

  if ($service.installed -and $service.status -ne 'Running') {
    $issues += "Service '$($config.serviceName)' is not running."
  }

  if ($service.installed -and -not $restartTask.exists) {
    $issues += "Restart task '$($restartTask.fullTaskName)' is missing. Reinstall the service to restore intentional restart bridging."
  } elseif ($service.installed -and -not $restartTask.matches) {
    $issues += "Restart task '$($restartTask.fullTaskName)' does not match the expected wrapper action. Reinstall the service to restore intentional restart bridging."
  }

  if (-not $health.ok) {
    $issues += "Health endpoint is not healthy: $($health.error)"
  }

  $report = @{
    serviceName = $config.serviceName
    installed   = $service.installed
    service     = $service
    restartTask = $restartTask
    proxy       = $proxy
    health      = $health
    healthUrl   = $config.healthUrl
    port        = $config.port
    config      = @{
      configSource  = $config.configSource
      sourcePath    = $config.sourceConfigPath
      rememberedPath = $config.rememberedPath
    }
    identity    = $identity
    warnings    = $warnings
    issues      = $issues
  }

  if ($Json) {
    $report | ConvertTo-Json -Depth 10
  } else {
    Write-Host "Service name : $($config.serviceName)"
    Write-Host "Config       : $($config.sourceConfigPath) [$($config.configSource)]"
    Write-Host "Remembered   : $($config.rememberedPath)"
    Write-Host "Configured   : $($identity.configuredMode)"
    Write-Host "Deprecated   : $($identity.deprecatedAlias)"
    Write-Host "Expected run : $($identity.expectedStartName)"
    Write-Host "Actual run   : $($identity.actualStartName)"
    Write-Host "Layout       : $($identity.installLayout)"
    Write-Host "Installed    : $($service.installed)"
    Write-Host "Status       : $($service.status)"
    Write-Host "Start type   : $($service.startType)"
    Write-Host "Restart task : $($restartTask.fullTaskName)"
    Write-Host "Task status  : $($restartTask.state)"
    Write-Host "Task matches : $($restartTask.matches)"
    Write-Host "HTTP proxy   : $($proxy.httpProxy.value) [$($proxy.httpProxy.source)]"
    Write-Host "HTTPS proxy  : $($proxy.httpsProxy.value) [$($proxy.httpsProxy.source)]"
    Write-Host "ALL proxy    : $($proxy.allProxy.value) [$($proxy.allProxy.source)]"
    Write-Host "NO_PROXY     : $($proxy.noProxy.value) [$($proxy.noProxy.source)]"
    Write-Host "Health URL   : $($config.healthUrl)"
    if ($health.ok) {
      Write-Host "Health       : OK ($($health.statusCode))"
      Write-Host $health.body
    } else {
      Write-Host 'Health       : FAILED'
      Write-Host $health.error
    }

    if ($warnings.Count -gt 0) {
      Write-Host ''
      Write-Host 'Warnings'
      foreach ($warning in $warnings) {
        Write-Host "- $warning"
      }
    }

    if ($issues.Count -gt 0) {
      Write-Host ''
      Write-Host 'Issues'
      foreach ($issue in $issues) {
        Write-Host "- $issue"
      }
    }
  }

  if ($service.installed -and $service.status -eq 'Running' -and $health.ok -and $issues.Count -eq 0) {
    exit 0
  }

  exit 1
} catch {
  Write-Error $_
  exit 1
}
