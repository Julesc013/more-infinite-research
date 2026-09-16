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
  'source/package-source.json'='spec/schemas/mir4-composable-package-source-v2.schema.json'
  'targets/package-authority.json'='spec/schemas/mir4-canonical-package-authority-v2.schema.json'
  'targets/registry.json'='spec/schemas/mir4-target-registry-v2.schema.json'
  'targets/support-policy.json'='spec/schemas/mir4-target-support-policy-v1.schema.json'
  'targets/f210/composition.json'='spec/schemas/mir4-target-composition-v2.schema.json'
  'targets/f200/composition.json'='spec/schemas/mir4-target-composition-v2.schema.json'
  'targets/f110/composition.json'='spec/schemas/mir4-target-composition-v2.schema.json'
  'targets/f100/composition.json'='spec/schemas/mir4-target-composition-v2.schema.json'
}
foreach($pair in $schemaPairs.GetEnumerator()){
  if(-not((Get-Content -Raw -LiteralPath (Join-Path $repo $pair.Key))|Test-Json -SchemaFile (Join-Path $repo $pair.Value))){throw "[mir4-editable-source-schema] $($pair.Key)"}
}
$manifest=Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'source/package-source.json' -Kind 'MIR4ComposablePackageSourceV2'
$registry=Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'targets/registry.json' -Kind 'MIR4TargetRegistryV2'
$support=Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'targets/support-policy.json' -Kind 'MIR4TargetSupportPolicyV1'
$schemaScratchRelative = 'build/mir4/test-canonical-package-record-schema-' + [guid]::NewGuid().ToString('N')
$schemaScratch = Join-Path $repo $schemaScratchRelative
New-Item -ItemType Directory -Force -Path $schemaScratch | Out-Null
try {
  $negativeCases = @(
    [pscustomobject]@{id='authority-unknown';path='targets/package-authority.json';kind='MIR4CanonicalPackageAuthorityV2';schema='spec/schemas/mir4-canonical-package-authority-v2.schema.json';mutate={param($r)$r|Add-Member -NotePropertyName unexpected -NotePropertyValue $true}},
    [pscustomobject]@{id='authority-invalid-gate';path='targets/package-authority.json';kind='MIR4CanonicalPackageAuthorityV2';schema='spec/schemas/mir4-canonical-package-authority-v2.schema.json';mutate={param($r)$r.transition_gate.publication=$true}},
    [pscustomobject]@{id='authority-missing-writer';path='targets/package-authority.json';kind='MIR4CanonicalPackageAuthorityV2';schema='spec/schemas/mir4-canonical-package-authority-v2.schema.json';mutate={param($r)[void]$r.PSObject.Properties.Remove('writer')}},
    [pscustomobject]@{id='manifest-unknown';path='source/package-source.json';kind='MIR4ComposablePackageSourceV2';schema='spec/schemas/mir4-composable-package-source-v2.schema.json';mutate={param($r)$r|Add-Member -NotePropertyName unexpected -NotePropertyValue $true}},
    [pscustomobject]@{id='registry-invalid-target';path='targets/registry.json';kind='MIR4TargetRegistryV2';schema='spec/schemas/mir4-target-registry-v2.schema.json';mutate={param($r)$r.targets[0].target='f999'}},
    [pscustomobject]@{id='support-missing';path='targets/support-policy.json';kind='MIR4TargetSupportPolicyV1';schema='spec/schemas/mir4-target-support-policy-v1.schema.json';mutate={param($r)[void]$r.PSObject.Properties.Remove('invariants')}},
    [pscustomobject]@{id='composition-unknown';path='targets/f210/composition.json';kind='MIR4TargetCompositionV2';schema='spec/schemas/mir4-target-composition-v2.schema.json';mutate={param($r)$r.operations[0]|Add-Member -NotePropertyName unexpected -NotePropertyValue $true}}
  )
  foreach ($case in $negativeCases) {
    $record = Get-Content -Raw -LiteralPath (Join-Path $repo $case.path) | ConvertFrom-Json -Depth 100 -DateKind String
    & $case.mutate $record
    $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
    $relative = ($schemaScratchRelative + '/' + $case.id + '.json').Replace('\\','/')
    [IO.File]::WriteAllText((Join-Path $repo $relative), (ConvertTo-MIR4BootstrapCanonicalJson -Value $record) + [char]10, [Text.UTF8Encoding]::new($false))
    $rejected = $false
    try { Read-MIR4CanonicalPackageAuthorityRecord -RepoRoot $repo -RelativePath $relative -Kind $case.kind -Schema $case.schema -Code 'mir4-editable-source-negative' | Out-Null } catch { $rejected = $_.Exception.Message -match 'mir4-editable-source-negative-schema' }
    if (-not $rejected) { throw "[mir4-editable-source-rehashed-schema-accepted] $($case.id)" }
    $materializerRejected = $false
    try { Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath $relative -Kind $case.kind | Out-Null } catch { $materializerRejected = $_.Exception.Message -match 'mir4-target-materializer-record-schema' }
    if (-not $materializerRejected) { throw "[mir4-editable-source-materializer-schema-accepted] $($case.id)" }
  }
} finally {
  if (Test-Path -LiteralPath $schemaScratch -PathType Container) { Remove-Item -LiteralPath $schemaScratch -Recurse -Force }
}
if(@($manifest.bindings).Count-ne358-or@($manifest.bindings.source_path|Sort-Object -Unique).Count-ne358-or@($manifest.bindings.predecessor_source_path|Sort-Object -Unique).Count-ne358){throw '[mir4-editable-source-binding-uniqueness]'}
$targetOutputs=@(foreach($binding in @($manifest.bindings)){foreach($target in @($binding.target_scope)){"$target|$([string]$binding.output_path)"}})
if(@($targetOutputs|Sort-Object -Unique).Count-ne$targetOutputs.Count){throw '[mir4-editable-source-target-output-uniqueness]'}
if((@($registry.targets.target|Sort-Object)-join'|')-cne'f100|f110|f200|f210'-or(@($support.targets.target|Sort-Object)-join'|')-cne'f100|f110|f200|f210'){throw '[mir4-editable-source-four-target-authority]'}
if(@($support.targets|Where-Object{[string]$_.qualification-cne'independent-exact-engine-required'}).Count-ne0-or-not[bool]$support.invariants.no_cross_target_proof_substitution){throw '[mir4-editable-source-independent-target-proof]'}

