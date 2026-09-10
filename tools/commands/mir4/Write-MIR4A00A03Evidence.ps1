# MIR4-CANONICAL-EXECUTABLE-TEST
# Append-only writer for tracked A00/A03 evidence records.
param(
  [Parameter(Mandatory)][ValidateSet('A00','A03ExecutionProof','A03Dossier','A03Receipt')][string]$Kind,
  [Parameter(Mandatory)][string]$InputPath,
  [Parameter(Mandatory)][string]$OutputPath,
  [Parameter(Mandatory)][ValidatePattern('^20[0-9]{2}-[0-9]{2}-[0-9]{2}T')][string]$RecordedAt,
  [switch]$RequireLocalEvidence,
  [switch]$TestOutput
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')

$contracts = @{
  A00 = @{ kind = 'MIR4A00CurrentAuthorityObservationV1'; schema = 'spec/schemas/mir4-a00-current-authority-observation-v1.schema.json' }
  A03ExecutionProof = @{ kind = 'MIR4A03K2K2SOExecutionProofV1'; schema = 'spec/schemas/mir4-a03-k2-k2so-execution-proof-v1.schema.json' }
  A03Dossier = @{ kind = 'MIR4A03K2K2SOIntakeDossierV1'; schema = 'spec/schemas/mir4-a03-k2-k2so-intake-dossier-v1.schema.json' }
  A03Receipt = @{ kind = 'MIR4A03K2K2SOIntakeReceiptV1'; schema = 'spec/schemas/mir4-a03-k2-k2so-intake-receipt-v1.schema.json' }
}
$contract = $contracts[$Kind]
$canonicalOutputs = @{
  A00 = 'spec/programmes/evidence/synthesis-2026-09-10/a00-current-authority-observation.json'
  A03ExecutionProof = 'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-execution-proof.json'
  A03Dossier = 'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-intake-dossier.json'
  A03Receipt = 'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-intake-receipt.json'
}

function Assert-A00A03NoAmbientTime {
  param([string]$Value)
  if ($Value -match '(?i)Get-Date|DateTime::Now|UtcNow') { throw '[mir4-a00-a03-ambient-time]' }
}

function Assert-A00CurrentAuthorityInput {
  param($Record)
  if ([string]$Record.kind -cne 'MIR4A00CurrentAuthorityObservationV1') { return }
  if ([string]$Record.task -cne 'A00' -or [string]$Record.base.merge_base -cne '3562377b520cccb071b97b3968946eae7024c950' -or
      [string]$Record.recovery.snapshot_logical_id -cne '20260909-205136-mir42-tin-browser-explanation' -or
      [int]$Record.recovery.entries -ne 180 -or [long]$Record.recovery.bytes -ne 238515273 -or
      -not [bool]$Record.recovery.bundle_verified -or -not [bool]$Record.recovery.apply_verified -or
      [int]$Record.recovery.restored_file_count -ne 13 -or [string]$Record.recovery.retained_stash_oid -cne '67c267748c7690efbb35625a580fea0dabaddd2e' -or
      -not [bool]$Record.classification.f210_waiver.prior_release_only -or [bool]$Record.classification.f210_waiver.mir42_qualification_authority -or
      @($Record.classification.authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) { throw '[mir4-a00-current-authority-input]' }
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $Record) -match '(?i)(?:[A-Z]:\\|\\\\)') { throw '[mir4-a00-absolute-path]' }
}

