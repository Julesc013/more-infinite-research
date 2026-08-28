param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot='build/mir4/m4c02-historical-succession',
  [string]$HistoricalBuildRoot='build/mir4/historical-private',
  [string]$RuntimeEvidenceRoot='build/mir4/m4c02-historical-succession/runtime',
  [switch]$Check
)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/mir/application/history/HistoricalSuccession.ps1')
. (Join-Path $repo 'tools/mir/application/history/SuccessorHost.ps1')
$status=@(& git -C $repo status --porcelain)
if($LASTEXITCODE-ne 0-or$status.Count-ne 0){throw '[mir4-w09-export-dirty-tree]'}
$source=[pscustomobject][ordered]@{commit=(& git -C $repo rev-parse HEAD).Trim();tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()}
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$allowed=[IO.Path]::GetFullPath((Join-Path $repo 'build/mir4')).TrimEnd('\')+'\'
if(-not($output+'\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw "[mir4-w09-export-boundary] $output"}

$matrix=New-MIR4HistoricalMuseumMatrixV1 -RepoRoot $repo -SourceIdentity $source -HistoricalBuildRoot $HistoricalBuildRoot -RuntimeEvidenceRoot $RuntimeEvidenceRoot
$successor=New-MIR4SuccessorHostResultV1 -RepoRoot $repo -SourceIdentity $source -OutputRoot $OutputRoot
$records=[ordered]@{
  'MIR4_HISTORICAL_MUSEUM_MATRIX.json'=$matrix
  'MIR4_SUCCESSOR_HOST_RESULT.json'=$successor
}
$schemas=@{
  'MIR4_HISTORICAL_MUSEUM_MATRIX.json'='spec/schemas/mir4-historical-museum-matrix-v1.schema.json'
  'MIR4_SUCCESSOR_HOST_RESULT.json'='spec/schemas/mir4-successor-host-result-v1.schema.json'
}
foreach($entry in $records.GetEnumerator()){
  if(-not(($entry.Value|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $repo $schemas[$entry.Key]))){throw "[mir4-w09-export-schema] $($entry.Key)"}
  if([string]$entry.Value.record_sha256-cne(Get-MIR4W09RecordSha256 -Record $entry.Value)){throw "[mir4-w09-export-record-hash] $($entry.Key)"}
  $path=Join-Path $output $entry.Key
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4PlatformCanonicalJson $entry.Value)+"`n")
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or-not[Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($path),[byte[]]$bytes)){throw "[mir4-w09-export-stale] $($entry.Key)"}
  }else{
    New-Item -ItemType Directory -Force -Path $output|Out-Null
    [IO.File]::WriteAllBytes($path,$bytes)
  }
}
[pscustomobject]@{status='partial-with-bounded-blockers';source_identity=(New-MIR4W09SourceIdentity -RepoRoot $repo -SourceIdentity $source);output=$output;records=@($records.Keys);blockers=@($successor.blockers)}|ConvertTo-Json -Depth 20
