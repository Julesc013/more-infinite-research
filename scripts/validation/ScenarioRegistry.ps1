function Import-MIRScenarioRegistry {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$TargetProfile
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Validation scenario registry not found: $Path"
  }
  $manifest = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
  if ($manifest.schema -ne 3) {
    throw "Expected validation scenario manifest must use schema 3."
  }

  $declared = @($manifest.profiles.($TargetProfile))
  if ($declared.Count -eq 0) {
    throw "Expected validation scenario manifest has no target profile for Factorio $TargetProfile."
  }
  $records = foreach ($entry in $declared) {
    if ($entry -is [string]) {
      throw "Schema-3 scenario declarations must be full records, not bare names: $entry"
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
    if ($null -eq $entry.fixtures -or $null -eq $entry.settings -or $null -eq $entry.tags -or $null -eq $entry.assertions) {
      throw "Scenario '$($entry.name)' is missing schema-3 setup, tag, or assertion ownership."
    }
    if ([string]$entry.source_mode -notin @("exact-package", "gate")) {
      throw "Scenario '$($entry.name)' has unsupported source_mode '$($entry.source_mode)'."
    }
    if ([int]$entry.timeout_seconds -le 0) {
      throw "Scenario '$($entry.name)' requires a positive timeout_seconds."
    }
    if (@($entry.assertions).Count -eq 0) {
      throw "Scenario '$($entry.name)' has zero declared assertions."
    }
    [pscustomobject]@{
      name = [string]$entry.name
      target_profile = [string]$entry.target_profile
      kind = [string]$entry.kind
      group = [string]$entry.group
      surface = [string]$entry.surface
      required_features = @($entry.required_features | ForEach-Object { [string]$_ })
      fixtures = @($entry.fixtures | ForEach-Object { [string]$_ })
      settings = $entry.settings
      source_mode = [string]$entry.source_mode
      timeout_seconds = [int]$entry.timeout_seconds
      tags = @($entry.tags | ForEach-Object { [string]$_ })
      isolation = [string]$entry.isolation
      assertions = @($entry.assertions)
    }
  }
  $names = @($records | ForEach-Object name)
  $duplicates = @($names | Group-Object | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name)
  if ($duplicates.Count -gt 0) {
    throw "Validation scenario registry contains duplicate names for target $TargetProfile`: $($duplicates -join ', ')."
  }

  [pscustomobject]@{
    schema = 3
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
    fixtures = @($record.fixtures)
    settings = $record.settings
    source_mode = [string]$record.source_mode
    timeout_seconds = [int]$record.timeout_seconds
    tags = @($record.tags)
    isolation = [string]$record.isolation
    assertions = @($record.assertions)
  }
}

function Select-MIRScenarioRegistry {
  param(
    [Parameter(Mandatory)]$Registry,
    [string[]]$Scenario = @(),
    [string[]]$Group = @(),
    [string[]]$Tag = @()
  )
  $active = $Scenario.Count -gt 0 -or $Group.Count -gt 0 -or $Tag.Count -gt 0
  if (-not $active) { return $Registry }
  $mandatory = @("static-validation", "package-build", "runtime-state-contract")
  $records = @($Registry.records | Where-Object {
    $record = $_
    $mandatory -contains $record.name `
      -or ($Scenario.Count -gt 0 -and $Scenario -contains $record.name) `
      -or ($Group.Count -gt 0 -and $Group -contains $record.group) `
      -or ($Tag.Count -gt 0 -and @($record.tags | Where-Object { $Tag -contains $_ }).Count -gt 0)
  })
  if ($records.Count -eq $mandatory.Count -and ($Scenario.Count -gt 0 -or $Group.Count -gt 0 -or $Tag.Count -gt 0)) {
    throw "Scenario selection matched no executable scenarios."
  }
  [pscustomobject]@{schema = 3; target_profile = $Registry.target_profile; records = $records}
}
