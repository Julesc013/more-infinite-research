Set-StrictMode -Version Latest

function New-MIR421ReleaseAssetCustodyFixture {
  param([Parameter(Mandatory)][string]$RepoRoot,[ValidateSet('4.2.1','4.2.2','4.2.3','4.3.0','4.3.1','4.4.0','4.4.2')][string]$CandidateSourceVersion='4.2.1')
  # Structural fixtures only: IDs and paths are synthetic. No network, native
  # campaign, signature or actual release qualification is claimed here.
  $contract=Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion $CandidateSourceVersion
  $pinPath=switch($CandidateSourceVersion){
    '4.2.1' {'fixtures/release-inputs/mir421-published-420-manifest.json'}
    '4.2.2' {'fixtures/release-inputs/mir422-published-421-manifest.json'}
    '4.2.3' {'fixtures/release-inputs/mir423-published-422-manifest.json'}
    '4.3.0' {'fixtures/release-inputs/mir423-published-422-manifest.json'}
    '4.3.1' {'fixtures/release-inputs/mir431-published-430-manifest.json'}
    '4.4.0' {'fixtures/release-inputs/mir431-published-430-manifest.json'}
    '4.4.2' {'fixtures/release-inputs/mir442-published-441-manifest.json'}
  }
  $pin=Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath (Join-Path $RepoRoot $pinPath) -CandidateSourceVersion $CandidateSourceVersion
  return [pscustomobject][ordered]@{
    release_id=$contract.release_id;source_tag=$contract.source_tag;source=$pin.manifest.source
    tag_object=('a' * 40);remote_tag_readback=$true
    manifest=[ordered]@{path='structural-fixture-only';sha256=$pin.sha256;bytes=$pin.bytes}
    signed=$false
    targets=@(foreach ($index in 0..8) {
      $row=$pin.manifest.targets[$index]
      [pscustomobject][ordered]@{target=$row.target;version=$row.distribution_version;path='structural-fixture-only';sha256=$row.sha256;bytes=$row.bytes;content_sha256=$row.content_sha256;entry_count=$row.entry_count;github_asset_id=($index + 1);github_digest=('sha256:' + $row.sha256.ToLowerInvariant())}
    })
    native_qualification='not-performed';release_qualification='not-performed'
  }
}
function Invoke-MIR430FullReleaseUpgradeControls {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$PackageAssets,[ValidateSet('4.3.0','4.3.1','4.4.0','4.4.2')][string]$CandidateSourceVersion='4.3.0')

  # Host-only structural controls. 4.3.0 proves all direct 4.2.x inputs; 4.3.1
  # and 4.4.0 use direct published 4.2.2 plus published 4.3.0, while 4.4.2
  # binds its explicit published 4.2.2, 4.4.0 and 4.4.1 lanes. Every path
  # requires the same complete definition and saved-state oracle.
  [IO.Directory]::CreateDirectory($Root) | Out-Null
  function Write-MIR430UpgradeJson($Path,$Value) {
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path
    return [pscustomobject]@{path=$Path;sha256=(Get-FileHash -LiteralPath $Path).Hash}
  }
  function Copy-MIR430UpgradeValue($Value) {
    return $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100
  }
  function Assert-MIR430Rejected($Action,[string]$Expected,[string]$Description) {
    $rejected = $false
    try { & $Action } catch { $rejected = $_.Exception.Message.StartsWith($Expected,[StringComparison]::Ordinal) }
    if (-not $rejected) { throw "upgrade controls accepted $Description" }
    $script:mir430UpgradeControlChecks++
  }
  function New-MIR430ChangedRow($Row,$Mutation,[string]$Stem,[string]$Stage='upgrade') {
    $changed = Copy-MIR430UpgradeValue $Row
    $receipt = Get-Content -LiteralPath $Row.receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $index = if ($Stage -ceq 'source') { 0 } else { 1 }
    $snapshot = Get-Content -LiteralPath $Row.snapshots[$index].path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    if ([string]$snapshot.stage -cne $Stage) { throw "430 upgrade control $Stage snapshot order changed" }
    & $Mutation $snapshot
    $reference = Write-MIR430UpgradeJson (Join-Path (Split-Path -Parent $Row.receipt.path) ($Stem + '-snapshot.json')) $snapshot
    $changed.snapshots[$index] = @{stage=$Stage;path=$reference.path;sha256=$reference.sha256}
    $receipt.full_state_evaluator_snapshots = $changed.snapshots
    $changed.receipt = Write-MIR430UpgradeJson (Join-Path (Split-Path -Parent $Row.receipt.path) ($Stem + '-receipt.json')) $receipt
    return $changed
  }

  $script:mir430UpgradeControlChecks = 0
  $predecessorVersions = if ($CandidateSourceVersion -ceq '4.4.2') { @('4.2.2','4.4.0','4.4.1') } elseif ($CandidateSourceVersion -cin @('4.3.1','4.4.0','4.4.2')) { @('4.2.2','4.3.0') } else { @('4.2.0','4.2.1','4.2.2') }
  $rows = @()
  foreach ($package in $PackageAssets) {
    foreach ($sourceVersion in $predecessorVersions) {
      $source = [version]$sourceVersion
      $directory = Join-Path $Root ($package.target + '-' + $sourceVersion.Replace('.','-'))
      [IO.Directory]::CreateDirectory($directory) | Out-Null
      $predecessor = Get-MIR423PublishedUpgradePredecessor -Target $package.target -PredecessorSourceVersion $sourceVersion -CandidateSourceVersion $CandidateSourceVersion
      $from = '4.' + $source.Minor + '.' + $package.target.Substring(1) + $source.Build.ToString('00')
      $to = [string]$package.distribution_version
      $state = @{
        forces=@{player=@{
          technologies=@{a=@{researched=$true;level=2};b=@{researched=$false;level=1};c=@{researched=$false;level=1}}
          bonuses=@{plate=0.1};settings=@{kept=$true};effects=@{speed=0.1};ammo=@{bullet=0.1};gun_speed=@{};turret=@{}
          queue=@('b');current_research='b';research_progress=0.42
        }}
        from_version=$from;to_version=$to
      }
      foreach ($technology in $state.forces.player.technologies.Values) {
        $technology.prototype=@{effects=@(@{type='mining-drill-productivity-bonus';modifier=0.02});ingredients=@(@{name='automation-science-pack';amount=1});prerequisites=@();research_unit_count=100;research_unit_energy=30;max_level=10}
      }
      $snapshots = @(
        foreach ($stage in @('source','upgrade','reload')) {
          $snapshot = Copy-MIR430UpgradeValue $state
          $snapshot.stage = $stage
          $reference = Write-MIR430UpgradeJson (Join-Path $directory ($stage + '.json')) $snapshot
          [pscustomobject]@{stage=$stage;path=$reference.path;sha256=$reference.sha256}
        }
      )
      $receipt = @{
        schema=3;status='passed';factorio_processes=4
        from=@{version=$from;sha256=$predecessor.target.sha256};to=@{version=$to;sha256=$package.sha256}
        published_maintenance_predecessor=@{source_tag=$predecessor.source_tag;manifest=@{sha256=$predecessor.manifest.sha256}}
        assertions=@('exact-candidate-normal-mod-directory-load','upgraded-save-reload-passed','upgraded-save-second-reload-passed','all-existing-technology-state-and-definitions-retained','all-exposed-earned-effects-retained','all-supported-research-queue-retained','full-state-oracle-executed-upgrade-and-two-reloads')
        resource_ledgers=@();library_activation=@{status='restored-direct-library-controls';dependency_payload_bytes_copied=0;archive_links_created=0;archive_extractions=0};full_state_evaluator_snapshots=$snapshots
      }
      foreach ($stage in @('create','load','reload','second_reload')) {
        $log = Join-Path $directory ($stage + '.txt')
        [IO.File]::WriteAllText($log,'[mir-fixture] complete research state retained technologies=3 recipes=1')
        $receipt[$stage + '_log'] = Split-Path -Leaf $log
        $receipt[$stage + '_log_sha256'] = (Get-FileHash -LiteralPath $log).Hash
        $ledger = Join-Path $directory ($stage + '.resources.jsonl')
        [IO.File]::WriteAllText($ledger,'{"synthetic_host_control":true}')
        $receipt.resource_ledgers += @{filename=(Split-Path -Leaf $ledger);sha256=(Get-FileHash -LiteralPath $ledger).Hash;exit_code=0;completion_predicate_observed=$false}
      }
      $receiptReference = Write-MIR430UpgradeJson (Join-Path $directory 'receipt.json') $receipt
      $rows += [pscustomobject]@{target=$package.target;predecessor_source_version=$sourceVersion;receipt=$receiptReference;snapshots=$snapshots}
    }
  }
  $bundle = @{schema=1;kind=('MIR' + $CandidateSourceVersion.Replace('.','') + 'MaintenanceUpgradeEvidenceV1');source_version=$CandidateSourceVersion;rows=$rows}
  $path = Join-Path $Root 'evidence.json'
  $null = Write-MIR430UpgradeJson $path $bundle
  $null = Assert-MIR423MaintenanceUpgradeEvidence -Path $path -PackageAssets $PackageAssets -CandidateSourceVersion $CandidateSourceVersion
  $script:mir430UpgradeControlChecks++

  $missing = Copy-MIR430UpgradeValue $bundle
  $missing.rows = @($missing.rows | Select-Object -First ($rows.Count - 1))
  $missingPath = Join-Path $Root 'missing.json'
  $null = Write-MIR430UpgradeJson $missingPath $missing
  $errorPrefix = 'mir' + $CandidateSourceVersion.Replace('.','') + '-upgrade'
  Assert-MIR430Rejected { Assert-MIR423MaintenanceUpgradeEvidence -Path $missingPath -PackageAssets $PackageAssets -CandidateSourceVersion $CandidateSourceVersion } ('[' + $errorPrefix + '-matrix-cardinality]') 'a missing predecessor row'
  $duplicate = Copy-MIR430UpgradeValue $bundle
  $duplicate.rows[2] = $duplicate.rows[0]
  $duplicatePath = Join-Path $Root 'duplicate.json'
  $null = Write-MIR430UpgradeJson $duplicatePath $duplicate
  Assert-MIR430Rejected { Assert-MIR423MaintenanceUpgradeEvidence -Path $duplicatePath -PackageAssets $PackageAssets -CandidateSourceVersion $CandidateSourceVersion } ('[' + $errorPrefix + '-matrix-identity]') 'a duplicate predecessor row'
  if ($CandidateSourceVersion -cin @('4.3.1','4.4.0','4.4.2')) {
    $wrongPredecessor = Copy-MIR430UpgradeValue $rows[0]
    $wrongPredecessor.predecessor_source_version = '4.2.1'
    Assert-MIR430Rejected { Assert-MIR423NativeUpgradeProof -Row $wrongPredecessor -Package $PackageAssets[0] -CandidateSourceVersion $CandidateSourceVersion } '[mir423-upgrade-predecessor-version]' 'an obsolete 4.2.1 predecessor for a dual-predecessor release'
  }

  $wrongPackage = Copy-MIR430UpgradeValue $PackageAssets[0]
  $wrongPackage.sha256 = if ([string]$PackageAssets[0].sha256 -ceq ('A' * 64)) { 'B' * 64 } else { 'A' * 64 }
  Assert-MIR430Rejected { Assert-MIR423NativeUpgradeProof -Row $rows[0] -Package $wrongPackage -CandidateSourceVersion $CandidateSourceVersion } ('[' + $errorPrefix + '-native-binding]') 'a wrong candidate archive'
  $wrongMinorReceipt = Get-Content -LiteralPath $rows[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
  $wrongMinorReceipt.to.version = '4.' + ([version]$CandidateSourceVersion).Minor + '.' + $PackageAssets[0].target.Substring(1) + (([version]$CandidateSourceVersion).Build + 1).ToString('00')
  $wrongMinorRow = Copy-MIR430UpgradeValue $rows[0]
  $wrongMinorRow.receipt = Write-MIR430UpgradeJson (Join-Path (Split-Path -Parent $rows[0].receipt.path) 'wrong-destination-minor.json') $wrongMinorReceipt
  Assert-MIR430Rejected { Assert-MIR423NativeUpgradeProof -Row $wrongMinorRow -Package $PackageAssets[0] -CandidateSourceVersion $CandidateSourceVersion } ('[' + $errorPrefix + '-native-binding]') 'a 4.2 destination projection'

  # Bind the receipt and package from the same direct row.  A fixed row index
  # would pair a different target after the 4.3.1 matrix gained its immediate
  # predecessor lane, turning this hash/tag control into a no-op.
  $badReceipt = Get-Content -LiteralPath $rows[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
  $badReceipt.published_maintenance_predecessor.source_tag = 'v-not-the-published-predecessor'
  $publishedRow = Copy-MIR430UpgradeValue $rows[0]
  $publishedRow.receipt = Write-MIR430UpgradeJson (Join-Path (Split-Path -Parent $rows[0].receipt.path) 'wrong-published.json') $badReceipt
  Assert-MIR430Rejected { Assert-MIR423NativeUpgradeProof -Row $publishedRow -Package $PackageAssets[0] -CandidateSourceVersion $CandidateSourceVersion } ('[' + $errorPrefix + '-published-predecessor]') 'the wrong published predecessor'

  $mutations = @(
    @{stem='old-definition';stage='upgrade';code='[mir423-upgrade-research-definition]';change={$args[0].forces.player.technologies.a.prototype.effects[0].modifier=0.03}},
    @{stem='old-science';stage='upgrade';code='[mir423-upgrade-research-definition]';change={$args[0].forces.player.technologies.a.prototype.ingredients[0].name='chemical-science-pack'}},
    @{stem='old-setting';stage='upgrade';code='[mir423-upgrade-settings]';change={$args[0].forces.player.settings.kept=$false}},
    @{stem='old-source-definition';stage='source';code='[mir423-upgrade-research-definition]';change={$args[0].forces.player.technologies.a.prototype.research_unit_count=200}},
    @{stem='missing-noncore-technology';stage='source';code='[mir423-upgrade-technology-set]';change={param($snapshot) $snapshot.forces.player.technologies.'requested-noncore-research'=@{researched=$false;level=1;prototype=@{effects=@(@{type='laboratory-speed';modifier=0.1});ingredients=@(@{name='automation-science-pack';amount=1});prerequisites=@();research_unit_count=100;research_unit_energy=30;max_level=10}}}}
  )
  # Index 0 is the direct published predecessor for this candidate. It
  # deliberately proves no prior-patch definition allowance crosses releases.
  foreach ($mutation in $mutations) {
    $changed = New-MIR430ChangedRow -Row $rows[0] -Mutation $mutation.change -Stem $mutation.stem -Stage $mutation.stage
    Assert-MIR430Rejected { Assert-MIR423NativeUpgradeProof -Row $changed -Package $PackageAssets[0] -CandidateSourceVersion $CandidateSourceVersion } $mutation.code ('a retained-state mutation: ' + $mutation.stem)
  }
  $fullProfile = New-MIR430ChangedRow -Row $rows[0] -Mutation { param($snapshot) $snapshot.forces.player.settings['mir-compiler-profile'] = 'full' } -Stem 'new-full-compiler-profile' -Stage 'upgrade'
  $fullProfileReceipt = Get-Content -LiteralPath $fullProfile.receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
  $reloadSnapshot = Get-Content -LiteralPath $fullProfile.snapshots[2].path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
  $reloadSnapshot.forces.player.settings['mir-compiler-profile'] = 'full'
  $reloadReference = Write-MIR430UpgradeJson (Join-Path (Split-Path -Parent $fullProfile.receipt.path) 'new-full-compiler-profile-reload.json') $reloadSnapshot
  $fullProfile.snapshots[2] = @{stage='reload';path=$reloadReference.path;sha256=$reloadReference.sha256}
  $fullProfileReceipt.full_state_evaluator_snapshots = $fullProfile.snapshots
  $fullProfile.receipt = Write-MIR430UpgradeJson (Join-Path (Split-Path -Parent $fullProfile.receipt.path) 'new-full-compiler-profile-receipt.json') $fullProfileReceipt
  $null = Assert-MIR423NativeUpgradeProof -Row $fullProfile -Package $PackageAssets[0] -CandidateSourceVersion $CandidateSourceVersion
  $script:mir430UpgradeControlChecks++
  $classicProfile = New-MIR430ChangedRow -Row $rows[0] -Mutation { param($snapshot) $snapshot.forces.player.settings['mir-compiler-profile'] = 'classic' } -Stem 'new-classic-compiler-profile' -Stage 'upgrade'
  Assert-MIR430Rejected { Assert-MIR423NativeUpgradeProof -Row $classicProfile -Package $PackageAssets[0] -CandidateSourceVersion $CandidateSourceVersion } '[mir423-upgrade-settings]' 'a new Classic compiler-profile setting'
  return [pscustomobject]@{path=$path;checks=$script:mir430UpgradeControlChecks;native_runs=0}
}

function Invoke-MIR430ReleaseUpgradeControls {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$PackageAssets,[ValidateSet('4.3.0','4.3.1','4.4.0','4.4.2')][string]$CandidateSourceVersion='4.3.0')

  # The release matrix is Full-only. Build its complete-state controls first,
  # then prove that a Classic omission receipt cannot be admitted in place of
  # them. Classic compiler behavior is characterized by compiler fixtures; it
  # is not release-preservation evidence.
  $full = Invoke-MIR430FullReleaseUpgradeControls -Root (Join-Path $Root 'full') -PackageAssets $PackageAssets -CandidateSourceVersion $CandidateSourceVersion
  $bundle = Get-Content -LiteralPath $full.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
  $row = @($bundle.rows | Where-Object { [string]$_.target -ceq 'f200' -and [string]$_.predecessor_source_version -ceq '4.2.2' })
  if ($row.Count -ne 1) { throw '430 release controls could not locate the Full f200 4.2.2 row' }
  $receipt = Get-Content -LiteralPath $row[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
  $receipt.upgrade_policy = @{schema=1;kind='MIR430ClassicReducedUpgradePolicyV1';compiler_profile='classic';full_catalog_status='not-evaluated';omitted_research_not_preserved=$true}
  $receipt.classic_omission_dispositions = @(@{technology_id='requested-noncore-research';disposition='removed';consequence='reduced-policy-no-preservation'})
  $receipt.classic_upgrade_evaluator_snapshots = @($row[0].snapshots)
  $null = $receipt.Remove('full_state_evaluator_snapshots')
  $classicPath = Join-Path (Split-Path -Parent $row[0].receipt.path) 'classic-omission-rejected.json'
  $receipt | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $classicPath -Encoding utf8NoBOM
  $classicRow = $row[0] | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100
  $classicRow.receipt = @{path=$classicPath;sha256=(Get-FileHash -LiteralPath $classicPath -Algorithm SHA256).Hash}
  $rejected = $false
  try { $null = Assert-MIR423NativeUpgradeProof -Row $classicRow -Package (@($PackageAssets | Where-Object { [string]$_.target -ceq 'f200' })[0]) -CandidateSourceVersion $CandidateSourceVersion }
  catch { $rejected = $_.Exception.Message -ceq ('[mir' + $CandidateSourceVersion.Replace('.','') + '-upgrade-classic-reduced-policy-not-release-preservation]') }
  if (-not $rejected) { throw 'release controls accepted a Classic omission receipt as preservation evidence' }
  return [pscustomobject]@{path=$full.path;checks=([int]$full.checks + 1);native_runs=0}
}

function Invoke-MIR431ReleaseUpgradeControls {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$PackageAssets)
  return Invoke-MIR430ReleaseUpgradeControls -Root $Root -PackageAssets $PackageAssets -CandidateSourceVersion '4.3.1'
}

