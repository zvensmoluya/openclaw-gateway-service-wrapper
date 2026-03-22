[CmdletBinding()]
param(
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

try {
  $config = Resolve-ServiceConfig -ConfigPath $ConfigPath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
  $result = Start-ManagedServiceWithRecovery -Config $config -TimeoutSec 30
  Write-Host $result.message
  exit 0
} catch {
  Write-Error $_
  exit 1
}
