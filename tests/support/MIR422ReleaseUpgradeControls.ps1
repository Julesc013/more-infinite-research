function Invoke-MIR422ReleaseUpgradeControls {
  param([string]$Root,[object[]]$PackageAssets)
  # Synthetic host controls only. These records never leave this disposable
  # test root and establish no Factorio or publication result.
  [IO.Directory]::CreateDirectory($Root)|Out-Null
  $checks=0
  function Write-UpgradeControlJson($path,$value){$value|ConvertTo-Json -Depth 100|Set-Content $path;return [pscustomobject]@{path=$path;sha256=(Get-FileHash $path).Hash}}
  function Clone-UpgradeControl($value){return $value|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable -Depth 100}
  $rows=@()
  foreach($package in $PackageAssets){
    foreach($patch in @(0,1)){
      $stem=$package.target+'-'+$patch;$directory=Join-Path $Root $stem
      [IO.Directory]::CreateDirectory($directory)|Out-Null
      $version='4.2.'+$package.target.Substring(1)+$patch.ToString('00');$to=$package.distribution_version
      $pinPath=if($patch-eq0){'fixtures/release-inputs/mir421-published-420-manifest.json'}else{'fixtures/release-inputs/mir422-published-421-manifest.json'}
      $pin=Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath (Join-Path $repo $pinPath) -CandidateSourceVersion $(if($patch-eq0){'4.2.1'}else{'4.2.2'})
      $published=@($pin.manifest.targets|Where-Object target -CEQ $package.target)[0]
      $state=@{forces=@{player=@{technologies=@{a=@{researched=$true;level=2};b=@{researched=$false;level=1};c=@{researched=$false;level=1}};bonuses=@{plate=0.1};settings=@{kept=$true};effects=@{speed=0.1};ammo=@{bullet=0.1};gun_speed=@{};turret=@{};queue=@('b');current_research='b';research_progress=0.42}};from_version=$version;to_version=$to}
      $snapshots=@(foreach($phase in @('source','upgrade','reload')){
        $snapshot=Clone-UpgradeControl $state;$snapshot.stage=$phase
        $reference=Write-UpgradeControlJson (Join-Path $directory ($phase+'.json')) $snapshot
        [pscustomobject]@{stage=$phase;path=$reference.path;sha256=$reference.sha256}
      })
      $native=@{schema=3;status='passed';factorio_processes=4;from=@{version=$version;sha256=$published.sha256};to=@{version=$to;sha256=$package.sha256};published_maintenance_predecessor=@{source_tag=$(if($patch-eq0){'v4.2.0-stable'}else{'v4.2.1'});manifest=@{sha256=$pin.sha256}};assertions=@('exact-candidate-normal-mod-directory-load','upgraded-save-reload-passed','upgraded-save-second-reload-passed');resource_ledgers=@();library_activation=@{status='restored-direct-library-controls';dependency_payload_bytes_copied=0;archive_links_created=0;archive_extractions=0}}
      foreach($phase in @('create','load','reload','second_reload')){
        $file=Join-Path $directory ($phase+'.txt');[IO.File]::WriteAllText($file,'[mir-fixture] complete research state retained technologies=3 recipes=1')
        $native[$phase+'_log']=Split-Path $file -Leaf;$native[$phase+'_log_sha256']=(Get-FileHash $file).Hash
        $ledger=Join-Path $directory ($phase+'.resources.jsonl');[IO.File]::WriteAllText($ledger,'{"synthetic_host_control":true}')
        $native.resource_ledgers+=@{filename=(Split-Path $ledger -Leaf);sha256=(Get-FileHash $ledger).Hash;exit_code=0;completion_predicate_observed=$false}
      }
      $receipt=Write-UpgradeControlJson (Join-Path $directory 'receipt.json') $native
      $rows+=[pscustomobject]@{target=$package.target;predecessor_source_version=('4.2.'+$patch);receipt=$receipt;snapshots=$snapshots}
    }
  }
  $damage=Clone-UpgradeControl $rows[0];$r=Get-Content $damage.receipt.path -Raw|ConvertFrom-Json -AsHashtable -Depth 100
  $damageDirectory=Join-Path $Root 'damage';[IO.Directory]::CreateDirectory($damageDirectory)|Out-Null
  $pin=Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath (Join-Path $repo 'fixtures/release-inputs/mir422-published-421-manifest.json') -CandidateSourceVersion '4.2.2'
  $saved=Join-Path $damageDirectory 'persisted.zip';[IO.File]::WriteAllText($saved,'synthetic persisted input')
  $r.native_scenario='reduced-published420-persisted421-damage-to422-survivor-preservation'
  $r.persisted_damage=@{pre_damage_snapshot_is_external_only=$true;lost_history_recovered=$false;post_damage_progress=0.57;save_path=$saved;save_sha256=(Get-FileHash $saved).Hash;log=$r.load_log;log_sha256=$r.load_log_sha256;published_intermediate=@{source_tag='v4.2.1';manifest=@{sha256=$pin.sha256};targets=@(@{target='f210';sha256=$pin.manifest.targets[0].sha256})}}
  $r.factorio_processes=5;$r.resource_ledgers+=@($r.resource_ledgers[0])
  $damage.receipt=Write-UpgradeControlJson (Join-Path (Split-Path $rows[0].receipt.path) 'damage-receipt.json') $r
  $ds=Get-Content $damage.snapshots[0].path -Raw|ConvertFrom-Json -AsHashtable -Depth 100;$ds.stage='persisted-damage'
  $ref=Write-UpgradeControlJson (Join-Path $damageDirectory 'damage.json') $ds
  $damage.snapshots+=@{stage='persisted-damage';path=$ref.path;sha256=$ref.sha256}
  $bundle=@{schema=1;kind='MIR422MaintenanceUpgradeEvidenceV1';source_version='4.2.2';rows=$rows;damaged_save=$damage}
  $path=Join-Path $Root 'evidence.json';$null=Write-UpgradeControlJson $path $bundle
  $null=Assert-MIR422MaintenanceUpgradeEvidence -Path $path -PackageAssets $PackageAssets;$checks++
  $bad=Clone-UpgradeControl $bundle;$bad.rows=@($bad.rows|Select-Object -First 17)
  $badPath=Join-Path $Root 'missing-row.json';$null=Write-UpgradeControlJson $badPath $bad
  $refused=$false;try{$null=Assert-MIR422MaintenanceUpgradeEvidence -Path $badPath -PackageAssets $PackageAssets}catch{$refused=$_.Exception.Message-ceq'[mir422-upgrade-matrix-cardinality]'}
  if(-not$refused){throw 'upgrade controls accepted missing predecessor row'};$checks++
  $bad=Clone-UpgradeControl $bundle;$bad.rows[1]=$bad.rows[0];$null=Write-UpgradeControlJson $badPath $bad
  $refused=$false;try{$null=Assert-MIR422MaintenanceUpgradeEvidence -Path $badPath -PackageAssets $PackageAssets}catch{$refused=$_.Exception.Message-ceq'[mir422-upgrade-matrix-identity]'}
  if(-not$refused){throw 'upgrade controls accepted duplicate predecessor'};$checks++
  $package=Clone-UpgradeControl $PackageAssets[0];$package.sha256='A'*64
  $refused=$false;try{$null=Assert-MIR422NativeUpgradeProof $rows[0] $package}catch{$refused=$_.Exception.Message-ceq'[mir422-upgrade-native-binding]'}
  if(-not$refused){throw 'upgrade controls accepted wrong candidate'};$checks++
  $before=Get-Content $rows[0].snapshots[0].path -Raw|ConvertFrom-Json -AsHashtable -Depth 100
  foreach($mutate in @(
    {$args[0].forces.player.technologies.Remove('a')|Out-Null},
    {$args[0].forces.player.technologies.a.researched=$false},
    {$args[0].forces.player.bonuses.plate=0},
    {$args[0].forces.player.research_progress=0},
    {$args[0].forces.player.queue=@()},
    {$args[0].forces.player.gun_speed.new_category=0.1},
    {$args[0].forces.player.technologies=@(1,2,3)},
    {$args[0].forces.player.technologies.a='scalar'},
    {$args[0].forces.player.bonuses=@(1,2,3)},
    {$args[0].forces.player.effects=@(1,2,3)}
  )){
    $after=Clone-UpgradeControl $before;&$mutate $after;$refused=$false
    try{Assert-MIR422CompleteSavedState $before $after}catch{$refused=$true}
    if(-not$refused){throw 'upgrade controls accepted changed saved state'};$checks++
  }
  $after=Clone-UpgradeControl $before;$after.forces.player.gun_speed.new_category=0
  Assert-MIR422CompleteSavedState $before $after;$checks++
  $bad=Clone-UpgradeControl $r;$bad.assertions=@($bad.assertions|Where-Object {$_-cne'upgraded-save-second-reload-passed'})
  $badRow=Clone-UpgradeControl $damage;$badRow.receipt=Write-UpgradeControlJson (Join-Path (Split-Path $rows[0].receipt.path) 'skipped-receipt.json') $bad
  $refused=$false;try{$null=Assert-MIR422NativeUpgradeProof $badRow $PackageAssets[0] -Damaged}catch{$refused=$_.Exception.Message-ceq'[mir422-upgrade-phase-skipped]'}
  if(-not$refused){throw 'upgrade controls accepted skipped phase'};$checks++
  $bad=Clone-UpgradeControl $r;$file=Join-Path (Split-Path $rows[0].receipt.path) 'empty-phase.txt';[IO.File]::WriteAllText($file,'loaded without full-state checker');$bad.load_log=Split-Path $file -Leaf;$bad.load_log_sha256=(Get-FileHash $file).Hash
  $badRow.receipt=Write-UpgradeControlJson (Join-Path (Split-Path $rows[0].receipt.path) 'empty-receipt.json') $bad
  $refused=$false;try{$null=Assert-MIR422NativeUpgradeProof $badRow $PackageAssets[0] -Damaged}catch{$refused=$_.Exception.Message-ceq'[mir422-upgrade-full-state-phase-skipped]'}
  if(-not$refused){throw 'upgrade controls accepted absent state checker'};$checks++
  $bad=Get-Content $rows[0].receipt.path -Raw|ConvertFrom-Json -AsHashtable -Depth 100
  $bad.full_state_evaluator_snapshots=Clone-UpgradeControl $rows[0].snapshots
  $bad.full_state_evaluator_snapshots[0].sha256='F'*64
  $badRow=Clone-UpgradeControl $rows[0];$badRow.receipt=Write-UpgradeControlJson (Join-Path (Split-Path $rows[0].receipt.path) 'swapped-snapshot-receipt.json') $bad
  $refused=$false;try{$null=Assert-MIR422NativeUpgradeProof $badRow $PackageAssets[0]}catch{$refused=$_.Exception.Message-ceq'[mir422-upgrade-receipt-snapshot-binding]'}
  if(-not$refused){throw 'upgrade controls accepted receipt snapshot substitution'};$checks++
  return [pscustomobject]@{path=$path;checks=$checks;native_runs=0}
}
