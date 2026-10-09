Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../tools/lib/validation/ImmutableInputStaging.ps1')

function Initialize-MIRCandidateRetentionOutputRoot {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$OutputRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $selected=if([IO.Path]::IsPathRooted($OutputRoot)){$OutputRoot}else{Join-Path $repo $OutputRoot}
  $output=Assert-MIRImmutableInputPathWithin -Path $selected -Root (Join-Path $repo 'build') -Context 'Retention output'
  $parent=Split-Path -Parent $output
  while($parent){
    if(Test-Path -LiteralPath $parent){Assert-MIRImmutableInputDirectory -Path $parent -Context 'Retention output ancestor'}
    $parent=Split-Path -Parent $parent
  }
  if(Test-Path -LiteralPath $output){throw "Retention output already exists; preserve it and select a new output root: $output"}
  New-Item -ItemType Directory -Path $output -ErrorAction Stop | Out-Null
  return $output
}

function New-MIRCandidateRetentionInputLease {
  param([Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$ModsDirectory,
    [Parameter(Mandatory)][string]$ModZip)
  $source=(Resolve-Path -LiteralPath $ModZip -ErrorAction Stop).Path
  $input=[ordered]@{source_path=$source;file_name=[IO.Path]::GetFileName($source);
    expected_sha256=Get-MIRImmutableInputSha256 $source;role='retention-package';
    identity=@{file_name=[IO.Path]::GetFileName($source)};
    provenance=@{kind='selected-retention-package';engine_qualification=$false};immutable=$true}
  New-MIRImmutableInputLease -RunRoot $RunRoot -StageDirectory $ModsDirectory -Inputs @($input) -RequireHardLinks
}
