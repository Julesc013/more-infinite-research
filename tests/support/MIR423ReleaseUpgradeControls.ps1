function Invoke-MIR423ReleaseUpgradeControls {
  param([string]$Root,[object[]]$PackageAssets)
  # Host-only structural controls. They exercise the release reader's 27-row
  # contract without executing Factorio or producing a publication claim.
  [IO.Directory]::CreateDirectory($Root)|Out-Null
  $checks=0
  function Write-UpgradeControlJson($path,$value){$value|ConvertTo-Json -Depth 100|Set-Content $path;return [pscustomobject]@{path=$path;sha256=(Get-FileHash $path).Hash}}
  function Clone-UpgradeControl($value){return $value|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable -Depth 100}
  $rows=@()
  foreach($package in $PackageAssets){
    foreach($patch in @(0,1,2)){
      $sourceVersion='4.2.'+$patch;$stem=$package.target+'-'+$patch;$directory=Join-Path $Root $stem
      [IO.Directory]::CreateDirectory($directory)|Out-Null
      $predecessor=Get-MIR423PublishedUpgradePredecessor -Target $package.target -PredecessorSourceVersion $sourceVersion
      $from='4.2.'+$package.target.Substring(1)+$patch.ToString('00');$to=$package.distribution_version
      $state=@{forces=@{player=@{technologies=@{a=@{researched=$true;level=2};b=@{researched=$false;level=1};c=@{researched=$false;level=1}};bonuses=@{plate=0.1};settings=@{kept=$true};effects=@{speed=0.1};ammo=@{bullet=0.1};gun_speed=@{};turret=@{};queue=@('b');current_research='b';research_progress=0.42}};from_version=$from;to_version=$to}
      foreach($technology in $state.forces.player.technologies.Values){
        $technology.prototype=@{effects=@(@{type='mining-drill-productivity-bonus';modifier=0.02});ingredients=@(@{name='automation-science-pack';amount=1});prerequisites=@();research_unit_count=100;research_unit_energy=30;max_level=10}
      }
      $snapshots=@(foreach($phase in @('source','upgrade','reload')){
        $snapshot=Clone-UpgradeControl $state;$snapshot.stage=$phase
        $reference=Write-UpgradeControlJson (Join-Path $directory ($phase+'.json')) $snapshot
        [pscustomobject]@{stage=$phase;path=$reference.path;sha256=$reference.sha256}
      })
      $native=@{schema=3;status='passed';factorio_processes=4;from=@{version=$from;sha256=$predecessor.target.sha256};to=@{version=$to;sha256=$package.sha256};published_maintenance_predecessor=@{source_tag=$predecessor.source_tag;manifest=@{sha256=$predecessor.manifest.sha256}};assertions=@('exact-candidate-normal-mod-directory-load','upgraded-save-reload-passed','upgraded-save-second-reload-passed','all-existing-technology-state-and-definitions-retained','all-exposed-earned-effects-retained','all-supported-research-queue-retained','full-state-oracle-executed-upgrade-and-two-reloads');resource_ledgers=@();library_activation=@{status='restored-direct-library-controls';dependency_payload_bytes_copied=0;archive_links_created=0;archive_extractions=0};full_state_evaluator_snapshots=$snapshots}
      foreach($phase in @('create','load','reload','second_reload')){
        $file=Join-Path $directory ($phase+'.txt');[IO.File]::WriteAllText($file,'[mir-fixture] complete research state retained technologies=3 recipes=1')
        $native[$phase+'_log']=Split-Path $file -Leaf;$native[$phase+'_log_sha256']=(Get-FileHash $file).Hash
        $ledger=Join-Path $directory ($phase+'.resources.jsonl');[IO.File]::WriteAllText($ledger,'{"synthetic_host_control":true}')
        $native.resource_ledgers+=@{filename=(Split-Path $ledger -Leaf);sha256=(Get-FileHash $ledger).Hash;exit_code=0;completion_predicate_observed=$false}
      }
      $receipt=Write-UpgradeControlJson (Join-Path $directory 'receipt.json') $native
      $rows+=[pscustomobject]@{target=$package.target;predecessor_source_version=$sourceVersion;receipt=$receipt;snapshots=$snapshots}
    }
  }
  $bundle=@{schema=1;kind='MIR423MaintenanceUpgradeEvidenceV1';source_version='4.2.3';rows=$rows}
  $path=Join-Path $Root 'evidence.json';$null=Write-UpgradeControlJson $path $bundle
  $null=Assert-MIR423MaintenanceUpgradeEvidence -Path $path -PackageAssets $PackageAssets;$checks++
  $bad=Clone-UpgradeControl $bundle;$bad.rows=@($bad.rows|Select-Object -First 26)
  $badPath=Join-Path $Root 'missing-row.json';$null=Write-UpgradeControlJson $badPath $bad
  $refused=$false;try{$null=Assert-MIR423MaintenanceUpgradeEvidence -Path $badPath -PackageAssets $PackageAssets}catch{$refused=$_.Exception.Message-ceq'[mir423-upgrade-matrix-cardinality]'}
  if(-not$refused){throw '423 upgrade controls accepted missing predecessor row'};$checks++
  $bad=Clone-UpgradeControl $bundle;$bad.rows[2]=$bad.rows[0];$null=Write-UpgradeControlJson $badPath $bad
  $refused=$false;try{$null=Assert-MIR423MaintenanceUpgradeEvidence -Path $badPath -PackageAssets $PackageAssets}catch{$refused=$_.Exception.Message-ceq'[mir423-upgrade-matrix-identity]'}
  if(-not$refused){throw '423 upgrade controls accepted duplicate predecessor row'};$checks++
  $package=Clone-UpgradeControl $PackageAssets[0];$package.sha256='A'*64
  $refused=$false;try{$null=Assert-MIR423NativeUpgradeProof $rows[0] $package}catch{$refused=$_.Exception.Message-ceq'[mir423-upgrade-native-binding]'}
  if(-not$refused){throw '423 upgrade controls accepted wrong candidate'};$checks++
  $badReceipt=Get-Content $rows[2].receipt.path -Raw|ConvertFrom-Json -AsHashtable -Depth 100
  $badReceipt.published_maintenance_predecessor.source_tag='v4.2.1'
  $badRow=Clone-UpgradeControl $rows[2];$badRow.receipt=Write-UpgradeControlJson (Join-Path (Split-Path $rows[2].receipt.path) 'wrong-published-predecessor.json') $badReceipt
  $refused=$false;try{$null=Assert-MIR423NativeUpgradeProof $badRow $PackageAssets[0]}catch{$refused=$_.Exception.Message-ceq'[mir423-upgrade-published-predecessor]'}
  if(-not$refused){throw '423 upgrade controls accepted wrong published 422 predecessor'};$checks++
  $badReceipt=Get-Content $rows[0].receipt.path -Raw|ConvertFrom-Json -AsHashtable -Depth 100
  $badReceipt.persisted_damage=@{irrelevant=$true}
  $badRow=Clone-UpgradeControl $rows[0];$badRow.receipt=Write-UpgradeControlJson (Join-Path (Split-Path $rows[0].receipt.path) 'transferred-damage.json') $badReceipt
  $refused=$false;try{$null=Assert-MIR423NativeUpgradeProof $badRow $PackageAssets[0]}catch{$refused=$_.Exception.Message-ceq'[mir423-upgrade-damage-scenario-not-transferable]'}
  if(-not$refused){throw '423 upgrade controls accepted transferred 422 damage exception'};$checks++
  $badReceipt=Get-Content $rows[0].receipt.path -Raw|ConvertFrom-Json -AsHashtable -Depth 100
  $null=$badReceipt.Remove('full_state_evaluator_snapshots')
  $badRow=Clone-UpgradeControl $rows[0];$badRow.receipt=Write-UpgradeControlJson (Join-Path (Split-Path $rows[0].receipt.path) 'missing-full-state-snapshots.json') $badReceipt
  $refused=$false;try{$null=Assert-MIR423NativeUpgradeProof $badRow $PackageAssets[0]}catch{$refused=$_.Exception.Message-ceq'[mir423-upgrade-receipt-snapshot-required]'}
  if(-not$refused){throw '423 upgrade controls accepted a receipt without full-state snapshots'};$checks++
  $badReceipt=Get-Content $rows[0].receipt.path -Raw|ConvertFrom-Json -AsHashtable -Depth 100
  $badReceipt.full_state_evaluator_snapshots[0].sha256='0'*64
  $badRow=Clone-UpgradeControl $rows[0];$badRow.receipt=Write-UpgradeControlJson (Join-Path (Split-Path $rows[0].receipt.path) 'mismatched-full-state-snapshot.json') $badReceipt
  $refused=$false;try{$null=Assert-MIR423NativeUpgradeProof $badRow $PackageAssets[0]}catch{$refused=$_.Exception.Message-ceq'[mir423-upgrade-receipt-snapshot-binding]'}
  if(-not$refused){throw '423 upgrade controls accepted mismatched full-state snapshots'};$checks++
  $badReceipt=Get-Content $rows[0].receipt.path -Raw|ConvertFrom-Json -AsHashtable -Depth 100
  $badReceipt.assertions=@($badReceipt.assertions|Where-Object {$_-cne'all-supported-research-queue-retained'})
  $badRow=Clone-UpgradeControl $rows[0];$badRow.receipt=Write-UpgradeControlJson (Join-Path (Split-Path $rows[0].receipt.path) 'missing-full-state-assertion.json') $badReceipt
  $refused=$false;try{$null=Assert-MIR423NativeUpgradeProof $badRow $PackageAssets[0]}catch{$refused=$_.Exception.Message-ceq'[mir423-upgrade-full-state-oracle-assertion]'}
  if(-not$refused){throw '423 upgrade controls accepted a receipt without its full-state oracle assertion'};$checks++
  # Bind opposing full snapshots and receipt hashes, so these mutations reach
  # the semantic evaluator rather than failing an unrelated custody check.
  function Write-ChangedUpgradeControlRow($row,$mutation,$stem){
    $changedRow=Clone-UpgradeControl $row
    $changedReceipt=Get-Content $row.receipt.path -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    $snapshot=Get-Content $row.snapshots[1].path -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    &$mutation $snapshot
    $reference=Write-UpgradeControlJson (Join-Path (Split-Path $row.receipt.path) ($stem+'-snapshot.json')) $snapshot
    $changedRow.snapshots[1]=@{stage='upgrade';path=$reference.path;sha256=$reference.sha256}
    $changedReceipt.full_state_evaluator_snapshots=$changedRow.snapshots
    $changedRow.receipt=Write-UpgradeControlJson (Join-Path (Split-Path $row.receipt.path) ($stem+'-receipt.json')) $changedReceipt
    return $changedRow
  }
  function Write-ChangedUpgradeControlSourceRow($row,$mutation,$stem){
    $changedRow=Clone-UpgradeControl $row
    $changedReceipt=Get-Content $row.receipt.path -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    $snapshot=Get-Content $row.snapshots[0].path -Raw|ConvertFrom-Json -AsHashtable -Depth 100
    if($snapshot.stage-cne'source'){throw '423 upgrade control source snapshot order changed'}
    &$mutation $snapshot
    $reference=Write-UpgradeControlJson (Join-Path (Split-Path $row.receipt.path) ($stem+'-snapshot.json')) $snapshot
    $changedRow.snapshots[0]=@{stage='source';path=$reference.path;sha256=$reference.sha256}
    $changedReceipt.full_state_evaluator_snapshots=$changedRow.snapshots
    $changedRow.receipt=Write-UpgradeControlJson (Join-Path (Split-Path $row.receipt.path) ($stem+'-receipt.json')) $changedReceipt
    return $changedRow
  }
  $mutations=@(
    @{stem='new-unresearched';code='[mir423-upgrade-technology-set]';change={$args[0].forces.player.technologies.d=@{researched=$false;level=1}}},
    @{stem='removed-technology';code='[mir423-upgrade-technology-set]';change={$null=$args[0].forces.player.technologies.Remove('b')}},
    @{stem='replaced-technology';code='[mir422-upgrade-technology-missing]';change={$null=$args[0].forces.player.technologies.Remove('b');$args[0].forces.player.technologies.d=@{researched=$false;level=1}}},
    @{stem='target-definition-added';code='[mir423-upgrade-definition-set]';change={$args[0].forces.player.technologies.a.definition=@{alternate=$true}}},
    @{stem='changed-effect';code='[mir423-upgrade-research-definition]';change={$args[0].forces.player.technologies.a.prototype.effects[0].modifier=0.03}},
    @{stem='changed-science';code='[mir423-upgrade-research-definition]';change={$args[0].forces.player.technologies.a.prototype.ingredients[0].name='chemical-science-pack'}},
    @{stem='changed-cost';code='[mir423-upgrade-research-definition]';change={$args[0].forces.player.technologies.a.prototype.research_unit_count=200}},
    @{stem='missing-definition';code='[mir423-upgrade-definition-set]';change={$null=$args[0].forces.player.technologies.a.Remove('prototype')}},
    @{stem='new-setting';code='[mir423-upgrade-settings]';change={$args[0].forces.player.settings.new_default=$true}},
    @{stem='changed-setting';code='[mir423-upgrade-settings]';change={$args[0].forces.player.settings.kept=$false}},
    @{stem='removed-setting';code='[mir423-upgrade-settings]';change={$null=$args[0].forces.player.settings.Remove('kept')}}
  )
  foreach($case in $mutations){
    $badRow=Write-ChangedUpgradeControlRow $rows[2] $case.change $case.stem
    $refused=$false
    try{$null=Assert-MIR423NativeUpgradeProof $badRow $PackageAssets[0]}catch{$refused=$_.Exception.Message.StartsWith($case.code,[StringComparison]::Ordinal)}
    if(-not$refused){throw ('423 upgrade controls accepted performance-only mutation: '+$case.stem)};$checks++
  }
  $sourceDefinitionRow=Write-ChangedUpgradeControlSourceRow $rows[2] {$args[0].forces.player.technologies.a.definition=@{alternate=$true}} 'source-definition-missing-from-target'
  $refused=$false
  try{$null=Assert-MIR423NativeUpgradeProof $sourceDefinitionRow $PackageAssets[0]}catch{$refused=$_.Exception.Message.StartsWith('[mir423-upgrade-definition-set]',[StringComparison]::Ordinal)}
  if(-not$refused){throw '423 upgrade controls accepted a source definition missing from the target'};$checks++
  $priorPatchDelta={
    $args[0].forces.player.technologies.d=@{researched=$false;level=1}
    $args[0].forces.player.technologies.a.prototype.effects[0].modifier=0.03
  }
  foreach($olderRow in @($rows[0],$rows[1])){
    $allowedRow=Write-ChangedUpgradeControlRow $olderRow $priorPatchDelta 'prior-patch-feature-delta'
    $null=Assert-MIR423NativeUpgradeProof $allowedRow $PackageAssets[0];$checks++
  }
  $bobAngel=Invoke-MIR442F200BobAngelReviewedAdditionControls -Root (Join-Path $Root 'f200-bob-angel-reviewed-additions')
  $checks += [int]$bobAngel.checks
  return [pscustomobject]@{path=$path;checks=$checks;native_runs=0}
}

