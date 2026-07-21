param(
  [string]$Path = "approved-delta\3.1.9-to-3.2.0.json",
  [string]$Candidate = "dist\more-infinite-research_3.2.0.zip",
  [string]$ExpectedSourceCommit = "",
  [switch]$ValidateStructureOnly
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
$artifactPath = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
  throw "Approved-delta artifact is absent: $artifactPath"
}
$artifact = Get-Content -Raw -LiteralPath $artifactPath | ConvertFrom-Json

function Get-MIRDeltaCanonicalJson {
  param($Value)
  return ($Value | ConvertTo-Json -Depth 100 -Compress)
}

function Test-MIRDeltaExactStringAddition {
  param($Before, $After, [string]$ExpectedAdded)
  $beforeValues = @($Before | ForEach-Object { [string]$_ })
  $afterValues = @($After | ForEach-Object { [string]$_ })
  $added = @($afterValues | Where-Object { $beforeValues -notcontains $_ })
  $removed = @($beforeValues | Where-Object { $afterValues -notcontains $_ })
  return $removed.Count -eq 0 -and $added.Count -eq 1 -and $added[0] -eq $ExpectedAdded
}

function Test-MIRDeltaExactEffectRemoval {
  param($Before, $After, [string]$ExpectedRecipe)
  $removed = @($Before | Where-Object { [string]$_.recipe -eq $ExpectedRecipe })
  $retained = @($Before | Where-Object { [string]$_.recipe -ne $ExpectedRecipe })
  return $removed.Count -eq 1 -and
    [string]$removed[0].type -eq "change-recipe-productivity" -and
    [double]$removed[0].change -eq 0.1 -and
    (Get-MIRDeltaCanonicalJson -Value $retained) -eq (Get-MIRDeltaCanonicalJson -Value @($After))
}

function Test-MIRDeltaScienceSet {
  param($Value)
  $rows = @($Value)
  $names = @($rows | ForEach-Object { [string]$_.name } | Sort-Object)
  return $rows.Count -eq 4 -and
    @($rows | Where-Object { [string]$_.type -ne "item" -or [double]$_.amount -ne 1 }).Count -eq 0 -and
    ($names -join "|") -eq "automation-science-pack|chemical-science-pack|logistic-science-pack|production-science-pack"
}

