[CmdletBinding()]
param([string]$RepoRoot='',[switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($RepoRoot)){$RepoRoot=(Resolve-Path(Join-Path $PSScriptRoot '../../..')).Path}else{$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path}
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')

$outputRelative='governance/repository/migrations/current-product-bridge-retirement-v1.json'
$schemaRelative='contracts/repository/mir4-current-product-bridge-retirement-v1.schema.json'
$fixed=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.mir/control/repository-fixed-point.json')|ConvertFrom-Json -Depth 100 -DateKind String
$predecessorPath='releases/migrations/MIR4-M42-02-Supply-Chain-DecompositionV1.json'
$predecessorRaw=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $predecessorPath)
$predecessor=$predecessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
if(-not(Test-MIR4BootstrapRecordHash -Record $predecessor)){throw '[mir4-bridge-retirement-predecessor]'}

$bridges=[Collections.Generic.List[object]]::new()
foreach($sequence in @($fixed.migration_sequence)){
  if([string]$sequence.migration_id-ceq'M41-CURRENT-PRODUCT-BRIDGE-RETIREMENT-V1'-or[string]$sequence.authority-notlike'governance/repository/migrations/*'){continue}
  $migration=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ([string]$sequence.authority))|ConvertFrom-Json -Depth 100 -DateKind String
  foreach($entry in @($migration.compatibility_entrypoints)){
    $replacements=@($migration.path_map|Where-Object{[string]$_.current_path-ceq[string]$entry.path}|ForEach-Object{[string]$_.final_path}|Sort-Object -Unique)
    if($replacements.Count-eq0){throw "[mir4-bridge-retirement-unbounded-replacement] $([string]$entry.path)"}
    $isReadme=[string]$entry.path-ceq'README.md'
    $bridges.Add([ordered]@{
      migration_id=[string]$migration.migration_id;path=[string]$entry.path;role=[string]$entry.role
      disposition=$(if($isReadme){'retired-reassigned'}else{'retained-historical-compatibility'})
      canonical_replacements=$replacements;writable=$false;package_visible=$false;current_semantic_use=$false;current_authority=$false
      owner='repository-governance';proof='tests/repository/Test-MIR4CurrentProductBridgeRetirement.ps1'
      expiry_condition=$(if($isReadme){'Repository README remains package-excluded and target READMEs remain materializer-generated.'}else{'Review for removal at MIR-4.2-COMPATIBILITY-SUNSET-REVIEW; removal requires consumer absence, parity, and rollback proof.'})
      rollback='Revert the exact bridge-retirement work package without granting current authority to this path.';deletion_authorized=$false
    })
  }
}
$bridges=@($bridges|Sort-Object migration_id,path)
if($bridges.Count-ne49){throw "[mir4-bridge-retirement-count] $($bridges.Count)"}
$package=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'targets/package-authority.json')|ConvertFrom-Json -Depth 100 -DateKind String
$context=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/execution/mir4-4.1-development-context-v1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if(-not(Test-MIR4BootstrapRecordHash -Record $package)-or-not(Test-MIR4BootstrapRecordHash -Record $context)){throw '[mir4-bridge-retirement-current-authority-hash]'}

