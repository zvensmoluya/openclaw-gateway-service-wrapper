[CmdletBinding()]
param(
  [string]$Configuration = 'Release',
  [string]$RuntimeIdentifier = 'win-x64',
  [string]$OutputRoot
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

  throw 'dotnet executable could not be found.'
}

$dotnet = Resolve-DotNetExecutable
$repoRoot = $PSScriptRoot
$agentRoot = Join-Path $repoRoot 'agent'

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $repoRoot 'dist\v2'
}

$publishRoot = Join-Path $OutputRoot "$RuntimeIdentifier\current"
$hostProject = Join-Path $agentRoot 'src\OpenClaw.Agent.Host\OpenClaw.Agent.Host.csproj'
$cliProject = Join-Path $agentRoot 'src\OpenClaw.Agent.Cli\OpenClaw.Agent.Cli.csproj'
$trayProject = Join-Path $agentRoot 'src\OpenClaw.Agent.Tray\OpenClaw.Agent.Tray.csproj'
$templatePath = Join-Path $agentRoot 'templates\agent.json.example'
$readmePath = Join-Path $agentRoot 'README.md'
$trayAssetsPath = Join-Path $repoRoot 'assets\tray'

if (Test-Path -LiteralPath $publishRoot) {
  Remove-Item -LiteralPath $publishRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $publishRoot | Out-Null

& $dotnet publish $hostProject `
  -c $Configuration `
  -r $RuntimeIdentifier `
  --self-contained true `
  -o $publishRoot `
  /p:UseAppHost=true `
  /p:PublishSingleFile=false

& $dotnet publish $cliProject `
  -c $Configuration `
  -r $RuntimeIdentifier `
  --self-contained true `
  -o $publishRoot `
  /p:UseAppHost=true `
  /p:PublishSingleFile=false

& $dotnet publish $trayProject `
  -c $Configuration `
  -r $RuntimeIdentifier `
  --self-contained true `
  -o $publishRoot `
  /p:UseAppHost=true `
  /p:PublishSingleFile=false

New-Item -ItemType Directory -Force -Path (Join-Path $publishRoot 'config') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $publishRoot 'state') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $publishRoot 'logs') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $publishRoot 'assets\tray') | Out-Null

Copy-Item -LiteralPath $templatePath -Destination (Join-Path $publishRoot 'config\agent.json.example') -Force
Copy-Item -LiteralPath $readmePath -Destination (Join-Path $publishRoot 'README.md') -Force
Get-ChildItem -LiteralPath $trayAssetsPath -File | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $publishRoot 'assets\tray') -Force
}

Write-Host "Published V2 agent layout to $publishRoot"
