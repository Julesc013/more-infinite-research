# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../.."))
)

$ErrorActionPreference = 'Stop'
$receiptPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-K2-Science-SOL06V1.json'
$receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100
$shaPattern = '^[A-F0-9]{64}$'
$finalMilePath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Tooling-Authority-Evolution-ReceiptV1.json'
$finalMile = Get-Content -Raw -LiteralPath $finalMilePath | ConvertFrom-Json -Depth 100 -DateKind String
$successorFixturePath = 'fixtures/assert-k2-science-phase-policy/data-final-fixes.lua'
if ([string]$finalMile.kind -cne 'MIR4FinalMileToolingAuthorityEvolutionReceiptV1' -or
    [string]$finalMile.predecessor_receipt.sha256 -cne 'CAB840352F129A028D2BD061DAD44A29C43BEB5C39F8639C1D8B64CC1E210831' -or
    @($finalMile.package_visible_delta).Count -ne 0 -or
    @($finalMile.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
  throw 'SOL-06 successor authority is invalid or grants a release transition.'
}

if ([int]$receipt.schema -ne 1 -or [string]$receipt.kind -ne 'MIR4K2ScienceSOL06V1' -or
    [string]$receipt.status -ne 'PASS' -or [string]$receipt.work_package -ne 'SOL-06' -or
    $receipt.package_visible -or $receipt.publication_authorized) {
  throw 'MIR 4 SOL-06 receipt header is invalid or grants unauthorized visibility.'
}
if ([string]$receipt.scope.starting_source.commit -ne '65796a468a5247c8b31143a82db5fa3c94926d46' -or
    [string]$receipt.scope.starting_source.reconciled_predecessor_commit -ne 'e190836c8b8f781c4e41dafc08df367ca986b33a' -or
    [string]$receipt.scope.feedback_id -ne 'PF-2026-08-K2SO-001' -or
    [string]$receipt.scope.science_classification -notmatch '^B1-' -or
    [string]$receipt.scope.family_breadth_classification -notmatch '^B2-optional') {
  throw 'SOL-06 is not bound to the reconciled source and corrected feedback classifications.'
}
if ([string]$receipt.input_reconciliation.superseded_assumption -ne 'f200-Krastorio2-plus-K2SO-combined-closure' -or
    [string]$receipt.input_reconciliation.f200 -notmatch 'standalone.*incompatible') {
  throw 'SOL-06 did not correct the impossible Factorio 2.0 combined K2/K2SO closure.'
}

$implementation = $receipt.implementation
if ([string]$implementation.policy -ne 'K2SciencePhasePolicyV2' -or
    -not $implementation.package_visible_semantics_changed -or -not $implementation.pure_policy -or
    @($implementation.profiles).Count -ne 2) {
  throw 'SOL-06 implementation does not retain the V2 pure-policy and two-profile contract.'
}
$f210Profile = $implementation.profiles | Where-Object id -eq 'factorio-2.1-k2so'
$f200Profile = $implementation.profiles | Where-Object id -eq 'factorio-2.0-k2so-standalone'
if ([string]$f210Profile.version_ranges.Krastorio2 -ne '>=2.1.2 <2.1.3' -or
    [string]$f210Profile.version_ranges.'Krastorio2-spaced-out' -ne '>=2.0.11 <2.0.14' -or
    [string]$f200Profile.version_ranges.'Krastorio2-spaced-out' -ne '>=1.6.21 <1.6.22' -or
    [string]$f200Profile.forbidden_mod -ne 'Krastorio2' -or
    [string]$f200Profile.exact_absent_retired_identity -ne 'kr-basic-tech-card') {
  throw 'SOL-06 target-specific version or capability profiles changed.'
}

foreach ($artifact in @($implementation.authorities)) {
  if ([string]$artifact.file_sha256 -notmatch $shaPattern) {
    throw "SOL-06 authority lacks a SHA-256 binding: $($artifact.path)"
  }
  $path = Join-Path $RepoRoot ([string]$artifact.path)
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "SOL-06 authority differs from its receipt: $($artifact.path)"
  }
  $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  if ($actual -ne [string]$artifact.file_sha256) {
    if ([string]$artifact.path -cne $successorFixturePath) {
      throw "SOL-06 authority differs from its receipt: $($artifact.path)"
    }
    $successor = @($finalMile.current_authorities | Where-Object { [string]$_.path -ceq $successorFixturePath })
    $canonicalText = [IO.File]::ReadAllText($path).Replace("`r`n", "`n")
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($canonicalText)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $canonicalSha256 = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
    if ($successor.Count -ne 1 -or [string]$successor[0].sha256 -cne $canonicalSha256 -or
        [string]$successor[0].hash_mode -cne 'canonical-text-v1' -or
        [string]$successor[0].role -cne 'exact-v1-v2-k2-policy-qualification-harness') {
      throw 'SOL-06 fixture changed without the exact package-excluded final-mile successor authority.'
    }
  }
}
$policySource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'prototypes/mir/compatibility/policies/k2_science_phase.lua')
$plannerSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'prototypes/mir/planner/science.lua')
$fixtureSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-k2-science-phase-policy/data-final-fixes.lua')
foreach ($token in @('K2SciencePhasePolicyV2', 'factorio-2.1-k2so', 'factorio-2.0-k2so-standalone',
    'maximum_exclusive', 'required_science_packs', 'forbidden_mods', 'capability_fingerprint')) {
  if ($policySource -notmatch [regex]::Escape($token)) { throw "K2 policy lacks required token: $token" }
}
if ($plannerSource -notmatch 'research_pack_prototype' -or $plannerSource -notmatch 'valid_research_ingredients' -or
    $fixtureSource -notmatch 'f210_lower_endpoint' -or $fixtureSource -notmatch 'f200_with_forbidden_k2' -or
    $fixtureSource -notmatch 'missing_capability') {
  throw 'SOL-06 planner capability wiring or negative fixture coverage is incomplete.'
}