$paths=@(
  [ordered]@{family='bridge-retirement-authority';current_path=$null;final_path=$outputRelative;state='canonical';package_visible=$false},
  [ordered]@{family='bridge-retirement-contract';current_path=$null;final_path=$schemaRelative;state='canonical';package_visible=$false},
  [ordered]@{family='bridge-retirement-application';current_path=$null;final_path='tools/mir/application/repository/BridgeRetirement.ps1';state='canonical';package_visible=$false},
  [ordered]@{family='bridge-retirement-writer';current_path=$null;final_path='tools/commands/mir4/Update-MIR4M41CurrentProductBridgeRetirementAuthority.ps1';state='canonical';package_visible=$false},
  [ordered]@{family='bridge-retirement-proof';current_path=$null;final_path='tests/repository/Test-MIR4CurrentProductBridgeRetirement.ps1';state='canonical';package_visible=$false},
  [ordered]@{family='development-execution-context';current_path='.mir/releases/waves/mir4-r0/MIR4-M4C01-Implementation-AuthorizationV1.json';final_path='spec/execution/mir4-4.1-development-context-v1.json';state='current-development-context';package_visible=$false},
  [ordered]@{family='package-identity-reader';current_path='tools/lib/validation/PackageIdentity.ps1';final_path='tools/lib/validation/PackageIdentity.ps1';state='canonical-fail-closed';package_visible=$false},
  [ordered]@{family='package-authority';current_path='targets/package-authority.json';final_path='targets/package-authority.json';state='canonical-root-projection-retired';package_visible=$false},
  [ordered]@{family='repository-fixed-point';current_path='.mir/control/repository-fixed-point.json';final_path='.mir/control/repository-fixed-point.json';state='append-only-successor';package_visible=$false},
  [ordered]@{family='repository-characterization';current_path='tools/mir/application/repository/RepositoryCharacterization.ps1';final_path='tools/mir/application/repository/RepositoryCharacterization.ps1';state='canonical-current-dispositions';package_visible=$false}
)
$record=[ordered]@{
  schema=1;kind='MIR4CurrentProductBridgeRetirementV1';migration_id='M41-CURRENT-PRODUCT-BRIDGE-RETIREMENT-V1';state='CURRENT-PRODUCT-BRIDGES-RETIRED-HISTORICAL-COMPATIBILITY-BOUNDED'
  scope='Retire every current-product authority bridge while retaining only explicit read-only, package-excluded, owned, tested, and expiry-bounded historical compatibility paths.'
  predecessor=[ordered]@{branch='dev';commit='03737ccaefbda04001166e6b5e2fffe20ccadf96';tree='9465304d732db746376e2e41f67cd2ff79766e67';receipt=$predecessorPath;receipt_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot $predecessorPath));record_sha256=[string]$predecessor.record_sha256;package_source_sha256=[string]$predecessor.preservation.package_source_sha256}
  writers=@([ordered]@{fact_family='current-product-bridge-retirement';path='tools/commands/mir4/Update-MIR4M41CurrentProductBridgeRetirementAuthority.ps1';command='pwsh -NoProfile -File tools/commands/mir4/Update-MIR4M41CurrentProductBridgeRetirementAuthority.ps1'})
  path_map=$paths;compatibility_entrypoints=@();bridge_dispositions=$bridges
  summary=[ordered]@{declared=49;retired=1;retained_historical=48;current_product=0;dual_write_authority=0;package_authority_bridge=0;release_current_state_authority_bridge=0;runtime_state_migration_authority_bridge=0;public_claim_authority_bridge=0;unowned=0;unbounded=0}
  package_source_authority=[ordered]@{path='targets/package-authority.json';record_sha256=[string]$package.record_sha256;legacy_root_state=[string]$package.legacy_root_projection.compatibility_state;silent_fallback_blocked=[bool]$package.legacy_root_projection.silent_reactivation_blocked}
  execution_context=[ordered]@{path='spec/execution/mir4-4.1-development-context-v1.json';record_sha256=[string]$context.record_sha256;release_authority=$false}
  rollback=[ordered]@{mode='revert-exact-merged-work-package';commit='03737ccaefbda04001166e6b5e2fffe20ccadf96';tree='9465304d732db746376e2e41f67cd2ff79766e67';root_writer_reactivation_authorized=$false}
  sunset=[ordered]@{state='historical-compatibility-only';review_boundary='MIR-4.2-COMPATIBILITY-SUNSET-REVIEW';removal_requires=@('declared-consumer-absence','canonical-parity','rollback-proof')}
  transition_gate=[ordered]@{bridge_retirement=$true;source_freeze=$false;version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  record_sha256=''
}
$recordObject=[pscustomobject]$record
$record.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $recordObject
$json=(($record|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n")
$outputPath=Join-Path $RepoRoot $outputRelative
if($Check){
  if(-not(Test-Path -LiteralPath $outputPath -PathType Leaf)-or[IO.File]::ReadAllText($outputPath).Replace("`r`n","`n")-cne$json){throw '[mir4-bridge-retirement-authority-stale]'}
}else{
  [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath));[IO.File]::WriteAllText($outputPath,$json,[Text.UTF8Encoding]::new($false))
}
if(-not((Get-Content -Raw -LiteralPath $outputPath)|Test-Json -SchemaFile(Join-Path $RepoRoot $schemaRelative))){throw '[mir4-bridge-retirement-authority-schema]'}
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;record_sha256=[string]$record.record_sha256;bridges=$bridges.Count;package_source_sha256=(Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot)}
