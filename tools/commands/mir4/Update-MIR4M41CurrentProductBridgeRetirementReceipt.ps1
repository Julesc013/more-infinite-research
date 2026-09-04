[CmdletBinding()]
param([string]$RepoRoot='',[string]$RecordedAt='',[switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($RepoRoot)){$RepoRoot=(Resolve-Path(Join-Path $PSScriptRoot '../../..')).Path}else{$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path}
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/repository/BridgeRetirement.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/repository/RepositoryCharacterization.ps1')

$outputRelative='releases/migrations/MIR4-M41-Current-Product-Bridge-RetirementV1.json'
$schemaRelative='contracts/repository/mir4-m41-current-product-bridge-retirement-v1.schema.json'
$predecessorRelative='releases/migrations/MIR4-M42-02-Supply-Chain-DecompositionV1.json'
$predecessorRaw=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $predecessorRelative)
$predecessor=$predecessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
$authority=Get-MIR4CurrentProductBridgeRetirementAuthority -RepoRoot $RepoRoot
$fixedRaw=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.mir/control/repository-fixed-point.json')
$fixed=$fixedRaw|ConvertFrom-Json -Depth 100 -DateKind String
$package=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'targets/package-authority.json')|ConvertFrom-Json -Depth 100 -DateKind String
$context=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/execution/mir4-4.1-development-context-v1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$fixed.state-cne'MIR41-CURRENT-PRODUCT-BRIDGES-RETIRED'-or-not[bool]$fixed.physical_cutover-or[bool]$fixed.current_package_source_remains_authoritative){throw '[mir4-bridge-retirement-fixed-point]'}

$characterization=Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $RepoRoot -OutputPath 'build/reports/repository-characterization'
[void](Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $RepoRoot -OutputPath 'build/reports/repository-characterization' -Check)
$bridge=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'build/reports/repository-characterization/bridge-expiry.json')|ConvertFrom-Json -Depth 100 -DateKind String
$zeroNames=@('current_product','dual_write_authority','package_authority_bridge','release_current_state_authority_bridge','runtime_state_migration_authority_bridge','public_claim_authority_bridge','unowned','unbounded')
foreach($name in $zeroNames){if([int]$bridge.summary.$name-ne0){throw "[mir4-bridge-retirement-characterization] $name"}}

$outputPath=Join-Path $RepoRoot $outputRelative
if($Check){
  if(-not(Test-Path -LiteralPath $outputPath -PathType Leaf)){throw '[mir4-bridge-retirement-receipt-missing]'}
  $existing=Get-Content -Raw -LiteralPath $outputPath|ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt=[string]$existing.recorded_at
}elseif([string]::IsNullOrWhiteSpace($RecordedAt)){$RecordedAt=[DateTimeOffset]::Now.ToString('o')}

