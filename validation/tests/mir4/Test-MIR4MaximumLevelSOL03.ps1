param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../.."))
)

$ErrorActionPreference = "Stop"
$path = Join-Path $RepoRoot ".mir/releases/waves/mir4-r0/MIR4-Maximum-Level-Binding-SOL03V1.json"
$record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
$shaPattern = '^[A-F0-9]{64}$'

if ([int]$record.schema -ne 1 -or [string]$record.kind -ne "MIR4MaximumLevelBindingSOL03V1" -or
    [string]$record.status -ne "PASS" -or [string]$record.work_package -ne "SOL-03" -or
    $record.package_visible -or $record.publication_authorized) {
  throw "MIR 4 SOL-03 completion header is invalid or grants unauthorized visibility."
}
if ([string]$record.scope.starting_source.commit -ne "65796a468a5247c8b31143a82db5fa3c94926d46" -or
    [string]$record.scope.starting_source.reconciled_predecessor_commit -ne "e190836c8b8f781c4e41dafc08df367ca986b33a" -or
    [string]$record.scope.claim_boundary -notmatch "Manual visual UI review.*remain unproven") {
  throw "SOL-03 is not bound to the reconciled source or overstates its exact claim boundary."
}

$candidate = $record.candidate
if ([string]$candidate.archive_sha256 -notmatch $shaPattern -or
    [string]$candidate.content_sha256 -notmatch $shaPattern -or
    [string]$candidate.disposition -ne "local-development-evidence-only-not-a-release-candidate") {
  throw "SOL-03 candidate identity or non-release disposition is invalid."
}
$plan = $record.verification_plan
if ([string]$plan.file_sha256 -notmatch $shaPattern -or
    [string]$plan.plan_material_sha256 -notmatch $shaPattern -or
    [string]$plan.required_test_set_sha256 -notmatch $shaPattern -or
    [int]$plan.counts.total -ne 152 -or [int]$plan.counts.run -ne 150 -or
    [int]$plan.counts.invalid -ne 2 -or @($plan.invalid_future_work).Count -ne 2 -or
    "static.mir4-bootstrap-materialization" -notin @($plan.invalid_future_work) -or
    "static.mir4-offline-custody" -notin @($plan.invalid_future_work)) {
  throw "SOL-03 verification-plan identity or expected future-work boundary is invalid."
}

$generic = @($record.generic_runtime_proofs)
$requiredScenarios = @(
  "compiler-contracts",
  "generated-maximum-level-absolute",
  "space-age-native-owner-settings-max-level",
  "space-age-native-owner-settings-max-level-late-conflict"
)
if ($generic.Count -ne 4 -or @($generic.scenario | Sort-Object -Unique).Count -ne 4 -or
    @($requiredScenarios | Where-Object { $_ -notin @($generic.scenario) }).Count -ne 0) {
  throw "SOL-03 does not retain the four required generic runtime proofs."
}
foreach ($proof in $generic) {
  if ([string]$proof.status -ne "passed" -or [string]$proof.file_sha256 -notmatch $shaPattern) {
    throw "SOL-03 generic runtime proof $($proof.scenario) is not hash-bound and passed."
  }
}

$exact = $record.exact_runtime_proof
if ([string]$exact.scenario -ne "local-2-1-corrundum-maxcap-13" -or
    [string]$exact.result -ne "passed" -or [string]$exact.claim_level -ne "diagnostic-only" -or
    [string]$exact.factorio.version -ne "2.1.14.87180" -or
    [string]$exact.factorio.executable_sha256 -notmatch $shaPattern -or
    [string]$exact.dependency_lock_sha256 -notmatch $shaPattern -or
    [string]$exact.campaign_evidence.file_sha256 -notmatch $shaPattern -or
    [string]$exact.load_results.file_sha256 -notmatch $shaPattern -or
    [string]$exact.engine_log.file_sha256 -notmatch $shaPattern) {
  throw "SOL-03 exact Corrundum evidence is incomplete or exceeds diagnostic-only scope."
}
$roots = @($exact.roots)
if ($roots.Count -ne 2 -or "corrundum" -notin @($roots.name) -or "PlanetsLib" -notin @($roots.name) -or
    @($roots | Where-Object { [string]$_.archive_sha256 -notmatch $shaPattern }).Count -ne 0) {
  throw "SOL-03 exact dependency closure is not completely archive-bound."
}
$assertions = $exact.assertions
if ([int]$assertions.required_audit_rows -ne 1 -or [int]$assertions.required_audit_rows_passed -ne 1 -or
    [int]$assertions.required_log_fragments -ne 9 -or [int]$assertions.required_log_fragments_passed -ne 9 -or
    [int]$assertions.forbidden_log_fragments -ne 1 -or [int]$assertions.forbidden_log_fragments_passed -ne 1 -or
    [int]$assertions.total -ne 11 -or [int]$assertions.passed -ne 11) {
  throw "SOL-03 exact runtime contract is not 11/11 passed."
}

$requiredAuthorities = @(
  "prototypes/mir/domain/technology/maximum_level_binding.lua",
  "prototypes/mir/pipeline/compiler_orchestrator.lua",
  "prototypes/mir/pipeline/mutations/maximum_level_presentation.lua",
  "prototypes/mir/emit/mod_data.lua",
  "prototypes/mir/runtime/maximum_level_control.lua",
  "prototypes/mir/compatibility/repairs/factorio_2_1_ambient_sound_schema.lua"
)
foreach ($relative in $requiredAuthorities) {
  if ($relative -notin @($record.implementation_authorities) -or -not (Test-Path -LiteralPath (Join-Path $RepoRoot $relative))) {
    throw "SOL-03 implementation authority is missing: $relative"
  }
}
$bindingSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes/mir/domain/technology/maximum_level_binding.lua")
$runtimeSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes/mir/runtime/maximum_level_control.lua")
$repairSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes/mir/compatibility/repairs/factorio_2_1_ambient_sound_schema.lua")
foreach ($token in @("MIRMaximumLevelPolicyV3", "exact-technology", "exact-native-owner", "exact-stream", "ecosystem-profile", "factorio-data-final-fixes-v1")) {
  if ($bindingSource -notmatch [regex]::Escape($token)) {
    throw "Maximum-level binding authority lacks required V3 token: $token"
  }
}
if ($runtimeSource -notmatch "more-infinite-research-maximum-level-policy" -or $runtimeSource -notmatch "POLICY_VERSION = 3" -or
    $repairSource -notmatch 'corrundum' -or $repairSource -notmatch '1\.0\.47') {
  throw "SOL-03 runtime transport or exact Corrundum repair wiring is missing."
}
if (-not $record.exit_gate.normalized_binding_v3 -or
    -not $record.exit_gate.three_ownership_routes_proven -or
    -not $record.exit_gate.order_independence_proven -or
    -not $record.exit_gate.known_finalizer_acceptance_proven -or
    -not $record.exit_gate.unknown_or_conflicting_finalizer_rejection_proven -or
    -not $record.exit_gate.exact_corrundum_runtime_contract_proven -or
    $record.exit_gate.publication_authorized -or
    [string]$record.exit_gate.next_work_package -ne "SOL-04") {
  throw "SOL-03 exit gate is incomplete or grants publication authority."
}

Write-Host "MIR 4 SOL-03 normalized maximum-level binding and exact runtime evidence passed."
