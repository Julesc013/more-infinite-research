Set-StrictMode -Version Latest

function New-MIR421ReleaseAssetCustodyFixture {
  param([Parameter(Mandatory)][string]$RepoRoot,[ValidateSet('4.2.1','4.2.2','4.2.3','4.3.0')][string]$CandidateSourceVersion='4.2.1')
  # Structural fixtures only: IDs and paths are synthetic. No network, native
  # campaign, signature or actual release qualification is claimed here.
  $contract=Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion $CandidateSourceVersion
  $pinPath=switch($CandidateSourceVersion){
    '4.2.1' {'fixtures/release-inputs/mir421-published-420-manifest.json'}
    '4.2.2' {'fixtures/release-inputs/mir422-published-421-manifest.json'}
    '4.2.3' {'fixtures/release-inputs/mir423-published-422-manifest.json'}
    '4.3.0' {'fixtures/release-inputs/mir423-published-422-manifest.json'}
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

function Invoke-MIR430ReleaseUpgradeControls {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$PackageAssets)

  # Host-only structural controls. The release reader still binds all 27
  # predecessor receipts, but a 4.3.0 destination must retain exact research
  # definitions for every supported 4.2 predecessor, not just 4.2.2.
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
    if (-not $rejected) { throw "430 upgrade controls accepted $Description" }
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
  $rows = @()
  foreach ($package in $PackageAssets) {
    foreach ($patch in @(0,1,2)) {
      $sourceVersion = '4.2.' + $patch
      $directory = Join-Path $Root ($package.target + '-' + $patch)
      [IO.Directory]::CreateDirectory($directory) | Out-Null
      $predecessor = Get-MIR423PublishedUpgradePredecessor -Target $package.target -PredecessorSourceVersion $sourceVersion -CandidateSourceVersion '4.3.0'
      $from = '4.2.' + $package.target.Substring(1) + $patch.ToString('00')
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
  $bundle = @{schema=1;kind='MIR430MaintenanceUpgradeEvidenceV1';source_version='4.3.0';rows=$rows}
  $path = Join-Path $Root 'evidence.json'
  $null = Write-MIR430UpgradeJson $path $bundle
  $null = Assert-MIR423MaintenanceUpgradeEvidence -Path $path -PackageAssets $PackageAssets -CandidateSourceVersion '4.3.0'
  $script:mir430UpgradeControlChecks++

  $missing = Copy-MIR430UpgradeValue $bundle
  $missing.rows = @($missing.rows | Select-Object -First 26)
  $missingPath = Join-Path $Root 'missing.json'
  $null = Write-MIR430UpgradeJson $missingPath $missing
  Assert-MIR430Rejected { Assert-MIR423MaintenanceUpgradeEvidence -Path $missingPath -PackageAssets $PackageAssets -CandidateSourceVersion '4.3.0' } '[mir430-upgrade-matrix-cardinality]' 'a missing predecessor row'
  $duplicate = Copy-MIR430UpgradeValue $bundle
  $duplicate.rows[2] = $duplicate.rows[0]
  $duplicatePath = Join-Path $Root 'duplicate.json'
  $null = Write-MIR430UpgradeJson $duplicatePath $duplicate
  Assert-MIR430Rejected { Assert-MIR423MaintenanceUpgradeEvidence -Path $duplicatePath -PackageAssets $PackageAssets -CandidateSourceVersion '4.3.0' } '[mir430-upgrade-matrix-identity]' 'a duplicate predecessor row'

  $wrongPackage = Copy-MIR430UpgradeValue $PackageAssets[0]
  $wrongPackage.sha256 = 'A' * 64
  Assert-MIR430Rejected { Assert-MIR423NativeUpgradeProof -Row $rows[0] -Package $wrongPackage -CandidateSourceVersion '4.3.0' } '[mir430-upgrade-native-binding]' 'a wrong candidate archive'
  $wrongMinorReceipt = Get-Content -LiteralPath $rows[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
  $wrongMinorReceipt.to.version = '4.2.' + $PackageAssets[0].target.Substring(1) + '03'
  $wrongMinorRow = Copy-MIR430UpgradeValue $rows[0]
  $wrongMinorRow.receipt = Write-MIR430UpgradeJson (Join-Path (Split-Path -Parent $rows[0].receipt.path) 'wrong-destination-minor.json') $wrongMinorReceipt
  Assert-MIR430Rejected { Assert-MIR423NativeUpgradeProof -Row $wrongMinorRow -Package $PackageAssets[0] -CandidateSourceVersion '4.3.0' } '[mir430-upgrade-native-binding]' 'a 4.2 destination projection'

  $badReceipt = Get-Content -LiteralPath $rows[2].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
  $badReceipt.published_maintenance_predecessor.source_tag = 'v4.2.1'
  $publishedRow = Copy-MIR430UpgradeValue $rows[2]
  $publishedRow.receipt = Write-MIR430UpgradeJson (Join-Path (Split-Path -Parent $rows[2].receipt.path) 'wrong-published.json') $badReceipt
  Assert-MIR430Rejected { Assert-MIR423NativeUpgradeProof -Row $publishedRow -Package $PackageAssets[0] -CandidateSourceVersion '4.3.0' } '[mir430-upgrade-published-predecessor]' 'the wrong published predecessor'

  $mutations = @(
    @{stem='old-definition';stage='upgrade';code='[mir423-upgrade-research-definition]';change={$args[0].forces.player.technologies.a.prototype.effects[0].modifier=0.03}},
    @{stem='old-science';stage='upgrade';code='[mir423-upgrade-research-definition]';change={$args[0].forces.player.technologies.a.prototype.ingredients[0].name='chemical-science-pack'}},
    @{stem='old-setting';stage='upgrade';code='[mir423-upgrade-settings]';change={$args[0].forces.player.settings.kept=$false}},
    @{stem='old-source-definition';stage='source';code='[mir423-upgrade-research-definition]';change={$args[0].forces.player.technologies.a.prototype.research_unit_count=200}}
  )
  # Index 0 is the 4.2.0 predecessor. It deliberately proves the minor-crossing
  # contract does not retain 4.2.3's old "prior patch delta" allowance.
  foreach ($mutation in $mutations) {
    $changed = New-MIR430ChangedRow -Row $rows[0] -Mutation $mutation.change -Stem $mutation.stem -Stage $mutation.stage
    Assert-MIR430Rejected { Assert-MIR423NativeUpgradeProof -Row $changed -Package $PackageAssets[0] -CandidateSourceVersion '4.3.0' } $mutation.code ('a retained-state mutation: ' + $mutation.stem)
  }
  return [pscustomobject]@{path=$path;checks=$script:mir430UpgradeControlChecks;native_runs=0}
}
