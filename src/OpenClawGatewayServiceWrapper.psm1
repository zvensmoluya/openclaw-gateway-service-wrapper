Set-StrictMode -Version Latest

$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function Get-WrapperRoot {
  return $script:RepoRoot
}

function ConvertTo-Hashtable {
  param(
    [AllowNull()]
    $InputObject
  )

  if ($null -eq $InputObject) {
    return $null
  }

  if ($InputObject -is [System.Collections.IDictionary]) {
    $table = @{}
    foreach ($key in $InputObject.Keys) {
      $table[$key] = ConvertTo-Hashtable -InputObject $InputObject[$key]
    }

    return $table
  }

  if ($InputObject -is [pscustomobject]) {
    $table = @{}
    foreach ($property in $InputObject.PSObject.Properties) {
      $table[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
    }

    return $table
  }

  if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
    $items = @()
    foreach ($item in $InputObject) {
      $items += ,(ConvertTo-Hashtable -InputObject $item)
    }

    return $items
  }

  return $InputObject
}

function Copy-Hashtable {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$InputObject
  )

  $copy = @{}
  foreach ($key in $InputObject.Keys) {
    $value = $InputObject[$key]
    if ($value -is [hashtable]) {
      $copy[$key] = Copy-Hashtable -InputObject $value
      continue
    }

    if (($value -is [System.Collections.IEnumerable]) -and -not ($value -is [string])) {
      $items = @()
      foreach ($item in $value) {
        if ($item -is [hashtable]) {
          $items += ,(Copy-Hashtable -InputObject $item)
        } else {
          $items += ,$item
        }
      }

      $copy[$key] = $items
      continue
    }

    $copy[$key] = $value
  }

  return $copy
}

function Merge-Hashtable {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Base,
    [Parameter(Mandatory = $true)]
    [hashtable]$Overlay
  )

  $merged = Copy-Hashtable -InputObject $Base
  foreach ($key in $Overlay.Keys) {
    if ($merged.ContainsKey($key) -and $merged[$key] -is [hashtable] -and $Overlay[$key] -is [hashtable]) {
      $merged[$key] = Merge-Hashtable -Base $merged[$key] -Overlay $Overlay[$key]
      continue
    }

    $merged[$key] = $Overlay[$key]
  }

  return $merged
}

function Get-DefaultTrayConfig {
  return @{
    title         = $null
    notifications = 'all'
    refresh       = @{
      fastSeconds = 30
      deepSeconds = 180
      menuSeconds = 10
    }
    icons         = @{
      default      = $null
      healthy      = $null
      degraded     = $null
      unhealthy    = $null
      stopped      = $null
      error        = $null
      loading      = $null
      notInstalled = $null
    }
  }
}

function Get-DefaultServiceConfig {
  return @{
    serviceName        = 'OpenClawService'
    displayName        = 'OpenClaw Service'
    description        = 'Runs the OpenClaw gateway as a Windows Service.'
    bind               = 'loopback'
    port               = 18789
    stateDir           = '%USERPROFILE%\.openclaw'
    configPath         = '%USERPROFILE%\.openclaw\openclaw.json'
    tempDir            = '%LOCALAPPDATA%\Temp'
    httpProxy          = $null
    httpsProxy         = $null
    allProxy           = $null
    noProxy            = $null
    serviceAccountMode = 'credential'
    openclawCommand    = ''
    allowForceBind     = $false
    winswVersion       = '2.12.0'
    winswDownloadUrl   = 'https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe'
    winswChecksum      = '05B82D46AD331CC16BDC00DE5C6332C1EF818DF8CEEFCD49C726553209B3A0DA'
    logPolicy          = @{
      mode = 'rotate'
    }
    startMode          = 'Automatic'
    delayedAutoStart   = $true
    stopTimeoutSeconds = 20
    failureActions     = @('10 sec', '20 sec', '30 sec')
    resetFailure       = '1 day'
    winswHome          = 'tools\winsw'
    runtimeStateDir    = '.runtime'
    logsDir            = 'logs'
    tray               = (Get-DefaultTrayConfig)
  }
}

function Get-WrapperProxyVariableDefinitions {
  return @(
    @{
      configKey = 'httpProxy'
      variables = @('HTTP_PROXY', 'http_proxy')
      redactUrl = $true
    },
    @{
      configKey = 'httpsProxy'
      variables = @('HTTPS_PROXY', 'https_proxy')
      redactUrl = $true
    },
    @{
      configKey = 'allProxy'
      variables = @('ALL_PROXY', 'all_proxy')
      redactUrl = $true
    },
    @{
      configKey = 'noProxy'
      variables = @('NO_PROXY', 'no_proxy')
      redactUrl = $false
    }
  )
}

function Normalize-OptionalWrapperConfigString {
  param(
    [AllowNull()]
    $Value
  )

  if ($null -eq $Value) {
    return $null
  }

  return $Value.ToString().Trim()
}

function Get-EnvironmentVariableEntry {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Names,
    [System.Collections.IDictionary]$Environment = [System.Environment]::GetEnvironmentVariables()
  )

  foreach ($name in $Names) {
    foreach ($key in $Environment.Keys) {
      if (-not [string]::Equals($key.ToString(), $name, [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
      }

      $value = Normalize-OptionalWrapperConfigString -Value $Environment[$key]
      if ($null -eq $value) {
        continue
      }

      return @{
        found = $true
        name  = $key.ToString()
        value = $value
      }
    }
  }

  return @{
    found = $false
    name  = $null
    value = $null
  }
}

function Redact-ProxyUrl {
  param(
    [AllowNull()]
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $null
  }

  try {
    $uri = [System.Uri]$Value
    if ([string]::IsNullOrWhiteSpace($uri.Scheme) -or [string]::IsNullOrWhiteSpace($uri.Host)) {
      return '<invalid>'
    }

    $portSuffix = if ($uri.IsDefaultPort -or $uri.Port -lt 1) { '' } else { ":$($uri.Port)" }
    return "$($uri.Scheme)://$($uri.Host)$portSuffix"
  } catch {
    return '<invalid>'
  }
}

function Resolve-WrapperProxyEnvironmentPlan {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [System.Collections.IDictionary]$Environment = [System.Environment]::GetEnvironmentVariables()
  )

  $presence = if ($Config.ContainsKey('proxyConfigPresence') -and ($Config.proxyConfigPresence -is [hashtable])) {
    $Config.proxyConfigPresence
  } else {
    @{}
  }

  $plan = @{}
  foreach ($definition in Get-WrapperProxyVariableDefinitions) {
    $ambient = Get-EnvironmentVariableEntry -Names $definition.variables -Environment $Environment
    $configured = $presence.ContainsKey($definition.configKey) -and [bool]$presence[$definition.configKey]
    $configuredValue = Normalize-OptionalWrapperConfigString -Value $Config[$definition.configKey]

    $source = 'unset'
    $effectiveValue = $null
    $clearRequested = $false

    if ($configured) {
      if ($null -ne $configuredValue) {
        if ($configuredValue.Length -eq 0) {
          $source = 'wrapperConfig'
          $clearRequested = $true
        } else {
          $source = 'wrapperConfig'
          $effectiveValue = $configuredValue
        }
      } elseif ($ambient.found) {
        $source = 'ambientEnvironment'
        $effectiveValue = $ambient.value
      }
    } elseif ($ambient.found) {
      $source = 'ambientEnvironment'
      $effectiveValue = $ambient.value
    }

    $plan[$definition.configKey] = @{
      source            = $source
      value             = $effectiveValue
      clearRequested    = $clearRequested
      configured        = $configured
      matchedAmbientKey = $ambient.name
      variables         = $definition.variables
      redactUrl         = [bool]$definition.redactUrl
    }
  }

  return $plan
}

function Set-WrapperProxyEnvironment {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [System.Collections.IDictionary]$Environment = [System.Environment]::GetEnvironmentVariables()
  )

  $plan = Resolve-WrapperProxyEnvironmentPlan -Config $Config -Environment $Environment
  foreach ($definition in Get-WrapperProxyVariableDefinitions) {
    $entry = $plan[$definition.configKey]
    if ($entry.source -ne 'wrapperConfig') {
      continue
    }

    foreach ($variableName in $definition.variables) {
      if ($entry.clearRequested) {
        [System.Environment]::SetEnvironmentVariable($variableName, $null, 'Process')
      } else {
        [System.Environment]::SetEnvironmentVariable($variableName, $entry.value, 'Process')
      }
    }
  }

  return $plan
}

function Get-WrapperProxyStatusReport {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [System.Collections.IDictionary]$Environment = [System.Environment]::GetEnvironmentVariables()
  )

  $plan = Resolve-WrapperProxyEnvironmentPlan -Config $Config -Environment $Environment
  $report = @{}
  foreach ($definition in Get-WrapperProxyVariableDefinitions) {
    $entry = $plan[$definition.configKey]
    $report[$definition.configKey] = @{
      source         = $entry.source
      value          = if ($definition.redactUrl) { Redact-ProxyUrl -Value $entry.value } else { $entry.value }
      clearRequested = $entry.clearRequested
    }
  }

  return $report
}

function New-EmptyWrapperProxyStatusReport {
  $report = @{}
  foreach ($definition in Get-WrapperProxyVariableDefinitions) {
    $report[$definition.configKey] = @{
      source         = 'unset'
      value          = $null
      clearRequested = $false
    }
  }

  return $report
}

function Resolve-AbsolutePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [string]$BasePath = $script:RepoRoot
  )

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Resolve-OptionalAbsolutePath {
  param(
    [AllowNull()]
    [string]$Path,
    [string]$BasePath = $script:RepoRoot
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $null
  }

  return (Resolve-AbsolutePath -Path $Path -BasePath $BasePath)
}

function Get-DefaultWrapperConfigPath {
  return (Join-Path $script:RepoRoot 'service-config.json')
}

function Get-RememberedConfigMetadataPath {
  $runtimeRoot = Resolve-AbsolutePath -Path ((Get-DefaultServiceConfig).runtimeStateDir) -BasePath $script:RepoRoot
  return (Join-Path $runtimeRoot 'active-config.json')
}

function Get-WindowsPowerShellExecutablePath {
  [CmdletBinding()]
  param()

  $command = Get-Command -Name 'powershell.exe' -CommandType Application -ErrorAction SilentlyContinue
  if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
    return $command.Source
  }

  return (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
}

function Get-WindowsScriptHostExecutablePath {
  [CmdletBinding()]
  param()

  return (Join-Path $env:WINDIR 'System32\wscript.exe')
}

function Get-CurrentUserStartupDirectory {
  [CmdletBinding()]
  param()

  $startupDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
  if ([string]::IsNullOrWhiteSpace($startupDirectory)) {
    throw 'Could not resolve the current user Startup folder.'
  }

  return $startupDirectory
}

function Get-TrayShortcutPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [string]$StartupDirectory = (Get-CurrentUserStartupDirectory)
  )

  return (Join-Path $StartupDirectory "$($Config.serviceName) Tray Controller.lnk")
}

function Get-TrayControllerLaunchArguments {
  [CmdletBinding()]
  param(
    [string]$ScriptPath = (Join-Path $script:RepoRoot 'tray-controller.ps1'),
    [string]$ConfigPath
  )

  $resolvedScriptPath = Resolve-AbsolutePath -Path $ScriptPath -BasePath $script:RepoRoot
  $arguments = @(
    '-NoProfile',
    '-WindowStyle',
    'Hidden',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    ('"{0}"' -f $resolvedScriptPath)
  )

  if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $resolvedConfigPath = Resolve-AbsolutePath -Path $ConfigPath -BasePath $script:RepoRoot
    $arguments += @(
      '-ConfigPath',
      ('"{0}"' -f $resolvedConfigPath)
    )
  }

  return ($arguments -join ' ')
}

function Get-TrayControllerLauncherPath {
  [CmdletBinding()]
  param(
    [string]$LauncherPath = (Join-Path $script:RepoRoot 'tray-controller-launcher.vbs')
  )

  return (Resolve-AbsolutePath -Path $LauncherPath -BasePath $script:RepoRoot)
}

function Get-TrayControllerLauncherArguments {
  [CmdletBinding()]
  param(
    [string]$LauncherPath = (Join-Path $script:RepoRoot 'tray-controller-launcher.vbs'),
    [string]$ConfigPath
  )

  $resolvedLauncherPath = Get-TrayControllerLauncherPath -LauncherPath $LauncherPath
  $arguments = @(
    ('"{0}"' -f $resolvedLauncherPath)
  )

  if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $resolvedConfigPath = Resolve-AbsolutePath -Path $ConfigPath -BasePath $script:RepoRoot
    $arguments += @(
      ('"{0}"' -f $resolvedConfigPath)
    )
  }

  return ($arguments -join ' ')
}

