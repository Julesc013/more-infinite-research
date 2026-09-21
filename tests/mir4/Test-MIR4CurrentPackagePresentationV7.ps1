# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
$writer=Join-Path $repo 'tools/commands/mir4/Update-MIR4CurrentPackagePresentationV6Authority.ps1'

$record=Get-MIR4CurrentPackagePresentationV7 -RepoRoot $repo
$v6=Get-MIR4CurrentPackagePresentationV6Historical -RepoRoot $repo
$manifest=Read-MIR4TargetMaterializerRecord -RepoRoot $repo -RelativePath 'source/package-source.json' -Kind 'MIR4ComposablePackageSourceV3'
$predecessorManifest=Get-MIR4ComposablePackageSourceV2Predecessor -RepoRoot $repo
Assert-MIR4CurrentPackagePresentationV7LiveFingerprint -RepoRoot $repo -StoredPackageSourceSha256 ([string]$record.package_source.fingerprint_sha256) -RequiredPackageSourceSha256 (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)|Out-Null
Update-MIR4CurrentSourceBindings -RepoRoot $repo -Check|Out-Null

$migrated=@($manifest.bindings|Where-Object{[string]$_.provenance.kind-ceq'migrated-predecessor'})
$introduced=@($manifest.bindings|Where-Object{[string]$_.provenance.kind-ceq'current-introduction'})
if([string]$record.predecessor.record_sha256-cne[string]$v6.record_sha256-or
   [string]$manifest.predecessor_record_sha256-cne[string]$v6.source_manifest.record_sha256-or
   $migrated.Count-ne359-or$introduced.Count-ne1-or
   [string]$introduced[0].source_path-cne'source/prototypes/mir/capabilities/science_integration/recipe_route_feasibility.lua'-or
   [string]$introduced[0].provenance.introduction_id-cne'MIR42-SCIENCE-ROUTE-FEASIBILITY'-or
   @($migrated.provenance.predecessor_source_path|Sort-Object -Unique -CaseSensitive).Count-ne359){throw '[mir4-package-presentation-v7-source-succession]'}

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

$inputs=Get-MIR4CurrentPackagePresentationV7Inputs -RepoRoot $repo
foreach($forgery in @(
  @{id='predecessor';mutate={param($r)$r.predecessor.record_sha256='0'*64};code='[mir4-package-presentation-v7-current-binding]'},
  @{id='manifest';mutate={param($r)$r.source_manifest.record_sha256='0'*64};code='[mir4-package-presentation-v7-current-binding]'},
  @{id='succession';mutate={param($r)$r.source_succession.current_record_sha256='0'*64};code='[mir4-package-presentation-v7-current-binding]'}
)){
  $copy=$record|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String
  &$forgery.mutate $copy;$copy.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $copy
  if(-not(Test-MIR4CurrentPackagePresentationV7Schema -Record $copy -RepoRoot $repo)-or-not(Test-MIR4BootstrapRecordHash -Record $copy)){throw "[mir4-package-presentation-v7-forgery-invalid] $($forgery.id)"}
  $rejected=$false;try{Assert-MIR4CurrentPackagePresentationV7SemanticBindings -Record $copy -Inputs $inputs|Out-Null}catch{$rejected=$_.Exception.Message-eq[string]$forgery.code};if(-not$rejected){throw "[mir4-package-presentation-v7-forgery-accepted] $($forgery.id)"}
}
foreach($mutation in @(
  @{id='ambiguous-provenance';mutate={param($r)$r.source_succession.introduced_binding_count=2}},
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

Write-Host '[ok] MIR4 package presentation V7 binds package-source V3 provenance, exact current package identities, and closed release gates.'