function Test-MIRDeltaSteelTechnology {
  param($Value, [switch]$Native)
  $expectedName = if ($Native) { "steel-plate-productivity" } else { "recipe-prod-research_steel-1" }
  $expectedFormula = if ($Native) { "1.5^L*1000" } else { "8000*2^(L-1)" }
  if ($null -eq $Value -or [string]$Value.name -ne $expectedName -or
    [string]$Value.count_formula -ne $expectedFormula -or [double]$Value.research_time -ne 60 -or
    [string]$Value.maximum_level -ne "infinite" -or $Value.upgrade -ne $true -or
    -not (Test-MIRDeltaScienceSet -Value $Value.science_ingredients)) {
    return $false
  }
  $effects = @($Value.effects)
  if (@($effects | Where-Object {
    [string]$_.type -ne "change-recipe-productivity" -or [double]$_.change -ne 0.1
  }).Count -ne 0) {
    return $false
  }
  $recipes = @($effects | ForEach-Object { [string]$_.recipe } | Sort-Object)
  if ($Native) {
    return ($recipes -join "|") -in @(
      "casting-steel|steel-plate",
      "casting-steel|mir-fixture-adopt-steel-plate|steel-plate"
    )
  }
  return ($recipes -join "|") -eq "steel-plate"
}
if ($artifact.schema -ne 1 -or $artifact.kind -ne "mir-approved-delta") {
  throw "Approved-delta artifact must use schema 1 and kind mir-approved-delta."
}
$expectedBaseline = "D77B3A78DA40CD4FDD4C829A01B5030E59FB593F3387124EF5C438F6A9E8DFCD"
if ($artifact.baseline.version -ne "3.1.9" -or $artifact.baseline.archive_sha256 -ne $expectedBaseline) {
  throw "Approved-delta baseline does not bind the sealed 3.1.9 archive."
}
if ($artifact.current.version -ne "3.2.0" -or [string]::IsNullOrWhiteSpace([string]$artifact.current.archive_sha256)) {
  throw "Approved-delta current side does not bind an exact 3.2.0 archive."
}
if (-not $ValidateStructureOnly) {
  $candidatePath = if ([IO.Path]::IsPathRooted($Candidate)) { $Candidate } else { Join-Path $repo $Candidate }
  if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
    throw "Approved-delta candidate is absent: $candidatePath"
  }
  if ([string]::IsNullOrWhiteSpace($ExpectedSourceCommit)) {
    throw "Approved-delta exact-candidate validation requires -ExpectedSourceCommit."
  }
  $currentCommit = (Get-MIRGitCommit -RepoRoot $repo)
  if ($currentCommit -ne $ExpectedSourceCommit -or (Test-MIRPackageSourceGitDirty -RepoRoot $repo)) {
    throw "Approved-delta exact-candidate validation requires the clean package source at ExpectedSourceCommit."
  }
  $candidateSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidatePath).Hash
  $candidateContentSha = Get-MIRZipContentFingerprint -Path $candidatePath
  if ($candidateContentSha -ne (Get-MIRPackageSourceFingerprint -RepoRoot $repo)) {
    throw "Approved-delta candidate content does not match the package source authority at ExpectedSourceCommit."
  }
  if ([string]$artifact.current.archive_sha256 -ne $candidateSha -or
      [string]$artifact.current.package_content_sha256 -ne $candidateContentSha -or
      [string]$artifact.current.source_commit -ne $ExpectedSourceCommit) {
    throw "Approved-delta current side does not bind the exact candidate, package content, and source authority."
  }
}
if ([string]::IsNullOrWhiteSpace([string]$artifact.exporter.producer_sha256)) {
  throw "Approved-delta exporter does not bind its exact producer fingerprint."
}

$expectedScenarios = @(
  "approved-delta-automatic-family-controls",
  "approved-delta-base",
  "approved-delta-base-continuations",
  "approved-delta-compat-atan",
  "approved-delta-compat-space-age-galore",
  "approved-delta-native-owner-adoption",
  "approved-delta-space-age"
)
$actualScenarios = @($artifact.scenario_evidence.scenario | Sort-Object -Unique)
if (($actualScenarios -join "`n") -ne (($expectedScenarios | Sort-Object) -join "`n")) {
  throw "Approved-delta scenario coverage differs from the governed seven-scenario matrix."
}
$expectedScenarioRows = @{
  "approved-delta-automatic-family-controls" = @{ baseline = 52; current = 53; differences = 28; technology_differences = 1 }
  "approved-delta-base" = @{ baseline = 52; current = 53; differences = 28; technology_differences = 1 }
  "approved-delta-base-continuations" = @{ baseline = 52; current = 53; differences = 28; technology_differences = 1 }
  "approved-delta-compat-atan" = @{ baseline = 52; current = 53; differences = 28; technology_differences = 1 }
  "approved-delta-compat-space-age-galore" = @{ baseline = 70; current = 71; differences = 27; technology_differences = 1 }
  "approved-delta-native-owner-adoption" = @{ baseline = 70; current = 71; differences = 29; technology_differences = 3 }
  "approved-delta-space-age" = @{ baseline = 70; current = 71; differences = 27; technology_differences = 1 }
}
foreach ($scenario in @($artifact.scenario_evidence)) {
  if ([string]::IsNullOrWhiteSpace([string]$scenario.baseline_fingerprint) -or
    [string]::IsNullOrWhiteSpace([string]$scenario.current_fingerprint)) {
    throw "Approved-delta scenario lacks normalized fingerprints: $($scenario.scenario)"
  }
  $expectedRow = $expectedScenarioRows[[string]$scenario.scenario]
  if ($null -eq $expectedRow -or
    [int]$scenario.baseline_technology_count -ne $expectedRow.baseline -or
    [int]$scenario.current_technology_count -ne $expectedRow.current -or
    [int]$scenario.difference_count -ne $expectedRow.differences -or
    [int]$scenario.technology_difference_count -ne $expectedRow.technology_differences) {
    throw "Approved-delta scenario counts differ from the exact reviewed 3.2 transition: $($scenario.scenario)"
  }
}

