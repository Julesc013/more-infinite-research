Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../tools/lib/validation/NativeProbeResources.ps1')

function New-MIRMaterialAuditInputLease {
  param([string]$RunRoot,[string]$ModsDirectory,[string]$CandidateArchive,[string]$DependencyDirectory,[Collections.IDictionary]$ExpectedArchives)
  $candidate=(Resolve-Path -LiteralPath $CandidateArchive -ErrorAction Stop).Path
  $dependencies=Resolve-MIRNativeProbeDependencyInputs -StageRoot $RunRoot -ExpectedArchives $ExpectedArchives -LocalModLibraryDirs @($DependencyDirectory)
  $inputs=@([ordered]@{source_path=$candidate;file_name=[IO.Path]::GetFileName($candidate);expected_sha256=Get-MIRImmutableInputSha256 $candidate;role='candidate';identity=@{file_name=[IO.Path]::GetFileName($candidate)};provenance=@{kind='selected-candidate-archive'};immutable=$true})
  foreach($entry in $dependencies.GetEnumerator()){
    $inputs+=@([ordered]@{source_path=$entry.Value.source_path;file_name=$entry.Key;expected_sha256=$entry.Value.expected_sha256;role='dependency-mod';identity=@{file_name=$entry.Key};immutable=$true;provenance=@{kind=$entry.Value.provenance_kind}})
  }
  New-MIRImmutableInputLease -RunRoot $RunRoot -StageDirectory $ModsDirectory -Inputs $inputs -RequireHardLinks
}
