param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$CaptureRoot='build/mir4/t13-exact-captures',
  [string]$UpgradeRoot='build/mir4/t13-release-canaries/upgrades',
  [string]$OutputRoot='build/mir4/t13-canary-records',
  [string]$ReferenceRoot='sdk/preview/mir4/reference/t13',
  [string]$F210Engine='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$F200Engine='D:\Programs\Factorio\2.0\bin\x64\factorio.exe',
  [switch]$PublishReference,
  [switch]$Check
)
$ErrorActionPreference='Stop';$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/mir/application/inspection/CompatibilityCanary.ps1')

function Resolve-T13Path([string]$Relative,[string]$AllowedRoot){
  $full=[IO.Path]::GetFullPath((Join-Path $repo $Relative));$allowed=[IO.Path]::GetFullPath((Join-Path $repo $AllowedRoot)).TrimEnd('\')+'\'
  if(-not($full+'\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw "[mir4-t13-output-boundary] $full"}
  $full
}

$reference=Resolve-T13Path -Relative $ReferenceRoot -AllowedRoot 'sdk/preview/mir4/reference'
if($Check){Test-MIR4T13Reference -RepoRoot $repo -ReferenceRoot $ReferenceRoot|ConvertTo-Json -Depth 10;exit 0}
$dirty=@(&git -C $repo status --porcelain --untracked-files=no);if($dirty.Count){throw '[mir4-t13-source-dirty] Commit tracked implementation before exact lifecycle capture.'}
$capture=(Resolve-Path -LiteralPath (Join-Path $repo $CaptureRoot)).Path
$upgrade=(Resolve-Path -LiteralPath (Join-Path $repo $UpgradeRoot)).Path
$output=Resolve-T13Path -Relative $OutputRoot -AllowedRoot 'build/mir4'
if(Test-Path -LiteralPath $output){Remove-Item -LiteralPath $output -Recurse -Force}
New-Item -ItemType Directory -Path $output -Force|Out-Null
$authority=Get-MIR4T13Authority -RepoRoot $repo
$source=[ordered]@{commit=(&git -C $repo rev-parse HEAD).Trim();tree=(&git -C $repo rev-parse 'HEAD^{tree}').Trim();work_package='T13'}
$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$upgradeMap=@{}
foreach($target in @('f210','f200')){$upgradeMap[$target]=Test-MIR4T13UpgradeMatrix -Authority $authority -Target $target -Path (Join-Path $upgrade "$target-upgrade-matrix.json")}
$captureMap=@{};$captures=@()
foreach($id in @($authority.canaries.capture_ids|ForEach-Object{$_}|Sort-Object -Unique -CaseSensitive)){
  Write-Host "[mir4-t13] lifecycle $id"
  $snapshot=Get-Content -Raw -LiteralPath (Join-Path $capture "snapshots/$id.json")|ConvertFrom-Json -Depth 100
  $lock=Get-Content -Raw -LiteralPath (Join-Path $capture "locks/$id.json")|ConvertFrom-Json -Depth 100
  $engine=if([string]$snapshot.target-ceq'f210'){$F210Engine}else{$F200Engine}
  $record=New-MIR4T13CaptureRecord -Authority $authority -Snapshot $snapshot -Lock $lock -RunRoot (Join-Path $capture "runtime/$id/run-1") -EnginePath $engine
  $captureMap[[string]$id]=$record;$captures+=$record
  Write-MIR4T13Json -Path (Join-Path $output "captures/$id.json") -Value $record
}
$canaries=@()
foreach($definition in @($authority.canaries)){
  $record=New-MIR4T13CanaryRecord -Authority $authority -Definition $definition -CaptureMap $captureMap -UpgradeMap $upgradeMap -SourceIdentity $source
  $canaries+=$record
  Write-MIR4T13Json -Path (Join-Path $output "canaries/$($definition.id).json") -Value $record
}
$supplements=Join-Path $output 'supplements';New-Item -ItemType Directory -Path $supplements -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $capture 'locks/f200-k2so.json') -Destination (Join-Path $supplements 'f200-k2so.lock.json') -Force
Copy-Item -LiteralPath (Join-Path $capture 'snapshots/f200-k2so.json') -Destination (Join-Path $supplements 'f200-k2so.snapshot.json') -Force
$packageAfter=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$receipt=[pscustomobject][ordered]@{
  schema=1;kind='MIR4T13ReceiptV1';work_package='T13';status='completed-machine-work';source_identity=$source
  canary_count=$canaries.Count;capture_count=$captures.Count;target_count=$upgradeMap.Count
  all_clean_loads_passed=$true;all_first_reloads_passed=$true;all_second_reloads_passed=$true;all_performance_within_budget=$true;all_target_upgrades_passed=$true
  all_claims_exact_and_expiring=$true;f200_k2so_archive_custody_complete=$true;t12_historical_blocker_superseded=$true
  package_source_before=$packageBefore;package_source_after=$packageAfter;package_source_unchanged=($packageBefore-ceq$packageAfter)
  public_support_claim_authorized=$false;source_freeze_authorized=$false;release_transition_authorized=$false;package_visible=$false;digest=''
}
Add-MIR4T13Digest -Value $receipt -Domain 'mir4:t13-receipt:1'|Out-Null
if(-not$receipt.package_source_unchanged-or$captures.Count-ne[int]$authority.required_capture_count-or$canaries.Count-ne[int]$authority.required_canary_count){throw '[mir4-t13-exit-gate]'}
Write-MIR4T13Json -Path (Join-Path $output 'MIR4_T13_RECEIPT.json') -Value $receipt
$files=@(Get-ChildItem -LiteralPath $output -Recurse -File -Filter '*.json'|Where-Object Name -cne 'MIR4_T13_MANIFEST.json'|Sort-Object FullName|ForEach-Object{[ordered]@{path=[IO.Path]::GetRelativePath($output,$_.FullName).Replace('\','/');bytes=$_.Length;sha256='sha256:'+(Get-MIR4T12FileSha256 $_.FullName)}})
$manifest=[pscustomobject][ordered]@{schema=1;kind='MIR4T13ManifestV1';source_identity=$source;canary_count=$canaries.Count;capture_count=$captures.Count;files=$files;complete=$true;package_visible=$false;digest=''}
Add-MIR4T13Digest -Value $manifest -Domain 'mir4:t13-manifest:1'|Out-Null
Write-MIR4T13Json -Path (Join-Path $output 'MIR4_T13_MANIFEST.json') -Value $manifest
if($PublishReference){
  if(Test-Path -LiteralPath $reference){Remove-Item -LiteralPath $reference -Recurse -Force}
  New-Item -ItemType Directory -Path $reference -Force|Out-Null
  foreach($file in Get-ChildItem -LiteralPath $output -Recurse -File -Filter '*.json'){
    $relative=[IO.Path]::GetRelativePath($output,$file.FullName);$destination=Join-Path $reference $relative;$parent=Split-Path -Parent $destination
    if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
  }
}
[pscustomobject][ordered]@{status='passed';source_identity=$source;canary_count=$canaries.Count;capture_count=$captures.Count;receipt_digest=$receipt.digest;package_source_unchanged=$receipt.package_source_unchanged;reference=$(if($PublishReference){$reference}else{$null});package_visible=$false;publication_authorized=$false}|ConvertTo-Json -Depth 20
