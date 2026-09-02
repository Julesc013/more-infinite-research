# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..'))
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'MIR4ReceiptTestSupport.ps1')
$hostedReceiptOnly = Test-MIR4HostedReceiptOnly
$receiptPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Affected-Proof-Closure-SOL08V1.json'
$receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100
$shaPattern = '^[A-F0-9]{64}$'

if ([int]$receipt.schema -ne 1 -or [string]$receipt.kind -ne 'MIR4AffectedProofClosureSOL08V1' -or
    [string]$receipt.work_package -ne 'SOL-08' -or [string]$receipt.status -ne 'PASS' -or
    $receipt.package_visible -or $receipt.release_admission_authorized -or
    $receipt.signing_or_sealing_authorized -or $receipt.publication_authorized) {
  throw 'MIR 4 SOL-08 receipt header is invalid or grants unauthorized authority.'
}
if ([string]$receipt.source.commit -ne '65796a468a5247c8b31143a82db5fa3c94926d46' -or
    [string]$receipt.source.reconciled_predecessor_commit -ne 'e190836c8b8f781c4e41dafc08df367ca986b33a') {
  throw 'SOL-08 no longer binds the reconciled M4C01 source.'
}

if (-not $hostedReceiptOnly) {
$manifestPath = Join-Path $RepoRoot ([string]$receipt.candidate_manifest.path)
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash -ne [string]$receipt.candidate_manifest.file_sha256) {
  throw 'SOL-08 candidate manifest is absent or differs from its receipt binding.'
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100
if ([string]$manifest.kind -ne 'MIR4AffectedTargetCandidateSetSOL08V1' -or
    [string]$manifest.status -ne 'built-unqualified-local-development-candidates' -or
    $manifest.public_output_authorized -or $manifest.publication_authorized -or @($manifest.targets).Count -ne 2) {
  throw 'SOL-08 candidate manifest violates its private development boundary.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$denyPattern = '^(?:\.mir|\.codex|\.github|build|dist|docs|fixtures|scripts|tests|validation|tools|credentials?|private|evidence|sdk)/|^(?:AGENTS\.md|CONTRIBUTING\.md|todo\.md)$'
foreach ($target in @($receipt.targets)) {
  $row = @($manifest.targets | Where-Object target_key -eq ([string]$target.target_key))
  if ($row.Count -ne 1 -or [string]$row[0].factorio_line -ne [string]$target.factorio_line -or
      [string]$row[0].version -ne [string]$target.version -or
      [string]$row[0].archive_sha256 -ne [string]$target.archive_sha256 -or
      [string]$row[0].content_sha256 -ne [string]$target.content_sha256 -or
      [long]$row[0].bytes -ne [long]$target.bytes -or [int]$row[0].entry_count -ne [int]$target.entry_count) {
    throw "SOL-08 target manifest binding changed for $($target.target_key)."
  }
  $archivePath = Join-Path $RepoRoot ([string]$target.candidate)
  if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf) -or
      (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash -ne [string]$target.archive_sha256) {
    throw "SOL-08 target archive is absent or changed for $($target.target_key)."
  }
  foreach ($repetition in @($row[0].repetitions)) {
    $repetitionPath = Join-Path $RepoRoot ([string]$repetition.path)
    if (-not (Test-Path -LiteralPath $repetitionPath -PathType Leaf) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $repetitionPath).Hash -ne [string]$target.archive_sha256) {
      throw "SOL-08 deterministic repetition differs for $($target.target_key)/$($repetition.id)."
    }
  }
  $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
  try {
    $files = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
    if ($files.Count -ne [int]$target.entry_count) { throw "SOL-08 archive entry count changed for $($target.target_key)." }
    $root = "more-infinite-research_$($target.version)/"
    if (@($files | Where-Object { -not $_.FullName.StartsWith($root, [StringComparison]::Ordinal) }).Count -ne 0) {
      throw "SOL-08 archive root changed for $($target.target_key)."
    }
    $relative = @($files | ForEach-Object { $_.FullName.Substring($root.Length) })
    $denied = @($relative | Where-Object { $_ -match $denyPattern })
    if ($denied.Count -ne 0) { throw "SOL-08 release denylist content entered $($target.target_key): $($denied -join ', ')" }
    $infoEntry = @($files | Where-Object FullName -eq ($root + 'info.json'))
    if ($infoEntry.Count -ne 1) { throw "SOL-08 info.json is absent for $($target.target_key)." }
    $reader = [IO.StreamReader]::new($infoEntry[0].Open())
    try { $info = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    if ([string]$info.version -ne [string]$target.version -or [string]$info.factorio_version -ne [string]$target.factorio_line) {
      throw "SOL-08 package metadata changed for $($target.target_key)."
    }
  } finally {
    $zip.Dispose()
  }
}

foreach ($deltaBinding in @($receipt.package_deltas)) {
  $path = Join-Path $RepoRoot ([string]$deltaBinding.path)
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$deltaBinding.file_sha256) {
    throw "SOL-08 archive delta changed for $($deltaBinding.target_key)."
  }
  $delta = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ([string]$delta.status -ne 'PASS' -or [int]$delta.summary.added -ne [int]$deltaBinding.added -or
      [int]$delta.summary.changed -ne [int]$deltaBinding.changed -or [int]$delta.summary.removed -ne 0 -or
      [int]$delta.summary.unexpected -ne 0 -or
      (@($delta.policy.allowed_change_roots | Sort-Object) -join "`n") -ne (@($deltaBinding.allowed_paths | Sort-Object) -join "`n")) {
    throw "SOL-08 archive delta is no longer bounded for $($deltaBinding.target_key)."
  }
}
foreach ($compositionBinding in @($receipt.composition)) {
  $path = Join-Path $RepoRoot ([string]$compositionBinding.path)
  $composition = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$compositionBinding.file_sha256 -or
      [bool]$composition.review.required -ne [bool]$compositionBinding.review_required -or -not $composition.review.reviewed) {
    throw "SOL-08 package composition changed for $($compositionBinding.target_key)."
  }
}

