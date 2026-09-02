# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..'))
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'MIR4ReceiptTestSupport.ps1')
$hostedReceiptOnly = Test-MIR4HostedReceiptOnly
$receiptPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-M4C01-Closeout-SOL09V1.json'
$receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100
$shaPattern = '^[A-F0-9]{64}$'
if ([int]$receipt.schema -ne 1 -or [string]$receipt.kind -ne 'MIR4M4C01CloseoutSOL09V1' -or
    [string]$receipt.work_package -ne 'SOL-09' -or [string]$receipt.status -ne 'PASS' -or
    [string]$receipt.source_commit -ne '65796a468a5247c8b31143a82db5fa3c94926d46' -or
    [string]$receipt.reconciled_predecessor_commit -ne 'e190836c8b8f781c4e41dafc08df367ca986b33a') {
  throw 'MIR 4 SOL-09 receipt header or source binding is invalid.'
}

if (-not $hostedReceiptOnly) {
$outputRoot = Join-Path $RepoRoot ([string]$receipt.output_root)
$checksumPath = Join-Path $RepoRoot ([string]$receipt.checksums.path)
if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $checksumPath).Hash -ne [string]$receipt.checksums.sha256) {
  throw 'SOL-09 checksum manifest is absent or changed.'
}
$checksums = Get-Content -Raw -LiteralPath $checksumPath | ConvertFrom-Json -Depth 100
if ([string]$checksums.kind -ne 'MIR4M4C01CloseoutChecksumsV1' -or [string]$checksums.status -ne 'complete' -or
    @($checksums.files).Count -ne [int]$receipt.checksums.file_count -or @($receipt.artifacts).Count -ne 9) {
  throw 'SOL-09 closeout checksum inventory is incomplete.'
}
foreach ($binding in @($receipt.artifacts)) {
  if ([string]$binding.sha256 -notmatch $shaPattern) { throw "SOL-09 artifact lacks SHA-256: $($binding.path)" }
  $path = Join-Path $outputRoot ([string]$binding.path)
  $row = @($checksums.files | Where-Object path -eq ([string]$binding.path))
  if ($row.Count -ne 1 -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or
      (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$binding.sha256 -or
      [string]$row[0].sha256 -ne [string]$binding.sha256 -or [long]$row[0].bytes -ne (Get-Item -LiteralPath $path).Length) {
    throw "SOL-09 closeout artifact differs from its exact checksum binding: $($binding.path)"
  }
}

$package = Get-Content -Raw -LiteralPath (Join-Path $outputRoot 'MIR4_M4C01_PACKAGE_MATRIX.json') | ConvertFrom-Json -Depth 100
if ([string]$package.status -ne 'complete-development-inventory' -or
    @($package.preserved_candidates).Count -ne 10 -or @($package.corrected_mandatory_candidates).Count -ne 2 -or
    (@($package.corrected_mandatory_candidates.target_key | Sort-Object) -join ',') -ne 'f200,f210' -or
    @($package.corrected_mandatory_candidates | Where-Object { [string]$_.status -ne 'exact-development-proof-passed-awaiting-source-freeze' -or $_.release_admitted }).Count -ne 0 -or
    $package.public_output_authorized) {
  throw 'SOL-09 package matrix is incomplete or overstates release admission.'
}
$preservedMandatory = @($package.preserved_candidates | Where-Object target_key -in @('f210','f200'))
if ($preservedMandatory.Count -ne 2 -or
    @($preservedMandatory | Where-Object status -ne 'superseded-for-corrected-target-proof').Count -ne 0) {
  throw 'SOL-09 did not supersede the preserved mandatory-target M4C01 bytes.'
}

$runtime = Get-Content -Raw -LiteralPath (Join-Path $outputRoot 'MIR4_M4C01_RUNTIME_MIGRATION_MATRIX.json') | ConvertFrom-Json -Depth 100
$f210 = @($runtime.rows | Where-Object target_key -eq 'f210')
$f200 = @($runtime.rows | Where-Object target_key -eq 'f200')
if ([string]$runtime.status -ne 'mandatory-target-development-proof-passed' -or [int]$runtime.product_failures -ne 0 -or
    $runtime.release_qualification_transferable -or $f210.Count -ne 1 -or $f200.Count -ne 1 -or
    [int]$f210[0].fresh_exact_loads -ne 6 -or [int]$f210[0].upgrade_archetypes -ne 5 -or
    [int]$f200[0].fresh_exact_loads -ne 4 -or [int]$f200[0].upgrade_archetypes -ne 1 -or
    [int]$f210[0].reloads_per_archetype -ne 2 -or [int]$f200[0].reloads_per_archetype -ne 2) {
  throw 'SOL-09 mandatory runtime and migration matrix is incomplete or transferable beyond evidence.'
}

$maturity = Get-Content -Raw -LiteralPath (Join-Path $outputRoot 'MIR4_M4C01_MATURITY_MATRIX.json') | ConvertFrom-Json -Depth 100
if ([string]$maturity.status -ne 'contract-enforced' -or @($maturity.preview_assets).Count -ne 4 -or
    @($maturity.preview_assets | Where-Object { [string]$_.maturity -ne 'preview' -or $_.mod_portal_payload }).Count -ne 0 -or
    [string]$maturity.publication.player_packages -ne 'not-authorized') {
  throw 'SOL-09 platform maturity or publication boundary changed.'
}
$nonInterference = Get-Content -Raw -LiteralPath (Join-Path $outputRoot 'MIR4_M4C01_NON_INTERFERENCE_MATRIX.json') | ConvertFrom-Json -Depth 100
if ([string]$nonInterference.status -ne 'passed-with-explicit-deltas' -or @($nonInterference.rows).Count -ne 5 -or
    @($nonInterference.rows | Where-Object status -notin @('passed','preserved-boundary')).Count -ne 0) {
  throw 'SOL-09 non-interference matrix is incomplete.'
}

$revocation = Get-Content -Raw -LiteralPath (Join-Path $outputRoot 'MIR4_M4C01_EVIDENCE_REVOCATION_MATRIX.json') | ConvertFrom-Json -Depth 100
if ([string]$revocation.status -ne 'current-evidence-set-closed' -or
    @($revocation.rows | Where-Object disposition -eq 'superseded').Count -lt 3 -or
    @($revocation.rows | Where-Object disposition -eq 'nontransferable-to-corrected-candidates').Count -ne 1 -or
    @($revocation.rows | Where-Object { [string]$_.evidence -like 'SOL09 * verification plan' -and [int]$_.invalid -ne 0 }).Count -ne 0) {
  throw 'SOL-09 evidence revocation matrix does not invalidate stale candidate-bound evidence.'
}

$feedback = Get-Content -Raw -LiteralPath (Join-Path $outputRoot 'MIR4_M4C01_PUBLIC_FEEDBACK_DISPOSITION.json') | ConvertFrom-Json -Depth 100
if ([string]$feedback.status -ne 'all-six-families-disposed' -or @($feedback.families).Count -ne 6 -or
    [int]$feedback.unresolved_product_blockers -ne 0 -or [int]$feedback.blanket_compatibility_claims -ne 0 -or
    @($feedback.families | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.receipt) }).Count -ne 0) {
  throw 'SOL-09 public feedback disposition is incomplete or creates a blanket claim.'
}

