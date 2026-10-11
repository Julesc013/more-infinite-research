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
  return [pscustomobject]@{path=$path;checks=$checks;native_runs=0}
}
