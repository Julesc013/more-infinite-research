# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
$writer=Join-Path $repo 'tools/commands/mir4/Update-MIR4CurrentPackagePresentationV6Authority.ps1'

$record=Get-MIR4CurrentPackagePresentationV7Historical -RepoRoot $repo
$v6=Get-MIR4CurrentPackagePresentationV6Historical -RepoRoot $repo
$manifest=Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'source/package-source.json' -Kind 'MIR4ComposablePackageSourceV3'
$predecessorManifest=Get-MIR4ComposablePackageSourceV2Predecessor -RepoRoot $repo
$currentPackageSource=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
Assert-MIR4CurrentPackagePresentationV7LiveFingerprint -RepoRoot $repo -StoredPackageSourceSha256 $currentPackageSource -RequiredPackageSourceSha256 $currentPackageSource|Out-Null
Update-MIR4CurrentSourceBindings -RepoRoot $repo -Check|Out-Null

$migrated=@($manifest.bindings|Where-Object{[string]$_.provenance.kind-ceq'migrated-predecessor'})
$introduced=@($manifest.bindings|Where-Object{[string]$_.provenance.kind-ceq'current-introduction'})
$historicalIntroduced=@($introduced|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR42-HISTORICAL-PRIVATE-TARGET-ADAPTERS'})
$repairIntroduced=@($introduced|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR42-REPAIR-02'})
$progressionIntroduced=@($introduced|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR42-MATERIAL-CONTINUATION'})
$progressionPlannerIntroduced=@($introduced|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR42-MATERIAL-CONTINUATION-PLANNER'})
$compilerTransitionIntroduced=@($introduced|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR4-CHG-2026-0163'})
$approvedBindingsIntroduced=@($introduced|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR440-APPROVED-SCIENCE-BINDINGS'})
$retiredPredecessorSources=@(
  'src/mod/families/modern/prototypes/mir/capabilities/science_integration/pack_production_reachability.lua',
  'src/mod/families/modern/prototypes/mir/capabilities/science_integration/production_route_policy.lua',
  'src/mod/families/modern/prototypes/mir/capabilities/science_integration/technology_researchability.lua',
  'targets/f200/files/prototypes/mir/planner/base_continuations/plan.lua'
)
$retiredCurrentSources=@(
  'source/prototypes/mir/capabilities/science_integration/recipe_route_feasibility.lua',
  'source/prototypes/mir/runtime/compiler_profile_notice.lua',
  'source/prototypes/mir/pipeline/classic_compiler.lua',
  'source/prototypes/mir/domain/compiler/classic_declarations.lua',
  'source/prototypes/mir/planner/classic/plan.lua',
  'source/adapters/f200/prototypes/mir/planner/base_continuations/plan.lua'
)
$predecessorPaths=@($predecessorManifest.bindings|ForEach-Object{[string]$_.predecessor_source_path}|Sort-Object -Unique)
$currentPaths=@($manifest.bindings|ForEach-Object{[string]$_.source_path}|Sort-Object -Unique)
$missingPredecessors=@($predecessorPaths|Where-Object{$_-cnotin@($migrated.provenance.predecessor_source_path)}|Sort-Object -Unique)
$sharedPlan=@($manifest.bindings|Where-Object{
  [string]$_.source_path-ceq'source/prototypes/mir/planner/base_continuations/plan.lua'-and
  [string]$_.output_path-ceq'prototypes/mir/planner/base_continuations/plan.lua'
})
$sharedPlanShape=($sharedPlan.Count-eq1-and[string]$sharedPlan[0].layer-ceq'capability'-and
  [string]$sharedPlan[0].semantic_class-ceq'target-replacement'-and
  [string]$sharedPlan[0].transform-ceq'copy-exact-bytes'-and
  (@($sharedPlan[0].target_scope)-join'|')-ceq'f210|f200|f110|f100')
$successionChecks=@(
  ([string]$record.predecessor.record_sha256-ceq[string]$v6.record_sha256),
  ([string]$manifest.predecessor_record_sha256-ceq[string]$v6.source_manifest.record_sha256),
  (@($manifest.bindings).Count-eq375),($currentPaths.Count-eq375),
  ($migrated.Count-eq355),(@($migrated.provenance.predecessor_source_path|Sort-Object -Unique -CaseSensitive).Count-eq355),
  ($introduced.Count-eq20),($compilerTransitionIntroduced.Count-eq1),($approvedBindingsIntroduced.Count-eq2),
  ($historicalIntroduced.Count-eq12),($repairIntroduced.Count-eq1),($progressionIntroduced.Count-eq1),($progressionPlannerIntroduced.Count-eq1),
  (@($introduced|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR42-SCIENCE-ROUTE-FEASIBILITY'}).Count-eq0),
  (($missingPredecessors-join'|')-ceq(($retiredPredecessorSources|Sort-Object -Unique)-join'|')),
  (@($retiredPredecessorSources|Where-Object{$_-cnotin$predecessorPaths}).Count-eq0),
  (@($retiredCurrentSources|Where-Object{$_-cin$currentPaths}).Count-eq0),
  $sharedPlanShape,
  ([string]$progressionIntroduced[0].source_path-ceq'source/prototypes/mir/families/material_progression.lua'),
  ([string]$progressionIntroduced[0].output_path-ceq'prototypes/mir/families/material_progression.lua'),
  ((@($progressionIntroduced[0].target_scope)-join'|')-ceq'f210|f200|f110|f100'),
  ([string]$progressionPlannerIntroduced[0].source_path-ceq'source/prototypes/mir/planner/stream_compiler/material_continuation.lua'),
  ([string]$progressionPlannerIntroduced[0].output_path-ceq'prototypes/mir/planner/stream_compiler/material_continuation.lua'),
  ((@($progressionPlannerIntroduced[0].target_scope)-join'|')-ceq'f210|f200|f110|f100'),
  ([string]$repairIntroduced[0].layer-ceq'shared'),([string]$repairIntroduced[0].semantic_class-ceq'common-semantic-source'),
  ([string]$repairIntroduced[0].source_path-ceq'source/prototypes/mir/runtime/effects/passive_repair.lua'),
  ([string]$repairIntroduced[0].output_path-ceq'prototypes/mir/runtime/effects/passive_repair.lua'),
  ([string]$repairIntroduced[0].transform-ceq'copy-exact-bytes'),
  ((@($repairIntroduced[0].target_scope|ForEach-Object{[string]$_}|Sort-Object -Unique)-join'|')-ceq'f200|f210'),
  (@($historicalIntroduced|Where-Object{[string]$_.source_path-notmatch'^source/(?:adapters|presentation)/historical/'}).Count-eq0),
  ((@($historicalIntroduced.target_scope|ForEach-Object{[string]$_}|Sort-Object -Unique)-join'|')-ceq'f013|f014|f015|f016|f017')
)
if($successionChecks-contains$false){throw '[mir4-package-presentation-v7-source-succession]'}
foreach($source in @('source/prototypes/mir/settings/compiler_profile.lua')){
  $row=@($compilerTransitionIntroduced|Where-Object{[string]$_.source_path-ceq$source})
  if($row.Count-ne1-or[string]$row[0].layer-cne'capability'-or[string]$row[0].semantic_class-cne'target-overlay'-or
    [string]$row[0].output_path-cne$source.Substring('source/'.Length)-or[string]$row[0].transform-cne'copy-exact-bytes'-or
    (@($row[0].target_scope)-join'|')-cne'f210|f200|f110|f100'){throw '[mir4-package-presentation-v7-source-succession]'}
}
foreach($source in @('source/prototypes/mir/capabilities/science_integration/lab_bindings.lua','source/prototypes/mir/capabilities/science_integration/pack_bindings.lua')){
  $row=@($approvedBindingsIntroduced|Where-Object{[string]$_.source_path-ceq$source})
  if($row.Count-ne1-or[string]$row[0].layer-cne'shared'-or[string]$row[0].semantic_class-cne'common-semantic-source'-or
    [string]$row[0].output_path-cne$source.Substring('source/'.Length)-or[string]$row[0].transform-cne'copy-exact-bytes'-or
    (@($row[0].target_scope)-join'|')-cne'f210|f200|f110|f100'){throw '[mir4-package-presentation-v7-source-succession]'}
}
Assert-MIR4ComposablePackageSourceV3Succession -Current $manifest -Predecessor $predecessorManifest|Out-Null

foreach($forgery in @(
  @{id='substituted-predecessor';mutate={param($r)$r.bindings[0].provenance.predecessor_source_path='src/mod/forged/predecessor.lua'}},
  @{id='missing-predecessor';mutate={param($r)$r.bindings=@($r.bindings|Select-Object -Skip 1)}},
  @{id='duplicated-predecessor';mutate={param($r)$r.bindings[1]=($r.bindings[0]|ConvertTo-Json -Depth 20|ConvertFrom-Json -Depth 20)}},
  @{id='changed-scope';mutate={param($r)$r.bindings[0].target_scope=@('f210')}},
  @{id='browser-overlap';mutate={param($r)($r.bindings|Where-Object source_path -CEQ 'source/adapters/runtime-capabilities/game-browser-host.lua').target_scope=@('f210','f200')}},
  @{id='browser-substitution';mutate={param($r)($r.bindings|Where-Object source_path -CEQ 'source/adapters/runtime-capabilities/game-browser-host.lua').source_path='source/adapters/runtime-capabilities/forged.lua'}},
  @{id='browser-output';mutate={param($r)($r.bindings|Where-Object source_path -CEQ 'source/adapters/runtime-capabilities/game-browser-host.lua').output_path='prototypes/mir/platform/factorio/forged.lua'}},
  @{id='browser-transform';mutate={param($r)($r.bindings|Where-Object source_path -CEQ 'source/adapters/runtime-capabilities/game-browser-host.lua').transform='forged-transform'}},
  @{id='browser-identity';mutate={param($r)($r.bindings|Where-Object source_path -CEQ 'source/adapters/runtime-capabilities/game-browser-host.lua').provenance.introduction_id='undeclared-introduction'}},
  @{id='retired-classic-reintroduced';mutate={param($r)$row=@($r.bindings|Where-Object source_path -CEQ 'source/prototypes/mir/settings/compiler_profile.lua');$row[0].source_path='source/prototypes/mir/domain/compiler/classic_declarations.lua';$row[0].output_path='prototypes/mir/domain/compiler/classic_declarations.lua'}},
  @{id='retired-runtime-notice-reintroduced';mutate={param($r)$row=@($r.bindings|Where-Object source_path -CEQ 'source/prototypes/mir/runtime/state.lua');$row[0].source_path='source/prototypes/mir/runtime/compiler_profile_notice.lua';$row[0].output_path='prototypes/mir/runtime/compiler_profile_notice.lua'}},
  @{id='retired-science-reintroduced';mutate={param($r)$row=@($r.bindings|Where-Object source_path -CEQ 'source/prototypes/mir/capabilities/science_integration/pack_bindings.lua');$row[0].source_path='source/prototypes/mir/capabilities/science_integration/recipe_route_feasibility.lua';$row[0].output_path='prototypes/mir/capabilities/science_integration/recipe_route_feasibility.lua';$row[0].provenance.introduction_id='MIR42-SCIENCE-ROUTE-FEASIBILITY'}},
  @{id='approved-binding-substitution';mutate={param($r)$row=@($r.bindings|Where-Object source_path -CEQ 'source/prototypes/mir/capabilities/science_integration/lab_bindings.lua');$row[0].source_path='source/prototypes/mir/capabilities/science_integration/forged.lua'}},
  @{id='retired-f200-plan-reintroduced';mutate={param($r)$row=@($r.bindings|Where-Object source_path -CEQ 'source/prototypes/mir/planner/base_continuations/plan.lua');$row[0].source_path='source/adapters/f200/prototypes/mir/planner/base_continuations/plan.lua'}},
  @{id='shared-f200-plan-missing';mutate={param($r)$row=@($r.bindings|Where-Object source_path -CEQ 'source/prototypes/mir/planner/base_continuations/plan.lua');$row[0].source_path='source/prototypes/mir/planner/base_continuations/forged-plan.lua'}},
  @{id='shared-f200-plan-scope';mutate={param($r)$row=@($r.bindings|Where-Object source_path -CEQ 'source/prototypes/mir/planner/base_continuations/plan.lua');$row[0].target_scope=@('f210','f110','f100')}}
)){
  $copy=$manifest|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String
  &$forgery.mutate $copy;$copy.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $copy
  if(-not(Test-MIR4BootstrapRecordHash -Record $copy)){throw "[mir4-package-presentation-v7-forgery-hash] $($forgery.id)"}
  $rejected=$false;try{Assert-MIR4ComposablePackageSourceV3Succession -Current $copy -Predecessor $predecessorManifest|Out-Null}catch{$rejected=$_.Exception.Message-eq'[mir4-package-presentation-v7-source-succession]'}
  if(-not$rejected){throw "[mir4-package-presentation-v7-source-succession-forgery] $($forgery.id)"}
}

foreach($target in @('f210','f200','f110','f100')){
  $state=Get-MIR4TargetMaterializerState -RepoRoot $repo -Target $target
  $selection=Get-MIR4TargetMaterializationBindings -State $state
  $identity=@($record.target_content_identities|Where-Object{[string]$_.target-ceq$target})
  $prior=@($v6.target_content_identities|Where-Object{[string]$_.target-ceq$target})
  foreach($path in @('prototypes/mir/capabilities/science_integration/lab_bindings.lua','prototypes/mir/capabilities/science_integration/pack_bindings.lua')){
    $binding=@($state.manifest.bindings|Where-Object{[string]$_.output_path-ceq$path})
    $operation=@($state.composition.operations|Where-Object{[string]$_.path-ceq$path})
    $selected=@($selection.bindings|Where-Object{[string]$_.output_path-ceq$path})
    if($binding.Count-ne1-or$selected.Count-ne1-or$operation.Count-ne0-or$identity.Count-ne1-or$prior.Count-ne1-or
       $target-notin@($binding[0].target_scope)-or[string]$binding[0].layer-cne'shared'-or
       [string]$selected[0].source_path-cne[string]$binding[0].source_path-or
       [string]$selected[0].output_sha256-cne[string]$binding[0].output_sha256-or
       [string]$identity[0].predecessor_content_sha256-cne[string]$prior[0].content_sha256-or
       [int]$identity[0].predecessor_entry_count-ne[int]$prior[0].entry_count-or
       -not[bool]$identity[0].exact_engine_qualification_required){throw "[mir4-package-presentation-v7-target-binding] $target $path"}
    # Shared source is selected directly, not introduced by a target overlay.
    # Read the selected bytes through the materializer's source/output hash checks.
    $bytes=Read-MIR4CanonicalSourceBindingBytes -State $state -Binding $selected[0]
    if($bytes.Length-ne[int64]$binding[0].output_bytes){throw "[mir4-package-presentation-v7-target-binding-bytes] $target $path"}

    $forgedState=$state|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String
    $forgedState.composition.operations=@($forgedState.composition.operations)+@([pscustomobject]@{
      path=$path;operation='add';source_path=[string]$binding[0].source_path
      transform=[string]$binding[0].transform;semantic_class=[string]$binding[0].semantic_class
      expected_bytes=[int64]$binding[0].output_bytes;expected_sha256=[string]$binding[0].output_sha256
    })
    $overlayRejected=$false
    try{Get-MIR4TargetMaterializationBindings -State $forgedState|Out-Null}catch{
      $overlayRejected=$_.Exception.Message-ceq"[mir4-target-materializer-operation-mismatch] ${target}:$path"
    }
    if(-not$overlayRejected){throw "[mir4-package-presentation-v7-shared-overlay-accepted] $target $path"}
  }
}

foreach($forgery in @(
  @{id='predecessor';mutate={param($r)$r.predecessor.record_sha256='0'*64}},
  @{id='manifest';mutate={param($r)$r.source_manifest.record_sha256='0'*64}},
  @{id='succession';mutate={param($r)$r.source_succession.current_record_sha256='0'*64}}
)){
  $copy=$record|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String
  &$forgery.mutate $copy;$copy.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $copy
  if(-not(Test-MIR4BootstrapRecordHash -Record $copy)){throw "[mir4-package-presentation-v7-forgery-hash] $($forgery.id)"}
  if(Test-MIR4CurrentPackagePresentationV7Schema -Record $copy -RepoRoot $repo){throw "[mir4-package-presentation-v7-rehashed-forgery-accepted] $($forgery.id)"}
}
foreach($mutation in @(
  @{id='ambiguous-provenance';mutate={param($r)$r.source_succession.introduced_binding_count=2}},
  @{id='package-source';mutate={param($r)$r.package_source.fingerprint_sha256='0'*64}},
  @{id='gate';mutate={param($r)$r.transition_gate.publication=$true}},
  @{id='authority';mutate={param($r)$r.authority_invariants.promotion_authorized=$true}}
)){
  $copy=$record|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String;&$mutation.mutate $copy;$copy.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $copy
  if(Test-MIR4CurrentPackagePresentationV7Schema -Record $copy -RepoRoot $repo){throw "[mir4-package-presentation-v7-tamper] $($mutation.id)"}
}

&$writer -RepoRoot $repo -Check|Out-Null
$scratch=Join-Path $repo ('build/mir4/test-package-presentation-v7-'+[guid]::NewGuid().ToString('N')+'.json');$stale=$false
try{&$writer -RepoRoot $repo -Check -CheckAuthorityPath $scratch|Out-Null}catch{$stale=$_.Exception.Message-eq'[mir4-package-presentation-v7-stale]'}
if(-not$stale-or(Test-Path -LiteralPath $scratch)){throw '[mir4-package-presentation-v7-check-isolation]'}
$immutable=$false;try{&$writer -RepoRoot $repo|Out-Null}catch{$immutable=$_.Exception.Message-eq'[mir4-package-presentation-v7-authority-immutable-overwrite]'}
if(-not$immutable){throw '[mir4-package-presentation-v7-overwrite]'}

Write-Host '[ok] MIR4 package presentation V7 remains an independently pinned historical transition while current development uses the live package contract.'
