[CmdletBinding()]
param(
  [string]$ConfigPath,
  [int]$WaitForStopTimeoutSec = 45,
  [int]$StartTimeoutSec = 30,
  [int]$StartRetryCount = 3,
  [int]$StartRetryDelaySec = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

function Write-RestartTaskAudit {
  param(
    [Parameter(Mandatory = $true)]
    [string]$LogPath,
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  $timestamp = (Get-Date).ToString('o')
  Add-Content -LiteralPath $LogPath -Value "$timestamp $Message" -Encoding UTF8
}

$config = $null
$taskInfo = $null
$logPath = $null

try {
  if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'service-config.json'
  }

  $config = Resolve-ServiceConfig -ConfigPath $ConfigPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
  $taskInfo = Get-ServiceRestartTaskInfo -Config $config
  Ensure-Directory -Path $config.logsDirectory
  $logPath = $taskInfo.logPath

  Write-RestartTaskAudit -LogPath $logPath -Message "restart bridge triggered for service '$($config.serviceName)'."

  $deadline = (Get-Date).AddSeconds($WaitForStopTimeoutSec)
  $serviceDetails = $null
  do {
    $serviceDetails = Get-ServiceDetails -ServiceName $config.serviceName
    if (-not $serviceDetails.installed) {
      throw "Service '$($config.serviceName)' is not installed."
    }

    if ($serviceDetails.status -notin @('Running', 'StopPending', 'StartPending')) {
      break
    }

    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  if ($serviceDetails.status -in @('Running', 'StopPending', 'StartPending')) {
    throw "Service '$($config.serviceName)' did not leave the running state within $WaitForStopTimeoutSec seconds."
  }

  Write-RestartTaskAudit -LogPath $logPath -Message "service '$($config.serviceName)' reached state '$($serviceDetails.status)'; starting recovery."

  $started = $false
  for ($attempt = 1; $attempt -le $StartRetryCount; $attempt++) {
    try {
      Start-Service -Name $config.serviceName -ErrorAction Stop
      $started = $true
      Write-RestartTaskAudit -LogPath $logPath -Message "start attempt $attempt submitted for service '$($config.serviceName)'."
      break
    } catch {
      Write-RestartTaskAudit -LogPath $logPath -Message "start attempt $attempt failed: $($_.Exception.Message)"
      if ($attempt -ge $StartRetryCount) {
        throw
      }

      Start-Sleep -Seconds $StartRetryDelaySec
    }
  }

  if (-not $started) {
    throw "Service '$($config.serviceName)' could not be started."
  }

  if (-not (Wait-ForServiceStatus -ServiceName $config.serviceName -DesiredStatus 'Running' -TimeoutSec $StartTimeoutSec)) {
    throw "Service '$($config.serviceName)' did not reach the Running state within $StartTimeoutSec seconds."
  }

  Write-RestartTaskAudit -LogPath $logPath -Message "service '$($config.serviceName)' is running again."
  exit 0
} catch {
  if (-not [string]::IsNullOrWhiteSpace($logPath)) {
    Write-RestartTaskAudit -LogPath $logPath -Message "restart bridge failed: $($_.Exception.Message)"
  }

  Write-Error $_
  exit 1
}