$generic = $receipt.generic_runtime_proof
if ([string]$generic.scenario -ne 'k2-science-phase-policy' -or [string]$generic.status -ne 'passed' -or
    [string]$generic.file_sha256 -notmatch $shaPattern -or @($generic.validates).Count -lt 7) {
  throw 'SOL-06 generic K2 policy proof is incomplete.'
}
foreach ($candidate in @($receipt.candidates.PSObject.Properties.Value)) {
  if ([string]$candidate.archive_sha256 -notmatch $shaPattern -or
      [string]$candidate.content_sha256 -notmatch $shaPattern -or
      [string]$candidate.disposition -notmatch 'local.*development-evidence-only') {
    throw 'SOL-06 candidate identity or private non-release disposition is invalid.'
  }
}
if ([string]$receipt.candidates.f200.construction -notmatch '^private-target-characterization' -or
    [string]$receipt.candidates.f200.base_predecessor.release -ne '2.5.11' -or
    [string]$receipt.candidates.f200.base_predecessor.archive_sha256 -notmatch $shaPattern) {
  throw 'SOL-06 overstates or fails to bind the private Factorio 2.0 characterization candidate.'
}

$reproduction = $receipt.f200_reproduction
if ([string]$reproduction.status -ne 'reproduced-on-immutable-predecessor' -or
    [string]$reproduction.candidate -ne 'dist/more-infinite-research_2.5.11.zip' -or
    (@($reproduction.unexpected_retained_early_packs | Sort-Object) -join ',') -ne
      'automation-science-pack,chemical-science-pack,logistic-science-pack') {
  throw 'SOL-06 does not retain the exact Factorio 2.0 predecessor defect witness.'
}
foreach ($binding in @($reproduction.campaign_evidence, $reproduction.load_results, $reproduction.engine_log)) {
  if ([string]$binding.file_sha256 -notmatch $shaPattern) { throw 'SOL-06 f200 reproduction evidence lacks a SHA-256.' }
}

