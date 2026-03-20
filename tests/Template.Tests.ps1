Describe 'Render-WinSWServiceXml' {
  BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  }

  It 'renders a WinSW service definition with start and stop scripts' {
    $identity = Get-ServiceIdentityContext -Mode 'currentUser'
    $config = Get-ServiceConfig -ConfigPath (Join-Path $repoRoot 'service-config.json') -IdentityContext $identity
    $xml = Render-WinSWServiceXml -Config $config

    Assert-MatchPattern $xml '<stopexecutable>powershell.exe</stopexecutable>'
    Assert-MatchPattern $xml 'run-gateway\.ps1'
    Assert-MatchPattern $xml 'stop-gateway\.ps1'
    Assert-MatchPattern $xml '<onfailure action="restart" delay="10 sec"></onfailure>'
    Assert-MatchPattern $xml '<log mode="rotate"></log>'
  }

  It 'renders a service account block when a credential is provided' {
    $identity = Get-ServiceIdentityContext -Mode 'currentUser'
    $config = Get-ServiceConfig -ConfigPath (Join-Path $repoRoot 'service-config.json') -IdentityContext $identity
    $secure = ConvertTo-SecureString 'example-password' -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential('example-user', $secure)
    $xml = Render-WinSWServiceXml -Config $config -ServiceAccountMode 'credential' -Credential $credential

    Assert-MatchPattern $xml '<serviceaccount>'
    Assert-MatchPattern $xml '<user>example-user</user>'
    Assert-MatchPattern $xml '<allowservicelogon>true</allowservicelogon>'
  }
}
