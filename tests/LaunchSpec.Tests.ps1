Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

Describe 'OpenClaw launch spec resolution' {
  InModuleScope OpenClawGatewayServiceWrapper {
    BeforeEach {
      $script:testPaths = @()
    }

    AfterEach {
      foreach ($path in $script:testPaths) {
        if (Test-Path -LiteralPath $path) {
          if ((Get-Item -LiteralPath $path).PSIsContainer) {
            Remove-Item -LiteralPath $path -Recurse -Force
          } else {
            Remove-Item -LiteralPath $path -Force
          }
        }
      }
    }

    It 'normalizes openclaw.cmd to direct node execution when sibling node.exe and openclaw.mjs exist' {
      $installRoot = Join-Path $env:TEMP "openclaw-launch-$([guid]::NewGuid().ToString('N'))"
      $script:testPaths += $installRoot
      $nodeModulesRoot = Join-Path $installRoot 'node_modules\openclaw'

      New-Item -ItemType Directory -Path $nodeModulesRoot -Force | Out-Null
      Set-Content -LiteralPath (Join-Path $installRoot 'openclaw.cmd') -Value '@echo off' -Encoding ASCII
      Set-Content -LiteralPath (Join-Path $installRoot 'node.exe') -Value '' -Encoding ASCII
      Set-Content -LiteralPath (Join-Path $nodeModulesRoot 'openclaw.mjs') -Value 'console.log("ok")' -Encoding UTF8

      $spec = Resolve-OpenClawLaunchSpec -Config @{
        openclawCommand = (Join-Path $installRoot 'openclaw.cmd')
      } -IdentityContext @{
        localAppData = $env:LOCALAPPDATA
      }

      $spec.launchMode | Should -Be 'directNodeFromCmdShim'
      $spec.executablePath | Should -Be (Join-Path $installRoot 'node.exe')
      @($spec.preArguments) | Should -Contain (Join-Path $nodeModulesRoot 'openclaw.mjs')
      $spec.requestedCommandPath | Should -Be (Join-Path $installRoot 'openclaw.cmd')
    }

    It 'keeps direct executables unchanged when no cmd shim normalization applies' {
      $spec = Resolve-OpenClawLaunchSpec -Config @{
        openclawCommand = 'powershell.exe'
      } -IdentityContext @{
        localAppData = $env:LOCALAPPDATA
      }

      $spec.launchMode | Should -Be 'directCommand'
      $spec.preArguments.Count | Should -Be 0
      $spec.executablePath | Should -Match 'powershell\.exe$'
    }
  }
}