function Get-UserNameLeaf {
  param(
    [Parameter(Mandatory = $true)]
    [string]$UserName
  )

  if ($UserName.Contains('\')) {
    return ($UserName.Split('\')[-1])
  }

  if ($UserName.Contains('@')) {
    return ($UserName.Split('@')[0])
  }

  return $UserName
}

function Get-ProfileRootForUserName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$UserName
  )

  try {
    $sid = (New-Object System.Security.Principal.NTAccount($UserName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
    $profileKey = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
    $profilePath = (Get-ItemProperty -Path $profileKey -Name ProfileImagePath -ErrorAction Stop).ProfileImagePath
    if (-not [string]::IsNullOrWhiteSpace($profilePath)) {
      return [Environment]::ExpandEnvironmentVariables($profilePath)
    }
  } catch {
  }

  $userLeaf = Get-UserNameLeaf -UserName $UserName
  return Join-Path 'C:\Users' $userLeaf
}

function Get-CurrentWindowsIdentityName {
  return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

function Convert-ToComparableServiceAccountName {
  param(
    [AllowNull()]
    [string]$AccountName
  )

  if ([string]::IsNullOrWhiteSpace($AccountName)) {
    return $null
  }

  $trimmed = $AccountName.Trim()
  switch -Regex ($trimmed) {
    '^(?i:localsystem|nt authority\\system)$' {
      return 'NT AUTHORITY\SYSTEM'
    }
    '^(?i:localservice|nt authority\\local ?service)$' {
      return 'NT AUTHORITY\LOCAL SERVICE'
    }
    '^(?i:networkservice|nt authority\\network ?service)$' {
      return 'NT AUTHORITY\NETWORK SERVICE'
    }
    default {
      if ($trimmed.StartsWith('.\')) {
        return "$env:COMPUTERNAME$($trimmed.Substring(1))"
      }

      return $trimmed
    }
  }
}

function Resolve-ServiceAccountSid {
  param(
    [AllowNull()]
    [string]$AccountName
  )

  $comparableAccountName = Convert-ToComparableServiceAccountName -AccountName $AccountName
  if ([string]::IsNullOrWhiteSpace($comparableAccountName)) {
    return $null
  }

  try {
    return (New-Object System.Security.Principal.NTAccount($comparableAccountName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
  } catch {
    return $null
  }
}

function Test-IsBuiltInServiceAccount {
  param(
    [AllowNull()]
    [string]$AccountName
  )

  $comparableAccountName = Convert-ToComparableServiceAccountName -AccountName $AccountName
  return $comparableAccountName -in @(
    'NT AUTHORITY\SYSTEM',
    'NT AUTHORITY\LOCAL SERVICE',
    'NT AUTHORITY\NETWORK SERVICE'
  )
}

function Test-ServiceAccountMatch {
  param(
    [AllowNull()]
    [string]$ExpectedAccountName,
    [AllowNull()]
    [string]$ActualAccountName
  )

  if ([string]::IsNullOrWhiteSpace($ExpectedAccountName) -or [string]::IsNullOrWhiteSpace($ActualAccountName)) {
    return $false
  }

  $expectedSid = Resolve-ServiceAccountSid -AccountName $ExpectedAccountName
  $actualSid = Resolve-ServiceAccountSid -AccountName $ActualAccountName
  if (($null -ne $expectedSid) -and ($null -ne $actualSid)) {
    return $expectedSid -eq $actualSid
  }

  $expectedComparable = Convert-ToComparableServiceAccountName -AccountName $ExpectedAccountName
  $actualComparable = Convert-ToComparableServiceAccountName -AccountName $ActualAccountName
  return [string]::Equals($expectedComparable, $actualComparable, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ExpectedServiceStartName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$UserName
  )

  if (Test-IsBuiltInServiceAccount -AccountName $UserName) {
    switch (Convert-ToComparableServiceAccountName -AccountName $UserName) {
      'NT AUTHORITY\SYSTEM' {
        return 'LocalSystem'
      }
      'NT AUTHORITY\LOCAL SERVICE' {
        return 'LocalService'
      }
      'NT AUTHORITY\NETWORK SERVICE' {
        return 'NetworkService'
      }
    }
  }

  if ($UserName.Contains('\')) {
    return $UserName
  }

  if ($UserName.Contains('@')) {
    return $UserName
  }

  return ".\$UserName"
}

function Get-ServiceAccountIdentityContext {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$AccountName
  )

  $comparableAccountName = Convert-ToComparableServiceAccountName -AccountName $AccountName
  switch ($comparableAccountName) {
    'NT AUTHORITY\SYSTEM' {
      $profileRoot = Join-Path $env:WINDIR 'System32\Config\SystemProfile'
      $localAppData = Join-Path $profileRoot 'AppData\Local'
      $tempDir = Join-Path $localAppData 'Temp'

      return @{
        mode         = 'serviceAccount'
        userName     = 'LocalSystem'
        profileRoot  = $profileRoot
        home         = $profileRoot
        localAppData = $localAppData
        tempDir      = $tempDir
      }
    }
    'NT AUTHORITY\LOCAL SERVICE' {
      $profileRoot = Join-Path $env:WINDIR 'ServiceProfiles\LocalService'
      $localAppData = Join-Path $profileRoot 'AppData\Local'
      $tempDir = Join-Path $localAppData 'Temp'

      return @{
        mode         = 'serviceAccount'
        userName     = 'LocalService'
        profileRoot  = $profileRoot
        home         = $profileRoot
        localAppData = $localAppData
        tempDir      = $tempDir
      }
    }
    'NT AUTHORITY\NETWORK SERVICE' {
      $profileRoot = Join-Path $env:WINDIR 'ServiceProfiles\NetworkService'
      $localAppData = Join-Path $profileRoot 'AppData\Local'
      $tempDir = Join-Path $localAppData 'Temp'

      return @{
        mode         = 'serviceAccount'
        userName     = 'NetworkService'
        profileRoot  = $profileRoot
        home         = $profileRoot
        localAppData = $localAppData
        tempDir      = $tempDir
      }
    }
    default {
      $profileRoot = Get-ProfileRootForUserName -UserName $comparableAccountName
      $localAppData = Join-Path $profileRoot 'AppData\Local'
      $tempDir = Join-Path $localAppData 'Temp'

      return @{
        mode         = 'serviceAccount'
        userName     = $comparableAccountName
        profileRoot  = $profileRoot
        home         = $profileRoot
        localAppData = $localAppData
        tempDir      = $tempDir
      }
    }
  }
}

function Get-ServiceIdentityContext {
  [CmdletBinding()]
  param(
    [ValidateSet('currentUser', 'credential')]
    [string]$Mode = 'currentUser',
    [pscredential]$Credential
  )

  switch ($Mode) {
    'currentUser' {
      $profileRoot = $env:USERPROFILE
      if ([string]::IsNullOrWhiteSpace($profileRoot)) {
        throw 'USERPROFILE is not available in the current session.'
      }

      $localAppData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Join-Path $profileRoot 'AppData\Local'
      } else {
        $env:LOCALAPPDATA
      }

      $tempDir = if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
        Join-Path $localAppData 'Temp'
      } else {
        $env:TEMP
      }

      return @{
        mode         = 'currentUser'
        userName     = [Environment]::UserName
        profileRoot  = $profileRoot
        home         = $profileRoot
        localAppData = $localAppData
        tempDir      = $tempDir
      }
    }
    'credential' {
      if ($null -eq $Credential) {
        throw 'A PSCredential is required when serviceAccountMode is credential.'
      }

      $profileRoot = Get-ProfileRootForUserName -UserName $Credential.UserName
      $localAppData = Join-Path $profileRoot 'AppData\Local'
      $tempDir = Join-Path $localAppData 'Temp'

      return @{
        mode         = 'credential'
        userName     = $Credential.UserName
        profileRoot  = $profileRoot
        home         = $profileRoot
        localAppData = $localAppData
        tempDir      = $tempDir
      }
    }
  }
}

function Expand-ConfigValue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value,
    [Parameter(Mandatory = $true)]
    [hashtable]$IdentityContext
  )

  $expanded = $Value
  $replacements = [ordered]@{
    '%USERPROFILE%'  = $IdentityContext.profileRoot
    '%HOME%'         = $IdentityContext.home
    '%LOCALAPPDATA%' = $IdentityContext.localAppData
    '%TEMP%'         = $IdentityContext.tempDir
    '%TMP%'          = $IdentityContext.tempDir
    '%REPO_ROOT%'    = $script:RepoRoot
  }

  foreach ($entry in $replacements.GetEnumerator()) {
    $expanded = $expanded.Replace($entry.Key, $entry.Value)
  }

  return $expanded
}

function Assert-ServiceConfig {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  if ([string]::IsNullOrWhiteSpace($Config.serviceName)) {
    throw 'serviceName must not be empty.'
  }

  if ($Config.serviceName -notmatch '^[A-Za-z0-9_.-]+$') {
    throw "serviceName '$($Config.serviceName)' contains unsupported characters."
  }

  if ([string]::IsNullOrWhiteSpace($Config.displayName)) {
    throw 'displayName must not be empty.'
  }

  if ($Config.port -lt 1 -or $Config.port -gt 65535) {
    throw "port '$($Config.port)' is outside the valid range 1-65535."
  }

  if ([string]::IsNullOrWhiteSpace($Config.bind)) {
    throw 'bind must not be empty.'
  }

  $normalizedMode = $Config.serviceAccountMode.ToString().Trim()
  if ($normalizedMode -notin @('currentUser', 'credential', 'localSystem')) {
    throw "serviceAccountMode '$normalizedMode' is not supported. Use currentUser, credential, or localSystem."
  }

  if ([string]::IsNullOrWhiteSpace($Config.winswVersion)) {
    throw 'winswVersion must not be empty.'
  }

  if ([string]::IsNullOrWhiteSpace($Config.winswDownloadUrl)) {
    throw 'winswDownloadUrl must not be empty.'
  }

  if ([string]::IsNullOrWhiteSpace($Config.winswChecksum) -or $Config.winswChecksum -notmatch '^[A-Fa-f0-9]{64}$') {
    throw 'winswChecksum must be a 64-character SHA256 value.'
  }

  if (-not ($Config.logPolicy -is [hashtable])) {
    throw 'logPolicy must be an object.'
  }

  if ([string]::IsNullOrWhiteSpace($Config.logPolicy.mode)) {
    throw 'logPolicy.mode must not be empty.'
  }

  foreach ($proxyField in @('httpProxy', 'httpsProxy', 'allProxy', 'noProxy')) {
    if (($null -ne $Config[$proxyField]) -and -not ($Config[$proxyField] -is [string])) {
      throw "$proxyField must be a string when provided."
    }
  }

  if (-not ($Config.tray -is [hashtable])) {
    throw 'tray must be an object.'
  }

  if ([string]::IsNullOrWhiteSpace($Config.tray.title)) {
    throw 'tray.title must not be empty.'
  }

  if ($Config.tray.notifications -notin @('all', 'errorsOnly', 'off')) {
    throw "tray.notifications '$($Config.tray.notifications)' is not supported. Use all, errorsOnly, or off."
  }

  if (-not ($Config.tray.refresh -is [hashtable])) {
    throw 'tray.refresh must be an object.'
  }

  if ($Config.tray.refresh.fastSeconds -lt 15 -or $Config.tray.refresh.fastSeconds -gt 300) {
    throw "tray.refresh.fastSeconds '$($Config.tray.refresh.fastSeconds)' is outside the valid range 15-300."
  }

  if ($Config.tray.refresh.deepSeconds -lt 60 -or $Config.tray.refresh.deepSeconds -gt 900) {
    throw "tray.refresh.deepSeconds '$($Config.tray.refresh.deepSeconds)' is outside the valid range 60-900."
  }

  if ($Config.tray.refresh.menuSeconds -lt 5 -or $Config.tray.refresh.menuSeconds -gt 60) {
    throw "tray.refresh.menuSeconds '$($Config.tray.refresh.menuSeconds)' is outside the valid range 5-60."
  }

  if (-not ($Config.tray.icons -is [hashtable])) {
    throw 'tray.icons must be an object.'
  }

  foreach ($iconField in @('default', 'healthy', 'degraded', 'unhealthy', 'stopped', 'error', 'loading', 'notInstalled')) {
    if (($null -ne $Config.tray.icons[$iconField]) -and -not ($Config.tray.icons[$iconField] -is [string])) {
      throw "tray.icons.$iconField must be a string when provided."
    }
  }
}

function Convert-ToIntConfigValue {
  param(
    [AllowNull()]
    $Value,
    [Parameter(Mandatory = $true)]
    [int]$Fallback
  )

  if ($null -eq $Value) {
    return $Fallback
  }

  try {
    return [int]$Value
  } catch {
    throw "Expected an integer-compatible value but got '$Value'."
  }
}

function Normalize-WrapperTrayConfig {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  if ($Config.ContainsKey('tray') -and $null -ne $Config.tray -and -not ($Config.tray -is [hashtable])) {
    throw 'tray must be an object.'
  }

  $trayConfig = if ($Config.ContainsKey('tray') -and ($Config.tray -is [hashtable])) {
    $Config.tray
  } else {
    @{}
  }

  if ($trayConfig.ContainsKey('refresh') -and $null -ne $trayConfig.refresh -and -not ($trayConfig.refresh -is [hashtable])) {
    throw 'tray.refresh must be an object.'
  }

  if ($trayConfig.ContainsKey('icons') -and $null -ne $trayConfig.icons -and -not ($trayConfig.icons -is [hashtable])) {
    throw 'tray.icons must be an object.'
  }

  $mergedTray = Merge-Hashtable -Base (Get-DefaultTrayConfig) -Overlay $trayConfig
  $mergedTray.title = Normalize-OptionalWrapperConfigString -Value $mergedTray.title
  if ([string]::IsNullOrWhiteSpace($mergedTray.title)) {
    $mergedTray.title = $Config.displayName
  }

  $mergedTray.notifications = if ($null -eq $mergedTray.notifications) {
    'all'
  } else {
    $mergedTray.notifications.ToString().Trim()
  }

  $mergedTray.refresh.fastSeconds = Convert-ToIntConfigValue -Value $mergedTray.refresh.fastSeconds -Fallback 30
  $mergedTray.refresh.deepSeconds = Convert-ToIntConfigValue -Value $mergedTray.refresh.deepSeconds -Fallback 180
  $mergedTray.refresh.menuSeconds = Convert-ToIntConfigValue -Value $mergedTray.refresh.menuSeconds -Fallback 10

  foreach ($iconField in @('default', 'healthy', 'degraded', 'unhealthy', 'stopped', 'error', 'loading', 'notInstalled')) {
    $normalizedPath = Normalize-OptionalWrapperConfigString -Value $mergedTray.icons[$iconField]
    $mergedTray.icons[$iconField] = Resolve-OptionalAbsolutePath -Path $normalizedPath -BasePath $script:RepoRoot
  }

  return $mergedTray
}

function Get-ServiceConfig {
  [CmdletBinding()]
  param(
    [string]$ConfigPath = (Get-DefaultWrapperConfigPath),
    [hashtable]$IdentityContext = (Get-ServiceIdentityContext -Mode 'currentUser')
  )

  $resolvedConfigPath = Resolve-AbsolutePath -Path $ConfigPath -BasePath $script:RepoRoot
  if (-not (Test-Path -LiteralPath $resolvedConfigPath)) {
    throw "Config file not found: $resolvedConfigPath"
  }

  $rawConfig = ConvertTo-Hashtable -InputObject (Get-Content -LiteralPath $resolvedConfigPath -Raw | ConvertFrom-Json)
  $merged = Merge-Hashtable -Base (Get-DefaultServiceConfig) -Overlay $rawConfig
  $merged.serviceAccountMode = $merged.serviceAccountMode.ToString().Trim()
  $merged.proxyConfigPresence = @{}
  foreach ($definition in Get-WrapperProxyVariableDefinitions) {
    $merged.proxyConfigPresence[$definition.configKey] = $rawConfig.ContainsKey($definition.configKey)
    if (($null -ne $merged[$definition.configKey]) -and -not ($merged[$definition.configKey] -is [string])) {
      throw "$($definition.configKey) must be a string when provided."
    }
    $merged[$definition.configKey] = Normalize-OptionalWrapperConfigString -Value $merged[$definition.configKey]
  }
  $merged.tray = Normalize-WrapperTrayConfig -Config $merged
  Assert-ServiceConfig -Config $merged

  $merged.sourceConfigPath = $resolvedConfigPath
  $merged.stateDir = Resolve-AbsolutePath -Path (Expand-ConfigValue -Value $merged.stateDir -IdentityContext $IdentityContext) -BasePath $script:RepoRoot
  $merged.gatewayConfigPath = Resolve-AbsolutePath -Path (Expand-ConfigValue -Value $merged.configPath -IdentityContext $IdentityContext) -BasePath $script:RepoRoot
  $merged.tempDir = Resolve-AbsolutePath -Path (Expand-ConfigValue -Value $merged.tempDir -IdentityContext $IdentityContext) -BasePath $script:RepoRoot
  $merged.logsDirectory = Resolve-AbsolutePath -Path $merged.logsDir -BasePath $script:RepoRoot
  $merged.runtimeStateDirectory = Resolve-AbsolutePath -Path $merged.runtimeStateDir -BasePath $script:RepoRoot
  $merged.healthUrl = "http://127.0.0.1:$($merged.port)/health"

  return $merged
}

function Resolve-ServiceAccountPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [pscredential]$Credential,
    [string]$CurrentWindowsIdentityName = (Get-CurrentWindowsIdentityName),
    [switch]$PromptForCredential
  )

  $configuredMode = $Config.serviceAccountMode.ToString().Trim()
  $deprecatedAlias = $configuredMode -eq 'currentUser'
  $resolvedCredential = $Credential
  $expectedStartName = $null
  $requiresCredential = $false
  $promptUserName = $null

  switch ($configuredMode) {
    'currentUser' {
      $expectedStartName = $CurrentWindowsIdentityName
      $promptUserName = $CurrentWindowsIdentityName

      if ($null -ne $resolvedCredential) {
        if (-not (Test-ServiceAccountMatch -ExpectedAccountName $CurrentWindowsIdentityName -ActualAccountName $resolvedCredential.UserName)) {
          throw "serviceAccountMode 'currentUser' is deprecated and only supports the current Windows identity '$CurrentWindowsIdentityName'. Pass a matching credential or set serviceAccountMode to 'credential'."
        }
      } elseif ($PromptForCredential) {
        $resolvedCredential = Get-Credential -UserName $CurrentWindowsIdentityName -Message "serviceAccountMode 'currentUser' is deprecated. Enter the password for the current Windows user that should run the OpenClaw service."
        if ($null -eq $resolvedCredential) {
          throw 'A credential is required to install the service for the current Windows user.'
        }

        if (-not (Test-ServiceAccountMatch -ExpectedAccountName $CurrentWindowsIdentityName -ActualAccountName $resolvedCredential.UserName)) {
          throw "serviceAccountMode 'currentUser' is deprecated and only supports the current Windows identity '$CurrentWindowsIdentityName'. The credential prompt username must stay on that account; use serviceAccountMode 'credential' to install under a different user."
        }
      } else {
        $requiresCredential = $true
      }
    }
    'credential' {
      if ($null -eq $resolvedCredential) {
        if ($PromptForCredential) {
          $resolvedCredential = Get-Credential -Message 'Enter the Windows user account that should run the OpenClaw service.'
          if ($null -eq $resolvedCredential) {
            throw 'A PSCredential is required when serviceAccountMode is credential.'
          }
        } else {
          $requiresCredential = $true
        }
      }

      if ($null -ne $resolvedCredential) {
        $expectedStartName = Get-ExpectedServiceStartName -UserName $resolvedCredential.UserName
      }
    }
    'localSystem' {
      if ($null -ne $resolvedCredential) {
        throw "serviceAccountMode 'localSystem' does not accept -Credential. Remove -Credential or use serviceAccountMode 'credential' or 'currentUser'."
      }

      $resolvedCredential = $null
      $expectedStartName = 'LocalSystem'
    }
    default {
      throw "serviceAccountMode '$configuredMode' is not supported. Use credential, currentUser, or localSystem."
    }
  }

  if (($configuredMode -ne 'localSystem') -and ($null -ne $resolvedCredential) -and [string]::IsNullOrEmpty($resolvedCredential.GetNetworkCredential().Password)) {
    throw "Windows services cannot log on with a blank password for account '$($resolvedCredential.UserName)'. Set a password on that account or use serviceAccountMode 'localSystem'."
  }

  $identityContext = if (-not [string]::IsNullOrWhiteSpace($expectedStartName)) {
    Get-ServiceAccountIdentityContext -AccountName $expectedStartName
  } else {
    $null
  }

  return @{
    configuredMode     = $configuredMode
    effectiveMode      = if ($configuredMode -eq 'localSystem') { 'localSystem' } else { 'credential' }
    deprecatedAlias    = $deprecatedAlias
    expectedStartName  = $expectedStartName
    identityContext    = $identityContext
    credential         = $resolvedCredential
    requiresCredential = $requiresCredential
    promptUserName     = $promptUserName
  }
}

function Read-RememberedServiceConfigSelection {
  [CmdletBinding()]
  param()

  $metadataPath = Get-RememberedConfigMetadataPath
  if (-not (Test-Path -LiteralPath $metadataPath)) {
    return $null
  }

  try {
    $record = ConvertTo-Hashtable -InputObject (Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json)
  } catch {
    throw "Remembered config metadata is not valid JSON: $metadataPath. Remove the file or reinstall the service."
  }

  if ($null -eq $record -or [string]::IsNullOrWhiteSpace($record.sourceConfigPath)) {
    throw "Remembered config metadata is missing sourceConfigPath: $metadataPath."
  }

  if ([string]::IsNullOrWhiteSpace($record.serviceName)) {
    throw "Remembered config metadata is missing serviceName: $metadataPath."
  }

  $record.sourceConfigPath = Resolve-AbsolutePath -Path $record.sourceConfigPath -BasePath $script:RepoRoot
  $record.metadataPath = $metadataPath
  return $record
}

function Write-RememberedServiceConfigSelection {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceConfigPath,
    [Parameter(Mandatory = $true)]
    [string]$ServiceName
  )

  $metadataPath = Get-RememberedConfigMetadataPath
  Ensure-Directory -Path (Split-Path -Parent $metadataPath)

  $record = @{
    sourceConfigPath = Resolve-AbsolutePath -Path $SourceConfigPath -BasePath $script:RepoRoot
    serviceName      = $ServiceName
    writtenAt        = (Get-Date).ToString('o')
  }

  Set-Content -LiteralPath $metadataPath -Value ($record | ConvertTo-Json -Depth 10) -Encoding UTF8
  return $metadataPath
}

