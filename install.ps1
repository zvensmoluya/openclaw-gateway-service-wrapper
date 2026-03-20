[CmdletBinding()]
param(
  [string]$ConfigPath,
  [pscredential]$Credential,
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

try {
  $bootstrapIdentity = Get-ServiceIdentityContext -Mode 'currentUser'
  $selection = Resolve-ServiceConfigSelection -ConfigPath $ConfigPath
  $bootstrapConfig = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext $bootstrapIdentity
  $installCredential = $Credential
  $serviceAccountMode = Get-EffectiveServiceAccountMode -Config $bootstrapConfig -Credential $installCredential
  if ($serviceAccountMode -eq 'currentUser') {
    $currentUserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $installCredential = Get-Credential -UserName $currentUserName -Message 'Enter the password for the user account that should run the OpenClaw service.'
    if ($null -eq $installCredential) {
      throw 'A credential is required to install the service for the current user.'
    }

    $serviceAccountMode = 'credential'
  }

  $identityContext = Get-ServiceIdentityContext -Mode $serviceAccountMode -Credential $installCredential
  $config = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext $identityContext
  $config.configSource = $selection.configSource
  $config.rememberedPath = $selection.rememberedPath
  $layout = Get-ServiceArtifactLayout -Config $config

  Ensure-Directory -Path $config.logsDirectory
  Ensure-Directory -Path $config.runtimeStateDirectory
  Ensure-Directory -Path $config.stateDir
  Ensure-Directory -Path (Split-Path -Parent $config.gatewayConfigPath)

  $openclawCommand = Resolve-OpenClawCommandPath -Config $config -IdentityContext $identityContext
  Write-Host "Resolved openclaw command: $openclawCommand"

  $serviceDetails = Get-ServiceDetails -ServiceName $config.serviceName
  if ($serviceDetails.installed) {
    Write-Host "Reinstalling existing service '$($config.serviceName)'."

    try {
      Invoke-WinSWCommand -Config $config -Command 'stop'
    } catch {
      if (-not $Force) {
        throw
      }

      Write-Warning "Standard stop failed, falling back to a targeted process-tree stop."
      [void](Stop-RecordedServiceProcessTree -Config $config -TimeoutSec $config.stopTimeoutSeconds)
    }

    [void](Wait-ForServiceStatus -ServiceName $config.serviceName -DesiredStatus 'Stopped' -TimeoutSec 30)

    try {
      Invoke-WinSWCommand -Config $config -Command 'uninstall'
    } catch {
      if (-not $Force) {
        throw
      }

      Write-Warning "Standard uninstall failed, removing the service with sc.exe."
      & sc.exe delete $config.serviceName *> $null
    }
  }

  $listeners = @(Get-PortListeners -Port $config.port)
  if ($listeners.Count -gt 0 -and -not $config.allowForceBind) {
    $details = $listeners | ForEach-Object { "$($_.processName)#$($_.processId)@$($_.localAddress):$($_.localPort)" }
    throw "Port $($config.port) is already in use. Either stop the listed listeners first or set allowForceBind to true. Listeners: $($details -join ', ')"
  }

  Ensure-WinSWBinary -Config $config -Force:$Force | Out-Null
  Write-WinSWServiceXml -Config $config -ServiceAccountMode $serviceAccountMode -Credential $installCredential | Out-Null

  Invoke-WinSWCommand -Config $config -Command 'install'
  Invoke-WinSWCommand -Config $config -Command 'start'

  if (-not (Wait-ForServiceStatus -ServiceName $config.serviceName -DesiredStatus 'Running' -TimeoutSec 30)) {
    throw "Service '$($config.serviceName)' did not reach the Running state within 30 seconds."
  }

  Write-RememberedServiceConfigSelection -SourceConfigPath $config.sourceConfigPath -ServiceName $config.serviceName | Out-Null
  $health = Invoke-HealthCheck -Url $config.healthUrl -TimeoutSec 8

  Write-Host ''
  Write-Host "Service name : $($config.serviceName)"
  Write-Host "Config       : $($config.sourceConfigPath) [$($config.configSource)]"
  Write-Host "Port         : $($config.port)"
  Write-Host "WinSW home   : $($layout.generatedDirectory)"
  Write-Host "Health URL   : $($config.healthUrl)"
  if ($health.ok) {
    Write-Host "Health       : OK ($($health.statusCode))"
  } else {
    Write-Warning "Health check failed after install: $($health.error)"
  }

  exit 0
} catch {
  Write-Error $_
  exit 1
}
