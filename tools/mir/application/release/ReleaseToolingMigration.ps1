. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot '../history/HistoricalToolingMigration.ps1')
. (Join-Path $PSScriptRoot 'ReleaseDag.ps1')
. (Join-Path $PSScriptRoot '../../../lib/validation/PackageIdentity.ps1')

$script:MIR4ReleaseToolingMigrationAuthorityPath='governance/repository/migrations/release-tooling-v1.json'
$script:MIR4ReleaseToolingMigrationAuthoritySchemaPath='contracts/repository/mir4-release-tooling-migration-authority-v1.schema.json'
$script:MIR4ReleaseToolingMigrationProofPath='assurance/repository/release-tooling-v1.json'
$script:MIR4ReleaseToolingMigrationProofSchemaPath='contracts/repository/mir4-release-tooling-migration-proof-v1.schema.json'
$script:MIR4ReleaseToolingMigrationReceiptPath='releases/migrations/MIR4-Release-Tooling-MigrationV1.json'
$script:MIR4ReleaseToolingMigrationReceiptSchemaPath='contracts/repository/mir4-release-tooling-migration-receipt-v1.schema.json'
$script:MIR4ReleaseToolingPredecessorReceiptPath='releases/migrations/MIR4-Historical-Tooling-MigrationV1.json'
$script:MIR4ReleaseToolingPredecessorReceiptSha256='2DD6E9A15A239968B22539EE1C203345CFA6FB29498911770D1035503737E104'
$script:MIR4ReleaseToolingPredecessorReceiptBytes=40658
$script:MIR4ReleaseToolingFunctionalDigestV1='sha256:59043062e11420aee5daaeee51f8735f538b3091b0a87b43ec9c22e10743f99d'
$script:MIR4ReleaseToolingImplementationSha256='C2CD3A4A84A21FB2722C5203CC9ED318BB1876C5C4388EB73BA5ADFE21CD4EE1'
$script:MIR4ReleaseToolingDagAuthoritySha256='4D7532BCE19B995CC215FA4E26E6079278E26E8FF3C1E9AE72C5F1422E24DDBD'
$script:MIR4ReleaseToolingCompatibilityPolicySha256='54C226D32D092BD521AD016089944ED282AF2806FE7ED26A6F61197B731B0EE2'
$script:MIR4ReleaseToolingT14ReceiptSha256='AD83B044BF955D136FF68484D5913F1B857238D73229ED03F8B278AB5CB6EED0'

function Get-MIR4ReleaseToolingMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4ReleaseToolingMigrationAuthorityPath -SchemaPath $script:MIR4ReleaseToolingMigrationAuthoritySchemaPath)){throw '[mir4-release-tooling-migration-authority-schema]'}
  $authority=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4ReleaseToolingMigrationAuthorityPath
  if([string]$authority.predecessor_receipt.path-cne$script:MIR4ReleaseToolingPredecessorReceiptPath-or[string]$authority.predecessor_receipt.sha256-cne$script:MIR4ReleaseToolingPredecessorReceiptSha256){throw '[mir4-release-tooling-migration-predecessor-authority]'}
  if(@($authority.writers).Count-ne1-or[string]$authority.writers[0].path-cne'tools/mir/application/release/ReleaseToolingMigration.ps1'){throw '[mir4-release-tooling-migration-single-writer]'}
  $finalPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path});if(@($finalPaths|Sort-Object -Unique).Count-ne$finalPaths.Count){throw '[mir4-release-tooling-migration-duplicate-final-path]'}
  foreach($requiredPath in @('tools/mir/application/release/ReleaseToolingMigration.ps1','tools/mir/cli/Invoke-MIR4ReleaseToolingMigration.ps1')){if($requiredPath-notin$finalPaths){throw "[mir4-release-tooling-migration-writer-closure] $requiredPath"}}
  if(@($authority.release_transition_authority.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-release-tooling-migration-release-authority]'}
  return $authority
}

function Get-MIR4ReleaseToolingMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4ReleaseToolingMigrationProofPath -SchemaPath $script:MIR4ReleaseToolingMigrationProofSchemaPath)){throw '[mir4-release-tooling-migration-proof-schema]'}
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4ReleaseToolingMigrationProofPath
}

