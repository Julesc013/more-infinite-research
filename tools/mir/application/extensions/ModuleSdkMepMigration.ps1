. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot '../runtime/RuntimeContinuityMigration.ps1')
. (Join-Path $PSScriptRoot '../../../lib/mir4/PlatformPreview.ps1')

$script:MIR4ModuleSdkMepMigrationAuthorityPath='governance/repository/migrations/module-sdk-mep-tooling-v1.json'
$script:MIR4ModuleSdkMepMigrationAuthoritySchemaPath='contracts/repository/mir4-module-sdk-mep-migration-authority-v1.schema.json'
$script:MIR4ModuleSdkMepMigrationProofPath='assurance/repository/module-sdk-mep-tooling-v1.json'
$script:MIR4ModuleSdkMepMigrationProofSchemaPath='contracts/repository/mir4-module-sdk-mep-migration-proof-v1.schema.json'
$script:MIR4ModuleSdkMepMigrationReceiptPath='releases/migrations/MIR4-Module-Sdk-Mep-Tooling-MigrationV1.json'
$script:MIR4ModuleSdkMepMigrationReceiptSchemaPath='contracts/repository/mir4-module-sdk-mep-migration-receipt-v1.schema.json'
$script:MIR4ModuleSdkMepPredecessorReceiptPath='releases/migrations/MIR4-Runtime-Continuity-Tooling-MigrationV1.json'
$script:MIR4ModuleSdkMepPredecessorReceiptSha256='731091D00E0ABA7E7E07E736E0C5299D45FAE588421A953E401310B2ACCBDC78'
$script:MIR4ModuleSdkMepPreCutoverDigestV1='sha256:5f813a132879013c1d3682ed78ac34e454d2d9c88cab6ec866f3adb31307d284'
$script:MIR4ModuleSdkMepParityDigestV1='sha256:11b21f03ae7839e0b555dc0604b5d02413d7c11dc023be25cf975dff6c448050'

function Get-MIR4ModuleSdkMepMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4ModuleSdkMepMigrationAuthorityPath -SchemaPath $script:MIR4ModuleSdkMepMigrationAuthoritySchemaPath)){throw '[mir4-module-sdk-mep-migration-authority-schema]'}
  $authority=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4ModuleSdkMepMigrationAuthorityPath
  if([string]$authority.predecessor_receipt.path-cne$script:MIR4ModuleSdkMepPredecessorReceiptPath-or[string]$authority.predecessor_receipt.sha256-cne$script:MIR4ModuleSdkMepPredecessorReceiptSha256){throw '[mir4-module-sdk-mep-migration-predecessor-authority]'}
  if(@($authority.writers).Count-ne1-or[string]$authority.writers[0].path-cne'tools/mir/application/extensions/ModuleSdkMepMigration.ps1'){throw '[mir4-module-sdk-mep-migration-single-writer]'}
  $finalPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path})
  if(@($finalPaths|Sort-Object -Unique).Count-ne$finalPaths.Count){throw '[mir4-module-sdk-mep-migration-duplicate-final-path]'}
  if(@($authority.release_transition_authority.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-module-sdk-mep-migration-release-authority]'}
  return $authority
}

function Get-MIR4ModuleSdkMepMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4ModuleSdkMepMigrationProofPath -SchemaPath $script:MIR4ModuleSdkMepMigrationProofSchemaPath)){throw '[mir4-module-sdk-mep-migration-proof-schema]'}
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4ModuleSdkMepMigrationProofPath
}

