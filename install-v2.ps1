[CmdletBinding()]
param(
  [string]$WrapperConfigPath = (Join-Path $PSScriptRoot 'service-config.json'),
  [string]$PublishRoot,
  [string]$InstallRoot,
  [string]$DataRoot,
  [switch]$SkipLaunch,
  [switch]$SkipLegacyCleanup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-DotNetExecutable {
  $candidates = @(
    (Join-Path $env:USERPROFILE '.dotnet\dotnet.exe'),
    (Get-Command dotnet -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  return $null
}

function Assert-DotNetSdkAvailable {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DotNetPath
  )

  $sdks = & $DotNetPath --list-sdks
  if (-not ($sdks | Where-Object { $_ -like '8.0.407*' })) {
    throw '.NET SDK 8.0.407 is required when the V2 publish layout does not already exist.'
  }
}

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

function Get-PublishRoot {
  if (-not [string]::IsNullOrWhiteSpace($PublishRoot)) {
    return [System.IO.Path]::GetFullPath($PublishRoot)
  }

  return Join-Path $PSScriptRoot 'dist\v2\win-x64\current'
}

function Test-V2PublishLayout {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $required = @(
    (Join-Path $Path 'OpenClaw.Agent.Host.exe'),
    (Join-Path $Path 'OpenClaw.Agent.Cli.exe'),
    (Join-Path $Path 'OpenClaw.Agent.Tray.exe'),
    (Join-Path $Path 'config\agent.json.example'),
    (Join-Path $Path 'assets\tray\openclaw.ico')
  )

  return -not ($required | Where-Object { -not (Test-Path -LiteralPath $_) })
}

function Ensure-PublishLayout {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (Test-V2PublishLayout -Path $Path) {
    return
  }

  if (-not [string]::IsNullOrWhiteSpace($PublishRoot)) {
    throw "Publish root '$Path' is missing required V2 artifacts."
  }

  $dotnet = Resolve-DotNetExecutable
  if ($null -eq $dotnet) {
    throw "V2 publish layout was not found at '$Path', and no dotnet executable is available to build it."
  }

  Assert-DotNetSdkAvailable -DotNetPath $dotnet
  & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build-v2.ps1') -Configuration Release

  if (-not (Test-V2PublishLayout -Path $Path)) {
    throw "V2 publish layout was still not found after running build-v2.ps1. Expected root: $Path"
  }
}

function Copy-DirectoryContents {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Source,
    [Parameter(Mandatory = $true)]
    [string]$Destination
  )

  $null = New-Item -ItemType Directory -Force -Path $Destination
  & robocopy.exe $Source $Destination /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed while copying '$Source' to '$Destination' (exit code $LASTEXITCODE)."
  }
}

function Get-ServiceNameFromWrapperConfig {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
  )

  if (-not (Test-Path -LiteralPath $ConfigPath)) {
    return 'OpenClawService'
  }

  try {
    $json = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ($null -ne $json.serviceName -and -not [string]::IsNullOrWhiteSpace("$($json.serviceName)")) {
      return "$($json.serviceName)"
    }
  } catch {
  }

  return 'OpenClawService'
}

function Assert-LegacyServiceNotRunning {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
  )

  $serviceName = Get-ServiceNameFromWrapperConfig -ConfigPath $ConfigPath
  $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
  if ($null -ne $service -and $service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
    throw "Legacy Service '$serviceName' is still running. Stop the old Service path before installing V2 to avoid dual management."
  }
}

function Set-RunValue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  $registryKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Microsoft\Windows\CurrentVersion\Run')
  try {
    $registryKey.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]::String)
  } finally {
    $registryKey.Dispose()
  }
}

function Invoke-CliJson {
  param(
    [Parameter(Mandatory = $true)]
    [string]$CliPath,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments,
    [Parameter(Mandatory = $true)]
    [string]$ResolvedDataRoot
  )

  $previousDataRoot = [System.Environment]::GetEnvironmentVariable('OPENCLAW_AGENT_DATA_ROOT')
  try {
    [System.Environment]::SetEnvironmentVariable('OPENCLAW_AGENT_DATA_ROOT', $ResolvedDataRoot)
    $output = & $CliPath @Arguments
    $exitCode = $LASTEXITCODE
  } finally {
    [System.Environment]::SetEnvironmentVariable('OPENCLAW_AGENT_DATA_ROOT', $previousDataRoot)
  }

  $payload = $null
  if (-not [string]::IsNullOrWhiteSpace(($output -join [Environment]::NewLine))) {
    try {
      $payload = ($output -join [Environment]::NewLine) | ConvertFrom-Json
    } catch {
    }
  }

  return @{
    exitCode = $exitCode
    payload  = $payload
  }
}

