param(
  [Parameter(Mandatory)][ValidateSet('source-freeze','target-build','target-qualification','preview-assets','independent-verification','release-seal','promotion','target-publication','public-readback','restore-drill')][string]$Phase,
  [Parameter(Mandatory)][string]$SourceReleaseRecord,
  [Parameter(Mandatory)][string]$CandidateId,
  [Parameter(Mandatory)][string]$SourceCommit,
  [Parameter(Mandatory)][string]$SourceTree,
  [Parameter(Mandatory)][string]$TargetDistributionRecordSet,
  [Parameter(Mandatory)][string]$ReleasePlanDigest,
  [Parameter(Mandatory)][string]$ProofRoot,
  [Parameter(Mandatory)][string]$SealRoot,
  [ValidateSet('Plan','DryRun','Execute','Resume','Verify','Compensate','Receipt')][string]$Operation = 'DryRun',
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path,
  [string]$OutputRoot = '',
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
# MIR4-RELEASE-WORKFLOW-COMPATIBILITY-COMMAND
& (Join-Path $RepoRoot 'tools/mir/cli/Invoke-MIR4ReleaseEngine.ps1') -Command phase -Phase $Phase -SourceReleaseRecord $SourceReleaseRecord -CandidateId $CandidateId -SourceCommit $SourceCommit -SourceTree $SourceTree -TargetDistributionRecordSet $TargetDistributionRecordSet -ReleasePlanDigest $ReleasePlanDigest -ProofRoot $ProofRoot -SealRoot $SealRoot -Operation $Operation -RepoRoot $RepoRoot -OutputRoot $OutputRoot -OutputPath $OutputPath
