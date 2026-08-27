# MIR4-RUNTIME-CONTINUITY-CANONICAL-CLI
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot='build/mir4/m4c02-runtime-continuity',
  [string]$CandidateZip='build/mir4/m4c02-target-products/packages/more-infinite-research_4.0.21000.zip',
  [switch]$Check
)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/PlatformPreview.ps1')
$status=@(& git -C $repo status --porcelain)
if($LASTEXITCODE-ne 0-or$status.Count-ne 0){throw '[mir4-runtime-continuity-export-dirty-tree]'}
$commit=(& git -C $repo rev-parse HEAD).Trim()
$tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$source=[ordered]@{commit=$commit;tree=$tree;programme_id='M4C02-09-24H'}
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$allowed=[IO.Path]::GetFullPath((Join-Path $repo 'build/mir4')).TrimEnd('\')+'\'
if(-not($output+'\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw "[mir4-runtime-continuity-export-boundary] $output"}

$candidate=$null
if(-not[string]::IsNullOrWhiteSpace($CandidateZip)){
  $candidate=if([IO.Path]::IsPathRooted($CandidateZip)){$CandidateZip}else{Join-Path $repo $CandidateZip}
  if(-not(Test-Path -LiteralPath $candidate -PathType Leaf)){throw "[mir4-runtime-continuity-candidate-missing] $CandidateZip"}
}
$providers=@(New-MIR4NormalizedTargetProviders -RepoRoot $repo)
$runtime=New-MIR4RuntimeStateMatrix -RepoRoot $repo -Providers $providers -SourceIdentity $source
$migration=New-MIR4MigrationGraphMatrix -RepoRoot $repo -Providers $providers -SourceIdentity $source
$continuity=New-MIR4ContinuityBundle -RepoRoot $repo -Providers $providers -SourceIdentity $source -CandidateZip $candidate -RuntimeStateMatrix $runtime -MigrationGraphMatrix $migration
$records=[ordered]@{
  'MIR4_RUNTIME_STATE_MATRIX.json'=$runtime
  'MIR4_MIGRATION_GRAPH_MATRIX.json'=$migration
  'MIR4_CONTINUITY_BUNDLE.json'=$continuity
}
foreach($entry in $records.GetEnumerator()){
  $path=Join-Path $output $entry.Key
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4PlatformCanonicalJson $entry.Value)+"`n")
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or-not[Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($path),[byte[]]$bytes)){throw "[mir4-runtime-continuity-export-stale] $($entry.Key)"}
  }else{
    New-Item -ItemType Directory -Force -Path $output|Out-Null
    [IO.File]::WriteAllBytes($path,$bytes)
  }
}
[pscustomobject]@{status='passed';source_identity=$source;candidate=$(if($candidate){[IO.Path]::GetFullPath($candidate)}else{$null});output=$output;records=@($records.Keys)}|ConvertTo-Json -Depth 8