function Stop-ExistingInstallProcesses {
  param(
    [Parameter(Mandatory = $true)]
    [string]$CurrentInstallPath,
    [Parameter(Mandatory = $true)]
    [string]$ResolvedDataRoot
  )

  $existingCliPath = Join-Path $CurrentInstallPath 'OpenClaw.Agent.Cli.exe'
  if (Test-Path -LiteralPath $existingCliPath) {
    try {
      [void](Invoke-CliJson -CliPath $existingCliPath -Arguments @('stop', '--json') -ResolvedDataRoot $ResolvedDataRoot)
    } catch {
    }
  }

  $hostStatePath = Join-Path $ResolvedDataRoot 'state\host-state.json'
  if (Test-Path -LiteralPath $hostStatePath) {
    try {
      $hostState = Get-Content -LiteralPath $hostStatePath -Raw | ConvertFrom-Json
      if ($null -ne $hostState.openClawProcessId -and [int]$hostState.openClawProcessId -gt 0) {
        Stop-Process -Id ([int]$hostState.openClawProcessId) -Force -ErrorAction SilentlyContinue
      }
      if ($null -ne $hostState.hostProcessId -and [int]$hostState.hostProcessId -gt 0) {
        Stop-Process -Id ([int]$hostState.hostProcessId) -Force -ErrorAction SilentlyContinue
      }
    } catch {
    }
  }

  Get-Process -Name 'OpenClaw.Agent.Tray' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Get-Process -Name 'OpenClaw.Agent.Host' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Wait-ForHealthyAgent {
  param(
    [Parameter(Mandatory = $true)]
    [string]$CliPath,
    [Parameter(Mandatory = $true)]
    [string]$ResolvedDataRoot,
    [int]$TimeoutSec = 45
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  do {
    $status = Invoke-CliJson -CliPath $CliPath -Arguments @('status', '--json') -ResolvedDataRoot $ResolvedDataRoot
    if ($null -ne $status.payload -and
      $status.payload.state.current -eq 'Running' -and
      $status.payload.health.ok -eq $true) {
      return
    }

    Start-Sleep -Milliseconds 1000
  } while ((Get-Date) -lt $deadline)

  throw 'V2 agent did not reach Running + health.ok within the expected time window.'
}

function Ensure-TrayRunning {
  param(
    [Parameter(Mandatory = $true)]
    [string]$TrayPath,
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory
  )

  $process = Get-Process -Name 'OpenClaw.Agent.Tray' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $process) {
    Start-Process -FilePath $TrayPath -WorkingDirectory $WorkingDirectory | Out-Null
    Start-Sleep -Seconds 2
  }

  if ($null -eq (Get-Process -Name 'OpenClaw.Agent.Tray' -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    throw 'Tray process is not running after install.'
  }
}

$resolvedPublishRoot = Get-PublishRoot
$resolvedInstallRoot = Resolve-Root -ExplicitPath $InstallRoot -EnvironmentVariable 'OPENCLAW_AGENT_INSTALL_ROOT' -FallbackPath (Join-Path $env:LOCALAPPDATA 'OpenClaw\app')
$resolvedDataRoot = Resolve-Root -ExplicitPath $DataRoot -EnvironmentVariable 'OPENCLAW_AGENT_DATA_ROOT' -FallbackPath (Join-Path $env:LOCALAPPDATA 'OpenClaw')
$resolvedWrapperConfigPath = [System.IO.Path]::GetFullPath($WrapperConfigPath)
$currentInstallPath = Join-Path $resolvedInstallRoot 'current'
$configPath = Join-Path $resolvedDataRoot 'config\agent.json'

Assert-LegacyServiceNotRunning -ConfigPath $resolvedWrapperConfigPath
Ensure-PublishLayout -Path $resolvedPublishRoot

New-Item -ItemType Directory -Force -Path $resolvedInstallRoot | Out-Null
if (Test-Path -LiteralPath $currentInstallPath) {
  Stop-ExistingInstallProcesses -CurrentInstallPath $currentInstallPath -ResolvedDataRoot $resolvedDataRoot
  Remove-Item -LiteralPath $currentInstallPath -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $currentInstallPath | Out-Null
Copy-DirectoryContents -Source $resolvedPublishRoot -Destination $currentInstallPath

New-Item -ItemType Directory -Force -Path (Join-Path $resolvedDataRoot 'config') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $resolvedDataRoot 'state') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $resolvedDataRoot 'logs') | Out-Null

$cliPath = Join-Path $currentInstallPath 'OpenClaw.Agent.Cli.exe'
$hostPath = Join-Path $currentInstallPath 'OpenClaw.Agent.Host.exe'
$trayPath = Join-Path $currentInstallPath 'OpenClaw.Agent.Tray.exe'

if (-not (Test-Path -LiteralPath $cliPath)) {
  throw "Installed CLI executable was not found: $cliPath"
}

if (-not (Test-Path -LiteralPath $hostPath)) {
  throw "Installed Host executable was not found: $hostPath"
}

if (-not (Test-Path -LiteralPath $trayPath)) {
  throw "Installed Tray executable was not found: $trayPath"
}

if (-not (Test-Path -LiteralPath (Join-Path $currentInstallPath 'assets\tray\openclaw.ico'))) {
  throw 'Installed tray assets were not found.'
}

if (-not (Test-Path -LiteralPath $configPath)) {
  $initConfigResult = Invoke-CliJson -CliPath $cliPath -Arguments @('init-config', '--from-wrapper', $resolvedWrapperConfigPath, '--json') -ResolvedDataRoot $resolvedDataRoot
  if ($initConfigResult.exitCode -ne 0) {
    throw "Failed to generate agent config from '$resolvedWrapperConfigPath'."
  }
}

Set-RunValue -Name 'OpenClaw.Agent.Host' -Value ('"{0}" --autostart' -f $hostPath)
Set-RunValue -Name 'OpenClaw.Agent.Tray' -Value ('"{0}"' -f $trayPath)

if (-not $SkipLaunch) {
  [void](Invoke-CliJson -CliPath $cliPath -Arguments @('start', '--json') -ResolvedDataRoot $resolvedDataRoot)
  Ensure-TrayRunning -TrayPath $trayPath -WorkingDirectory $currentInstallPath
  Wait-ForHealthyAgent -CliPath $cliPath -ResolvedDataRoot $resolvedDataRoot
}

if (-not $SkipLegacyCleanup) {
  & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'cleanup-v2-legacy.ps1') -WrapperConfigPath $resolvedWrapperConfigPath
  if ($LASTEXITCODE -ne 0) {
    throw 'Legacy cleanup did not complete successfully.'
  }
}

Write-Host "Installed V2 agent to $currentInstallPath"
Write-Host "Data root: $resolvedDataRoot"
