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

function Get-MIRDeltaProducerFingerprint {
  $paths = @(
    "scripts/Export-MIRApprovedDelta.ps1",
    "fixtures/compat-matrix/expected-scenarios.json",
    "fixtures/export-approved-delta/data-final-fixes.lua",
    "fixtures/export-approved-delta/info.json",
    "scripts/validation/FactorioProcess.ps1",
    "scripts/validation/PackageIdentity.ps1",
    "scripts/validation/ResultAggregation.ps1",
    "scripts/validation/ScenarioRegistry.ps1",
    "scripts/validation/SettingsOverrides.ps1",
    "scripts/validation/TargetProfiles.ps1"
  )
  $rows = @(
    foreach ($relative in $paths) {
      $file = Join-Path $repo $relative
      $identity = Get-MIRFileContentIdentity -Path $file -RelativePath $relative
      "$relative=$([string]$identity.Sha256)"
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
$isFactorio20Backport = $artifact.baseline.version -eq '2.4.9' -and
  $artifact.current.version -eq '2.5.0' -and $artifact.current.factorio_version -eq '2.0'
if ($isFactorio20Backport) {
  $expectedBaseline = [ordered]@{
    archive = 'B5503F94D04624F65462CC275FB6AA71A8CE93075F732DF498F6D73AD255F978'
    content = '23D992943090BFF487675E9DF8C5C12BFDB1F3018B0BF04C9928265E5DC95255'
    commit = '7ebe93029695bbf809a15a14c6540530738a9e62'
  }
  $expectedCurrent = [ordered]@{
    archive = '65C1610BAE120F135E328583899672E3636EAAD6D946DF104FD045B2D9AB10F1'
    content = '5BBE4D09FD4F65D8A91D2F4AF1664D1C68B846288B9BEF7858162F3F156158F1'
    commit = '493e71a6c883c2e191e1e13c7647cf38a8a8b261'
  }
  if ($artifact.baseline.factorio_version -ne '2.0' -or
      [string]$artifact.baseline.archive_sha256 -ne $expectedBaseline.archive -or
      [string]$artifact.baseline.package_content_sha256 -ne $expectedBaseline.content -or
      [string]$artifact.baseline.source_commit -ne $expectedBaseline.commit) {
    throw 'Approved-delta baseline does not bind the exact published 2.4.9 authority.'
  }
  if ([string]$artifact.current.archive_sha256 -ne $expectedCurrent.archive -or
      [string]$artifact.current.package_content_sha256 -ne $expectedCurrent.content -or
      [string]$artifact.current.source_commit -ne $expectedCurrent.commit -or
      [string]$artifact.current.package_source_commit -ne $expectedCurrent.commit) {
    throw 'Approved-delta current side does not bind the exact P11 2.5.0 package authority.'
  }
  $releaseLedger = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir\releases.json') | ConvertFrom-Json
  $releaseAuthority = $releaseLedger.development.'factorio-2.0'
  $baselineAuthority = $releaseLedger.published_baselines.'factorio-2.0'
  if ([string]$releaseAuthority.package_source_commit -ne $expectedCurrent.commit -or
      [string]$releaseAuthority.archive_sha256 -ne $expectedCurrent.archive -or
      [string]$releaseAuthority.package_content_sha256 -ne $expectedCurrent.content -or
      [string]$baselineAuthority.tag_commit -ne $expectedBaseline.commit -or
      [string]$baselineAuthority.archive_sha256 -ne $expectedBaseline.archive -or
      [string]$baselineAuthority.package_content_sha256 -ne $expectedBaseline.content) {
    throw 'Approved-delta package identities differ from the governed 2.0 release ledger.'
  }
  $qualificationSourceCommit = [string]$artifact.exporter.qualification_source_commit
  if ($qualificationSourceCommit -notmatch '^[0-9a-f]{40}$' -or
      [string]$artifact.exporter.producer_sha256 -ne (Get-MIRDeltaProducerFingerprint) -or
      [string]$artifact.exporter.factorio_binary_version -ne '2.0.77.84539') {
    throw 'Approved-delta producer, qualification source, or Factorio 2.0.77 identity drifted.'
  }
  if (-not $ValidateStructureOnly) {
    $candidatePath = if ([IO.Path]::IsPathRooted($Candidate)) { $Candidate } else { Join-Path $repo $Candidate }
    if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { throw "Approved-delta candidate is absent: $candidatePath" }
    if ([string]::IsNullOrWhiteSpace($ExpectedSourceCommit)) { throw 'Approved-delta exact-candidate validation requires -ExpectedSourceCommit.' }
    $currentCommit = Get-MIRGitCommit -RepoRoot $repo
    if ($currentCommit -ne $ExpectedSourceCommit -or (Test-MIRPackageSourceGitDirty -RepoRoot $repo)) {
      throw 'Approved-delta exact-candidate validation requires the clean package source at ExpectedSourceCommit.'
    }
    & git -C $repo merge-base --is-ancestor $expectedCurrent.commit $qualificationSourceCommit
    if ($LASTEXITCODE -ne 0) { throw 'Approved-delta package source is not an ancestor of its qualification source.' }
    & git -C $repo merge-base --is-ancestor $qualificationSourceCommit $ExpectedSourceCommit
    if ($LASTEXITCODE -ne 0) { throw 'Approved-delta qualification source is not an ancestor of ExpectedSourceCommit.' }
    [string[]]$packageRoots = @(Get-MIRPackageSourceRoots)
    & git -C $repo diff --quiet $expectedCurrent.commit $ExpectedSourceCommit -- @packageRoots
    if ($LASTEXITCODE -ne 0) { throw 'Package-visible source changed after P11 package-source authority.' }
    $candidateSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidatePath).Hash
    $candidateContentSha = Get-MIRZipContentFingerprint -Path $candidatePath
    if ($candidateSha -ne $expectedCurrent.archive -or $candidateContentSha -ne $expectedCurrent.content -or
        $candidateContentSha -ne (Get-MIRPackageSourceFingerprint -RepoRoot $repo)) {
      throw 'Approved-delta does not bind the exact P11 candidate bytes and package source.'
    }
  }

  $expectedScenarios = [ordered]@{
    'approved-delta-automatic-family-controls' = @{ baseline_fp='36AFBCC1A94343322D002124C66522C5CDB901D9345995AFC9A8980B14E834E0'; current_fp='CC4EA2A85B1D7F4D32340240954062E2250BF46989F9569F95F05F7F79A5B768'; baseline=53; current=54; differences=47; technology_differences=2 }
    'approved-delta-base' = @{ baseline_fp='7A5FF8482C287D7FFFBF816BC5A2B8280EA04646EEF236C604B98600FDE6E46E'; current_fp='BF4DB12135B3E7854F5A9A76AB343932C9B4729662C4C6EB48DB4EFCD5DB8E93'; baseline=53; current=54; differences=46; technology_differences=1 }
    'approved-delta-base-continuations' = @{ baseline_fp='7A5FF8482C287D7FFFBF816BC5A2B8280EA04646EEF236C604B98600FDE6E46E'; current_fp='BF4DB12135B3E7854F5A9A76AB343932C9B4729662C4C6EB48DB4EFCD5DB8E93'; baseline=53; current=54; differences=46; technology_differences=1 }
    'approved-delta-compat-atan' = @{ baseline_fp='EB80E8545659B3A6620122EA5C114FA7096AB2E5DF24FC34691549E27FBEC236'; current_fp='4CB9302119F5DBD6B7ADB9C64C6739E3506F3466C25A6B8486ADBE77F03A3FDF'; baseline=53; current=54; differences=46; technology_differences=1 }
    'approved-delta-compat-space-age-galore' = @{ baseline_fp='25120728B97FAFF6BE2A96B9C39F6674EC37D403D486B88CB0C44E4D8A662DE9'; current_fp='FFFCA445BBBF260AE3F0D125BA6F86EFDA25F90456472CCAC12CB5E96D8D10BE'; baseline=69; current=74; differences=59; technology_differences=10 }
    'approved-delta-native-owner-adoption' = @{ baseline_fp='A013B3B7E085BE990C376FD7399AC905057AF925980137F5E2A64B7A07A01805'; current_fp='47BB43C1849AE3E6FED7A8F6DD50BD86AE218ADCE775BB3B3AFD4761485B44C4'; baseline=69; current=74; differences=59; technology_differences=10 }
    'approved-delta-space-age' = @{ baseline_fp='27179CEE0CF70765F84ECD493EB60BD62CABF2D808812DC9B79A94A535D7280B'; current_fp='B0E835A5CC8BFC80A3132CDB4A63EFF397A029765727D1C3983B2CB9F95DF25B'; baseline=69; current=74; differences=59; technology_differences=10 }
  }
  $actualScenarioNames = @($artifact.scenario_evidence.scenario | Sort-Object -Unique)
  if (($actualScenarioNames -join '|') -ne (@($expectedScenarios.Keys | Sort-Object) -join '|')) {
    throw 'Approved-delta scenario coverage differs from the exact seven-scenario 2.5 matrix.'
  }
  foreach ($scenario in @($artifact.scenario_evidence)) {
    $expected = $expectedScenarios[[string]$scenario.scenario]
    if ([string]$scenario.baseline_fingerprint -ne $expected.baseline_fp -or
        [string]$scenario.current_fingerprint -ne $expected.current_fp -or
        [int]$scenario.baseline_technology_count -ne $expected.baseline -or
        [int]$scenario.current_technology_count -ne $expected.current -or
        [int]$scenario.difference_count -ne $expected.differences -or
        [int]$scenario.technology_difference_count -ne $expected.technology_differences) {
      throw "Approved-delta exact scenario authority drifted: $($scenario.scenario)"
    }
  }
  $differences = @($artifact.differences)
  foreach ($difference in $differences) {
    foreach ($required in @('field','before','after','reason','intentional','migration_impact','required_evidence')) {
      if (@($difference.PSObject.Properties.Name) -notcontains $required) { throw "Approved-delta row lacks ${required}: $($difference.field)" }
    }
    if ($difference.intentional -ne $true -or [string]::IsNullOrWhiteSpace([string]$difference.reason) -or
        [string]::IsNullOrWhiteSpace([string]$difference.migration_impact) -or @($difference.required_evidence).Count -eq 0) {
      throw "Approved-delta row is not completely approved: $($difference.field)"
    }
  }
  if ($differences.Count -ne 375 -or [int]$artifact.summary.difference_count -ne 375 -or
      [int]$artifact.summary.intentional_count -ne 375 -or [int]$artifact.summary.unapproved_count -ne 0 -or
      [string]$artifact.summary.status -ne 'approved') {
    throw 'Approved-delta summary differs from the exact reviewed 2.5 transition.'
  }
  $rowsSha = Get-MIRStringSha256 -Value (Get-MIRDeltaCanonicalJson -Value $differences)
  $fieldsSha = Get-MIRStringSha256 -Value (@($differences.field) -join "`n")
  if ($rowsSha -ne '84B9BAB680F15E3B62BDD2FA327275183F07B2CE90129B5C36333BAF41A196EA' -or
      $fieldsSha -ne '731736C4768372582DFCFD886A8F0118472CA7801E007C95667478B5DAB08E2A') {
    throw 'Approved-delta reviewed rows or exact field set drifted.'
  }
  $binding = if ($ValidateStructureOnly) { 'governed artifact structure' } else { 'the exact P11 candidate' }
  Write-Host "[ok] MIR 2.5 approved delta binds $binding, seven exact Factorio 2.0.77 scenarios, and 375 exact intentional differences with zero unknowns."
  return
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
$packageSourceCommit = [string]$releaseAuthority.package_source_commit
if ($packageSourceCommit -notmatch '^[0-9a-f]{40}$' -or
    [string]$artifact.current.source_commit -ne $packageSourceCommit -or
    [string]$artifact.current.package_source_commit -ne $packageSourceCommit) {
  throw "Approved-delta current side does not bind the active release candidate's canonical package-source commit."
}
$qualificationSourceCommit = [string]$artifact.exporter.qualification_source_commit
if ($qualificationSourceCommit -notmatch '^[0-9a-f]{40}$') {
  throw "Approved-delta exporter does not bind a full qualification-source commit."
}
$expectedProducerSha256 = Get-MIRDeltaProducerFingerprint
if ([string]$artifact.exporter.producer_sha256 -ne $expectedProducerSha256) {
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
