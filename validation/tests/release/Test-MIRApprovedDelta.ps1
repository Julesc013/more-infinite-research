param(
  [string]$Path = "",
  [string]$Candidate = "",
  [string]$ExpectedSourceCommit = "",
  [switch]$ValidateStructureOnly
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $MirLegacyScriptRoot "..")).Path
. (Join-Path $repo "tools\lib\validation\PackageIdentity.ps1")
. (Join-Path $repo "tools\lib\control\Core.ps1")
. (Join-Path $repo "tools\lib\control\Executor.ps1")
$activeVersion = [string](Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json).version
$defaultDeltaByVersion = @{
  "3.2.2" = ".mir\releases\deltas\3.2.1-to-3.2.2.json"
  "3.2.5" = ".mir\releases\deltas\3.2.3-to-3.2.5.json"
}
$releaseRecordRoot = Resolve-MIRCPPathId -RepoRoot $repo -Id "releases.records"
$activeReleasePath = Join-Path $repo (Join-Path $releaseRecordRoot "$activeVersion.json")
if (Test-Path -LiteralPath $activeReleasePath -PathType Leaf) {
  $activeRelease = Get-Content -Raw -LiteralPath $activeReleasePath | ConvertFrom-Json
  if ([string]$activeRelease.state -in @("planned", "source-frozen", "package-built")) {
    if ($null -ne $activeRelease.proofs.PSObject.Properties["approved_delta"] -or
        @($activeRelease.remaining_obligations | ForEach-Object { [string]$_ }) -notcontains "focused-qualification") {
      throw "A pre-qualification release must not claim approved-delta proof and must retain focused qualification."
    }
    Write-Host "[ok] active candidate is pre-qualification; approved-delta evidence remains explicitly pending."
    exit 0
  }
}
if ([string]::IsNullOrWhiteSpace($Path)) {
  if (-not $defaultDeltaByVersion.ContainsKey($activeVersion)) {
    throw "No default approved-delta artifact is registered for MIR $activeVersion."
  }
  $Path = [string]$defaultDeltaByVersion[$activeVersion]
}
if ([string]::IsNullOrWhiteSpace($Candidate)) {
  $Candidate = "dist\more-infinite-research_$activeVersion.zip"
}
if ($activeVersion -eq "3.2.2") {
  $arguments = @{
    RepoRoot = $repo
    Path = ".mir\releases\deltas\3.2.1-to-3.2.2.json"
    Candidate = $Candidate
    ExpectedSourceCommit = $ExpectedSourceCommit
    ValidateStructureOnly = $ValidateStructureOnly
  }
  & (Join-Path $repo "validation\tests\release\Test-MIRApprovedPatchDelta.ps1") @arguments
  exit $LASTEXITCODE
}
$artifactPath = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
  throw "Approved-delta artifact is absent: $artifactPath"
}
$artifact = Get-Content -Raw -LiteralPath $artifactPath | ConvertFrom-Json

