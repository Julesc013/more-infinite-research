. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot '../technology/TechnologyAcceptanceMigration.ps1')
. (Join-Path $PSScriptRoot '../../../lib/mir4/PlatformPreview.ps1')
. (Join-Path $PSScriptRoot 'TargetCompiler.ps1')

$script:MIR4TargetCompilerMigrationAuthorityPath='governance/repository/migrations/target-compiler-tooling-v1.json'
$script:MIR4TargetCompilerMigrationAuthoritySchemaPath='contracts/repository/mir4-target-compiler-migration-authority-v1.schema.json'
$script:MIR4TargetCompilerMigrationProofPath='assurance/repository/target-compiler-tooling-v1.json'
$script:MIR4TargetCompilerMigrationProofSchemaPath='contracts/repository/mir4-target-compiler-migration-proof-v1.schema.json'
$script:MIR4TargetCompilerMigrationReceiptPath='releases/migrations/MIR4-Target-Compiler-Tooling-MigrationV1.json'
$script:MIR4TargetCompilerMigrationReceiptSchemaPath='contracts/repository/mir4-target-compiler-migration-receipt-v1.schema.json'
$script:MIR4TargetCompilerPredecessorReceiptPath='releases/migrations/MIR4-Technology-Acceptance-Tooling-MigrationV1.json'
$script:MIR4TargetCompilerPredecessorReceiptSha256='011AC795CBB9FBC850E5821D367F1D57264DB79A16540694B4AD4771EB38E879'
$script:MIR4TargetCompilerParityDigestV1='sha256:53840ec0d6c45e8c9cab1afd7aaace1ee3e6d2a24ae5adf59ac1c248ec8cde27'

function Get-MIR4TargetCompilerMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4TargetCompilerMigrationAuthorityPath -SchemaPath $script:MIR4TargetCompilerMigrationAuthoritySchemaPath)){
    throw '[mir4-target-compiler-migration-authority-schema]'
  }
  $authority=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4TargetCompilerMigrationAuthorityPath
  if([string]$authority.predecessor_receipt.path-cne$script:MIR4TargetCompilerPredecessorReceiptPath-or
     [string]$authority.predecessor_receipt.sha256-cne$script:MIR4TargetCompilerPredecessorReceiptSha256){throw '[mir4-target-compiler-migration-predecessor-authority]'}
  if(@($authority.writers).Count-ne1-or[string]$authority.writers[0].path-cne'tools/mir/application/targets/TargetCompilerMigration.ps1'){
    throw '[mir4-target-compiler-migration-single-writer]'
  }
  $finalPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path})
  if(@($finalPaths|Sort-Object -Unique).Count-ne$finalPaths.Count){throw '[mir4-target-compiler-migration-duplicate-final-path]'}
  if(@($authority.release_transition_authority.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-target-compiler-migration-release-authority]'}
  return $authority
}

function Get-MIR4TargetCompilerMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4TargetCompilerMigrationProofPath -SchemaPath $script:MIR4TargetCompilerMigrationProofSchemaPath)){
    throw '[mir4-target-compiler-migration-proof-schema]'
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4TargetCompilerMigrationProofPath
}

function Test-MIR4TargetCompilerCompatibilityForwarderV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $path='tools/lib/mir4/TargetCompiler.ps1'
  $text=[IO.File]::ReadAllText((Join-Path $repo $path)).Replace('\','/')
  if($text-cnotmatch'MIR4-TARGET-COMPILER-COMPATIBILITY-LIBRARY'-or
     $text-cnotmatch[regex]::Escape('mir/application/targets/TargetCompiler.ps1')-or
     $text.Split([char]10).Count-gt4){throw "[mir4-target-compiler-compatibility-forwarder] $path"}
  return $true
}

