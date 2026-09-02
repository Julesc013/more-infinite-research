Set-StrictMode -Version Latest

function Assert-MIR4F2DAggregateV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[$Code]" }
}

function Get-MIR4F2DAggregateFileSha256V1 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-MIR4F2DAggregateTargetConfigsV1 {
  return @(
    [pscustomobject][ordered]@{target='f210';receipt='releases/migrations/MIR4-M41-F2D-F210-Runtime-Replay-Authority-EvolutionV1.json';schema='contracts/repository/mir4-m41-f2d-f210-runtime-replay-authority-evolution-v1.schema.json';kind='MIR4M41F2DF210RuntimeReplayAuthorityEvolutionV1';status='M41-F2D-210-PASSED-NO-CUTOVER';prior='releases/migrations/MIR4-M41-F2D-Runtime-Replay-Harness-Authority-EvolutionV1.json';archetypes=5}
    [pscustomobject][ordered]@{target='f200';receipt='releases/migrations/MIR4-M41-F2D-F200-Runtime-Replay-Authority-EvolutionV1.json';schema='contracts/repository/mir4-m41-f2d-target-runtime-replay-authority-evolution-v1.schema.json';kind='MIR4M41F2DTargetRuntimeReplayAuthorityEvolutionV1';status='M41-F2D-200-PASSED-NO-CUTOVER';prior='releases/migrations/MIR4-M41-F2D-F210-Runtime-Replay-Authority-EvolutionV1.json';archetypes=1}
    [pscustomobject][ordered]@{target='f110';receipt='releases/migrations/MIR4-M41-F2D-F110-Runtime-Replay-Authority-EvolutionV1.json';schema='contracts/repository/mir4-m41-f2d-target-runtime-replay-authority-evolution-v1.schema.json';kind='MIR4M41F2DTargetRuntimeReplayAuthorityEvolutionV1';status='M41-F2D-110-PASSED-NO-CUTOVER';prior='releases/migrations/MIR4-M41-F2D-F200-Runtime-Replay-Authority-EvolutionV1.json';archetypes=1}
    [pscustomobject][ordered]@{target='f100';receipt='releases/migrations/MIR4-M41-F2D-F100-Runtime-Replay-Authority-EvolutionV1.json';schema='contracts/repository/mir4-m41-f2d-target-runtime-replay-authority-evolution-v1.schema.json';kind='MIR4M41F2DTargetRuntimeReplayAuthorityEvolutionV1';status='M41-F2D-100-PASSED-NO-CUTOVER';prior='releases/migrations/MIR4-M41-F2D-F110-Runtime-Replay-Authority-EvolutionV1.json';archetypes=1}
  )
}

