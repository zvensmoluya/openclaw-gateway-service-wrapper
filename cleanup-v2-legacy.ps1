[CmdletBinding()]
param(
  [string]$WrapperConfigPath = (Join-Path $PSScriptRoot 'service-config.local.json'),
  [string]$ServiceName,
  [string]$StartupPath,
  [string]$WinSWRoot,
  [string]$RuntimeSelectionPath,
  [switch]$NoServiceUninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Root {
  param(
    [string]$ExplicitPath,
    [string]$FallbackPath
  )

  if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
    return [System.IO.Path]::GetFullPath($ExplicitPath)
  }

  return [System.IO.Path]::GetFullPath($FallbackPath)
}

function Resolve-ServiceName {
  param(
    [string]$ConfigPath,
    [string]$ExplicitServiceName
  )

  if (-not [string]::IsNullOrWhiteSpace($ExplicitServiceName)) {
    return $ExplicitServiceName
  }

  if (Test-Path -LiteralPath $ConfigPath) {
    try {
      $json = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
      if ($null -ne $json.serviceName -and -not [string]::IsNullOrWhiteSpace("$($json.serviceName)")) {
        return "$($json.serviceName)"
      }
    } catch {
    }
  }

  return 'OpenClawService'
}

function Remove-LegacyTrayShortcuts {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$LegacyServiceName
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "${LegacyServiceName} Tray Controller*" } |
    Remove-Item -Force -ErrorAction SilentlyContinue
}

function Remove-RememberedSelection {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$LegacyServiceName,
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  try {
    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $sourceConfigPath = if ($null -ne $json.sourceConfigPath) { [System.IO.Path]::GetFullPath("$($json.sourceConfigPath)") } else { $null }
    if ($json.serviceName -eq $LegacyServiceName -or $sourceConfigPath -eq $ConfigPath) {
      Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
  } catch {
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  }
}

function Remove-LegacyTasks {
  param(
    [Parameter(Mandatory = $true)]
    [string]$LegacyServiceName
  )

  if (-not (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
    return
  }

  foreach ($taskName in @("${LegacyServiceName}-Restart", "${LegacyServiceName}-Start", "${LegacyServiceName}-Stop")) {
    try {
      Unregister-ScheduledTask -TaskPath '\OpenClaw\' -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    } catch {
    }
  }
}

$resolvedWrapperConfigPath = [System.IO.Path]::GetFullPath($WrapperConfigPath)
$resolvedStartupPath = Resolve-Root -ExplicitPath $StartupPath -FallbackPath ([Environment]::GetFolderPath('Startup'))
$resolvedWinSWRoot = Resolve-Root -ExplicitPath $WinSWRoot -FallbackPath (Join-Path $PSScriptRoot 'tools\winsw')
$resolvedRuntimeSelectionPath = Resolve-Root -ExplicitPath $RuntimeSelectionPath -FallbackPath (Join-Path $PSScriptRoot '.runtime\active-config.json')
$resolvedServiceName = Resolve-ServiceName -ConfigPath $resolvedWrapperConfigPath -ExplicitServiceName $ServiceName

$legacyService = Get-Service -Name $resolvedServiceName -ErrorAction SilentlyContinue
if ($null -ne $legacyService -and -not $NoServiceUninstall) {
  & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'uninstall.ps1') -ConfigPath $resolvedWrapperConfigPath -PurgeTools
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to uninstall legacy service '$resolvedServiceName'."
  }
}

Remove-LegacyTasks -LegacyServiceName $resolvedServiceName
Remove-LegacyTrayShortcuts -Path $resolvedStartupPath -LegacyServiceName $resolvedServiceName
Remove-RememberedSelection -Path $resolvedRuntimeSelectionPath -LegacyServiceName $resolvedServiceName -ConfigPath $resolvedWrapperConfigPath

$legacyWinSWPath = Join-Path $resolvedWinSWRoot $resolvedServiceName
if (Test-Path -LiteralPath $legacyWinSWPath) {
  Remove-Item -LiteralPath $legacyWinSWPath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Legacy cleanup completed for $resolvedServiceName"