function Clear-RememberedServiceConfigSelection {
  [CmdletBinding()]
  param()

  $metadataPath = Get-RememberedConfigMetadataPath
  if (Test-Path -LiteralPath $metadataPath) {
    Remove-Item -LiteralPath $metadataPath -Force
    return $true
  }

  return $false
}

function Resolve-ServiceConfigSelection {
  [CmdletBinding()]
  param(
    [string]$ConfigPath,
    [switch]$AllowInvalidRemembered
  )

  if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $remembered = $null
    try {
      $remembered = Read-RememberedServiceConfigSelection
    } catch {
    }

    return @{
      configSource         = 'explicit'
      sourcePath           = Resolve-AbsolutePath -Path $ConfigPath -BasePath $script:RepoRoot
      rememberedPath       = if ($null -ne $remembered) { $remembered.sourceConfigPath } else { $null }
      rememberedServiceName = if ($null -ne $remembered) { $remembered.serviceName } else { $null }
    }
  }

  try {
    $remembered = Read-RememberedServiceConfigSelection
  } catch {
    if ($AllowInvalidRemembered) {
      return @{
        configSource         = 'remembered'
        sourcePath           = $null
        rememberedPath       = $null
        rememberedServiceName = $null
        invalidReason        = $_.Exception.Message
      }
    }

    throw
  }

  if ($null -ne $remembered) {
    if (-not (Test-Path -LiteralPath $remembered.sourceConfigPath)) {
      $message = "Remembered config path not found: $($remembered.sourceConfigPath). Pass -ConfigPath explicitly or reinstall the service."
      if ($AllowInvalidRemembered) {
        return @{
          configSource         = 'remembered'
          sourcePath           = $remembered.sourceConfigPath
          rememberedPath       = $remembered.sourceConfigPath
          rememberedServiceName = $remembered.serviceName
          invalidReason        = $message
        }
      }

      throw $message
    }

    return @{
      configSource         = 'remembered'
      sourcePath           = $remembered.sourceConfigPath
      rememberedPath       = $remembered.sourceConfigPath
      rememberedServiceName = $remembered.serviceName
    }
  }

  return @{
    configSource         = 'repoDefault'
    sourcePath           = Get-DefaultWrapperConfigPath
    rememberedPath       = $null
    rememberedServiceName = $null
  }
}

function Resolve-ServiceConfig {
  [CmdletBinding()]
  param(
    [string]$ConfigPath,
    [hashtable]$IdentityContext = (Get-ServiceIdentityContext -Mode 'currentUser')
  )

  $selection = Resolve-ServiceConfigSelection -ConfigPath $ConfigPath
  $config = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext $IdentityContext
  $config.configSource = $selection.configSource
  $config.rememberedPath = $selection.rememberedPath
  return $config
}

function Get-EffectiveServiceAccountMode {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [pscredential]$Credential
  )

  if ($null -ne $Credential) {
    return 'credential'
  }

  return $Config.serviceAccountMode
}

function Ensure-Directory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    [void](New-Item -ItemType Directory -Path $Path -Force)
  }
}

function Install-TrayStartupShortcut {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [string]$ConfigPath,
    [string]$StartupDirectory = (Get-CurrentUserStartupDirectory)
  )

  Ensure-Directory -Path $StartupDirectory

  $shortcutPath = Get-TrayShortcutPath -Config $Config -StartupDirectory $StartupDirectory
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $null
  try {
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Get-WindowsScriptHostExecutablePath
    $shortcut.Arguments = Get-TrayControllerLauncherArguments -ConfigPath $ConfigPath
    $shortcut.WorkingDirectory = $script:RepoRoot
    $shortcut.Description = "Open the $($Config.displayName) tray controller."
    $shortcut.IconLocation = "$([System.Environment]::SystemDirectory)\shell32.dll,44"
    $shortcut.Save()
  } finally {
    if ($null -ne $shortcut) {
      [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut)
    }

    if ($null -ne $shell) {
      [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
  }

  return $shortcutPath
}

function Remove-TrayStartupShortcut {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [string]$StartupDirectory = (Get-CurrentUserStartupDirectory)
  )

  $shortcutPath = Get-TrayShortcutPath -Config $Config -StartupDirectory $StartupDirectory
  if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath -Force
    return $true
  }

  return $false
}

function Get-ServiceArtifactLayout {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  $winswBase = Resolve-AbsolutePath -Path $Config.winswHome -BasePath $script:RepoRoot
  $generatedDirectory = Join-Path $winswBase $Config.serviceName
  $generatedExecutablePath = Join-Path $generatedDirectory "$($Config.serviceName).exe"
  $generatedXmlPath = Join-Path $generatedDirectory "$($Config.serviceName).xml"
  $legacyExecutablePath = Join-Path $script:RepoRoot "$($Config.serviceName).exe"
  $legacyXmlPath = Join-Path $script:RepoRoot "$($Config.serviceName).xml"
  $stateFilePath = Join-Path $Config.runtimeStateDirectory "$($Config.serviceName).state.json"
  $controlStatePath = Join-Path $Config.runtimeStateDirectory "$($Config.serviceName).control-state.json"

  return @{
    generatedDirectory      = $generatedDirectory
    generatedExecutablePath = $generatedExecutablePath
    generatedXmlPath        = $generatedXmlPath
    legacyExecutablePath    = $legacyExecutablePath
    legacyXmlPath           = $legacyXmlPath
    stateFilePath           = $stateFilePath
    controlStatePath        = $controlStatePath
  }
}

function Get-ServiceControlArtifactPaths {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [ValidateSet('start', 'stop', 'restart')]
    [string]$Action
  )

  $layout = Get-ServiceArtifactLayout -Config $Config
  $paths = @{
    statePath = $layout.controlStatePath
  }

  if (-not [string]::IsNullOrWhiteSpace($Action)) {
    $paths.requestPath = Join-Path $Config.runtimeStateDirectory "$($Config.serviceName).control-$Action.request.json"
    $paths.resultPath = Join-Path $Config.runtimeStateDirectory "$($Config.serviceName).control-$Action.result.json"
    $paths.logPath = Join-Path $Config.logsDirectory "$($Config.serviceName).control-$Action.log"
  }

  return $paths
}

function Read-ServiceControlState {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  $paths = Get-ServiceControlArtifactPaths -Config $Config
  if (-not (Test-Path -LiteralPath $paths.statePath)) {
    return $null
  }

  return (ConvertTo-Hashtable -InputObject (Get-Content -LiteralPath $paths.statePath -Raw | ConvertFrom-Json))
}

function Write-ServiceControlState {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [hashtable]$State
  )

  $paths = Get-ServiceControlArtifactPaths -Config $Config
  Ensure-Directory -Path $Config.runtimeStateDirectory
  Set-Content -LiteralPath $paths.statePath -Value ($State | ConvertTo-Json -Depth 10) -Encoding UTF8
  return $paths.statePath
}

function Update-ServiceControlState {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [hashtable]$Patch
  )

  $existing = Read-ServiceControlState -Config $Config
  if ($null -eq $existing) {
    $existing = @{}
  }

  foreach ($key in $Patch.Keys) {
    $existing[$key] = $Patch[$key]
  }

  Write-ServiceControlState -Config $Config -State $existing | Out-Null
}

function Read-ServiceControlRequest {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop', 'restart')]
    [string]$Action
  )

  $paths = Get-ServiceControlArtifactPaths -Config $Config -Action $Action
  if (-not (Test-Path -LiteralPath $paths.requestPath)) {
    return $null
  }

  return (ConvertTo-Hashtable -InputObject (Get-Content -LiteralPath $paths.requestPath -Raw | ConvertFrom-Json))
}

function Write-ServiceControlRequest {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop', 'restart')]
    [string]$Action,
    [Parameter(Mandatory = $true)]
    [hashtable]$Request
  )

  $paths = Get-ServiceControlArtifactPaths -Config $Config -Action $Action
  Ensure-Directory -Path $Config.runtimeStateDirectory
  Set-Content -LiteralPath $paths.requestPath -Value ($Request | ConvertTo-Json -Depth 10) -Encoding UTF8
  return $paths.requestPath
}

function Read-ServiceControlResult {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop', 'restart')]
    [string]$Action
  )

  $paths = Get-ServiceControlArtifactPaths -Config $Config -Action $Action
  if (-not (Test-Path -LiteralPath $paths.resultPath)) {
    return $null
  }

  return (ConvertTo-Hashtable -InputObject (Get-Content -LiteralPath $paths.resultPath -Raw | ConvertFrom-Json))
}

function Write-ServiceControlResult {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop', 'restart')]
    [string]$Action,
    [Parameter(Mandatory = $true)]
    [hashtable]$Result
  )

  $paths = Get-ServiceControlArtifactPaths -Config $Config -Action $Action
  Ensure-Directory -Path $Config.runtimeStateDirectory
  Set-Content -LiteralPath $paths.resultPath -Value ($Result | ConvertTo-Json -Depth 10) -Encoding UTF8
  return $paths.resultPath
}

function Write-ServiceControlAudit {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop', 'restart')]
    [string]$Action,
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  $paths = Get-ServiceControlArtifactPaths -Config $Config -Action $Action
  Ensure-Directory -Path $Config.logsDirectory
  Add-Content -LiteralPath $paths.logPath -Value ("{0} {1}" -f (Get-Date).ToString('o'), $Message) -Encoding UTF8
}

function Get-ServiceControlMutexName {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ServiceName
  )

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($ServiceName.ToLowerInvariant())
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = [System.BitConverter]::ToString($algorithm.ComputeHash($bytes)).Replace('-', '')
  } finally {
    $algorithm.Dispose()
  }

  return "Global\OpenClaw.Control.$hash"
}

function Test-IsCurrentProcessElevated {
  [CmdletBinding()]
  param()

  $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-EmptyScheduledTaskStatusReport {
  [CmdletBinding()]
  param()

  return @{
    taskPath       = $null
    taskName       = $null
    fullTaskName   = $null
    scriptPath     = $null
    logPath        = $null
    description    = $null
    exists         = $false
    state          = $null
    matches        = $false
    expectedAction = @{
      execute   = $null
      arguments = $null
    }
    actualAction   = @{
      execute   = $null
      arguments = $null
    }
  }
}

function New-EmptyServiceRestartTaskStatusReport {
  [CmdletBinding()]
  param()

  return (New-EmptyScheduledTaskStatusReport)
}

function New-EmptyServiceControlTaskStatusReport {
  [CmdletBinding()]
  param(
    [ValidateSet('start', 'stop', 'restart')]
    [string]$Action
  )

  $report = New-EmptyScheduledTaskStatusReport
  $report.action = $Action
  $report.requestPath = $null
  $report.resultPath = $null
  $report.statePath = $null
  return $report
}

function Set-ScheduledTaskStatusReportFromInfo {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Report,
    [Parameter(Mandatory = $true)]
    [hashtable]$TaskInfo
  )

  $Report.taskPath = $TaskInfo.taskPath
  $Report.taskName = $TaskInfo.taskName
  $Report.fullTaskName = $TaskInfo.fullTaskName
  $Report.scriptPath = $TaskInfo.scriptPath
  $Report.logPath = $TaskInfo.logPath
  $Report.description = $TaskInfo.description
  $Report.expectedAction.execute = $TaskInfo.actionExecutable
  $Report.expectedAction.arguments = $TaskInfo.actionArguments

  if ($TaskInfo.ContainsKey('requestPath')) {
    $Report.requestPath = $TaskInfo.requestPath
  }

  if ($TaskInfo.ContainsKey('resultPath')) {
    $Report.resultPath = $TaskInfo.resultPath
  }

  if ($TaskInfo.ContainsKey('statePath')) {
    $Report.statePath = $TaskInfo.statePath
  }

  return $Report
}

function New-ServiceScheduledTaskInfo {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$TaskName,
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [Parameter(Mandatory = $true)]
    [string]$LogPath,
    [Parameter(Mandatory = $true)]
    [string]$Description,
    [hashtable]$AdditionalArguments = @{}
  )

  $taskPath = '\OpenClaw\'
  $fullTaskName = "$taskPath$TaskName"
  $actionExecutable = Get-WindowsPowerShellExecutablePath
  $actionArguments = Format-PowerShellCommandArguments -ScriptPath $ScriptPath -ConfigPath $ConfigPath -AdditionalNamedArguments $AdditionalArguments

  return @{
    taskPath         = $taskPath
    taskName         = $TaskName
    fullTaskName     = $fullTaskName
    scriptPath       = $ScriptPath
    logPath          = $LogPath
    description      = $Description
    actionExecutable = $actionExecutable
    actionArguments  = $actionArguments
  }
}

function Get-ServiceRestartTaskInfo {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  $scriptPath = Join-Path $script:RepoRoot 'restart-service-task.ps1'
  return (New-ServiceScheduledTaskInfo `
    -TaskName "$($Config.serviceName)-Restart" `
    -ScriptPath $scriptPath `
    -ConfigPath $Config.sourceConfigPath `
    -LogPath (Join-Path $Config.logsDirectory "$($Config.serviceName).restart-task.log") `
    -Description "Bridge intentional OpenClaw restarts back into the WinSW service '$($Config.serviceName)'." `
    -AdditionalArguments @{})
}