$blockers = Get-Content -Raw -LiteralPath (Join-Path $outputRoot 'MIR4_M4C01_BLOCKER_MATRIX.json') | ConvertFrom-Json -Depth 100
$requiredReleaseBlockers = @('source-freeze-and-candidate-allocation','fresh-performance-f210','fresh-performance-f200','independent-review','maintainer-manual-acceptance')
if ([string]$blockers.status -ne 'implementation-complete-release-actions-blocked' -or @($blockers.product_blockers).Count -ne 0 -or
    (@($blockers.release_candidate_blockers.id | Sort-Object) -join ',') -ne (@($requiredReleaseBlockers | Sort-Object) -join ',') -or
    @($blockers.nonblocking_target_gaps).Count -ne 3 -or
    @($blockers.prohibited_without_new_authority) -notcontains 'commit-or-source-freeze' -or
    @($blockers.prohibited_without_new_authority) -notcontains 'mod-portal-upload') {
  throw 'SOL-09 blocker matrix hides a release gate or mislabels a nonblocking target gap.'
}

$completion = Get-Content -Raw -LiteralPath (Join-Path $outputRoot 'MIR4_M4C01_COMPLETION_RECORD.json') | ConvertFrom-Json -Depth 100
if ([string]$completion.status -ne 'M4C01-DEVELOPMENT-CLOSEOUT-COMPLETE' -or -not $completion.implementation_complete -or
    $completion.release_candidate_ready -or $completion.publication_authorized -or [int]$completion.mandatory_product_failures -ne 0 -or
    [string]$completion.gates.mandatory_corrected_target_loads -ne 'passed-10-of-10' -or
    [string]$completion.gates.mandatory_upgrade_archetypes -ne 'passed-6-of-6-two-reloads-each' -or
    [string]$completion.gates.verification_plans -ne 'materialized-zero-invalid-f210-and-f200') {
  throw 'SOL-09 completion record is incomplete or overclaims release readiness.'
}
} else {
  if ([string]$receipt.output_root -cne 'build/mir4/m4c01-closeout' -or
      [string]$receipt.checksums.path -cne 'build/mir4/m4c01-closeout/SHA256SUMS.json' -or
      [int]$receipt.checksums.file_count -ne 9) {
    throw 'SOL-09 hosted closeout custody root or checksum inventory changed.'
  }
  $null = Assert-MIR4ExternalEvidenceBinding -RepoRoot $RepoRoot -RelativePath ([string]$receipt.checksums.path) -Sha256 ([string]$receipt.checksums.sha256)
  $expectedArtifacts = @(
    'MIR4_M4C01_BLOCKER_MATRIX.json',
    'MIR4_M4C01_COMPLETION_RECORD.json',
    'MIR4_M4C01_EVIDENCE_REVOCATION_MATRIX.json',
    'MIR4_M4C01_HANDOFF.md',
    'MIR4_M4C01_MATURITY_MATRIX.json',
    'MIR4_M4C01_NON_INTERFERENCE_MATRIX.json',
    'MIR4_M4C01_PACKAGE_MATRIX.json',
    'MIR4_M4C01_PUBLIC_FEEDBACK_DISPOSITION.json',
    'MIR4_M4C01_RUNTIME_MIGRATION_MATRIX.json'
  )
  $artifacts = @($receipt.artifacts)
  if ($artifacts.Count -ne 9 -or
      (@($artifacts.path | Sort-Object) -join ',') -cne (@($expectedArtifacts | Sort-Object) -join ',')) {
    throw 'SOL-09 hosted closeout artifact inventory changed.'
  }
  foreach ($binding in $artifacts) {
    $relativePath = ([string]$receipt.output_root).TrimEnd('/') + '/' + [string]$binding.path
    $null = Assert-MIR4ExternalEvidenceBinding -RepoRoot $RepoRoot -RelativePath $relativePath -Sha256 ([string]$binding.sha256)
  }
}

