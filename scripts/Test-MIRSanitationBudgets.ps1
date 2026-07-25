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

$campaignBudgetNames = @($policy.campaigns.PSObject.Properties.Name)
$missing = @(Compare-Object $scenarioNames $campaignBudgetNames | Where-Object SideIndicator -eq '<=' | ForEach-Object InputObject)
$unknown = @(Compare-Object $scenarioNames $campaignBudgetNames | Where-Object SideIndicator -eq '=>' | ForEach-Object InputObject)
if ($missing.Count -gt 0 -or $unknown.Count -gt 0) {
  throw "Sanitation budget scenario set mismatch. Missing: $($missing -join ', '); unknown: $($unknown -join ', ')."
}

$localRepairNames = @(
  Get-ChildItem -LiteralPath (Join-Path $RepoRoot "fixtures\run-profiles") -Filter "release-targeted*.json" -File |
    ForEach-Object {
      $profile = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
      if ([string]$profile.kind -eq "release-targeted" -and $profile.skip_repair_smokes -ne $true) {
        foreach ($modName in @($profile.repair_smoke_mod_names)) {
          "local-$([string]$profile.factorio_line)-$([string]$modName)"
        }
      }
    } |
    Sort-Object -Unique
)
if ($null -eq $policy.PSObject.Properties["local_mod_zips"]) {
  throw "Sanitation budget authority must declare local_mod_zips for release-targeted repair smokes."
}
$localRepairBudgetNames = @($policy.local_mod_zips.PSObject.Properties.Name)
$missingLocalRepairs = @(Compare-Object $localRepairNames $localRepairBudgetNames | Where-Object SideIndicator -eq '<=' | ForEach-Object InputObject)
$unknownLocalRepairs = @(Compare-Object $localRepairNames $localRepairBudgetNames | Where-Object SideIndicator -eq '=>' | ForEach-Object InputObject)
if ($missingLocalRepairs.Count -gt 0 -or $unknownLocalRepairs.Count -gt 0) {
  throw "Local repair sanitation budget set mismatch. Missing: $($missingLocalRepairs -join ', '); unknown: $($unknownLocalRepairs -join ', ')."
}

$budgetSets = [ordered]@{
  campaigns = $policy.campaigns
  local_mod_zips = $policy.local_mod_zips
}
foreach ($scope in $budgetSets.Keys) {
  $budgets = $budgetSets[$scope]
  foreach ($name in @($budgets.PSObject.Properties.Name)) {
  $budget = $budgets.$name
  if ($null -eq $budget.PSObject.Properties["expected_external_prunes"] -or
      $null -eq $budget.PSObject.Properties["maximum_unreviewed_external_prunes"]) {
    throw "Sanitation budget $scope/$name is incomplete."
  }
  $maximum = [int]$budget.maximum_unreviewed_external_prunes
  if ($maximum -ne 0) { throw "Release sanitation budget $scope/$name must use zero unreviewed external prunes." }
  $identities = @()
  foreach ($row in @($budget.expected_external_prunes)) {
    foreach ($field in @("technology", "effect_type", "target")) {
      if ([string]::IsNullOrWhiteSpace([string]$row.$field)) { throw "Sanitation budget $scope/$name contains a prune without $field." }
    }
    $identities += "$($row.technology)|$($row.effect_type)|$($row.target)"
  }
  if (@($identities | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
    throw "Sanitation budget $scope/$name contains duplicate expected prune identities."
  }
  }
}

$compatAuditText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\Invoke-MIRCompatAudit.ps1")
foreach ($requiredDiagnosticsWiring in @(
  'Initialize-MIRSettingsOverrideMod -ModsDir $modsDir -FactorioVersion $FactorioLine',
  'Enable-CopiedDiagnostics -ModsDir $modsDir',
  '"mir-validation-settings-overrides"'
)) {
  if (-not $compatAuditText.Contains($requiredDiagnosticsWiring)) {
    throw "Compatibility audits do not enable candidate-safe diagnostics through the validation override mod: $requiredDiagnosticsWiring"
  }
}
$factorioRunnerText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\MIRCompatAudit\FactorioRunner.ps1")
if ($factorioRunnerText.Contains("prototypes\mir\settings\test_overrides.lua")) {
  throw "Compatibility audits must not mutate the copied MIR source tree to enable diagnostics."
}

Write-Host "[ok] every ecosystem campaign and release-targeted local repair smoke has an exact zero-tolerance sanitation budget."