function Get-ServiceControlTaskInfo {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop', 'restart')]
    [string]$Action
  )

  if ($Action -eq 'restart') {
    $restartInfo = Get-ServiceRestartTaskInfo -Config $Config
    $restartPaths = Get-ServiceControlArtifactPaths -Config $Config -Action $Action
    $restartInfo.requestPath = $restartPaths.requestPath
    $restartInfo.resultPath = $restartPaths.resultPath
    $restartInfo.statePath = $restartPaths.statePath
    return $restartInfo
  }

  $actionTitle = (Get-Culture).TextInfo.ToTitleCase($Action)
  $scriptPath = Join-Path $script:RepoRoot 'control-service-task.ps1'
  $paths = Get-ServiceControlArtifactPaths -Config $Config -Action $Action
  $info = New-ServiceScheduledTaskInfo `
    -TaskName "$($Config.serviceName)-$actionTitle" `
    -ScriptPath $scriptPath `
    -ConfigPath $Config.sourceConfigPath `
    -LogPath $paths.logPath `
    -Description "Bridge '$Action' requests for the WinSW service '$($Config.serviceName)' through a SYSTEM-owned control task." `
    -AdditionalArguments @{ Action = $Action }
  $info.requestPath = $paths.requestPath
  $info.resultPath = $paths.resultPath
  $info.statePath = $paths.statePath
  return $info
}

function Format-ServiceScheduledTaskCommandLine {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$TaskInfo
  )

  return ('"{0}" {1}' -f $TaskInfo.actionExecutable, $TaskInfo.actionArguments)
}

function Format-ServiceRestartTaskCommandLine {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$TaskInfo
  )

  return (Format-ServiceScheduledTaskCommandLine -TaskInfo $TaskInfo)
}

function Invoke-SchtasksCommand {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments,
    [switch]$AllowFailure
  )

  $output = & schtasks.exe @Arguments 2>&1 | ForEach-Object { $_.ToString() }
  $exitCode = $LASTEXITCODE
  $text = ($output -join [Environment]::NewLine).Trim()

  if (-not $AllowFailure -and $exitCode -ne 0) {
    if ([string]::IsNullOrWhiteSpace($text)) {
      throw "schtasks.exe failed with exit code $exitCode."
    }

    throw "schtasks.exe failed with exit code ${exitCode}: $text"
  }

  return @{
    exitCode = $exitCode
    output   = $text
  }
}

function Get-ScheduledTaskStatusViaCom {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$TaskInfo,
    [Parameter(Mandatory = $true)]
    [hashtable]$Report
  )

  $service = $null
  try {
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $folderPath = $TaskInfo.taskPath.TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($folderPath)) {
      $folderPath = '\'
    }
    $folder = $service.GetFolder($folderPath)
    $task = $folder.GetTask($TaskInfo.taskName)

    if ($null -eq $task) {
      return $Report
    }

    $Report.exists = $true
    $Report.state = $task.State.ToString()

    [xml]$definition = $task.Xml
    $commandNode = $definition.SelectSingleNode('/Task/Actions/Exec/Command')
    $argumentsNode = $definition.SelectSingleNode('/Task/Actions/Exec/Arguments')

    $Report.actualAction.execute = if ($null -ne $commandNode) { $commandNode.InnerText } else { $null }
    $Report.actualAction.arguments = if ($null -ne $argumentsNode) { $argumentsNode.InnerText } else { $null }
    $Report.matches = (
      (Test-ServiceRestartTaskExecutableMatch -Expected $TaskInfo.actionExecutable -Actual $Report.actualAction.execute) -and
      [string]::Equals($TaskInfo.actionArguments, $Report.actualAction.arguments, [System.StringComparison]::OrdinalIgnoreCase)
    )

    return $Report
  } catch {
    $message = $_.Exception.Message
    $hresult = $_.Exception.HResult
    if ($hresult -eq -2147024891 -or $message -match 'Access is denied') {
      $Report.exists = $true
      $Report.matches = $true
      $Report.state = 'Unknown'
      return $Report
    }

    return $Report
  } finally {
    if ($null -ne $service) {
      [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($service)
    }
  }
}

function Test-ServiceRestartTaskExecutableMatch {
  param(
    [AllowNull()]
    [string]$Expected,
    [AllowNull()]
    [string]$Actual
  )

  if ([string]::IsNullOrWhiteSpace($Expected) -or [string]::IsNullOrWhiteSpace($Actual)) {
    return $false
  }

  $expectedFullPath = [System.IO.Path]::GetFullPath($Expected)
  $actualNormalized = $Actual.Trim()

  if ([System.IO.Path]::IsPathRooted($actualNormalized)) {
    $actualFullPath = [System.IO.Path]::GetFullPath($actualNormalized)
    if ([string]::Equals($expectedFullPath, $actualFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }

  return [string]::Equals(
    [System.IO.Path]::GetFileName($expectedFullPath),
    [System.IO.Path]::GetFileName($actualNormalized),
    [System.StringComparison]::OrdinalIgnoreCase
  )
}

function Get-ScheduledTaskStatusReport {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$TaskInfo,
    [Parameter(Mandatory = $true)]
    [hashtable]$Report
  )

  Set-ScheduledTaskStatusReportFromInfo -Report $Report -TaskInfo $TaskInfo | Out-Null
  $task = $null
  try {
    $task = Get-ScheduledTask -TaskPath $TaskInfo.taskPath -TaskName $TaskInfo.taskName -ErrorAction Stop
  } catch {
    return (Get-ScheduledTaskStatusViaCom -TaskInfo $TaskInfo -Report $Report)
  }

  $Report.exists = $true
  $Report.state = $task.State.ToString()

  $action = $null
  if ($null -ne $task.Actions) {
    $actions = @($task.Actions)
    if ($actions.Count -gt 0) {
      $action = $actions[0]
    }
  }

  if ($null -ne $action) {
    $Report.actualAction.execute = $action.Execute
    $Report.actualAction.arguments = $action.Arguments
  }

  $Report.matches = (
    (Test-ServiceRestartTaskExecutableMatch -Expected $TaskInfo.actionExecutable -Actual $Report.actualAction.execute) -and
    [string]::Equals($TaskInfo.actionArguments, $Report.actualAction.arguments, [System.StringComparison]::OrdinalIgnoreCase)
  )

  return $Report
}

function Get-ServiceRestartTaskStatus {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  $info = Get-ServiceRestartTaskInfo -Config $Config
  $report = New-EmptyServiceRestartTaskStatusReport
  return (Get-ScheduledTaskStatusReport -TaskInfo $info -Report $report)
}

function Get-ServiceControlTaskStatus {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop', 'restart')]
    [string]$Action
  )

  $info = Get-ServiceControlTaskInfo -Config $Config -Action $Action
  $report = New-EmptyServiceControlTaskStatusReport -Action $Action
  return (Get-ScheduledTaskStatusReport -TaskInfo $info -Report $report)
}

function Get-ServiceControlTaskStatuses {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  return [ordered]@{
    start   = Get-ServiceControlTaskStatus -Config $Config -Action 'start'
    stop    = Get-ServiceControlTaskStatus -Config $Config -Action 'stop'
    restart = Get-ServiceControlTaskStatus -Config $Config -Action 'restart'
  }
}

function Register-WrapperScheduledTask {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$TaskInfo
  )

  try {
    $action = New-ScheduledTaskAction -Execute $TaskInfo.actionExecutable -Argument $TaskInfo.actionArguments -WorkingDirectory $script:RepoRoot
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
      -AllowStartIfOnBatteries `
      -DontStopIfGoingOnBatteries `
      -StartWhenAvailable `
      -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    Register-ScheduledTask `
      -TaskPath $TaskInfo.taskPath `
      -TaskName $TaskInfo.taskName `
      -Action $action `
      -Principal $principal `
      -Settings $settings `
      -Description $TaskInfo.description `
      -Force | Out-Null
  } catch {
    $taskCommand = Format-ServiceScheduledTaskCommandLine -TaskInfo $TaskInfo
    Invoke-SchtasksCommand -Arguments @(
      '/Create',
      '/TN', $TaskInfo.fullTaskName,
      '/SC', 'ONCE',
      '/ST', '23:59',
      '/RU', 'SYSTEM',
      '/RL', 'HIGHEST',
      '/TR', $taskCommand,
      '/F'
    ) | Out-Null
  }

  return $TaskInfo.fullTaskName
}

function Remove-WrapperScheduledTask {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$TaskInfo
  )

  try {
    Get-ScheduledTask -TaskPath $TaskInfo.taskPath -TaskName $TaskInfo.taskName -ErrorAction Stop | Out-Null
  } catch {
    $query = Invoke-SchtasksCommand -Arguments @('/Query', '/TN', $TaskInfo.fullTaskName) -AllowFailure
    if ($query.exitCode -ne 0) {
      return $false
    }

    Invoke-SchtasksCommand -Arguments @('/Delete', '/TN', $TaskInfo.fullTaskName, '/F') | Out-Null
    return $true
  }

  Unregister-ScheduledTask -TaskPath $TaskInfo.taskPath -TaskName $TaskInfo.taskName -Confirm:$false
  return $true
}

function Start-WrapperScheduledTask {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$TaskInfo
  )

  try {
    Start-ScheduledTask -TaskPath $TaskInfo.taskPath -TaskName $TaskInfo.taskName -ErrorAction Stop
    return $true
  } catch {
    $result = Invoke-SchtasksCommand -Arguments @('/Run', '/TN', $TaskInfo.fullTaskName) -AllowFailure
    if ($result.exitCode -ne 0) {
      if ([string]::IsNullOrWhiteSpace($result.output)) {
        throw "Failed to start scheduled task '$($TaskInfo.fullTaskName)'."
      }

      throw "Failed to start scheduled task '$($TaskInfo.fullTaskName)': $($result.output)"
    }
  }

  return $true
}

function Register-ServiceRestartTask {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  $info = Get-ServiceRestartTaskInfo -Config $Config
  return (Register-WrapperScheduledTask -TaskInfo $info)
}

function Register-ServiceControlTasks {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  return [ordered]@{
    start   = Register-WrapperScheduledTask -TaskInfo (Get-ServiceControlTaskInfo -Config $Config -Action 'start')
    stop    = Register-WrapperScheduledTask -TaskInfo (Get-ServiceControlTaskInfo -Config $Config -Action 'stop')
    restart = Register-ServiceRestartTask -Config $Config
  }
}

function Remove-ServiceRestartTask {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  return (Remove-WrapperScheduledTask -TaskInfo (Get-ServiceRestartTaskInfo -Config $Config))
}

function Remove-ServiceControlTasks {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  return [ordered]@{
    start   = Remove-WrapperScheduledTask -TaskInfo (Get-ServiceControlTaskInfo -Config $Config -Action 'start')
    stop    = Remove-WrapperScheduledTask -TaskInfo (Get-ServiceControlTaskInfo -Config $Config -Action 'stop')
    restart = Remove-ServiceRestartTask -Config $Config
  }
}

function Get-ServiceExecutablePathFromPathName {
  param(
    [AllowNull()]
    [string]$PathName
  )

  if ([string]::IsNullOrWhiteSpace($PathName)) {
    return $null
  }

  if ($PathName -match '^\s*"([^"]+)"') {
    return [System.IO.Path]::GetFullPath($matches[1])
  }

  if ($PathName -match '^\s*(\S+)') {
    return [System.IO.Path]::GetFullPath($matches[1])
  }

  return $null
}

function Get-ServiceInstallLayoutFromExecutablePath {
  param(
    [AllowNull()]
    [string]$ExecutablePath
  )

  if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
    return 'generated'
  }

  $resolvedExecutablePath = [System.IO.Path]::GetFullPath($ExecutablePath)
  $generatedRoot = [System.IO.Path]::GetFullPath((Join-Path $script:RepoRoot 'tools\winsw'))
  if ($resolvedExecutablePath.StartsWith($generatedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return 'generated'
  }

  $executableDirectory = Split-Path -Parent $resolvedExecutablePath
  if ([string]::Equals($executableDirectory, $script:RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return 'legacyRoot'
  }

  return 'generated'
}

function Get-WinSWServiceAccountInfo {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$XmlPath
  )

  if (-not (Test-Path -LiteralPath $XmlPath)) {
    return $null
  }

  [xml]$document = Get-Content -LiteralPath $XmlPath -Raw
  $serviceAccountNode = $document.SelectSingleNode('/service/serviceaccount')
  if ($null -eq $serviceAccountNode) {
    return @{
      xmlPath            = $XmlPath
      hasServiceAccount  = $false
      expectedStartName  = $null
    }
  }

  $domain = $serviceAccountNode.domain
  $user = $serviceAccountNode.user
  if ([string]::IsNullOrWhiteSpace($user)) {
    return @{
      xmlPath            = $XmlPath
      hasServiceAccount  = $false
      expectedStartName  = $null
    }
  }

  $expectedStartName = if ([string]::IsNullOrWhiteSpace($domain) -or $domain -eq '.') {
    if ($user.Contains('@')) {
      $user
    } else {
      ".\$user"
    }
  } else {
    "$domain\$user"
  }

  return @{
    xmlPath           = $XmlPath
    hasServiceAccount = $true
    expectedStartName = $expectedStartName
  }
}

function Get-ServiceInstallLayout {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [hashtable]$ServiceDetails
  )

  if (($null -ne $ServiceDetails) -and $ServiceDetails.installed -and -not [string]::IsNullOrWhiteSpace($ServiceDetails.pathName)) {
    $actualExecutablePath = Get-ServiceExecutablePathFromPathName -PathName $ServiceDetails.pathName
    return (Get-ServiceInstallLayoutFromExecutablePath -ExecutablePath $actualExecutablePath)
  }

  $layout = Get-ServiceArtifactLayout -Config $Config
  if ((Test-Path -LiteralPath $layout.legacyExecutablePath) -and -not (Test-Path -LiteralPath $layout.generatedExecutablePath)) {
    return 'legacyRoot'
  }

  return 'generated'
}

function Resolve-InspectionIdentityContext {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [hashtable]$ServiceDetails,
    [string]$CurrentWindowsIdentityName = (Get-CurrentWindowsIdentityName)
  )

  if (($null -ne $ServiceDetails) -and $ServiceDetails.installed -and -not [string]::IsNullOrWhiteSpace($ServiceDetails.startName)) {
    return (Get-ServiceAccountIdentityContext -AccountName $ServiceDetails.startName)
  }

  $plan = Resolve-ServiceAccountPlan -Config $Config -CurrentWindowsIdentityName $CurrentWindowsIdentityName
  if ($null -ne $plan.identityContext) {
    return $plan.identityContext
  }

  return (Get-ServiceIdentityContext -Mode 'currentUser')
}

function Get-ServiceIdentityReport {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [hashtable]$ServiceDetails,
    [string]$CurrentWindowsIdentityName = (Get-CurrentWindowsIdentityName)
  )

  $plan = Resolve-ServiceAccountPlan -Config $Config -CurrentWindowsIdentityName $CurrentWindowsIdentityName
  $installLayout = Get-ServiceInstallLayout -Config $Config -ServiceDetails $ServiceDetails
  $layout = Get-ServiceArtifactLayout -Config $Config
  $xmlPath = if ($installLayout -eq 'legacyRoot') {
    $layout.legacyXmlPath
  } else {
    $layout.generatedXmlPath
  }

  $xmlAccount = Get-WinSWServiceAccountInfo -XmlPath $xmlPath
  $expectedStartName = if (($null -ne $xmlAccount) -and -not [string]::IsNullOrWhiteSpace($xmlAccount.expectedStartName)) {
    $xmlAccount.expectedStartName
  } elseif (($installLayout -eq 'legacyRoot') -and ($plan.configuredMode -eq 'currentUser')) {
    $null
  } else {
    $plan.expectedStartName
  }

  $actualStartName = if (($null -ne $ServiceDetails) -and $ServiceDetails.installed) {
    $ServiceDetails.startName
  } else {
    $null
  }

  $matches = if (-not [string]::IsNullOrWhiteSpace($expectedStartName) -and -not [string]::IsNullOrWhiteSpace($actualStartName)) {
    Test-ServiceAccountMatch -ExpectedAccountName $expectedStartName -ActualAccountName $actualStartName
  } else {
    $false
  }

  return @{
    configuredMode   = $plan.configuredMode
    deprecatedAlias  = $plan.deprecatedAlias
    expectedStartName = $expectedStartName
    actualStartName  = $actualStartName
    matches          = $matches
    installLayout    = $installLayout
  }
}