function Test-MIR4ModuleSdkMepCompatibilityForwardersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $bindings=@(
    @{path='tools/lib/mir4/ModuleEcosystem.ps1';target='mir/application/extensions/ModuleEcosystem.ps1';max=3},
    @{path='tools/lib/mir4/ExperimentalApiSdk.ps1';target='mir/application/extensions/ExperimentalApiSdk.ps1';max=3},
    @{path='tools/lib/mir4/ExtensionDeveloperExperience.ps1';target='mir/application/extensions/ExtensionDeveloperExperience.ps1';max=3},
    @{path='tools/lib/mir4/MepDiscovery.ps1';target='mir/application/extensions/MepDiscovery.ps1';max=3},
    @{path='tools/lib/mir4/SdkV1.ps1';target='mir/application/extensions/SdkV1.ps1';max=3},
    @{path='tools/commands/mir4/Export-MIR4ModuleEcosystemRecords.ps1';target='mir/cli/Export-MIR4ModuleEcosystemRecords.ps1';max=12},
    @{path='tools/commands/mir4/Invoke-MIR4ExperimentalApi.ps1';target='mir/cli/Invoke-MIR4ExperimentalApi.ps1';max=12},
    @{path='tools/commands/mir4/Invoke-MIR4Extension.ps1';target='mir/cli/Invoke-MIR4Extension.ps1';max=22}
  )
  foreach($binding in $bindings){
    $text=[IO.File]::ReadAllText((Join-Path $repo $binding.path)).Replace('\','/')
    if($text-cnotmatch[regex]::Escape([string]$binding.target)-or$text.Split([char]10).Count-gt[int]$binding.max-or$text-match'(?m)^function\s+'){
      throw "[mir4-module-sdk-mep-compatibility-forwarder] $($binding.path)"
    }
  }
  return $true
}

function Test-MIR4ModuleSdkMepDeclaredConsumersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $module='tools/mir/application/extensions/ModuleEcosystem.ps1'
  $api='tools/mir/application/extensions/ExperimentalApiSdk.ps1'
  $dx='tools/mir/application/extensions/ExtensionDeveloperExperience.ps1'
  $discovery='tools/mir/application/extensions/MepDiscovery.ps1'
  $sdk='tools/mir/application/extensions/SdkV1.ps1'
  $exporter='tools/mir/cli/Export-MIR4ModuleEcosystemRecords.ps1'
  $extensionCli='tools/mir/cli/Invoke-MIR4Extension.ps1'
  $apiCli='tools/mir/cli/Invoke-MIR4ExperimentalApi.ps1'
  $requirements=[ordered]@{
    'tools/lib/mir4/PlatformPreview.ps1'=@($module,$api,$discovery)
    'tools/lib/mir4/SupportAssessment.ps1'=@('mir/application/extensions/ModuleEcosystem.ps1')
    'tools/mir.ps1'=@($exporter,$extensionCli,$apiCli,'tools/mir/cli/Invoke-MIR4ModuleSdkMepMigration.ps1')
    'tests/canonicalization/Test-MIR4CanonicalizationDiagnostics.ps1'=@($module,$api)
    'validation/tests/mir4/Test-MIR4ModuleEcosystemW05.ps1'=@($exporter,$extensionCli)
    'validation/tests/mir4/Test-MIR4ExtensionDeveloperExperienceT09.ps1'=@($dx,$extensionCli)
    'validation/tests/mir4/Test-MIR4MepDiscoveryT11.ps1'=@($discovery,$extensionCli)
    'validation/tests/mir4/Test-MIR4ExperimentalApiSdk.ps1'=@($api,$apiCli)
    '.mir/control/paths.yml'=@($module,$api,$dx,$discovery,$sdk,$exporter,$extensionCli,$apiCli)
    '.mir/modules.yml'=@($module,$api,$dx,$discovery,$sdk,$exporter,$extensionCli,$apiCli)
    '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json'=@($module,$exporter,$extensionCli)
    'docs/architecture/mir4-module-ecosystem.md'=@($module,$api,$dx,$discovery,$sdk,$exporter,$extensionCli,$apiCli)
    'docs/architecture/module-boundaries.md'=@($module,$api,$dx,$discovery,$sdk,$exporter,$extensionCli,$apiCli)
  }
  foreach($entry in $requirements.GetEnumerator()){
    $text=[IO.File]::ReadAllText((Join-Path $repo ([string]$entry.Key))).Replace('\','/')
    foreach($required in @($entry.Value)){if($text-cnotmatch[regex]::Escape([string]$required)){throw "[mir4-module-sdk-mep-consumer-final-path] $($entry.Key) -> $required"}}
  }
  return $true
}

