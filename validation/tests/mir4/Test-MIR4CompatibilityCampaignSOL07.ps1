param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../.."))
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'MIR4ReceiptTestSupport.ps1')
$hostedReceiptOnly = Test-MIR4HostedReceiptOnly
$receiptPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Compatibility-Campaign-SOL07V1.json'
$receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100
$shaPattern = '^[A-F0-9]{64}$'

if ([int]$receipt.schema -ne 1 -or [string]$receipt.kind -ne 'MIR4CompatibilityCampaignSOL07V1' -or
    [string]$receipt.status -ne 'PASS' -or [string]$receipt.work_package -ne 'SOL-07' -or
    $receipt.package_visible -or $receipt.publication_authorized -or $receipt.public_release_claim_authorized) {
  throw 'MIR 4 SOL-07 receipt header is invalid or grants unauthorized visibility.'
}
if ([string]$receipt.scope.starting_source.commit -ne '65796a468a5247c8b31143a82db5fa3c94926d46' -or
    [string]$receipt.scope.starting_source.reconciled_predecessor_commit -ne 'e190836c8b8f781c4e41dafc08df367ca986b33a' -or
    [string]$receipt.scope.candidate.archive_sha256 -ne '27E4A872ECBC9D9ED4AB9B4431F26450EB039A52379D408BE6A99342780CB223' -or
    [string]$receipt.scope.candidate.content_sha256 -notmatch $shaPattern -or
    [string]$receipt.scope.factorio_2_1.executable_sha256 -ne 'E396BD25C068DD4C5EF45E93E6A87DBA0E12EEA964B6A5B73163041CC4A6143F') {
  throw 'SOL-07 source, candidate, or Factorio identity changed.'
}
$expectedResultModel = @('LOAD', 'INTEGRITY', 'extension-required', 'review-required', 'omitted', 'failed-hard-safety')
if ((@($receipt.scope.result_model) -join ',') -ne ($expectedResultModel -join ',') -or
    [string]$receipt.scope.claim_boundary -notmatch 'no blanket compatibility') {
  throw 'SOL-07 result model or claim boundary is incomplete.'
}

$bindings = @($receipt.evidence_bindings)
if ($bindings.Count -ne 7 -or @($bindings.id | Sort-Object -Unique).Count -ne 7) {
  throw 'SOL-07 must bind seven unique exact campaign evidence sets.'
}
foreach ($binding in $bindings) {
  foreach ($field in @('file_sha256', 'lock_sha256', 'candidate_sha256', 'engine_sha256')) {
    if ([string]$binding.$field -notmatch $shaPattern) {
      throw "SOL-07 evidence binding $($binding.id) lacks $field."
    }
  }
  $evidenceMaterialized = Assert-MIR4ExternalEvidenceBinding -RepoRoot $RepoRoot -RelativePath ([string]$binding.path) -Sha256 ([string]$binding.file_sha256)
  $lockMaterialized = Assert-MIR4ExternalEvidenceBinding -RepoRoot $RepoRoot -RelativePath ([string]$binding.lock_path) -Sha256 ([string]$binding.lock_sha256)
  if ($evidenceMaterialized -ne $lockMaterialized) { throw "SOL-07 evidence and lock custody differ for $($binding.id)." }
  if ($evidenceMaterialized) {
    $evidencePath = Join-Path $RepoRoot ([string]$binding.path)
    $evidence = Get-Content -Raw -LiteralPath $evidencePath | ConvertFrom-Json -Depth 100
    if ([string]$evidence.mir_archive.sha256 -ne [string]$binding.candidate_sha256 -or
        [string]$evidence.factorio_binary.sha256 -ne [string]$binding.engine_sha256) {
      throw "SOL-07 evidence identity differs from binding $($binding.id)."
    }
    foreach ($scenarioId in @($binding.accepted_scenarios)) {
      $row = @($evidence.scenarios | Where-Object scenario_id -eq $scenarioId)
      if ($row.Count -ne 1 -or [string]$row[0].result -ne 'passed' -or
          [int]$row[0].dependency_failure_count -ne 0 -or $row[0].timed_out) {
        throw "SOL-07 accepted scenario is not an exact pass: $scenarioId"
      }
    }
  }
}

$finding = @($receipt.superseded_campaign_findings)
if ($finding.Count -ne 1 -or [string]$finding[0].id -ne 'SOL07-HARNESS-001' -or
    [string]$finding[0].result -ne 'skipped' -or [int]$finding[0].dependency_failure_count -ne 2 -or
    [string]$finding[0].classification -ne 'harness-input-ambiguity-not-product-failure' -or
    [string]$finding[0].superseded_by -ne 'f210-recycler-progression') {
  throw 'SOL-07 did not retain and supersede the minimized Recycler harness finding.'
}

foreach ($historical in @($receipt.historical_context)) {
  if ([string]$historical.file_sha256 -notmatch $shaPattern) {
    throw "SOL-07 historical context lacks a SHA-256: $($historical.path)"
  }
  $path = Join-Path $RepoRoot ([string]$historical.path)
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
      (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne [string]$historical.file_sha256) {
    throw "SOL-07 historical context differs from its binding: $($historical.path)"
  }
}

