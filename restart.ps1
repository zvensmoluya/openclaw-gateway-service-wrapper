[CmdletBinding()]
param(
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

try {
  if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'service-config.json'
  }

  $config = Get-ServiceConfig -ConfigPath $ConfigPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
  Invoke-WinSWCommand -Config $config -Command 'restart'
  if (-not (Wait-ForServiceStatus -ServiceName $config.serviceName -DesiredStatus 'Running' -TimeoutSec 30)) {
    throw "Service '$($config.serviceName)' did not return to the Running state within 30 seconds."
  }

  Write-Host "Service '$($config.serviceName)' restarted successfully."
  exit 0
} catch {
  Write-Error $_
  exit 1
}