function Get-ServiceInstallValidationIssues {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [hashtable]$ServiceDetails,
    [string]$CurrentWindowsIdentityName = (Get-CurrentWindowsIdentityName)
  )

  $identity = Get-ServiceIdentityReport -Config $Config -ServiceDetails $ServiceDetails -CurrentWindowsIdentityName $CurrentWindowsIdentityName
  $issues = @()

  if (Test-IsBuiltInServiceAccount -AccountName $identity.actualStartName) {
    if (-not ([string]::IsNullOrWhiteSpace($identity.expectedStartName)) -and $identity.matches) {
      return [string[]]$issues
    }

    if ([string]::IsNullOrWhiteSpace($identity.expectedStartName)) {
      $issues += "Service '$($Config.serviceName)' was installed as built-in account '$($identity.actualStartName)'. Reinstall with explicit credentials."
    } else {
      $issues += "Service '$($Config.serviceName)' is running as '$($identity.actualStartName)', but the planned service account is '$($identity.expectedStartName)'. Reinstall with explicit credentials."
    }
  } elseif (-not [string]::IsNullOrWhiteSpace($identity.expectedStartName) -and -not $identity.matches) {
    $issues += "Service '$($Config.serviceName)' is running as '$($identity.actualStartName)', but the planned service account is '$($identity.expectedStartName)'. Reinstall with explicit credentials."
  }

  return [string[]]$issues
}

function Resolve-ManagedExecutablePath {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  $layout = Get-ServiceArtifactLayout -Config $Config
  if (Test-Path -LiteralPath $layout.generatedExecutablePath) {
    return $layout.generatedExecutablePath
  }

  if (Test-Path -LiteralPath $layout.legacyExecutablePath) {
    return $layout.legacyExecutablePath
  }

  throw "WinSW executable not found. Expected either '$($layout.generatedExecutablePath)' or '$($layout.legacyExecutablePath)'."
}

function Escape-XmlText {
  param(
    [AllowNull()]
    [string]$Value
  )

  if ($null -eq $Value) {
    return ''
  }

  return [System.Security.SecurityElement]::Escape($Value)
}

function Format-PowerShellCommandArguments {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,
    [string]$ConfigPath,
    [hashtable]$AdditionalNamedArguments = @{}
  )

  $arguments = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    ('"{0}"' -f $ScriptPath)
  )

  if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $arguments += @(
      '-ConfigPath',
      ('"{0}"' -f $ConfigPath)
    )
  }

  foreach ($key in ($AdditionalNamedArguments.Keys | Sort-Object)) {
    $value = $AdditionalNamedArguments[$key]
    if ($value -is [switch]) {
      if ([bool]$value) {
        $arguments += "-$key"
      }

      continue
    }

    if ($value -is [bool]) {
      if ([bool]$value) {
        $arguments += "-$key"
      }

      continue
    }

    $arguments += "-$key"
    $arguments += ('"{0}"' -f "$value")
  }

  return ($arguments -join ' ')
}

function Join-ProcessArgumentString {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $quoted = foreach ($argument in $Arguments) {
    if ([string]::IsNullOrEmpty($argument)) {
      '""'
      continue
    }

    if ($argument -match '[\s"]') {
      '"{0}"' -f $argument.Replace('"', '\"')
      continue
    }

    $argument
  }

  return ($quoted -join ' ')
}

function Split-ServiceCredentialUser {
  param(
    [Parameter(Mandatory = $true)]
    [string]$UserName
  )

  if ($UserName.Contains('\')) {
    $parts = $UserName.Split('\', 2)
    return @{
      domain = $parts[0]
      user   = $parts[1]
    }
  }

  return @{
    domain = '.'
    user   = $UserName
  }
}

function Render-WinSWServiceXml {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [ValidateSet('currentUser', 'credential', 'localSystem')]
    [string]$ServiceAccountMode = 'currentUser',
    [pscredential]$Credential
  )

  $templatePath = Join-Path $script:RepoRoot 'templates\winsw-service.xml.template'
  $runScript = Join-Path $script:RepoRoot 'run-gateway.ps1'
  $stopScript = Join-Path $script:RepoRoot 'stop-gateway.ps1'
  $template = Get-Content -LiteralPath $templatePath -Raw

  $delayedAutoStartBlock = if ($Config.delayedAutoStart) {
    '  <delayedAutoStart>true</delayedAutoStart>'
  } else {
    ''
  }

  $failureLines = foreach ($delay in $Config.failureActions) {
    "  <onfailure action=`"restart`" delay=`"$delay`"></onfailure>"
  }

  $serviceAccountBlock = ''
  if (($ServiceAccountMode -eq 'localSystem') -and ($null -ne $Credential)) {
    throw "serviceAccountMode 'localSystem' must not render a WinSW serviceaccount block."
  }

  if (($ServiceAccountMode -in @('currentUser', 'credential')) -and ($null -ne $Credential)) {
    $credentialParts = Split-ServiceCredentialUser -UserName $Credential.UserName
    $serviceAccountBlock = @(
      '  <serviceaccount>'
      "    <domain>$(Escape-XmlText -Value $credentialParts.domain)</domain>"
      "    <user>$(Escape-XmlText -Value $credentialParts.user)</user>"
      "    <password>$(Escape-XmlText -Value $Credential.GetNetworkCredential().Password)</password>"
      '    <allowservicelogon>true</allowservicelogon>'
      '  </serviceaccount>'
    ) -join [Environment]::NewLine
  } elseif ($ServiceAccountMode -eq 'credential') {
    throw 'Credential mode requires a PSCredential.'
  }

  $replacements = @{
    '{{SERVICE_ID}}'               = Escape-XmlText -Value $Config.serviceName
    '{{DISPLAY_NAME}}'             = Escape-XmlText -Value $Config.displayName
    '{{SERVICE_DESCRIPTION}}'      = Escape-XmlText -Value $Config.description
    '{{EXECUTABLE}}'               = Escape-XmlText -Value 'powershell.exe'
    '{{ARGUMENTS}}'                = Escape-XmlText -Value (Format-PowerShellCommandArguments -ScriptPath $runScript -ConfigPath $Config.sourceConfigPath)
    '{{WORKING_DIRECTORY}}'        = Escape-XmlText -Value $script:RepoRoot
    '{{LOG_PATH}}'                 = Escape-XmlText -Value $Config.logsDirectory
    '{{LOG_MODE}}'                 = Escape-XmlText -Value $Config.logPolicy.mode
    '{{START_MODE}}'               = Escape-XmlText -Value $Config.startMode
    '{{DELAYED_AUTO_START_BLOCK}}' = $delayedAutoStartBlock
    '{{RESET_FAILURE}}'            = Escape-XmlText -Value $Config.resetFailure
    '{{ON_FAILURE_BLOCK}}'         = $failureLines -join [Environment]::NewLine
    '{{STOP_TIMEOUT}}'             = Escape-XmlText -Value ("$($Config.stopTimeoutSeconds) sec")
    '{{STOP_EXECUTABLE}}'          = Escape-XmlText -Value 'powershell.exe'
    '{{STOP_ARGUMENTS}}'           = Escape-XmlText -Value (Format-PowerShellCommandArguments -ScriptPath $stopScript -ConfigPath $Config.sourceConfigPath)
    '{{SERVICE_ACCOUNT_BLOCK}}'    = $serviceAccountBlock
  }

  foreach ($token in $replacements.Keys) {
    $template = $template.Replace($token, $replacements[$token])
  }

  return $template
}

function Write-WinSWServiceXml {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [ValidateSet('currentUser', 'credential', 'localSystem')]
    [string]$ServiceAccountMode = 'currentUser',
    [pscredential]$Credential
  )

  $layout = Get-ServiceArtifactLayout -Config $Config
  Ensure-Directory -Path $layout.generatedDirectory
  $xml = Render-WinSWServiceXml -Config $Config -ServiceAccountMode $ServiceAccountMode -Credential $Credential
  Set-Content -LiteralPath $layout.generatedXmlPath -Value $xml -Encoding UTF8
  return $layout.generatedXmlPath
}

function Ensure-WinSWBinary {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [switch]$Force
  )

  $layout = Get-ServiceArtifactLayout -Config $Config
  Ensure-Directory -Path $layout.generatedDirectory

  $needsDownload = $true
  if ((Test-Path -LiteralPath $layout.generatedExecutablePath) -and -not $Force) {
    $existingHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $layout.generatedExecutablePath).Hash
    if ($existingHash -eq $Config.winswChecksum.ToUpperInvariant()) {
      $needsDownload = $false
    }
  }

  if ($needsDownload) {
    $temporaryPath = Join-Path $env:TEMP "$($Config.serviceName)-winsw-$($Config.winswVersion).exe"
    Invoke-WebRequest -Uri $Config.winswDownloadUrl -OutFile $temporaryPath
    $downloadedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $temporaryPath).Hash
    if ($downloadedHash -ne $Config.winswChecksum.ToUpperInvariant()) {
      throw "Downloaded WinSW checksum mismatch. Expected $($Config.winswChecksum), got $downloadedHash."
    }

    Copy-Item -LiteralPath $temporaryPath -Destination $layout.generatedExecutablePath -Force
  }

  return $layout.generatedExecutablePath
}

function Resolve-OpenClawCommandPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [hashtable]$IdentityContext = (Get-ServiceIdentityContext -Mode 'currentUser')
  )

  if (-not [string]::IsNullOrWhiteSpace($Config.openclawCommand)) {
    $commandMatch = Get-Command $Config.openclawCommand -ErrorAction SilentlyContinue
    if ($null -ne $commandMatch) {
      return $commandMatch.Source
    }

    $configuredPath = Expand-ConfigValue -Value $Config.openclawCommand -IdentityContext $IdentityContext
    $configuredPath = Resolve-AbsolutePath -Path $configuredPath -BasePath $script:RepoRoot
    if (-not (Test-Path -LiteralPath $configuredPath)) {
      throw "Configured openclawCommand does not exist: $configuredPath"
    }

    return $configuredPath
  }

  $command = Get-Command openclaw.cmd -ErrorAction SilentlyContinue
  if ($null -ne $command) {
    return $command.Source
  }

  $programsRoot = Join-Path $IdentityContext.localAppData 'Programs'
  if (Test-Path -LiteralPath $programsRoot) {
    $candidates = Get-ChildItem -LiteralPath $programsRoot -Directory -Filter 'node-*-win-x64' |
      Sort-Object Name -Descending |
      ForEach-Object { Join-Path $_.FullName 'openclaw.cmd' } |
      Where-Object { Test-Path -LiteralPath $_ }

    if ($candidates.Count -gt 0) {
      return $candidates[0]
    }
  }

  throw "openclaw.cmd could not be found in PATH or under $programsRoot."
}

function Resolve-OpenClawLaunchSpec {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [hashtable]$IdentityContext = (Get-ServiceIdentityContext -Mode 'currentUser')
  )

  $requestedCommandPath = Resolve-OpenClawCommandPath -Config $Config -IdentityContext $IdentityContext
  $executablePath = $requestedCommandPath
  $preArguments = @()
  $launchMode = 'directCommand'
  $entryScriptPath = $null

  if ($requestedCommandPath -match '\.cmd$') {
    $commandDirectory = Split-Path -Parent $requestedCommandPath
    $nodeExecutablePath = Join-Path $commandDirectory 'node.exe'
    $candidateEntryScriptPath = Join-Path $commandDirectory 'node_modules\openclaw\openclaw.mjs'
    if ((Test-Path -LiteralPath $nodeExecutablePath) -and (Test-Path -LiteralPath $candidateEntryScriptPath)) {
      $executablePath = $nodeExecutablePath
      $preArguments = @($candidateEntryScriptPath)
      $entryScriptPath = $candidateEntryScriptPath
      $launchMode = 'directNodeFromCmdShim'
    } else {
      $launchMode = 'cmdShim'
    }
  }

  return @{
    requestedCommandPath = $requestedCommandPath
    executablePath       = $executablePath
    preArguments         = @($preArguments)
    entryScriptPath      = $entryScriptPath
    launchMode           = $launchMode
  }
}

function Get-ServiceDetails {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ServiceName
  )

  $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
  $cimService = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue

  if ($null -eq $service -and $null -eq $cimService) {
    return @{
      installed = $false
      name      = $ServiceName
      status    = $null
      startType = $null
      processId = 0
      startName = $null
      pathName  = $null
    }
  }

  return @{
    installed = $true
    name      = $ServiceName
    status    = if ($null -ne $service) { $service.Status.ToString() } else { $cimService.State }
    startType = if ($null -ne $service) { $service.StartType.ToString() } else { $null }
    processId = if ($null -ne $cimService) { [int]$cimService.ProcessId } else { 0 }
    startName = if ($null -ne $cimService) { $cimService.StartName } else { $null }
    pathName  = if ($null -ne $cimService) { $cimService.PathName } else { $null }
  }
}