$differences = @($artifact.differences)
foreach ($difference in $differences) {
  $propertyNames = @($difference.PSObject.Properties.Name)
  foreach ($required in @("field", "before", "after", "reason", "intentional", "migration_impact", "required_evidence")) {
    if ($propertyNames -notcontains $required) { throw "Approved-delta row lacks ${required}: $($difference.field)" }
  }
  if ([string]::IsNullOrWhiteSpace([string]$difference.field) -or
    [string]::IsNullOrWhiteSpace([string]$difference.reason) -or
    [string]::IsNullOrWhiteSpace([string]$difference.migration_impact) -or
    $difference.intentional -isnot [bool] -or
    @($difference.required_evidence).Count -eq 0) {
    throw "Approved-delta row has incomplete disposition evidence: $($difference.field)"
  }
}
$unapproved = @($differences | Where-Object intentional -ne $true)
if ($unapproved.Count -ne 0 -or $artifact.summary.unapproved_count -ne 0 -or $artifact.summary.status -ne "approved") {
  throw "Approved-delta contains review-required differences."
}
if ($artifact.summary.difference_count -ne $differences.Count -or
  $artifact.summary.intentional_count -ne $differences.Count) {
  throw "Approved-delta summary counts differ from its rows."
}
if ($differences.Count -ne 200) {
  throw "Approved-delta difference count differs from the exact reviewed 3.2 transition."
}

$expectedReasonCounts = [ordered]@{
  "Exact package identity and source fingerprint changed between the sealed 3.1.9 baseline and the 3.2 compiler branch." = 5
  "Scenario binds the two exact MIR package versions under comparison." = 7
  "3.2 hardens GenerationPlan authority and target-neutral CompilerEvidence contracts." = 77
  "3.2 publishes compact public coverage and reserves the complete recipe ledger for explicit internal diagnostics." = 49
  "3.2 adds the explicitly reviewed steel productivity stream and its stable startup-setting family." = 42
  "3.2 adds the explicitly reviewed steel productivity stream and stable generated identity." = 4
  "3.2 adds the explicitly reviewed base steel productivity technology." = 4
  "3.2 adopts safe steel recipes into the existing Space Age steel productivity owner." = 3
  "3.2 adds exactly one reviewed steel stream identity for the active base or Space Age ownership model." = 7
  "3.2 removes the reviewed copper scrap-recovery loop from material productivity ownership." = 1
  "3.2 removes the reviewed iron scrap-recovery loop from material productivity ownership." = 1
}
foreach ($entry in $expectedReasonCounts.GetEnumerator()) {
  $count = @($differences | Where-Object reason -eq $entry.Key).Count
  if ($count -ne $entry.Value) {
    throw "Approved-delta disposition count drifted for '$($entry.Key)': expected $($entry.Value), found $count."
  }
}
if (@($differences | Where-Object { -not $expectedReasonCounts.Contains([string]$_.reason) }).Count -ne 0) {
  throw "Approved-delta contains an unknown intentional disposition."
}