$subjects = @($receipt.subjects)
$expectedSubjects = @(
  'base-and-official', 'planetslib-corrundum', 'cubium', 'recycler-progression', 'k2-k2so', 'aai', 'bz',
  'industrial-revolution-3', 'industrial-revolution-4', 'space-exploration', 'bob', 'angel', 'pyanodons'
)
if ($subjects.Count -ne 13 -or @($subjects.id | Sort-Object -Unique).Count -ne 13 -or
    @($expectedSubjects | Where-Object { $_ -notin @($subjects.id) }).Count -ne 0) {
  throw 'SOL-07 subject ledger is incomplete or contains duplicate subjects.'
}
$bindingIds = @($bindings.id)
foreach ($subject in $subjects) {
  if ([string]$subject.outcome -notin $expectedResultModel -or
      [string]$subject.claim_level -notin @('loads', 'diagnostic-only', 'partial-support')) {
    throw "SOL-07 subject has an invalid outcome or claim level: $($subject.id)"
  }
  foreach ($evidenceId in @($subject.evidence_ids)) {
    if ([string]$evidenceId -notin $bindingIds) {
      throw "SOL-07 subject $($subject.id) names unknown evidence $evidenceId."
    }
  }
  if ([string]$subject.outcome -in @('LOAD', 'INTEGRITY') -and @($subject.evidence_ids).Count -eq 0) {
    throw "SOL-07 positive subject lacks exact evidence: $($subject.id)"
  }
  if ([string]$subject.outcome -in @('review-required', 'extension-required') -and
      [string]::IsNullOrWhiteSpace([string]$subject.blocker)) {
    throw "SOL-07 bounded subject lacks a blocker: $($subject.id)"
  }
  if ([string]$subject.qualified_surface -match '(?i)\b(?:broad|full[- ]pack|full[- ]suite|all compatibility)') {
    throw "SOL-07 subject overstates its qualified surface: $($subject.id)"
  }
}
$expectedOutcomes = @{
  'base-and-official' = 'LOAD'; 'planetslib-corrundum' = 'INTEGRITY'; cubium = 'INTEGRITY'
  'recycler-progression' = 'INTEGRITY'; 'k2-k2so' = 'INTEGRITY'; aai = 'LOAD'; bz = 'LOAD'
  'industrial-revolution-3' = 'review-required'; 'industrial-revolution-4' = 'review-required'
  'space-exploration' = 'extension-required'; bob = 'LOAD'; angel = 'review-required'; pyanodons = 'review-required'
}
foreach ($id in $expectedOutcomes.Keys) {
  if ([string]($subjects | Where-Object id -eq $id).outcome -ne [string]$expectedOutcomes[$id]) {
    throw "SOL-07 disposition changed for $id."
  }
}

$summary = $receipt.summary
if ([int]$summary.subject_count -ne 13 -or [int]$summary.load_outcomes -ne 4 -or
    [int]$summary.integrity_outcomes -ne 4 -or [int]$summary.extension_required -ne 1 -or
    [int]$summary.review_required -ne 4 -or [int]$summary.current_candidate_passed_scenario_count -ne 10 -or
    [int]$summary.private_f200_development_passed_scenario_count -ne 1 -or
    [int]$summary.blanket_claims_emitted -ne 0 -or [int]$summary.product_failures -ne 0) {
  throw 'SOL-07 subject summary is inconsistent with the exact ledger.'
}

$plan = $receipt.verification_plan
if ([string]$plan.status -ne 'materialized-preclose' -or [string]$plan.file_sha256 -notmatch $shaPattern -or
    [string]$plan.plan_material_sha256 -notmatch $shaPattern -or
    [string]$plan.required_test_set_sha256 -notmatch $shaPattern -or
    [int]$plan.counts.total -ne 158 -or [int]$plan.counts.run -ne 155 -or
    [int]$plan.counts.reuse -ne 0 -or [int]$plan.counts.invalid -ne 3 -or
    'runtime.upgrade' -notin @($plan.invalid_future_work) -or
    'static.mir4-bootstrap-materialization' -notin @($plan.invalid_future_work) -or
    'static.mir4-offline-custody' -notin @($plan.invalid_future_work)) {
  throw 'SOL-07 verification plan or bounded future-work set is incorrect.'
}

$gate = $receipt.exit_gate
if (-not $gate.subject_ledger_complete -or -not $gate.exact_current_candidate_locks_bound -or
    -not $gate.representative_affected_campaign_passed -or -not $gate.superseded_harness_failure_minimized -or
    -not $gate.unexecuted_overhauls_have_no_claim -or $gate.blanket_claims_emitted -or
    $gate.publication_authorized -or [string]$gate.next_work_package -ne 'SOL-08') {
  throw 'SOL-07 exit gate is incomplete or grants unsupported authority.'
}

if ($hostedReceiptOnly) { Write-Host 'MIR 4 SOL-07 committed receipt closure passed; exact private evidence bytes remain bound to the local integration gate.' }
else { Write-Host 'MIR 4 SOL-07 exact compatibility subject ledger and bounded campaign outcomes passed.' }