$declared=@($manifest.bindings.source_path|Sort-Object -CaseSensitive -Unique)
$actual=[Collections.Generic.List[string]]::new()
foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $repo 'source') -Recurse -File|Where-Object{$_.FullName-notin@((Join-Path $repo 'source/package-source.json'),(Join-Path $repo 'source/.mir-root.json'))})){$actual.Add([IO.Path]::GetRelativePath($repo,$file.FullName).Replace([IO.Path]::DirectorySeparatorChar,'/'))}
if(($declared-join"`n")-cne(@($actual|Sort-Object -CaseSensitive -Unique)-join"`n")){throw '[mir4-editable-source-physical-source-set]'}
if(Test-Path -LiteralPath (Join-Path $repo 'src') -PathType Container){throw '[mir4-editable-source-abbreviated-root-retained]'}
if(Test-Path -LiteralPath (Join-Path $repo 'source/families') -PathType Container){throw '[mir4-editable-source-era-family-retained]'}
if(@(Get-ChildItem -LiteralPath (Join-Path $repo 'targets') -Recurse -File|Where-Object{$_.FullName-match'[\\/](?:files|generation)[\\/]'}).Count-ne0){throw '[mir4-editable-source-payload-outside-source-root]'}
$relocationCases=[ordered]@{
  'src/mod/common/prototypes/mir/core/deepcopy.lua'='source/prototypes/mir/core/deepcopy.lua'
  'src/mod/families/modern/prototypes/mir/core/fingerprint.lua'='source/prototypes/mir/core/fingerprint.lua'
  'targets/f200/files/prototypes/mir/planner/stream_compiler.lua'='source/prototypes/mir/planner/stream_compiler.lua'
}
foreach($case in $relocationCases.GetEnumerator()){
  if((Resolve-MIR4CanonicalPackageSourcePath -RepoRoot $repo -RelativePath $case.Key)-cne$case.Value){throw "[mir4-editable-source-relocation] $($case.Key)"}
}
foreach($retiredPath in @('src/mod/not-a-declared-source.lua','src/mod/families/legacy/prototypes/mir/core/fingerprint.lua','targets/f210/files/prototypes/mir/planner/stream_compiler.lua')){
  $relocationRejected=$false
  try{[void](Resolve-MIR4CanonicalPackageSourcePath -RepoRoot $repo -RelativePath $retiredPath)}catch{$relocationRejected=$_.Exception.Message.Contains('[mir4-package-source-relocation-ambiguous]')}
  if(-not$relocationRejected){throw "[mir4-editable-source-relocation-negative] $retiredPath"}
}
foreach($target in @('f210','f200','f110','f100')){
  $state=Get-MIR4TargetMaterializerState -RepoRoot $repo -Target $target
  $selection=Get-MIR4TargetMaterializationBindings -State $state
  if(-not[bool]$selection.scoped_operation_closure-or@($selection.bindings).Count-ne@($state.manifest.bindings|Where-Object{$target-in@($_.target_scope)}).Count){throw "[mir4-editable-source-scoped-operation-closure] $target"}
  foreach($binding in @($state.manifest.bindings|Where-Object{$target-in@($_.target_scope)})){[void](Read-MIR4CanonicalSourceBindingBytes -State $state -Binding $binding)}
}

