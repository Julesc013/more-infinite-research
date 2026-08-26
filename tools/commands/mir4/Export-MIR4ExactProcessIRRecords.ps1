param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot='build/mir4/t12-exact-processir',
  [string]$ReferenceRoot='sdk/preview/mir4/reference/t12',
  [string]$F210Engine='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$F200Engine='D:\Programs\Factorio\2.0\bin\x64\factorio.exe',
  [string[]]$ArchiveSearchRoots=@('C:\Projects\Factorio\testmods\2.1','C:\Projects\Factorio\testmods\2.0','C:\Downloads'),
  [string[]]$CaptureId=@(),
  [ValidateRange(1,4)][int]$Repetitions=2,
  [switch]$PublishReference,
  [switch]$Check
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $repo 'tools/lib/mir4/ExactProcessIR.ps1')

function Resolve-T12Output([string]$Relative,[string]$AllowedRoot){
  $full=[IO.Path]::GetFullPath((Join-Path $repo $Relative));$allowed=[IO.Path]::GetFullPath((Join-Path $repo $AllowedRoot)).TrimEnd('\')+'\'
  if(-not($full+'\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw "[mir4-t12-output-boundary] $full"}
  $full
}
function Write-T12Json([string]$Path,$Value){
  $parent=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
  [IO.File]::WriteAllText($Path,(ConvertTo-MIR4CanonicalJsonV1 $Value)+"`n",[Text.UTF8Encoding]::new($false))
}
function Test-T12Reference([string]$Root){
  $manifestPath=Join-Path $Root 'MIR4_T12_EXACT_PROCESSIR_MANIFEST.json'
  if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw '[mir4-t12-reference-manifest-missing]'}
  $manifest=Get-Content -Raw -LiteralPath $manifestPath|ConvertFrom-Json -Depth 100
  if([int]$manifest.schema-ne 1-or[string]$manifest.kind-cne'MIR4T12ExactProcessIRManifestV1'-or-not$manifest.complete){throw '[mir4-t12-reference-manifest]'}
  foreach($file in @($manifest.files)){
    $path=Join-Path $Root ([string]$file.path)
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or('sha256:'+(Get-MIR4T12FileSha256 $path))-cne[string]$file.sha256){throw "[mir4-t12-reference-file] $($file.path)"}
  }
  foreach($lockFile in Get-ChildItem -LiteralPath (Join-Path $Root 'locks') -File -Filter '*.json'){$lock=Get-Content -Raw -LiteralPath $lockFile.FullName|ConvertFrom-Json -Depth 100;Test-MIR4EnvironmentLockV1 $lock|Out-Null}
  foreach($snapshotFile in Get-ChildItem -LiteralPath (Join-Path $Root 'snapshots') -File -Filter '*.json'){$snapshot=Get-Content -Raw -LiteralPath $snapshotFile.FullName|ConvertFrom-Json -Depth 100;if([string]$snapshot.digest-cne(Get-MIR4T12RecordDigest $snapshot)-or-not$snapshot.observer.deterministic-or$snapshot.package_visible-or$snapshot.authoritative){throw "[mir4-t12-reference-snapshot] $($snapshot.capture_id)"}}
  $receipt=Get-Content -Raw -LiteralPath (Join-Path $Root 'MIR4_T12_RECEIPT.json')|ConvertFrom-Json -Depth 100
  if([string]$receipt.digest-cne(Get-MIR4T12RecordDigest -Value $receipt -Domain 'mir4:t12-receipt:1')-or[string]$receipt.status-notin@('completed-machine-work','completed-machine-work-with-custody-blocker')-or-not$receipt.package_source_unchanged){throw '[mir4-t12-reference-receipt]'}
  [pscustomobject][ordered]@{status='passed';capture_count=[int]$receipt.capture_count;reference_root=$Root;package_visible=$false}
}

$output=Resolve-T12Output -Relative $OutputRoot -AllowedRoot 'build/mir4'
$reference=Resolve-T12Output -Relative $ReferenceRoot -AllowedRoot 'sdk/preview/mir4/reference'
if($Check){Test-T12Reference -Root $reference|ConvertTo-Json -Depth 10;exit 0}

$trackedDirty=@(&git -C $repo status --porcelain --untracked-files=no)
if($trackedDirty.Count){throw '[mir4-t12-source-dirty] Commit tracked implementation before exact engine capture.'}
$authority=Get-MIR4T12Authority -RepoRoot $repo
$selected=@($authority.captures)
if($CaptureId.Count){$wanted=@{};foreach($id in $CaptureId){$wanted[$id]=$true};$selected=@($selected|Where-Object{$wanted.ContainsKey([string]$_.id)});if($selected.Count-ne$wanted.Count){throw '[mir4-t12-capture-selection]'}}
if(Test-Path -LiteralPath $output){Remove-Item -LiteralPath $output -Recurse -Force}
New-Item -ItemType Directory -Path $output -Force|Out-Null
$source=[ordered]@{commit=(&git -C $repo rev-parse HEAD).Trim();tree=(&git -C $repo rev-parse 'HEAD^{tree}').Trim();work_package='T12'}
$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$sets=@();$blockers=@()
foreach($capture in $selected){
  Write-Host "[mir4-t12] capture $($capture.id) repetitions=$Repetitions"
  $engine=if([string]$capture.target-ceq'f210'){$F210Engine}else{$F200Engine}
  try{$set=Invoke-MIR4T12ExactCapture -RepoRoot $repo -Authority $authority -Capture $capture -EnginePath $engine -OutputRoot $output -ArchiveSearchRoots $ArchiveSearchRoots -SourceIdentity $source -Repetitions $Repetitions}
  catch{
    if(-not$_.Exception.Message.StartsWith('[mir4-t12-exact-archive-missing]')){throw}
    $blocker=[pscustomobject][ordered]@{schema=1;kind='MIR4T12CustodyBlockerV1';work_package='T12';capture_id=[string]$capture.id;target=[string]$capture.target;scenario_id=[string]$capture.scenario_id;status='blocked-exact-archive-custody';reason=$_.Exception.Message;evidence_ref=[string]$capture.evidence;lock_ref=[string]$capture.lock;fabricated_substitute=$false;package_visible=$false;digest=''}
    Add-MIR4T12RecordDigest -Value $blocker -Domain 'mir4:t12-custody-blocker:1'|Out-Null
    $blockers+=$blocker;Write-T12Json -Path (Join-Path $output "blockers/$($capture.id).json") -Value $blocker
    Write-Warning "T12 capture $($capture.id) retained an explicit custody blocker: $($_.Exception.Message)"
    continue
  }
  $sets+=$set
  Write-T12Json -Path (Join-Path $output "snapshots/$($capture.id).json") -Value $set.snapshot
  Write-T12Json -Path (Join-Path $output "locks/$($capture.id).json") -Value $set.environment_lock
}
$snapshots=@($sets.snapshot)
$byId=@{};foreach($snapshot in $snapshots){$byId[[string]$snapshot.capture_id]=$snapshot}
$comparisons=@()
foreach($snapshot in $snapshots){
  $baseId=if([string]$snapshot.target-ceq'f210'){'f210-base'}else{'f200-base'}
  if([string]$snapshot.capture_id-cne$baseId-and$byId.ContainsKey($baseId)){
    $comparison=New-MIR4T12ComparisonV1 -A $byId[$baseId] -B $snapshot
    $comparisons+=$comparison
    Write-T12Json -Path (Join-Path $output "comparisons/$baseId--$($snapshot.capture_id).json") -Value $comparison
  }
}
$w06=New-MIR4W06Records -RepoRoot $repo -SourceIdentity $source
$effects=[pscustomobject][ordered]@{schema=1;kind='MIR4T12ExactEffectObservationV1';source_identity=$source;effect_channel_registry_digest=[string]$w06.effects.digest;captures=@($snapshots|Sort-Object capture_id|ForEach-Object{[ordered]@{capture_id=$_.capture_id;environment_lock_digest=$_.environment_lock_digest;snapshot_digest=$_.digest;classification_counts=$_.classification_counts}});copied_not_reclassified=$true;automatic_mutation=$false;package_visible=$false;digest=''}
Add-MIR4T12RecordDigest -Value $effects -Domain 'mir4:t12-effects:1'|Out-Null
$opportunities=[pscustomobject][ordered]@{schema=1;kind='MIR4T12ExactOpportunityCatalogueV1';source_identity=$source;constructors=@($w06.synthesis.constructors);modes=@($w06.synthesis.modes.id);captures=@($snapshots|Sort-Object capture_id|ForEach-Object{[ordered]@{capture_id=$_.capture_id;overall_classification=$_.process_ir.overall_classification;terminal_disposition=$_.process_ir.terminal_disposition;snapshot_digest=$_.digest}});diagnose_or_conservative_preview_only=$true;automatic_synthesis_authorized=$false;planner_admission=$false;package_visible=$false;digest=''}
Add-MIR4T12RecordDigest -Value $opportunities -Domain 'mir4:t12-opportunities:1'|Out-Null
Write-T12Json -Path (Join-Path $output 'MIR4_T12_EXACT_EFFECTS.json') -Value $effects
Write-T12Json -Path (Join-Path $output 'MIR4_T12_OPPORTUNITIES.json') -Value $opportunities
$packageAfter=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$receipt=[pscustomobject][ordered]@{
  schema=1;kind='MIR4T12ReceiptV1';work_package='T12';status=$(if($blockers.Count){'completed-machine-work-with-custody-blocker'}else{'completed-machine-work'});source_identity=$source
  capture_count=$snapshots.Count;required_capture_count=$authority.captures.Count;targets=@($snapshots.target|Sort-Object -Unique -CaseSensitive);capture_ids=@($snapshots.capture_id|Sort-Object -CaseSensitive)
  blocker_count=$blockers.Count;blockers=@($blockers|ForEach-Object{[ordered]@{capture_id=$_.capture_id;status=$_.status;digest=$_.digest}})
  repetitions=$Repetitions;all_deterministic=(@($sets|Where-Object{-not$_.deterministic}).Count-eq 0);comparison_count=$comparisons.Count
  exact_target_processir_status=$(if(($snapshots.Count+$blockers.Count)-eq$authority.captures.Count-and$Repetitions-ge[int]$authority.required_repetitions){$(if($blockers.Count){'CAPTURED-EXACT-F210-F200-PROCESSIR-PREVIEW-WITH-DECLARED-CUSTODY-BLOCKER'}else{'CAPTURED-EXACT-F210-F200-PROCESSIR-PREVIEW'})}else{'PARTIAL-LOCAL-T12-CAPTURE'})
  bilateral_synthetic_gate_preserved=[bool]$w06.parity.bilateral_gate.passed;terminal_fact_authority_preserved=$true;explicit_unavailable_not_zero=$true
  package_source_before=$packageBefore;package_source_after=$packageAfter;package_source_unchanged=($packageBefore-ceq$packageAfter)
  player_mutation_authorized=$false;prototype_write_authorized=$false;planner_or_emitter_admission_authorized=$false;public_support_authorized=$false;release_admission_authorized=$false;package_visible=$false;digest=''
}
Add-MIR4T12RecordDigest -Value $receipt -Domain 'mir4:t12-receipt:1'|Out-Null
if(-not$receipt.package_source_unchanged-or-not$receipt.all_deterministic){throw '[mir4-t12-exit-gate]'}
Write-T12Json -Path (Join-Path $output 'MIR4_T12_RECEIPT.json') -Value $receipt

$files=@(Get-ChildItem -LiteralPath $output -Recurse -File -Filter '*.json'|Where-Object{$_.Name-cne'MIR4_T12_EXACT_PROCESSIR_MANIFEST.json'}|Sort-Object FullName|ForEach-Object{[ordered]@{path=[IO.Path]::GetRelativePath($output,$_.FullName).Replace('\','/');bytes=$_.Length;sha256='sha256:'+(Get-MIR4T12FileSha256 $_.FullName)}})
$manifest=[pscustomobject][ordered]@{schema=1;kind='MIR4T12ExactProcessIRManifestV1';source_identity=$source;capture_count=$snapshots.Count;blocker_count=$blockers.Count;comparison_count=$comparisons.Count;files=$files;complete=(($snapshots.Count+$blockers.Count)-eq$authority.captures.Count);package_visible=$false;digest=''}
Add-MIR4T12RecordDigest -Value $manifest -Domain 'mir4:t12-manifest:1'|Out-Null
Write-T12Json -Path (Join-Path $output 'MIR4_T12_EXACT_PROCESSIR_MANIFEST.json') -Value $manifest

if($PublishReference){
  if(Test-Path -LiteralPath $reference){Remove-Item -LiteralPath $reference -Recurse -Force}
  New-Item -ItemType Directory -Path $reference -Force|Out-Null
  foreach($file in Get-ChildItem -LiteralPath $output -Recurse -File -Filter '*.json'){$relative=[IO.Path]::GetRelativePath($output,$file.FullName);$destination=Join-Path $reference $relative;$parent=Split-Path -Parent $destination;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};Copy-Item -LiteralPath $file.FullName -Destination $destination -Force}
}
[pscustomobject][ordered]@{status='passed';source_identity=$source;output=$output;reference=$(if($PublishReference){$reference}else{$null});capture_count=$snapshots.Count;comparison_count=$comparisons.Count;receipt_digest=$receipt.digest;package_source_unchanged=$receipt.package_source_unchanged;package_visible=$false;publication_authorized=$false}|ConvertTo-Json -Depth 20
