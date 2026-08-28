param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot='build/mir4/m4c02-inspector-compatibility',
  [switch]$Check
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/inspection/Inspector.ps1')
. (Join-Path $repo 'tools/mir/application/inspection/CompatibilityFactory.ps1')
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$allowed=[IO.Path]::GetFullPath((Join-Path $repo 'build/mir4')).TrimEnd('\')+'\'
if(-not($output+'\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw "[mir4-w07-output-boundary] $output"}
$dirty=@(& git -C $repo status --porcelain --untracked-files=no)
if($dirty.Count){throw '[mir4-w07-source-dirty] Commit tracked source before exporting exact records.'}
$source=[ordered]@{commit=(& git -C $repo rev-parse HEAD).Trim();tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim();programme_id='M4C02-09-24H'}
$ledger=New-MIR4CompatibilitySubjectLedger -RepoRoot $repo -SourceIdentity $source
$support=New-MIR4ReferenceSupportBundleV1 -Ledger $ledger -RepoRoot $repo -Target f210
$plan=New-MIR4CompatibilityFactoryPlanV1 -SupportBundle $support -Ledger $ledger -RepoRoot $repo -SourceIdentity $source
$zipRelative=([IO.Path]::GetRelativePath($repo,(Join-Path $output 'factory/mir4-compatibility-reference-v1.zip'))).Replace('\','/')
if($Check){
  $zipPath=Join-Path $repo $zipRelative
  $zipCheck=Test-MIR4CompatibilityFactoryDataBundleV1 -RepoRoot $repo -ZipPath $zipPath
  $package=[pscustomobject][ordered]@{path=$zipRelative;bytes=(Get-Item -LiteralPath $zipPath).Length;sha256=(Get-MIR4W07FileSha256 $zipPath);entry_count=[int]$zipCheck.entry_count;status='passed-data-only-package-excluded'}
}else{
  $package=Export-MIR4CompatibilityFactoryDataBundleV1 -RepoRoot $repo -SupportBundle $support -Ledger $ledger -Plan $plan -OutputPath $zipRelative
}
$workbenchSet=New-MIR4InspectorWorkbenchResultV1 -RepoRoot $repo -Ledger $ledger -FactoryPlan $plan -FactoryPackage $package -SourceIdentity $source
$records=[ordered]@{
  'MIR4_INSPECTOR_WORKBENCH_RESULT.json'=$workbenchSet.result
  'MIR4_COMPATIBILITY_SUBJECT_LEDGER.json'=$ledger
  'reference/MIR4_INSPECTION_BUNDLE_V1.json'=$workbenchSet.inspection_bundle
  'reference/MIR4_COMPATIBILITY_FACTORY_PLAN_V1.json'=$plan
  'reference/MIR4_SUPPORT_BUNDLE_V1.json'=$support
}
$schemas=[ordered]@{
  'MIR4_INSPECTOR_WORKBENCH_RESULT.json'='spec/schemas/mir4-inspector-workbench-result-v1.schema.json'
  'MIR4_COMPATIBILITY_SUBJECT_LEDGER.json'='spec/schemas/mir4-compatibility-subject-ledger-v1.schema.json'
  'reference/MIR4_INSPECTION_BUNDLE_V1.json'='spec/schemas/mir4-inspection-bundle-v1.schema.json'
  'reference/MIR4_COMPATIBILITY_FACTORY_PLAN_V1.json'='spec/schemas/mir4-compatibility-factory-plan-v1.schema.json'
}
foreach($entry in $records.GetEnumerator()){
  $path=Join-Path $output $entry.Key
  if($schemas.Contains($entry.Key)){
    $schema=Get-Content -Raw -LiteralPath (Join-Path $repo $schemas[$entry.Key])
    if(-not(($entry.Value|ConvertTo-Json -Depth 100)|Test-Json -Schema $schema)){throw "[mir4-w07-schema] $($entry.Key)"}
  }
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir4-w07-record-missing] $($entry.Key)"}
    $actual=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100
    if((ConvertTo-MIR4ModuleCanonicalJson $actual)-cne(ConvertTo-MIR4ModuleCanonicalJson $entry.Value)){throw "[mir4-w07-record-stale] $($entry.Key)"}
  }else{
    $parent=Split-Path -Parent $path;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllText($path,(ConvertTo-MIR4ModuleCanonicalJson $entry.Value)+"`n",[Text.UTF8Encoding]::new($false))
  }
}
[pscustomobject][ordered]@{
  status='passed';source_identity=$source;output=$output
  records=@('MIR4_INSPECTOR_WORKBENCH_RESULT.json','MIR4_COMPATIBILITY_SUBJECT_LEDGER.json')
  auxiliary_records=3;factory_package=$package;maturity='developer-preview'
  blockers=@('BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER','BLOCKED-EXACT-PROFILE-CLAIM-TRANSFER')
  package_visible=$false;public_release_proof=$false;publication_authorized=$false
}|ConvertTo-Json -Depth 20