function Invoke-MIR442F200BobAngelReviewedAdditionControls {
  param([Parameter(Mandatory)][string]$Root)
  # Host-only controls for the source-derived, exact F200 Bob/Angel addition
  # allowance. They do not consume a candidate snapshot or execute Factorio.
  [IO.Directory]::CreateDirectory($Root) | Out-Null
  function Copy-MIR442BobAngelControl($Value) {
    return ($Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100)
  }
  function New-MIR442BobAngelControlActiveMods([string]$MIRVersion) {
    $mods=[ordered]@{}
    foreach($identity in @(
        'angelsbioprocessing@2.0.3','angelsbioprocessinggraphics@2.0.0',
        'angelspetrochem@2.0.3','angelspetrochemgraphics@2.0.1',
        'angelsrefining@2.0.4','angelsrefininggraphics@2.0.0',
        'angelssmelting@2.0.5','angelssmeltinggraphics@2.0.0',
        'base@2.0.77','bobelectronics@2.1.1','boblibrary@2.1.0',
        'bobores@2.1.2','bobplates@2.1.1','bobrevamp@2.1.1',
        'mir-fixture-assert-upgrade-4-0-20000-to-4-1-20000@0.1.89',
        'mir423-startup-observer@1.0.0',('more-infinite-research@'+$MIRVersion))) {
      $name,$version=$identity -split '@',2
      $mods[$name]=$version
    }
    return $mods
  }
  function New-MIR442BobAngelControlState([string]$MIRVersion,[switch]$WithReviewedAdditions) {
    $technologies=[ordered]@{}
    foreach($name in @('existing-a','existing-b','existing-c')) {
      $technologies[$name]=[ordered]@{
        researched=$false;level=1;enabled=$true;visible_when_disabled=$false;saved_progress=0
        prototype=[ordered]@{order=$name;hidden=$false;hidden_in_factoriopedia=$false;max_level=1;prerequisites=@();ingredients=@();effects=@();unit_count=1;unit_count_formula='1';unit_energy=1}
      }
    }
    if($WithReviewedAdditions) {
      foreach($name in (Get-MIR442F200BobAngelReviewedAdditionContracts).Keys) {
        $technologies[$name]=Copy-MIR442BobAngelControl (Get-MIR442F200BobAngelReviewedAdditionContracts)[$name]
      }
    }
    $state=[ordered]@{active_mods=(New-MIR442BobAngelControlActiveMods $MIRVersion);forces=[ordered]@{
      player=[ordered]@{technologies=$technologies;effects=[ordered]@{}}
      enemy=[ordered]@{technologies=(Copy-MIR442BobAngelControl $technologies);effects=[ordered]@{}}
      neutral=[ordered]@{technologies=(Copy-MIR442BobAngelControl $technologies);effects=[ordered]@{}}
    }}
    return ($state | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100)
  }
  function Assert-MIR442BobAngelReaderRefusal([string]$Description,$Before,$After,[Collections.IDictionary]$Contracts,[string]$Code) {
    $refused=$false
    try { Assert-MIR422CompleteSavedState -Before $Before -After $After -RequireExactResearchDefinitions -ReviewedAddedTechnologyContracts $Contracts }
    catch { $refused=$_.Exception.Message.StartsWith($Code,[StringComparison]::Ordinal) }
    if(-not$refused){throw "442 Bob/Angel reviewed-addition controls accepted $Description"}
  }

  $contracts=Get-MIR442F200BobAngelReviewedAdditionContracts
  # This hash is the canonical serialization of the independently reviewed
  # ten-record source contract. Keep the compact field vectors below readable.
  $contractText=(($contracts | ConvertTo-Json -Depth 100) -join "`r`n") + "`r`n"
  if((Get-MIR4Sha256String -Value $contractText)-cne'E9ADABE4F26967CBFE3103CF42A883F1F22BFDF1E2403402DC1290AA5F7B7669'){
    throw '442 Bob/Angel reviewed-addition contract digest changed'
  }
  $expected=[ordered]@{
    'braking-force-8'=@{level=8;unit_count=861;max_level=4294967295;science='automation-science-pack|logistic-science-pack';effect='train-braking-force-bonus|0.15'}
    'inserter-capacity-bonus-8'=@{level=8;unit_count=914488;max_level=4294967295;science='automation-science-pack|logistic-science-pack';effect='inserter-stack-size-bonus|2'}
    'laser-shooting-speed-8'=@{level=8;unit_count=1025;max_level=4294967295;science='automation-science-pack|logistic-science-pack|military-science-pack';effect='gun-speed|0.5'}
    'research-speed-7'=@{level=7;unit_count=683;max_level=4294967295;science='automation-science-pack|logistic-science-pack|military-science-pack';effect='laboratory-speed|0.6'}
    'weapon-shooting-speed-7'=@{level=7;unit_count=683;max_level=4294967295;science='automation-science-pack|logistic-science-pack|military-science-pack';effect='gun-speed|0.4'}
    'worker-robots-storage-4'=@{level=4;unit_count=675;max_level=4294967295;science='automation-science-pack|logistic-science-pack';effect='worker-robot-storage|1'}
    'recipe-prod-research_cannon_shooting_speed-1'=@{level=1;unit_count=60;max_level=4294967295;science='automation-science-pack|logistic-science-pack|military-science-pack';effect='gun-speed|0.1'}
    'recipe-prod-research_electric_shooting_speed-1'=@{level=1;unit_count=60;max_level=4294967295;science='automation-science-pack|logistic-science-pack|military-science-pack';effect='gun-speed|0.1'}
    'recipe-prod-research_material_copper_tungsten-1'=@{level=1;unit_count=200;max_level=3;science='automation-science-pack|logistic-science-pack';effect='change-recipe-productivity|0.02'}
    'recipe-prod-research_material_copper_tungsten-4'=@{level=4;unit_count=1600;max_level=150;science='automation-science-pack|logistic-science-pack|utility-science-pack';effect='change-recipe-productivity|0.02'}
  }
  if((($contracts.Keys|Sort-Object)-join'|') -cne (($expected.Keys|Sort-Object)-join'|')){throw '442 Bob/Angel reviewed-addition contract names changed'}
  foreach($name in $expected.Keys){
    $actual=$contracts[$name];$prototype=$actual.prototype;$firstEffect=$prototype.effects[0]
    $science=(@($prototype.ingredients|ForEach-Object name)-join'|')
    $effectAmount=if($firstEffect.Contains('modifier')){$firstEffect.modifier}else{$firstEffect.change}
    $effect=([string]$firstEffect.type+'|'+[string]$effectAmount)
    if($actual.level-ne$expected[$name].level-or$prototype.unit_count-ne$expected[$name].unit_count-or
      $prototype.max_level-ne$expected[$name].max_level-or$science-cne$expected[$name].science-or
      $effect-cne$expected[$name].effect){throw "442 Bob/Angel reviewed-addition contract changed $name"}
  }
  $source=New-MIR442BobAngelControlState '4.2.20002'
  $upgrade=New-MIR442BobAngelControlState '4.4.20002' -WithReviewedAdditions
  $reload=Copy-MIR442BobAngelControl $upgrade
  $states=[ordered]@{source=$source;upgrade=$upgrade;reload=$reload}
  $record=[ordered]@{
    archetype='f200-bob-angel';factorio_binary_version='2.0.77.84539'
    from=[ordered]@{version='4.2.20002'};to=[ordered]@{version='4.4.20002'}
    f200_bob_angel_input_profile=[ordered]@{
      sha256='306F4D61739054AD63395B80D5C1884A8B1BEAEF222D70640EA446661BB6B0FA'
      source_lock=[ordered]@{sha256='00193B07816DBB0043FDDC0BC801A67BCE47041EC60C171D6837F2141CBF9FED';identity_sha256='AF1B932BF627053685FEC050FF97CC71F50A682B89A64FDACA3223F81771BF22'}
    }
  }
  $row=[pscustomobject]@{target='f200';predecessor_source_version='4.2.2'}
  $package=[pscustomobject]@{sha256='E0DEB9E1A9E3CE83903B9CD3DADB13A51D9DD0BF2E480845554BBCC67CCDC0D2'}
  $selected=Get-MIR442F200BobAngelReviewedAdditions -Record $record -Row $row -Package $package -CandidateSourceVersion '4.4.2' -States $states
  if($null-eq$selected-or-not(Test-MIR422SavedScalarEqual $contracts $selected)){throw '442 Bob/Angel reviewed additions were not selected for the exact lane'}
  $checks=1
  foreach($phase in @('upgrade','reload')) { Assert-MIR422CompleteSavedState -Before $source -After $states[$phase] -RequireExactResearchDefinitions -ReviewedAddedTechnologyContracts $selected; $checks++ }

  $genericRecord=[ordered]@{}
  $generic=Get-MIR442F200BobAngelReviewedAdditions -Record $genericRecord -Row $row -Package $package -CandidateSourceVersion '4.4.2' -States $states
  if($null-ne$generic){throw '442 Bob/Angel reviewed additions selected an incomplete receipt'}
  $genericBefore=New-MIR442BobAngelControlState '4.2.20002'
  $genericAfter=Copy-MIR442BobAngelControl $genericBefore
  Assert-MIR422CompleteSavedState -Before $genericBefore -After $genericAfter -RequireExactResearchDefinitions -ReviewedAddedTechnologyContracts $generic
  $checks++
  $wrongProfile=Copy-MIR442BobAngelControl $record;$wrongProfile.f200_bob_angel_input_profile.sha256='0'*64
  if($null-ne(Get-MIR442F200BobAngelReviewedAdditions -Record $wrongProfile -Row $row -Package $package -CandidateSourceVersion '4.4.2' -States $states)){throw '442 Bob/Angel reviewed additions accepted wrong profile'};$checks++
  $wrongMods=Copy-MIR442BobAngelControl $states;$wrongMods.upgrade.active_mods.base='2.0.78'
  if($null-ne(Get-MIR442F200BobAngelReviewedAdditions -Record $record -Row $row -Package $package -CandidateSourceVersion '4.4.2' -States $wrongMods)){throw '442 Bob/Angel reviewed additions accepted wrong active mods'};$checks++

  $mutations=@(
    @{name='unexpected technology';code='[mir442-f200-bob-angel-added-technology-set]';phase='upgrade';apply={param($state)$state.forces.player.technologies.unreviewed=Copy-MIR442BobAngelControl $contracts['braking-force-8']}},
    @{name='missing reviewed addition';code='[mir442-f200-bob-angel-added-technology-set]';phase='upgrade';apply={param($state)$null=$state.forces.player.technologies.Remove('braking-force-8')}},
    @{name='changed added unit count';code='[mir442-f200-bob-angel-added-technology-definition]';phase='upgrade';apply={param($state)$state.forces.player.technologies['braking-force-8'].prototype.unit_count=862}},
    @{name='changed added effect';code='[mir442-f200-bob-angel-added-technology-definition]';phase='upgrade';apply={param($state)$state.forces.player.technologies['braking-force-8'].prototype.effects[0].modifier=0.16}},
    @{name='changed added science';code='[mir442-f200-bob-angel-added-technology-definition]';phase='upgrade';apply={param($state)$state.forces.player.technologies['braking-force-8'].prototype.ingredients[0].name='chemical-science-pack'}},
    @{name='changed added cap';code='[mir442-f200-bob-angel-added-technology-definition]';phase='upgrade';apply={param($state)$state.forces.player.technologies['recipe-prod-research_material_copper_tungsten-1'].prototype.max_level=4}},
    @{name='earned reviewed addition';code='[mir442-f200-bob-angel-added-technology-definition]';phase='upgrade';apply={param($state)$state.forces.player.technologies['braking-force-8'].researched=$true}},
    @{name='changed existing definition';code='[mir423-upgrade-research-definition]';phase='upgrade';apply={param($state)$state.forces.player.technologies['existing-a'].prototype.order='changed'}},
    @{name='reload-only changed effect';code='[mir442-f200-bob-angel-added-technology-definition]';phase='reload';apply={param($state)$state.forces.player.technologies['braking-force-8'].prototype.effects[0].modifier=0.16}}
  )
  foreach($mutation in $mutations) {
    $after=Copy-MIR442BobAngelControl $states[$mutation.phase]
    & $mutation.apply $after
    Assert-MIR442BobAngelReaderRefusal $mutation.name $source $after $selected $mutation.code
    $checks++
  }
  Assert-MIR442BobAngelReaderRefusal 'the exact lane without its reviewed contract' $source $upgrade $null '[mir423-upgrade-technology-set]';$checks++
  return [pscustomobject]@{checks=$checks;native_runs=0}
}

