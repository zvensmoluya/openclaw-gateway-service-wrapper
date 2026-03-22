[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('start', 'stop', 'restart')]
  [string]$Action,
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

function Resolve-ControlTaskConfig {
  param(
    [string]$ResolvedConfigPath
  )

  $currentIdentity = Get-ServiceIdentityContext -Mode 'currentUser'
  $selection = Resolve-ServiceConfigSelection -ConfigPath $ResolvedConfigPath
  $bootstrapConfig = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext $currentIdentity
  $service = Get-ServiceDetails -ServiceName $bootstrapConfig.serviceName
  $inspectionIdentity = Resolve-InspectionIdentityContext -Config $bootstrapConfig -ServiceDetails $service
  $config = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext $inspectionIdentity
  $config.configSource = $selection.configSource
  $config.rememberedPath = $selection.rememberedPath
  return $config
}

try {
  $config = Resolve-ControlTaskConfig -ResolvedConfigPath $ConfigPath
  $result = Invoke-ServiceControlTaskAction -Config $config -Action $Action -Origin 'systemTask'
  if (-not $result.success) {
    throw $result.message
  }

  Write-Host $result.message
  exit 0
} catch {
  Write-Error $_
  exit 1
}