if ($activeVersion -eq "3.2.5") {
  if ([int]$artifact.schema -ne 1 -or [string]$artifact.kind -ne "mir-control-plane-v5-approved-patch-delta") {
    throw "MIR 3.2.5 approved delta must use the native Control Plane v5 patch-delta schema."
  }
  $baselinePath = Join-Path $repo "dist\more-infinite-research_3.2.3.zip"
  $candidatePath = if ([IO.Path]::IsPathRooted($Candidate)) { $Candidate } else { Join-Path $repo $Candidate }
  foreach ($requiredArchive in @($baselinePath, $candidatePath)) {
    if (-not (Test-Path -LiteralPath $requiredArchive -PathType Leaf)) {
      throw "MIR 3.2.5 approved-delta archive is absent: $requiredArchive"
    }
  }
  $policies = @(Get-MIRCPNativePatchDeltaPolicy -Target "2.1" -FromVersion "3.2.3" -ToVersion "3.2.5" -CandidateId "C32" -RepoRoot $repo)
  if ($policies.Count -ne 1 -or [string]$policies[0].id -ne "c32-unified-cost-compatibility-v1") {
    throw "MIR 3.2.5 approved-delta policy selection is not exact."
  }
  $policy = $policies[0]
  $baseline = Get-MIRCPZipPackageObservation -Path $baselinePath
  $current = Get-MIRCPZipPackageObservation -Path $candidatePath
  $baselineByPath = @{}
  foreach ($file in @($baseline.files)) { $baselineByPath[[string]$file.path] = [string]$file.sha256 }
  $currentByPath = @{}
  foreach ($file in @($current.files)) { $currentByPath[[string]$file.path] = [string]$file.sha256 }
  $added = @($currentByPath.Keys | Where-Object { -not $baselineByPath.ContainsKey($_) } | Sort-Object)
  $removed = @($baselineByPath.Keys | Where-Object { -not $currentByPath.ContainsKey($_) } | Sort-Object)
  $changed = @($currentByPath.Keys | Where-Object { $baselineByPath.ContainsKey($_) -and $baselineByPath[$_] -cne $currentByPath[$_] } | Sort-Object)
  $policyPath = Join-Path $repo ".mir\control-plane\approved-delta-policies.json"
  $portablePolicySha256 = Get-MIRCPPortableTextSha256 -Path $policyPath
  $bindings = @(
    [pscustomobject]@{ id = "policy"; passed = ([string]$artifact.policy.id -eq [string]$policy.id -and [string]$artifact.policy.authority_digest_policy -eq "utf8-lf" -and [string]$artifact.policy.authority_sha256 -eq $portablePolicySha256) },
    [pscustomobject]@{ id = "baseline"; passed = ([string]$baseline.archive_sha256 -eq [string]$policy.baseline.archive_sha256 -and [string]$baseline.content_sha256 -eq [string]$policy.baseline.content_sha256 -and [int64]$baseline.bytes -eq [int64]$policy.baseline.bytes -and [int]$baseline.entries -eq [int]$policy.baseline.entries) },
    [pscustomobject]@{ id = "candidate"; passed = ([string]$current.archive_sha256 -eq [string]$policy.candidate.archive_sha256 -and [string]$current.content_sha256 -eq [string]$policy.candidate.content_sha256 -and [int64]$current.bytes -eq [int64]$policy.candidate.bytes -and [int]$current.entries -eq [int]$policy.candidate.entries) },
    [pscustomobject]@{ id = "release-record"; passed = ([string]$activeRelease.candidate_id -eq "C32" -and [string]$activeRelease.package.source_commit -eq [string]$policy.candidate.source_commit -and [string]$activeRelease.package.archive_sha256 -eq [string]$current.archive_sha256 -and [string]$activeRelease.package.content_sha256 -eq [string]$current.content_sha256) },
    [pscustomobject]@{ id = "artifact-observation"; passed = ([string]$artifact.observation.baseline.archive_sha256 -eq [string]$baseline.archive_sha256 -and [string]$artifact.observation.current.archive_sha256 -eq [string]$current.archive_sha256 -and [string]$artifact.observation.current.source_commit -eq [string]$policy.candidate.source_commit) },
    [pscustomobject]@{ id = "added-paths"; passed = (Test-MIRCPExactPathSet -Expected @($policy.allowed_added_paths) -Actual $added) },
    [pscustomobject]@{ id = "removed-paths"; passed = (Test-MIRCPExactPathSet -Expected @($policy.allowed_removed_paths) -Actual $removed) },
    [pscustomobject]@{ id = "changed-paths"; passed = (Test-MIRCPExactPathSet -Expected @($policy.allowed_changed_paths) -Actual $changed) },
    [pscustomobject]@{ id = "artifact-added-paths"; passed = (Test-MIRCPExactPathSet -Expected $added -Actual @($artifact.observation.delta.added)) },
    [pscustomobject]@{ id = "artifact-removed-paths"; passed = (Test-MIRCPExactPathSet -Expected $removed -Actual @($artifact.observation.delta.removed)) },
    [pscustomobject]@{ id = "artifact-changed-paths"; passed = (Test-MIRCPExactPathSet -Expected $changed -Actual @($artifact.observation.delta.changed)) },
    [pscustomobject]@{ id = "evaluation"; passed = ([string]$artifact.evaluation.status -eq "approved" -and [int]$artifact.evaluation.unapproved_count -eq 0 -and @($artifact.evaluation.predicates | Where-Object { -not [bool]$_.passed }).Count -eq 0) }
  )
  $failedBindings = @($bindings | Where-Object { -not [bool]$_.passed })
  if ($failedBindings.Count -gt 0) {
    throw "MIR 3.2.5 native approved delta failed exact bindings: $(@($failedBindings.id) -join ', ')."
  }
  if (-not $ValidateStructureOnly) {
    if ([string]::IsNullOrWhiteSpace($ExpectedSourceCommit)) {
      throw "Approved-delta exact-candidate validation requires -ExpectedSourceCommit."
    }
    $currentCommit = Get-MIRGitCommit -RepoRoot $repo
    if ($currentCommit -ne $ExpectedSourceCommit -or (Test-MIRPackageSourceGitDirty -RepoRoot $repo)) {
      throw "Approved-delta exact-candidate validation requires the clean qualification source at ExpectedSourceCommit."
    }
    & git -C $repo merge-base --is-ancestor ([string]$policy.candidate.source_commit) $ExpectedSourceCommit
    if ($LASTEXITCODE -ne 0) { throw "Approved-delta package source is not an ancestor of the qualification source." }
    [string[]]$packageRoots = @(Get-MIRPackageSourceRoots)
    & git -C $repo diff --quiet ([string]$policy.candidate.source_commit) $ExpectedSourceCommit -- @packageRoots
    if ($LASTEXITCODE -ne 0) { throw "Package-visible source changed after the approved-delta package authority." }
  }
  Write-Host "[ok] MIR 3.2.5 approved delta binds exact C32 bytes and $($added.Count + $removed.Count + $changed.Count) governed package-path differences with zero unapproved rows."
  exit 0
}