function Test-MIR4TargetCompilerDeclaredConsumersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $canonical='tools/mir/application/targets/TargetCompiler.ps1'
  $bindings=@(
    'tools/lib/mir4/PlatformPreview.ps1',
    'validation/tests/mir4/Test-MIR4TargetCompilerW02.ps1',
    'tools/commands/mir4/Export-MIR4AssuranceScaleRecords.ps1',
    'tests/targets/Test-MIR4TargetCompiler.ps1',
    '.mir/control/paths.yml',
    '.mir/modules.yml',
    'docs/architecture/mir4-target-compiler.md',
    'docs/architecture/module-boundaries.md'
  )
  foreach($path in $bindings){
    $text=[IO.File]::ReadAllText((Join-Path $repo $path)).Replace('\','/')
    if($text-cnotmatch[regex]::Escape($canonical)){throw "[mir4-target-compiler-consumer-final-path] $path"}
  }
  return $true
}

function Get-MIR4TargetCompilerFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $left=New-MIR4TargetContractSet -RepoRoot $repo
  $right=New-MIR4TargetContractSet -RepoRoot $repo
  $laws=Test-MIR4TargetProviderLaws -RepoRoot $repo
  $record=[ordered]@{
    deterministic=((ConvertTo-MIR4PlatformCanonicalJson $left)-ceq(ConvertTo-MIR4PlatformCanonicalJson $right))
    contract_set_digest=[string]$left.digest
    law_result_digest=[string]$laws.digest
    targets=@($left.targets|ForEach-Object{[string]$_.target})
    laws=@($laws.targets[0].laws|ForEach-Object{[string]$_})
    law_target_count=@($laws.targets).Count
    laws_passed=[bool]$laws.passed
    authoritative_output=[bool]$left.authoritative_output
    mutation_capability=[bool]$left.mutation_capability
    publication_authorized=[bool]$left.publication_authorized
  }
  return [pscustomobject][ordered]@{record=$record;digest=(Get-MIR4CanonicalDigestV1 -Value $record -Domain 'mir4:target-compiler-functional-parity:1')}
}

function Test-MIR4TargetCompilerFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $result=Get-MIR4TargetCompilerFunctionalParityV1 -RepoRoot $RepoRoot
  if(-not[bool]$result.record.deterministic-or-not[bool]$result.record.laws_passed-or
     [int]$result.record.law_target_count-ne17-or@($result.record.targets).Count-ne17-or@($result.record.laws).Count-ne9-or
     [bool]$result.record.authoritative_output-or[bool]$result.record.mutation_capability-or[bool]$result.record.publication_authorized){
    throw '[mir4-target-compiler-functional-shape-parity]'
  }
  if([string]$result.digest-cne$script:MIR4TargetCompilerParityDigestV1){throw "[mir4-target-compiler-functional-parity] $([string]$result.digest)"}
  return $result
}

