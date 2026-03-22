[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('start', 'stop', 'restart')]
  [string]$Action,
  [string]$ConfigPath,
  [string]$ResultPath,
  [int]$TimeoutSec = 90,
  [switch]$Elevated,
  [switch]$NoInvoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

function Write-ServiceActionResultFile {
  param(
    [hashtable]$Result
  )

  if ([string]::IsNullOrWhiteSpace($ResultPath)) {
    return
  }

  $directory = Split-Path -Parent $ResultPath
  if (-not [string]::IsNullOrWhiteSpace($directory)) {
    Ensure-Directory -Path $directory
  }

  Set-Content -LiteralPath $ResultPath -Value ($Result | ConvertTo-Json -Depth 10) -Encoding UTF8
}

function Get-ActionPrimaryMessage {
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

function Resolve-InvokerConfig {
  param(
    [string]$ResolvedConfigPath
  )

  $selection = Resolve-ServiceConfigSelection -ConfigPath $ResolvedConfigPath
  $config = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
  $config.configSource = $selection.configSource
  $config.rememberedPath = $selection.rememberedPath
  return $config
}

function New-ServiceActionResult {
  param(
    [bool]$Success,
    [string]$Message,
    [string]$ErrorMessage,
    [string]$RequestId = $null,
    [bool]$Busy = $false
  )

  return @{
    action      = $Action
    success     = $Success
    message     = $Message
    error       = $ErrorMessage
    requestId   = $RequestId
    busy        = $Busy
    writtenAt   = (Get-Date).ToString('o')
  }
}

function Test-IsElevationCanceled {
  param(
    [Parameter(Mandatory = $true)]
    $Exception
  )

  if ($Exception -is [System.ComponentModel.Win32Exception] -and $Exception.NativeErrorCode -eq 1223) {
    return $true
  }

  if ($Exception.HResult -eq -2147023673) {
    return $true
  }

  return ($Exception.Message -match 'cancel')
}

function Invoke-ElevatedServiceAction {
  param(
    [hashtable]$Config
  )

  $helperResultPath = if ([string]::IsNullOrWhiteSpace($ResultPath)) {
    Join-Path $env:TEMP "openclaw-service-action-$([guid]::NewGuid().ToString('N')).json"
  } else {
    $ResultPath
  }
  $arguments = @(
    '-NoProfile',
    '-WindowStyle',
    'Hidden',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    (Join-Path $PSScriptRoot 'invoke-service-action.ps1'),
    '-Action',
    $Action,
    '-TimeoutSec',
    [string]$TimeoutSec,
    '-Elevated',
    '-ResultPath',
    $helperResultPath
  )

  if (-not [string]::IsNullOrWhiteSpace($Config.sourceConfigPath)) {
    $arguments += @('-ConfigPath', $Config.sourceConfigPath)
  }

  try {
    $process = Start-Process `
      -FilePath (Get-WindowsPowerShellExecutablePath) `
      -ArgumentList (Join-ProcessArgumentString -Arguments $arguments) `
      -Verb RunAs `
      -WindowStyle Hidden `
      -PassThru `
      -Wait
  } catch {
    if (Test-IsElevationCanceled -Exception $_.Exception) {
      return (New-ServiceActionResult -Success $false -Message 'Action canceled at the UAC prompt.' -ErrorMessage 'Action canceled at the UAC prompt.')
    }

    throw
  }

  if (Test-Path -LiteralPath $helperResultPath) {
    $payload = ConvertTo-Hashtable -InputObject (Get-Content -LiteralPath $helperResultPath -Raw | ConvertFrom-Json)
    if ([string]::IsNullOrWhiteSpace($ResultPath)) {
      Remove-Item -LiteralPath $helperResultPath -Force
    }

    return $payload
  }

  if ($process.ExitCode -eq 0) {
    return (New-ServiceActionResult -Success $true -Message "Service action '$Action' completed." -ErrorMessage $null)
  }

  return (New-ServiceActionResult -Success $false -Message "Service action '$Action' failed." -ErrorMessage "Service action '$Action' failed.")
}

if ($NoInvoke) {
  return
}

try {
  $config = Resolve-InvokerConfig -ResolvedConfigPath $ConfigPath
  $result = if (-not $Elevated -and -not (Test-IsCurrentProcessElevated)) {
    Invoke-ElevatedServiceAction -Config $config
  } else {
    $bridgeResult = Invoke-ServiceControlAction -Config $config -Action $Action -TimeoutSec $TimeoutSec
    New-ServiceActionResult `
      -Success ([bool]$bridgeResult.success) `
      -Message "$($bridgeResult.message)" `
      -ErrorMessage "$($bridgeResult.error)" `
      -RequestId "$($bridgeResult.requestId)" `
      -Busy:([bool]$bridgeResult.busy)
  }

  Write-ServiceActionResultFile -Result $result

  if ($result.success) {
    Write-Host $result.message
    exit 0
  }

  $errorText = if ([string]::IsNullOrWhiteSpace($result.message)) { "Service action '$Action' failed." } else { $result.message }
  [Console]::Error.WriteLine($errorText)
  exit 1
} catch {
  $message = Get-ActionPrimaryMessage -Lines @($_.Exception.Message) -Fallback "Service action '$Action' failed."
  $result = New-ServiceActionResult -Success $false -Message $message -ErrorMessage $message
  Write-ServiceActionResultFile -Result $result
  [Console]::Error.WriteLine($message)
  exit 1
}
