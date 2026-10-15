# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/mir/application/package/ShadowTargetMaterializer.ps1')

$historicalPackage='8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'
$historicalReadme='DF5D4D801DC4A416E4F7C9826EB2E3AE6CFD915937C8599CA7307CCEB343F947'
$schemaPairs=[ordered]@{
  'source/package-source.json'='spec/schemas/mir4-composable-package-source-v3.schema.json'
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
$manifest=Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'source/package-source.json' -Kind 'MIR4ComposablePackageSourceV3'
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
    [pscustomobject]@{id='manifest-unknown';path='source/package-source.json';kind='MIR4ComposablePackageSourceV3';schema='spec/schemas/mir4-composable-package-source-v3.schema.json';mutate={param($r)$r|Add-Member -NotePropertyName unexpected -NotePropertyValue $true}},
    [pscustomobject]@{id='manifest-missing-provenance';path='source/package-source.json';kind='MIR4ComposablePackageSourceV3';schema='spec/schemas/mir4-composable-package-source-v3.schema.json';mutate={param($r)[void]$r.bindings[0].PSObject.Properties.Remove('provenance')}},
    [pscustomobject]@{id='manifest-ambiguous-provenance';path='source/package-source.json';kind='MIR4ComposablePackageSourceV3';schema='spec/schemas/mir4-composable-package-source-v3.schema.json';mutate={param($r)$introduced=@($r.bindings|Where-Object{[string]$_.provenance.kind-ceq'current-introduction'});$introduced[0].provenance|Add-Member -NotePropertyName predecessor_source_path -NotePropertyValue 'src/mod/forged.lua'}},
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
$migratedBindings=@($manifest.bindings|Where-Object{[string]$_.provenance.kind-ceq'migrated-predecessor'})
$introducedBindings=@($manifest.bindings|Where-Object{[string]$_.provenance.kind-ceq'current-introduction'})
$historicalBindings=@($introducedBindings|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR42-HISTORICAL-PRIVATE-TARGET-ADAPTERS'})
$compilerTransitionBindings=@($introducedBindings|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR4-CHG-2026-0163'})
$approvedScienceBindings=@($introducedBindings|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR440-APPROVED-SCIENCE-BINDINGS'})
$repairBindings=@($introducedBindings|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR42-REPAIR-02'})
$progressionBindings=@($introducedBindings|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR42-MATERIAL-CONTINUATION'})
$progressionPlannerBindings=@($introducedBindings|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR42-MATERIAL-CONTINUATION-PLANNER'})
$retiredCurrentSources=@(
  'source/prototypes/mir/capabilities/science_integration/recipe_route_feasibility.lua',
  'source/prototypes/mir/runtime/compiler_profile_notice.lua',
  'source/prototypes/mir/pipeline/classic_compiler.lua',
  'source/prototypes/mir/domain/compiler/classic_declarations.lua',
  'source/prototypes/mir/planner/classic/plan.lua'
)
$compilerTransitionSources=@(
  'source/prototypes/mir/settings/compiler_profile.lua'
)
$approvedScienceSources=@(
  'source/prototypes/mir/capabilities/science_integration/lab_bindings.lua',
  'source/prototypes/mir/capabilities/science_integration/pack_bindings.lua'
)
if(@($manifest.bindings).Count-ne375-or@($manifest.bindings.source_path|Sort-Object -Unique).Count-ne375-or
   $migratedBindings.Count-ne355-or@($migratedBindings.provenance.predecessor_source_path|Sort-Object -Unique).Count-ne355-or
   $introducedBindings.Count-ne20-or$historicalBindings.Count-ne12-or$compilerTransitionBindings.Count-ne1-or$approvedScienceBindings.Count-ne2-or
   @($introducedBindings|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR42-SCIENCE-ROUTE-FEASIBILITY'}).Count-ne0-or
   @($retiredCurrentSources|Where-Object{$_-cin@($manifest.bindings.source_path)}).Count-ne0-or
   @($retiredCurrentSources|Where-Object{Test-Path -LiteralPath (Join-Path $repo $_)}).Count-ne0-or
   [string]$progressionBindings[0].source_path-cne'source/prototypes/mir/families/material_progression.lua'-or
   [string]$progressionBindings[0].output_path-cne'prototypes/mir/families/material_progression.lua'-or
   (@($progressionBindings[0].target_scope)-join'|')-cne'f210|f200|f110|f100'-or
   [string]$progressionPlannerBindings[0].source_path-cne'source/prototypes/mir/planner/stream_compiler/material_continuation.lua'-or
   [string]$progressionPlannerBindings[0].output_path-cne'prototypes/mir/planner/stream_compiler/material_continuation.lua'-or
   (@($progressionPlannerBindings[0].target_scope)-join'|')-cne'f210|f200|f110|f100'-or
   @($historicalBindings.source_path|Where-Object{$_-notmatch'^source/(?:adapters|presentation)/historical/'}).Count-ne0-or
   [string]$repairBindings[0].layer-cne'shared'-or[string]$repairBindings[0].semantic_class-cne'common-semantic-source'-or
   [string]$repairBindings[0].source_path-cne'source/prototypes/mir/runtime/effects/passive_repair.lua'-or
   [string]$repairBindings[0].output_path-cne'prototypes/mir/runtime/effects/passive_repair.lua'-or
   [string]$repairBindings[0].transform-cne'copy-exact-bytes'-or
   (@($repairBindings[0].target_scope|ForEach-Object{[string]$_}|Sort-Object -Unique)-join'|')-cne'f200|f210'-or
   [string]$repairBindings[0].provenance.kind-cne'current-introduction'){
  throw '[mir4-editable-source-binding-uniqueness]'
}
foreach($source in $compilerTransitionSources){
  $row=@($compilerTransitionBindings|Where-Object{[string]$_.source_path-ceq$source})
  if($row.Count-ne1-or[string]$row[0].layer-cne'capability'-or[string]$row[0].semantic_class-cne'target-overlay'-or
     [string]$row[0].output_path-cne$source.Substring('source/'.Length)-or[string]$row[0].transform-cne'copy-exact-bytes'-or
     ((@($row[0].target_scope)-join'|')-cne'f210|f200|f110|f100')){throw '[mir4-editable-source-binding-uniqueness]'}
}
foreach($source in $approvedScienceSources){
  $row=@($approvedScienceBindings|Where-Object{[string]$_.source_path-ceq$source})
  if($row.Count-ne1-or[string]$row[0].layer-cne'shared'-or[string]$row[0].semantic_class-cne'common-semantic-source'-or
     [string]$row[0].output_path-cne$source.Substring('source/'.Length)-or[string]$row[0].transform-cne'copy-exact-bytes'-or
     ((@($row[0].target_scope)-join'|')-cne'f210|f200|f110|f100')){throw '[mir4-editable-source-binding-uniqueness]'}
}
Assert-MIR4ComposablePackageSourceV3Succession -Current $manifest -Predecessor (Get-MIR4ComposablePackageSourceV2Predecessor -RepoRoot $repo)|Out-Null
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

$sourceManifestPath=Join-Path $repo 'source/package-source.json'
$sourceManifestBefore=(Get-FileHash -LiteralPath $sourceManifestPath -Algorithm SHA256).Hash
Assert-MIR4EditableSourceRejected {
  Update-MIR4CurrentSourceBindings -RepoRoot $repo -RetiredSourcePaths @('source/prototypes/mir/settings/compiler_profile.lua') -Check | Out-Null
} '[mir4-source-retirement-source-present]'
Assert-MIR4EditableSourceRejected {
  Update-MIR4CurrentSourceBindings -RepoRoot $repo -RetiredSourcePaths @('source/prototypes/mir/runtime/not-a-declared-source.lua') -Check | Out-Null
} '[mir4-source-retirement-binding]'
Assert-MIR4EditableSourceRejected {
  Update-MIR4CurrentSourceBindings -RepoRoot $repo -RetiredSourcePaths @('../outside.lua') -Check | Out-Null
} 'Unsafe or non-portable MIR 4 archive path'
if((Get-FileHash -LiteralPath $sourceManifestPath -Algorithm SHA256).Hash-cne$sourceManifestBefore){throw '[mir4-editable-source-retirement-check-mutated-manifest]'}

# A retired target adapter may fall back only to the already admitted shared
# source for the exact same output.  Exercise the writer's in-memory
# retirement transform so this control never deletes or refreshes live source.
$sharedPlanPath='source/prototypes/mir/planner/base_continuations/plan.lua'
$syntheticRetiredAdapterPath='source/adapters/f200/prototypes/mir/planner/base_continuations/retired-plan.lua'
$presentAdapterPath='source/adapters/f200/prototypes/mir/planner/base_continuations/qualify.lua'
$fallbackFixtureManifest=Copy-MIR4EditableSourceState $manifest
$fallbackShared=@($fallbackFixtureManifest.bindings|Where-Object{[string]$_.source_path-ceq$sharedPlanPath})
if($fallbackShared.Count-ne1){throw '[mir4-editable-source-adapter-fallback-fixture]'}
# Model the pre-retirement manifest in memory.  The current source has already
# removed the f200 plan adapter, so no live binding can serve as this fixture.
$syntheticFallbackAdapter=Copy-MIR4EditableSourceState $fallbackShared[0]
$syntheticFallbackAdapter.layer='adapter'
$syntheticFallbackAdapter.target_scope=@('f200')
$syntheticFallbackAdapter.source_path=$syntheticRetiredAdapterPath
$syntheticFallbackAdapter.provenance=[pscustomobject][ordered]@{kind='test-only-retired-adapter'}
$fallbackShared[0].target_scope=@('f210','f110','f100')
$fallbackFixtureManifest.bindings=@($fallbackFixtureManifest.bindings)+@($syntheticFallbackAdapter)
$fallbackManifest=Copy-MIR4EditableSourceState $fallbackFixtureManifest
$fallbackCompositions=[ordered]@{}
foreach($target in @('f210','f200','f110','f100')){
  $fallbackCompositions[$target]=Copy-MIR4EditableSourceState (Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath "targets/$target/composition.json" -Kind 'MIR4TargetCompositionV2')
}
$fallbackF200Operation=@($fallbackCompositions.f200.operations|Where-Object{[string]$_.path-ceq[string]$syntheticFallbackAdapter.output_path})
if($fallbackF200Operation.Count-ne1-or[string]$fallbackF200Operation[0].source_path-cne$sharedPlanPath){throw '[mir4-editable-source-adapter-fallback-overlay-fixture]'}
$fallbackF200Operation[0].source_path=$syntheticRetiredAdapterPath
$unrelatedCompositions=[ordered]@{}
foreach($target in @('f210','f110','f100')){$unrelatedCompositions[$target]=$fallbackCompositions[$target]|ConvertTo-Json -Depth 100}
$fallbackEntries=@(Resolve-MIR4AdapterFallbackRetirements -RepoRoot $repo -Manifest $fallbackManifest -AdapterFallbackRetirements @{$syntheticRetiredAdapterPath=$sharedPlanPath})
if($fallbackEntries.Count-ne1-or@($fallbackManifest.bindings|Where-Object{[string]$_.source_path-ceq$syntheticRetiredAdapterPath}).Count-ne0-or
   (@($fallbackEntries[0].fallback_binding.target_scope)-join'|')-cne'f210|f200|f110|f100') {throw '[mir4-editable-source-adapter-fallback-selection]'}
foreach($target in @('f210','f200','f110','f100')){Update-MIR4AdapterFallbackRetirementOverlay -Composition $fallbackCompositions[$target] -Target $target -Entries $fallbackEntries}
$fallbackF200Operation=@($fallbackCompositions.f200.operations|Where-Object{[string]$_.path-ceq'prototypes/mir/planner/base_continuations/plan.lua'})
if($fallbackF200Operation.Count-ne1-or[string]$fallbackF200Operation[0].source_path-cne$sharedPlanPath){throw '[mir4-editable-source-adapter-fallback-overlay]'}
foreach($target in @('f210','f110','f100')){if(($fallbackCompositions[$target]|ConvertTo-Json -Depth 100)-cne$unrelatedCompositions[$target]){throw "[mir4-editable-source-adapter-fallback-unrelated-target] $target"}}

$missingFallbackManifest=Copy-MIR4EditableSourceState $fallbackFixtureManifest
Assert-MIR4EditableSourceRejected {Resolve-MIR4AdapterFallbackRetirements -RepoRoot $repo -Manifest $missingFallbackManifest -AdapterFallbackRetirements @{$syntheticRetiredAdapterPath='source/prototypes/mir/planner/base_continuations/not-a-plan.lua'}|Out-Null} '[mir4-source-adapter-fallback-binding]'
$duplicateFallbackManifest=Copy-MIR4EditableSourceState $fallbackFixtureManifest
$duplicateFallbackManifest.bindings=@($duplicateFallbackManifest.bindings)+@(Copy-MIR4EditableSourceState (@($duplicateFallbackManifest.bindings|Where-Object{[string]$_.source_path-ceq$sharedPlanPath})[0]))
Assert-MIR4EditableSourceRejected {Resolve-MIR4AdapterFallbackRetirements -RepoRoot $repo -Manifest $duplicateFallbackManifest -AdapterFallbackRetirements @{$syntheticRetiredAdapterPath=$sharedPlanPath}|Out-Null} '[mir4-source-adapter-fallback-binding]'
Assert-MIR4EditableSourceRejected {Resolve-MIR4AdapterFallbackRetirements -RepoRoot $repo -Manifest (Copy-MIR4EditableSourceState $manifest) -AdapterFallbackRetirements @{$presentAdapterPath=$sharedPlanPath}|Out-Null} '[mir4-source-adapter-fallback-source-present]'
$wrongOutputManifest=Copy-MIR4EditableSourceState $fallbackFixtureManifest
@($wrongOutputManifest.bindings|Where-Object{[string]$_.source_path-ceq$sharedPlanPath})[0].output_path='prototypes/mir/planner/base_continuations/not-plan.lua'
Assert-MIR4EditableSourceRejected {Resolve-MIR4AdapterFallbackRetirements -RepoRoot $repo -Manifest $wrongOutputManifest -AdapterFallbackRetirements @{$syntheticRetiredAdapterPath=$sharedPlanPath}|Out-Null} '[mir4-source-adapter-fallback-output]'
$wrongTransformManifest=Copy-MIR4EditableSourceState $fallbackFixtureManifest
@($wrongTransformManifest.bindings|Where-Object{[string]$_.source_path-ceq$sharedPlanPath})[0].transform='exact-template-v1'
Assert-MIR4EditableSourceRejected {Resolve-MIR4AdapterFallbackRetirements -RepoRoot $repo -Manifest $wrongTransformManifest -AdapterFallbackRetirements @{$syntheticRetiredAdapterPath=$sharedPlanPath}|Out-Null} '[mir4-source-adapter-fallback-binding]'
$overlappingScopeManifest=Copy-MIR4EditableSourceState $fallbackFixtureManifest
@($overlappingScopeManifest.bindings|Where-Object{[string]$_.source_path-ceq$sharedPlanPath})[0].target_scope=@('f210','f200','f110','f100')
Assert-MIR4EditableSourceRejected {Resolve-MIR4AdapterFallbackRetirements -RepoRoot $repo -Manifest $overlappingScopeManifest -AdapterFallbackRetirements @{$syntheticRetiredAdapterPath=$sharedPlanPath}|Out-Null} '[mir4-source-adapter-fallback-scope]'
$nonAdapterRetirementManifest=Copy-MIR4EditableSourceState $fallbackFixtureManifest
@($nonAdapterRetirementManifest.bindings|Where-Object{[string]$_.source_path-ceq$syntheticRetiredAdapterPath})[0].source_path='source/prototypes/mir/planner/base_continuations/retired-plan.lua'
Assert-MIR4EditableSourceRejected {Resolve-MIR4AdapterFallbackRetirements -RepoRoot $repo -Manifest $nonAdapterRetirementManifest -AdapterFallbackRetirements @{'source/prototypes/mir/planner/base_continuations/retired-plan.lua'=$sharedPlanPath}|Out-Null} '[mir4-source-adapter-fallback-path]'
$badOverlay=Copy-MIR4EditableSourceState $fallbackCompositions.f200
@($badOverlay.operations|Where-Object{[string]$_.path-ceq'prototypes/mir/planner/base_continuations/plan.lua'})[0].source_path=$sharedPlanPath
Assert-MIR4EditableSourceRejected {Update-MIR4AdapterFallbackRetirementOverlay -Composition $badOverlay -Target 'f200' -Entries $fallbackEntries} '[mir4-source-adapter-fallback-overlay]'

$cliPath=Join-Path $repo 'tools/mir/cli/Invoke-MIR4PackageSource.ps1'
$cliTokens=$null;$cliErrors=$null;$cliAst=[Management.Automation.Language.Parser]::ParseFile($cliPath,[ref]$cliTokens,[ref]$cliErrors)
if($cliErrors.Count-or@($cliAst.ParamBlock.Parameters|Where-Object {$_.Name.VariablePath.UserPath-ceq'AdapterFallbackRetirements'}).Count-ne1-or
   -not([IO.File]::ReadAllText($cliPath).Contains('-AdapterFallbackRetirements $AdapterFallbackRetirements'))){throw '[mir4-editable-source-adapter-fallback-cli]'}
Assert-MIR4EditableSourceRejected {& $cliPath -RepoRoot $repo -Command 'baseline' -AdapterFallbackRetirements @{$syntheticRetiredAdapterPath=$sharedPlanPath}} '[mir4-source-retirement-command]'
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
  # The current source removes the retired discovery and Classic implementations
  # while adding the approved lab/pack reference bindings.  The frozen baseline
  # identities remain exact; current semantic changes are not historical byte parity.
  $expectedDelta=if($target-in@('f210','f200')){37}else{106}
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
