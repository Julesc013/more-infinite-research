param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$PolicyPath = ".mir\sanitation-budgets.json"
)

$ErrorActionPreference = "Stop"
$policyFile = if ([IO.Path]::IsPathRooted($PolicyPath)) { $PolicyPath } else { Join-Path $RepoRoot $PolicyPath }
$policy = Get-Content -Raw -LiteralPath $policyFile | ConvertFrom-Json
if ([int]$policy.schema -ne 1 -or [string]$policy.policy -ne "mir-ecosystem-sanitation-budget-v1") {
  throw "Sanitation budget authority must use mir-ecosystem-sanitation-budget-v1 schema 1."
}

$scenarioNames = @()
foreach ($relative in @(
  "fixtures\compat-matrix\manual-scenarios.json",
  "fixtures\compat-matrix\local-library-scenarios.json",
  "fixtures\compat-matrix\local-library-scenarios-2.0.json"
)) {
  $manifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $relative) | ConvertFrom-Json
  $scenarioNames += @($manifest.scenarios | ForEach-Object { [string]$_.name })
}
$duplicates = @($scenarioNames | Group-Object | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw "Scenario names must be globally unique for sanitation budgets: $($duplicates.Name -join ', ')" }

$budgetNames = @($policy.campaigns.PSObject.Properties.Name)
$missing = @(Compare-Object $scenarioNames $budgetNames | Where-Object SideIndicator -eq '<=' | ForEach-Object InputObject)
$unknown = @(Compare-Object $scenarioNames $budgetNames | Where-Object SideIndicator -eq '=>' | ForEach-Object InputObject)
if ($missing.Count -gt 0 -or $unknown.Count -gt 0) {
  throw "Sanitation budget scenario set mismatch. Missing: $($missing -join ', '); unknown: $($unknown -join ', ')."
}

foreach ($name in $budgetNames) {
  $budget = $policy.campaigns.$name
  if ($null -eq $budget.PSObject.Properties["expected_external_prunes"] -or
      $null -eq $budget.PSObject.Properties["maximum_unreviewed_external_prunes"]) {
    throw "Sanitation budget $name is incomplete."
  }
  $maximum = [int]$budget.maximum_unreviewed_external_prunes
  if ($maximum -ne 0) { throw "Release sanitation budget $name must use zero unreviewed external prunes." }
  $identities = @()
  foreach ($row in @($budget.expected_external_prunes)) {
    foreach ($field in @("technology", "effect_type", "target")) {
      if ([string]::IsNullOrWhiteSpace([string]$row.$field)) { throw "Sanitation budget $name contains a prune without $field." }
    }
    $identities += "$($row.technology)|$($row.effect_type)|$($row.target)"
  }
  if (@($identities | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
    throw "Sanitation budget $name contains duplicate expected prune identities."
  }
}

Write-Host "[ok] every ecosystem scenario has an exact zero-tolerance sanitation budget."
