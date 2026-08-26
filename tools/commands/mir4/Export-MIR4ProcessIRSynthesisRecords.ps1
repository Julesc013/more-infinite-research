param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot='build/mir4/m4c02-processir-synthesis',
  [switch]$Check
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/SafetyKernel.ps1')
. (Join-Path $repo 'tools/lib/mir4/ProcessIR.ps1')
$status=@(& git -C $repo status --porcelain)
if($LASTEXITCODE-ne 0-or$status.Count-ne 0){throw '[mir4-processir-export-dirty-tree]'}
$commit=(& git -C $repo rev-parse HEAD).Trim();$tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$source=[ordered]@{commit=$commit;tree=$tree;programme_id='M4C02-09-24H'}
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot));$allowed=[IO.Path]::GetFullPath((Join-Path $repo 'build/mir4')).TrimEnd('\')+'\'
if(-not($output+'\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw "[mir4-processir-export-boundary] $output"}
$result=New-MIR4W06Records -RepoRoot $repo -SourceIdentity $source
$records=[ordered]@{
  'MIR4_PROCESSIR_PARITY_RESULT.json'=[ordered]@{value=$result.parity;schema='spec/schemas/mir4-process-ir-v1.schema.json'}
  'MIR4_EFFECT_CHANNEL_REGISTRY.json'=[ordered]@{value=$result.effects;schema='spec/schemas/mir4-effect-channel-registry-v1.schema.json'}
  'MIR4_SYNTHESIS_MATURITY_MATRIX.json'=[ordered]@{value=$result.synthesis;schema='spec/schemas/mir4-synthesis-maturity-matrix-v1.schema.json'}
}
foreach($entry in $records.GetEnumerator()){
  $json=ConvertTo-MIR4ProcessIRCanonicalJson $entry.Value.value
  if(-not($json|Test-Json -SchemaFile (Join-Path $repo $entry.Value.schema))){throw "[mir4-processir-export-schema] $($entry.Key)"}
  $path=Join-Path $output $entry.Key;$bytes=[Text.UTF8Encoding]::new($false).GetBytes($json+"`n")
  if($Check){if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or-not[Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($path),[byte[]]$bytes)){throw "[mir4-processir-export-stale] $($entry.Key)"}}
  else{New-Item -ItemType Directory -Force -Path $output|Out-Null;[IO.File]::WriteAllBytes($path,$bytes)}
}
[pscustomobject]@{status='passed-with-declared-custody-gap';source_identity=$source;output=$output;records=@($records.Keys);maturity='developer-preview';blockers=@('BLOCKED-EXACT-ARCHIVE-CUSTODY-F200-K2SO');package_visible=$false;publication_authorized=$false}|ConvertTo-Json -Depth 8