function Get-MIR4ModuleSdkMepFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $authority=Get-MIR4ModuleEcosystemAuthority -RepoRoot $repo
  $reference=New-MIR4ReferenceExtensionV1 -RepoRoot $repo
  $transport=New-MIR4TargetTransportPlanV1 -RepoRoot $repo
  $responses=@(foreach($surface in @($authority.api_surfaces)){New-MIR4ApiV1Response -RepoRoot $repo -Surface ([string]$surface) -Target f210 -Items @()})
  $files=Get-MIR4ModuleEcosystemSdkFiles -RepoRoot $repo
  $record=[ordered]@{
    fragment_kind_count=@($authority.fragment_kinds).Count;api_surface_count=@($authority.api_surfaces).Count;transport_count=@($authority.transports).Count;builder_command_count=@($authority.builder_commands).Count
    reference_digest=[string]$reference.digest;transport_digest=[string]$transport.digest;api_response_digests=@($responses|ForEach-Object{[string]$_.digest});generated_file_count=$files.Count
    production_consumer_status=[string]$authority.independent_consumer.status;package_visible=$false;public_support=$false;release_transition_authority=$false
  }
  return [pscustomobject][ordered]@{record=$record;digest=(Get-MIR4CanonicalDigestV1 -Value $record -Domain 'mir4:module-sdk-mep-functional-parity:1')}
}

function Test-MIR4ModuleSdkMepFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $result=Get-MIR4ModuleSdkMepFunctionalParityV1 -RepoRoot $RepoRoot
  $record=$result.record
  if([int]$record.fragment_kind_count-ne12-or[int]$record.api_surface_count-ne9-or[int]$record.transport_count-ne17-or[int]$record.builder_command_count-ne11-or[int]$record.generated_file_count-ne56-or[string]$record.production_consumer_status-cne'BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER'-or[bool]$record.package_visible-or[bool]$record.public_support-or[bool]$record.release_transition_authority){throw '[mir4-module-sdk-mep-functional-shape-parity]'}
  if([string]$result.digest-cne$script:MIR4ModuleSdkMepParityDigestV1){throw "[mir4-module-sdk-mep-functional-parity] $([string]$result.digest)"}
  return $result
}