$summary = $receipt.proof_summary
if ([string]$summary.sol02_through_sol08 -ne 'PASS' -or [int]$summary.mandatory_target_exact_loads -ne 10 -or
    [int]$summary.mandatory_target_upgrade_archetypes -ne 6 -or [int]$summary.reloads_per_upgrade_archetype -ne 2 -or
    [string]$summary.bootstrap_materialization -ne 'PASS' -or [string]$summary.offline_custody_fail_closed -ne 'PASS' -or
    [string]$summary.assurance_regression -ne 'PASS' -or [int]$summary.f210_plan_invalid -ne 0 -or
    [int]$summary.f200_plan_invalid -ne 0 -or [int]$summary.product_blockers -ne 0) {
  throw 'SOL-09 proof summary changed.'
}
$boundary = $receipt.completion_boundary
if (-not $boundary.m4c01_development_closeout_complete -or $boundary.release_candidate_ready -or
    $boundary.source_freeze_authorized -or $boundary.commit_authorized -or $boundary.signing_or_sealing_authorized -or
    $boundary.promotion_authorized -or $boundary.publication_authorized -or @($boundary.remaining_release_gates).Count -ne 5 -or
    [string]$receipt.next_work_package -ne 'independent-audit-readiness-review') {
  throw 'SOL-09 completion boundary grants unsupported authority or drops required review.'
}

if ($hostedReceiptOnly) { Write-Host 'MIR 4 SOL-09 committed closeout receipt closure passed; exact private closeout bytes remain bound to the local integration gate.' }
else { Write-Host 'MIR 4 SOL-09 M4C01 development closeout, evidence revocation, and release blocker matrices passed.' }
