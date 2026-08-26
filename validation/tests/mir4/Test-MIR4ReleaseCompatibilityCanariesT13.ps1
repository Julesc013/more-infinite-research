param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/CompatibilityCanary.ps1')

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
$authority=Get-MIR4T13Authority -RepoRoot $RepoRoot
$authorityJson=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Release-Compatibility-Canaries-T13V1.json')
if(-not($authorityJson|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-release-compatibility-canaries-t13-v1.schema.json'))){throw '[mir4-t13-authority-schema]'}
foreach($flag in @('semantic_authority','player_mutation_authorized','prototype_write_authorized','automatic_synthesis_authorized','public_support_claim_authorized','source_freeze_authorized','signing_or_sealing_authorized','promotion_authorized','publication_authorized','package_visible')){if([bool]$authority.$flag){throw "[mir4-t13-authority-firewall] $flag"}}

& (Join-Path $RepoRoot 'tools/commands/mir4/Export-MIR4CompatibilityCanaryRecords.ps1') -RepoRoot $RepoRoot -Check|Out-Null
$root=Join-Path $RepoRoot 'sdk/preview/mir4/reference/t13'
$receipt=Get-Content -Raw -LiteralPath (Join-Path $root 'MIR4_T13_RECEIPT.json')|ConvertFrom-Json -Depth 100
if(-not(($receipt|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/preview/mir4-t13-receipt-v1.schema.json'))-or
  [string]$receipt.digest-cne(Get-MIR4T12RecordDigest -Value $receipt -Domain 'mir4:t13-receipt:1')-or
  [int]$receipt.canary_count-ne 8-or[int]$receipt.capture_count-ne 11-or[int]$receipt.target_count-ne 2-or
  -not$receipt.all_clean_loads_passed-or-not$receipt.all_first_reloads_passed-or-not$receipt.all_second_reloads_passed-or-not$receipt.all_target_upgrades_passed-or-not$receipt.all_performance_within_budget-or
  -not$receipt.f200_k2so_archive_custody_complete-or-not$receipt.t12_historical_blocker_superseded-or-not$receipt.package_source_unchanged-or$receipt.public_support_claim_authorized-or$receipt.source_freeze_authorized-or$receipt.release_transition_authorized-or$receipt.package_visible){throw '[mir4-t13-receipt]'}

$expectedCanaries=@('aai-selected','base-and-official-closure','bz-selected','corrundum','cubium','k2-k2so-f200','k2-k2so-f210','recycler-progression')
$canaryFiles=@(Get-ChildItem -LiteralPath (Join-Path $root 'canaries') -File -Filter '*.json'|Sort-Object BaseName)
if(($canaryFiles.BaseName-join'|')-cne($expectedCanaries-join'|')){throw '[mir4-t13-canary-set]'}
$seenCaptures=@()
foreach($file in $canaryFiles){
  $record=Get-Content -Raw -LiteralPath $file.FullName|ConvertFrom-Json -Depth 100
  if(-not(($record|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/preview/mir4-release-compatibility-canary-v1.schema.json'))-or
    [string]$record.digest-cne(Get-MIR4T12RecordDigest -Value $record -Domain 'mir4:release-canary:1')-or
    [string]$record.claim_level-cne'exact-locked-release-canary-input'-or[string]$record.target_disposition-cne'qualified-exact-release-canary'-or
    @($record.limitations).Count-lt 1-or@($record.expiry_triggers).Count-lt 5-or-not$record.exact_environment_only-or-not$record.release_qualification_input-or
    $record.public_support_claim_authorized-or$record.release_transition_authorized-or$record.package_visible){throw "[mir4-t13-canary] $($file.Name)"}
  if(([string]$record.support_statement)-match'(?i)all modpacks|blanket support|full[- ]pack support'){throw "[mir4-t13-blanket-claim] $($file.Name)"}
  foreach($upgrade in @($record.target_upgrades)){if([string]$upgrade.status-cne'passed'-or-not$upgrade.first_reload_asserted-or-not$upgrade.second_reload_asserted-or@($upgrade.archetypes).Count-lt 1){throw "[mir4-t13-upgrade-binding] $($file.Name)"}}
  $seenCaptures+=@($record.capture_ids)
}
if(@($seenCaptures|Sort-Object -Unique -CaseSensitive).Count-ne 11){throw '[mir4-t13-canary-capture-coverage]'}

$captureFiles=@(Get-ChildItem -LiteralPath (Join-Path $root 'captures') -File -Filter '*.json')
if($captureFiles.Count-ne 11){throw '[mir4-t13-capture-count]'}
foreach($file in $captureFiles){
  $record=Get-Content -Raw -LiteralPath $file.FullName|ConvertFrom-Json -Depth 100
  if(-not(($record|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/preview/mir4-t13-exact-capture-canary-v1.schema.json'))-or
    [string]$record.digest-cne(Get-MIR4T12RecordDigest -Value $record -Domain 'mir4:t13-capture:1')-or
    @($record.lifecycle.reloads).Count-ne 2-or-not$record.lifecycle.first_reload_passed-or-not$record.lifecycle.second_reload_passed-or-not$record.lifecycle.save_byte_identical-or
    -not$record.performance.within_budget-or[int]$record.exact_fact_capture.process_count-lt 1-or-not$record.exact_fact_capture.terminal_fact_authority_preserved-or
    $record.support_assessment.automatic_synthesis_authorized-or$record.support_assessment.public_claim_authorized-or$record.raw_logs_published-or$record.private_paths_published-or$record.package_visible){throw "[mir4-t13-capture] $($file.Name)"}
}

$lock=Get-Content -Raw -LiteralPath (Join-Path $root 'supplements/f200-k2so.lock.json')|ConvertFrom-Json -Depth 100
$snapshot=Get-Content -Raw -LiteralPath (Join-Path $root 'supplements/f200-k2so.snapshot.json')|ConvertFrom-Json -Depth 100
Test-MIR4EnvironmentLockV1 -Lock $lock|Out-Null
$requiredArchives=@(
  @{name='ChangeInserterDropLane';version='1.2.0';sha='sha256:8773256dfddbc2c504aa98e6c1323fbbcee792a4240594fccdb5ba2c07983c74'},
  @{name='k2so-assets';version='1.0.5';sha='sha256:dda5fdf18a3d761c1f5b4f3de0743afcd1332342c356a8ac8894e6521b4d29c1'},
  @{name='Krastorio2Assets';version='2.0.5';sha='sha256:e8d9079bb5f99623ea81a425c5441b4f2fe21807766f893c9a4e90170110e92b'},
  @{name='Krastorio2MenuSimulations';version='2.0.2';sha='sha256:0ed38e61ee45dcbe6d94159f25c38f073a3ea47f0322d02b062036044ea95f7b'}
)
foreach($required in $requiredArchives){$row=@($lock.mods|Where-Object{[string]$_.name-ceq$required.name});if($row.Count-ne 1-or[string]$row[0].version-cne$required.version-or[string]$row[0].sha256-cne$required.sha){throw "[mir4-t13-f200-k2so-archive] $($required.name)"}}
if([string]$snapshot.environment_lock_digest-cne[string]$lock.digest-or[string]$snapshot.digest-cne(Get-MIR4T12RecordDigest $snapshot)){throw '[mir4-t13-f200-k2so-snapshot]'}

$badLock=($lock|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100);$badLock.target='f210'
$failedClosed=$false
try{New-MIR4T13CaptureRecord -Authority $authority -Snapshot $snapshot -Lock $badLock -RunRoot 'does-not-matter' -EnginePath 'does-not-matter'|Out-Null}catch{$failedClosed=$_.Exception.Message.StartsWith('[mir4-t13-capture-binding]')}
if(-not$failedClosed){throw '[mir4-t13-mismatched-lock-fail-closed]'}
if((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot)-cne$packageBefore-or$packageBefore-cne'9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'){throw '[mir4-t13-package-source-mutation]'}
Write-Host '[ok] MIR 4 T13 exact release canaries, lifecycle reloads, target upgrades, expiry, F200 K2SO custody closure, and authority firewall passed.'