function Invoke-MIR442F016RestorationControls {
  param([Parameter(Mandatory)][string]$Root)

  # Host-only reader controls. These vectors are independently transcribed from
  # the captured published 4.2.2 F016 definitions, rather than consulting the
  # release-reader allowance. They contain only the reviewed prerequisite field.
  [IO.Directory]::CreateDirectory($Root) | Out-Null
  $vectors = @(
    @{name='braking-force-8';before=@('advanced-electronics','advanced-electronics-2','advanced-material-processing-2','braking-force-6','braking-force-7');after=@('advanced-electronics','advanced-electronics-2','advanced-material-processing-2','automation-2','battery','braking-force-6','braking-force-7','electric-engine','engine','speed-module')},
    @{name='inserter-capacity-bonus-8';before=@('advanced-electronics','advanced-electronics-2','advanced-material-processing-2','inserter-capacity-bonus-6','inserter-capacity-bonus-7');after=@('advanced-electronics','advanced-electronics-2','advanced-material-processing-2','automation-2','battery','electric-engine','engine','inserter-capacity-bonus-6','inserter-capacity-bonus-7','speed-module')},
    @{name='recipe-prod-research_character_crafting_speed-1';before=@('advanced-electronics-2','military-2');after=@('advanced-electronics-2','automation-2','battery','military-2','speed-module','turrets')},
    @{name='recipe-prod-research_character_mining_speed-1';before=@('advanced-electronics-2','military-2');after=@('advanced-electronics-2','automation-2','battery','military-2','speed-module','turrets')},
    @{name='recipe-prod-research_character_reach-1';before=@('advanced-electronics-2','military-2');after=@('advanced-electronics-2','automation-2','battery','military-2','speed-module','turrets')},
    @{name='recipe-prod-research_character_walking_speed-1';before=@('advanced-electronics-2','military-2');after=@('advanced-electronics-2','automation-2','battery','military-2','speed-module','turrets')},
    @{name='recipe-prod-research_electric_shooting_speed-1';before=@('advanced-electronics','advanced-material-processing-2','discharge-defense-equipment','military-2');after=@('advanced-electronics','advanced-material-processing-2','discharge-defense-equipment','electric-engine','engine','military-2','turrets')},
    @{name='recipe-prod-research_flamethrower_shooting_speed-1';before=@('advanced-electronics','advanced-material-processing-2','flamethrower','military-2');after=@('advanced-electronics','advanced-material-processing-2','electric-engine','engine','flamethrower','military-2','turrets')},
    @{name='recipe-prod-research_inventory_capacity-1';before=@('advanced-electronics-2','military-2');after=@('advanced-electronics-2','automation-2','battery','military-2','speed-module','turrets')},
    @{name='recipe-prod-research_lab_productivity-1';before=@('advanced-electronics','advanced-electronics-2','advanced-material-processing-2','military-2');after=@('advanced-electronics','advanced-electronics-2','advanced-material-processing-2','automation-2','battery','electric-engine','engine','military-2','speed-module','turrets')},
    @{name='recipe-prod-research_robot_battery-1';before=@('advanced-electronics','advanced-material-processing-2');after=@('advanced-electronics','advanced-material-processing-2','electric-engine','engine')},
    @{name='recipe-prod-research_rocket_shooting_speed-1';before=@('advanced-electronics','advanced-material-processing-2','military-2','rocketry');after=@('advanced-electronics','advanced-material-processing-2','electric-engine','engine','military-2','rocketry','turrets')},
    @{name='research-speed-7';before=@('advanced-electronics','advanced-electronics-2','advanced-material-processing-2','military-2','research-speed-5','research-speed-6');after=@('advanced-electronics','advanced-electronics-2','advanced-material-processing-2','automation-2','battery','electric-engine','engine','military-2','research-speed-5','research-speed-6','speed-module','turrets')},
    @{name='worker-robots-storage-4';before=@('advanced-electronics','advanced-electronics-2','advanced-material-processing-2','worker-robots-storage-2','worker-robots-storage-3');after=@('advanced-electronics','advanced-electronics-2','advanced-material-processing-2','automation-2','battery','electric-engine','engine','speed-module','worker-robots-storage-2','worker-robots-storage-3')}
  )

  function New-MIR442F016PrerequisiteVector([object[]]$Names) {
    $value = [ordered]@{}
    for ($index = 0; $index -lt $Names.Count; $index++) {
      $value[($index + 1).ToString([Globalization.CultureInfo]::InvariantCulture)] = [string]$Names[$index]
    }
    return $value
  }
  function New-MIR442F016Snapshot([string]$FromVersion,[string]$EngineLine,[switch]$Restored) {
    $forces = [ordered]@{}
    foreach ($forceName in @('enemy','neutral','player')) {
      $technologies = [ordered]@{}
      foreach ($row in $vectors) {
        $prerequisites = New-MIR442F016PrerequisiteVector $(if ($Restored) { @($row.after) } else { @($row.before) })
        $technologies[[string]$row.name] = [ordered]@{
          researched=$false;level=1
          definition=[ordered]@{
            effects=@(@{type='laboratory-speed';modifier=0.1})
            ingredients=@(@{name='automation-science-pack';amount=1})
            prerequisites=$prerequisites
            max_level='infinite';order='a';unit_count=100;unit_count_formula='100*L';unit_energy=30
          }
        }
      }
      $forces[$forceName] = [ordered]@{
        technologies=$technologies;bonuses=@{};recipes=@{};settings=@{};effects=@{};ammo=@{};gun_speed=@{};turret=@{}
        queue=@();research_queue_enabled=$true;current_research=$null;research_progress=0
      }
    }
    # Native evaluator snapshots are JSON records read with -AsHashtable. Keep
    # the control representation identical so IDictionary.Clone behavior and
    # numeric-string prerequisite dictionaries use the real reader shape.
    return ([ordered]@{engine_line=$EngineLine;from_version=$FromVersion;to_version='4.4.01602';forces=$forces} |
      ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100)
  }
  function Assert-MIR442F016ReaderRefusal([string]$Description,$Before,$After) {
    $refused = $false
    try { Assert-MIR422CompleteSavedState -Before $Before -After $After -RequireExactResearchDefinitions }
    catch { $refused = $_.Exception.Message.StartsWith('[mir423-upgrade-research-definition]',[StringComparison]::Ordinal) }
    if (-not $refused) { throw "442 F016 restoration controls accepted $Description" }
  }

  $checks = 0
  foreach ($fromVersion in @('4.4.01600','4.4.01601')) {
    $before = New-MIR442F016Snapshot -FromVersion $fromVersion -EngineLine '0.16'
    $after = New-MIR442F016Snapshot -FromVersion $fromVersion -EngineLine '0.16' -Restored
    Assert-MIR422CompleteSavedState -Before $before -After $after -RequireExactResearchDefinitions
    $checks++
  }

  $before = New-MIR442F016Snapshot -FromVersion '4.4.01600' -EngineLine '0.16'
  $after = New-MIR442F016Snapshot -FromVersion '4.4.01600' -EngineLine '0.16' -Restored
  $after.forces.player.technologies['braking-force-8'].definition.prerequisites['99'] = 'forged-prerequisite'
  Assert-MIR442F016ReaderRefusal 'an unreviewed F016 prerequisite' $before $after; $checks++

  $before = New-MIR442F016Snapshot -FromVersion '4.4.01600' -EngineLine '0.16'
  $after = New-MIR442F016Snapshot -FromVersion '4.4.01600' -EngineLine '0.16' -Restored
  $after.forces.neutral.technologies['recipe-prod-research_lab_productivity-1'].definition.unit_count = 101
  Assert-MIR442F016ReaderRefusal 'a non-prerequisite change on a reviewed technology' $before $after; $checks++

  $before = New-MIR442F016Snapshot -FromVersion '4.2.01602' -EngineLine '0.16'
  $after = New-MIR442F016Snapshot -FromVersion '4.2.01602' -EngineLine '0.16' -Restored
  Assert-MIR442F016ReaderRefusal 'a direct published 4.2.2 predecessor' $before $after; $checks++

  $before = New-MIR442F016Snapshot -FromVersion '4.4.01600' -EngineLine '0.15'
  $after = New-MIR442F016Snapshot -FromVersion '4.4.01600' -EngineLine '0.15' -Restored
  Assert-MIR442F016ReaderRefusal 'a non-F016 engine line' $before $after; $checks++

  $before = New-MIR442F016Snapshot -FromVersion '4.4.01600' -EngineLine '0.16'
  $after = New-MIR442F016Snapshot -FromVersion '4.4.01600' -EngineLine '0.16' -Restored
  $after.to_version = '4.4.01603'
  Assert-MIR442F016ReaderRefusal 'a non-4.4.01602 destination' $before $after; $checks++

  $before = New-MIR442F016Snapshot -FromVersion '4.4.01600' -EngineLine '0.16'
  $after = New-MIR442F016Snapshot -FromVersion '4.4.01600' -EngineLine '0.16' -Restored
  $beforeTechnology = $before.forces.player.technologies['braking-force-8']
  $afterTechnology = $after.forces.player.technologies['braking-force-8']
  $null = $before.forces.player.technologies.Remove('braking-force-8')
  $null = $after.forces.player.technologies.Remove('braking-force-8')
  $before.forces.player.technologies['Braking-force-8'] = $beforeTechnology
  $after.forces.player.technologies['Braking-force-8'] = $afterTechnology
  Assert-MIR442F016ReaderRefusal 'a case-altered reviewed technology name' $before $after; $checks++

  return [pscustomobject]@{checks=$checks;native_runs=0}
}
