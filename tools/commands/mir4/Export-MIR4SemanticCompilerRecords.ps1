param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot='build/mir4/m4c02-semantic-compiler',
  [switch]$Check
)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/PlatformPreview.ps1')
$status=@(& git -C $repo status --porcelain)
if($LASTEXITCODE-ne 0-or$status.Count-ne 0){throw '[mir4-semantic-export-dirty-tree]'}
$commit=(& git -C $repo rev-parse HEAD).Trim()
$tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$allowed=[IO.Path]::GetFullPath((Join-Path $repo 'build/mir4')).TrimEnd('\')+'\'
if(-not($output+'\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw "[mir4-semantic-export-boundary] $output"}

$providers=@(New-MIR4NormalizedTargetProviders -RepoRoot $repo)
$runs=@(New-MIR4NormalizedCompilationRuns -RepoRoot $repo -Providers $providers)
$cutover=New-MIR4FeatureSettingCutoverMatrix -RepoRoot $repo -Providers $providers
$protocols=New-MIR4ProviderMicroProtocolMatrix -RepoRoot $repo
$laws=Test-MIR4SemanticMergeLaws -RepoRoot $repo
$source=[ordered]@{commit=$commit;tree=$tree;programme_id='M4C02-09-24H'}
$runContract=[pscustomobject][ordered]@{
  schema=1;kind='MIR4CompilationRunContractV1';source_identity=$source;maturity='shadow';authority='.mir/releases/waves/mir4-r0/MIR4-Semantic-Compiler-ProgrammeV1.json'
  run_schema='spec/schemas/mir4-compilation-run-v1.schema.json';targets=@($runs|ForEach-Object{[ordered]@{target=[string]$_.target.id;run_digest=[string]$_.digest;result=[string]$_.result}})
  terminal_player_authority_unchanged=$true;package_visible=$false;public_release_proof=$false;mutation_capability=$false;digest=''
}
Add-MIR4PlatformDigest $runContract|Out-Null

function Add-MIR4SemanticExportIdentity($Record,[string]$Kind){
  $copy=$Record|ConvertTo-Json -Depth 100|ConvertFrom-Json
  $copy.PSObject.Properties.Remove('digest')
  $ordered=[ordered]@{schema=1;kind=$Kind;source_identity=$source;maturity='shadow';authority='.mir/releases/waves/mir4-r0/MIR4-Semantic-Compiler-ProgrammeV1.json'}
  foreach($property in $copy.PSObject.Properties){if($property.Name-notin@('schema','kind','maturity','programme_id')){$ordered[$property.Name]=$property.Value}}
  $ordered.package_visible=$false;$ordered.public_release_proof=$false;$ordered.digest=''
  $result=[pscustomobject]$ordered;Add-MIR4PlatformDigest $result|Out-Null;return $result
}

$records=[ordered]@{
  'MIR4_COMPILATION_RUN_CONTRACT.json'=$runContract
  'MIR4_FEATURE_SETTING_CUTOVER_MATRIX.json'=(Add-MIR4SemanticExportIdentity $cutover 'MIR4FeatureSettingCutoverMatrixExportV1')
  'MIR4_PROVIDER_MICRO_PROTOCOL_MATRIX.json'=(Add-MIR4SemanticExportIdentity $protocols 'MIR4ProviderMicroProtocolMatrixExportV1')
  'MIR4_MERGE_LAW_CATALOGUE.json'=(Add-MIR4SemanticExportIdentity $laws 'MIR4MergeLawCatalogueExportV1')
}
foreach($entry in $records.GetEnumerator()){
  $path=Join-Path $output $entry.Key
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4PlatformCanonicalJson $entry.Value)+"`n")
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or-not[Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($path),[byte[]]$bytes)){throw "[mir4-semantic-export-stale] $($entry.Key)"}
  }else{New-Item -ItemType Directory -Force -Path $output|Out-Null;[IO.File]::WriteAllBytes($path,$bytes)}
}
[pscustomobject]@{status='passed';source_identity=$source;output=$output;records=@($records.Keys)}|ConvertTo-Json -Depth 8
