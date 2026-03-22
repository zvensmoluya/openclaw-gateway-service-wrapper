[CmdletBinding()]
param(
  [switch]$PurgeTools,
  [string]$ConfigPath,
  [switch]$Elevated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

function Get-UninstallElevationArguments {
  [CmdletBinding()]
  param()

  $arguments = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    (Join-Path $PSScriptRoot 'uninstall.ps1'),
    '-Elevated'
  )

  if ($PurgeTools) {
    $arguments += '-PurgeTools'
  }

  if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $arguments += @('-ConfigPath', $ConfigPath)
  }

  return $arguments
}

try {
  if (-not $Elevated -and -not (Test-IsCurrentProcessElevated)) {
    $elevatedProcess = Start-Process `
      -FilePath (Get-WindowsPowerShellExecutablePath) `
      -ArgumentList (Join-ProcessArgumentString -Arguments (Get-UninstallElevationArguments)) `
      -Verb RunAs `
      -Wait `
      -PassThru
    exit $elevatedProcess.ExitCode
  }

  $config = Resolve-ServiceConfig -ConfigPath $ConfigPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
  $serviceDetails = Get-ServiceDetails -ServiceName $config.serviceName

  if ($serviceDetails.installed) {
    Write-Host "Preparing SYSTEM control bridge for safe uninstall."
    [void](Register-ServiceControlTasks -Config $config)
    try {
      $stopBridgeResult = Invoke-ServiceControlAction -Config $config -Action 'stop' -TimeoutSec 60
      if (-not $stopBridgeResult.success) {
        throw $stopBridgeResult.message
      }
    } catch {
      Write-Warning "Standard stop failed, falling back to a targeted process-tree stop."
      [void](Stop-RecordedServiceProcessTree -Config $config -TimeoutSec $config.stopTimeoutSeconds)
    }

    [void](Wait-ForServiceStatus -ServiceName $config.serviceName -DesiredStatus 'Stopped' -TimeoutSec 30)

    try {
      Invoke-WinSWCommand -Config $config -Command 'uninstall'
    } catch {
      Write-Warning "WinSW uninstall failed, removing the service with sc.exe."
      & sc.exe delete $config.serviceName *> $null
    }
  }

  try {
    [void](Remove-ServiceControlTasks -Config $config)
  } catch {
    Write-Warning "SYSTEM control task cleanup failed: $($_.Exception.Message)"
  }

  if ($PurgeTools) {
    Remove-GeneratedArtifacts -Config $config
  }

  $remembered = $null
  try {
    $remembered = Read-RememberedServiceConfigSelection
  } catch {
  }

  if ($null -ne $remembered -and $remembered.serviceName -eq $config.serviceName) {
    [void](Clear-RememberedServiceConfigSelection)
  }

  try {
    [void](Remove-TrayStartupShortcut -Config $config)
  } catch {
    Write-Warning "Tray startup shortcut cleanup failed: $($_.Exception.Message)"
  }

  Write-Host "Service '$($config.serviceName)' has been removed."
  if ($PurgeTools) {
    Write-Host 'Generated WinSW artifacts were purged.'
  }

  exit 0
} catch {
  Write-Error $_
  exit 1
}
