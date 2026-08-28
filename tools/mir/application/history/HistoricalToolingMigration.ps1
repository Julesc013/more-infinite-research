. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot '../assurance/AssuranceOfflineCustodyMigration.ps1')
. (Join-Path $PSScriptRoot '../../../lib/mir4/PlatformPreview.ps1')
. (Join-Path $PSScriptRoot '../../../lib/validation/PackageIdentity.ps1')
. (Join-Path $PSScriptRoot 'HistoricalSuccession.ps1')
. (Join-Path $PSScriptRoot 'SuccessorHost.ps1')

$script:MIR4HistoricalToolingMigrationAuthorityPath='governance/repository/migrations/historical-tooling-v1.json'
$script:MIR4HistoricalToolingMigrationAuthoritySchemaPath='contracts/repository/mir4-historical-tooling-migration-authority-v1.schema.json'
$script:MIR4HistoricalToolingMigrationProofPath='assurance/repository/historical-tooling-v1.json'
$script:MIR4HistoricalToolingMigrationProofSchemaPath='contracts/repository/mir4-historical-tooling-migration-proof-v1.schema.json'
$script:MIR4HistoricalToolingMigrationReceiptPath='releases/migrations/MIR4-Historical-Tooling-MigrationV1.json'
$script:MIR4HistoricalToolingMigrationReceiptSchemaPath='contracts/repository/mir4-historical-tooling-migration-receipt-v1.schema.json'
$script:MIR4HistoricalToolingPredecessorReceiptPath='releases/migrations/MIR4-Assurance-Offline-Custody-Tooling-MigrationV1.json'
$script:MIR4HistoricalToolingPredecessorReceiptSha256='3B6F3B057BD74353B4A12FB5F7C108C3AE41470C375D74DAC424E888668ED749'
$script:MIR4HistoricalToolingPreCutoverDigestV1='sha256:a66ac831c64f82246d406c209f6c389abde61dd767021b141a0b235c887708f4'
$script:MIR4HistoricalToolingParityDigestV1='sha256:beda067ccc49a56b9b836994e96517b3869275a461d0a67eeff617361ce25c6f'
$script:MIR4HistoricalToolingArchiveContentSha256V1='sha256:c5b5c7d1a82f7d2d68d7f324249cbf56150a3cb43accb5944305e152196fe0b1'
$script:MIR4HistoricalToolingCompatibilityPolicySha256='54C226D32D092BD521AD016089944ED282AF2806FE7ED26A6F61197B731B0EE2'
$script:MIR4HistoricalToolingT14ReceiptSha256='AD83B044BF955D136FF68484D5913F1B857238D73229ED03F8B278AB5CB6EED0'
$script:MIR4HistoricalToolingReleaseDagSha256='C2CD3A4A84A21FB2722C5203CC9ED318BB1876C5C4388EB73BA5ADFE21CD4EE1'

function Get-MIR4HistoricalToolingMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4HistoricalToolingMigrationAuthorityPath -SchemaPath $script:MIR4HistoricalToolingMigrationAuthoritySchemaPath)){throw '[mir4-historical-tooling-migration-authority-schema]'}
  $authority=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4HistoricalToolingMigrationAuthorityPath
  if([string]$authority.predecessor_receipt.path-cne$script:MIR4HistoricalToolingPredecessorReceiptPath-or[string]$authority.predecessor_receipt.sha256-cne$script:MIR4HistoricalToolingPredecessorReceiptSha256){throw '[mir4-historical-tooling-migration-predecessor-authority]'}
  if(@($authority.writers).Count-ne1-or[string]$authority.writers[0].path-cne'tools/mir/application/history/HistoricalToolingMigration.ps1'){throw '[mir4-historical-tooling-migration-single-writer]'}
  $finalPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path});if(@($finalPaths|Sort-Object -Unique).Count-ne$finalPaths.Count){throw '[mir4-historical-tooling-migration-duplicate-final-path]'}
  foreach($requiredPath in @('tools/mir/application/history/HistoricalToolingMigration.ps1','tools/mir/cli/Invoke-MIR4HistoricalToolingMigration.ps1')){if($requiredPath-notin$finalPaths){throw "[mir4-historical-tooling-migration-writer-closure] $requiredPath"}}
  if(@($authority.release_transition_authority.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-historical-tooling-migration-release-authority]'}
  return $authority
}

