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
    [Parameter(Mandatory)][string]$SshKeygenPath
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
    offline_restore_drill_completed = $false
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
  }
}
