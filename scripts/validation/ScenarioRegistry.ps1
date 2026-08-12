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

function ConvertTo-MIRScenarioCanonicalText {
  param([AllowNull()]$Value)

  if ($null -eq $Value) { return "null" }
  if ($Value -is [Management.Automation.SwitchParameter]) {
    return $(if ([bool]$Value) { "true" } else { "false" })
  }
  if ($Value -is [bool]) { return $(if ($Value) { "true" } else { "false" }) }
  if ($Value -is [string]) { return ($Value | ConvertTo-Json -Compress) }
  if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or
      $Value -is [int64] -or $Value -is [single] -or $Value -is [double] -or
      $Value -is [decimal]) {
    return [string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0}", $Value)
  }
  if ($Value -is [Collections.IDictionary]) {
    $rows = foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
      (ConvertTo-MIRScenarioCanonicalText -Value $key) + ":" +
        (ConvertTo-MIRScenarioCanonicalText -Value $Value[$key])
    }
    return "{" + ($rows -join ",") + "}"
  }
  if ($Value -is [pscustomobject]) {
    $rows = foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
      (ConvertTo-MIRScenarioCanonicalText -Value ([string]$property.Name)) + ":" +
        (ConvertTo-MIRScenarioCanonicalText -Value $property.Value)
    }
    return "{" + ($rows -join ",") + "}"
  }
  if ($Value -is [Collections.IEnumerable]) {
    $rows = foreach ($item in @($Value)) { ConvertTo-MIRScenarioCanonicalText -Value $item }
    return "[" + ($rows -join ",") + "]"
  }
  throw "Scenario environment contains unsupported value type '$($Value.GetType().FullName)'."
}

function Assert-MIRScenarioInvocationMatchesDeclaration {
  param(
    [Parameter(Mandatory)]$Declaration,
    [Parameter(Mandatory)][Collections.IDictionary]$Invocation
  )

  $scenarioName = [string]$Declaration.name
  $actualFixtures = @($Invocation["EnabledFixtureNames"] | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  $expectedFixtures = @($Declaration.fixtures | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  if (($actualFixtures -join "`n") -cne ($expectedFixtures -join "`n")) {
    throw "Scenario '$scenarioName' invocation fixtures differ from its full-record authority. Expected [$($expectedFixtures -join ', ')]; actual [$($actualFixtures -join ', ')]."
  }

  $actualSpaceAge = $Invocation.Contains("EnableSpaceAge") -and [bool]$Invocation["EnableSpaceAge"]
  $expectedSpaceAge = [string]$Declaration.surface -eq "space-age"
  if ($actualSpaceAge -ne $expectedSpaceAge) {
    throw "Scenario '$scenarioName' invocation surface differs from its full-record authority. Expected Space Age=$expectedSpaceAge; actual=$actualSpaceAge."
  }

  $aliases = [ordered]@{
    enabled_base_extensions = "EnabledBaseExtensionKeys"
    enabled_streams = "EnabledStreamKeys"
    disabled_base_extensions = "DisabledBaseExtensionKeys"
    disabled_streams = "DisabledStreamKeys"
  }
  $ignored = @("ScenarioName", "EnabledFixtureNames", "EnableSpaceAge")
  $actualSettings = [ordered]@{}
  foreach ($key in @($Invocation.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
    if ($key -in $ignored) { continue }
    $actualSettings[$key] = $Invocation[$key]
  }
  $expectedSettings = [ordered]@{}
  foreach ($property in @($Declaration.settings.PSObject.Properties | Sort-Object Name)) {
    $settingName = [string]$property.Name
    $canonicalName = if ($aliases.Contains($settingName)) { [string]$aliases[$settingName] } else { $settingName }
    $expectedSettings[$canonicalName] = $property.Value
  }
  $actualText = ConvertTo-MIRScenarioCanonicalText -Value $actualSettings
  $expectedText = ConvertTo-MIRScenarioCanonicalText -Value $expectedSettings
  if ($actualText -cne $expectedText) {
    throw "Scenario '$scenarioName' invocation settings differ from its full-record authority. Expected $expectedText; actual $actualText."
  }
}

function Resolve-MIRScenarioSettingParameterName {
  param([Parameter(Mandatory)][string]$Name)

  switch ($Name) {
    "enabled_base_extensions" { "EnabledBaseExtensionKeys" }
    "enabled_streams" { "EnabledStreamKeys" }
    "disabled_base_extensions" { "DisabledBaseExtensionKeys" }
    "disabled_streams" { "DisabledStreamKeys" }
    default { $Name }
  }
}

function Select-MIRScenarioRegistryForTargetCapabilities {
  param(
    [Parameter(Mandatory)]$Registry,
    [Parameter(Mandatory)]$TargetProfile
  )

  if (-not $TargetProfile.features) {
    throw "Target profile is missing its feature authority."
  }
  $records = @($Registry.records | Where-Object {
    $supported = $true
    foreach ($feature in @($_.required_features | ForEach-Object { [string]$_ })) {
      $property = $TargetProfile.features.PSObject.Properties[$feature]
      if ($null -eq $property) {
        throw "Scenario '$($_.name)' requires unknown target feature '$feature'."
      }
      if ($property.Value -ne $true) { $supported = $false; break }
    }
    $supported
  })
  [pscustomobject]@{
    schema = [int]$Registry.schema
    target_profile = [string]$Registry.target_profile
    records = $records
  }
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
