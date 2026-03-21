[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('start', 'stop', 'restart')]
  [string]$Action,
  [string]$ConfigPath,
  [string]$ResultPath,
  [switch]$NoInvoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WindowsPowerShellExecutablePath {
  $command = Get-Command -Name 'powershell.exe' -CommandType Application -ErrorAction SilentlyContinue
  if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
    return $command.Source
  }

  return (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
}

function Resolve-TrayActionScriptPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ResolvedAction
  )

  $scriptName = switch ($ResolvedAction) {
    'start' { 'start.ps1' }
    'stop' { 'stop.ps1' }
    'restart' { 'restart.ps1' }
    default { throw "Unsupported tray action '$ResolvedAction'." }
  }

  return (Join-Path $PSScriptRoot $scriptName)
}

function Write-TrayActionResult {
  param(
    [bool]$Success,
    [string]$Message
  )

  if ([string]::IsNullOrWhiteSpace($ResultPath)) {
    return
  }

  $directory = Split-Path -Parent $ResultPath
  if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
    [void](New-Item -ItemType Directory -Path $directory -Force)
  }

  $payload = @{
    action    = $Action
    success   = $Success
    message   = $Message
    writtenAt = (Get-Date).ToString('o')
  }

  Set-Content -LiteralPath $ResultPath -Value ($payload | ConvertTo-Json -Depth 10) -Encoding UTF8
}

function Get-PrimaryMessage {
  param(
    [AllowNull()]
    [string[]]$Lines,
    [string]$Fallback
  )

  $message = $Lines |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Select-Object -First 1

  if ([string]::IsNullOrWhiteSpace($message)) {
    return $Fallback
  }

  return $message.Trim()
}

function Invoke-TrayActionCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ResolvedAction,
    [string]$ResolvedConfigPath
  )

  $scriptPath = Resolve-TrayActionScriptPath -ResolvedAction $ResolvedAction
  $arguments = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $scriptPath
  )

  if (-not [string]::IsNullOrWhiteSpace($ResolvedConfigPath)) {
    $arguments += @('-ConfigPath', $ResolvedConfigPath)
  }

  $output = & (Get-WindowsPowerShellExecutablePath) @arguments 2>&1
  return @{
    exitCode = $LASTEXITCODE
    output   = @($output | ForEach-Object { "$_" })
  }
}

if ($NoInvoke) {
  return
}

try {
  $result = Invoke-TrayActionCommand -ResolvedAction $Action -ResolvedConfigPath $ConfigPath
  if ($result.exitCode -ne 0) {
    $message = Get-PrimaryMessage -Lines $result.output -Fallback "Tray action '$Action' failed."
    Write-TrayActionResult -Success $false -Message $message
    [Console]::Error.WriteLine($message)
    exit $result.exitCode
  }

  $message = Get-PrimaryMessage -Lines $result.output -Fallback "Tray action '$Action' completed."
  Write-TrayActionResult -Success $true -Message $message
  Write-Host $message
  exit 0
} catch {
  $message = $_.Exception.Message
  Write-TrayActionResult -Success $false -Message $message
  [Console]::Error.WriteLine($message)
  exit 1
}
