. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot '../compiler/SemanticCompilerPolicyMigration.ps1')
. (Join-Path $PSScriptRoot '../../../lib/mir4/PlatformPreview.ps1')

$script:MIR4RuntimeContinuityMigrationAuthorityPath='governance/repository/migrations/runtime-continuity-tooling-v1.json'
$script:MIR4RuntimeContinuityMigrationAuthoritySchemaPath='contracts/repository/mir4-runtime-continuity-migration-authority-v1.schema.json'
$script:MIR4RuntimeContinuityMigrationProofPath='assurance/repository/runtime-continuity-tooling-v1.json'
$script:MIR4RuntimeContinuityMigrationProofSchemaPath='contracts/repository/mir4-runtime-continuity-migration-proof-v1.schema.json'
$script:MIR4RuntimeContinuityMigrationReceiptPath='releases/migrations/MIR4-Runtime-Continuity-Tooling-MigrationV1.json'
$script:MIR4RuntimeContinuityMigrationReceiptSchemaPath='contracts/repository/mir4-runtime-continuity-migration-receipt-v1.schema.json'
$script:MIR4RuntimeContinuityPredecessorReceiptPath='releases/migrations/MIR4-Semantic-Compiler-Policy-Tooling-MigrationV1.json'
$script:MIR4RuntimeContinuityPredecessorReceiptSha256='A1F7B204B839C6425D37EDB34208B0F37FBEA0DC40E1FE45658CED78DC53C5C9'
$script:MIR4RuntimeContinuityParityDigestV1='sha256:5913a0d3fa7746af872bbdaa67e7f3b45bdfc82391522922f25fcc14028b45df'

function Get-MIR4RuntimeContinuityMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4RuntimeContinuityMigrationAuthorityPath -SchemaPath $script:MIR4RuntimeContinuityMigrationAuthoritySchemaPath)){throw '[mir4-runtime-continuity-migration-authority-schema]'}
  $authority=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4RuntimeContinuityMigrationAuthorityPath
  if([string]$authority.predecessor_receipt.path-cne$script:MIR4RuntimeContinuityPredecessorReceiptPath-or[string]$authority.predecessor_receipt.sha256-cne$script:MIR4RuntimeContinuityPredecessorReceiptSha256){throw '[mir4-runtime-continuity-migration-predecessor-authority]'}
  if(@($authority.writers).Count-ne1-or[string]$authority.writers[0].path-cne'tools/mir/application/runtime/RuntimeContinuityMigration.ps1'){throw '[mir4-runtime-continuity-migration-single-writer]'}
  $finalPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path})
  if(@($finalPaths|Sort-Object -Unique).Count-ne$finalPaths.Count){throw '[mir4-runtime-continuity-migration-duplicate-final-path]'}
  if(@($authority.release_transition_authority.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-runtime-continuity-migration-release-authority]'}
  return $authority
}

function Get-MIR4RuntimeContinuityMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4RuntimeContinuityMigrationProofPath -SchemaPath $script:MIR4RuntimeContinuityMigrationProofSchemaPath)){throw '[mir4-runtime-continuity-migration-proof-schema]'}
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4RuntimeContinuityMigrationProofPath
}

function Test-MIR4RuntimeContinuityCompatibilityForwardersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $bindings=@(
    @{path='tools/lib/mir4/RuntimeStateModel.ps1';marker='MIR4-RUNTIME-CONTINUITY-COMPATIBILITY-LIBRARY';target='mir/application/runtime/RuntimeStateModel.ps1';max=4},
    @{path='tools/commands/mir4/Export-MIR4RuntimeContinuityRecords.ps1';marker='MIR4-RUNTIME-CONTINUITY-COMPATIBILITY-COMMAND';target='tools/mir/cli/Export-MIR4RuntimeContinuityRecords.ps1';max=12}
  )
  foreach($binding in $bindings){
    $text=[IO.File]::ReadAllText((Join-Path $repo $binding.path)).Replace('\','/')
    if($text-cnotmatch[regex]::Escape([string]$binding.marker)-or$text-cnotmatch[regex]::Escape([string]$binding.target)-or$text.Split([char]10).Count-gt[int]$binding.max-or$text-match'(?m)^function\s+'){
      throw "[mir4-runtime-continuity-compatibility-forwarder] $($binding.path)"
    }
  }
  return $true
}

