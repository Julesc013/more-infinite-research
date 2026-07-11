function Import-MIRScenarioRegistry {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$TargetProfile
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Validation scenario registry not found: $Path"
  }
  $manifest = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
  if ($manifest.schema -ne 1) {
    throw "Expected validation scenario manifest must use schema 1."
  }

  $names = @($manifest.profiles.($TargetProfile) | ForEach-Object { [string]$_ })
  if ($names.Count -eq 0) {
    throw "Expected validation scenario manifest has no target profile for Factorio $TargetProfile."
  }
  $duplicates = @($names | Group-Object | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name)
  if ($duplicates.Count -gt 0) {
    throw "Validation scenario registry contains duplicate names for target $TargetProfile`: $($duplicates -join ', ')."
  }

  $configurationChangeNames = @(
    "space-age-scripted-runtime-lifecycle",
    "space-age-scripted-runtime-disable-restoration",
    "space-age-scripted-runtime-reenable",
    "space-age-vanilla-family-adoption-config-change"
  )
  $packageNames = @("package-zip-base", "package-zip-space-age")
  $gateGroups = @{
    "static-validation" = "static"
    "package-build" = "package"
    "runtime-state-contract" = "runtime-state"
  }

  $records = foreach ($name in $names) {
    $kind = if ($gateGroups.ContainsKey($name)) {
      "gate"
    } elseif ($packageNames -contains $name) {
      "package"
    } elseif ($configurationChangeNames -contains $name) {
      "configuration-change"
    } else {
      "runtime"
    }
    [pscustomobject]@{
      name = $name
      target_profile = $TargetProfile
      kind = $kind
      gate_group = if ($kind -eq "gate") { $gateGroups[$name] } else { $null }
    }
  }

  [pscustomobject]@{
    schema = 1
    target_profile = $TargetProfile
    records = @($records)
  }
}

function Get-MIRExpectedScenarioNames {
  param([Parameter(Mandatory)]$Registry)
  @($Registry.records | ForEach-Object { [string]$_.name })
}

function Resolve-MIRScenarioDeclaration {
  param(
    [Parameter(Mandatory)]$Registry,
    [Parameter(Mandatory)][string]$ScenarioName,
    [Parameter(Mandatory)]
    [ValidateSet("gate", "runtime", "configuration-change", "package")]
    [string]$Kind,
    [switch]$EnableSpaceAge
  )

  $matches = @($Registry.records | Where-Object name -eq $ScenarioName)
  if ($matches.Count -ne 1) {
    throw "Scenario '$ScenarioName' is not declared exactly once for target $($Registry.target_profile)."
  }
  $record = $matches[0]
  if ($record.kind -ne $Kind) {
    throw "Scenario '$ScenarioName' is declared as kind '$($record.kind)', not '$Kind'."
  }

  $group = if ($Kind -eq "gate") {
    [string]$record.gate_group
  } else {
    Get-MIRValidationScenarioGroup `
      -ScenarioName $ScenarioName `
      -Kind $Kind `
      -EnableSpaceAge:$EnableSpaceAge
  }
  if ([string]::IsNullOrWhiteSpace($group)) {
    throw "Scenario '$ScenarioName' resolved without an evidence group."
  }

  [pscustomobject]@{
    name = [string]$record.name
    target_profile = [string]$record.target_profile
    kind = [string]$record.kind
    group = $group
    surface = if ($EnableSpaceAge) { "space-age" } else { "base" }
  }
}