function Get-MIR4HistoricalToolingMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4HistoricalToolingMigrationProofPath -SchemaPath $script:MIR4HistoricalToolingMigrationProofSchemaPath)){throw '[mir4-historical-tooling-migration-proof-schema]'}
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4HistoricalToolingMigrationProofPath
}

function Test-MIR4HistoricalToolingForwardersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $bindings=@(
    @{path='tools/lib/mir4/HistoricalSuccession.ps1';target='mir/application/history/HistoricalSuccession.ps1'},
    @{path='tools/lib/mir4/SuccessorHost.ps1';target='mir/application/history/SuccessorHost.ps1'},
    @{path='tools/commands/mir4/Export-MIR4HistoricalSuccessionRecords.ps1';target='mir/cli/Export-MIR4HistoricalSuccessionRecords.ps1'}
  )
  foreach($binding in $bindings){$text=[IO.File]::ReadAllText((Join-Path $repo $binding.path)).Replace('\','/');if($text-cnotmatch[regex]::Escape([string]$binding.target)-or$text.Split([char]10).Count-gt3-or$text-match'(?m)^function\s+'){throw "[mir4-historical-tooling-forwarder] $($binding.path)"}}
  return $true
}

function Test-MIR4HistoricalToolingDeclaredConsumersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $history='tools/mir/application/history/HistoricalSuccession.ps1';$successorHost='tools/mir/application/history/SuccessorHost.ps1';$exporter='tools/mir/cli/Export-MIR4HistoricalSuccessionRecords.ps1'
  $requirements=[ordered]@{
    'tools/lib/mir4/PlatformPreview.ps1'=@($history,$successorHost)
    'validation/tests/mir4/Test-MIR4HistoricalSuccessionW09.ps1'=@($history,$successorHost,$exporter)
    'validation/tests.yml'=@($history,$successorHost,$exporter,'tests/history/Test-MIR4HistoricalTooling.ps1','tests/history/Test-MIR4HistoricalToolingMigration.ps1')
    '.mir/control/paths.yml'=@($history,$successorHost,$exporter,'tools/mir/application/history/HistoricalToolingMigration.ps1','tools/mir/cli/Invoke-MIR4HistoricalToolingMigration.ps1')
    '.mir/modules.yml'=@($history,$successorHost,$exporter)
    '.mir/releases/waves/mir4-r0/MIR4-Historical-Succession-ProgrammeV1.json'=@($history,$successorHost,$exporter,$script:MIR4HistoricalToolingMigrationReceiptPath)
    '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json'=@($history,$successorHost)
    'tools/mir.ps1'=@($exporter,'tools/mir/cli/Invoke-MIR4HistoricalToolingMigration.ps1')
    'docs/architecture/mir4-historical-succession.md'=@('tools/mir/application/history','tools/mir/cli/Export-MIR4HistoricalSuccessionRecords.ps1')
    'docs/architecture/module-boundaries.md'=@('tools/mir/application/history')
  }
  foreach($entry in $requirements.GetEnumerator()){$text=[IO.File]::ReadAllText((Join-Path $repo ([string]$entry.Key))).Replace('\','/');foreach($required in @($entry.Value)){if($text-cnotmatch[regex]::Escape([string]$required)){throw "[mir4-historical-tooling-consumer-final-path] $($entry.Key) -> $required"}}}
  return $true
}

function Get-MIR4HistoricalToolingFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $source=[pscustomobject][ordered]@{commit='rfp10-functional-probe';tree='rfp10-functional-probe'}
  $identity=New-MIR4W09SourceIdentity -RepoRoot $repo -SourceIdentity $source
  $authority=Get-MIR4W09Authority -RepoRoot $repo
  $witness=[pscustomobject][ordered]@{kind='MIR4PackageSuccessionWitnessV1';digest='sha256:611a5a2c8f276ab6c0a710ea71a82fcba92fe079a29195a85921048c4d8b66e2';append_only=$true;prior_release_evidence_mutated=$false}
  $archive=Write-MIR4W09SyntheticArchive -RepoRoot $repo -OutputPath (Join-Path $repo 'build/results/assurance/rfp10-functional-probe/synthetic-successor.zip')
  $archiveContent=Get-MIR4W09SyntheticArchiveContentIdentity -ArchivePath (Join-Path $repo ([string]$archive.path))
  if([int]$archiveContent.entry_count-ne[int]$archive.entry_count-or[string]$archiveContent.content_sha256-cne$script:MIR4HistoricalToolingArchiveContentSha256V1){throw '[mir4-historical-tooling-archive-content]'}
  $descriptor=Get-MIR4W09InputDescriptor -RepoRoot $repo -RelativePath 'fixtures/mir4-historical-succession-v1/reconstruction/manifest.json'
  $recordHash=Get-MIR4W09RecordSha256 -Record ([pscustomobject][ordered]@{kind='MIR4HistoricalToolingFunctionalProbeV1';schema=1;alpha='stable';nested=[ordered]@{z=2;a=1};record_sha256=''})
  $record=[pscustomobject][ordered]@{
    kind='MIR4HistoricalToolingFunctionalProbeV1';schema=1
    authority=[ordered]@{programme_id=[string]$authority.programme_id;historical_target_count=@($authority.historical_targets).Count;museum_target_count=@($authority.museum_targets).Count;package_visible=[bool]$authority.package_visible;prototype_write_authorized=[bool]$authority.prototype_write_authorized;publication_authorized=[bool]$authority.publication_authorized}
    source_identity=$identity
    succession=[ordered]@{kind=[string]$witness.kind;digest=[string]$witness.digest;append_only=[bool]$witness.append_only;prior_release_evidence_mutated=[bool]$witness.prior_release_evidence_mutated}
    archive=[ordered]@{content_sha256=[string]$archiveContent.content_sha256;entry_count=[int]$archiveContent.entry_count;uncompressed_bytes=[long]$archiveContent.uncompressed_bytes}
    fixture_descriptor=$descriptor
    record_hash=$recordHash
    sensitive=[ordered]@{negative=(Test-MIR4W09SensitivePropertyName -Value ([pscustomobject]@{public='ok'}));positive=(Test-MIR4W09SensitivePropertyName -Value ([pscustomobject]@{private_signing_material='blocked'}))}
  }
  $json=ConvertTo-MIR4PlatformCanonicalJson $record
  $digest='sha256:'+([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($json))).ToLowerInvariant())
  return [pscustomobject][ordered]@{record=$record;digest=$digest}
}

