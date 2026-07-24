param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$BudgetsPath = ".mir\performance-budgets.json",
  [string]$PerformancePolicyPath = ".mir\performance.yml",
  [string]$ValidationSummaryPath = "",
  [string]$MediumPackSummaryPath = "",
  [string]$LargePackSummaryPath = "",
  [string]$OutputPath = "",
  [switch]$ValidateManifestOnly
)

$ErrorActionPreference = "Stop"

function Resolve-MIRPerformancePath {
  param([Parameter(Mandatory)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return (Join-Path $RepoRoot $Path)
}

$resolvedBudgetsPath = Resolve-MIRPerformancePath -Path $BudgetsPath
$resolvedPerformancePolicyPath = Resolve-MIRPerformancePath -Path $PerformancePolicyPath
$manifest = Get-Content -Raw -LiteralPath $resolvedBudgetsPath | ConvertFrom-Json
if ($manifest.schema -ne 2) { throw "Performance budget manifest must use schema 2." }
$budgets = @($manifest.budgets)
if ($budgets.Count -eq 0) { throw "Performance budget manifest contains no budgets." }
$regressionLanes = @($manifest.regression_lanes)
if ($regressionLanes.Count -eq 0) { throw "Performance budget manifest contains no regression lanes." }
$compilerStageBudgets = @($manifest.compiler_stage_budgets)
$compilerCounterBounds = @($manifest.compiler_counter_bounds)
if (($compilerStageBudgets.id -join ",") -ne "recipe-risk-facts,provider-discovery,stream-compiler") {
  throw "Performance budget manifest omits the governed C6 compiler stages."
}
foreach ($budget in $compilerStageBudgets) {
  if ([string]::IsNullOrWhiteSpace([string]$budget.phase) -or [double]$budget.max_seconds -le 0) {
    throw "Compiler stage performance budget is invalid: $($budget.id)"
  }
}
foreach ($bound in $compilerCounterBounds) {
  if ([string]::IsNullOrWhiteSpace([string]$bound.counter) -or [int]$bound.maximum -le 0) {
    throw "Compiler counter bound is invalid: $($bound.id)"
  }
}

$requiredIds = @(
  "base", "space-age", "scoped-caps-off", "scoped-caps-on", "diagnostics-off",
  "diagnostics-on", "medium-pack", "large-pack", "large-synthetic-graph", "large-synthetic-recipes", "full-matrix"
)
$duplicates = @($budgets | Group-Object id | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name)
if ($duplicates.Count -gt 0) { throw "Duplicate performance budget IDs: $($duplicates -join ', ')." }
foreach ($requiredId in $requiredIds) {
  if (@($budgets | Where-Object id -eq $requiredId).Count -ne 1) {
    throw "Performance budget '$requiredId' is not declared exactly once."
  }
}
foreach ($budget in $budgets) {
  if ([double]$budget.max_seconds -le 0) { throw "Performance budget '$($budget.id)' must be positive." }
  if ([string]::IsNullOrWhiteSpace([string]$budget.key)) { throw "Performance budget '$($budget.id)' has no source key." }
}
foreach ($lane in $regressionLanes) {
  if ([string]::IsNullOrWhiteSpace([string]$lane.id) -or [double]$lane.maximum_regression_percent -ne 20 -or
      [double]$lane.absolute_noise_allowance_seconds -lt 0) {
    throw "Performance regression lane is invalid: $($lane.id)"
  }
}

$performancePolicy = Get-Content -Raw -LiteralPath $resolvedPerformancePolicyPath
foreach ($requiredPolicySnippet in @(
  'release: 3.2.0',
  'qualified_baseline: "3.1.9"',
  'maximum_regression_percent: 20',
  'witness_node_limit: 64'
)) {
  if ($performancePolicy -notmatch [regex]::Escape($requiredPolicySnippet)) {
    throw "Performance policy is missing '$requiredPolicySnippet'."
  }
}
$requiredTelemetryCounters = @(
  "recipes", "technologies", "effects", "graph_edges", "graph_components", "cyclic_components",
  "recipe_index_scans", "recipe_fact_copies", "candidate_operations", "accepted_operations",
  "rejected_operations", "diagnostic_rows", "generation_plan_rows", "generation_plan_public_bytes",
  "generation_plan_internal_bytes", "technology_design_count", "technology_design_canonical_bytes",
  "coverage_rows", "coverage_public_bytes", "coverage_internal_bytes", "context_state_keys",
  "context_snapshot_bytes", "technology_closure_cache_entries", "technology_closure_cached_nodes",
  "sanitation_scanned_technologies", "sanitation_scanned_effects", "recipe_risk_facts",
  "recipe_hard_risk_count", "recipe_review_risk_count", "provider_candidates",
  "provider_cardinality_review_required", "provider_review_required", "family_members", "stream_rows",
  "technology_catalog_candidates", "technology_catalog_alternatives", "technology_catalog_canonical_bytes",
  "technology_catalog_public_bytes", "technology_catalog_internal_bytes", "compiler_evidence_public_bytes",
  "technology_graph_parity_rows", "snapshot_prototype_bytes", "snapshot_deep_copies",
  "snapshot_canonicalization_passes", "snapshot_construction_milliseconds", "snapshot_peak_memory_bytes",
  "input_snapshot_bytes", "qualification_snapshot_bytes", "snapshot_reused_domains", "snapshot_copied_domains",
  "qualification_snapshot_construction_milliseconds", "qualification_peak_memory_bytes",
  "compiler_total_milliseconds", "public_artifact_total_bytes", "fingerprint_calls",
  "canonicalization_calls", "canonical_bytes_total", "canonical_serializations_over_one_mib",
  "maximum_canonical_bytes", "trusted_record_registrations", "trusted_untrusted_verifications",
  "trusted_assertions", "trusted_rejected_assertions", "trusted_assertion_canonicalizations",
  "catalog_snapshot_count", "full_record_copy_count", "technology_design_full_copies",
  "gate_deep_verifications", "technology_design_deep_verifications",
  "safety_qualification_deep_verifications", "technology_candidate_deep_verifications",
  "technology_catalog_deep_verifications", "transformation_operation_deep_verifications",
  "transformation_plan_deep_verifications"
)
$requiredTelemetryPhases = @(
  "snapshot", "recipe_risk_facts", "provider_discovery", "stream_compiler", "graph", "planning", "postconditions"
)
foreach ($name in @($requiredTelemetryCounters + $requiredTelemetryPhases)) {
  if ($performancePolicy -notmatch "(?m)^\s*-\s+$([regex]::Escape($name))\s*$") {
    throw "Performance policy is missing required telemetry name '$name'."
  }
}
$requiredCounterBudgetIds = @(
  "initial-snapshot-milliseconds", "qualification-snapshot-milliseconds", "compiler-total-milliseconds",
  "snapshot-peak-memory", "qualification-peak-memory", "input-snapshot-bytes",
  "qualification-snapshot-bytes", "public-artifact-total-bytes"
)
foreach ($id in $requiredCounterBudgetIds) {
  if (@($compilerCounterBounds | Where-Object id -eq $id).Count -ne 1) {
    throw "Compiler performance counter budget is missing: $id"
  }
}
$telemetrySource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\report\compiler_telemetry.lua")
foreach ($name in $requiredTelemetryCounters) {
  if ($telemetrySource -notmatch ('"' + [regex]::Escape($name) + '"')) {
    throw "Compiler telemetry does not initialize required counter '$name'."
  }
}
foreach ($name in $requiredTelemetryPhases) {
  if ($telemetrySource -notmatch ('"' + [regex]::Escape($name) + '"')) {
    throw "Compiler telemetry does not initialize required phase '$name'."
  }
}
if ($telemetrySource -notmatch 'WITNESS_LIMIT\s*=\s*64') {
  throw "Compiler telemetry witness limit differs from the governed performance policy."
}

$campaignPath = Join-Path $RepoRoot ".mir\performance-campaign.json"
$campaign = Get-Content -Raw -LiteralPath $campaignPath | ConvertFrom-Json
if ([int]$campaign.schema -ne 2 -or [string]$campaign.release -ne "3.2.0" -or
    [string]$campaign.factorio_line -ne "2.1" -or [string]$campaign.factorio_version -ne "2.1.11") {
  throw "Performance campaign authority must be the schema-2 MIR 3.2.0 Factorio 2.1.11 campaign."
}
$releaseLedgerPath = Join-Path $RepoRoot ".mir\releases.json"
$releaseLedger = Get-Content -Raw -LiteralPath $releaseLedgerPath | ConvertFrom-Json
$activeCandidate = $releaseLedger.development.'factorio-2.1'
if ($null -eq $activeCandidate -or
    [string]$campaign.candidate.candidate_id -ne [string]$activeCandidate.candidate_id -or
    [string]$campaign.candidate.version -ne [string]$activeCandidate.mir_version -or
    [string]$campaign.candidate.package_source_commit -ne [string]$activeCandidate.package_source_commit -or
    [string]$campaign.candidate.package_source_sha256 -ne [string]$activeCandidate.package_source_sha256 -or
    [string]$campaign.candidate.archive_sha256 -ne [string]$activeCandidate.archive_sha256 -or
    [string]$campaign.candidate.package_content_sha256 -ne [string]$activeCandidate.package_content_sha256) {
  throw "Performance campaign candidate authority differs from the active Factorio 2.1 release candidate."
}
if ([int]$campaign.run_policy.warmup_runs -lt 1 -or
    [int]$campaign.run_policy.minimum_measured_runs_per_package -lt 5 -or
    [string]$campaign.run_policy.order -ne "paired-balanced") {
  throw "Performance campaign authority does not declare the governed paired run policy."
}
$campaignLaneIds = @($campaign.lanes.id + $campaign.phase_lanes.id | Sort-Object)
$budgetLaneIds = @($regressionLanes.id | Sort-Object)
if (($campaignLaneIds -join "`n") -ne ($budgetLaneIds -join "`n")) {
  throw "Performance campaign and regression budget lane sets differ."
}
foreach ($requiredPath in @(
  "fixtures\performance-regression-probe\info.json",
  "fixtures\performance-regression-probe\probe.lua",
  "fixtures\performance-regression-probe\data.lua",
  "fixtures\performance-regression-probe\data-final-fixes.lua",
  "scripts\Measure-MIRPerformanceRegression.ps1",
  "scripts\validation\PerformanceCampaign.ps1"
)) {
  if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $requiredPath) -PathType Leaf)) {
    throw "Performance campaign producer authority is absent: $requiredPath"
  }
}
$producerSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\Measure-MIRPerformanceRegression.ps1")
foreach ($snippet in @("schema = 3", "artifact_volume", "counter_budget_failures", "MIR_PERFORMANCE_PROBE", "paired-balanced", "ProbeSmokeOnly", "CompatSmokeLaneId")) {
  if ($producerSource -notmatch [regex]::Escape($snippet)) {
    throw "Performance campaign producer lacks required schema-3 behavior '$snippet'."
  }
}
$performanceCampaignHelpers = Join-Path $RepoRoot "scripts\validation\PerformanceCampaign.ps1"
. $performanceCampaignHelpers
$orderedCounter = Get-MIRPerformanceCounterValue -Counters ([ordered]@{bounded=12}) -Name "bounded"
$jsonCounter = Get-MIRPerformanceCounterValue -Counters ('{"bounded":12}' | ConvertFrom-Json) -Name "bounded"
$missingCounter = Get-MIRPerformanceCounterValue -Counters ([ordered]@{bounded=12}) -Name "missing"
if (-not [bool]$orderedCounter.found -or [long]$orderedCounter.value -ne 12 -or
    -not [bool]$jsonCounter.found -or [long]$jsonCounter.value -ne 12 -or
    [bool]$missingCounter.found) {
  throw "Performance counter lookup must support ordered producer maps, parsed evidence objects, and missing counters."
}
if ($producerSource -notmatch 'FailFast\s*=\s*\(\$PackageLabel\s+-eq\s+"candidate"\)' -or
    $producerSource -notmatch '\$PackageLabel\s+-eq\s+"candidate"[\s\S]{0,200}process_result[\s\S]{0,200}result') {
  throw "Performance campaign must enforce process and claim gates on the candidate without imposing current behavioral claims on the sealed baseline."
}
if ($producerSource -notmatch '\[int\]\$scenarios\[0\]\.exit_code\s+-ne\s+0' -or
    $producerSource -notmatch '\[int\]\$scenarios\[0\]\.dependency_failure_count\s+-ne\s+0') {
  throw "Performance campaign must still require successful Factorio execution and an exact dependency closure for both packages."
}
$campaignFingerprintSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\validation\PerformanceCampaign.ps1")
if ($campaignFingerprintSource -notmatch [regex]::Escape('.mir/sanitation-budgets.json')) {
  throw "Performance harness fingerprint must bind the ecosystem sanitation budget authority."
}
$compatRunnerSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\MIRCompatAudit\FactorioRunner.ps1")
$compatAuditSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\Invoke-MIRCompatAudit.ps1")
$durationProjectionCount = [regex]::Matches($compatAuditSource, 'duration_seconds\s*=\s*\[double\]\$result\.duration_seconds').Count
if ($compatRunnerSource -notmatch 'duration_seconds\s*=\s*\[Math\]::Round\(\$timer\.Elapsed\.TotalSeconds' -or
    $durationProjectionCount -lt 2) {
  throw "Compatibility performance lanes require authoritative Factorio process duration in load and campaign evidence."
}
if ($compatAuditSource -notmatch 'process_passed\s*=\s*\[bool\]\$result\.passed' -or
    $compatAuditSource -notmatch '\$processResult\s*=\s*if\s*\(\$result\.process_passed\s+-eq\s+\$true\)' -or
    $compatAuditSource -notmatch '\$claimGateResult\s*=\s*if\s*\(\$processResult\s+-eq\s+"passed"\s+-and\s+\$result\.passed\s+-eq\s+\$true') {
  throw "Compatibility evidence must distinguish successful Factorio execution from the package-specific behavioral claim gate."
}