function New-MIR4TargetCompilerMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $migration=Get-MIR4TargetCompilerMigrationAuthorityV1 -RepoRoot $repo
  $proof=Get-MIR4TargetCompilerMigrationProofPolicyV1 -RepoRoot $repo
  $prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration
  [void](Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4TargetCompilerPredecessorReceiptPath `
    -ExpectedSha256 $script:MIR4TargetCompilerPredecessorReceiptSha256 `
    -SchemaPath 'contracts/repository/mir4-technology-acceptance-migration-receipt-v1.schema.json' `
    -Kind 'MIR4TechnologyAcceptanceMigrationReceiptV1' `
    -DigestDomain 'mir4:technology-acceptance-migration-receipt:1' `
    -ErrorPrefix 'mir4-target-compiler-predecessor')
  [void](Test-MIR4TargetCompilerCompatibilityForwarderV1 -RepoRoot $repo)
  [void](Test-MIR4TargetCompilerDeclaredConsumersV1 -RepoRoot $repo)
  [void](Test-MIR4TargetCompilerFunctionalParityV1 -RepoRoot $repo)

  $integrationPaths=@(
    '.gitattributes','.mir/assurance.json','.mir/control/repository-fixed-point.json','.mir/control/paths.yml',
    '.mir/control-plane/ownership.json','.mir/modules.yml','.mir/releases/waves/mir4-r0/MIR4-Target-Compiler-ProgrammeV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Semantic-Compiler-ProgrammeV1.json','.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json',
    'assurance/.mir-root.json','governance/.mir-root.json','tests/.mir-root.json','validation/tests.yml','tools/mir.ps1',
    'tools/lib/mir4/PreFreezeRelease.ps1','tools/lib/mir4/PlatformPreview.ps1','tools/lib/assurance/Evidence.ps1',
    'tools/commands/mir4/Export-MIR4AssuranceScaleRecords.ps1','validation/tests/mir4/Test-MIR4TargetCompilerW02.ps1',
    'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1','tools/mir/application/technology/TechnologyAcceptanceMigration.ps1',
    'tools/mir/cli/Invoke-MIR4TechnologyAcceptanceMigration.ps1','tests/technology/Test-MIR4TechnologyAcceptanceMigration.ps1',
    'tools/mir/domain/repository/RepositoryFixedPoint.ps1','tests/repository/Test-MIR4RepositoryFixedPoint.ps1',
    'validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1','validation/tests/tooling/Test-MIRAssurance.ps1',
    'docs/architecture/mir4-repository-fixed-point.md','docs/architecture/mir4-target-compiler.md','docs/architecture/module-boundaries.md',
    'docs/reference/generated/mir4-whole-platform-matrix.md','docs/releases/mir4-4.0-whole-platform-programme.md',
    'mir.lock','sdk/preview/mir4/reference/compilation-runs.json','sdk/preview/mir4/reference/merge-law-catalogue.json',
    'sdk/preview/mir4/reference/query-snapshot-f210.json','sdk/preview/mir4/reference/target-contracts.json',
    'sdk/preview/mir4/reference/target-provider-law-results.json'
  )
  $parity=[ordered]@{
    canonical_writer_count=@($migration.writers).Count
    shared_migration_engine=$true
    compatibility_forwarder_verified=$true
    target_compiler_function_parity=$true
    declared_consumers_use_final_path=$true
    focused_test_registered=$true
    predecessor_writer_disabled=$true
    release_history_successor_verified=$true
    release_history_fingerprint_bound=$true
    authority_schema_verified=$true
    assurance_schema_verified=$true
    rollback_recorded=(-not[string]::IsNullOrWhiteSpace([string]$migration.rollback.command))
    duplicate_writers=@()
  }
  return New-MIR4AppendOnlyAuthorityMigrationReceiptV1 -RepoRoot $repo -Migration $migration -Proof $proof -Prior $prior `
    -ReceiptKind 'MIR4TargetCompilerMigrationReceiptV1' `
    -ReceiptState 'TARGET-COMPILER-APPLICATION-AND-TEST-CUTOVER-VERIFIED-COMPATIBILITY-RETAINED' `
    -ReceiptPath $script:MIR4TargetCompilerMigrationReceiptPath `
    -MigrationAuthorityPath $script:MIR4TargetCompilerMigrationAuthorityPath `
    -AssurancePath $script:MIR4TargetCompilerMigrationProofPath `
    -Scope 'package-excluded-target-compiler-migration' `
    -EvolutionReason 'Package-excluded target-compiler application and focused test migration with immutable predecessor and release-history successor proof.' `
    -DigestDomain 'mir4:target-compiler-migration-receipt:1' `
    -Parity $parity -IntegrationPaths $integrationPaths
}

function Get-MIR4TargetCompilerMigrationReceiptTextV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (ConvertTo-MIR4CanonicalJsonV1 -Value (New-MIR4TargetCompilerMigrationReceiptV1 -RepoRoot $RepoRoot))+[char]10
}

function Invoke-MIR4TargetCompilerMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $path=Join-Path $repo $script:MIR4TargetCompilerMigrationReceiptPath
  $text=Get-MIR4TargetCompilerMigrationReceiptTextV1 -RepoRoot $repo
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or[IO.File]::ReadAllText($path)-cne$text){throw '[mir4-target-compiler-migration-receipt-stale]'}
    if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4TargetCompilerMigrationReceiptPath -SchemaPath $script:MIR4TargetCompilerMigrationReceiptSchemaPath)){
      throw '[mir4-target-compiler-migration-receipt-schema]'
    }
  }else{
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent)|Out-Null
    [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4TargetCompilerMigrationReceiptPath
}
