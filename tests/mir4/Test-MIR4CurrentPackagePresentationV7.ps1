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
$scienceIntroduced=@($introduced|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR42-SCIENCE-ROUTE-FEASIBILITY'})
$historicalIntroduced=@($introduced|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR42-HISTORICAL-PRIVATE-TARGET-ADAPTERS'})
$repairIntroduced=@($introduced|Where-Object{[string]$_.provenance.introduction_id-ceq'MIR42-REPAIR-02'})
if([string]$record.predecessor.record_sha256-cne[string]$v6.record_sha256-or
  [string]$manifest.predecessor_record_sha256-cne[string]$v6.source_manifest.record_sha256-or
   @($manifest.bindings).Count-ne373-or@($manifest.bindings.source_path|Sort-Object -Unique).Count-ne373-or
   $migrated.Count-ne359-or@($migrated.provenance.predecessor_source_path|Sort-Object -Unique -CaseSensitive).Count-ne359-or
   $introduced.Count-ne14-or$scienceIntroduced.Count-ne1-or$historicalIntroduced.Count-ne12-or$repairIntroduced.Count-ne1-or
  [string]$scienceIntroduced[0].source_path-cne'source/prototypes/mir/capabilities/science_integration/recipe_route_feasibility.lua'-or
   [string]$repairIntroduced[0].layer-cne'shared'-or[string]$repairIntroduced[0].semantic_class-cne'common-semantic-source'-or
   [string]$repairIntroduced[0].source_path-cne'source/prototypes/mir/runtime/effects/passive_repair.lua'-or
   [string]$repairIntroduced[0].output_path-cne'prototypes/mir/runtime/effects/passive_repair.lua'-or
   [string]$repairIntroduced[0].transform-cne'copy-exact-bytes'-or
   (@($repairIntroduced[0].target_scope|ForEach-Object{[string]$_}|Sort-Object -Unique)-join'|')-cne'f200|f210'-or
   [string]$repairIntroduced[0].provenance.kind-cne'current-introduction'-or
  @($historicalIntroduced|Where-Object{[string]$_.source_path-notmatch'^source/(?:adapters|presentation)/historical/'}).Count-ne0-or
  (@($historicalIntroduced.target_scope|ForEach-Object{[string]$_}|Sort-Object -Unique)-join'|')-cne'f013|f014|f015|f016|f017'-or
   @($migrated.provenance.predecessor_source_path|Sort-Object -Unique -CaseSensitive).Count-ne359){throw '[mir4-package-presentation-v7-source-succession]'}

Assert-MIR4ComposablePackageSourceV3Succession -Current $manifest -Predecessor $predecessorManifest|Out-Null

foreach($forgery in @(
  @{id='substituted-predecessor';mutate={param($r)$r.bindings[0].provenance.predecessor_source_path='src/mod/forged/predecessor.lua'}},
  @{id='missing-predecessor';mutate={param($r)$r.bindings=@($r.bindings|Select-Object -Skip 1)}},
  @{id='duplicated-predecessor';mutate={param($r)$r.bindings[1]=($r.bindings[0]|ConvertTo-Json -Depth 20|ConvertFrom-Json -Depth 20)}},
  @{id='changed-scope';mutate={param($r)$r.bindings[0].target_scope=@('f210')}}
)){
  $copy=$manifest|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String
  &$forgery.mutate $copy;$copy.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $copy
  if(-not(Test-MIR4BootstrapRecordHash -Record $copy)){throw "[mir4-package-presentation-v7-forgery-hash] $($forgery.id)"}
  $rejected=$false;try{Assert-MIR4ComposablePackageSourceV3Succession -Current $copy -Predecessor $predecessorManifest|Out-Null}catch{$rejected=$_.Exception.Message-eq'[mir4-package-presentation-v7-source-succession]'}
  if(-not$rejected){throw "[mir4-package-presentation-v7-source-succession-forgery] $($forgery.id)"}
}

foreach($target in @('f210','f200','f110','f100')){
  $state=Get-MIR4TargetMaterializerState -RepoRoot $repo -Target $target
  $binding=@($state.manifest.bindings|Where-Object{[string]$_.output_path-ceq'prototypes/mir/capabilities/science_integration/recipe_route_feasibility.lua'})
  $operation=@($state.composition.operations|Where-Object{[string]$_.path-ceq'prototypes/mir/capabilities/science_integration/recipe_route_feasibility.lua'})
  $identity=@($record.target_content_identities|Where-Object{[string]$_.target-ceq$target})
  $prior=@($v6.target_content_identities|Where-Object{[string]$_.target-ceq$target})
  if($binding.Count-ne1-or$operation.Count-ne1-or$identity.Count-ne1-or$prior.Count-ne1-or
     $target-notin@($binding[0].target_scope)-or[string]$operation[0].operation-cne'add'-or
     [string]$operation[0].expected_sha256-cne[string]$binding[0].output_sha256-or
     [string]$identity[0].predecessor_content_sha256-cne[string]$prior[0].content_sha256-or
     [int]$identity[0].predecessor_entry_count-ne[int]$prior[0].entry_count-or
     -not[bool]$identity[0].exact_engine_qualification_required){throw "[mir4-package-presentation-v7-target-binding] $target"}
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
