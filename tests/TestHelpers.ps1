function Assert-Equal {
  param(
    $Actual,
    $Expected
  )

  if ($Actual -ne $Expected) {
    throw "Expected '$Expected' but got '$Actual'."
  }
}

function Assert-MatchPattern {
  param(
    $Actual,
    [string]$Pattern
  )

  if ($Actual -notmatch $Pattern) {
    throw "Expected '$Actual' to match pattern '$Pattern'."
  }
}