$predecessorCommit=[string]$authority.predecessor.commit
$trackedChanges=@(& git -C $RepoRoot diff --name-only $predecessorCommit --)
if($LASTEXITCODE-ne0){throw '[mir4-bridge-retirement-diff]'}
$untrackedChanges=@(& git -C $RepoRoot ls-files --others --exclude-standard)
if($LASTEXITCODE-ne0){throw '[mir4-bridge-retirement-untracked]'}
$changedPaths=@($trackedChanges+$untrackedChanges|ForEach-Object{([string]$_).Replace('\','/')}|Where-Object{$_-and$_-cne$outputRelative}|Sort-Object -Unique)
$packageOutputs=@(Get-MIRPackageOutputPaths -RepoRoot $RepoRoot)
$evolved=[Collections.Generic.List[object]]::new()
$current=[Collections.Generic.List[object]]::new()
foreach($path in $changedPaths){
  $full=Join-Path $RepoRoot $path
  if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "[mir4-bridge-retirement-changed-path] $path"}
  if(-not(Test-MIRTextFingerprintPath -RelativePath $path)){throw "[mir4-bridge-retirement-non-text-authority] $path"}
  if($path-in$packageOutputs){throw "[mir4-bridge-retirement-package-visible-binding] $path"}
  $currentSha=Get-MIRFileContentSha256 -Path $full -RelativePath $path
  & git -C $RepoRoot cat-file -e ($predecessorCommit+':'+$path) 2>$null
  if($LASTEXITCODE-eq0){
    $evolved.Add([ordered]@{path=$path;previous_sha256=(Get-MIRGitTextAtCommitSha256 -RepoRoot $RepoRoot -Commit $predecessorCommit -RelativePath $path);current_sha256=$currentSha;hash_mode='canonical-text-v1';scope='current-product-bridge-retirement';package_visible=$false;release_authority=$false})
  }else{
    $current.Add([ordered]@{path=$path;sha256=$currentSha;hash_mode='canonical-text-v1';role='Current bridge-retirement authority or proof.'})
  }
}
if($evolved.Count-eq0-or$current.Count-eq0){throw '[mir4-bridge-retirement-authority-bindings]'}
$record=[ordered]@{
  schema=1;kind='MIR4M41CurrentProductBridgeRetirementReceiptV1';recorded_at=$RecordedAt;status='M41-CURRENT-PRODUCT-BRIDGES-RETIRED-PRIVATE-QUALIFICATION-PENDING'
  predecessor=[ordered]@{path=$predecessorRelative;sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot $predecessorRelative));record_sha256=[string]$predecessor.record_sha256}
  authority=[ordered]@{path='governance/repository/migrations/current-product-bridge-retirement-v1.json';sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot 'governance/repository/migrations/current-product-bridge-retirement-v1.json'));record_sha256=[string]$authority.record_sha256}
  fixed_point=[ordered]@{path='.mir/control/repository-fixed-point.json';sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot '.mir/control/repository-fixed-point.json'));state=[string]$fixed.state;physical_cutover=[bool]$fixed.physical_cutover;legacy_root_current_authority=[bool]$fixed.current_package_source_remains_authoritative}
  package_source=[ordered]@{predecessor_sha256=[string]$predecessor.preservation.package_source_sha256;current_sha256=(Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot);authority_record_sha256=[string]$package.record_sha256;writer=[string]$package.writer.implementation;legacy_root_state=[string]$package.legacy_root_projection.compatibility_state;silent_fallback_blocked=[bool]$package.legacy_root_projection.silent_reactivation_blocked}
  execution_context=[ordered]@{path='spec/execution/mir4-4.1-development-context-v1.json';record_sha256=[string]$context.record_sha256;historical_m4c01_current_authority=[bool]$context.historical_context.current_authority;release_authority=$false}
  characterization=[ordered]@{bridge_expiry_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot 'build/reports/repository-characterization/bridge-expiry.json'));declared=[int]$bridge.summary.declared;retired=[int]$bridge.summary.retired;retained_historical=[int]$bridge.summary.retained_historical;required_zero=$zeroNames}
  evolved_bindings=@($evolved);current_authorities=@($current)
  proofs=@('tests/repository/Test-MIR4CurrentProductBridgeRetirement.ps1','tests/repository/Test-MIR4RepositoryFixedPoint.ps1','tests/mir4/Test-MIR4PackageAuthorityF2E.ps1','tests/mir4/Test-MIR4RepositoryCharacterizationM4200A.ps1')
  package_visible_delta=@();transition_gate=[ordered]@{bridge_retirement=$true;private_qualification=$false;version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false};record_sha256=''
}
$recordObject=[pscustomobject]$record
$record.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $recordObject
$json=(($record|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n")
if($Check){if([IO.File]::ReadAllText($outputPath).Replace("`r`n","`n")-cne$json){throw '[mir4-bridge-retirement-receipt-stale]'}}else{[void](New-Item -ItemType Directory -Force -Path(Split-Path -Parent $outputPath));[IO.File]::WriteAllText($outputPath,$json,[Text.UTF8Encoding]::new($false))}
if(-not((Get-Content -Raw -LiteralPath $outputPath)|Test-Json -SchemaFile(Join-Path $RepoRoot $schemaRelative))){throw '[mir4-bridge-retirement-receipt-schema]'}
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;record_sha256=[string]$record.record_sha256;bridges=[int]$bridge.summary.declared;current_product=[int]$bridge.summary.current_product;package_source_sha256=[string]$record.package_source.current_sha256}