function Test-MIR4RuntimeContinuityDeclaredConsumersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $application='tools/mir/application/runtime/RuntimeStateModel.ps1'
  $exporter='tools/mir/cli/Export-MIR4RuntimeContinuityRecords.ps1'
  $requirements=[ordered]@{
    'tools/lib/mir4/PlatformPreview.ps1'=@($application)
    'tools/mir.ps1'=@($exporter,'tools/mir/cli/Invoke-MIR4RuntimeContinuityMigration.ps1')
    'validation/tests/mir4/Test-MIR4RuntimeContinuityW04.ps1'=@($exporter)
    '.mir/control/paths.yml'=@($application,$exporter)
    '.mir/modules.yml'=@($application,$exporter)
    '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json'=@($application)
    'docs/architecture/mir4-runtime-continuity.md'=@($application,$exporter)
    'docs/architecture/mir4-platform-preview.md'=@($application)
    'docs/architecture/module-boundaries.md'=@($application,$exporter)
  }
  foreach($entry in $requirements.GetEnumerator()){
    $text=[IO.File]::ReadAllText((Join-Path $repo ([string]$entry.Key))).Replace('\','/')
    foreach($required in @($entry.Value)){if($text-cnotmatch[regex]::Escape([string]$required)){throw "[mir4-runtime-continuity-consumer-final-path] $($entry.Key) -> $required"}}
  }
  return $true
}

function Get-MIR4RuntimeContinuityFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $providers=@(New-MIR4NormalizedTargetProviders -RepoRoot $repo)
  $runtime=New-MIR4RuntimeStateMatrix -RepoRoot $repo -Providers $providers -SourceIdentity $null
  $migration=New-MIR4MigrationGraphMatrix -RepoRoot $repo -Providers $providers -SourceIdentity $null
  $continuity=New-MIR4ContinuityBundle -RepoRoot $repo -Providers $providers -SourceIdentity $null -CandidateZip $null -RuntimeStateMatrix $runtime -MigrationGraphMatrix $migration
  $record=[ordered]@{
    target_count=$providers.Count;runtime_digest=[string]$runtime.digest;migration_digest=[string]$migration.digest;continuity_digest=[string]$continuity.digest
    feature_count=@($runtime.runtime_feature_specs).Count;state_count=@($runtime.state_specs).Count;registration_group_count=@($runtime.registration_plan.groups).Count;migration_edge_count=@($migration.edges).Count
    runtime_laws_passed=[bool]$runtime.registration_plan.law_results.all_passed;migration_laws_passed=[bool]$migration.law_results.all_passed
    package_visible=[bool]$runtime.package_visible-or[bool]$migration.package_visible-or[bool]$continuity.package_visible
    runtime_mutation_authorized=[bool]$runtime.runtime_mutation_authorized-or[bool]$continuity.runtime_mutation_authorized
    migration_execution_authorized=[bool]$migration.migration_execution_authorized
    public_release_proof=[bool]$runtime.public_release_proof-or[bool]$migration.public_release_proof-or[bool]$continuity.public_release_proof
  }
  return [pscustomobject][ordered]@{record=$record;digest=(Get-MIR4CanonicalDigestV1 -Value $record -Domain 'mir4:runtime-continuity-functional-parity:1')}
}

function Test-MIR4RuntimeContinuityFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $result=Get-MIR4RuntimeContinuityFunctionalParityV1 -RepoRoot $RepoRoot
  $record=$result.record
  if([int]$record.target_count-ne17-or[int]$record.feature_count-ne7-or[int]$record.state_count-ne5-or[int]$record.registration_group_count-ne9-or[int]$record.migration_edge_count-ne10-or-not[bool]$record.runtime_laws_passed-or-not[bool]$record.migration_laws_passed-or[bool]$record.package_visible-or[bool]$record.runtime_mutation_authorized-or[bool]$record.migration_execution_authorized-or[bool]$record.public_release_proof){throw '[mir4-runtime-continuity-functional-shape-parity]'}
  if([string]$result.digest-cne$script:MIR4RuntimeContinuityParityDigestV1){throw "[mir4-runtime-continuity-functional-parity] $([string]$result.digest)"}
  return $result
}