function Get-MIRDeltaCanonicalJson {
  param($Value)
  return ($Value | ConvertTo-Json -Depth 100 -Compress)
}

function Get-MIRDeltaProducerFingerprint {
  $paths = @(
    "scripts/Export-MIRApprovedDelta.ps1",
    "validation/scenarios/runtime.json",
    "fixtures/export-approved-delta/data-final-fixes.lua",
    "fixtures/export-approved-delta/info.json",
    "tools/lib/validation/FactorioProcess.ps1",
    "tools/lib/validation/PackageIdentity.ps1",
    "tools/lib/validation/ResultAggregation.ps1",
    "tools/lib/validation/ScenarioRegistry.ps1",
    "tools/lib/validation/SettingsOverrides.ps1",
    "tools/lib/validation/TargetProfiles.ps1"
  )
  $rows = @(
    foreach ($relative in $paths) {
      $file = Join-Path $repo $relative
      "$relative=$((Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash)"
    }
  )
  return Get-MIRStringSha256 -Value ($rows -join "`n")
}

function Test-MIRDeltaTechnologyCatalogAddition {
  param($Difference)

  $path = [string]$Difference.field
  $after = $Difference.after
  if ($null -ne $Difference.before -or
      $path -notmatch '^scenarios\.[^.]+\.mod_data_contracts\.(?<catalog>more-infinite-research-technology-catalog(?:-internal)?)$' -or
      [string]$after.contract_shape.kind -ne "object") {
    return $false
  }
  $actualFields = @($after.contract_shape.fields.PSObject.Properties.Name | Sort-Object)
  if ($Matches.catalog -eq "more-infinite-research-technology-catalog") {
    $expectedFields = @(
      "catalog_fingerprint", "counts", "kind", "provider_summary", "public_fingerprint",
      "reason_histogram", "samples", "schema", "selected", "technology_catalog_schema", "truncation"
    ) | Sort-Object
    return [string]$after.data_type -eq "more-infinite-research.technology-catalog-public" -and
      [int]$after.schema -eq 1 -and
      ($actualFields -join "|") -eq ($expectedFields -join "|")
  }
  $expectedFields = @(
    "alternative_qualifications", "base_candidates", "candidate_catalog_fingerprint", "candidates",
    "catalog_fingerprint", "compilation_plan_fingerprint", "context_fingerprint", "current_selections",
    "generation_plan_fingerprint", "mutation_authority", "phase", "preselection_catalog_fingerprint",
    "qualification_catalog_fingerprint", "qualifications", "schema", "selection_authority",
    "selection_fingerprint"
  ) | Sort-Object
  return [string]$after.data_type -eq "more-infinite-research.technology-catalog-v3-internal" -and
    [int]$after.schema -eq 3 -and
    ($actualFields -join "|") -eq ($expectedFields -join "|")
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
$releaseLedger = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\releases.json") | ConvertFrom-Json
$releaseAuthority = $releaseLedger.development."factorio-2.1"
$activePackageSourceCommit = [string]$releaseAuthority.package_source_commit
$artifactPackageSourceCommit = [string]$artifact.current.package_source_commit
$artifactBindsActiveCandidate = $activePackageSourceCommit -match '^[0-9a-f]{40}$' -and
  [string]$artifact.current.source_commit -eq $activePackageSourceCommit -and
  $artifactPackageSourceCommit -eq $activePackageSourceCommit
$historicalStructureCheck = $ValidateStructureOnly -and
  [string]$releaseAuthority.approved_delta -eq "pending" -and
  $activePackageSourceCommit -match '^[0-9a-f]{40}$' -and
  [string]$artifact.current.source_commit -match '^[0-9a-f]{40}$' -and
  $artifactPackageSourceCommit -match '^[0-9a-f]{40}$' -and
  $artifactPackageSourceCommit -ne $activePackageSourceCommit
if (-not $artifactBindsActiveCandidate -and -not $historicalStructureCheck) {
  throw "Approved-delta current side does not bind the active release candidate's canonical package-source commit."
}
$packageSourceCommit = $artifactPackageSourceCommit
$qualificationSourceCommit = [string]$artifact.exporter.qualification_source_commit
if ($qualificationSourceCommit -notmatch '^[0-9a-f]{40}$') {
  throw "Approved-delta exporter does not bind a full qualification-source commit."
}
$expectedProducerSha256 = Get-MIRDeltaProducerFingerprint
if (-not $historicalStructureCheck -and [string]$artifact.exporter.producer_sha256 -ne $expectedProducerSha256) {
  throw "Approved-delta exporter fingerprint differs from the current governed producer."
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
  & git -C $repo merge-base --is-ancestor $packageSourceCommit $qualificationSourceCommit
  if ($LASTEXITCODE -ne 0) {
    throw "Approved-delta package source is not an ancestor of its qualification source."
  }
  & git -C $repo merge-base --is-ancestor $qualificationSourceCommit $ExpectedSourceCommit
  if ($LASTEXITCODE -ne 0) {
    throw "Approved-delta qualification source is not an ancestor of ExpectedSourceCommit."
  }
  [string[]]$packageRoots = @(Get-MIRPackageSourceRoots)
  & git -C $repo diff --quiet $packageSourceCommit $ExpectedSourceCommit -- @packageRoots
  if ($LASTEXITCODE -ne 0) {
    throw "Package-visible source changed after approved-delta package-source authority."
  }
  $candidateSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidatePath).Hash
  $candidateContentSha = Get-MIRZipContentFingerprint -Path $candidatePath
  if ($candidateContentSha -ne (Get-MIRPackageSourceFingerprint -RepoRoot $repo)) {
    throw "Approved-delta candidate content does not match the package source authority at ExpectedSourceCommit."
  }
  if ([string]$artifact.current.archive_sha256 -ne $candidateSha -or
      [string]$artifact.current.package_content_sha256 -ne $candidateContentSha -or
      [string]$releaseAuthority.archive_sha256 -ne $candidateSha -or
      [string]$releaseAuthority.package_content_sha256 -ne $candidateContentSha -or
      [string]$releaseAuthority.package_source_sha256 -ne $candidateContentSha) {
    throw "Approved-delta current side does not bind the exact candidate, package content, and source authority."
  }
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
  "approved-delta-automatic-family-controls" = @{ baseline = 52; current = 53; differences = 30; technology_differences = 1 }
  "approved-delta-base" = @{ baseline = 52; current = 53; differences = 30; technology_differences = 1 }
  "approved-delta-base-continuations" = @{ baseline = 52; current = 53; differences = 30; technology_differences = 1 }
  "approved-delta-compat-atan" = @{ baseline = 52; current = 53; differences = 30; technology_differences = 1 }
  "approved-delta-compat-space-age-galore" = @{ baseline = 70; current = 71; differences = 29; technology_differences = 1 }
  "approved-delta-native-owner-adoption" = @{ baseline = 70; current = 71; differences = 31; technology_differences = 3 }
  "approved-delta-space-age" = @{ baseline = 70; current = 71; differences = 29; technology_differences = 1 }
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
if ($differences.Count -ne 221) {
  throw "Approved-delta difference count differs from the exact reviewed 3.2 transition."
}

$expectedReasonCounts = [ordered]@{
  "Exact package identity and source fingerprint changed between the sealed 3.1.9 baseline and the 3.2 compiler branch." = 12
  "Scenario binds the two exact MIR package versions under comparison." = 7
  "3.2 hardens GenerationPlan authority and target-neutral CompilerEvidence contracts." = 77
  "3.2 adds bounded public and explicit internal TechnologyCatalog evidence contracts." = 14
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
  $catalogRows = @($differences | Where-Object { $_.field -like "$prefix*technology-catalog*" })
  if ($catalogRows.Count -ne 2 -or
      @($catalogRows | Where-Object { -not (Test-MIRDeltaTechnologyCatalogAddition -Difference $_) }).Count -ne 0) {
    throw "Approved-delta scenario lacks the exact public/internal TechnologyCatalog transition: $scenario"
  }
}

$binding = if ($ValidateStructureOnly) { "governed artifact structure" } else { "the exact active candidate" }
Write-Host "[ok] MIR approved delta binds $binding, seven exact-package scenarios, $($differences.Count) intentional differences, one reviewed steel identity per scenario, and exact scrap-recovery exclusions."
