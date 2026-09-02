param(
  [Parameter(Mandatory)][ValidateSet('show','check','phase')][string]$Command,
  [string]$Phase = '',
  [string]$SourceReleaseRecord = '',
  [string]$CandidateId = '',
  [string]$SourceCommit = '',
  [string]$SourceTree = '',
  [string]$TargetDistributionRecordSet = '',
  [string]$ReleasePlanDigest = '',
  [string]$ProofRoot = '',
  [string]$SealRoot = '',
  [ValidateSet('Plan','DryRun','Execute','Resume','Verify','Compensate','Receipt')][string]$Operation = 'DryRun',
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path,
  [string]$OutputRoot = '',
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/ReleaseApplicationDag.ps1')

$result = switch ($Command) {
  'show' { Get-MIR4ReleaseApplicationDagV1 -RepoRoot $RepoRoot }
  'check' { Test-MIR4ReleaseApplicationDagV1 -RepoRoot $RepoRoot }
  'phase' {
    foreach ($field in @('Phase','SourceReleaseRecord','CandidateId','SourceCommit','SourceTree','TargetDistributionRecordSet','ReleasePlanDigest','ProofRoot','SealRoot')) {
      if ([string]::IsNullOrWhiteSpace([string](Get-Variable -Name $field -ValueOnly))) { throw "[mir4-release-engine-required] $field" }
    }
    Invoke-MIR4ReleaseApplicationPhaseV1 -RepoRoot $RepoRoot -Phase $Phase -SourceReleaseRecord $SourceReleaseRecord -CandidateId $CandidateId -SourceCommit $SourceCommit -SourceTree $SourceTree -TargetDistributionRecordSet $TargetDistributionRecordSet -ReleasePlanDigest $ReleasePlanDigest -ProofRoot $ProofRoot -SealRoot $SealRoot -Operation $Operation -OutputRoot $OutputRoot
  }
}
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  $full = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $RepoRoot $OutputPath }
  New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
  [IO.File]::WriteAllText($full,($result | ConvertTo-Json -Depth 100) + [Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}
$result | ConvertTo-Json -Depth 100