function Test-MIR4ReleaseToolingForwarderV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$path=Join-Path $repo 'tools/lib/mir4/ReleaseDag.ps1'
  $text=[IO.File]::ReadAllText($path).Replace('\','/')
  if($text-cnotmatch[regex]::Escape('mir/application/release/ReleaseDag.ps1')-or$text.Split([char]10).Count-gt3-or$text-match'(?m)^function\s+'){throw '[mir4-release-tooling-forwarder] tools/lib/mir4/ReleaseDag.ps1'}
  return $true
}

function Test-MIR4ReleaseToolingDeclaredConsumersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$releaseDag='tools/mir/application/release/ReleaseDag.ps1'
  $requirements=[ordered]@{
    'tools/lib/mir4/PlatformPreview.ps1'=@($releaseDag)
    'validation/tests.yml'=@($releaseDag,'tests/release-tooling/Test-MIR4ReleaseTooling.ps1','tests/release-tooling/Test-MIR4ReleaseToolingMigration.ps1')
    '.mir/control/paths.yml'=@($releaseDag,'tools/mir/application/release/ReleaseToolingMigration.ps1','tools/mir/cli/Invoke-MIR4ReleaseToolingMigration.ps1')
    '.mir/modules.yml'=@($releaseDag,'tools/mir/application/release/ReleaseToolingMigration.ps1','tools/mir/cli/Invoke-MIR4ReleaseToolingMigration.ps1')
    'tools/mir.ps1'=@('tools/mir/cli/Invoke-MIR4ReleaseToolingMigration.ps1')
    'docs/architecture/mir4-platform-preview.md'=@('tools/mir/application/release/ReleaseDag.ps1')
    'docs/architecture/module-boundaries.md'=@('tools/mir/application/release/ReleaseDag.ps1')
  }
  foreach($entry in $requirements.GetEnumerator()){$text=[IO.File]::ReadAllText((Join-Path $repo ([string]$entry.Key))).Replace('\','/');foreach($required in @($entry.Value)){if($text-cnotmatch[regex]::Escape([string]$required)){throw "[mir4-release-tooling-consumer-final-path] $($entry.Key) -> $required"}}}
  return $true
}

function Invoke-MIR4ReleaseToolingProbeCaseV1($Value){try{$result=Test-MIR4ReleaseDag -Dag $Value;return [ordered]@{accepted=$true;result=[bool]$result;error=''}}catch{return [ordered]@{accepted=$false;result=$false;error=[string]$_.Exception.Message}}}
function Copy-MIR4ReleaseToolingProbeV1($Value){return $Value|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100}

function Get-MIR4ReleaseToolingFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $dag=Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/platform/mir4-preview-v0/release-dag.json')|ConvertFrom-Json -Depth 100
  $identity=Copy-MIR4ReleaseToolingProbeV1 $dag;$identity.kind='wrong'
  $duplicate=Copy-MIR4ReleaseToolingProbeV1 $dag;$duplicate.nodes+=Copy-MIR4ReleaseToolingProbeV1 $duplicate.nodes[0]
  $missing=Copy-MIR4ReleaseToolingProbeV1 $dag;$missing.nodes[0].depends_on=@('absent')
  $boundary=Copy-MIR4ReleaseToolingProbeV1 $dag;$boundary.nodes[10].authorization='candidate-programme'
  $cycle=Copy-MIR4ReleaseToolingProbeV1 $dag;$cycle.nodes[0].depends_on=@('public-readback')
  $record=[ordered]@{
    kind='MIR4ReleaseDagFunctionalProbeV1';schema=1;source_kind=[string]$dag.kind;source_schema=[int]$dag.schema;source_status=[string]$dag.status
    node_count=@($dag.nodes).Count;protected_mutation_count=@($dag.nodes|Where-Object{$_.mutation-in@('sign','seal','promote','tag','publish','delete')}).Count
    valid=Invoke-MIR4ReleaseToolingProbeCaseV1 $dag;identity=Invoke-MIR4ReleaseToolingProbeCaseV1 $identity;duplicate=Invoke-MIR4ReleaseToolingProbeCaseV1 $duplicate
    missing=Invoke-MIR4ReleaseToolingProbeCaseV1 $missing;boundary=Invoke-MIR4ReleaseToolingProbeCaseV1 $boundary;cycle=Invoke-MIR4ReleaseToolingProbeCaseV1 $cycle
  }
  return [pscustomobject][ordered]@{record=$record;digest=(Get-MIR4CanonicalDigestV1 -Value $record -Domain 'mir4:release-dag-functional-probe:1')}
}

