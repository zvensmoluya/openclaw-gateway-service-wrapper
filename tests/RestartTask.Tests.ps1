Describe 'Service restart task helpers' {
  BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $module = Import-Module (Join-Path $repoRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking -PassThru
    $script:moduleName = $module.Name
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  }

  It 'builds a deterministic restart task definition from the service name' {
    $identity = Get-ServiceIdentityContext -Mode 'currentUser'
    $config = Get-ServiceConfig -ConfigPath (Join-Path $repoRoot 'service-config.json') -IdentityContext $identity

    $task = Get-ServiceRestartTaskInfo -Config $config

    Assert-Equal $task.taskPath '\OpenClaw\'
    Assert-Equal $task.taskName 'OpenClawService-Restart'
    Assert-Equal $task.fullTaskName '\OpenClaw\OpenClawService-Restart'
    Assert-MatchPattern $task.scriptPath 'restart-service-task\.ps1$'
    Assert-MatchPattern $task.logPath 'logs\\OpenClawService\.restart-task\.log$'
    Assert-MatchPattern $task.actionArguments '-File ".*restart-service-task\.ps1" -ConfigPath ".*service-config\.json"'
  }

  It 'reports a matching registered restart task action' {
    $identity = Get-ServiceIdentityContext -Mode 'currentUser'
    $config = Get-ServiceConfig -ConfigPath (Join-Path $repoRoot 'service-config.json') -IdentityContext $identity
    $taskInfo = Get-ServiceRestartTaskInfo -Config $config

    Mock Get-ScheduledTask -ModuleName $script:moduleName {
      @{
        State   = 'Ready'
        Actions = @(
          @{
            Execute   = $taskInfo.actionExecutable
            Arguments = $taskInfo.actionArguments
          }
        )
      }
    }

    $status = Get-ServiceRestartTaskStatus -Config $config

    $status.exists | Should -BeTrue
    $status.matches | Should -BeTrue
    $status.state | Should -Be 'Ready'
    $status.actualAction.execute | Should -Be $taskInfo.actionExecutable
    $status.actualAction.arguments | Should -Be $taskInfo.actionArguments
  }

  It 'reports a mismatched registered restart task action' {
    $identity = Get-ServiceIdentityContext -Mode 'currentUser'
    $config = Get-ServiceConfig -ConfigPath (Join-Path $repoRoot 'service-config.json') -IdentityContext $identity

    Mock Get-ScheduledTask -ModuleName $script:moduleName {
      @{
        State   = 'Ready'
        Actions = @(
          @{
            Execute   = 'powershell.exe'
            Arguments = '-NoProfile -ExecutionPolicy Bypass -File "C:\wrong.ps1"'
          }
        )
      }
    }

    $status = Get-ServiceRestartTaskStatus -Config $config

    $status.exists | Should -BeTrue
    $status.matches | Should -BeFalse
    $status.actualAction.arguments | Should -Be '-NoProfile -ExecutionPolicy Bypass -File "C:\wrong.ps1"'
  }

  It 'builds deterministic SYSTEM control task definitions for start and stop' {
    $identity = Get-ServiceIdentityContext -Mode 'currentUser'
    $config = Get-ServiceConfig -ConfigPath (Join-Path $repoRoot 'service-config.json') -IdentityContext $identity

    $startTask = Get-ServiceControlTaskInfo -Config $config -Action 'start'
    $stopTask = Get-ServiceControlTaskInfo -Config $config -Action 'stop'

    Assert-Equal $startTask.fullTaskName '\OpenClaw\OpenClawService-Start'
    Assert-Equal $stopTask.fullTaskName '\OpenClaw\OpenClawService-Stop'
    Assert-MatchPattern $startTask.scriptPath 'control-service-task\.ps1$'
    Assert-MatchPattern $stopTask.scriptPath 'control-service-task\.ps1$'
    Assert-MatchPattern $startTask.actionArguments '-Action "start"'
    Assert-MatchPattern $stopTask.actionArguments '-Action "stop"'
  }

  It 'reports matching registered control task actions' {
    $identity = Get-ServiceIdentityContext -Mode 'currentUser'
    $config = Get-ServiceConfig -ConfigPath (Join-Path $repoRoot 'service-config.json') -IdentityContext $identity
    $taskInfo = Get-ServiceControlTaskInfo -Config $config -Action 'start'

    Mock Get-ScheduledTask -ModuleName $script:moduleName {
      @{
        State   = 'Ready'
        Actions = @(
          @{
            Execute   = $taskInfo.actionExecutable
            Arguments = $taskInfo.actionArguments
          }
        )
      }
    }

    $status = Get-ServiceControlTaskStatus -Config $config -Action 'start'

    $status.exists | Should -BeTrue
    $status.matches | Should -BeTrue
    $status.fullTaskName | Should -Be '\OpenClaw\OpenClawService-Start'
    $status.requestPath | Should -Match 'control-start\.request\.json$'
    $status.resultPath | Should -Match 'control-start\.result\.json$'
  }
}