if ($ValidateManifestOnly) {
  Write-Host "[ok] MIR performance manifests declare $($budgets.Count) budgets, ten paired lanes, a schema-3 producer, and complete bounded compiler telemetry."
  exit 0
}

foreach ($requiredPath in @($ValidationSummaryPath, $MediumPackSummaryPath, $LargePackSummaryPath)) {
  if ([string]::IsNullOrWhiteSpace($requiredPath)) { throw "All performance evidence input paths are required." }
}
$validationPath = Resolve-MIRPerformancePath -Path $ValidationSummaryPath
$mediumPath = Resolve-MIRPerformancePath -Path $MediumPackSummaryPath
$largePath = Resolve-MIRPerformancePath -Path $LargePackSummaryPath
$validation = Get-Content -Raw -LiteralPath $validationPath | ConvertFrom-Json
$medium = Get-Content -Raw -LiteralPath $mediumPath | ConvertFrom-Json
$large = Get-Content -Raw -LiteralPath $largePath | ConvertFrom-Json

if ($validation.status -ne "passed") { throw "Validation timing source is not passed: $validationPath" }

function Get-MIRStepSeconds {
  param($Summary, [string]$Name, [string]$Context)
  $matches = @($Summary.results | Where-Object name -eq $Name)
  if ($matches.Count -ne 1) { throw "$Context summary does not contain exactly one '$Name' step." }
  if ($matches[0].status -ne "passed") { throw "$Context step '$Name' is not passed." }
  return [double]$matches[0].seconds
}