function Resolve-MIR4F2DAggregateEvidenceRootV1 {
  param(
    [Parameter(Mandatory)][string]$EvidenceHome,
    [Parameter(Mandatory)][string]$LogicalRoot,
    [Parameter(Mandatory)][string]$ReplayCommit,
    [Parameter(Mandatory)][string]$Target
  )
  $expected = "MIR_EVIDENCE_HOME/m41-f2d/$ReplayCommit/$Target"
  Assert-MIR4F2DAggregateV1 ($LogicalRoot -ceq $expected) 'mir4-f2d-aggregate-logical-evidence-root'
  $evidenceBase = (Resolve-Path -LiteralPath $EvidenceHome).Path
  $candidate = Join-Path $evidenceBase "m41-f2d\$ReplayCommit\$Target"
  Assert-MIR4F2DAggregateV1 (Test-Path -LiteralPath $candidate -PathType Container) 'mir4-f2d-aggregate-evidence-root-missing'
  $resolved = (Resolve-Path -LiteralPath $candidate).Path
  Assert-MIR4F2DAggregateV1 ($resolved.StartsWith($evidenceBase + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) 'mir4-f2d-aggregate-evidence-containment'
  return $resolved
}

function New-MIR4M41F2DFourTargetRuntimeReplayVerificationV1 {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$EvidenceHome
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $evidenceHomeResolved = (Resolve-Path -LiteralPath $EvidenceHome).Path
  $golden = Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/distribution/mir4-golden-four-target-baseline-v1.json') | ConvertFrom-Json -Depth 100
  $channel = Get-MIR4Factorio21ChannelAuthority -RepoRoot $repo
  $configs = @(Get-MIR4F2DAggregateTargetConfigsV1)
  $rows = [Collections.Generic.List[object]]::new()
  $receiptHashes = @{}
  $candidateIds = @{}
  $logicalRoots = @{}

  foreach ($config in $configs) {
    $receiptPath = Join-Path $repo ([string]$config.receipt)
    $schemaPath = Join-Path $repo ([string]$config.schema)
    Assert-MIR4F2DAggregateV1 (Test-Path -LiteralPath $receiptPath -PathType Leaf) 'mir4-f2d-aggregate-receipt-missing'
    $receiptText = Get-Content -Raw -LiteralPath $receiptPath
    Assert-MIR4F2DAggregateV1 ($receiptText | Test-Json -SchemaFile $schemaPath) 'mir4-f2d-aggregate-receipt-schema'
    $receipt = $receiptText | ConvertFrom-Json -Depth 100 -DateKind String
    $receiptSha = Get-MIR4F2DAggregateFileSha256V1 $receiptPath
    $receiptHashes[[string]$config.receipt] = $receiptSha
    $proof = $receipt.replay_proof
    Assert-MIR4F2DAggregateV1 ([string]$receipt.kind -ceq [string]$config.kind -and [string]$receipt.status -ceq [string]$config.status) 'mir4-f2d-aggregate-receipt-identity'
    Assert-MIR4F2DAggregateV1 ([string]$proof.target -ceq [string]$config.target -and [string]$proof.status -ceq [string]$config.status) 'mir4-f2d-aggregate-target-identity'
    if ($receipt.PSObject.Properties.Name -contains 'target') { Assert-MIR4F2DAggregateV1 ([string]$receipt.target -ceq [string]$config.target) 'mir4-f2d-aggregate-receipt-target' }
    Assert-MIR4F2DAggregateV1 ([string]$receipt.predecessor_receipt.path -ceq [string]$config.prior) 'mir4-f2d-aggregate-predecessor-path'
    $priorPath = Join-Path $repo ([string]$config.prior)
    Assert-MIR4F2DAggregateV1 ((Get-MIR4F2DAggregateFileSha256V1 $priorPath) -ceq [string]$receipt.predecessor_receipt.sha256) 'mir4-f2d-aggregate-predecessor-sha'
    Assert-MIR4F2DAggregateV1 (@($receipt.package_visible_delta).Count -eq 0 -and [bool]$receipt.invariants.old_writer_remains_authoritative) 'mir4-f2d-aggregate-authority-boundary'
    Assert-MIR4F2DAggregateV1 (@($receipt.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-f2d-aggregate-target-transition-gate'

    $replayCommit = [string]$receipt.base.replay_commit
    $replayTree = [string]$receipt.base.replay_tree
    Assert-MIR4F2DAggregateV1 ($replayCommit -match '^[0-9a-f]{40}$' -and $replayTree -match '^[0-9a-f]{40}$') 'mir4-f2d-aggregate-replay-identity'
    & git -C $repo cat-file -e "$replayCommit`^{commit}"
    Assert-MIR4F2DAggregateV1 ($LASTEXITCODE -eq 0) 'mir4-f2d-aggregate-replay-commit-missing'
    $observedTree = (& git -C $repo rev-parse "$replayCommit`^{tree}").Trim()
    Assert-MIR4F2DAggregateV1 ($observedTree -ceq $replayTree) 'mir4-f2d-aggregate-replay-tree'

    $baseline = @($golden.targets | Where-Object target -eq ([string]$config.target))
    Assert-MIR4F2DAggregateV1 ($baseline.Count -eq 1) 'mir4-f2d-aggregate-baseline'
    $baseline = $baseline[0]
    Assert-MIR4F2DAggregateV1 ([string]$proof.package.distribution_version -ceq [string]$baseline.distribution_version -and [string]$proof.package.content_sha256 -ceq [string]$baseline.archive.content_sha256 -and [int]$proof.package.entry_count -eq [int]$baseline.archive.entry_count -and [string]$proof.package.archive_sha256 -match '^[A-F0-9]{64}$') 'mir4-f2d-aggregate-package'
    $predecessorArchive = Join-Path $repo "dist/more-infinite-research_$([string]$baseline.predecessor).zip"
    Assert-MIR4F2DAggregateV1 ([string]$proof.predecessor.version -ceq [string]$baseline.predecessor -and (Get-MIR4F2DAggregateFileSha256V1 $predecessorArchive) -ceq [string]$proof.predecessor.archive_sha256) 'mir4-f2d-aggregate-predecessor-package'

    if ([string]$config.target -ceq 'f210') {
      Assert-MIR4F2DAggregateV1 ([string]$proof.engine.selector -ceq 'latest-installed-official-2.1-experimental' -and [string]$proof.engine.version -ceq [string]$channel.current_review.version -and [string]$proof.engine.file_version -ceq [string]$channel.current_review.file_version -and [string]$proof.engine.binary_sha256 -ceq [string]$channel.current_review.binary_sha256) 'mir4-f2d-aggregate-f210-engine'
    } else {
      Assert-MIR4F2DAggregateV1 (Test-MIR4FixedFactorioEngineIdentity -Target ([string]$config.target) -ObservedIdentity $proof.engine -RepoRoot $repo) 'mir4-f2d-aggregate-fixed-engine'
    }

    Assert-MIR4F2DAggregateV1 ([string]$proof.fresh_load.status -ceq 'passed' -and [int]$proof.fresh_load.scenario_count -gt 0 -and [string]$proof.upgrade.status -ceq 'passed' -and [bool]$proof.upgrade.first_reload -and [bool]$proof.upgrade.second_reload) 'mir4-f2d-aggregate-runtime-result'
    $archetypeCount = if ($proof.upgrade.PSObject.Properties.Name -contains 'archetype_count') { [int]$proof.upgrade.archetype_count } else { @($proof.upgrade.archetypes).Count }
    Assert-MIR4F2DAggregateV1 ($archetypeCount -eq [int]$config.archetypes) 'mir4-f2d-aggregate-upgrade-archetypes'

    $candidateId = [string]$proof.candidate_id
    $logicalRoot = [string]$proof.evidence.logical_root
    Assert-MIR4F2DAggregateV1 (-not $candidateIds.ContainsKey($candidateId) -and -not $logicalRoots.ContainsKey($logicalRoot)) 'mir4-f2d-aggregate-cross-target-substitution'
    $candidateIds[$candidateId] = [string]$config.target
    $logicalRoots[$logicalRoot] = [string]$config.target
    $evidenceRoot = Resolve-MIR4F2DAggregateEvidenceRootV1 -EvidenceHome $evidenceHomeResolved -LogicalRoot $logicalRoot -ReplayCommit $replayCommit -Target ([string]$config.target)
    $requiredHashes = [ordered]@{
      'target-proof.json' = [string]$proof.evidence.target_proof_sha256
      'fresh-load-result.json' = [string]$proof.fresh_load.result_sha256
      'upgrade-matrix.json' = [string]$proof.upgrade.result_sha256
      'independent-verification.json' = [string]$proof.evidence.independent_verification_sha256
      'resource-receipt.json' = [string]$proof.resource.receipt_sha256
      'custody-manifest.json' = [string]$proof.evidence.custody_manifest_sha256
    }
    foreach ($name in $requiredHashes.Keys) {
      $path = Join-Path $evidenceRoot $name
      Assert-MIR4F2DAggregateV1 ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-MIR4F2DAggregateFileSha256V1 $path) -ceq [string]$requiredHashes[$name]) 'mir4-f2d-aggregate-evidence-hash'
    }
    $targetProof = Get-Content -Raw -LiteralPath (Join-Path $evidenceRoot 'target-proof.json') | ConvertFrom-Json -Depth 100
    $fresh = Get-Content -Raw -LiteralPath (Join-Path $evidenceRoot 'fresh-load-result.json') | ConvertFrom-Json -Depth 100
    $upgrade = Get-Content -Raw -LiteralPath (Join-Path $evidenceRoot 'upgrade-matrix.json') | ConvertFrom-Json -Depth 100
    $independent = Get-Content -Raw -LiteralPath (Join-Path $evidenceRoot 'independent-verification.json') | ConvertFrom-Json -Depth 100
    $resource = Get-Content -Raw -LiteralPath (Join-Path $evidenceRoot 'resource-receipt.json') | ConvertFrom-Json -Depth 100
    $custody = Get-Content -Raw -LiteralPath (Join-Path $evidenceRoot 'custody-manifest.json') | ConvertFrom-Json -Depth 100
    Assert-MIR4F2DAggregateV1 ([string]$targetProof.target -ceq [string]$config.target -and [string]$fresh.target -ceq [string]$config.target -and [string]$independent.target -ceq [string]$config.target -and [string]$resource.target -ceq [string]$config.target -and [string]$custody.target -ceq [string]$config.target) 'mir4-f2d-aggregate-evidence-target'
    Assert-MIR4F2DAggregateV1 ([string]$targetProof.source.commit -ceq $replayCommit -and [string]$targetProof.source.tree -ceq $replayTree -and [string]$upgrade.source_commit -ceq $replayCommit) 'mir4-f2d-aggregate-evidence-source'
    Assert-MIR4F2DAggregateV1 ([string]$fresh.status -ceq 'passed' -and [string]$upgrade.status -ceq 'passed' -and [string]$independent.status -ceq 'passed' -and [string]$resource.work_root_status -ceq 'removed' -and [string]$custody.status -ceq 'verified') 'mir4-f2d-aggregate-evidence-status'
    Assert-MIR4F2DAggregateV1 (@($upgrade.required_archetypes).Count -eq [int]$config.archetypes -and @($upgrade.rows | Where-Object { 'upgraded-save-reload-passed' -notin @($_.assertions) -or 'upgraded-save-second-reload-passed' -notin @($_.assertions) }).Count -eq 0) 'mir4-f2d-aggregate-evidence-reloads'
    Assert-MIR4F2DAggregateV1 (@($custody.files).Count -eq [int]$proof.evidence.custody_file_count) 'mir4-f2d-aggregate-custody-count'
    foreach ($file in @($custody.files)) {
      $relative = [string]$file.path
      Assert-MIR4F2DAggregateV1 (-not [IO.Path]::IsPathRooted($relative) -and $relative -notmatch '(^|[\\/])\.\.([\\/]|$)') 'mir4-f2d-aggregate-custody-path'
      $path = Join-Path $evidenceRoot $relative
      Assert-MIR4F2DAggregateV1 ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-MIR4F2DAggregateFileSha256V1 $path) -ceq [string]$file.sha256 -and [int64](Get-Item -LiteralPath $path).Length -eq [int64]$file.bytes) 'mir4-f2d-aggregate-custody-file'
    }
    $evidenceFiles = @(Get-ChildItem -LiteralPath $evidenceRoot -File | Sort-Object Name)
    Assert-MIR4F2DAggregateV1 ($evidenceFiles.Count -eq [int]$proof.evidence.evidence_file_count) 'mir4-f2d-aggregate-evidence-file-count'
    foreach ($file in $evidenceFiles) {
      $text = [IO.File]::ReadAllText($file.FullName)
      Assert-MIR4F2DAggregateV1 ($text -notmatch '[A-Za-z]:\\') 'mir4-f2d-aggregate-evidence-redaction'
    }

    $rows.Add([pscustomobject][ordered]@{
      target = [string]$config.target
      receipt = [pscustomobject][ordered]@{path=[string]$config.receipt;sha256=$receiptSha;kind=[string]$receipt.kind;status=[string]$receipt.status;predecessor_path=[string]$receipt.predecessor_receipt.path;predecessor_sha256=[string]$receipt.predecessor_receipt.sha256}
      replay = [pscustomobject][ordered]@{commit=$replayCommit;tree=$replayTree;candidate_id=$candidateId}
      engine = [pscustomobject][ordered]@{selector=[string]$proof.engine.selector;version=[string]$proof.engine.version;file_version=[string]$proof.engine.file_version;binary_sha256=[string]$proof.engine.binary_sha256}
      package = [pscustomobject][ordered]@{distribution_version=[string]$proof.package.distribution_version;archive_sha256=[string]$proof.package.archive_sha256;content_sha256=[string]$proof.package.content_sha256;entry_count=[int]$proof.package.entry_count}
      predecessor = [pscustomobject][ordered]@{version=[string]$proof.predecessor.version;archive_sha256=[string]$proof.predecessor.archive_sha256}
      runtime = [pscustomobject][ordered]@{fresh_load_result_sha256=[string]$proof.fresh_load.result_sha256;fresh_scenario_count=[int]$proof.fresh_load.scenario_count;upgrade_result_sha256=[string]$proof.upgrade.result_sha256;upgrade_archetype_count=$archetypeCount;first_reload=$true;second_reload=$true}
      evidence = [pscustomobject][ordered]@{logical_root=$logicalRoot;target_proof_sha256=[string]$proof.evidence.target_proof_sha256;independent_verification_sha256=[string]$proof.evidence.independent_verification_sha256;resource_receipt_sha256=[string]$proof.resource.receipt_sha256;custody_manifest_sha256=[string]$proof.evidence.custody_manifest_sha256;custody_file_count=[int]$proof.evidence.custody_file_count;evidence_file_count=[int]$proof.evidence.evidence_file_count;evidence_bytes=[int64]$proof.evidence.evidence_bytes;redacted=$true;verified=$true;work_root_status='removed'}
    })
  }

  for ($i=1; $i -lt $configs.Count; $i++) {
    Assert-MIR4F2DAggregateV1 ([string]$rows[$i].receipt.predecessor_path -ceq [string]$rows[$i-1].receipt.path -and [string]$rows[$i].receipt.predecessor_sha256 -ceq [string]$rows[$i-1].receipt.sha256) 'mir4-f2d-aggregate-receipt-chain'
  }
  $packageFingerprint = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  $readmeSha = Get-MIRFileContentSha256 -Path (Join-Path $repo 'README.md') -RelativePath 'README.md'
  Assert-MIR4F2DAggregateV1 ($packageFingerprint -ceq '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336') 'mir4-f2d-aggregate-package-source'
  Assert-MIR4F2DAggregateV1 ($readmeSha -ceq 'DF5D4D801DC4A416E4F7C9826EB2E3AE6CFD915937C8599CA7307CCEB343F947') 'mir4-f2d-aggregate-root-readme'
  return [pscustomobject][ordered]@{
    abi = 'mir4-f2d-four-target-aggregate/1'
    target_order = @('f210','f200','f110','f100')
    targets = @($rows)
    receipt_chain = 'verified'
    replay_commits_and_trees = 'verified'
    engine_identities = 'verified'
    package_and_transition_results = 'verified'
    external_custody = 'verified'
    evidence_path_redaction = 'verified'
    cross_target_substitution = 'rejected'
    package_source_sha256 = $packageFingerprint
    root_readme_sha256 = $readmeSha
    old_writer_authoritative = $true
  }
}