function New-MIR4ModuleSdkMepMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $migration=Get-MIR4ModuleSdkMepMigrationAuthorityV1 -RepoRoot $repo
  $proof=Get-MIR4ModuleSdkMepMigrationProofPolicyV1 -RepoRoot $repo
  $prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration
  [void](Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4ModuleSdkMepPredecessorReceiptPath -ExpectedSha256 $script:MIR4ModuleSdkMepPredecessorReceiptSha256 -SchemaPath 'contracts/repository/mir4-runtime-continuity-migration-receipt-v1.schema.json' -Kind 'MIR4RuntimeContinuityMigrationReceiptV1' -DigestDomain 'mir4:runtime-continuity-migration-receipt:1' -ErrorPrefix 'mir4-module-sdk-mep-predecessor')
  [void](Test-MIR4ModuleSdkMepCompatibilityForwardersV1 -RepoRoot $repo)
  [void](Test-MIR4ModuleSdkMepDeclaredConsumersV1 -RepoRoot $repo)
  [void](Test-MIR4ModuleSdkMepFunctionalParityV1 -RepoRoot $repo)

  $integrationPaths=@(
    '.gitattributes','.mir/assurance.json','.mir/control/repository-fixed-point.json','.mir/control/paths.yml','.mir/control-plane/ownership.json','.mir/modules.yml','.mir/docs.yml',
    '.mir/releases/waves/mir4-r0/MIR4-Module-Ecosystem-ProgrammeV1.json','.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json',
    'assurance/.mir-root.json','governance/.mir-root.json','tests/.mir-root.json','validation/tests.yml','tools/mir.ps1','mir.lock',
    'tools/lib/mir4/PlatformPreview.ps1','tools/lib/mir4/PreFreezeRelease.ps1','tools/lib/mir4/SupportAssessment.ps1','tools/lib/assurance/Evidence.ps1',
    'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1','tools/mir/application/runtime/RuntimeContinuityMigration.ps1','tools/mir/cli/Invoke-MIR4RuntimeContinuityMigration.ps1','tests/runtime/Test-MIR4RuntimeContinuityMigration.ps1',
    'tools/mir/application/diagnostics/DiagnosticsMigration.ps1','tools/mir/domain/repository/RepositoryFixedPoint.ps1','tests/repository/Test-MIR4RepositoryFixedPoint.ps1','tests/canonicalization/Test-MIR4CanonicalizationDiagnostics.ps1',
    'validation/tests/mir4/Test-MIR4ExperimentalApiSdk.ps1','validation/tests/mir4/Test-MIR4ModuleEcosystemW05.ps1','validation/tests/mir4/Test-MIR4ExtensionDeveloperExperienceT09.ps1','validation/tests/mir4/Test-MIR4MepDiscoveryT11.ps1','validation/tests/mir4/Test-MIR4DocumentationContinuityT14.ps1',
    'validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1','validation/tests/tooling/Test-MIRAssurance.ps1',
    'docs/architecture/mir4-repository-fixed-point.md','docs/architecture/mir4-module-ecosystem.md','docs/architecture/mir4-platform-preview.md','docs/architecture/module-boundaries.md','docs/developer/first-extension.md','docs/developer/v0-to-v1-migration.md',
    'docs/reference/generated/mir4-platform-component-matrix.md','docs/reference/generated/mir4-whole-platform-matrix.md','docs/releases/mir4-4.0-whole-platform-programme.md',
    'sdk/preview/mir4/mep-v1/conformance.ps1','sdk/preview/mir4/mep-v1/migration/Convert-MIR4MepV0ToV1.ps1'
  )
  $parity=[ordered]@{
    canonical_writer_count=@($migration.writers).Count;shared_migration_engine=$true;compatibility_forwarders_verified=$true
    module_sdk_mep_functional_parity=$true;module_export_command_parity=$true;experimental_api_command_parity=$true;extension_builder_command_parity=$true
    declared_consumers_use_final_paths=$true;focused_test_registered=$true;compatibility_policy_read_only=$true;player_runtime_authority_read_only=$true;predecessor_writer_disabled=$true
    independent_production_consumer_blocker_retained=$true;release_history_successor_verified=$true;release_history_fingerprint_bound=$true;authority_schema_verified=$true;assurance_schema_verified=$true
    rollback_recorded=(-not[string]::IsNullOrWhiteSpace([string]$migration.rollback.command));duplicate_writers=@()
  }
  return New-MIR4AppendOnlyAuthorityMigrationReceiptV1 -RepoRoot $repo -Migration $migration -Proof $proof -Prior $prior `
    -ReceiptKind 'MIR4ModuleSdkMepMigrationReceiptV1' `
    -ReceiptState 'MODULE-SDK-MEP-APPLICATION-CLI-AND-TEST-CUTOVER-VERIFIED-COMPATIBILITY-RETAINED' `
    -ReceiptPath $script:MIR4ModuleSdkMepMigrationReceiptPath `
    -MigrationAuthorityPath $script:MIR4ModuleSdkMepMigrationAuthorityPath `
    -AssurancePath $script:MIR4ModuleSdkMepMigrationProofPath `
    -Scope 'package-excluded-module-sdk-mep-migration' `
    -EvolutionReason 'Package-excluded module, SDK, MEP, builder, discovery, deterministic CLI, and focused-test migration with immutable predecessor, player-runtime firewall, and release-history successor proof.' `
    -DigestDomain 'mir4:module-sdk-mep-migration-receipt:1' `
    -Parity $parity -IntegrationPaths $integrationPaths
}

function Get-MIR4ModuleSdkMepMigrationReceiptTextV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (ConvertTo-MIR4CanonicalJsonV1 -Value (New-MIR4ModuleSdkMepMigrationReceiptV1 -RepoRoot $RepoRoot))+[char]10
}

function Invoke-MIR4ModuleSdkMepMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $path=Join-Path $repo $script:MIR4ModuleSdkMepMigrationReceiptPath
  $text=Get-MIR4ModuleSdkMepMigrationReceiptTextV1 -RepoRoot $repo
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or[IO.File]::ReadAllText($path)-cne$text){throw '[mir4-module-sdk-mep-migration-receipt-stale]'}
    if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4ModuleSdkMepMigrationReceiptPath -SchemaPath $script:MIR4ModuleSdkMepMigrationReceiptSchemaPath)){throw '[mir4-module-sdk-mep-migration-receipt-schema]'}
  }else{
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent)|Out-Null
    [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4ModuleSdkMepMigrationReceiptPath
}
