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
if ($manifest.schema -ne 1) { throw "Performance budget manifest must use schema 1." }
$budgets = @($manifest.budgets)
if ($budgets.Count -eq 0) { throw "Performance budget manifest contains no budgets." }

$requiredIds = @(
  "base", "space-age", "scoped-caps-off", "scoped-caps-on", "diagnostics-off",
  "diagnostics-on", "medium-pack", "large-pack", "large-synthetic-graph", "full-matrix"
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
  "rejected_operations", "diagnostic_rows"
)
$requiredTelemetryPhases = @("snapshot", "graph", "planning", "postconditions")
foreach ($name in @($requiredTelemetryCounters + $requiredTelemetryPhases)) {
  if ($performancePolicy -notmatch "(?m)^\s*-\s+$([regex]::Escape($name))\s*$") {
    throw "Performance policy is missing required telemetry name '$name'."
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

if ($ValidateManifestOnly) {
  Write-Host "[ok] MIR performance manifest declares $($budgets.Count) budgets and complete bounded compiler telemetry."
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