function Test-MIR4ReleaseToolingFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $result=Get-MIR4ReleaseToolingFunctionalParityV1 -RepoRoot $RepoRoot
  if([string]$result.digest-cne$script:MIR4ReleaseToolingFunctionalDigestV1-or-not[bool]$result.record.valid.accepted-or[int]$result.record.node_count-ne20-or[int]$result.record.protected_mutation_count-ne6){throw "[mir4-release-tooling-functional-parity] $([string]$result.digest)"}
  return $result
}

function New-MIR4ReleaseToolingMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$migration=Get-MIR4ReleaseToolingMigrationAuthorityV1 -RepoRoot $repo;$proof=Get-MIR4ReleaseToolingMigrationProofPolicyV1 -RepoRoot $repo
  $prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration -IncludeHistoricalToolingMigration
  [void](Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4ReleaseToolingPredecessorReceiptPath -ExpectedSha256 $script:MIR4ReleaseToolingPredecessorReceiptSha256 -SchemaPath 'contracts/repository/mir4-historical-tooling-migration-receipt-v1.schema.json' -Kind 'MIR4HistoricalToolingMigrationReceiptV1' -DigestDomain 'mir4:historical-tooling-migration-receipt:1' -ErrorPrefix 'mir4-release-tooling-predecessor')
  if((Get-Item -LiteralPath (Join-Path $repo $script:MIR4ReleaseToolingPredecessorReceiptPath)).Length-ne$script:MIR4ReleaseToolingPredecessorReceiptBytes){throw '[mir4-release-tooling-predecessor-byte-length]'}
  [void](Test-MIR4ReleaseToolingForwarderV1 -RepoRoot $repo);[void](Test-MIR4ReleaseToolingDeclaredConsumersV1 -RepoRoot $repo);[void](Test-MIR4ReleaseToolingFunctionalParityV1 -RepoRoot $repo)
  if((Get-FileHash -LiteralPath (Join-Path $repo 'tools/mir/application/release/ReleaseDag.ps1') -Algorithm SHA256).Hash-cne$script:MIR4ReleaseToolingImplementationSha256){throw '[mir4-release-tooling-implementation-parity]'}
  if((Get-FileHash -LiteralPath (Join-Path $repo 'spec/platform/mir4-preview-v0/release-dag.json') -Algorithm SHA256).Hash-cne$script:MIR4ReleaseToolingDagAuthoritySha256){throw '[mir4-release-tooling-dag-authority-mutated]'}
  if((Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash-cne$script:MIR4ReleaseToolingCompatibilityPolicySha256){throw '[mir4-release-tooling-compatibility-policy-mutated]'}
  if((Get-FileHash -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T14-Authority-Evolution-ReceiptV1.json') -Algorithm SHA256).Hash-cne$script:MIR4ReleaseToolingT14ReceiptSha256){throw '[mir4-release-tooling-t14-receipt-mutated]'}
  $bootstrapProfile=@((Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json').profiles.'mir4-bootstrap');foreach($testId in @('static.mir4-release-tooling-v1','static.mir4-release-tooling-migration-v1')){if($testId-notin$bootstrapProfile){throw "[mir4-release-tooling-bootstrap-profile] $testId"}}
  $integrationPaths=@(
    '.gitattributes','.mir/assurance.json','.mir/control/repository-fixed-point.json','.mir/control/paths.yml','.mir/control-plane/ownership.json','.mir/modules.yml','.mir/docs.yml',
    'assurance/.mir-root.json','governance/.mir-root.json','tests/.mir-root.json','validation/tests.yml','tools/mir.ps1','mir.lock','spec/platform/mir4-preview-v0/release-dag.json',
    'tools/mir/application/release/ReleaseDag.ps1','tools/mir/application/release/ReleaseToolingMigration.ps1','tools/mir/cli/Invoke-MIR4ReleaseToolingMigration.ps1','tools/lib/mir4/ReleaseDag.ps1',
    'tools/lib/mir4/PlatformPreview.ps1','tools/lib/mir4/PreFreezeRelease.ps1','tools/lib/assurance/Evidence.ps1','validation/tests/mir4/Test-MIR4PlatformPreview.ps1',
    'validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1','validation/tests/tooling/Test-MIRAssurance.ps1',
    'docs/architecture/mir4-repository-fixed-point.md','docs/architecture/mir4-platform-preview.md','docs/architecture/mir4-historical-succession.md','docs/architecture/module-boundaries.md','docs/reference/generated/mir4-platform-component-matrix.md','docs/reference/generated/mir4-whole-platform-matrix.md','docs/releases/mir4-4.0-whole-platform-programme.md',
    'tools/mir/application/history/HistoricalToolingMigration.ps1','tools/mir/cli/Invoke-MIR4HistoricalToolingMigration.ps1','tests/history/Test-MIR4HistoricalToolingMigration.ps1','tests/assurance/Test-MIR4AssuranceOfflineCustodyMigration.ps1',
    'tools/mir/domain/repository/RepositoryFixedPoint.ps1','tests/repository/Test-MIR4RepositoryFixedPoint.ps1'
  )
  $parity=[ordered]@{canonical_writer_count=@($migration.writers).Count;shared_migration_engine=$true;compatibility_forwarder_verified=$true;release_dag_functional_parity=$true;release_dag_result_abi_preserved=$true;declared_consumers_use_final_path=$true;focused_test_registered=$true;release_dag_authority_read_only=$true;compatibility_policy_read_only=$true;historical_t14_evidence_read_only=$true;release_phase_engine_out_of_scope=$true;player_runtime_authority_read_only=$true;predecessor_writer_disabled=$true;release_history_successor_verified=$true;release_history_fingerprint_bound=$true;authority_schema_verified=$true;assurance_schema_verified=$true;rollback_recorded=(-not[string]::IsNullOrWhiteSpace([string]$migration.rollback.command));duplicate_writers=@()}
  return New-MIR4AppendOnlyAuthorityMigrationReceiptV1 -RepoRoot $repo -Migration $migration -Proof $proof -Prior $prior -ReceiptKind 'MIR4ReleaseToolingMigrationReceiptV1' -ReceiptState 'RELEASE-DAG-APPLICATION-AND-TEST-CUTOVER-VERIFIED-COMPATIBILITY-RETAINED' -ReceiptPath $script:MIR4ReleaseToolingMigrationReceiptPath -MigrationAuthorityPath $script:MIR4ReleaseToolingMigrationAuthorityPath -AssurancePath $script:MIR4ReleaseToolingMigrationProofPath -Scope 'package-excluded-release-tooling-migration' -EvolutionReason 'Package-excluded read-only release-DAG tooling migration with release phase execution, compatibility policy, immutable T14 evidence, player-runtime, and release-authority firewalls.' -DigestDomain 'mir4:release-tooling-migration-receipt:1' -Parity $parity -IntegrationPaths $integrationPaths
}

function Get-MIR4ReleaseToolingMigrationReceiptTextV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (ConvertTo-MIR4CanonicalJsonV1 -Value (New-MIR4ReleaseToolingMigrationReceiptV1 -RepoRoot $RepoRoot))+[char]10
}

function Invoke-MIR4ReleaseToolingMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$path=Join-Path $repo $script:MIR4ReleaseToolingMigrationReceiptPath;$text=Get-MIR4ReleaseToolingMigrationReceiptTextV1 -RepoRoot $repo
  if($Check){if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or[IO.File]::ReadAllText($path)-cne$text){throw '[mir4-release-tooling-migration-receipt-stale]'};if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4ReleaseToolingMigrationReceiptPath -SchemaPath $script:MIR4ReleaseToolingMigrationReceiptSchemaPath)){throw '[mir4-release-tooling-migration-receipt-schema]'}}else{New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent)|Out-Null;[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))}
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4ReleaseToolingMigrationReceiptPath
}
