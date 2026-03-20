$script:IsLegacyPester = ((Get-Module Pester).Version.Major -lt 4)

function Assert-Equal {
  param(
    $Actual,
    $Expected
  )

  if ($script:IsLegacyPester) {
    $Actual | Should Be $Expected
  } else {
    $Actual | Should -Be $Expected
  }
}

function Assert-MatchPattern {
  param(
    $Actual,
    [string]$Pattern
  )

  if ($script:IsLegacyPester) {
    $Actual | Should Match $Pattern
  } else {
    $Actual | Should -Match $Pattern
  }
}
