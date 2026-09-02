# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../.."))
)

$ErrorActionPreference = "Stop"
$path = Join-Path $RepoRoot ".mir/releases/waves/mir4-r0/MIR4-Production-Route-SOL04V1.json"
$record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
$shaPattern = '^[A-F0-9]{64}$'

if ([int]$record.schema -ne 1 -or [string]$record.kind -ne "MIR4ProductionRouteSOL04V1" -or
    [string]$record.status -ne "PASS" -or [string]$record.work_package -ne "SOL-04" -or
    $record.package_visible -or $record.publication_authorized) {
  throw "MIR 4 SOL-04 completion header is invalid or grants unauthorized visibility."
}
if ([string]$record.scope.starting_source.commit -ne "65796a468a5247c8b31143a82db5fa3c94926d46" -or
    [string]$record.scope.starting_source.reconciled_predecessor_commit -ne "e190836c8b8f781c4e41dafc08df367ca986b33a" -or
    [string]$record.scope.authority -ne "SciencePackProductionRoutePolicyV2" -or
    [string]$record.scope.claim_boundary -notmatch "1\.0\.0.*source-locked only.*unqualified") {
  throw "SOL-04 is not bound to the reconciled source and bounded route-policy claim."
}

$candidate = $record.candidate
if ([string]$candidate.archive_sha256 -notmatch $shaPattern -or
    [string]$candidate.content_sha256 -notmatch $shaPattern -or
    [string]$candidate.disposition -ne "local-development-evidence-only-not-a-release-candidate") {
  throw "SOL-04 candidate identity or non-release disposition is invalid."
}
$plan = $record.verification_plan
if ([string]$plan.file_sha256 -notmatch $shaPattern -or
    [string]$plan.plan_material_sha256 -notmatch $shaPattern -or
    [string]$plan.required_test_set_sha256 -notmatch $shaPattern -or
    [int]$plan.counts.total -ne 152 -or [int]$plan.counts.run -ne 150 -or
    [int]$plan.counts.invalid -ne 2 -or @($plan.invalid_future_work).Count -ne 2 -or
    "static.mir4-bootstrap-materialization" -notin @($plan.invalid_future_work) -or
    "static.mir4-offline-custody" -notin @($plan.invalid_future_work)) {
  throw "SOL-04 verification-plan identity or future-work boundary is invalid."
}

$generic = $record.generic_runtime_proof
if ([string]$generic.scenario -ne "generated-prerequisite-safety" -or
    [string]$generic.status -ne "passed" -or
    [string]$generic.file_sha256 -notmatch $shaPattern -or
    [string]$generic.candidate_archive_sha256 -ne [string]$candidate.archive_sha256 -or
    [string]$generic.candidate_content_sha256 -ne [string]$candidate.content_sha256) {
  throw "SOL-04 generic production-route proof is not passed and candidate-bound."
}

$exact = @($record.exact_runtime_proofs)
$requiredScenarios = @(
  "local-2-1-cubium-production-routes",
  "local-2-1-recycler-progression-routes"
)
if ($exact.Count -ne 2 -or @($exact.scenario | Sort-Object -Unique).Count -ne 2 -or
    @($requiredScenarios | Where-Object { $_ -notin @($exact.scenario) }).Count -ne 0) {
  throw "SOL-04 does not retain the two exact Factorio 2.1 route proofs."
}
foreach ($proof in $exact) {
  if ([string]$proof.result -ne "passed" -or [string]$proof.claim_level -ne "diagnostic-only" -or
      [string]$proof.factorio.version -ne "2.1.14.87180" -or
      [string]$proof.factorio.executable_sha256 -notmatch $shaPattern -or
      [string]$proof.dependency_lock_sha256 -notmatch $shaPattern -or
      [string]$proof.campaign_evidence.file_sha256 -notmatch $shaPattern -or
      [string]$proof.load_results.file_sha256 -notmatch $shaPattern -or
      [string]$proof.engine_log.file_sha256 -notmatch $shaPattern) {
    throw "SOL-04 exact evidence is incomplete for $($proof.scenario)."
  }
  if (@($proof.roots).Count -ne 2 -or
      @($proof.roots | Where-Object { [string]$_.archive_sha256 -notmatch $shaPattern }).Count -ne 0) {
    throw "SOL-04 exact dependency closure is not archive-bound for $($proof.scenario)."
  }
}