function Test-MIR4HistoricalToolingFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $result=Get-MIR4HistoricalToolingFunctionalParityV1 -RepoRoot $RepoRoot
  if([string]$result.digest-cne$script:MIR4HistoricalToolingParityDigestV1-or[int]$result.record.authority.historical_target_count-ne6-or[int]$result.record.authority.museum_target_count-ne7-or-not[bool]$result.record.sensitive.positive-or[bool]$result.record.sensitive.negative){throw "[mir4-historical-tooling-functional-parity] $([string]$result.digest)"}
  return $result
}

function New-MIR4HistoricalToolingMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$migration=Get-MIR4HistoricalToolingMigrationAuthorityV1 -RepoRoot $repo;$proof=Get-MIR4HistoricalToolingMigrationProofPolicyV1 -RepoRoot $repo
  $prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration
  [void](Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4HistoricalToolingPredecessorReceiptPath -ExpectedSha256 $script:MIR4HistoricalToolingPredecessorReceiptSha256 -SchemaPath 'contracts/repository/mir4-assurance-offline-custody-migration-receipt-v1.schema.json' -Kind 'MIR4AssuranceOfflineCustodyMigrationReceiptV1' -DigestDomain 'mir4:assurance-offline-custody-migration-receipt:1' -ErrorPrefix 'mir4-historical-tooling-predecessor')
  [void](Test-MIR4HistoricalToolingForwardersV1 -RepoRoot $repo);[void](Test-MIR4HistoricalToolingDeclaredConsumersV1 -RepoRoot $repo);[void](Test-MIR4HistoricalToolingFunctionalParityV1 -RepoRoot $repo)
  if((Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash-cne$script:MIR4HistoricalToolingCompatibilityPolicySha256){throw '[mir4-historical-tooling-compatibility-policy-mutated]'}
  if((Get-FileHash -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T14-Authority-Evolution-ReceiptV1.json') -Algorithm SHA256).Hash-cne$script:MIR4HistoricalToolingT14ReceiptSha256){throw '[mir4-historical-tooling-t14-receipt-mutated]'}
  if((Get-FileHash -LiteralPath (Join-Path $repo 'tools/lib/mir4/ReleaseDag.ps1') -Algorithm SHA256).Hash-cne$script:MIR4HistoricalToolingReleaseDagSha256){throw '[mir4-historical-tooling-release-dag-mutated]'}
  $programme=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/releases/waves/mir4-r0/MIR4-Historical-Succession-ProgrammeV1.json'
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path '.mir/releases/waves/mir4-r0/MIR4-Historical-Succession-ProgrammeV1.json' -SchemaPath 'spec/schemas/mir4-historical-succession-programme-v1.schema.json')){throw '[mir4-historical-tooling-programme-schema]'}
  $programmePath=Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Historical-Succession-ProgrammeV1.json';$programmeSchemaPath=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $programmePath) ([string]$programme.'$schema')));if($programmeSchemaPath-cne[IO.Path]::GetFullPath((Join-Path $repo 'spec/schemas/mir4-historical-succession-programme-v1.schema.json'))){throw '[mir4-historical-tooling-programme-schema-uri]'}
  $bootstrapProfile=@((Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path '.mir/assurance.json').profiles.'mir4-bootstrap');foreach($testId in @('static.mir4-historical-tooling-v1','static.mir4-historical-tooling-migration-v1')){if($testId-notin$bootstrapProfile){throw "[mir4-historical-tooling-bootstrap-profile] $testId"}}
  foreach($flag in @('package_visible','semantic_authority','target_policy_authority','museum_admission_authority','rights_or_custody_authority','player_package_mutation_authorized','prototype_write_authorized','runtime_state_mutation_authorized','migration_execution_authorized','source_freeze_authorized','production_signing_or_sealing_authorized','promotion_or_tag_authorized','network_or_upload_authorized','publication_authorized')){if([bool]$programme.$flag){throw "[mir4-historical-tooling-authority-firewall] $flag"}}
  $integrationPaths=@(
    '.gitattributes','.mir/assurance.json','.mir/control/repository-fixed-point.json','.mir/control/paths.yml','.mir/control-plane/ownership.json','.mir/modules.yml','.mir/docs.yml',
    '.mir/releases/waves/mir4-r0/MIR4-Historical-Succession-ProgrammeV1.json','.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json',
    'assurance/.mir-root.json','governance/.mir-root.json','tests/.mir-root.json','validation/tests.yml','tools/mir.ps1','mir.lock','spec/schemas/mir4-historical-succession-programme-v1.schema.json',
    'tools/mir/application/history/HistoricalToolingMigration.ps1','tools/mir/cli/Invoke-MIR4HistoricalToolingMigration.ps1',
    'tools/lib/mir4/PlatformPreview.ps1','tools/lib/mir4/PreFreezeRelease.ps1','tools/lib/assurance/Evidence.ps1',
    'validation/tests/mir4/Test-MIR4HistoricalSuccessionW09.ps1','validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1','validation/tests/tooling/Test-MIRAssurance.ps1',
    'docs/architecture/mir4-repository-fixed-point.md','docs/architecture/mir4-historical-succession.md','docs/architecture/module-boundaries.md','docs/reference/generated/mir4-platform-component-matrix.md','docs/reference/generated/mir4-whole-platform-matrix.md','docs/releases/mir4-4.0-whole-platform-programme.md',
    'tools/mir/application/assurance/AssuranceOfflineCustodyMigration.ps1','tools/mir/cli/Invoke-MIR4AssuranceOfflineCustodyMigration.ps1','tests/assurance/Test-MIR4AssuranceOfflineCustodyMigration.ps1',
    'tools/mir/domain/repository/RepositoryFixedPoint.ps1','tests/repository/Test-MIR4RepositoryFixedPoint.ps1'
  )
  $parity=[ordered]@{canonical_writer_count=@($migration.writers).Count;shared_migration_engine=$true;compatibility_forwarders_verified=$true;historical_functional_parity=$true;historical_export_command_parity=$true;declared_consumers_use_final_paths=$true;focused_test_registered=$true;compatibility_policy_read_only=$true;historical_t14_evidence_read_only=$true;release_dag_read_only=$true;player_runtime_authority_read_only=$true;predecessor_writer_disabled=$true;release_history_successor_verified=$true;release_history_fingerprint_bound=$true;authority_schema_verified=$true;assurance_schema_verified=$true;rollback_recorded=(-not[string]::IsNullOrWhiteSpace([string]$migration.rollback.command));duplicate_writers=@()}
  return New-MIR4AppendOnlyAuthorityMigrationReceiptV1 -RepoRoot $repo -Migration $migration -Proof $proof -Prior $prior -ReceiptKind 'MIR4HistoricalToolingMigrationReceiptV1' -ReceiptState 'HISTORICAL-SUCCESSION-APPLICATION-CLI-AND-TEST-CUTOVER-VERIFIED-COMPATIBILITY-RETAINED' -ReceiptPath $script:MIR4HistoricalToolingMigrationReceiptPath -MigrationAuthorityPath $script:MIR4HistoricalToolingMigrationAuthorityPath -AssurancePath $script:MIR4HistoricalToolingMigrationProofPath -Scope 'package-excluded-historical-tooling-migration' -EvolutionReason 'Package-excluded W09 historical-succession and successor-host tooling migration with ReleaseDag, compatibility policy, immutable T14 evidence, player-runtime, and release-authority firewalls.' -DigestDomain 'mir4:historical-tooling-migration-receipt:1' -Parity $parity -IntegrationPaths $integrationPaths
}

function Get-MIR4HistoricalToolingMigrationReceiptTextV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (ConvertTo-MIR4CanonicalJsonV1 -Value (New-MIR4HistoricalToolingMigrationReceiptV1 -RepoRoot $RepoRoot))+[char]10
}

function Invoke-MIR4HistoricalToolingMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$path=Join-Path $repo $script:MIR4HistoricalToolingMigrationReceiptPath;$text=Get-MIR4HistoricalToolingMigrationReceiptTextV1 -RepoRoot $repo
  if($Check){if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or[IO.File]::ReadAllText($path)-cne$text){throw '[mir4-historical-tooling-migration-receipt-stale]'};if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4HistoricalToolingMigrationReceiptPath -SchemaPath $script:MIR4HistoricalToolingMigrationReceiptSchemaPath)){throw '[mir4-historical-tooling-migration-receipt-schema]'}}else{New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent)|Out-Null;[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))}
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4HistoricalToolingMigrationReceiptPath
}