foreach ($matrixBinding in @($receipt.upgrade_matrices)) {
  $path = Join-Path $RepoRoot ([string]$matrixBinding.path)
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$matrixBinding.file_sha256) {
    throw "SOL-08 upgrade matrix changed for $($matrixBinding.target_key)."
  }
  $matrix = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ([string]$matrix.status -ne 'passed' -or @($matrix.rows).Count -ne [int]$matrixBinding.passed -or
      (@($matrix.required_archetypes | Sort-Object) -join "`n") -ne (@($matrixBinding.required_archetypes | Sort-Object) -join "`n")) {
    throw "SOL-08 upgrade matrix is incomplete for $($matrixBinding.target_key)."
  }
  foreach ($row in @($matrix.rows)) {
    $resultPath = Join-Path $RepoRoot ([string]$row.result)
    if ([string]$row.status -ne 'passed' -or
        'upgraded-save-reload-passed' -notin @($row.assertions) -or
        'upgraded-save-second-reload-passed' -notin @($row.assertions) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $resultPath).Hash -ne [string]$row.result_sha256) {
      throw "SOL-08 upgrade row is not an exact two-reload pass: $($matrixBinding.target_key)/$($row.id)."
    }
  }
}

$targetByKey = @{}
foreach ($target in @($receipt.targets)) { $targetByKey[[string]$target.target_key] = $target }
$scenarioPasses = 0
foreach ($binding in @($receipt.exact_load_evidence)) {
  $path = Join-Path $RepoRoot ([string]$binding.path)
  $lockPath = Join-Path $RepoRoot ([string]$binding.lock_path)
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$binding.file_sha256 -or
      (Get-FileHash -Algorithm SHA256 -LiteralPath $lockPath).Hash -ne [string]$binding.lock_sha256) {
    throw "SOL-08 exact load evidence changed: $($binding.id)."
  }
  $evidence = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  $target = $targetByKey[[string]$binding.target_key]
  if ([string]$evidence.mir_archive.sha256 -ne [string]$target.archive_sha256 -or
      [string]$evidence.factorio_binary.sha256 -ne [string]$target.engine_sha256) {
    throw "SOL-08 load evidence identity changed: $($binding.id)."
  }
  foreach ($scenarioId in @($binding.accepted_scenarios)) {
    $row = @($evidence.scenarios | Where-Object scenario_id -eq $scenarioId)
    if ($row.Count -ne 1 -or [string]$row[0].result -ne 'passed' -or
        [int]$row[0].dependency_failure_count -ne 0 -or $row[0].timed_out) {
      throw "SOL-08 scenario is not an exact pass: $scenarioId."
    }
    $scenarioPasses++
  }
}
if ($scenarioPasses -ne 10) { throw 'SOL-08 exact target-load scenario count changed.' }
$recyclerBinding = @($receipt.exact_load_evidence | Where-Object id -eq 'f200-recycler-characterization')[0]
$recyclerEvidence = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ([string]$recyclerBinding.path)) | ConvertFrom-Json -Depth 100
$recyclerRoot = Split-Path -Parent (Join-Path $RepoRoot ([string]$recyclerBinding.path))
$recyclerLogs = @(Get-ChildItem -LiteralPath $recyclerRoot -Recurse -File -Filter 'local-2-0-recycler-progression-routes.log')
if ([string]$recyclerBinding.disposition -ne 'not-reproduced-on-exact-1.0.0-surface-absent' -or
    $recyclerLogs.Count -ne 1 -or
    -not (Select-String -LiteralPath $recyclerLogs[0].FullName -SimpleMatch '[mir-fixture-assert-recycler-progression-routes-f200] PASS recycler-1-routes-rejected=true surface-present=false exercised=0' -Quiet)) {
  throw 'SOL-08 exact f200 Recycler Progression characterization changed.'
}

