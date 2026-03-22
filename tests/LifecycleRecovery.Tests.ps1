Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

Describe 'service lifecycle recovery' {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
  }

  InModuleScope OpenClawGatewayServiceWrapper {
    BeforeEach {
      $script:testConfig = @{
        serviceName        = 'OpenClawService'
        port               = 18789
        stopTimeoutSeconds = 15
      }
    }

    It 'detects a stuck StopPending service with residual listeners' {
      Mock Get-ServiceDetails {
        @{
          installed = $true
          name      = 'OpenClawService'
          status    = 'StopPending'
          startType = 'Automatic'
          processId = 32032
          startName = 'LocalSystem'
          pathName  = 'OpenClawService.exe'
        }
      }
      Mock Read-RunState {
        @{
          wrapperProcessId = 26524
        }
      }
      Mock Get-PortListeners {
        @(
          [pscustomobject]@{
            processId = 38744
          }
        )
      }
      Mock Test-ProcessExists { $true }

      $context = Get-ServiceRecoveryContext -Config $script:testConfig

      $context.isPending | Should -BeTrue
      $context.isStopPending | Should -BeTrue
      $context.isStuckStopping | Should -BeTrue
      $context.hasPortListeners | Should -BeTrue
      $context.service.transitionStatus | Should -Be 'StopPending'
      $context.service.stuckStopping | Should -BeTrue
      $context.listenerProcessIds | Should -Contain 38744
    }

    It 'falls back to residual cleanup when stop does not reach Stopped' {
      $script:stopWaitCalls = 0

      Mock Invoke-WinSWCommand {}
      Mock Wait-ForServiceStatus {
        param($ServiceName, $DesiredStatus, $TimeoutSec)
        if ($DesiredStatus -eq 'Stopped') {
          $script:stopWaitCalls++
          return ($script:stopWaitCalls -ge 2)
        }

        return $false
      }
      Mock Get-ServiceRecoveryContext {
        @{
          status               = 'StopPending'
          isStopPending        = $true
          isPending            = $true
          isStuckStopping      = $true
          hasPortListeners     = $true
          existingProcessIds   = @(26524, 38744)
          service              = @{
            status = 'StopPending'
          }
        }
      }
      Mock Invoke-ServiceResidualCleanup {
        @{
          success = $true
          context = @{
            status = 'Stopped'
          }
        }
      }

      $result = Stop-ManagedServiceWithRecovery -Config $script:testConfig -TimeoutSec 30

      $result.cleanupAttempted | Should -BeTrue
      $result.message | Should -Be "Service 'OpenClawService' is stopped."
      Should -Invoke Invoke-ServiceResidualCleanup -Times 1 -Exactly
    }

    It 'cleans a stuck stopping service before start' {
      $script:startContextCalls = 0
      $script:commands = @()

      Mock Get-ServiceRecoveryContext {
        $script:startContextCalls++
        if ($script:startContextCalls -eq 1) {
          return @{
            needsStartRecovery                 = $true
            isStopPending                      = $true
            isPending                          = $true
            isPortOccupiedWhileServiceNotRunning = $true
            service = @{
              status = 'StopPending'
            }
          }
        }

        return @{
          needsStartRecovery                 = $false
          isStopPending                      = $false
          isPending                          = $false
          isPortOccupiedWhileServiceNotRunning = $false
          service = @{
            status = 'Running'
          }
        }
      }
      Mock Invoke-ServiceResidualCleanup {
        @{
          success = $true
          context = @{
            status = 'Stopped'
          }
        }
      }
      Mock Wait-ForServiceStatus { $true }
      Mock Invoke-WinSWCommand {
        param($Config, $Command)
        $script:commands += $Command
      }

      $result = Start-ManagedServiceWithRecovery -Config $script:testConfig -TimeoutSec 30

      $result.recovered | Should -BeTrue
      $result.cleanupAttempted | Should -BeTrue
      $result.message | Should -Be 'Recovered a stuck stop and started the service.'
      $script:commands | Should -Contain 'start'
      Should -Invoke Invoke-ServiceResidualCleanup -Times 1 -Exactly
    }

    It 'restarts by composing stop and start recovery' {
      Mock Stop-ManagedServiceWithRecovery {
        @{
          message = "Service 'OpenClawService' is stopped."
          recovered = $true
        }
      }
      Mock Start-ManagedServiceWithRecovery {
        @{
          message = "Service 'OpenClawService' is running."
          recovered = $false
        }
      }
      Mock Get-ServiceRecoveryContext {
        @{
          service = @{
            status = 'Running'
          }
        }
      }

      $result = Restart-ManagedServiceWithRecovery -Config $script:testConfig -TimeoutSec 30

      $result.message | Should -Be 'Recovered a stuck stop and restarted the service.'
      Should -Invoke Stop-ManagedServiceWithRecovery -Times 1 -Exactly
      Should -Invoke Start-ManagedServiceWithRecovery -Times 1 -Exactly
    }
  }
}