function New-MIR4RuntimeContinuityMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $migration=Get-MIR4RuntimeContinuityMigrationAuthorityV1 -RepoRoot $repo
  $proof=Get-MIR4RuntimeContinuityMigrationProofPolicyV1 -RepoRoot $repo
  $prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration
  [void](Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4RuntimeContinuityPredecessorReceiptPath `
    -ExpectedSha256 $script:MIR4RuntimeContinuityPredecessorReceiptSha256 `
    -SchemaPath 'contracts/repository/mir4-semantic-compiler-policy-migration-receipt-v1.schema.json' `
    -Kind 'MIR4SemanticCompilerPolicyMigrationReceiptV1' `
    -DigestDomain 'mir4:semantic-compiler-policy-migration-receipt:1' `
    -ErrorPrefix 'mir4-runtime-continuity-predecessor')
  [void](Test-MIR4RuntimeContinuityCompatibilityForwardersV1 -RepoRoot $repo)
  [void](Test-MIR4RuntimeContinuityDeclaredConsumersV1 -RepoRoot $repo)
  [void](Test-MIR4RuntimeContinuityFunctionalParityV1 -RepoRoot $repo)

  $integrationPaths=@(
    '.gitattributes','.mir/assurance.json','.mir/control/repository-fixed-point.json','.mir/control/paths.yml','.mir/control-plane/ownership.json','.mir/modules.yml',
    '.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json','.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json',
    'assurance/.mir-root.json','governance/.mir-root.json','tests/.mir-root.json','validation/tests.yml','tools/mir.ps1','mir.lock',
    'tools/lib/mir4/PlatformPreview.ps1','tools/lib/mir4/PreFreezeRelease.ps1','tools/lib/assurance/Evidence.ps1',
    'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1','tools/mir/application/compiler/SemanticCompilerPolicyMigration.ps1','tools/mir/cli/Invoke-MIR4SemanticCompilerPolicyMigration.ps1','tests/compiler/Test-MIR4SemanticCompilerMigration.ps1',
    'tools/mir/domain/repository/RepositoryFixedPoint.ps1','tests/repository/Test-MIR4RepositoryFixedPoint.ps1',
    'validation/tests/mir4/Test-MIR4RuntimeContinuityW04.ps1','validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1','validation/tests/tooling/Test-MIRAssurance.ps1',
    'docs/architecture/mir4-repository-fixed-point.md','docs/architecture/mir4-runtime-continuity.md','docs/architecture/mir4-platform-preview.md','docs/architecture/module-boundaries.md',
    'docs/reference/generated/mir4-platform-component-matrix.md','docs/reference/generated/mir4-whole-platform-matrix.md','docs/releases/mir4-4.0-whole-platform-programme.md',
    'sdk/preview/mir4/reference/runtime-state-inventory.json','sdk/preview/mir4/reference/migration-graph-matrix.json','sdk/preview/mir4/reference/continuity-bundle-template.json',
    'spec/schemas/mir4-runtime-state-matrix-v1.schema.json','spec/schemas/mir4-migration-graph-matrix-v1.schema.json','spec/schemas/mir4-continuity-bundle-v1.schema.json'
  )
  $parity=[ordered]@{
    canonical_writer_count=@($migration.writers).Count;shared_migration_engine=$true;compatibility_forwarders_verified=$true
    runtime_continuity_function_parity=$true;runtime_export_command_parity=$true;declared_consumers_use_final_paths=$true;focused_test_registered=$true
    compatibility_policy_read_only=$true;player_runtime_authority_read_only=$true;predecessor_writer_disabled=$true
    release_history_successor_verified=$true;release_history_fingerprint_bound=$true;authority_schema_verified=$true;assurance_schema_verified=$true
    rollback_recorded=(-not[string]::IsNullOrWhiteSpace([string]$migration.rollback.command));duplicate_writers=@()
  }
  return New-MIR4AppendOnlyAuthorityMigrationReceiptV1 -RepoRoot $repo -Migration $migration -Proof $proof -Prior $prior `
    -ReceiptKind 'MIR4RuntimeContinuityMigrationReceiptV1' `
    -ReceiptState 'RUNTIME-CONTINUITY-APPLICATION-CLI-AND-TEST-CUTOVER-VERIFIED-COMPATIBILITY-RETAINED' `
    -ReceiptPath $script:MIR4RuntimeContinuityMigrationReceiptPath `
    -MigrationAuthorityPath $script:MIR4RuntimeContinuityMigrationAuthorityPath `
    -AssurancePath $script:MIR4RuntimeContinuityMigrationProofPath `
    -Scope 'package-excluded-runtime-continuity-migration' `
    -EvolutionReason 'Package-excluded runtime continuity application, deterministic exporter, and focused-test migration with immutable predecessor, player-runtime firewall, and release-history successor proof.' `
    -DigestDomain 'mir4:runtime-continuity-migration-receipt:1' `
    -Parity $parity -IntegrationPaths $integrationPaths
}

function Get-MIR4RuntimeContinuityMigrationReceiptTextV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (ConvertTo-MIR4CanonicalJsonV1 -Value (New-MIR4RuntimeContinuityMigrationReceiptV1 -RepoRoot $RepoRoot))+[char]10
}

function Invoke-MIR4RuntimeContinuityMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $path=Join-Path $repo $script:MIR4RuntimeContinuityMigrationReceiptPath
  $text=Get-MIR4RuntimeContinuityMigrationReceiptTextV1 -RepoRoot $repo
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or[IO.File]::ReadAllText($path)-cne$text){throw '[mir4-runtime-continuity-migration-receipt-stale]'}
    if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4RuntimeContinuityMigrationReceiptPath -SchemaPath $script:MIR4RuntimeContinuityMigrationReceiptSchemaPath)){throw '[mir4-runtime-continuity-migration-receipt-schema]'}
  }else{
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent)|Out-Null
    [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4RuntimeContinuityMigrationReceiptPath
}