function Wait-ForServiceStatus {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ServiceName,
    [Parameter(Mandatory = $true)]
    [ValidateSet('Running', 'Stopped')]
    [string]$DesiredStatus,
    [int]$TimeoutSec = 30
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  do {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($DesiredStatus -eq 'Stopped' -and $null -eq $service) {
      return $true
    }

    if ($null -ne $service -and $service.Status.ToString() -eq $DesiredStatus) {
      return $true
    }

    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  return $false
}

function Wait-ForServiceRemoval {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ServiceName,
    [int]$TimeoutSec = 30
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  do {
    $service = Get-ServiceDetails -ServiceName $ServiceName
    if (-not $service.installed) {
      return $true
    }

    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  return $false
}

function Disable-ServiceStartForReinstall {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ServiceName
  )

  & sc.exe config $ServiceName start= disabled *> $null
  return ($LASTEXITCODE -eq 0)
}

function Test-IsPendingServiceStatus {
  param(
    [AllowNull()]
    [string]$Status
  )

  if ([string]::IsNullOrWhiteSpace($Status)) {
    return $false
  }

  return $Status -in @('StartPending', 'StopPending', 'ContinuePending')
}

function Get-ServiceRecoveryContext {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  $service = Get-ServiceDetails -ServiceName $Config.serviceName
  try {
    $runState = Read-RunState -Config $Config
  } catch {
    $runState = $null
  }
  $wrapperProcessId = 0
  $gatewayProcessId = 0
  $recordedListenerProcessIds = @()
  $launchMode = $null
  if ($null -ne $runState -and $runState.ContainsKey('wrapperProcessId')) {
    $wrapperProcessId = [int]$runState.wrapperProcessId
  }
  if ($null -ne $runState -and $runState.ContainsKey('gatewayProcessId')) {
    $gatewayProcessId = [int]$runState.gatewayProcessId
  }
  if ($null -ne $runState -and $runState.ContainsKey('listenerProcessIds')) {
    $recordedListenerProcessIds = Normalize-RunStateProcessIdList -Value $runState.listenerProcessIds
  }
  if ($null -ne $runState -and $runState.ContainsKey('launchMode')) {
    $launchMode = "$($runState.launchMode)"
  }

  $listeners = @()
  if ($Config.ContainsKey('port') -and [int]$Config.port -gt 0) {
    try {
      $listeners = @(Get-PortListeners -Port ([int]$Config.port))
    } catch {
      $listeners = @()
    }
  }

  $listenerProcessIds = @(
    $listeners |
      ForEach-Object {
        if ($null -ne $_ -and $_.PSObject.Properties.Name -contains 'processId') {
          [int]$_.processId
        }
      } |
      Where-Object { $_ -gt 0 } |
      Sort-Object -Unique
  )

  $knownProcessIds = @(
    $listenerProcessIds +
    $recordedListenerProcessIds +
    @($gatewayProcessId, $wrapperProcessId, $service.processId)
  ) | Where-Object { $_ -gt 0 } | Sort-Object -Unique

  $existingProcessIds = @(
    $knownProcessIds |
      Where-Object { Test-ProcessExists -ProcessId $_ } |
      Sort-Object -Unique
  )

  $status = if ($service.installed) { "$($service.status)" } else { $null }
  $isPending = Test-IsPendingServiceStatus -Status $status
  $isStopPending = $status -eq 'StopPending'
  $isStartPending = $status -eq 'StartPending'
  $hasPortListeners = $listenerProcessIds.Count -gt 0
  $hasResidualProcesses = $existingProcessIds.Count -gt 0
  $isPortOccupiedWhileServiceNotRunning = $service.installed -and $status -ne 'Running' -and $hasPortListeners
  $isStuckStopping = $isStopPending -and ($hasResidualProcesses -or $hasPortListeners)
  $needsStartRecovery = $isStopPending -or $isPortOccupiedWhileServiceNotRunning

  $service.transitionStatus = if ($isPending) { $status } else { $null }
  $service.pending = $isPending
  $service.stuckStopping = $isStuckStopping
  $service.wrapperProcessId = $wrapperProcessId
  $service.gatewayProcessId = $gatewayProcessId
  $service.listenerProcessIds = $listenerProcessIds
  $service.recordedListenerProcessIds = $recordedListenerProcessIds
  $service.launchMode = $launchMode

  return @{
    service                        = $service
    runState                       = $runState
    status                         = $status
    wrapperProcessId               = $wrapperProcessId
    gatewayProcessId               = $gatewayProcessId
    listeners                      = $listeners
    listenerProcessIds             = $listenerProcessIds
    recordedListenerProcessIds     = $recordedListenerProcessIds
    knownProcessIds                = $knownProcessIds
    existingProcessIds             = $existingProcessIds
    isPending                      = $isPending
    isStopPending                  = $isStopPending
    isStartPending                 = $isStartPending
    hasPortListeners               = $hasPortListeners
    hasResidualProcesses           = $hasResidualProcesses
    isPortOccupiedWhileServiceNotRunning = $isPortOccupiedWhileServiceNotRunning
    isStuckStopping                = $isStuckStopping
    needsStartRecovery             = $needsStartRecovery
    launchMode                     = $launchMode
  }
}

function Normalize-RunStateProcessIdList {
  [CmdletBinding()]
  param(
    [AllowNull()]
    $Value
  )

  $processIds = @()
  foreach ($item in @($Value)) {
    $processId = 0
    if ([int]::TryParse("$item", [ref]$processId) -and $processId -gt 0) {
      $processIds += $processId
    }
  }

  return @($processIds | Sort-Object -Unique)
}

function Test-ServiceRuntimeProcessesStopped {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
  )

  foreach ($processId in @(
      @($Context.listenerProcessIds) +
      @($Context.recordedListenerProcessIds) +
      @($Context.gatewayProcessId, $Context.wrapperProcessId)
    ) | Where-Object { $_ -gt 0 } | Sort-Object -Unique) {
    if (Test-ProcessExists -ProcessId $processId) {
      return $false
    }
  }

  return (-not $Context.hasPortListeners)
}

function Get-ServiceRuntimeTerminationTargets {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context,
    [switch]$IncludeServiceProcess
  )

  $targets = [System.Collections.ArrayList]::new()
  $seen = @{}

  function Add-TerminationTarget {
    param(
      [int]$ProcessId,
      [string]$Kind,
      [bool]$IncludeChildren
    )

    if ($ProcessId -le 0) {
      return
    }

    $key = "$ProcessId"
    if ($seen.ContainsKey($key)) {
      return
    }

    $seen[$key] = $true
    [void]$targets.Add(@{
      processId       = $ProcessId
      kind            = $Kind
      includeChildren = $IncludeChildren
    })
  }

  foreach ($processId in @($Context.listenerProcessIds)) {
    Add-TerminationTarget -ProcessId $processId -Kind 'listener' -IncludeChildren $false
  }

  foreach ($processId in @($Context.recordedListenerProcessIds)) {
    Add-TerminationTarget -ProcessId $processId -Kind 'recordedListener' -IncludeChildren $false
  }

  Add-TerminationTarget -ProcessId $Context.gatewayProcessId -Kind 'gateway' -IncludeChildren $true
  Add-TerminationTarget -ProcessId $Context.wrapperProcessId -Kind 'wrapper' -IncludeChildren $true

  if ($IncludeServiceProcess -and $null -ne $Context.service) {
    Add-TerminationTarget -ProcessId ([int]$Context.service.processId) -Kind 'service' -IncludeChildren $true
  }

  return @($targets)
}

function Get-ServiceRecoveryIssueMessage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [hashtable]$Context = (Get-ServiceRecoveryContext -Config $Config)
  )

  if ($Context.isStuckStopping) {
    return "Service '$($Config.serviceName)' is stuck in StopPending while the gateway process is still alive. Clear the residual service process tree before starting again."
  }

  if ($Context.isPortOccupiedWhileServiceNotRunning) {
    return "Service '$($Config.serviceName)' is not running but a residual gateway process is still listening on port $($Config.port)."
  }

  if ($Context.isStartPending) {
    return "Service '$($Config.serviceName)' is still transitioning in StartPending."
  }

  if ($Context.isPending) {
    return "Service '$($Config.serviceName)' is still transitioning in $($Context.status)."
  }

  return $null
}

function Invoke-ServiceResidualCleanup {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [int]$TimeoutSec = 15
  )

  $initialContext = Get-ServiceRecoveryContext -Config $Config
  $treeStopped = Stop-RecordedServiceProcessTree -Config $Config -TimeoutSec $TimeoutSec
  $currentContext = Get-ServiceRecoveryContext -Config $Config
  $terminationTargets = @(Get-ServiceRuntimeTerminationTargets -Context $currentContext -IncludeServiceProcess)
  $attemptedProcessIds = @()

  foreach ($target in $terminationTargets) {
    $attemptedProcessIds += $target.processId
    [void](Stop-ProcessIdWithFallbacks -ProcessId $target.processId -IncludeChildren:$target.includeChildren)
  }

  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  do {
    $currentContext = Get-ServiceRecoveryContext -Config $Config
    if ((@($currentContext.existingProcessIds).Count -eq 0) -and -not $currentContext.hasPortListeners) {
      return @{
        success            = $true
        treeStopped        = $treeStopped
        attemptedProcessIds = @($attemptedProcessIds | Sort-Object -Unique)
        forceAttempted     = $false
        initialContext     = $initialContext
        context            = $currentContext
      }
    }

    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  $currentContext = Get-ServiceRecoveryContext -Config $Config
  foreach ($target in @(Get-ServiceRuntimeTerminationTargets -Context $currentContext -IncludeServiceProcess)) {
    if ($attemptedProcessIds -notcontains $target.processId) {
      $attemptedProcessIds += $target.processId
    }
    [void](Stop-ProcessIdWithFallbacks -ProcessId $target.processId -Force -IncludeChildren:$target.includeChildren)
  }

  Start-Sleep -Seconds 2
  $currentContext = Get-ServiceRecoveryContext -Config $Config
  return @{
    success            = ((@($currentContext.existingProcessIds).Count -eq 0) -and -not $currentContext.hasPortListeners)
    treeStopped        = $treeStopped
    attemptedProcessIds = @($attemptedProcessIds | Sort-Object -Unique)
    forceAttempted     = $true
    initialContext     = $initialContext
    context            = $currentContext
  }
}

function Stop-ManagedServiceWithRecovery {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [int]$TimeoutSec = 30
  )

  $graceTimeoutSec = [Math]::Min($TimeoutSec, [Math]::Max(5, [int]$Config.stopTimeoutSeconds))
  $standardStopFailed = $false

  try {
    Invoke-WinSWCommand -Config $Config -Command 'stop'
  } catch {
    $standardStopFailed = $true
  }

  if (Wait-ForServiceStatus -ServiceName $Config.serviceName -DesiredStatus 'Stopped' -TimeoutSec $graceTimeoutSec) {
    return @{
      message           = "Service '$($Config.serviceName)' is stopped."
      recovered         = $standardStopFailed
      cleanupAttempted  = $standardStopFailed
      cleanupResult     = $null
      context           = (Get-ServiceRecoveryContext -Config $Config)
    }
  }

  $context = Get-ServiceRecoveryContext -Config $Config
  $cleanup = Invoke-ServiceResidualCleanup -Config $Config -TimeoutSec ([Math]::Max(5, [int]$Config.stopTimeoutSeconds))
  if (Wait-ForServiceStatus -ServiceName $Config.serviceName -DesiredStatus 'Stopped' -TimeoutSec $TimeoutSec) {
    return @{
      message           = "Service '$($Config.serviceName)' is stopped."
      recovered         = $true
      cleanupAttempted  = $true
      cleanupResult     = $cleanup
      context           = (Get-ServiceRecoveryContext -Config $Config)
    }
  }

  $finalContext = Get-ServiceRecoveryContext -Config $Config
  $issueMessage = Get-ServiceRecoveryIssueMessage -Config $Config -Context $finalContext
  if ([string]::IsNullOrWhiteSpace($issueMessage)) {
    $issueMessage = "Service '$($Config.serviceName)' did not stop within $TimeoutSec seconds."
  }

  throw $issueMessage
}

function Start-ManagedServiceWithRecovery {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [int]$TimeoutSec = 30
  )

  $preStartContext = Get-ServiceRecoveryContext -Config $Config
  $cleanup = $null
  if ($preStartContext.needsStartRecovery) {
    $cleanup = Invoke-ServiceResidualCleanup -Config $Config -TimeoutSec ([Math]::Max(5, [int]$Config.stopTimeoutSeconds))
    if (-not $cleanup.success) {
      $issueMessage = Get-ServiceRecoveryIssueMessage -Config $Config -Context $cleanup.context
      if ([string]::IsNullOrWhiteSpace($issueMessage)) {
        $issueMessage = "Service '$($Config.serviceName)' is stuck stopping and its residual processes could not be cleared."
      }

      throw $issueMessage
    }

    [void](Wait-ForServiceStatus -ServiceName $Config.serviceName -DesiredStatus 'Stopped' -TimeoutSec ([Math]::Max(5, [int]$Config.stopTimeoutSeconds)))
  }

  Invoke-WinSWCommand -Config $Config -Command 'start'
  if (Wait-ForServiceStatus -ServiceName $Config.serviceName -DesiredStatus 'Running' -TimeoutSec $TimeoutSec) {
    return @{
      message           = if ($null -ne $cleanup) { 'Recovered a stuck stop and started the service.' } else { "Service '$($Config.serviceName)' is running." }
      recovered         = ($null -ne $cleanup)
      cleanupAttempted  = ($null -ne $cleanup)
      cleanupResult     = $cleanup
      context           = (Get-ServiceRecoveryContext -Config $Config)
    }
  }

  $timeoutContext = Get-ServiceRecoveryContext -Config $Config
  if ($timeoutContext.needsStartRecovery) {
    $cleanup = Invoke-ServiceResidualCleanup -Config $Config -TimeoutSec ([Math]::Max(5, [int]$Config.stopTimeoutSeconds))
    if ($cleanup.success) {
      Invoke-WinSWCommand -Config $Config -Command 'start'
      if (Wait-ForServiceStatus -ServiceName $Config.serviceName -DesiredStatus 'Running' -TimeoutSec $TimeoutSec) {
        return @{
          message           = 'Recovered a stuck stop and started the service.'
          recovered         = $true
          cleanupAttempted  = $true
          cleanupResult     = $cleanup
          context           = (Get-ServiceRecoveryContext -Config $Config)
        }
      }
    }
  }

  $finalContext = Get-ServiceRecoveryContext -Config $Config
  $issueMessage = Get-ServiceRecoveryIssueMessage -Config $Config -Context $finalContext
  if ([string]::IsNullOrWhiteSpace($issueMessage)) {
    $issueMessage = "Service '$($Config.serviceName)' did not start within $TimeoutSec seconds."
  }

  throw $issueMessage
}

function Restart-ManagedServiceWithRecovery {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [int]$TimeoutSec = 30
  )

  $stopResult = Stop-ManagedServiceWithRecovery -Config $Config -TimeoutSec $TimeoutSec
  $startResult = Start-ManagedServiceWithRecovery -Config $Config -TimeoutSec $TimeoutSec
  $stopRecovered = if ($stopResult -is [System.Collections.IDictionary]) {
    $stopResult.ContainsKey('recovered') -and [bool]$stopResult.recovered
  } else {
    ($null -ne $stopResult) -and ($stopResult.PSObject.Properties.Name -contains 'recovered') -and [bool]$stopResult.recovered
  }
  $startRecovered = if ($startResult -is [System.Collections.IDictionary]) {
    $startResult.ContainsKey('recovered') -and [bool]$startResult.recovered
  } else {
    ($null -ne $startResult) -and ($startResult.PSObject.Properties.Name -contains 'recovered') -and [bool]$startResult.recovered
  }
  $recovered = [bool](
    $stopRecovered -or
    $startRecovered
  )
  return @{
    message = if ($recovered) { 'Recovered a stuck stop and restarted the service.' } else { "Service '$($Config.serviceName)' restarted successfully." }
    recovered = $recovered
    context = (Get-ServiceRecoveryContext -Config $Config)
  }
}

function Get-ServiceActionResultMessage {
  [CmdletBinding()]
  param(
    [AllowNull()]
    $Result,
    [string]$Fallback = $null
  )

  foreach ($item in @($Result)) {
    if ($item -is [System.Collections.IDictionary]) {
      if ($item.Contains('message') -and -not [string]::IsNullOrWhiteSpace("$($item.message)")) {
        return "$($item.message)"
      }

      continue
    }

    if ($null -ne $item -and ($item.PSObject.Properties.Name -contains 'message') -and -not [string]::IsNullOrWhiteSpace("$($item.message)")) {
      return "$($item.message)"
    }
  }

  foreach ($item in @($Result)) {
    if ($item -is [string] -and -not [string]::IsNullOrWhiteSpace($item)) {
      return $item.Trim()
    }
  }

  return $Fallback
}

function Get-ServiceControlTaskFailureMessage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$TaskStatus
  )

  if (-not $TaskStatus.exists) {
    return "Control task '$($TaskStatus.fullTaskName)' is missing. Reinstall the service to restore SYSTEM-backed lifecycle control."
  }

  if (-not $TaskStatus.matches) {
    return "Control task '$($TaskStatus.fullTaskName)' does not match the expected wrapper action. Reinstall the service to restore SYSTEM-backed lifecycle control."
  }

  return $null
}

