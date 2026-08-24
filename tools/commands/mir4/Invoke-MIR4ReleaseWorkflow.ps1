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
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path,
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')
$parameters = @{
  RepoRoot=$RepoRoot;Phase=$Phase;SourceReleaseRecord=$SourceReleaseRecord;CandidateId=$CandidateId
  SourceCommit=$SourceCommit;SourceTree=$SourceTree;TargetDistributionRecordSet=$TargetDistributionRecordSet
  ReleasePlanDigest=$ReleasePlanDigest;ProofRoot=$ProofRoot;SealRoot=$SealRoot
}
$result = Test-MIR4ReleaseWorkflowInvocation @parameters
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  $full = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $RepoRoot $OutputPath }
  New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
  [IO.File]::WriteAllText($full,($result|ConvertTo-Json -Depth 30)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}
$result | ConvertTo-Json -Depth 30