$cubium = $exact | Where-Object scenario -eq "local-2-1-cubium-production-routes"
if ("cubium" -notin @($cubium.roots.name) -or "1.0.30" -notin @($cubium.roots.version) -or
    [int]$cubium.assertions.total -ne 3 -or [int]$cubium.assertions.passed -ne 3) {
  throw "SOL-04 exact Cubium closure or assertion count is invalid."
}
$recycler = $exact | Where-Object scenario -eq "local-2-1-recycler-progression-routes"
if ("recycler-progression" -notin @($recycler.roots.name) -or "1.1.1" -notin @($recycler.roots.version) -or
    [int]$recycler.assertions.total -ne 2 -or [int]$recycler.assertions.passed -ne 2) {
  throw "SOL-04 exact Recycler Progression closure or assertion count is invalid."
}

$pending = @($record.bounded_pending_targets)
if ($pending.Count -ne 1 -or [string]$pending[0].mod -ne "recycler-progression" -or
    [string]$pending[0].version -ne "1.0.0" -or [string]$pending[0].factorio_line -ne "2.0" -or
    [string]$pending[0].archive_sha256 -notmatch $shaPattern -or
    [string]$pending[0].status -ne "source-locked-awaiting-target-local-proof" -or
    [string]$pending[0].planned_work_package -ne "SOL-08" -or
    [string]$pending[0].public_claim -ne "none") {
  throw "SOL-04 does not preserve the bounded Recycler Progression 1.0.0 target gap."
}

$requiredAuthorities = @(
  "prototypes/mir/capabilities/science_integration/production_route_policy.lua",
  "prototypes/mir/capabilities/science_integration/pack_production_reachability.lua",
  "prototypes/mir/compatibility/repairs/factorio_2_1_ambient_sound_schema.lua",
  "fixtures/assert-generated-prerequisite-safety/data-final-fixes.lua",
  "fixtures/assert-cubium-production-routes/data-final-fixes.lua",
  "fixtures/assert-recycler-progression-routes/data-final-fixes.lua"
)
foreach ($relative in $requiredAuthorities) {
  if ($relative -notin @($record.implementation_authorities) -or
      -not (Test-Path -LiteralPath (Join-Path $RepoRoot $relative))) {
    throw "SOL-04 implementation authority is missing: $relative"
  }
}
$policySource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes/mir/capabilities/science_integration/production_route_policy.lua")
$reachabilitySource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes/mir/capabilities/science_integration/pack_production_reachability.lua")
foreach ($token in @("SciencePackProductionRoutePolicyV2", "ordinary-primary", "self_return_cannot_prove_acquisition", "rejected_routes")) {
  if ($policySource -notmatch [regex]::Escape($token)) {
    throw "Production-route policy lacks required token: $token"
  }
}
if ($reachabilitySource -notmatch '%-recycling\$' -or
    $policySource -notmatch "retain the canonical ordinary recipe") {
  throw "Production-route classification or ordinary-primary preference wiring is missing."
}
if (-not $record.exit_gate.generic_route_policy_proven -or
    -not $record.exit_gate.ordinary_primary_preference_proven -or
    -not $record.exit_gate.immediate_alternate_exception_proven -or
    -not $record.exit_gate.rejected_route_witnesses_proven -or
    -not $record.exit_gate.exact_cubium_f210_proven -or
    -not $record.exit_gate.exact_recycler_progression_f210_proven -or
    $record.exit_gate.recycler_progression_f200_qualified -or
    $record.exit_gate.publication_authorized -or
    [string]$record.exit_gate.next_work_package -ne "SOL-05") {
  throw "SOL-04 exit gate is incomplete, overclaims Factorio 2.0, or grants publication authority."
}

Write-Host "MIR 4 SOL-04 production-route policy and exact Factorio 2.1 evidence passed."