function Wait-ForServiceControlResult {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop', 'restart')]
    [string]$Action,
    [Parameter(Mandatory = $true)]
    [string]$RequestId,
    [int]$TimeoutSec = 90
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  do {
    $result = $null
    try {
      $result = Read-ServiceControlResult -Config $Config -Action $Action
    } catch {
      $result = $null
    }

    if ($null -ne $result -and [string]::Equals("$($result.requestId)", $RequestId, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $result
    }

    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  $taskInfo = Get-ServiceControlTaskInfo -Config $Config -Action $Action
  return @{
    serviceName  = $Config.serviceName
    action       = $Action
    requestId    = $RequestId
    success      = $false
    busy         = $false
    message      = "Timed out waiting for control task '$($taskInfo.fullTaskName)' to finish. Run doctor.ps1 or reinstall the service if the control bridge is missing."
    error        = "Timed out waiting for control task '$($taskInfo.fullTaskName)' to report completion within $TimeoutSec seconds."
    requestedAt  = $null
    startedAt    = $null
    completedAt  = (Get-Date).ToString('o')
    writtenAt    = (Get-Date).ToString('o')
    origin       = 'interactive'
    requester    = Get-CurrentWindowsIdentityName
  }
}

function Invoke-ServiceControlAction {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop', 'restart')]
    [string]$Action,
    [int]$TimeoutSec = 90
  )

  $taskStatus = Get-ServiceControlTaskStatus -Config $Config -Action $Action
  $failureMessage = Get-ServiceControlTaskFailureMessage -TaskStatus $taskStatus
  if (-not [string]::IsNullOrWhiteSpace($failureMessage)) {
    throw $failureMessage
  }

  $mutex = New-Object System.Threading.Mutex($false, (Get-ServiceControlMutexName -ServiceName $Config.serviceName))
  $hasHandle = $false
  $requestId = [guid]::NewGuid().ToString('N')
  $requestTime = Get-Date
  try {
    try {
      $hasHandle = $mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
      $hasHandle = $true
    }

    if (-not $hasHandle) {
      return @{
        serviceName  = $Config.serviceName
        action       = $Action
        requestId    = $requestId
        success      = $false
        busy         = $true
        message      = 'Another service action is already in progress.'
        error        = 'Another service action is already in progress.'
        requestedAt  = $requestTime.ToString('o')
        startedAt    = $null
        completedAt  = $requestTime.ToString('o')
        writtenAt    = $requestTime.ToString('o')
        origin       = 'interactive'
        requester    = Get-CurrentWindowsIdentityName
      }
    }

    $taskInfo = Get-ServiceControlTaskInfo -Config $Config -Action $Action
    $request = @{
      serviceName = $Config.serviceName
      requestId   = $requestId
      action      = $Action
      origin      = 'interactive'
      requester   = Get-CurrentWindowsIdentityName
      processId   = $PID
      requestedAt = $requestTime.ToString('o')
    }

    if (Test-Path -LiteralPath $taskInfo.resultPath) {
      Remove-Item -LiteralPath $taskInfo.resultPath -Force
    }

    Write-ServiceControlRequest -Config $Config -Action $Action -Request $request | Out-Null
    Write-ServiceControlState -Config $Config -State @{
      serviceName = $Config.serviceName
      action      = $Action
      requestId   = $requestId
      origin      = $request.origin
      requester   = $request.requester
      processId   = $request.processId
      requestedAt = $request.requestedAt
      status      = 'requested'
      success     = $null
      message     = "Queued '$Action' request for SYSTEM control bridge."
      error       = $null
      startedAt   = $null
      completedAt = $null
    } | Out-Null
    Write-ServiceControlAudit -Config $Config -Action $Action -Message "queued request $requestId from $($request.requester)."

    Start-WrapperScheduledTask -TaskInfo $taskInfo | Out-Null
    return (Wait-ForServiceControlResult -Config $Config -Action $Action -RequestId $requestId -TimeoutSec $TimeoutSec)
  } finally {
    if ($hasHandle) {
      try {
        $mutex.ReleaseMutex()
      } catch {
      }
    }

    if ($null -ne $mutex) {
      $mutex.Dispose()
    }
  }
}

function Invoke-ServiceControlTaskAction {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop', 'restart')]
    [string]$Action,
    [string]$Origin = 'task'
  )

  $taskInfo = Get-ServiceControlTaskInfo -Config $Config -Action $Action
  $request = Read-ServiceControlRequest -Config $Config -Action $Action
  if ($null -eq $request -or -not [string]::Equals("$($request.action)", $Action, [System.StringComparison]::OrdinalIgnoreCase)) {
    $request = @{
      serviceName = $Config.serviceName
      requestId   = [guid]::NewGuid().ToString('N')
      action      = $Action
      origin      = $Origin
      requester   = Get-CurrentWindowsIdentityName
      processId   = $PID
      requestedAt = (Get-Date).ToString('o')
    }
  }

  $startedAt = Get-Date
  Write-ServiceControlState -Config $Config -State @{
    serviceName = $Config.serviceName
    action      = $Action
    requestId   = $request.requestId
    origin      = $request.origin
    requester   = $request.requester
    processId   = $request.processId
    requestedAt = $request.requestedAt
    startedAt   = $startedAt.ToString('o')
    completedAt = $null
    status      = 'running'
    success     = $null
    message     = "Running '$Action' through SYSTEM control bridge."
    error       = $null
  } | Out-Null
  Write-ServiceControlAudit -Config $Config -Action $Action -Message "processing request $($request.requestId) from $($request.origin)."

  $message = $null
  $errorMessage = $null
  $success = $false
  try {
    $actionResult = switch ($Action) {
      'start' { Start-ManagedServiceWithRecovery -Config $Config -TimeoutSec 30 }
      'stop' { Stop-ManagedServiceWithRecovery -Config $Config -TimeoutSec 30 }
      'restart' { Restart-ManagedServiceWithRecovery -Config $Config -TimeoutSec 30 }
    }

    $message = Get-ServiceActionResultMessage -Result $actionResult -Fallback "Service action '$Action' completed."
    $success = $true
  } catch {
    $message = $_.Exception.Message
    $errorMessage = $_.Exception.Message
    $success = $false
  }

  $completedAt = Get-Date
  $result = @{
    serviceName  = $Config.serviceName
    action       = $Action
    requestId    = $request.requestId
    success      = $success
    busy         = $false
    message      = $message
    error        = $errorMessage
    requestedAt  = $request.requestedAt
    startedAt    = $startedAt.ToString('o')
    completedAt  = $completedAt.ToString('o')
    writtenAt    = $completedAt.ToString('o')
    origin       = $request.origin
    requester    = $request.requester
  }

  Write-ServiceControlResult -Config $Config -Action $Action -Result $result | Out-Null
  Write-ServiceControlState -Config $Config -State @{
    serviceName = $Config.serviceName
    action      = $Action
    requestId   = $request.requestId
    origin      = $request.origin
    requester   = $request.requester
    processId   = $request.processId
    requestedAt = $request.requestedAt
    startedAt   = $startedAt.ToString('o')
    completedAt = $completedAt.ToString('o')
    status      = if ($success) { 'completed' } else { 'failed' }
    success     = $success
    message     = $message
    error       = $errorMessage
  } | Out-Null
  Write-ServiceControlAudit -Config $Config -Action $Action -Message "$(if ($success) { 'completed' } else { 'failed' }) request $($request.requestId): $message"

  return $result
}

function Invoke-WinSWCommand {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [string]$Command
  )

  $exePath = Resolve-ManagedExecutablePath -Config $Config
  $output = & $exePath $Command 2>&1 | ForEach-Object { "$_" }
  if ($LASTEXITCODE -ne 0) {
    $text = ($output -join [Environment]::NewLine).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
      throw "WinSW command '$Command' failed with exit code $LASTEXITCODE."
    }

    throw "WinSW command '$Command' failed with exit code ${LASTEXITCODE}: $text"
  }
}

function Get-PortListeners {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [int]$Port
  )

  $listeners = @()

  try {
    $connections = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop
    foreach ($connection in $connections) {
      $process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
      $listeners += [pscustomobject]@{
        localAddress = $connection.LocalAddress
        localPort    = $connection.LocalPort
        processId    = $connection.OwningProcess
        processName  = if ($null -ne $process) { $process.ProcessName } else { $null }
      }
    }
  } catch {
    $netstat = netstat -ano -p tcp
    foreach ($line in $netstat) {
      if ($line -match "^\s*TCP\s+(\S+):$Port\s+\S+\s+LISTENING\s+(\d+)\s*$") {
        $processId = [int]$matches[2]
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        $listeners += [pscustomobject]@{
          localAddress = $matches[1]
          localPort    = $Port
          processId    = $processId
          processName  = if ($null -ne $process) { $process.ProcessName } else { $null }
        }
      }
    }
  }

  return @($listeners | Where-Object { $null -ne $_ } | Sort-Object processId -Unique)
}

function Wait-ForPortListeners {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [int]$Port,
    [int]$TimeoutSec = 10
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  do {
    $listeners = @(Get-PortListeners -Port $Port)
    if ($listeners.Count -gt 0) {
      return $listeners
    }

    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  return @()
}

function Invoke-HealthCheck {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Url,
    [int]$TimeoutSec = 8
  )

  try {
    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec
    return @{
      ok         = $true
      statusCode = [int]$response.StatusCode
      body       = $response.Content
      error      = $null
    }
  } catch {
    return @{
      ok         = $false
      statusCode = $null
      body       = $null
      error      = $_.Exception.Message
    }
  }
}

function Get-GatewayConfigValidationIssues {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  $issues = @()
  $gatewayConfigParent = Split-Path -Parent $Config.gatewayConfigPath

  if (-not (Test-Path -LiteralPath $gatewayConfigParent)) {
    $issues += "Gateway config parent directory does not exist: $gatewayConfigParent"
  }

  if (-not (Test-Path -LiteralPath $Config.gatewayConfigPath)) {
    $issues += "Gateway config file does not exist: $($Config.gatewayConfigPath)"
    return [string[]]$issues
  }

  try {
    Get-Content -LiteralPath $Config.gatewayConfigPath -Raw | ConvertFrom-Json | Out-Null
  } catch {
    $issues += "Gateway config file is not valid JSON: $($Config.gatewayConfigPath). $($_.Exception.Message)"
  }

  return [string[]]$issues
}

function Read-RunState {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  $layout = Get-ServiceArtifactLayout -Config $Config
  if (-not (Test-Path -LiteralPath $layout.stateFilePath)) {
    return $null
  }

  return (ConvertTo-Hashtable -InputObject (Get-Content -LiteralPath $layout.stateFilePath -Raw | ConvertFrom-Json))
}

function Write-RunState {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [hashtable]$State
  )

  $layout = Get-ServiceArtifactLayout -Config $Config
  Ensure-Directory -Path $Config.runtimeStateDirectory
  if ($State.ContainsKey('listenerProcessIds')) {
    $State.listenerProcessIds = @(Normalize-RunStateProcessIdList -Value $State.listenerProcessIds)
  }
  Set-Content -LiteralPath $layout.stateFilePath -Value ($State | ConvertTo-Json -Depth 10) -Encoding UTF8
  return $layout.stateFilePath
}

function Update-RunState {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [Parameter(Mandatory = $true)]
    [hashtable]$Patch
  )

  $existing = Read-RunState -Config $Config
  if ($null -eq $existing) {
    $existing = @{}
  }

  foreach ($key in $Patch.Keys) {
    $existing[$key] = $Patch[$key]
  }

  Write-RunState -Config $Config -State $existing | Out-Null
}

function Test-ProcessExists {
  param(
    [int]$ProcessId
  )

  if ($ProcessId -le 0) {
    return $false
  }

  return ($null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue))
}

