[CmdletBinding()]
param(
  [string]$Version = '0.1.0',
  [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

try {
  if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot 'dist'
  }

  $config = Get-ServiceConfig -ConfigPath (Join-Path $PSScriptRoot 'service-config.json') -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
  $packageName = "openclaw-gateway-service-wrapper-$Version"
  $stagingRoot = Join-Path $OutputDirectory $packageName
  $zipPath = Join-Path $OutputDirectory "$packageName.zip"

  if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
  }

  if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
  }

  Ensure-Directory -Path $OutputDirectory
  Ensure-Directory -Path $stagingRoot

  $rootFiles = @(
    'CHANGELOG.md',
    'CONTRIBUTING.md',
    'LICENSE',
    'README.md',
    'README.zh-CN.md',
    'build-release.ps1',
    'doctor.ps1',
    'install.ps1',
    'invoke-tray-action.ps1',
    'reinstall-service-elevated.ps1',
    'restart.ps1',
    'run-gateway.ps1',
    'service-config.json',
    'service-config.local.example.json',
    'service-config.credential.example.json',
    'service-config.custom-port.example.json',
    'start.ps1',
    'status.ps1',
    'status-service.ps1',
    'stop-gateway.ps1',
    'stop.ps1',
    'tray-controller.ps1',
    'uninstall.ps1',
    'uninstall-service-elevated.ps1'
  )

  foreach ($file in $rootFiles) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $stagingRoot $file) -Force
  }

  foreach ($directory in @('docs', 'src', 'templates', 'tests')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $directory) -Destination (Join-Path $stagingRoot $directory) -Recurse -Force
  }

  $metadata = @{
    name          = 'openclaw-gateway-service-wrapper'
    version       = $Version
    builtAt       = (Get-Date).ToString('o')
    winswVersion  = $config.winswVersion
    winswUrl      = $config.winswDownloadUrl
    winswChecksum = $config.winswChecksum
  }

  Set-Content -LiteralPath (Join-Path $stagingRoot 'release-metadata.json') -Value ($metadata | ConvertTo-Json -Depth 10) -Encoding UTF8

  $hashLines = Get-ChildItem -LiteralPath $stagingRoot -File -Recurse |
    Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
    Sort-Object FullName |
    ForEach-Object {
      $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
      $relativePath = $_.FullName.Substring($stagingRoot.Length + 1)
      "$hash *$relativePath"
    }

  Set-Content -LiteralPath (Join-Path $stagingRoot 'SHA256SUMS.txt') -Value $hashLines -Encoding UTF8

  Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $zipPath -Force
  Write-Host "Created $zipPath"
  exit 0
} catch {
  Write-Error $_
  exit 1
}