$results = foreach ($budget in $budgets) {
  $actual = switch ([string]$budget.source) {
    "validation_scenario" {
      $matches = @($validation.scenarios | Where-Object name -eq $budget.key)
      if ($matches.Count -ne 1 -or $matches[0].status -ne "passed") {
        throw "Validation timing source '$($budget.key)' is not exactly one passed scenario."
      }
      [double]$matches[0].duration_seconds
    }
    "validation_total" { [double]$validation.duration_seconds }
    "medium_pack_step" { Get-MIRStepSeconds -Summary $medium -Name $budget.key -Context "Medium-pack" }
    "large_pack_step" { Get-MIRStepSeconds -Summary $large -Name $budget.key -Context "Large-pack" }
    default { throw "Unknown performance budget source '$($budget.source)'." }
  }
  $maximum = [double]$budget.max_seconds
  [ordered]@{
    id = [string]$budget.id
    source = [string]$budget.source
    key = [string]$budget.key
    actual_seconds = [Math]::Round($actual, 3)
    max_seconds = $maximum
    status = if ($actual -le $maximum) { "passed" } else { "failed" }
  }
}

$failed = @($results | Where-Object status -ne "passed")
$evidence = [ordered]@{
  schema = 1
  release = [string]$manifest.release
  factorio_line = [string]$manifest.factorio_line
  status = if ($failed.Count -eq 0) { "passed" } else { "failed" }
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  git_commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
  factorio_binary_version = [string]$validation.factorio_binary_version
  validation_run_id = [string]$validation.run_id
  validation_source = $ValidationSummaryPath
  medium_pack = [ordered]@{
    scenario = "local-2-1-bz-suite-space-age"
    third_party_mods = 6
    source = $MediumPackSummaryPath
  }
  large_pack = [ordered]@{
    scenario = "local-2-1-krastorio-spaced-out"
    third_party_mods = 8
    audit_rows = 2654
    compatibility_claim = "load-observation-only"
    source = $LargePackSummaryPath
  }
  results = @($results)
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  $resolvedOutputPath = Resolve-MIRPerformancePath -Path $OutputPath
  $parent = Split-Path -Parent $resolvedOutputPath
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutputPath -Encoding UTF8
  Write-Host "[ok] MIR performance evidence: $resolvedOutputPath"
}
if ($failed.Count -gt 0) {
  throw "Performance budgets failed: $(@($failed | ForEach-Object id) -join ', ')."
}
Write-Host "[ok] MIR performance budgets passed ($($results.Count)/$($results.Count))."