function Invoke-MIR442ReleaseUpgradeControls {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$PackageAssets)
  $controls = Invoke-MIR430ReleaseUpgradeControls -Root $Root -PackageAssets $PackageAssets -CandidateSourceVersion '4.4.2'
  $f016 = Invoke-MIR442F016RestorationControls -Root (Join-Path $Root 'f016-prerequisite-restorations')
  return [pscustomobject]@{path=$controls.path;checks=([int]$controls.checks + [int]$f016.checks);native_runs=0}
}

function Invoke-MIR440ReleaseUpgradeControls {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$PackageAssets)
  return Invoke-MIR430ReleaseUpgradeControls -Root $Root -PackageAssets $PackageAssets -CandidateSourceVersion '4.4.0'
}

function Invoke-MIR430ClassicCharacterizationControls {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$PackageAssets)

  # Host-only structural controls for the explicit reduced Classic policy. The
  # older full-oracle factory remains above for the opt-in Full compiler; this
  # evidence must never present a catalogue-reduction result as full state
  # preservation.
  [IO.Directory]::CreateDirectory($Root)|Out-Null
  function Write-MIR430ClassicControlJson($Path,$Value){
    $Value|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $Path -Encoding utf8
    [ordered]@{path=$Path;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
  }
  function Copy-MIR430ClassicControlValue($Value){$Value|ConvertTo-Json -Depth 100|ConvertFrom-Json -AsHashtable -Depth 100}
  function New-MIR430ClassicTechnology([string]$Name,[int]$UnitCount,[object[]]$Effects,[object[]]$Ingredients){
    [ordered]@{name=$Name;level=3;researched=$false;enabled=$true;unit_count=$UnitCount;unit_energy=60;unit_ingredients=$Ingredients;prerequisites=@('utility-science-pack');effects=$Effects;hidden=$false;max_level='infinite'}
  }
  function New-MIR430ClassicSnapshot($Stage,$From,$To){
    $source=$Stage-ceq'source'
    $ingredient=if($source){@(@{name='automation-science-pack';amount=1})}else{@(@{name='automation-science-pack';amount=2})}
    $craftCount=if($source){100}else{200}
    $direct=@(
      (New-MIR430ClassicTechnology 'recipe-prod-research_inventory_capacity-1' 100 @(@{type='character-inventory-slots-bonus';modifier=1},@{type='character-logistic-trash-slots';modifier=1}) @(@{name='automation-science-pack';amount=1})),
      (New-MIR430ClassicTechnology 'recipe-prod-research_character_crafting_speed-1' $craftCount @(@{type='character-crafting-speed';modifier=0.05}) $ingredient),
      (New-MIR430ClassicTechnology 'recipe-prod-research_character_mining_speed-1' 100 @(@{type='character-mining-speed';modifier=0.05}) @(@{name='automation-science-pack';amount=1})),
      (New-MIR430ClassicTechnology 'recipe-prod-research_character_reach-1' 100 @(@{type='character-reach-distance';modifier=10},@{type='character-build-distance';modifier=10},@{type='character-resource-reach-distance';modifier=10},@{type='character-item-drop-distance';modifier=10}) @(@{name='automation-science-pack';amount=1})),
      (New-MIR430ClassicTechnology 'recipe-prod-research_character_walking_speed-1' 100 @(@{type='character-running-speed';modifier=0.05}) @(@{name='automation-science-pack';amount=1}))
    )
    $ids=@($direct|ForEach-Object {[string]$_.name})
    $prefix=@($direct)
    if($source){$prefix+=@(New-MIR430ClassicTechnology 'recipe-prod-research_iron-1' 100 @(@{type='character-mining-speed';modifier=0.01}) @(@{name='automation-science-pack';amount=1}))}
    $native=@(
      (New-MIR430ClassicTechnology 'braking-force-1' 100 @(@{type='train-braking-force-bonus';modifier=0.1}) @(@{name='automation-science-pack';amount=1})),
      (New-MIR430ClassicTechnology 'research-speed-1' 100 @(@{type='laboratory-speed';modifier=0.1}) @(@{name='automation-science-pack';amount=1})),
      (New-MIR430ClassicTechnology 'worker-robots-storage-1' 100 @(@{type='worker-robot-storage';modifier=1}) @(@{name='automation-science-pack';amount=1})),
      (New-MIR430ClassicTechnology 'inserter-capacity-bonus-1' 100 @(@{type='bulk-inserter-capacity-bonus';modifier=1}) @(@{name='automation-science-pack';amount=1})),
      (New-MIR430ClassicTechnology 'weapon-shooting-speed-1' 100 @(@{type='gun-speed';modifier=0.1;ammo_category='bullet'}) @(@{name='automation-science-pack';amount=1})),
      (New-MIR430ClassicTechnology 'laser-shooting-speed-1' 100 @(@{type='gun-speed';modifier=0.1;ammo_category='laser'}) @(@{name='automation-science-pack';amount=1}))
    )
    $core=Copy-MIR430ClassicControlValue $direct[1]
    $core.current_research=$core.name;$core.research_progress=if($source){0.42}else{0.21};$core.queue=@($core.name,'recipe-prod-research_inventory_capacity-1')
    $core.force_modifier=0.10
    [ordered]@{
      schema=1;kind='MIR430ClassicUpgradeSnapshotV1';stage=$Stage;from_version=$From;to_version=$To
      compiler_profile=if($source){$false}else{'classic'};full_catalog_status=if($source){'source-full'}else{'not-evaluated'}
      base=@{name='mining-productivity-4';level=4;researched=$true;enabled=$true;unit_count=100;unit_energy=30;unit_ingredients=@(@{name='automation-science-pack';amount=1});prerequisites=@();effects=@(@{type='mining-drill-productivity-bonus';modifier=0.02});hidden=$false;max_level='infinite';force_modifier=0.08}
      retained_core=$core
      omitted=@{technology_id='recipe-prod-research_iron-1';source_present=$true;candidate_present=$source;consequence=if($source){'not-yet-applied'}else{'removed-reduced-policy-no-preservation'}}
      base_force_effects=@{mining_drill_productivity_bonus=0.08}
      current_research='recipe-prod-research_character_crafting_speed-1';research_progress=if($source){0.42}else{0.21};research_queue=@('recipe-prod-research_character_crafting_speed-1','recipe-prod-research_inventory_capacity-1')
      declared_direct_ids=$ids;declared_direct_technologies=$direct;declared_direct_force_effects=@{character_inventory_slots_bonus=1;character_trash_slot_count=1;manual_crafting_speed_modifier=0.10;manual_mining_speed_modifier=0.05;character_reach_distance_bonus=10;character_build_distance_bonus=10;character_resource_reach_distance_bonus=10;character_item_drop_distance_bonus=10;character_running_speed_modifier=0.05}
      mir_prefix_technologies=$prefix;native_technologies=$native
      native_force_effects=@{train_braking_force_bonus=0.1;laboratory_speed_modifier=0.1;worker_robots_storage_bonus=1;inserter_stack_size_bonus=1}
      native_gun_speed_modifiers=@{bullet=0.1;laser=0.1};known_omitted_id='recipe-prod-research_iron-1'
    }
  }
  $script:mir430ClassicControlChecks=0
  $rows=@()
  foreach($package in $PackageAssets){
    foreach($patch in @(0,1,2)){
      $sourceVersion='4.2.'+$patch;$directory=Join-Path $Root ($package.target+'-'+$patch);[IO.Directory]::CreateDirectory($directory)|Out-Null
      $predecessor=Get-MIR423PublishedUpgradePredecessor -Target $package.target -PredecessorSourceVersion $sourceVersion -CandidateSourceVersion '4.3.0'
      $from='4.2.'+$package.target.Substring(1)+$patch.ToString('00');$to=[string]$package.distribution_version
      $classic=$package.target-cin@('f210','f200','f110','f100')
      if($classic){
        $snapshots=@();$snapshotValues=@{}
        foreach($stage in @('source','upgrade','reload')){
          $snapshot=New-MIR430ClassicSnapshot $stage $from $to;$snapshotValues[$stage]=$snapshot
          $reference=Write-MIR430ClassicControlJson (Join-Path $directory ($stage+'.json')) $snapshot
          $snapshots+=[ordered]@{stage=$stage;path=$reference.path;sha256=$reference.sha256}
        }
        $catalog=Get-MIR430ClassicSealCatalogDisposition -Source $snapshotValues.source -Candidate $snapshotValues.reload
        $receipt=[ordered]@{
          schema=3;status='passed';factorio_processes=4;from=@{version=$from;sha256=$predecessor.target.sha256};to=@{version=$to;sha256=$package.sha256}
          published_maintenance_predecessor=@{source_tag=$predecessor.source_tag;manifest=@{sha256=$predecessor.manifest.sha256}}
          assertions=@('exact-candidate-normal-mod-directory-load','upgraded-save-reload-passed','upgraded-save-second-reload-passed','classic-profile-setting-verified','classic-base-research-integrity-retained','classic-retained-core-level-effect-queue-and-completed-work-retained','classic-omitted-mir-research-disposition-recorded','classic-reduced-policy-oracle-executed-upgrade-and-two-reloads')
          upgrade_policy=@{schema=1;kind='MIR430ClassicReducedUpgradePolicyV1';compiler_profile='classic';full_catalog_status='not-evaluated';omitted_research_not_preserved=$true;fixture_scope='known-classic-core-and-omission-v1';tested_catalog_scope='candidate-bound-active-base-default-classic-mir-prefix-catalog'}
          classic_profile_setting=@{name='mir-compiler-profile';value='classic';source='candidate-runtime-snapshot'}
          classic_catalog_scope=$catalog.scope;classic_mir_prefix_dispositions=@($catalog.dispositions)
          classic_omission_dispositions=@(@{technology_id='recipe-prod-research_character_crafting_speed-1';disposition='retained-existing-investment-definition-changed';consequence='classic-declared-core-definition'},@{technology_id='recipe-prod-research_iron-1';disposition='removed';consequence='removed-reduced-policy-no-preservation'})
          resource_ledgers=@();library_activation=@{status='restored-direct-library-controls';dependency_payload_bytes_copied=0;archive_links_created=0;archive_extractions=0};classic_upgrade_evaluator_snapshots=$snapshots
        }
      }else{
        # Historical targets retain the pre-existing exact Full policy.  This
        # mixed matrix catches a Classic reader from accidentally relaxing a
        # legacy target merely because the release source is 4.3.0.
        $state=@{forces=@{player=@{technologies=@{a=@{researched=$true;level=2};b=@{researched=$false;level=1};c=@{researched=$false;level=1}};bonuses=@{plate=0.1};settings=@{kept=$true};effects=@{speed=0.1};ammo=@{bullet=0.1};gun_speed=@{};turret=@{};queue=@('b');current_research='b';research_progress=0.42}};from_version=$from;to_version=$to}
        foreach($technology in $state.forces.player.technologies.Values){$technology.prototype=@{effects=@(@{type='mining-drill-productivity-bonus';modifier=0.02});ingredients=@(@{name='automation-science-pack';amount=1});prerequisites=@();research_unit_count=100;research_unit_energy=30;max_level=10}}
        $snapshots=@();foreach($stage in @('source','upgrade','reload')){
          $snapshot=Copy-MIR430ClassicControlValue $state;$snapshot.stage=$stage
          $reference=Write-MIR430ClassicControlJson (Join-Path $directory ($stage+'.json')) $snapshot
          $snapshots+=[ordered]@{stage=$stage;path=$reference.path;sha256=$reference.sha256}
        }
        $receipt=[ordered]@{
          schema=3;status='passed';factorio_processes=4;from=@{version=$from;sha256=$predecessor.target.sha256};to=@{version=$to;sha256=$package.sha256}
          published_maintenance_predecessor=@{source_tag=$predecessor.source_tag;manifest=@{sha256=$predecessor.manifest.sha256}}
          assertions=@('exact-candidate-normal-mod-directory-load','upgraded-save-reload-passed','upgraded-save-second-reload-passed','all-existing-technology-state-and-definitions-retained','all-exposed-earned-effects-retained','all-supported-research-queue-retained','full-state-oracle-executed-upgrade-and-two-reloads')
          resource_ledgers=@();library_activation=@{status='restored-direct-library-controls';dependency_payload_bytes_copied=0;archive_links_created=0;archive_extractions=0};full_state_evaluator_snapshots=$snapshots
        }
      }
      foreach($stage in @('create','load','reload','second_reload')){
        $log=Join-Path $directory ($stage+'.txt');$message=if($classic){if($stage-ceq'create'){'classic reduced-policy source proof complete'}elseif($stage-ceq'load'){'classic reduced-policy upgrade proof complete'}else{'classic reduced-policy reload proof complete'}}else{'complete research state retained technologies=3 recipes=1'}
        [IO.File]::WriteAllText($log,'[mir-fixture] '+$message,[Text.UTF8Encoding]::new($false));$receipt[$stage+'_log']=Split-Path $log -Leaf;$receipt[$stage+'_log_sha256']=(Get-FileHash $log -Algorithm SHA256).Hash
        $ledger=Join-Path $directory ($stage+'.resources.jsonl');[IO.File]::WriteAllText($ledger,'{"synthetic_host_control":true}',[Text.UTF8Encoding]::new($false));$receipt.resource_ledgers+=@{filename=(Split-Path $ledger -Leaf);sha256=(Get-FileHash $ledger -Algorithm SHA256).Hash;exit_code=0;completion_predicate_observed=$false}
      }
      $receiptReference=Write-MIR430ClassicControlJson (Join-Path $directory 'receipt.json') $receipt
      $rows+=[pscustomobject]@{target=$package.target;predecessor_source_version=$sourceVersion;receipt=$receiptReference;snapshots=$snapshots}
    }
  }
  # Classic is intentionally characterized through its own bounded validator.
  # Do not feed these omission records into the release-evidence reader: that
  # reader is reserved for Full preservation proofs.
  $classicRows = @($rows | Where-Object {
    $record = Get-Content -LiteralPath $_.receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $record.Contains('upgrade_policy') -and [string]$record.upgrade_policy.kind -ceq 'MIR430ClassicReducedUpgradePolicyV1'
  })
  if ($classicRows.Count -ne 12) { throw '430 Classic characterization did not build the four modern predecessor rows' }
  foreach ($row in $classicRows) {
    $record = Get-Content -LiteralPath $row.receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $states = @{}
    foreach ($snapshot in @($row.snapshots)) {
      $snapshotRecord = (Read-MIR423UpgradeProofReference ([pscustomobject]@{path=$snapshot.path;sha256=$snapshot.sha256})).record
      $states[[string]$snapshot.stage] = $snapshotRecord
    }
    if ((@($states.Keys | Sort-Object) -join '|') -cne 'reload|source|upgrade') { throw '430 Classic characterization snapshot set changed' }
    Assert-MIR430ClassicNativeUpgradeProof -Record $record -States $states
  }
  return [pscustomobject]@{checks=$classicRows.Count;native_runs=0;release_evidence=$false}
}
