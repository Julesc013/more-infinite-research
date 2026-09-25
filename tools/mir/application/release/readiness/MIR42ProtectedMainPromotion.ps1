Set-StrictMode -Version Latest

$mir42PromotionRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
if (-not (Get-Command Get-MIR42ExactFourTargetCandidate -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'MIR42TechnicalSeal.ps1')
}

function Get-MIR42PromotionRemoteRef {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Ref,[Parameter(Mandatory)][string]$Code)
  $rows = @(& git -C $RepoRoot ls-remote --refs origin $Ref 2>$null)
  if ($LASTEXITCODE -ne 0 -or $rows.Count -ne 1 -or $rows[0] -notmatch '^([a-f0-9]{40})\s+') {
    throw "[$Code]"
  }
  return [string]$Matches[1]
}

function Get-MIR42FourTargetOfflineRestoreDrill {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Seal)
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-promotion-restore-drill'
  $record = $receipt.record
  Assert-MIR42SealPropertyNames -Value $record -Expected @('schema','kind','status','source','candidate_manifest','technical_seal','capsule','restored_inventory','targets','clean_untracked_root','publication_authorized','record_sha256') -Code 'mir42-promotion-restore-drill-shape'
  if ([int]$record.schema -ne 1 -or
      [string]$record.kind -cne 'MIR42FourTargetOfflineRestoreDrillV1' -or
      [string]$record.status -cne 'MIR-4.2-FOUR-TARGET-OFFLINE-RESTORE-DRILL-PASSED-PRIVATE-UNSEALED' -or
      [string]$record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$record.source.tree -cne [string]$Candidate.source.tree -or
      [string]$record.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256 -or
      -not [bool]$record.clean_untracked_root -or [bool]$record.publication_authorized) {
    throw '[mir42-promotion-restore-drill-state]'
  }
  Assert-MIR42SealPropertyNames -Value $record.capsule -Expected @('path','sha256') -Code 'mir42-promotion-restore-drill-capsule-shape'
  $capsulePath = Resolve-MIR42SealImmutableFile -Path ([string]$record.capsule.path) -Sha256 ([string]$record.capsule.sha256) -Code 'mir42-promotion-restore-drill-capsule'
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $capsule = [IO.Compression.ZipFile]::OpenRead($capsulePath)
    try { $capsuleEntries = @($capsule.Entries | Where-Object { -not [string]::IsNullOrEmpty([string]$_.Name) } | ForEach-Object { [string]$_.FullName }) }
    finally { $capsule.Dispose() }
  } catch { throw '[mir42-promotion-restore-drill-capsule-zip]' }
  $expectedCapsuleEntries = @('candidate-manifest.json','technical-seal.json') + @($script:MIR42SealTargets | ForEach-Object { "target-rows/$_.json" }) + @($Candidate.targets | ForEach-Object { "assets/$([IO.Path]::GetFileName([string]$_.archive_path))" })
  if ($capsuleEntries.Count -ne $expectedCapsuleEntries.Count -or
      ((@($capsuleEntries | Sort-Object) -join '|') -cne (@($expectedCapsuleEntries | Sort-Object) -join '|'))) {
    throw '[mir42-promotion-restore-drill-capsule-members]'
  }
  foreach ($field in @('candidate_manifest','technical_seal')) {
    Assert-MIR42SealPropertyNames -Value $record.$field -Expected @('path','sha256','record_sha256') -Code "mir42-promotion-restore-drill-$field-shape"
    $file = Resolve-MIR42SealImmutableFile -Path ([string]$record.$field.path) -Sha256 ([string]$record.$field.sha256) -Code "mir42-promotion-restore-drill-$field"
    $bound = Read-MIR42SealRecord -Path $file -Code "mir42-promotion-restore-drill-$field"
    $expected = if ($field -eq 'candidate_manifest') { $Candidate.identity } else { $Seal }
    if ([string]$bound.sha256 -cne [string]$expected.sha256 -or
        [string]$bound.record.record_sha256 -cne [string]$expected.record.record_sha256 -or
        [string]$record.$field.record_sha256 -cne [string]$expected.record.record_sha256) {
      throw "[mir42-promotion-restore-drill-$field-binding]"
    }
  }
  Assert-MIR42SealTargetSet -Rows @($record.targets) -Code 'mir42-promotion-restore-drill'
  foreach ($candidateTarget in @($Candidate.targets)) {
    $row = @($record.targets | Where-Object { [string]$_.target -ceq [string]$candidateTarget.target })
    if ($row.Count -ne 1) { throw "[mir42-promotion-restore-drill-target-cardinality] $([string]$candidateTarget.target)" }
    Assert-MIR42SealPropertyNames -Value $row[0] -Expected @('target','archive','restored_archive') -Code 'mir42-promotion-restore-drill-target-shape'
    foreach ($field in @('archive','restored_archive')) {
      $expected = if ($field -eq 'archive') { @('sha256','content_sha256','entry_count') } else { @('path','sha256','content_sha256','entry_count') }
      Assert-MIR42SealPropertyNames -Value $row[0].$field -Expected $expected -Code "mir42-promotion-restore-drill-$field-shape"
      if ([string]$row[0].$field.sha256 -cne [string]$candidateTarget.archive_sha256 -or
          [string]$row[0].$field.content_sha256 -cne [string]$candidateTarget.content_sha256 -or
          [int]$row[0].$field.entry_count -ne [int]$candidateTarget.entry_count) {
        throw "[mir42-promotion-restore-drill-$field-binding] $([string]$candidateTarget.target)"
      }
    }
    $restoredPath = Resolve-MIR42SealImmutableFile -Path ([string]$row[0].restored_archive.path) -Sha256 ([string]$row[0].restored_archive.sha256) -Code 'mir42-promotion-restore-drill-restored-archive'
    try { $inventory = Get-MIR4ArchiveInventory -Path $restoredPath }
    catch { throw "[mir42-promotion-restore-drill-restored-archive-invalid] $([string]$candidateTarget.target)" }
    if ([string]$inventory.archive_sha256 -cne [string]$candidateTarget.archive_sha256 -or
        [string]$inventory.content_sha256 -cne [string]$candidateTarget.content_sha256 -or
        [int]$inventory.entry_count -ne [int]$candidateTarget.entry_count) {
      throw "[mir42-promotion-restore-drill-restored-archive-inventory] $([string]$candidateTarget.target)"
    }
  }
  $restoredInventory = @($record.restored_inventory)
  $requiredRestoredHashes = @([string]$Candidate.identity.sha256,[string]$Seal.sha256) + @($Candidate.targets | ForEach-Object { [string]$_.archive_sha256 })
  if ($restoredInventory.Count -ne $expectedCapsuleEntries.Count -or
      @($restoredInventory | Where-Object { $_.PSObject.Properties.Name -notcontains 'path' -or $_.PSObject.Properties.Name -notcontains 'sha256' }).Count -ne 0) {
    throw '[mir42-promotion-restore-drill-restored-inventory-shape]'
  }
  foreach ($restored in $restoredInventory) {
    Assert-MIR42SealPropertyNames -Value $restored -Expected @('path','sha256') -Code 'mir42-promotion-restore-drill-restored-inventory-row-shape'
    $null = Resolve-MIR42SealImmutableFile -Path ([string]$restored.path) -Sha256 ([string]$restored.sha256) -Code 'mir42-promotion-restore-drill-restored-inventory-row'
  }
  foreach ($requiredHash in $requiredRestoredHashes) {
    if (@($restoredInventory | Where-Object { [string]$_.sha256 -ceq $requiredHash }).Count -ne 1) {
      throw '[mir42-promotion-restore-drill-restored-inventory-binding]'
    }
  }
  return $receipt
}

