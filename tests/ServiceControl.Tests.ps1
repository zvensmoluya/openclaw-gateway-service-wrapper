Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking

Describe 'service control bridge helpers' {
  InModuleScope OpenClawGatewayServiceWrapper {
    BeforeEach {
      $script:testConfig = @{
        serviceName           = 'OpenClawService'
        sourceConfigPath      = 'C:\OpenClaw-Service\service-config.json'
        runtimeStateDirectory = 'C:\OpenClaw-Service\.runtime'
        logsDirectory         = 'C:\OpenClaw-Service\logs'
        winswHome             = 'tools\winsw'
      }
    }

    It 'fails closed when a control task is missing' {
      Mock Get-ServiceControlTaskStatus {
        @{
          fullTaskName = '\OpenClaw\OpenClawService-Start'
          exists       = $false
          matches      = $false
        }
      }

      { Invoke-ServiceControlAction -Config $script:testConfig -Action 'start' } | Should -Throw '*SYSTEM-backed lifecycle control*'
    }

    It 'writes a request and waits for the matching result' {
      Mock Get-ServiceControlTaskStatus {
        @{
          fullTaskName = '\OpenClaw\OpenClawService-Stop'
          exists       = $true
          matches      = $true
        }
      }
      Mock Get-ServiceControlTaskInfo {
        @{
          fullTaskName = '\OpenClaw\OpenClawService-Stop'
          resultPath   = 'C:\OpenClaw-Service\.runtime\OpenClawService.control-stop.result.json'
        }
      }
      Mock Write-ServiceControlRequest { 'request.json' }
      Mock Write-ServiceControlState { 'state.json' }
      Mock Write-ServiceControlAudit {}
      Mock Start-WrapperScheduledTask { $true }
      Mock Wait-ForServiceControlResult {
        @{
          success   = $true
          busy      = $false
          requestId = 'request-1'
          message   = "Service 'OpenClawService' is stopped."
          error     = $null
        }
      }

      $result = Invoke-ServiceControlAction -Config $script:testConfig -Action 'stop'

      $result.success | Should -BeTrue
      $result.message | Should -Be "Service 'OpenClawService' is stopped."
      Should -Invoke Write-ServiceControlRequest -Times 1 -Exactly
      Should -Invoke Start-WrapperScheduledTask -Times 1 -Exactly
      Should -Invoke Wait-ForServiceControlResult -Times 1 -Exactly
    }

    It 'dispatches start control tasks through start recovery' {
      Mock Read-ServiceControlRequest {
        @{
          requestId   = 'req-start'
          action      = 'start'
          origin      = 'interactive'
          requester   = 'CONTOSO\admin'
          processId   = 100
          requestedAt = '2026-03-22T10:00:00.0000000+08:00'
        }
      }
      Mock Write-ServiceControlState { 'state.json' }
      Mock Write-ServiceControlAudit {}
      Mock Write-ServiceControlResult { 'result.json' }
      Mock Start-ManagedServiceWithRecovery {
        @{
          message = "Service 'OpenClawService' is running."
        }
      }
      Mock Stop-ManagedServiceWithRecovery {}
      Mock Restart-ManagedServiceWithRecovery {}

      $result = Invoke-ServiceControlTaskAction -Config $script:testConfig -Action 'start'

      $result.success | Should -BeTrue
      $result.action | Should -Be 'start'
      $result.message | Should -Be "Service 'OpenClawService' is running."
      Should -Invoke Start-ManagedServiceWithRecovery -Times 1 -Exactly
      Should -Invoke Stop-ManagedServiceWithRecovery -Times 0 -Exactly
      Should -Invoke Restart-ManagedServiceWithRecovery -Times 0 -Exactly
    }

    It 'dispatches stop control tasks through stop recovery' {
      Mock Read-ServiceControlRequest {
        @{
          requestId   = 'req-stop'
          action      = 'stop'
          origin      = 'interactive'
          requester   = 'CONTOSO\admin'
          processId   = 101
          requestedAt = '2026-03-22T10:00:00.0000000+08:00'
        }
      }
      Mock Write-ServiceControlState { 'state.json' }
      Mock Write-ServiceControlAudit {}
      Mock Write-ServiceControlResult { 'result.json' }
      Mock Stop-ManagedServiceWithRecovery {
        @{
          message = "Service 'OpenClawService' is stopped."
        }
      }
      Mock Start-ManagedServiceWithRecovery {}
      Mock Restart-ManagedServiceWithRecovery {}

      $result = Invoke-ServiceControlTaskAction -Config $script:testConfig -Action 'stop'

      $result.success | Should -BeTrue
      $result.action | Should -Be 'stop'
      Should -Invoke Stop-ManagedServiceWithRecovery -Times 1 -Exactly
      Should -Invoke Start-ManagedServiceWithRecovery -Times 0 -Exactly
      Should -Invoke Restart-ManagedServiceWithRecovery -Times 0 -Exactly
    }

    It 'dispatches restart control tasks through restart recovery' {
      Mock Read-ServiceControlRequest {
        @{
          requestId   = 'req-restart'
          action      = 'restart'
          origin      = 'interactive'
          requester   = 'CONTOSO\admin'
          processId   = 102
          requestedAt = '2026-03-22T10:00:00.0000000+08:00'
        }
      }
      Mock Write-ServiceControlState { 'state.json' }
      Mock Write-ServiceControlAudit {}
      Mock Write-ServiceControlResult { 'result.json' }
      Mock Restart-ManagedServiceWithRecovery {
        @{
          message = "Service 'OpenClawService' restarted successfully."
        }
      }
      Mock Start-ManagedServiceWithRecovery {}
      Mock Stop-ManagedServiceWithRecovery {}

      $result = Invoke-ServiceControlTaskAction -Config $script:testConfig -Action 'restart'

      $result.success | Should -BeTrue
      $result.action | Should -Be 'restart'
      Should -Invoke Restart-ManagedServiceWithRecovery -Times 1 -Exactly
      Should -Invoke Start-ManagedServiceWithRecovery -Times 0 -Exactly
      Should -Invoke Stop-ManagedServiceWithRecovery -Times 0 -Exactly
    }
  }
}
