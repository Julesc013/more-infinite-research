function Import-MIRScenarioRegistry {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$TargetProfile
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Validation scenario registry not found: $Path"
  }
  $manifest = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
  if ($manifest.schema -ne 2) {
    throw "Expected validation scenario manifest must use schema 2."
  }

  $declared = @($manifest.profiles.($TargetProfile))
  if ($declared.Count -eq 0) {
    throw "Expected validation scenario manifest has no target profile for Factorio $TargetProfile."
  }
  $records = foreach ($entry in $declared) {
    if ($entry -is [string]) {
      throw "Schema-2 scenario declarations must be full records, not bare names: $entry"
    }
    foreach ($field in @("name", "target_profile", "kind", "group", "surface")) {
      if ([string]::IsNullOrWhiteSpace([string]$entry.$field)) {
        throw "Schema-2 scenario declaration is missing '$field'."
      }
    }
    if ([string]$entry.target_profile -ne $TargetProfile) {
      throw "Scenario '$($entry.name)' targets '$($entry.target_profile)', not '$TargetProfile'."
    }
    if ([string]$entry.kind -notin @("gate", "runtime", "configuration-change", "package")) {
      throw "Scenario '$($entry.name)' has unsupported kind '$($entry.kind)'."
    }
    [pscustomobject]@{
      name = [string]$entry.name
      target_profile = [string]$entry.target_profile
      kind = [string]$entry.kind
      group = [string]$entry.group
      surface = [string]$entry.surface
      required_features = @($entry.required_features | ForEach-Object { [string]$_ })
    }
  }
  $names = @($records | ForEach-Object name)
  $duplicates = @($names | Group-Object | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name)
  if ($duplicates.Count -gt 0) {
    throw "Validation scenario registry contains duplicate names for target $TargetProfile`: $($duplicates -join ', ')."
  }

  [pscustomobject]@{
    schema = 2
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

  $group = [string]$record.group
  if ([string]::IsNullOrWhiteSpace($group)) {
    throw "Scenario '$ScenarioName' resolved without an evidence group."
  }

  [pscustomobject]@{
    name = [string]$record.name
    target_profile = [string]$record.target_profile
    kind = [string]$record.kind
    group = $group
    surface = [string]$record.surface
    required_features = @($record.required_features)
  }
}
