Describe 'V2 install scripts' {
  BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $script:stagePublishRoot = {
      param(
        [Parameter(Mandatory = $true)]
        [string]$Root
      )

      New-Item -ItemType Directory -Force -Path (Join-Path $Root 'config') | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $Root 'logs') | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $Root 'state') | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $Root 'assets\tray') | Out-Null
      Copy-Item -LiteralPath (Get-Command powershell.exe).Source -Destination (Join-Path $Root 'OpenClaw.Agent.Host.exe')
      Copy-Item -LiteralPath (Get-Command powershell.exe).Source -Destination (Join-Path $Root 'OpenClaw.Agent.Cli.exe')
      Copy-Item -LiteralPath (Get-Command powershell.exe).Source -Destination (Join-Path $Root 'OpenClaw.Agent.Tray.exe')
      Set-Content -LiteralPath (Join-Path $Root 'config\agent.json.example') -Value '{}'
      Copy-Item -LiteralPath (Join-Path $repoRoot 'assets\tray\openclaw.ico') -Destination (Join-Path $Root 'assets\tray\openclaw.ico')
    }
  }

  AfterEach {
    Remove-ItemProperty -Path $runKeyPath -Name 'OpenClaw.Agent.Host' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $runKeyPath -Name 'OpenClaw.Agent.Tray' -ErrorAction SilentlyContinue
  }

  It 'installs the V2 layout and registers host and tray startup entries' {
    $tempRoot = Join-Path $env:TEMP ("openclaw-v2-install-test-" + [guid]::NewGuid().ToString('N'))
    $publishRoot = Join-Path $tempRoot 'publish'
    $installRoot = Join-Path $tempRoot 'app'
    $dataRoot = Join-Path $tempRoot 'data'
    $wrapperConfigPath = Join-Path $tempRoot 'wrapper.json'

    try {
      & $script:stagePublishRoot -Root $publishRoot
      New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'config') | Out-Null
      Set-Content -LiteralPath (Join-Path $dataRoot 'config\agent.json') -Value @'
{
  "openclaw": {
    "executable": "openclaw.cmd",
    "arguments": [],
    "workingDirectory": null,
    "configPath": "%USERPROFILE%\\.openclaw\\openclaw.json"
  },
  "network": {
    "bind": "loopback",
    "port": 18789
  },
  "proxy": {
    "httpProxy": null,
    "httpsProxy": null,
    "allProxy": null,
    "noProxy": null
  },
  "tray": {
    "title": "OpenClaw",
    "notifications": "all",
    "refresh": {
      "fastSeconds": 30,
      "deepSeconds": 180,
      "menuSeconds": 10
    },
    "icons": {
      "default": null
    }
  }
}
'@
      Set-Content -LiteralPath $wrapperConfigPath -Value '{ "serviceName": "OpenClawServiceV2InstallTest" }'

      & (Join-Path $repoRoot 'install-v2.ps1') -PublishRoot $publishRoot -InstallRoot $installRoot -DataRoot $dataRoot -WrapperConfigPath $wrapperConfigPath -SkipLaunch -SkipLegacyCleanup

      Test-Path (Join-Path $installRoot 'current\OpenClaw.Agent.Host.exe') | Should -BeTrue
      Test-Path (Join-Path $installRoot 'current\OpenClaw.Agent.Cli.exe') | Should -BeTrue
      Test-Path (Join-Path $installRoot 'current\OpenClaw.Agent.Tray.exe') | Should -BeTrue
      Test-Path (Join-Path $installRoot 'current\assets\tray\openclaw.ico') | Should -BeTrue
      (Get-ItemPropertyValue -Path $runKeyPath -Name 'OpenClaw.Agent.Host') | Should -Match 'OpenClaw\.Agent\.Host\.exe" --autostart$'
      (Get-ItemPropertyValue -Path $runKeyPath -Name 'OpenClaw.Agent.Tray') | Should -Match 'OpenClaw\.Agent\.Tray\.exe"$'
    } finally {
      if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
      }
    }
  }

  It 'uninstalls the V2 layout and purges the data root when requested' {
    $tempRoot = Join-Path $env:TEMP ("openclaw-v2-uninstall-test-" + [guid]::NewGuid().ToString('N'))
    $installRoot = Join-Path $tempRoot 'app'
    $dataRoot = Join-Path $tempRoot 'data'

    try {
      New-Item -ItemType Directory -Force -Path (Join-Path $installRoot 'current') | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'config') | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'state') | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $dataRoot 'logs') | Out-Null
      Set-Content -LiteralPath (Join-Path $installRoot 'current\OpenClaw.Agent.Cli.exe') -Value 'stub'
      New-Item -Path $runKeyPath -Force | Out-Null
      New-ItemProperty -Path $runKeyPath -Name 'OpenClaw.Agent.Host' -Value '"host"' -PropertyType String -Force | Out-Null
      New-ItemProperty -Path $runKeyPath -Name 'OpenClaw.Agent.Tray' -Value '"tray"' -PropertyType String -Force | Out-Null

      & (Join-Path $repoRoot 'uninstall-v2.ps1') -InstallRoot $installRoot -DataRoot $dataRoot -Purge

      Test-Path $installRoot | Should -BeFalse
      Test-Path $dataRoot | Should -BeFalse
      { Get-ItemProperty -Path $runKeyPath -Name 'OpenClaw.Agent.Host' -ErrorAction Stop } | Should -Throw
      { Get-ItemProperty -Path $runKeyPath -Name 'OpenClaw.Agent.Tray' -ErrorAction Stop } | Should -Throw
    } finally {
      if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
      }
    }
  }
}
