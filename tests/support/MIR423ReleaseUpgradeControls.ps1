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
  return [pscustomobject]@{path=$path;checks=$checks;native_runs=0}
}