$proofs = @($receipt.exact_runtime_proofs)
if ($proofs.Count -ne 3 -or @($proofs.id | Sort-Object -Unique).Count -ne 3 -or
    @('f210-upper-endpoint', 'f210-lower-endpoint', 'f200-standalone' |
      Where-Object { $_ -notin @($proofs.id) }).Count -ne 0) {
  throw 'SOL-06 does not bind all three exact endpoint proofs.'
}
foreach ($proof in $proofs) {
  if ([string]$proof.result -ne 'passed' -or -not $proof.science_contract_passed -or
      [string]$proof.factorio.executable_sha256 -notmatch $shaPattern -or
      [string]$proof.root_archive_sha256 -notmatch $shaPattern -or
      [string]$proof.campaign_evidence_sha256 -notmatch $shaPattern -or
      [string]$proof.load_results_sha256 -notmatch $shaPattern -or
      [string]$proof.dependency_lock_sha256 -notmatch $shaPattern -or
      [string]$proof.engine_log_sha256 -notmatch $shaPattern) {
    throw "SOL-06 exact proof is incomplete: $($proof.id)"
  }
}
if ([string]($proofs | Where-Object id -eq 'f210-upper-endpoint').versions.'Krastorio2-spaced-out' -ne '2.0.13' -or
    [string]($proofs | Where-Object id -eq 'f210-lower-endpoint').versions.'Krastorio2-spaced-out' -ne '2.0.11' -or
    [string]($proofs | Where-Object id -eq 'f200-standalone').versions.Krastorio2 -ne 'absent' -or
    [string]($proofs | Where-Object id -eq 'f200-standalone').versions.'Krastorio2-spaced-out' -ne '1.6.21') {
  throw 'SOL-06 exact proof versions do not bind the admitted endpoints.'
}

$science = $receipt.science_contract
if ([string]$science.representative_early_stream.technology -ne 'research_advanced_circuit' -or
    @($science.representative_early_stream.required).Count -ne 5 -or
    [string]$science.representative_late_stream.technology -ne 'research_belts' -or
    (@($science.representative_late_stream.required) -join ',') -ne 'production-science-pack,space-science-pack' -or
    @($science.representative_late_stream.forbidden).Count -ne 5) {
  throw 'SOL-06 representative science contract is incomplete.'
}

$families = @($receipt.optional_productivity_family_dispositions)
$imersite = $families | Where-Object family -eq 'imersite'
if ($families.Count -ne 6 -or [string]$imersite.disposition -ne 'preserved-external-owner' -or
    [string]$imersite.owner -ne 'kr-imersite-productivity' -or $imersite.mir_duplicate_emitted -or
    @($imersite.owned_recipes).Count -ne 7) {
  throw 'SOL-06 does not preserve the exact K2SO imersite owner without duplication.'
}
foreach ($name in @('rare-metals', 'silicon', 'glass')) {
  if ([string]($families | Where-Object family -eq $name).disposition -ne 'review-required-deferred-processir') {
    throw "SOL-06 optional $name family was admitted without ProcessIR proof."
  }
}
foreach ($name in @('black-tile', 'white-tile')) {
  $row = $families | Where-Object family -eq $name
  if ([string]$row.disposition -ne 'omitted-hard-safety' -or
      [string]$row.reason -ne 'recipe_productivity_not_allowed') {
    throw "SOL-06 $name hard-safety disposition changed."
  }
}

$plan = $receipt.verification_plan
if ([string]$plan.status -ne 'materialized-preclose' -or [string]$plan.file_sha256 -notmatch $shaPattern -or
    [string]$plan.plan_material_sha256 -notmatch $shaPattern -or
    [string]$plan.required_test_set_sha256 -notmatch $shaPattern -or
    [int]$plan.counts.total -ne 157 -or [int]$plan.counts.run -ne 154 -or
    [int]$plan.counts.reuse -ne 0 -or [int]$plan.counts.invalid -ne 3 -or
    'runtime.upgrade' -notin @($plan.invalid_future_work) -or
    'static.mir4-bootstrap-materialization' -notin @($plan.invalid_future_work) -or
    'static.mir4-offline-custody' -notin @($plan.invalid_future_work)) {
  throw 'SOL-06 verification plan or bounded SOL-09 invalid set is incorrect.'
}

$gate = $receipt.exit_gate
if (-not $gate.bounded_policy_implemented -or -not $gate.profile_capability_fingerprints_proven -or
    -not $gate.f210_lower_and_upper_endpoints_proven -or -not $gate.f200_defect_reproduced -or
    -not $gate.f200_private_target_proof_passed -or -not $gate.exact_science_contract_passed -or
    -not $gate.duplicate_imersite_owner_avoided -or -not $gate.optional_family_breadth_nonblocking_and_disposed -or
    -not $gate.formal_f200_target_materialization_deferred_to_sol08 -or
    $gate.public_release_claim_authorized -or $gate.publication_authorized -or
    [string]$gate.next_work_package -ne 'SOL-07') {
  throw 'SOL-06 exit gate is incomplete or grants release/publication authority.'
}

Write-Host 'MIR 4 SOL-06 bounded K2 science policy, exact F210/F200 proof, and family dispositions passed.'