function Copy-MIR4EditableSourceState($State){
  return ($State|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String)
}
function Assert-MIR4EditableSourceRejected([scriptblock]$Action,[string]$Code){
  $rejected=$false
  try{&$Action}catch{$rejected=$_.Exception.Message.Contains($Code)}
  if(-not$rejected){throw "[mir4-editable-source-negative] $Code"}
}
Assert-MIR4EditableSourceRejected {
  New-MIR4TargetPackage -RepoRoot $repo -Target f210 -CandidateId HISTORICAL-REJECT -SourceVersion '4.1.0' -OutputRoot 'build/packages/test-historical-rejection' | Out-Null
} '[mir4-target-materializer-historical-source-version-requires-pinned-checkout]'
$omissionState=Copy-MIR4EditableSourceState (Get-MIR4TargetMaterializerState -RepoRoot $repo -Target 'f200')
$omission=@($omissionState.composition.operations|Where-Object{[string]$_.operation-ceq'omit'}|Select-Object -First 1)
if($omission.Count-ne1){throw '[mir4-editable-source-omission-fixture]'}
$omission[0].expected_bytes=0
Assert-MIR4EditableSourceRejected {Get-MIR4TargetMaterializationBindings -State $omissionState|Out-Null} '[mir4-target-materializer-omission]'

$metadataState=Copy-MIR4EditableSourceState (Get-MIR4TargetMaterializerState -RepoRoot $repo -Target 'f210')
$metadata=@($metadataState.composition.operations|Where-Object{[string]$_.path-ceq'info.json'}|Select-Object -First 1)
if($metadata.Count-ne1){throw '[mir4-editable-source-metadata-fixture]'}
$metadata[0].semantic_class='target-overlay'
Assert-MIR4EditableSourceRejected {Get-MIR4TargetMaterializationBindings -State $metadataState|Out-Null} '[mir4-target-materializer-operation-mismatch]'

$byteState=Copy-MIR4EditableSourceState (Get-MIR4TargetMaterializerState -RepoRoot $repo -Target 'f210')
$byteOperation=@($byteState.composition.operations|Where-Object{[string]$_.path-ceq'info.json'}|Select-Object -First 1)
$byteOperation[0].expected_bytes=[int64]$byteOperation[0].expected_bytes+1
Assert-MIR4EditableSourceRejected {Get-MIR4TargetMaterializationBindings -State $byteState|Out-Null} '[mir4-target-materializer-operation-mismatch]'

$transformState=Copy-MIR4EditableSourceState (Get-MIR4TargetMaterializerState -RepoRoot $repo -Target 'f210')
$transformOperation=@($transformState.composition.operations|Where-Object{[string]$_.path-ceq'info.json'}|Select-Object -First 1)
$transformOperation[0].transform='copy-exact-bytes'
Assert-MIR4EditableSourceRejected {Get-MIR4TargetMaterializationBindings -State $transformState|Out-Null} '[mir4-target-materializer-operation-mismatch]'

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
  $expectedDelta=if($target-in@('f210','f200')){32}else{103}
  if($expected.Count-ne1-or$actualRow.Count-ne1-or
     [string]$actualRow[0].baseline_content_sha256-cne[string]$expected[0].archive.content_sha256-or
     [int]$actualRow[0].baseline_entry_count-ne[int]$expected[0].archive.entry_count-or
     [int]$actualRow[0].entry_count_delta-ne$expectedDelta-or
     [bool]$actualRow[0].baseline_match-ne$false-or
     [string]$actualRow[0].archive_a-cne[string]$actualRow[0].archive_b-or
     -not[bool]$actualRow[0].deterministic_archive_bytes){throw "[mir4-editable-source-target-parity] $target"}
}
$f2e=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F2E-Package-Authority-CutoverV1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$f2e.verification.legacy_root_projection_sha256-cne$historicalPackage-or
   [string](Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F2C-Editable-Source-Materializer-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100).root_readme_sha256-cne$historicalReadme){throw '[mir4-editable-source-historical-boundary]'}
if(-not[bool]$proof.transition_gate.package_cutover-or-not[bool]$proof.transition_gate.old_writer_retirement-or
   @($proof.transition_gate.PSObject.Properties|Where-Object{$_.Name-notin@('package_cutover','old_writer_retirement')-and[bool]$_.Value}).Count-ne0){throw '[mir4-editable-source-transition-authority]'}

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-editable-source-materializer-m41-f2c';historical_fixed_point_preserved=$true;bindings=@($manifest.bindings).Count;source_files=$declared.Count;deduplicated_source_bindings=(@($manifest.bindings).Count-$declared.Count);targets=@($proof.targets).Count;content_roots=@($proof.targets|ForEach-Object{[ordered]@{target=[string]$_.target;content_sha256=[string]$_.content_sha256;entries=[int]$_.entry_count}});package_source_sha256=(Get-MIRPackageSourceFingerprint -RepoRoot $repo);historical_root_package_source_sha256=$historicalPackage;historical_root_readme_sha256=$historicalReadme;production_archive_input=$false;package_cutover=$true;record_sha256=[string]$proof.record_sha256}|ConvertTo-Json -Depth 20
