$script:MIR4TargetDisplayPattern = '^F[0-9]{3}$'
$script:MIR4LegacyTargetPattern = '^f[0-9]{3}$'

function ConvertTo-MIR4TargetKey {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Target)

  if ($Target -cnotmatch '^[Ff][0-9]{3}$') {
    throw "[mir4-target-key] Target must be an F-number such as F210 or F200."
  }
  return $Target.ToUpperInvariant()
}

function ConvertTo-MIR4LegacyTargetKey {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Target)

  return (ConvertTo-MIR4TargetKey -Target $Target).ToLowerInvariant()
}

function New-MIR4TargetKeyProjection {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Target)

  $canonical = ConvertTo-MIR4TargetKey -Target $Target
  return [pscustomobject][ordered]@{
    target = $canonical
    legacy_target = $canonical.ToLowerInvariant()
    distribution_target_code = $canonical.Substring(1, 3)
  }
}
