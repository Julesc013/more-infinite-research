param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot='build/mir4/m4c02-module-ecosystem',
  [string]$CandidateZip='build/mir4/m4c02-target-products/packages/more-infinite-research_4.0.21000.zip',
  [switch]$Check
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/PlatformPreview.ps1')
$status=@(& git -C $repo status --porcelain)
if($LASTEXITCODE-ne 0-or$status.Count-ne 0){throw '[mir4-module-ecosystem-export-dirty-tree]'}
$commit=(& git -C $repo rev-parse HEAD).Trim();$tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$source=[ordered]@{commit=$commit;tree=$tree;programme_id='M4C02-09-24H'}
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot));$allowed=[IO.Path]::GetFullPath((Join-Path $repo 'build/mir4')).TrimEnd('\')+'\'
if(-not($output+'\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw "[mir4-module-ecosystem-export-boundary] $output"}
$candidate=$null
if(-not[string]::IsNullOrWhiteSpace($CandidateZip)){$candidate=if([IO.Path]::IsPathRooted($CandidateZip)){$CandidateZip}else{Join-Path $repo $CandidateZip};if(-not(Test-Path -LiteralPath $candidate -PathType Leaf)){throw "[mir4-module-ecosystem-candidate-missing] $CandidateZip"}}
$result=New-MIR4W05Records -RepoRoot $repo -SourceIdentity $source -CandidateZip $candidate
$records=[ordered]@{'MIR4_MEP_CONFORMANCE.json'=$result.mep;'MIR4_API_SDK_GRADUATION_MATRIX.json'=$result.sdk;'MIR4_REFERENCE_CONSUMER_RESULT.json'=$result.consumer}
foreach($entry in $records.GetEnumerator()){
  $path=Join-Path $output $entry.Key;$bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4ModuleCanonicalJson $entry.Value)+"`n")
  if($Check){if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or-not[Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($path),[byte[]]$bytes)){throw "[mir4-module-ecosystem-export-stale] $($entry.Key)"}}
  else{New-Item -ItemType Directory -Force -Path $output|Out-Null;[IO.File]::WriteAllBytes($path,$bytes)}
}
[pscustomobject]@{status='passed';source_identity=$source;candidate=$(if($candidate){[IO.Path]::GetFullPath($candidate)}else{$null});output=$output;records=@($records.Keys);blockers=@('BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER')}|ConvertTo-Json -Depth 8
