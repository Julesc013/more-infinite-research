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
$next=Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion '4.3.1'
Assert-MIR430Contract ($next.source_version-ceq'4.3.0' -and $next.source_tag-ceq'v4.3.0' -and $next.release_id-eq411700807 -and $next.asset_count-eq15 -and $next.target_commitish-ceq'main') '4.3.1 must bind the published 4.3.0 custody contract exactly.'
$nextPin=Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath (Join-Path $repo 'fixtures/release-inputs/mir431-published-430-manifest.json') -CandidateSourceVersion '4.3.1'
Assert-MIR430Contract ($nextPin.sha256-ceq$next.manifest_sha256 -and $nextPin.bytes-eq$next.manifest_bytes) '4.3.1 must authenticate the recorded 4.3.0 manifest bytes.'
$nextPinRelative='fixtures/release-inputs/mir431-published-430-manifest.json'
$nextPinAttributes=@(& git -C $repo check-attr text eol whitespace -- $nextPinRelative)
Assert-MIR430Contract (($nextPinAttributes -join "`n") -match '(?m)text: unset$' -and ($nextPinAttributes -join "`n") -match '(?m)eol: unset$' -and ($nextPinAttributes -join "`n") -match '(?m)whitespace: blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol$') '4.3.1 published 4.3.0 manifest must retain its raw-byte checkout attributes.'
$nextPinIndex=@(& git -C $repo ls-files -s -- $nextPinRelative)
if($nextPinIndex.Count-ne1-or$nextPinIndex[0]-notmatch'^[0-9]{6} (?<oid>[0-9a-f]{40}) 0\t') { throw '4.3.1 published 4.3.0 manifest must be staged with one index blob.' }
$nextPinWorkingOid=(& git -C $repo hash-object -- $nextPinRelative).Trim()
Assert-MIR430Contract ($nextPinWorkingOid-ceq$Matches.oid) '4.3.1 published 4.3.0 manifest index blob must match its exact working bytes.'
$direct431=Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion '4.2.3'
Assert-MIR430Contract ($direct431.source_version-ceq'4.2.2' -and $direct431.source_tag-ceq'v4.2.2') '4.3.1 direct evidence must retain the exact published 4.2.2 custody reader.'
$direct431Pin=Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath (Join-Path $repo 'fixtures/release-inputs/mir423-published-422-manifest.json') -CandidateSourceVersion '4.2.3'
Assert-MIR430Contract ($direct431Pin.sha256-ceq$direct431.manifest_sha256 -and $direct431Pin.bytes-eq$direct431.manifest_bytes) '4.3.1 direct evidence must authenticate the recorded 4.2.2 manifest bytes.'

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
  $contract431=Get-MIR42IndividualEngineEvidenceBindingContract -Candidate $candidate -PublishedMaintenance
  Assert-MIR430Contract ($contract431.maintenance_source_version-ceq'4.3.1' -and $contract431.binder_status.Contains('MIR-4.3.1-')) 'Schema-six evidence must bind the published 4.3.0 predecessor for 4.3.1.'
  $candidate.identity.record.schema=7;$candidate.identity.record.kind='MIR42FourTargetDeterministicCandidateManifestV7'
  $refused=$false
  try {Get-MIR42IndividualEngineEvidenceBindingContract -Candidate $candidate -PublishedMaintenance|Out-Null}catch{$refused=$true}
  Assert-MIR430Contract $refused 'Unknown future candidate evidence must remain refused.'
  $candidate.identity.record.schema=5;$candidate.identity.record.kind='MIR42FourTargetDeterministicCandidateManifestV5'
  $candidate.scope='four-target';$candidate.targets=@($script:MIR42SealTargets|ForEach-Object{[pscustomobject]@{target=$_}})
  $refused=$false
  try {Get-MIR42IndividualEngineEvidenceBindingContract -Candidate $candidate -PublishedMaintenance|Out-Null}catch{$refused=$true}
  Assert-MIR430Contract $refused 'A four-target subset must not satisfy nine-target maintenance evidence.'
} finally {
  Set-Item Function:script:Get-MIR42SealCandidateConstructionVersionContract -Value $constructionReader
}
[pscustomobject]@{status='MIR430-RELEASE-CONTRACT-CONTROLS-PASSED';assertions=$script:mir430ContractAssertions;factorio_processes=0;publication_authorized=$false}