function Assert-A03EvidencePaths {
  param($Record, [string]$RepositoryRoot, [bool]$RequireEvidence)
  $paths = @()
  if ([string]$Record.kind -ceq 'MIR4A03K2K2SOExecutionProofV1') {
    $paths = @(
      [string]$Record.authority_observation.path,[string]$Record.environment_lock.path,
      [string]$Record.configuration.source_mod_list.path,[string]$Record.configuration.launch_mod_list.path,
      [string]$Record.configuration.source_mod_settings.path,[string]$Record.configuration.post_engine_mod_settings.path,
      [string]$Record.execution.plan.path,[string]$Record.execution.summary.path,[string]$Record.execution.attempt.path,
      [string]$Record.execution.attempt.structured_result.path,[string]$Record.execution.attempt.executor_stdout.path,[string]$Record.execution.attempt.executor_stderr.path,
      [string]$Record.execution.runtime.result_file.path,[string]$Record.execution.runtime.stdout.path,[string]$Record.execution.runtime.stderr.path,
      [string]$Record.execution.runtime.factorio_log.path,[string]$Record.execution.runtime.save.path
    )
  } elseif ([string]$Record.kind -ceq 'MIR4A03K2K2SOIntakeDossierV1') {
    $paths = @(
    [string]$Record.authority_observation.path,[string]$Record.environment_lock.path,[string]$Record.execution_proof.path,
    [string]$Record.runtime_result.file.path,[string]$Record.runtime_result.factorio_log.path,[string]$Record.runtime_result.save.path,
    [string]$Record.historical_lineage.old_admitted_campaign.path,
    [string]$Record.historical_lineage.pre_engine_failure.evidence_path,
    [string]$Record.historical_lineage.superseded_pass.evidence_path,
    [string]$Record.historical_lineage.superseded_pass.repaired_projection.path,
    [string]$Record.historical_lineage.superseded_pass.pre_selfhash_repair.path,
    [string]$Record.historical_lineage.prior_admitted_run.plan.path,
    [string]$Record.historical_lineage.prior_admitted_run.summary.path,
    [string]$Record.historical_lineage.prior_admitted_run.attempt.path,
    [string]$Record.historical_lineage.prior_admitted_run.runtime.path,
    [string]$Record.historical_lineage.source_tree_correction_superseded_run.plan.path,
    [string]$Record.historical_lineage.source_tree_correction_superseded_run.summary.path,
    [string]$Record.historical_lineage.source_tree_correction_superseded_run.attempt.path,
    [string]$Record.historical_lineage.source_tree_correction_superseded_run.runtime.path
    )
  } elseif ([string]$Record.kind -ceq 'MIR4A03K2K2SOIntakeReceiptV1') {
    $paths = @(
      [string]$Record.authority_observation.path,[string]$Record.dossier.path,[string]$Record.environment_lock.path,[string]$Record.execution_proof.path,
      [string]$Record.execution.plan.path,[string]$Record.execution.summary.path,[string]$Record.execution.attempt.path,[string]$Record.execution.runtime.path
    )
  }
  foreach ($relativePath in $paths) {
    if ([string]::IsNullOrWhiteSpace($relativePath) -or [IO.Path]::IsPathRooted($relativePath) -or $relativePath -match '(^|[\\/])\.\.([\\/]|$)') { throw '[mir4-a03-dossier-evidence-path-shape]' }
    $nativePath = $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if ($RequireEvidence -and -not (Test-Path -LiteralPath (Join-Path $RepositoryRoot $nativePath) -PathType Leaf)) { throw '[mir4-a03-dossier-evidence-path-missing]' }
  }
}

if ($OutputPath -match '(^|[\\/])\.\.([\\/]|$)') { throw '[mir4-a00-a03-output-boundary]' }
$outputFull = if ([IO.Path]::IsPathRooted($OutputPath)) { [IO.Path]::GetFullPath($OutputPath) } else { [IO.Path]::GetFullPath((Join-Path $repo $OutputPath)) }
$repoPrefix = $repo.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $outputFull.StartsWith($repoPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-a00-a03-output-boundary]' }
if ($TestOutput) {
  $testRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build/tests')).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (-not $outputFull.StartsWith($testRoot,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-a00-a03-output-boundary]' }
} else {
  $canonicalFull = [IO.Path]::GetFullPath((Join-Path $repo $canonicalOutputs[$Kind]))
  if (-not $outputFull.Equals($canonicalFull,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-a00-a03-output-kind-boundary]' }
}

$inputText = Get-Content -Raw -LiteralPath $InputPath
Assert-A00A03NoAmbientTime -Value $inputText
$input = $inputText | ConvertFrom-Json -Depth 100 -DateKind String
if ([string]$input.kind -cne [string]$contract.kind) { throw '[mir4-a00-a03-kind-contract]' }
Assert-A00CurrentAuthorityInput -Record $input
Assert-A03EvidencePaths -Record $input -RepositoryRoot $repo -RequireEvidence ([bool]$RequireLocalEvidence)
if ($null -ne $input.PSObject.Properties['recorded_at']) { $input.recorded_at = $RecordedAt }
else { $input | Add-Member -NotePropertyName recorded_at -NotePropertyValue $RecordedAt }

# Canonical records are append-only: an existing byte sequence may only be
# accepted when the deterministic projection is identical.
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('mir4-a00-a03-' + [guid]::NewGuid().ToString('N') + '.json')
try {
  $hash = Write-MIR4BootstrapRecord -Record $input -Path $scratch
  if ($hash -cne $hash.ToUpperInvariant()) { throw '[mir4-a00-a03-record-hash-case]' }
  $projection = [IO.File]::ReadAllText($scratch)
  if (-not ($projection | Test-Json -SchemaFile (Join-Path $repo ([string]$contract.schema)))) { throw '[mir4-a00-a03-projection-schema]' }
  if (Test-Path -LiteralPath $outputFull) {
    if ([IO.File]::ReadAllText((Resolve-Path -LiteralPath $outputFull).Path) -cne $projection) { throw '[mir4-a00-a03-immutable-overwrite]' }
    return $hash
  }
  $parent = [IO.Path]::GetDirectoryName($outputFull)
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $ownedTemp = Join-Path $parent ('.' + [IO.Path]::GetFileName($outputFull) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
  try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($projection)
    $stream = [IO.FileStream]::new($ownedTemp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
    try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    try { [IO.File]::Move($ownedTemp,$outputFull,$false) }
    catch [IO.IOException] {
      if (-not (Test-Path -LiteralPath $outputFull) -or [IO.File]::ReadAllText($outputFull) -cne $projection) { throw '[mir4-a00-a03-immutable-overwrite]' }
    }
  } finally { if (Test-Path -LiteralPath $ownedTemp) { Remove-Item -LiteralPath $ownedTemp -Force } }
  return $hash
} finally { if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Force } }