$behaviorDifferences = @($differences | Where-Object {
  $_.field -match '\.(technologies|technology_ids|generated_registry|settings)(\.|$)' -or
  $_.field -match '^package\.(runtime_namespaces|migrations)'
})
foreach ($difference in $behaviorDifferences) {
  $path = [string]$difference.field
  if ($path -match '^package\.(runtime_namespaces|migrations)') {
    throw "Approved-delta changes a runtime namespace or migration contract: $path"
  }
  if ($path -match '^scenarios\.[^.]+\.settings\.(ips-[^.]+-research_steel)$') {
    $expectedSettings = @{
      "ips-cost-base-research_steel" = @{ type = "number"; value = 8000 }
      "ips-cost-growth-research_steel" = @{ type = "number"; value = 2 }
      "ips-effect-per-level-research_steel" = @{ type = "number"; value = 10 }
      "ips-enable-research_steel" = @{ type = "boolean"; value = $true }
      "ips-max-level-research_steel" = @{ type = "number"; value = 0 }
      "ips-research-time-research_steel" = @{ type = "number"; value = 60 }
    }
    $setting = $Matches[1]
    if (-not $expectedSettings.ContainsKey($setting) -or $null -ne $difference.before -or
      [string]$difference.after.value_type -ne [string]$expectedSettings[$setting].type -or
      $difference.after.current_value -ne $expectedSettings[$setting].value) {
      throw "Approved-delta contains an unexpected steel setting transition: $path"
    }
    continue
  }
  if ($path -match '^scenarios\.[^.]+\.generated_registry\.recipe-prod-research_steel-1$') {
    if ($null -ne $difference.before -or [string]$difference.after.key -ne "research_steel" -or
      [string]$difference.after.kind -ne "stream" -or [string]$difference.after.name -ne "recipe-prod-research_steel-1") {
      throw "Approved-delta contains an unexpected steel registry transition: $path"
    }
    continue
  }
  if ($path -match '^scenarios\.[^.]+\.technology_ids$') {
    $expectedAdded = if ($path -match '(compat-space-age-galore|native-owner-adoption|space-age)\.technology_ids$') {
      "steel-plate-productivity"
    } else {
      "recipe-prod-research_steel-1"
    }
    if (-not (Test-MIRDeltaExactStringAddition -Before $difference.before -After $difference.after -ExpectedAdded $expectedAdded)) {
      throw "Approved-delta technology identity transition is not the exact reviewed steel addition: $path"
    }
    continue
  }
  if ($path -match '^scenarios\.[^.]+\.technologies\.recipe-prod-research_steel-1$') {
    if ($null -ne $difference.before -or -not (Test-MIRDeltaSteelTechnology -Value $difference.after)) {
      throw "Approved-delta base steel technology differs from its reviewed design: $path"
    }
    continue
  }
  if ($path -match '^scenarios\.[^.]+\.technologies\.steel-plate-productivity$') {
    if ($null -ne $difference.before -or -not (Test-MIRDeltaSteelTechnology -Value $difference.after -Native)) {
      throw "Approved-delta native steel owner differs from its reviewed design: $path"
    }
    continue
  }
  if ($path -eq 'scenarios.approved-delta-native-owner-adoption.technologies.recipe-prod-research_copper-1.effects') {
    if (-not (Test-MIRDeltaExactEffectRemoval -Before $difference.before -After $difference.after -ExpectedRecipe "mir-fixture-scrap-copper-plate-recovery")) {
      throw "Approved-delta copper change is not the exact reviewed scrap-recovery removal."
    }
    continue
  }
  if ($path -eq 'scenarios.approved-delta-native-owner-adoption.technologies.recipe-prod-research_iron-1.effects') {
    if (-not (Test-MIRDeltaExactEffectRemoval -Before $difference.before -After $difference.after -ExpectedRecipe "mir-fixture-scrap-iron-plate-recovery")) {
      throw "Approved-delta iron change is not the exact reviewed scrap-recovery removal."
    }
    continue
  }
  throw "Approved-delta contains an unbounded technology, registry, or setting change: $path"
}
foreach ($scenario in $expectedScenarios) {
  $prefix = "scenarios.$scenario.mod_data_contracts."
  if (-not @($differences.field | Where-Object { $_ -like "$prefix*compiler-evidence*" })) {
    throw "Approved-delta scenario lacks the CompilerEvidence schema transition: $scenario"
  }
  if (-not @($differences.field | Where-Object { $_ -like "$prefix*generation-plan*" })) {
    throw "Approved-delta scenario lacks the GenerationPlan authority transition: $scenario"
  }
  if (-not @($differences.field | Where-Object { $_ -like "$prefix*coverage-report*" })) {
    throw "Approved-delta scenario lacks the compact public coverage transition: $scenario"
  }
}

$binding = if ($ValidateStructureOnly) { "governed artifact structure" } else { "the exact active candidate" }
Write-Host "[ok] MIR approved delta binds $binding, seven exact-package scenarios, $($differences.Count) intentional differences, one reviewed steel identity per scenario, and exact scrap-recovery exclusions."
