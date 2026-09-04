param(
  [Parameter(Mandatory)][ValidateSet('show','check','phase','readiness-check','candidate-build','qualification','independent-verify','technical-seal','prepare-tag','promotion-plan','promote')][string]$Command,
  [string]$Phase = '',
  [string]$SourceReleaseRecord = '',
  [string]$CandidateId = '',
  [string]$SourceCommit = '',
  [string]$SourceTree = '',
  [string]$TargetDistributionRecordSet = '',
  [string]$ReleasePlanDigest = '',
  [string]$ProofRoot = '',
  [string]$SealRoot = '',
  [string]$WorkRoot = '',
  [string]$EvidenceRoot = '',
  [string]$SigningKey = '',
  [ValidateSet('Plan','DryRun','Execute','Resume','Verify','Compensate','Receipt')][string]$Operation = 'DryRun',
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path,
  [string]$OutputRoot = '',
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/ReleaseApplicationDag.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/MIR441ReleaseReadiness.ps1')

$result = switch ($Command) {
  'show' { Get-MIR4ReleaseApplicationDagV1 -RepoRoot $RepoRoot }
  'check' { Test-MIR4ReleaseApplicationDagV1 -RepoRoot $RepoRoot }
  'readiness-check' { Test-MIR441ReleaseReadiness -RepoRoot $RepoRoot -WorkRoot $WorkRoot }
  'candidate-build' {
    foreach ($field in @('WorkRoot','EvidenceRoot')) {
      if ([string]::IsNullOrWhiteSpace([string](Get-Variable -Name $field -ValueOnly))) { throw "[mir441-release-engine-required] $field" }
    }
    New-MIR441FourTargetCandidate -RepoRoot $RepoRoot -WorkRoot $WorkRoot -EvidenceRoot $EvidenceRoot
  }
  'qualification' {
    foreach ($field in @('WorkRoot','EvidenceRoot')) { if ([string]::IsNullOrWhiteSpace([string](Get-Variable -Name $field -ValueOnly))) { throw "[mir441-release-engine-required] $field" } }
    Invoke-MIR441FourTargetQualification -RepoRoot $RepoRoot -WorkRoot $WorkRoot -EvidenceRoot $EvidenceRoot
  }
  'independent-verify' {
    if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { throw '[mir441-release-engine-required] EvidenceRoot' }
    Test-MIR441IndependentQualification -RepoRoot $RepoRoot -EvidenceRoot $EvidenceRoot
  }
  'technical-seal' {
    foreach ($field in @('WorkRoot','EvidenceRoot')) { if ([string]::IsNullOrWhiteSpace([string](Get-Variable -Name $field -ValueOnly))) { throw "[mir441-release-engine-required] $field" } }
    New-MIR441TechnicalSeal -RepoRoot $RepoRoot -WorkRoot $WorkRoot -EvidenceRoot $EvidenceRoot
  }
  'prepare-tag' {
    if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { throw '[mir441-release-engine-required] EvidenceRoot' }
    & (Join-Path $EvidenceRoot 'release-window/Prepare-MIR410SignedTag.ps1') -RepoRoot $RepoRoot -SigningKey $SigningKey
  }
  'promotion-plan' {
    if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { throw '[mir441-release-engine-required] EvidenceRoot' }
    Invoke-MIR441ExactMainPromotion -RepoRoot $RepoRoot -EvidenceRoot $EvidenceRoot -Plan
  }
  'promote' {
    if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) { throw '[mir441-release-engine-required] EvidenceRoot' }
    Invoke-MIR441ExactMainPromotion -RepoRoot $RepoRoot -EvidenceRoot $EvidenceRoot
  }
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
