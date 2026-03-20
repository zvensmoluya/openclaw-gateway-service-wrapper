Describe 'Get-ServiceArtifactLayout' {
  BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot 'src\OpenClawGatewayServiceWrapper.psm1') -Force -DisableNameChecking
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
  }

  It 'uses the generated tools directory for WinSW artifacts' {
    $identity = Get-ServiceIdentityContext -Mode 'currentUser'
    $config = Get-ServiceConfig -ConfigPath (Join-Path $repoRoot 'service-config.json') -IdentityContext $identity
    $layout = Get-ServiceArtifactLayout -Config $config

    Assert-MatchPattern $layout.generatedExecutablePath 'tools\\winsw\\OpenClawService\\OpenClawService\.exe$'
    Assert-MatchPattern $layout.generatedXmlPath 'tools\\winsw\\OpenClawService\\OpenClawService\.xml$'
    Assert-MatchPattern $layout.stateFilePath '\.runtime\\OpenClawService\.state\.json$'
  }

  It 'switches to credential mode when install-time credentials are provided' {
    $identity = Get-ServiceIdentityContext -Mode 'currentUser'
    $config = Get-ServiceConfig -ConfigPath (Join-Path $repoRoot 'service-config.json') -IdentityContext $identity
    $secure = ConvertTo-SecureString 'example-password' -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential('example-user', $secure)

    Assert-Equal (Get-EffectiveServiceAccountMode -Config $config -Credential $credential) 'credential'
  }
}
