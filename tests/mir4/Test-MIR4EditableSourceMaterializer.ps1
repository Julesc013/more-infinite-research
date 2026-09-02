# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/mir/application/package/ShadowTargetMaterializer.ps1')

$historicalPackage='8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'
$historicalReadme='DF5D4D801DC4A416E4F7C9826EB2E3AE6CFD915937C8599CA7307CCEB343F947'
$schemaPairs=[ordered]@{
  'src/mod/package-source.json'='spec/schemas/mir4-package-source-manifest-v1.schema.json'
  'targets/registry.json'='spec/schemas/mir4-target-registry-v1.schema.json'
  'targets/support-policy.json'='spec/schemas/mir4-target-support-policy-v1.schema.json'
  'targets/f210/overlay.json'='spec/schemas/mir4-target-overlay-v1.schema.json'
  'targets/f200/overlay.json'='spec/schemas/mir4-target-overlay-v1.schema.json'
  'targets/f110/overlay.json'='spec/schemas/mir4-target-overlay-v1.schema.json'
  'targets/f100/overlay.json'='spec/schemas/mir4-target-overlay-v1.schema.json'
}
foreach($pair in $schemaPairs.GetEnumerator()){
  if(-not((Get-Content -Raw -LiteralPath (Join-Path $repo $pair.Key))|Test-Json -SchemaFile (Join-Path $repo $pair.Value))){throw "[mir4-editable-source-schema] $($pair.Key)"}
}
$manifest=Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'src/mod/package-source.json' -Kind 'MIR4PackageSourceManifestV1'
$registry=Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'targets/registry.json' -Kind 'MIR4TargetRegistryV1'
$support=Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'targets/support-policy.json' -Kind 'MIR4TargetSupportPolicyV1'
if(@($manifest.bindings).Count-ne437-or@($manifest.bindings|ForEach-Object{"$($_.layer)|$($_.output_path)"}|Sort-Object -Unique).Count-ne437-or@($manifest.bindings.source_path|Sort-Object -Unique).Count-ne437){throw '[mir4-editable-source-binding-uniqueness]'}
if((@($registry.targets.target|Sort-Object)-join'|')-cne'f100|f110|f200|f210'-or(@($support.targets.target|Sort-Object)-join'|')-cne'f100|f110|f200|f210'){throw '[mir4-editable-source-four-target-authority]'}
if(@($support.targets|Where-Object{[string]$_.qualification-cne'independent-exact-engine-required'}).Count-ne0-or-not[bool]$support.invariants.no_cross_target_proof_substitution){throw '[mir4-editable-source-independent-target-proof]'}

$declared=@($manifest.bindings.source_path|Sort-Object -CaseSensitive -Unique)
$actual=[Collections.Generic.List[string]]::new()
foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $repo 'src/mod') -Recurse -File|Where-Object{$_.FullName-cne(Join-Path $repo 'src/mod/package-source.json')})){$actual.Add([IO.Path]::GetRelativePath($repo,$file.FullName).Replace([IO.Path]::DirectorySeparatorChar,'/'))}
foreach($target in @('f210','f200','f110','f100')){
  foreach($leaf in @('files','generation')){
    $root=Join-Path $repo "targets/$target/$leaf"
    foreach($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue)){$actual.Add([IO.Path]::GetRelativePath($repo,$file.FullName).Replace([IO.Path]::DirectorySeparatorChar,'/'))}
  }
}
if(($declared-join"`n")-cne(@($actual|Sort-Object -CaseSensitive -Unique)-join"`n")){throw '[mir4-editable-source-physical-source-set]'}
foreach($target in @('f210','f200','f110','f100')){
  $state=Get-MIR4TargetMaterializerState -RepoRoot $repo -Target $target
  foreach($binding in @($state.manifest.bindings|Where-Object{$target-in@($_.target_scope)})){[void](Read-MIR4CanonicalSourceBindingBytes -State $state -Binding $binding)}
}

$productionText=Get-Content -Raw -LiteralPath (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
if($productionText-match'Read-MIR4ArchiveBytes|Get-MIR4Shadow|spec/distribution/mir4-golden|dist/more-infinite-research_4[.]0'){throw '[mir4-editable-source-production-archive-input]'}
if(Test-Path -LiteralPath (Join-Path $repo 'tools/commands/mir4/Initialize-MIR4CanonicalSource.ps1')){throw '[mir4-editable-source-bootstrap-writer-not-retired]'}

$proof=Invoke-MIR4CurrentSourceMaterializerProof -RepoRoot $repo -OutputRoot 'build/packages' -ReportPath 'build/reports/package-source/mir4-current-source-materializer-v1.json'
$proofPath=Join-Path $repo 'build/reports/package-source/mir4-current-source-materializer-v1.json'
if(-not((Get-Content -Raw -LiteralPath $proofPath)|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-current-source-materializer-proof-v1.schema.json'))){throw '[mir4-editable-source-proof-schema]'}
$baseline=Get-MIR4ShadowBaseline -RepoRoot $repo
foreach($target in @('f210','f200','f110','f100')){
  $expected=@($baseline.targets|Where-Object{[string]$_.target-ceq$target})
  $actualRow=@($proof.targets|Where-Object{[string]$_.target-ceq$target})
  $modern=$target-in@('f210','f200')
  $expectedDelta=if($modern){22}else{0}
  if($expected.Count-ne1-or$actualRow.Count-ne1-or
     [string]$actualRow[0].baseline_content_sha256-cne[string]$expected[0].archive.content_sha256-or
     [int]$actualRow[0].baseline_entry_count-ne[int]$expected[0].archive.entry_count-or
     [int]$actualRow[0].entry_count_delta-ne$expectedDelta-or
     [bool]$actualRow[0].baseline_match-ne(-not$modern)-or
     [string]$actualRow[0].archive_a-cne[string]$actualRow[0].archive_b-or
     -not[bool]$actualRow[0].deterministic_archive_bytes){throw "[mir4-editable-source-target-parity] $target"}
}
$f2e=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F2E-Package-Authority-CutoverV1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$f2e.verification.legacy_root_projection_sha256-cne$historicalPackage-or
   [string](Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F2C-Editable-Source-Materializer-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100).root_readme_sha256-cne$historicalReadme){throw '[mir4-editable-source-historical-boundary]'}
if(-not[bool]$proof.transition_gate.package_cutover-or-not[bool]$proof.transition_gate.old_writer_retirement-or
   @($proof.transition_gate.PSObject.Properties|Where-Object{$_.Name-notin@('package_cutover','old_writer_retirement')-and[bool]$_.Value}).Count-ne0){throw '[mir4-editable-source-transition-authority]'}

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-editable-source-materializer-m41-f2c';historical_fixed_point_preserved=$true;bindings=@($manifest.bindings).Count;source_files=$declared.Count;targets=@($proof.targets).Count;content_roots=@($proof.targets|ForEach-Object{[ordered]@{target=[string]$_.target;content_sha256=[string]$_.content_sha256;entries=[int]$_.entry_count}});package_source_sha256=(Get-MIRPackageSourceFingerprint -RepoRoot $repo);historical_root_package_source_sha256=$historicalPackage;historical_root_readme_sha256=$historicalReadme;production_archive_input=$false;package_cutover=$true;record_sha256=[string]$proof.record_sha256}|ConvertTo-Json -Depth 20
