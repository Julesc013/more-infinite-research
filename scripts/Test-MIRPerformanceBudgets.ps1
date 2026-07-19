param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$BudgetsPath = ".mir\performance-budgets.json",
  [string]$PerformancePolicyPath = ".mir\performance.yml",
  [string]$CampaignPath = ".mir\performance-campaign.json",
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
$resolvedCampaignPath = Resolve-MIRPerformancePath -Path $CampaignPath
$manifest = Get-Content -Raw -LiteralPath $resolvedBudgetsPath | ConvertFrom-Json
if ($manifest.schema -ne 2) { throw "Performance budget manifest must use schema 2." }
$budgets = @($manifest.budgets)
if ($budgets.Count -eq 0) { throw "Performance budget manifest contains no budgets." }
$regressionLanes = @($manifest.regression_lanes)
if ($regressionLanes.Count -eq 0) { throw "Performance budget manifest contains no regression lanes." }

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

$campaign = Get-Content -Raw -LiteralPath $resolvedCampaignPath | ConvertFrom-Json
if ([int]$campaign.schema -ne 1 -or [string]$campaign.release -ne "2.4.9" -or
    [string]$campaign.factorio_line -ne "2.0" -or [string]$campaign.factorio_version -ne "2.0.77") {
  throw "Paired performance campaign authority is not the governed MIR 2.4.9 Factorio 2.0.77 campaign."
}
$campaignLanes = @($campaign.lanes)
if ((@($regressionLanes.id | Sort-Object) -join "`n") -ne (@($campaignLanes.id | Sort-Object) -join "`n")) {
  throw "Paired performance campaign does not contain the exact governed regression lane set."
}
$expectedCampaignLanes = @{
  "base.factorio-total" = @("exact-package-load", "base-default")
  "space-age.factorio-total" = @("exact-package-load", "space-age-default")
  "medium-ecosystem.factorio-total" = @("compat-audit", "local-2-0-bz-suite")
  "large-ecosystem.factorio-total" = @("compat-audit", "local-2-0-performance-large")
  "diagnostics-off.factorio-total" = @("exact-package-load", "base-diagnostics-off")
  "diagnostics-on.factorio-total" = @("exact-package-load", "base-diagnostics-on")
}
foreach ($laneId in $expectedCampaignLanes.Keys) {
  $row = @($campaignLanes | Where-Object id -eq $laneId)
  if ($row.Count -ne 1 -or [string]$row[0].runner -ne $expectedCampaignLanes[$laneId][0] -or
      [string]$row[0].scenario -ne $expectedCampaignLanes[$laneId][1]) {
    throw "Paired performance campaign lane authority drifted: $laneId"
  }
}
if ([int]$campaign.run_policy.warmup_runs -lt 1 -or
    [int]$campaign.run_policy.minimum_measured_runs_per_package -lt 5 -or
    [string]$campaign.run_policy.order -ne "paired-balanced") {
  throw "Paired performance campaign run policy is below the governed minimum."
}
if ([string]$campaign.baseline.archive_sha256 -ne "7649824B72247AA38F05661422DFDEE7C729B21CC73A0A35D2455443B45D39F8") {
  throw "Paired performance campaign does not bind the published MIR 2.4.5 baseline archive."
}

$performancePolicy = Get-Content -Raw -LiteralPath $resolvedPerformancePolicyPath
foreach ($requiredPolicySnippet in @(
  'release: 2.4.9',
  'factorio_line: "2.0"',
  'qualified_baseline: "2.4.5"',
  'maximum_regression_percent: 20'
)) {
  if ($performancePolicy -notmatch [regex]::Escape($requiredPolicySnippet)) {
    throw "Performance policy is missing '$requiredPolicySnippet'."
  }
}

if ($ValidateManifestOnly) {
  Write-Host "[ok] MIR 2.4.9 performance manifest declares $($budgets.Count) absolute budgets and $($regressionLanes.Count) exact paired Factorio 2.0 lanes."
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