function Get-MIR42ProtectedMainPromotionPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$TechnicalSealPath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$QualificationPath,
    [Parameter(Mandatory)][string]$RealEngineCampaignPath,
    [Parameter(Mandatory)][string]$IndependentVerificationPath,
    [Parameter(Mandatory)][string]$SigningCeremonyPath,
    [Parameter(Mandatory)][string]$SourceFreezeAuthorityPath,
    [Parameter(Mandatory)][string]$ReviewerAttestationPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$OfflineRestoreDrillPath
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $readiness = Get-MIR42FourTargetTechnicalSealReadiness -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath `
    -QualificationPath $QualificationPath -RealEngineCampaignPath $RealEngineCampaignPath -IndependentVerificationPath $IndependentVerificationPath `
    -SigningCeremonyPath $SigningCeremonyPath -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -ReviewerAttestationPath $ReviewerAttestationPath -SshKeygenPath $SshKeygenPath
  if (-not [bool]$readiness.technical_seal_authorized) { throw "[mir42-promotion-verified-seal-inputs] $($readiness.blockers -join '; ')" }
  $candidate = $readiness._state.candidate
  $seal = Read-MIR42SealRecord -Path $TechnicalSealPath -Code 'mir42-promotion-seal'
  if ([string]$seal.record.kind -cne 'MIR42FourTargetTechnicalSealV1' -or
      [string]$seal.record.status -cne 'MIR-4.2-FOUR-TARGET-TECHNICALLY-SEALED-AWAITING-PROTECTED-MAIN-PR' -or
      [string]$seal.record.candidate_manifest.sha256 -cne [string]$candidate.identity.sha256 -or
      [string]$seal.record.candidate_manifest.record_sha256 -cne [string]$candidate.identity.record.record_sha256 -or
      [string]$seal.record.source.commit -cne [string]$candidate.source.commit -or
      [string]$seal.record.source.tree -cne [string]$candidate.source.tree -or
      [string]$seal.record.source.package_source_sha256 -cne [string]$candidate.source.package_source_sha256 -or
      [bool]$seal.record.protected_main_promotion_authorized -or [bool]$seal.record.tagging_authorized -or
      [bool]$seal.record.publication_authorized) {
    throw '[mir42-promotion-seal-binding]'
  }
  foreach ($binding in @(
    @('qualification',$readiness._state.qualification),
    @('real_engine_campaign',$readiness._state.campaign),
    @('independent_verification',$readiness._state.independent),
    @('signing_ceremony',$readiness._state.signing),
    @('source_freeze_authority',$readiness._state.freeze),
    @('independent_reviewer_attestation',$readiness._state.reviewer)
  )) {
    $name = [string]$binding[0]; $proof = $binding[1]
    if ([string]$seal.record.$name.sha256 -cne [string]$proof.sha256 -or
        [string]$seal.record.$name.record_sha256 -cne [string]$proof.record.record_sha256) {
      throw "[mir42-promotion-seal-proof-binding] $name"
    }
  }
  $restoreDrill = Get-MIR42FourTargetOfflineRestoreDrill -Path $OfflineRestoreDrillPath -Candidate $candidate -Seal $seal
  $topologyPath = Join-Path $repo 'spec/releases/mir4-protected-main-promotion-topology-v1.json'
  $schemaPath = Join-Path $repo 'spec/schemas/mir4-protected-main-promotion-topology-v1.schema.json'
  $topologyRaw = Get-Content -Raw -LiteralPath $topologyPath
  if (-not ($topologyRaw | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) { throw '[mir42-promotion-topology-schema]' }
  $topology = $topologyRaw | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$topology.status -cne 'implemented-and-synthetically-rehearsed-release-blocked' -or
      [string]$topology.promotion.target -cne 'main' -or [string]$topology.promotion.merge_method -cne 'squash' -or
      -not [bool]$topology.promotion.pull_request_required -or -not [bool]$topology.promotion.linear_history_required -or
      -not [bool]$topology.promotion.protected_request_contract_required -or
      ((@($topology.promotion.required_status_checks | Sort-Object) -join '|') -cne 'branch-policy|verification-gate') -or
      [bool]$topology.promotion.force_push -or [bool]$topology.promotion.ruleset_mutation -or
      [int]$topology.promotion.bypass_actor_count -ne 0 -or [bool]$topology.authority.main_mutation -or
      [bool]$topology.authority.tagging -or [bool]$topology.authority.publication) {
    throw '[mir42-promotion-protected-topology]'
  }
  $main = Get-MIR42PromotionRemoteRef -RepoRoot $repo -Ref 'refs/heads/main' -Code 'mir42-promotion-main-ref-readback'
  $dev = Get-MIR42PromotionRemoteRef -RepoRoot $repo -Ref 'refs/heads/dev' -Code 'mir42-promotion-dev-ref-readback'
  $freeze = $readiness._state.freeze.record
  if ([string]$freeze.promotion_base.commit -cne $main -or
      [string]$freeze.frozen_dev.commit -cne $dev -or
      [string]$freeze.frozen_dev.commit -cne [string]$candidate.source.commit -or
      [string]$freeze.frozen_dev.tree -cne [string]$candidate.source.tree) {
    throw '[mir42-promotion-frozen-ref-drift]'
  }
  $candidateRef = 'refs/heads/release/mir-4.2-candidate-' + ([string]$candidate.source.commit).Substring(0,12)
  $candidateRefRows = @(& git -C $repo ls-remote --refs origin $candidateRef 2>$null)
  if ($LASTEXITCODE -ne 0) { throw '[mir42-promotion-candidate-ref-readback]' }
  if ($candidateRefRows.Count -ne 0) { throw '[mir42-promotion-candidate-ref-already-exists]' }
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42ProtectedMainPromotionPlanV1'
    status = 'MIR-4.2-PROTECTED-MAIN-PROMOTION-PLAN-ONLY'
    source = $candidate.source
    technical_seal = [ordered]@{sha256=[string]$seal.sha256;record_sha256=[string]$seal.record.record_sha256}
    offline_restore_drill = [ordered]@{sha256=[string]$restoreDrill.sha256;record_sha256=[string]$restoreDrill.record.record_sha256}
    main_before = $main
    frozen_dev = [ordered]@{ref='refs/heads/dev';commit=[string]$candidate.source.commit;tree=[string]$candidate.source.tree}
    candidate = [ordered]@{
      ref = $candidateRef
      base_ref = 'refs/heads/main'
      base_commit = $main
      parent_count = 1
      exact_tree = [string]$candidate.source.tree
      source_commit_trailer = "MIR4-Frozen-Dev-Commit: $([string]$candidate.source.commit)"
      create_only = $true
      remote_ref_must_be_absent = $true
    }
    target = 'main'
    merge_method = 'squash'
    pull_request_required = $true
    linear_history_required = $true
    required_status_checks = @('branch-policy','verification-gate')
    bypass_actors_allowed = 0
    force_push = $false
    ruleset_mutation = $false
    remote_mutation_performed = $false
    offline_restore_drill_required_after_technical_seal = $true
    offline_restore_drill_completed = $true
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
  }
}