function Invoke-TaskKill {
  [CmdletBinding()]
  param(
    [int]$ProcessId,
    [switch]$Force,
    [switch]$IncludeChildren = $true
  )

  if ($ProcessId -le 0 -or -not (Test-ProcessExists -ProcessId $ProcessId)) {
    return @{
      attempted = $false
      success   = $true
      exitCode  = 0
      output    = $null
    }
  }

  $arguments = @('/PID', $ProcessId)
  if ($IncludeChildren) {
    $arguments += '/T'
  }
  if ($Force) {
    $arguments += '/F'
  }

  $stdoutPath = Join-Path $env:TEMP "openclaw-taskkill-$([guid]::NewGuid().ToString('N')).out.txt"
  $stderrPath = Join-Path $env:TEMP "openclaw-taskkill-$([guid]::NewGuid().ToString('N')).err.txt"
  try {
    $process = Start-Process `
      -FilePath 'taskkill.exe' `
      -ArgumentList (Join-ProcessArgumentString -Arguments ($arguments | ForEach-Object { "$_" })) `
      -WindowStyle Hidden `
      -Wait `
      -PassThru `
      -RedirectStandardOutput $stdoutPath `
      -RedirectStandardError $stderrPath
    $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
    $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
    $output = (@($stdout, $stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine
    return @{
      attempted = $true
      success   = (($process.ExitCode -eq 0) -or -not (Test-ProcessExists -ProcessId $ProcessId))
      exitCode  = $process.ExitCode
      output    = $output.Trim()
    }
  } finally {
    foreach ($path in @($stdoutPath, $stderrPath)) {
      if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
      }
    }
  }
}

function Stop-ProcessIdWithFallbacks {
  [CmdletBinding()]
  param(
    [int]$ProcessId,
    [switch]$Force,
    [switch]$IncludeChildren
  )

  if ($ProcessId -le 0 -or -not (Test-ProcessExists -ProcessId $ProcessId)) {
    return @{
      processId = $ProcessId
      success   = $true
      method    = 'alreadyExited'
      output    = $null
    }
  }

  $taskKillResult = Invoke-TaskKill -ProcessId $ProcessId -Force:$Force -IncludeChildren:$IncludeChildren
  if (-not (Test-ProcessExists -ProcessId $ProcessId)) {
    return @{
      processId = $ProcessId
      success   = $true
      method    = 'taskkill'
      output    = $taskKillResult.output
    }
  }

  try {
    Stop-Process -Id $ProcessId -Force -ErrorAction Stop
  } catch {
  }

  Start-Sleep -Milliseconds 300
  if (-not (Test-ProcessExists -ProcessId $ProcessId)) {
    return @{
      processId = $ProcessId
      success   = $true
      method    = 'Stop-Process'
      output    = $taskKillResult.output
    }
  }

  try {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
    if ($null -ne $process) {
      [void](Invoke-CimMethod -InputObject $process -MethodName Terminate -Arguments @{ Reason = 0 } -ErrorAction SilentlyContinue)
    }
  } catch {
  }

  Start-Sleep -Milliseconds 300
  return @{
    processId = $ProcessId
    success   = (-not (Test-ProcessExists -ProcessId $ProcessId))
    method    = 'Terminate'
    output    = $taskKillResult.output
  }
}

function Stop-RecordedServiceProcessTree {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config,
    [int]$TimeoutSec = 15
  )

  $initialContext = Get-ServiceRecoveryContext -Config $Config
  $targets = @(Get-ServiceRuntimeTerminationTargets -Context $initialContext)
  if ($targets.Count -eq 0) {
    return $false
  }

  foreach ($target in $targets) {
    [void](Stop-ProcessIdWithFallbacks -ProcessId $target.processId -IncludeChildren:$target.includeChildren)
  }

  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    $currentContext = Get-ServiceRecoveryContext -Config $Config
    if (Test-ServiceRuntimeProcessesStopped -Context $currentContext) {
      return $true
    }

    Start-Sleep -Milliseconds 500
  }

  foreach ($target in @(Get-ServiceRuntimeTerminationTargets -Context (Get-ServiceRecoveryContext -Config $Config))) {
    [void](Stop-ProcessIdWithFallbacks -ProcessId $target.processId -Force -IncludeChildren:$target.includeChildren)
  }
  Start-Sleep -Seconds 2
  return (Test-ServiceRuntimeProcessesStopped -Context (Get-ServiceRecoveryContext -Config $Config))
}

function Remove-GeneratedArtifacts {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Config
  )

  $layout = Get-ServiceArtifactLayout -Config $Config
  if (Test-Path -LiteralPath $layout.generatedDirectory) {
    Remove-Item -LiteralPath $layout.generatedDirectory -Recurse -Force
  }

  if (Test-Path -LiteralPath $layout.stateFilePath) {
    Remove-Item -LiteralPath $layout.stateFilePath -Force
  }
}

function Get-TrayControllerPaths {
  [CmdletBinding()]
  param(
    [hashtable]$Config,
    [string]$ServiceName,
    [string]$RuntimeStateDirectory,
    [string]$LogsDirectory
  )

  $defaultConfig = Get-DefaultServiceConfig
  $resolvedServiceName = if ($null -ne $Config -and -not [string]::IsNullOrWhiteSpace($Config.serviceName)) {
    $Config.serviceName
  } elseif (-not [string]::IsNullOrWhiteSpace($ServiceName)) {
    $ServiceName
  } else {
    $defaultConfig.serviceName
  }

  $resolvedRuntimeStateDirectory = if ($null -ne $Config -and -not [string]::IsNullOrWhiteSpace($Config.runtimeStateDirectory)) {
    Resolve-AbsolutePath -Path $Config.runtimeStateDirectory -BasePath $script:RepoRoot
  } elseif (-not [string]::IsNullOrWhiteSpace($RuntimeStateDirectory)) {
    Resolve-AbsolutePath -Path $RuntimeStateDirectory -BasePath $script:RepoRoot
  } else {
    Resolve-AbsolutePath -Path $defaultConfig.runtimeStateDir -BasePath $script:RepoRoot
  }

  $resolvedLogsDirectory = if ($null -ne $Config -and -not [string]::IsNullOrWhiteSpace($Config.logsDirectory)) {
    Resolve-AbsolutePath -Path $Config.logsDirectory -BasePath $script:RepoRoot
  } elseif (-not [string]::IsNullOrWhiteSpace($LogsDirectory)) {
    Resolve-AbsolutePath -Path $LogsDirectory -BasePath $script:RepoRoot
  } else {
    Resolve-AbsolutePath -Path $defaultConfig.logsDir -BasePath $script:RepoRoot
  }

  return @{
    serviceName           = $resolvedServiceName
    runtimeStateDirectory = $resolvedRuntimeStateDirectory
    logsDirectory         = $resolvedLogsDirectory
    cachePath             = Join-Path $resolvedRuntimeStateDirectory "$resolvedServiceName.tray-state.json"
    logPath               = Join-Path $resolvedLogsDirectory "$resolvedServiceName.tray.log"
  }
}

function Resolve-TrayControllerContext {
  [CmdletBinding()]
  param(
    [string]$ConfigPath,
    [string]$CurrentWindowsIdentityName = (Get-CurrentWindowsIdentityName),
    [switch]$AllowInvalidRemembered
  )

  $selection = Resolve-ServiceConfigSelection -ConfigPath $ConfigPath -AllowInvalidRemembered:$AllowInvalidRemembered
  $context = @{
    selection                 = $selection
    bootstrapConfig           = $null
    config                    = $null
    service                   = $null
    inspectionIdentityContext = $null
    paths                     = Get-TrayControllerPaths -ServiceName $selection.rememberedServiceName
    serviceName               = $null
  }
  $context.serviceName = $context.paths.serviceName

  if ($selection.ContainsKey('invalidReason') -or [string]::IsNullOrWhiteSpace($selection.sourcePath)) {
    return $context
  }

  $bootstrapConfig = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext (Get-ServiceIdentityContext -Mode 'currentUser')
  $service = Get-ServiceDetails -ServiceName $bootstrapConfig.serviceName
  $inspectionIdentityContext = Resolve-InspectionIdentityContext -Config $bootstrapConfig -ServiceDetails $service -CurrentWindowsIdentityName $CurrentWindowsIdentityName
  $config = Get-ServiceConfig -ConfigPath $selection.sourcePath -IdentityContext $inspectionIdentityContext
  $config.configSource = $selection.configSource
  $config.rememberedPath = $selection.rememberedPath

  $context.bootstrapConfig = $bootstrapConfig
  $context.config = $config
  $context.service = $service
  $context.inspectionIdentityContext = $inspectionIdentityContext
  $context.paths = Get-TrayControllerPaths -Config $config
  $context.serviceName = $config.serviceName

  return $context
}

function Read-TrayStateCache {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$CachePath
  )

  if (-not (Test-Path -LiteralPath $CachePath)) {
    return $null
  }

  $text = Get-Content -LiteralPath $CachePath -Raw
  if ([string]::IsNullOrWhiteSpace($text)) {
    return $null
  }

  return (ConvertTo-Hashtable -InputObject ($text | ConvertFrom-Json))
}

function Write-TrayStateCache {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$CachePath,
    [Parameter(Mandatory = $true)]
    [hashtable]$Snapshot
  )

  Ensure-Directory -Path (Split-Path -Parent $CachePath)
  Set-Content -LiteralPath $CachePath -Value ($Snapshot | ConvertTo-Json -Depth 10) -Encoding UTF8
  return $CachePath
}

function New-TrayStatusSnapshot {
  [CmdletBinding()]
  param(
    [string]$ServiceName,
    [string]$DisplayName,
    [bool]$Installed,
    $Service,
    $Health,
    [AllowEmptyCollection()]
    [string[]]$Issues = @(),
    [AllowEmptyCollection()]
    [string[]]$Warnings = @(),
    [ValidateSet('fast', 'deep')]
    [string]$RefreshKind = 'deep',
    [datetime]$ObservedAt = (Get-Date),
    [string]$ConfigSource,
    [string]$ConfigPath,
    [string]$RememberedPath,
    [switch]$IsStale,
    [string]$StaleReason,
    [string]$LastDeepObservedAt,
    [string]$HealthObservedAt,
    [string]$ErrorMessage
  )

  $resolvedServiceName = if ([string]::IsNullOrWhiteSpace($ServiceName)) { 'OpenClaw' } else { $ServiceName }
  $resolvedDisplayName = if ([string]::IsNullOrWhiteSpace($DisplayName)) { $resolvedServiceName } else { $DisplayName }
  $serviceTable = ConvertTo-Hashtable -InputObject $Service
  if ($null -eq $serviceTable) {
    $serviceTable = @{}
  }

  $healthTable = ConvertTo-Hashtable -InputObject $Health
  if ($null -eq $healthTable) {
    $healthTable = @{}
  }

  $issueList = @($Issues | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $warningList = @($Warnings | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $serviceStatus = if ($serviceTable.ContainsKey('status') -and -not [string]::IsNullOrWhiteSpace("$($serviceTable.status)")) {
    "$($serviceTable.status)"
  } else {
    $null
  }
  $hasHealthData = $healthTable.ContainsKey('ok') -and $null -ne $healthTable.ok
  $isHealthy = $hasHealthData -and [bool]$healthTable.ok
  $isPendingStatus = Test-IsPendingServiceStatus -Status $serviceStatus
  $issueSummary = if ($issueList.Count -gt 0) { $issueList[0] } else { $null }
  $warningSummary = if ($warningList.Count -gt 0) { $warningList[0] } else { $null }
  $observedAtIso = $ObservedAt.ToString('o')
  $resolvedLastDeepObservedAt = if ([string]::IsNullOrWhiteSpace($LastDeepObservedAt) -and $RefreshKind -eq 'deep') {
    $observedAtIso
  } else {
    $LastDeepObservedAt
  }
  $resolvedHealthObservedAt = if ([string]::IsNullOrWhiteSpace($HealthObservedAt) -and $hasHealthData -and $RefreshKind -eq 'deep') {
    $observedAtIso
  } else {
    $HealthObservedAt
  }

  if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
    $summary = if ($ErrorMessage -like 'Remembered config path not found:*') { 'Config error' } else { 'Status unavailable' }
    $detail = $ErrorMessage
    $state = 'error'
  } elseif (-not $Installed) {
    $summary = 'Not installed'
    $detail = "$resolvedDisplayName is not installed."
    $state = 'notInstalled'
  } elseif ($serviceStatus -eq 'StopPending') {
    $summary = if ($issueList.Count -gt 0) { 'Stuck stopping' } else { 'Stopping...' }
    $detail = if ($issueList.Count -gt 0) { $issueSummary } else { "$resolvedDisplayName is stopping." }
    $state = 'pending'
  } elseif ($isPendingStatus) {
    $summary = 'Transitioning...'
    $detail = if ($issueList.Count -gt 0) { $issueSummary } else { "$resolvedDisplayName is transitioning ($serviceStatus)." }
    $state = 'pending'
  } elseif ($serviceStatus -ne 'Running') {
    $summary = 'Stopped'
    $detail = "$resolvedDisplayName is installed but not running."
    $state = 'stopped'
  } elseif (-not $hasHealthData) {
    $summary = 'Refreshing...'
    $detail = 'Waiting for a deep refresh.'
    $state = 'loading'
  } elseif (-not $isHealthy) {
    $summary = 'Running with issues'
    $detail = if (-not [string]::IsNullOrWhiteSpace("$($healthTable.error)")) { "$($healthTable.error)" } else { "$resolvedDisplayName is running but unhealthy." }
    $state = 'unhealthy'
  } elseif ($issueList.Count -gt 0) {
    $summary = 'Running with attention needed'
    $detail = $issueSummary
    $state = 'degraded'
  } else {
    $summary = 'Running'
    $detail = "$resolvedDisplayName is healthy."
    $state = 'healthy'
  }

  if ($IsStale) {
    if ([string]::IsNullOrWhiteSpace($StaleReason)) {
      $StaleReason = 'Showing the last known tray status while a refresh is pending.'
    }

    $detail = if ([string]::IsNullOrWhiteSpace($detail)) { $StaleReason } else { "$detail Stale: $StaleReason" }
  }

  $canStart = $Installed -and ($serviceStatus -ne 'Running' -or $serviceStatus -eq 'StopPending') -and [string]::IsNullOrWhiteSpace($ErrorMessage)
  if ($isPendingStatus -and $serviceStatus -ne 'StopPending') {
    $canStart = $false
  }
  $canStop = $Installed -and $serviceStatus -eq 'Running' -and [string]::IsNullOrWhiteSpace($ErrorMessage)
  $canRestart = $canStop
  $tooltipText = "${resolvedDisplayName}: $summary"
  if ($IsStale) {
    $tooltipText = "$tooltipText (stale)"
  }

  return @{
    serviceName         = $resolvedServiceName
    displayName         = $resolvedDisplayName
    observedAt          = $observedAtIso
    refreshKind         = $RefreshKind
    lastDeepObservedAt  = $resolvedLastDeepObservedAt
    state               = $state
    summary             = $summary
    detail              = $detail
    tooltipText         = $tooltipText
    stale               = [bool]$IsStale
    staleReason         = $StaleReason
    config              = @{
      configSource   = $ConfigSource
      sourcePath     = $ConfigPath
      rememberedPath = $RememberedPath
    }
    service             = @{
      installed = $Installed
      status    = $serviceStatus
      name      = if ($serviceTable.ContainsKey('name')) { $serviceTable.name } else { $resolvedServiceName }
      startType = if ($serviceTable.ContainsKey('startType')) { $serviceTable.startType } else { $null }
    }
    health              = @{
      ok         = if ($hasHealthData) { [bool]$healthTable.ok } else { $null }
      statusCode = if ($healthTable.ContainsKey('statusCode')) { $healthTable.statusCode } else { $null }
      body       = if ($healthTable.ContainsKey('body')) { $healthTable.body } else { $null }
      error      = if ($healthTable.ContainsKey('error')) { $healthTable.error } else { $null }
      observedAt = $resolvedHealthObservedAt
      source     = if ($hasHealthData) {
        if ($RefreshKind -eq 'deep') { 'live' } else { 'cache' }
      } else {
        'none'
      }
    }
    actions             = @{
      canStart   = $canStart
      canStop    = $canStop
      canRestart = $canRestart
    }
    issues              = $issueList
    warnings            = $warningList
    issuesSummary       = $issueSummary
    warningsSummary     = $warningSummary
    summaryLine         = if ($issueList.Count -gt 0) {
      $issueSummary
    } elseif ($warningList.Count -gt 0) {
      $warningSummary
    } elseif ($state -eq 'loading') {
      'Refreshing tray status in the background.'
    } else {
      $detail
    }
  }
}

function Set-TrayStatusSnapshotStale {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Snapshot,
    [string]$Reason,
    [ValidateSet('fast', 'deep')]
    [string]$RefreshKind = 'deep',
    [datetime]$ObservedAt = (Get-Date)
  )

  $updated = Copy-Hashtable -InputObject $Snapshot
  $updated.observedAt = $ObservedAt.ToString('o')
  $updated.refreshKind = $RefreshKind
  $updated.stale = $true
  $updated.staleReason = if ([string]::IsNullOrWhiteSpace($Reason)) {
    'Showing the last known tray status while a refresh is pending.'
  } else {
    $Reason
  }

  if (-not [string]::IsNullOrWhiteSpace("$($updated.detail)")) {
    if ("$($updated.detail)" -notlike '*Stale:*') {
      $updated.detail = "$($updated.detail) Stale: $($updated.staleReason)"
    }
  } else {
    $updated.detail = $updated.staleReason
  }

  if (-not [string]::IsNullOrWhiteSpace("$($updated.tooltipText)") -and "$($updated.tooltipText)" -notlike '*(stale)') {
    $updated.tooltipText = "$($updated.tooltipText) (stale)"
  }

  return $updated
}

Export-ModuleMember -Function `
  Clear-RememberedServiceConfigSelection, `
  ConvertTo-Hashtable, `
  Get-CurrentWindowsIdentityName, `
  Get-ServiceControlArtifactPaths, `
  Get-ServiceControlMutexName, `
  Get-ServiceControlTaskFailureMessage, `
  Get-ServiceControlTaskInfo, `
  Get-ServiceControlTaskStatus, `
  Get-ServiceControlTaskStatuses, `
  New-EmptyServiceRestartTaskStatusReport, `
  New-EmptyServiceControlTaskStatusReport, `
  Get-TrayControllerLauncherArguments, `
  Get-TrayControllerLauncherPath, `
  Get-ServiceRestartTaskInfo, `
  Get-ServiceRestartTaskStatus, `
  Get-WrapperProxyStatusReport, `
  Get-TrayControllerLaunchArguments, `
  Get-TrayShortcutPath, `
  Ensure-Directory, `
  Ensure-WinSWBinary, `
  Get-EffectiveServiceAccountMode, `
  New-EmptyWrapperProxyStatusReport, `
  Get-GatewayConfigValidationIssues, `
  Get-PortListeners, `
  Get-RememberedConfigMetadataPath, `
  Get-TrayControllerPaths, `
  New-TrayStatusSnapshot, `
  Get-ExpectedServiceStartName, `
  Get-WindowsPowerShellExecutablePath, `
  Get-ServiceAccountIdentityContext, `
  Get-ServiceArtifactLayout, `
  Get-ServiceConfig, `
  Get-ServiceRecoveryContext, `
  Get-ServiceRecoveryIssueMessage, `
  Get-ServiceDetails, `
  Get-ServiceExecutablePathFromPathName, `
  Get-ServiceIdentityContext, `
  Get-ServiceIdentityReport, `
  Get-ServiceInstallValidationIssues, `
  Get-ServiceInstallLayout, `
  Get-ServiceInstallLayoutFromExecutablePath, `
  Read-TrayStateCache, `
  Resolve-TrayControllerContext, `
  Get-WinSWServiceAccountInfo, `
  Get-WrapperRoot, `
  Invoke-HealthCheck, `
  Invoke-WinSWCommand, `
  Disable-ServiceStartForReinstall, `
  Install-TrayStartupShortcut, `
  Invoke-ServiceControlAction, `
  Invoke-ServiceControlTaskAction, `
  Join-ProcessArgumentString, `
  Register-ServiceRestartTask, `
  Register-ServiceControlTasks, `
  Read-RememberedServiceConfigSelection, `
  Read-ServiceControlRequest, `
  Read-ServiceControlResult, `
  Read-ServiceControlState, `
  Read-RunState, `
  Remove-GeneratedArtifacts, `
  Remove-ServiceControlTasks, `
  Remove-ServiceRestartTask, `
  Remove-TrayStartupShortcut, `
  Render-WinSWServiceXml, `
  Resolve-ManagedExecutablePath, `
  Resolve-OpenClawCommandPath, `
  Resolve-OpenClawLaunchSpec, `
  Resolve-ServiceAccountPlan, `
  Resolve-ServiceConfig, `
  Resolve-ServiceConfigSelection, `
  Resolve-WrapperProxyEnvironmentPlan, `
  Resolve-InspectionIdentityContext, `
  Restart-ManagedServiceWithRecovery, `
  Set-TrayStatusSnapshotStale, `
  Set-WrapperProxyEnvironment, `
  Start-ManagedServiceWithRecovery, `
  Stop-RecordedServiceProcessTree, `
  Stop-ManagedServiceWithRecovery, `
  Test-IsBuiltInServiceAccount, `
  Test-IsCurrentProcessElevated, `
  Test-IsPendingServiceStatus, `
  Test-ServiceAccountMatch, `
  Update-ServiceControlState, `
  Update-RunState, `
  Invoke-ServiceResidualCleanup, `
  Wait-ForServiceRemoval, `
  Wait-ForServiceControlResult, `
  Wait-ForServiceStatus, `
  Wait-ForPortListeners, `
  Write-ServiceControlAudit, `
  Write-ServiceControlRequest, `
  Write-ServiceControlResult, `
  Write-ServiceControlState, `
  Write-TrayStateCache, `
  Write-RememberedServiceConfigSelection, `
  Write-RunState, `
  Write-WinSWServiceXml