foreach ($planBinding in @($receipt.verification_plans)) {
  $path = Join-Path $RepoRoot ([string]$planBinding.path)
  $plan = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  $invalid = @($plan.tests | Where-Object disposition -eq 'INVALID' | ForEach-Object id | Sort-Object)
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne [string]$planBinding.file_sha256 -or
      [string]$plan.plan_material_sha256 -ne [string]$planBinding.plan_material_sha256 -or
      [string]$plan.required_test_set_sha256 -ne [string]$planBinding.required_test_set_sha256 -or
      [int]$plan.counts.total -ne [int]$planBinding.counts.total -or [int]$plan.counts.run -ne [int]$planBinding.counts.run -or
      [int]$plan.counts.reuse -ne 0 -or [int]$plan.counts.invalid -ne 2 -or
      (@($invalid) -join ',') -ne 'static.mir4-bootstrap-materialization,static.mir4-offline-custody' -or
      [string](@($plan.tests | Where-Object id -eq 'runtime.upgrade')[0].disposition) -ne 'RUN') {
    throw "SOL-08 verification plan changed for $($planBinding.target_key)."
  }
}
} else {
  $null = Assert-MIR4ExternalEvidenceBinding -RepoRoot $RepoRoot -RelativePath ([string]$receipt.candidate_manifest.path) -Sha256 ([string]$receipt.candidate_manifest.file_sha256)
  if ([string]$receipt.candidate_manifest.status -cne 'built-unqualified-local-development-candidates') {
    throw 'SOL-08 hosted receipt closure lost its private candidate-manifest disposition.'
  }

  $targets = @($receipt.targets)
  if ($targets.Count -ne 2 -or (@($targets.target_key | Sort-Object) -join ',') -cne 'f200,f210') {
    throw 'SOL-08 hosted receipt closure does not bind exactly f200 and f210.'
  }
  foreach ($target in $targets) {
    $null = Assert-MIR4ExternalEvidenceBinding -RepoRoot $RepoRoot -RelativePath ([string]$target.candidate) -Sha256 ([string]$target.archive_sha256)
    if ([string]$target.content_sha256 -cnotmatch $shaPattern -or [string]$target.engine_sha256 -cnotmatch $shaPattern -or
        [string]$target.predecessor_sha256 -cnotmatch $shaPattern -or [long]$target.bytes -le 0 -or
        [int]$target.entry_count -le 0 -or (@($target.deterministic_repetitions) -join ',') -cne 'A,B') {
      throw "SOL-08 hosted target identity is incomplete: $($target.target_key)."
    }
  }

  $deltas = @($receipt.package_deltas)
  if ($deltas.Count -ne 2 -or (@($deltas.target_key | Sort-Object) -join ',') -cne 'f200,f210') {
    throw 'SOL-08 hosted receipt closure does not bind both package deltas.'
  }
  foreach ($binding in $deltas) {
    $null = Assert-MIR4ExternalEvidenceBinding -RepoRoot $RepoRoot -RelativePath ([string]$binding.path) -Sha256 ([string]$binding.file_sha256)
    if ([int]$binding.removed -ne 0 -or [int]$binding.unexpected -ne 0 -or @($binding.allowed_paths).Count -eq 0) {
      throw "SOL-08 hosted package-delta boundary changed: $($binding.target_key)."
    }
  }

  $composition = @($receipt.composition)
  if ($composition.Count -ne 2 -or (@($composition.target_key | Sort-Object) -join ',') -cne 'f200,f210' -or
      @($composition | Where-Object review_required).Count -ne 0) {
    throw 'SOL-08 hosted package-composition receipt closure changed.'
  }
  foreach ($binding in $composition) {
    $null = Assert-MIR4ExternalEvidenceBinding -RepoRoot $RepoRoot -RelativePath ([string]$binding.path) -Sha256 ([string]$binding.file_sha256)
  }

  $upgradeMatrices = @($receipt.upgrade_matrices)
  if ($upgradeMatrices.Count -ne 2 -or [int](($upgradeMatrices | Measure-Object -Property passed -Sum).Sum) -ne 6 -or
      @($upgradeMatrices | Where-Object reloads_per_archetype -ne 2).Count -ne 0) {
    throw 'SOL-08 hosted two-reload upgrade receipt closure changed.'
  }
  foreach ($binding in $upgradeMatrices) {
    $null = Assert-MIR4ExternalEvidenceBinding -RepoRoot $RepoRoot -RelativePath ([string]$binding.path) -Sha256 ([string]$binding.file_sha256)
    if (@($binding.required_archetypes).Count -ne [int]$binding.passed) {
      throw "SOL-08 hosted upgrade-archetype binding changed: $($binding.target_key)."
    }
  }

  $loadEvidence = @($receipt.exact_load_evidence)
  $scenarioCount = [int](($loadEvidence | ForEach-Object { @($_.accepted_scenarios).Count } | Measure-Object -Sum).Sum)
  if ($loadEvidence.Count -ne 5 -or $scenarioCount -ne 10) {
    throw 'SOL-08 hosted exact-load receipt closure changed.'
  }
  foreach ($binding in $loadEvidence) {
    $null = Assert-MIR4ExternalEvidenceBinding -RepoRoot $RepoRoot -RelativePath ([string]$binding.path) -Sha256 ([string]$binding.file_sha256)
    $null = Assert-MIR4ExternalEvidenceBinding -RepoRoot $RepoRoot -RelativePath ([string]$binding.lock_path) -Sha256 ([string]$binding.lock_sha256)
    if ([string]$binding.target_key -cnotin @('f210', 'f200') -or @($binding.accepted_scenarios).Count -eq 0) {
      throw "SOL-08 hosted exact-load binding is incomplete: $($binding.id)."
    }
  }
  $recyclerBinding = @($loadEvidence | Where-Object id -eq 'f200-recycler-characterization')
  if ($recyclerBinding.Count -ne 1 -or [string]$recyclerBinding[0].disposition -cne 'not-reproduced-on-exact-1.0.0-surface-absent' -or
      [string]$recyclerBinding[0].assertion -cne 'recycler-1-routes-rejected=true surface-present=false exercised=0') {
    throw 'SOL-08 hosted f200 Recycler Progression characterization changed.'
  }

  $plans = @($receipt.verification_plans)
  if ($plans.Count -ne 2 -or (@($plans.target_key | Sort-Object) -join ',') -cne 'f200,f210') {
    throw 'SOL-08 hosted verification-plan closure is incomplete.'
  }
  foreach ($binding in $plans) {
    $null = Assert-MIR4ExternalEvidenceBinding -RepoRoot $RepoRoot -RelativePath ([string]$binding.path) -Sha256 ([string]$binding.file_sha256)
    if ([string]$binding.plan_material_sha256 -cnotmatch $shaPattern -or
        [string]$binding.required_test_set_sha256 -cnotmatch $shaPattern -or
        [int]$binding.counts.total -le 0 -or [int]$binding.counts.run -le 0 -or
        [int]$binding.counts.reuse -ne 0 -or [int]$binding.counts.invalid -ne 2 -or
        [string]$binding.runtime_upgrade -cne 'RUN') {
      throw "SOL-08 hosted verification-plan binding changed: $($binding.target_key)."
    }
  }
}

$releaseSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/lib/assurance/Release.ps1')
foreach ($guard in @(
  "authority_class = 'private-affected-correction-testing-only'",
  'affected-correction candidate bytes differ from the exact manifest',
  'affected-correction plan requires the exact target-bound Factorio engine',
  'affected-correction plan requires the exact target-bound predecessor archive',
  '[bool]$affectedManifest.publication_authorized',
  '[bool]$authority.signing_or_sealing_authorized'
)) {
  if (-not $releaseSource.Contains($guard)) { throw "SOL-08 private planning authority lost fail-closed guard: $guard" }
}
if ([string]$receipt.assurance.evidence_store_test -ne 'PASS' -or
    [string]$receipt.assurance.broad_self_test.status -ne 'PASS' -or
    [string]$receipt.assurance.broad_self_test.message -notmatch 'bound to exact M4C01 implementation authority') {
  throw 'SOL-08 assurance disposition changed or lost its candidate-programme authority binding.'
}
if ([string]$receipt.performance.status -ne 'NOT_RERUN' -or [string]$receipt.performance.final_release_requirement -notmatch 'fresh candidate-bound') {
  throw 'SOL-08 performance disposition overclaims qualification.'
}

$gate = $receipt.exit_gate
if (-not $gate.deterministic_target_candidates_built -or -not $gate.package_deltas_bounded -or
    -not $gate.package_denylist_clean -or [int]$gate.exact_f210_loads_passed -ne 6 -or
    [int]$gate.exact_f200_loads_passed -ne 4 -or [int]$gate.upgrade_archetypes_passed -ne 6 -or
    -not $gate.two_reloads_per_upgrade_archetype -or [int]$gate.product_failures -ne 0 -or
    [int]$gate.broad_compatibility_claims_added -ne 0 -or -not $gate.old_m4c01_bytes_superseded_for_corrected_target_proof -or
    $gate.source_freeze_authorized -or $gate.publication_authorized -or [string]$gate.next_work_package -ne 'SOL-09') {
  throw 'SOL-08 exit gate is incomplete or grants unsupported authority.'
}

if ($hostedReceiptOnly) { Write-Host 'MIR 4 SOL-08 committed receipt closure passed; exact private packages and evidence bytes remain bound to the local integration gate.' }
else { Write-Host 'MIR 4 SOL-08 deterministic affected-target packages, exact loads, and two-reload upgrade proof passed.' }
