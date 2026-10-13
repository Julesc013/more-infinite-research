# MIR4-CONTROLLED-STATIC-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
$script:mir430ContractAssertions=0
function Assert-MIR430Contract([bool]$Condition,[string]$Message) {
  if(-not $Condition){throw $Message}
  $script:mir430ContractAssertions++
}
$previous=Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion '4.2.3'
$current=Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion '4.3.0'
Assert-MIR430Contract (($previous|ConvertTo-Json -Compress)-ceq($current|ConvertTo-Json -Compress)) '4.3.0 must retain exact published 4.2.2 custody.'
$pin=Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath (Join-Path $repo 'fixtures/release-inputs/mir423-published-422-manifest.json') -CandidateSourceVersion '4.3.0'
Assert-MIR430Contract ($pin.sha256-ceq$current.manifest_sha256 -and $pin.bytes-eq$current.manifest_bytes) '4.3.0 must validate original receipt bytes.'
$refused=$false
try {Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion '4.3.1'|Out-Null}catch{$refused=$true}
Assert-MIR430Contract $refused 'Future 4.3.1 custody cannot be invented before publication.'

# Exercise the real scoped engine-contract functions with a controlled
# construction descriptor. Complete candidate/schema/custody validation is
# separately owned by the actual package and technical-seal readers; this
# fixture does not produce a package, engine pass, seal or release authority.
$constructionReader=(Get-Command Get-MIR42SealCandidateConstructionVersionContract).ScriptBlock
try {
  Set-Item Function:script:Get-MIR42SealCandidateConstructionVersionContract -Value {
    param($RepoRoot,$Manifest)
    Get-MIR42CandidateConstructionVersionContract -RepoRoot $RepoRoot -Manifest $Manifest
  }
  $candidate=[pscustomobject]@{scope='nine-target';targets=@($script:MIR42SealNineTargetCandidates|ForEach-Object{[pscustomobject]@{target=$_}});identity=[pscustomobject]@{record=[pscustomobject]@{schema=5;kind='MIR42FourTargetDeterministicCandidateManifestV5'}}}
  $contract=Get-MIR42IndividualEngineEvidenceBindingContract -Candidate $candidate -PublishedMaintenance
  Assert-MIR430Contract ($contract.maintenance_source_version-ceq'4.3.0') 'Individual evidence must consume the full candidate source version.'
  Assert-MIR430Contract ($contract.binder_status.Contains('MIR-4.3.0-')) 'Individual evidence status must name the current candidate.'
  $candidate.identity.record.schema=6;$candidate.identity.record.kind='MIR42FourTargetDeterministicCandidateManifestV6'
  $refused=$false
  try {Get-MIR42IndividualEngineEvidenceBindingContract -Candidate $candidate -PublishedMaintenance|Out-Null}catch{$refused=$true}
  Assert-MIR430Contract $refused 'Unpublished 4.3.1 evidence must remain refused.'
  $candidate.identity.record.schema=5;$candidate.identity.record.kind='MIR42FourTargetDeterministicCandidateManifestV5'
  $candidate.scope='four-target';$candidate.targets=@($script:MIR42SealTargets|ForEach-Object{[pscustomobject]@{target=$_}})
  $refused=$false
  try {Get-MIR42IndividualEngineEvidenceBindingContract -Candidate $candidate -PublishedMaintenance|Out-Null}catch{$refused=$true}
  Assert-MIR430Contract $refused 'A four-target subset must not satisfy nine-target maintenance evidence.'
} finally {
  Set-Item Function:script:Get-MIR42SealCandidateConstructionVersionContract -Value $constructionReader
}
[pscustomobject]@{status='MIR430-RELEASE-CONTRACT-CONTROLS-PASSED';assertions=$script:mir430ContractAssertions;factorio_processes=0;publication_authorized=$false}
