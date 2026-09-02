. (Join-Path $PSScriptRoot '../../../lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $PSScriptRoot '../../../lib/mir4/ReleasePhaseEngine.ps1')
. (Join-Path $PSScriptRoot '../../../lib/mir4/ReleaseAdapters.ps1')

function Get-MIR4ReleaseApplicationDagV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo 'governance/release/mir4-release-application-dag-v1.json'
  $schema = Join-Path $repo 'contracts/repository/mir4-release-application-dag-v1.schema.json'
  $json = Get-Content -Raw -LiteralPath $path
  if (-not ($json | Test-Json -SchemaFile $schema)) { throw '[mir4-release-application-dag-schema]' }
  return $json | ConvertFrom-Json -Depth 100
}

function Test-MIR4ReleaseApplicationDagV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $dag = Get-MIR4ReleaseApplicationDagV1 -RepoRoot $repo
  $nodes = @($dag.nodes)
  $ids = @($nodes | ForEach-Object { [string]$_.id })
  if ($ids.Count -ne @($ids | Sort-Object -Unique).Count) { throw '[mir4-release-application-dag-duplicate-node]' }
  $required = @(
    'release-intent','source-freeze','affected-targets','target-build','focused-qualification',
    'candidate-qualification','manual-acceptance','protected-qualification','seal-rehearsal',
    'promotion-rehearsal','tag-rehearsal','publication-rehearsal','public-readback-rehearsal',
    'restore','reporting'
  )
  if (@($required | Where-Object { $_ -notin $ids }).Count -ne 0) { throw '[mir4-release-application-dag-required-node]' }
  $byId = @{}
  foreach ($node in $nodes) { $byId[[string]$node.id] = $node }
  foreach ($node in $nodes) {
    foreach ($dependency in @($node.depends_on)) {
      if (-not $byId.ContainsKey([string]$dependency)) { throw "[mir4-release-application-dag-dependency] $($node.id)/$dependency" }
    }
  }
  $visiting = @{}
  $visited = @{}
  function Visit-MIR4ReleaseApplicationNodeV1([string]$Id) {
    if ($visiting[$Id]) { throw "[mir4-release-application-dag-cycle] $Id" }
    if ($visited[$Id]) { return }
    $visiting[$Id] = $true
    foreach ($dependency in @($byId[$Id].depends_on)) { Visit-MIR4ReleaseApplicationNodeV1 ([string]$dependency) }
    $visiting.Remove($Id)
    $visited[$Id] = $true
  }
  foreach ($id in $ids) { Visit-MIR4ReleaseApplicationNodeV1 $id }

  $phaseContract = (Get-MIR4ReleasePhaseContract -RepoRoot $repo).record
  foreach ($node in @($nodes | Where-Object executor -eq 'phase-engine')) {
    if ([string]$node.phase -notin @($phaseContract.phases)) { throw "[mir4-release-application-dag-phase] $($node.id)" }
  }
  if ([bool]$dag.engine.production_capable -or [bool]$dag.engine.production_authorized) { throw '[mir4-release-application-production-capability]' }
  if (@($dag.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) { throw '[mir4-release-application-transition-gate]' }
  if (@($dag.publisher.forbidden_capabilities) -notcontains 'build' -or
      @($dag.publisher.forbidden_capabilities) -notcontains 'source-checkout' -or
      @($dag.publisher.allowed_capabilities) -contains 'build') {
    throw '[mir4-release-application-publisher-build-capability]'
  }
  if ([string]$dag.independent_verifier.node -cne 'protected-qualification' -or
      -not [bool]$dag.independent_verifier.dependency_minimal -or
      -not [bool]$dag.independent_verifier.separate_from_build) {
    throw '[mir4-release-application-independent-verifier]'
  }
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4ReleaseApplicationDagCheckV1'
    status = 'M42-01-RELEASE-APPLICATION-DAG-PASSED'
    node_count = $nodes.Count
    phase_engine_node_count = @($nodes | Where-Object executor -eq 'phase-engine').Count
    publisher_can_build = $false
    production_authorized = $false
    publication_authorized = $false
  }
}

function Invoke-MIR4ReleaseApplicationPhaseV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Phase,
    [Parameter(Mandatory)][string]$SourceReleaseRecord,
    [Parameter(Mandatory)][string]$CandidateId,
    [Parameter(Mandatory)][string]$SourceCommit,
    [Parameter(Mandatory)][string]$SourceTree,
    [Parameter(Mandatory)][string]$TargetDistributionRecordSet,
    [Parameter(Mandatory)][string]$ReleasePlanDigest,
    [Parameter(Mandatory)][string]$ProofRoot,
    [Parameter(Mandatory)][string]$SealRoot,
    [ValidateSet('Plan','DryRun','Execute','Resume','Verify','Compensate','Receipt')][string]$Operation = 'DryRun',
    [string]$OutputRoot = ''
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $dag = Get-MIR4ReleaseApplicationDagV1 -RepoRoot $repo
  $matches = @($dag.nodes | Where-Object { [string]$_.executor -ceq 'phase-engine' -and [string]$_.phase -ceq $Phase })
  if ($matches.Count -ne 1) { throw "[mir4-release-application-phase-route] $Phase" }
  $parameters = @{
    RepoRoot=$repo;Phase=$Phase;SourceReleaseRecord=$SourceReleaseRecord;CandidateId=$CandidateId
    SourceCommit=$SourceCommit;SourceTree=$SourceTree;TargetDistributionRecordSet=$TargetDistributionRecordSet
    ReleasePlanDigest=$ReleasePlanDigest;ProofRoot=$ProofRoot;SealRoot=$SealRoot
  }
  $validation = Test-MIR4ReleaseWorkflowInvocation @parameters -NonProductionRehearsal
  $inputs = [pscustomobject][ordered]@{
    source_release_record=$SourceReleaseRecord;candidate_id=$CandidateId;source_commit=$SourceCommit;source_tree=$SourceTree
    target_distribution_record_set=$TargetDistributionRecordSet;release_plan_digest=$ReleasePlanDigest
    proof_root=$ProofRoot;seal_root=$SealRoot
  }
  $adapter = Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase $Phase
  $result = Invoke-MIR4ReleasePhaseEngine -RepoRoot $repo -Operation $Operation -Phase $Phase -Inputs $inputs -Adapter $adapter -OutputRoot $OutputRoot
  $result | Add-Member -NotePropertyName application_node -NotePropertyValue ([string]$matches[0].id) -Force
  $result | Add-Member -NotePropertyName validation -NotePropertyValue $validation -Force
  return $result
}
