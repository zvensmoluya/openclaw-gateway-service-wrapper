[CmdletBinding()]
param(
  [switch]$Purge,
  [string]$InstallRoot,
  [string]$DataRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Root {
  param(
    [string]$ExplicitPath,
    [string]$EnvironmentVariable,
    [string]$FallbackPath
  )

  if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
    return [System.IO.Path]::GetFullPath($ExplicitPath)
  }

  if (-not [string]::IsNullOrWhiteSpace($EnvironmentVariable)) {
    $envValue = [System.Environment]::GetEnvironmentVariable($EnvironmentVariable)
    if (-not [string]::IsNullOrWhiteSpace($envValue)) {
      return [System.IO.Path]::GetFullPath($envValue)
    }
  }

  return [System.IO.Path]::GetFullPath($FallbackPath)
}

function Remove-RunValue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $registryKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run', $true)
  if ($null -ne $registryKey) {
    try {
      $registryKey.DeleteValue($Name, $false)
    } finally {
      $registryKey.Dispose()
    }
  }
}

$resolvedInstallRoot = Resolve-Root -ExplicitPath $InstallRoot -EnvironmentVariable 'OPENCLAW_AGENT_INSTALL_ROOT' -FallbackPath (Join-Path $env:LOCALAPPDATA 'OpenClaw\app')
$resolvedDataRoot = Resolve-Root -ExplicitPath $DataRoot -EnvironmentVariable 'OPENCLAW_AGENT_DATA_ROOT' -FallbackPath (Join-Path $env:LOCALAPPDATA 'OpenClaw')
$currentInstallPath = Join-Path $resolvedInstallRoot 'current'
$cliPath = Join-Path $currentInstallPath 'OpenClaw.Agent.Cli.exe'
$hostStatePath = Join-Path $resolvedDataRoot 'state\host-state.json'

Remove-RunValue -Name 'OpenClaw.Agent.Host'
Remove-RunValue -Name 'OpenClaw.Agent.Tray'

if (Test-Path -LiteralPath $cliPath) {
  $originalDataRoot = [System.Environment]::GetEnvironmentVariable('OPENCLAW_AGENT_DATA_ROOT')
  try {
    [System.Environment]::SetEnvironmentVariable('OPENCLAW_AGENT_DATA_ROOT', $resolvedDataRoot)
    try {
      & $cliPath stop --json | Out-Null
    } catch {
    }
  } finally {
    [System.Environment]::SetEnvironmentVariable('OPENCLAW_AGENT_DATA_ROOT', $originalDataRoot)
  }
}

Get-Process -Name 'OpenClaw.Agent.Tray' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $hostStatePath) {
  try {
    $hostState = Get-Content -LiteralPath $hostStatePath -Raw | ConvertFrom-Json
    if ($null -ne $hostState.hostProcessId -and [int]$hostState.hostProcessId -gt 0) {
      Stop-Process -Id ([int]$hostState.hostProcessId) -Force -ErrorAction SilentlyContinue
    }
  } catch {
  }
}

if (Test-Path -LiteralPath $currentInstallPath) {
  Remove-Item -LiteralPath $currentInstallPath -Recurse -Force
}

if ($Purge) {
  if (Test-Path -LiteralPath $resolvedDataRoot) {
    Remove-Item -LiteralPath $resolvedDataRoot -Recurse -Force
  }
} else {
  foreach ($name in @('config', 'state', 'logs')) {
    $path = Join-Path $resolvedDataRoot $name
    if (-not (Test-Path -LiteralPath $path)) {
      New-Item -ItemType Directory -Force -Path $path | Out-Null
    }
  }
}

if (Test-Path -LiteralPath $resolvedInstallRoot) {
  $remaining = Get-ChildItem -LiteralPath $resolvedInstallRoot -Force -ErrorAction SilentlyContinue
  if ($null -eq $remaining -or $remaining.Count -eq 0) {
    Remove-Item -LiteralPath $resolvedInstallRoot -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "Uninstalled V2 agent from $currentInstallPath"
