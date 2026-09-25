Set-StrictMode -Version Latest

$mir42PromotionRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
if (-not (Get-Command Get-MIR42ExactFourTargetCandidate -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'MIR42TechnicalSeal.ps1')
}

function Get-MIR42ProtectedMainPromotionPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$TechnicalSealPath,
    [Parameter(Mandatory)][string]$CandidateManifestPath
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $candidate = Get-MIR42ExactFourTargetCandidate -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath
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
  $main = @(& git -C $repo rev-parse --verify refs/remotes/origin/main 2>$null)
  if ($LASTEXITCODE -ne 0 -or $main.Count -ne 1 -or ([string]$main[0]).Trim() -notmatch '^[a-f0-9]{40}$') { throw '[mir42-promotion-main-ref]' }
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42ProtectedMainPromotionPlanV1'
    status = 'MIR-4.2-PROTECTED-MAIN-PROMOTION-PLAN-ONLY'
    source = $candidate.source
    technical_seal = [ordered]@{sha256=[string]$seal.sha256;record_sha256=[string]$seal.record.record_sha256}
    main_before = ([string]$main[0]).Trim()
    target = 'main'
    merge_method = 'squash'
    pull_request_required = $true
    linear_history_required = $true
    required_status_checks = @('branch-policy','verification-gate')
    bypass_actors_allowed = 0
    force_push = $false
    ruleset_mutation = $false
    remote_mutation_performed = $false
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
  }
}
