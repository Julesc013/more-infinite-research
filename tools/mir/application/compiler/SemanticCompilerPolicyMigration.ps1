. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot '../targets/TargetCompilerMigration.ps1')
. (Join-Path $PSScriptRoot '../../../lib/mir4/PlatformPreview.ps1')

$script:MIR4SemanticCompilerPolicyMigrationAuthorityPath='governance/repository/migrations/semantic-compiler-policy-tooling-v1.json'
$script:MIR4SemanticCompilerPolicyMigrationAuthoritySchemaPath='contracts/repository/mir4-semantic-compiler-policy-migration-authority-v1.schema.json'
$script:MIR4SemanticCompilerPolicyMigrationProofPath='assurance/repository/semantic-compiler-policy-tooling-v1.json'
$script:MIR4SemanticCompilerPolicyMigrationProofSchemaPath='contracts/repository/mir4-semantic-compiler-policy-migration-proof-v1.schema.json'
$script:MIR4SemanticCompilerPolicyMigrationReceiptPath='releases/migrations/MIR4-Semantic-Compiler-Policy-Tooling-MigrationV1.json'
$script:MIR4SemanticCompilerPolicyMigrationReceiptSchemaPath='contracts/repository/mir4-semantic-compiler-policy-migration-receipt-v1.schema.json'
$script:MIR4SemanticCompilerPolicyPredecessorReceiptPath='releases/migrations/MIR4-Target-Compiler-Tooling-MigrationV1.json'
$script:MIR4SemanticCompilerPolicyPredecessorReceiptSha256='799232DAFAF72E3A3B4862DFE19667D39BEAE2FAE6118B4F2228EB98A7E41EBC'
$script:MIR4SemanticCompilerPolicyParityDigestV1='sha256:f45cb86141b5a74a7009415dd657295cf959b473d50cbe9bda1fbb7e0c26f893'

function Get-MIR4SemanticCompilerPolicyMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4SemanticCompilerPolicyMigrationAuthorityPath -SchemaPath $script:MIR4SemanticCompilerPolicyMigrationAuthoritySchemaPath)){
    throw '[mir4-semantic-compiler-policy-migration-authority-schema]'
  }
  $authority=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4SemanticCompilerPolicyMigrationAuthorityPath
  if([string]$authority.predecessor_receipt.path-cne$script:MIR4SemanticCompilerPolicyPredecessorReceiptPath-or
     [string]$authority.predecessor_receipt.sha256-cne$script:MIR4SemanticCompilerPolicyPredecessorReceiptSha256){throw '[mir4-semantic-compiler-policy-migration-predecessor-authority]'}
  if(@($authority.writers).Count-ne1-or[string]$authority.writers[0].path-cne'tools/mir/application/compiler/SemanticCompilerPolicyMigration.ps1'){
    throw '[mir4-semantic-compiler-policy-migration-single-writer]'
  }
  $finalPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path})
  if(@($finalPaths|Sort-Object -Unique).Count-ne$finalPaths.Count){throw '[mir4-semantic-compiler-policy-migration-duplicate-final-path]'}
  if(@($authority.release_transition_authority.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-semantic-compiler-policy-migration-release-authority]'}
  return $authority
}

function Get-MIR4SemanticCompilerPolicyMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4SemanticCompilerPolicyMigrationProofPath -SchemaPath $script:MIR4SemanticCompilerPolicyMigrationProofSchemaPath)){
    throw '[mir4-semantic-compiler-policy-migration-proof-schema]'
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4SemanticCompilerPolicyMigrationProofPath
}

function Test-MIR4SemanticCompilerPolicyCompatibilityForwardersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $bindings=@(
    @{path='tools/lib/mir4/SafetyKernel.ps1';marker='MIR4-SAFETY-KERNEL-COMPATIBILITY-LIBRARY';target='mir/domain/safety/SafetyKernel.ps1';max=4},
    @{path='tools/lib/mir4/PolicyEngine.ps1';marker='MIR4-POLICY-ENGINE-COMPATIBILITY-LIBRARY';target='mir/domain/policy/PolicyEngine.ps1';max=4},
    @{path='tools/lib/mir4/NormalizedCompiler.ps1';marker='MIR4-NORMALIZED-COMPILER-COMPATIBILITY-LIBRARY';target='mir/application/compiler/NormalizedCompiler.ps1';max=4},
    @{path='tools/lib/mir4/CompilationRun.ps1';marker='MIR4-COMPILATION-RUN-COMPATIBILITY-LIBRARY';target='mir/application/compiler/CompilationRun.ps1';max=4},
    @{path='tools/commands/mir4/Export-MIR4SemanticCompilerRecords.ps1';marker='MIR4-SEMANTIC-COMPILER-COMPATIBILITY-COMMAND';target='tools/mir/cli/Export-MIR4SemanticCompilerRecords.ps1';max=12}
  )
  foreach($binding in $bindings){
    $text=[IO.File]::ReadAllText((Join-Path $repo $binding.path)).Replace('\','/')
    if($text-cnotmatch[regex]::Escape([string]$binding.marker)-or$text-cnotmatch[regex]::Escape([string]$binding.target)-or
       $text.Split([char]10).Count-gt[int]$binding.max-or$text-match'(?m)^function\s+'){
      throw "[mir4-semantic-compiler-policy-compatibility-forwarder] $($binding.path)"
    }
  }
  return $true
}

function Test-MIR4SemanticCompilerPolicyDeclaredConsumersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $requirements=[ordered]@{
    'tools/lib/mir4/PlatformPreview.ps1'=@('tools/mir/domain/safety/SafetyKernel.ps1','tools/mir/domain/policy/PolicyEngine.ps1','tools/mir/application/compiler/NormalizedCompiler.ps1','tools/mir/application/compiler/CompilationRun.ps1')
    'tools/lib/mir4/ExactProcessIR.ps1'=@('mir/domain/safety/SafetyKernel.ps1')
    'tools/commands/mir4/Export-MIR4ProcessIRSynthesisRecords.ps1'=@('tools/mir/domain/safety/SafetyKernel.ps1')
    'validation/tests/mir4/Test-MIR4SemanticCompilationW03.ps1'=@('tools/mir/cli/Export-MIR4SemanticCompilerRecords.ps1')
    'tools/mir.ps1'=@('tools/mir/cli/Export-MIR4SemanticCompilerRecords.ps1')
    '.mir/control/paths.yml'=@('tools/mir/domain/safety/SafetyKernel.ps1','tools/mir/domain/policy/PolicyEngine.ps1','tools/mir/application/compiler/NormalizedCompiler.ps1','tools/mir/application/compiler/CompilationRun.ps1','tools/mir/cli/Export-MIR4SemanticCompilerRecords.ps1')
    '.mir/modules.yml'=@('tools/mir/domain/safety/SafetyKernel.ps1','tools/mir/domain/policy/PolicyEngine.ps1','tools/mir/application/compiler/NormalizedCompiler.ps1','tools/mir/application/compiler/CompilationRun.ps1','tools/mir/cli/Export-MIR4SemanticCompilerRecords.ps1')
    'docs/architecture/mir4-semantic-compiler.md'=@('tools/mir/domain/safety/SafetyKernel.ps1','tools/mir/domain/policy/PolicyEngine.ps1','tools/mir/application/compiler/NormalizedCompiler.ps1','tools/mir/application/compiler/CompilationRun.ps1','tools/mir/cli/Export-MIR4SemanticCompilerRecords.ps1')
    'docs/architecture/module-boundaries.md'=@('tools/mir/domain/safety/SafetyKernel.ps1','tools/mir/domain/policy/PolicyEngine.ps1','tools/mir/application/compiler/NormalizedCompiler.ps1','tools/mir/application/compiler/CompilationRun.ps1')
  }
  foreach($entry in $requirements.GetEnumerator()){
    $text=[IO.File]::ReadAllText((Join-Path $repo ([string]$entry.Key))).Replace('\','/')
    foreach($required in @($entry.Value)){if($text-cnotmatch[regex]::Escape([string]$required)){throw "[mir4-semantic-compiler-policy-consumer-final-path] $($entry.Key) -> $required"}}
  }
  return $true
}

function Get-MIR4SemanticCompilerPolicyFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $providers=@(New-MIR4NormalizedTargetProviders -RepoRoot $repo)
  $runs=@(New-MIR4NormalizedCompilationRuns -RepoRoot $repo -Providers $providers)
  $protocols=New-MIR4ProviderMicroProtocolMatrix -RepoRoot $repo
  $cutover=New-MIR4FeatureSettingCutoverMatrix -RepoRoot $repo -Providers $providers
  $laws=Test-MIR4SemanticMergeLaws -RepoRoot $repo
  $safe=[pscustomobject][ordered]@{subject='safe';operations=@('data-only-fragment');evidence=@('fixture:safe');requested_disposition='preserve';positive_cycle=$false;proven_bounded=$true;owner_opaque=$false;owner_rewrite=$false}
  $unsafe=[pscustomobject][ordered]@{subject='unsafe';operations=@('prototype-write');evidence=@('fixture:unsafe');requested_disposition='handle';positive_cycle=$false;proven_bounded=$true;owner_opaque=$false;owner_rewrite=$false}
  $safeDecision=Resolve-MIR4PolicyDisposition -Contribution $safe
  $unsafeDecision=Resolve-MIR4PolicyDisposition -Contribution $unsafe
  $record=[ordered]@{
    target_count=$providers.Count
    run_count=$runs.Count
    provider_protocol_count=@($protocols.protocols).Count
    cutover_target_count=@($cutover.targets).Count
    merge_law_count=@($laws.laws).Count
    merge_laws_complete=[bool]$laws.complete
    run_digests=@($runs|ForEach-Object{[string]$_.digest})
    protocol_digest=[string]$protocols.digest
    cutover_digest=[string]$cutover.digest
    merge_law_digest=[string]$laws.digest
    safe_disposition=[string]$safeDecision.disposition
    unsafe_disposition=[string]$unsafeDecision.disposition
    hard_safety_overridable=[bool]$unsafeDecision.safety.hard_safety_overridable
    mutation_authorized=@($runs|Where-Object{$_.mutation_capability-or$_.runtime_state_mutation_capability}).Count-gt0
    support_claimed=@($runs|Where-Object{$_.public_support_claim}).Count-gt0
  }
  return [pscustomobject][ordered]@{record=$record;digest=(Get-MIR4CanonicalDigestV1 -Value $record -Domain 'mir4:semantic-compiler-policy-functional-parity:1')}
}

function Test-MIR4SemanticCompilerPolicyFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $result=Get-MIR4SemanticCompilerPolicyFunctionalParityV1 -RepoRoot $RepoRoot
  if([int]$result.record.target_count-ne17-or[int]$result.record.run_count-ne17-or[int]$result.record.provider_protocol_count-ne13-or
     [int]$result.record.cutover_target_count-ne17-or[int]$result.record.merge_law_count-ne12-or-not[bool]$result.record.merge_laws_complete-or
     [string]$result.record.safe_disposition-cne'preserve'-or[string]$result.record.unsafe_disposition-cne'fail-hard-safety'-or
     [bool]$result.record.hard_safety_overridable-or[bool]$result.record.mutation_authorized-or[bool]$result.record.support_claimed){
    throw '[mir4-semantic-compiler-policy-functional-shape-parity]'
  }
  if([string]$result.digest-cne$script:MIR4SemanticCompilerPolicyParityDigestV1){throw "[mir4-semantic-compiler-policy-functional-parity] $([string]$result.digest)"}
  return $result
}

function New-MIR4SemanticCompilerPolicyMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $migration=Get-MIR4SemanticCompilerPolicyMigrationAuthorityV1 -RepoRoot $repo
  $proof=Get-MIR4SemanticCompilerPolicyMigrationProofPolicyV1 -RepoRoot $repo
  $prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration
  [void](Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4SemanticCompilerPolicyPredecessorReceiptPath `
    -ExpectedSha256 $script:MIR4SemanticCompilerPolicyPredecessorReceiptSha256 `
    -SchemaPath 'contracts/repository/mir4-target-compiler-migration-receipt-v1.schema.json' `
    -Kind 'MIR4TargetCompilerMigrationReceiptV1' `
    -DigestDomain 'mir4:target-compiler-migration-receipt:1' `
    -ErrorPrefix 'mir4-semantic-compiler-policy-predecessor')
  [void](Test-MIR4SemanticCompilerPolicyCompatibilityForwardersV1 -RepoRoot $repo)
  [void](Test-MIR4SemanticCompilerPolicyDeclaredConsumersV1 -RepoRoot $repo)
  [void](Test-MIR4SemanticCompilerPolicyFunctionalParityV1 -RepoRoot $repo)

  $integrationPaths=@(
    '.gitattributes','.mir/assurance.json','.mir/control/repository-fixed-point.json','.mir/control/paths.yml','.mir/control-plane/ownership.json','.mir/modules.yml',
    '.mir/releases/waves/mir4-r0/MIR4-Semantic-Compiler-ProgrammeV1.json','.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json','.mir/releases/waves/mir4-r0/MIR4-ProcessIR-Synthesis-ProgrammeV1.json',
    'assurance/.mir-root.json','governance/.mir-root.json','tests/.mir-root.json','validation/tests.yml','tools/mir.ps1','mir.lock',
    'tools/lib/mir4/PlatformPreview.ps1','tools/lib/mir4/ExactProcessIR.ps1','tools/lib/mir4/PreFreezeRelease.ps1','tools/lib/assurance/Evidence.ps1',
    'tools/commands/mir4/Export-MIR4ProcessIRSynthesisRecords.ps1','validation/tests/mir4/Test-MIR4SemanticCompilationW03.ps1',
    'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1','tools/mir/application/targets/TargetCompilerMigration.ps1','tools/mir/cli/Invoke-MIR4TargetCompilerMigration.ps1','tests/targets/Test-MIR4TargetCompilerMigration.ps1',
    'tools/mir/domain/repository/RepositoryFixedPoint.ps1','tests/repository/Test-MIR4RepositoryFixedPoint.ps1',
    'validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1','validation/tests/tooling/Test-MIRAssurance.ps1',
    'docs/architecture/mir4-repository-fixed-point.md','docs/architecture/mir4-semantic-compiler.md','docs/architecture/mir4-platform-preview.md','docs/architecture/mir4-processir-synthesis.md','docs/architecture/module-boundaries.md',
    'docs/reference/generated/mir4-platform-component-matrix.md','docs/reference/generated/mir4-whole-platform-matrix.md','docs/releases/mir4-4.0-whole-platform-programme.md',
    'sdk/preview/mir4/reference/compilation-runs.json','sdk/preview/mir4/reference/feature-setting-cutover-matrix.json','sdk/preview/mir4/reference/provider-micro-protocol-matrix.json','sdk/preview/mir4/reference/merge-law-catalogue.json',
    'sdk/preview/mir4/reference/effect-channel-registry-v1.json','sdk/preview/mir4/reference/process-ir-parity-result.json','sdk/preview/mir4/reference/query-snapshot-f210.json'
  )
  $parity=[ordered]@{
    canonical_writer_count=@($migration.writers).Count
    shared_migration_engine=$true
    compatibility_forwarders_verified=$true
    semantic_compiler_policy_function_parity=$true
    semantic_export_command_parity=$true
    declared_consumers_use_final_paths=$true
    focused_test_registered=$true
    compatibility_policy_read_only=$true
    predecessor_writer_disabled=$true
    release_history_successor_verified=$true
    release_history_fingerprint_bound=$true
    authority_schema_verified=$true
    assurance_schema_verified=$true
    rollback_recorded=(-not[string]::IsNullOrWhiteSpace([string]$migration.rollback.command))
    duplicate_writers=@()
  }
  return New-MIR4AppendOnlyAuthorityMigrationReceiptV1 -RepoRoot $repo -Migration $migration -Proof $proof -Prior $prior `
    -ReceiptKind 'MIR4SemanticCompilerPolicyMigrationReceiptV1' `
    -ReceiptState 'SEMANTIC-COMPILER-POLICY-DOMAIN-APPLICATION-CLI-AND-TEST-CUTOVER-VERIFIED-COMPATIBILITY-RETAINED' `
    -ReceiptPath $script:MIR4SemanticCompilerPolicyMigrationReceiptPath `
    -MigrationAuthorityPath $script:MIR4SemanticCompilerPolicyMigrationAuthorityPath `
    -AssurancePath $script:MIR4SemanticCompilerPolicyMigrationProofPath `
    -Scope 'package-excluded-semantic-compiler-policy-migration' `
    -EvolutionReason 'Package-excluded semantic compiler, safety and policy domain, deterministic exporter, and focused-test migration with immutable predecessor and release-history successor proof.' `
    -DigestDomain 'mir4:semantic-compiler-policy-migration-receipt:1' `
    -Parity $parity -IntegrationPaths $integrationPaths
}

function Get-MIR4SemanticCompilerPolicyMigrationReceiptTextV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (ConvertTo-MIR4CanonicalJsonV1 -Value (New-MIR4SemanticCompilerPolicyMigrationReceiptV1 -RepoRoot $RepoRoot))+[char]10
}

function Invoke-MIR4SemanticCompilerPolicyMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $path=Join-Path $repo $script:MIR4SemanticCompilerPolicyMigrationReceiptPath
  $text=Get-MIR4SemanticCompilerPolicyMigrationReceiptTextV1 -RepoRoot $repo
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or[IO.File]::ReadAllText($path)-cne$text){throw '[mir4-semantic-compiler-policy-migration-receipt-stale]'}
    if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4SemanticCompilerPolicyMigrationReceiptPath -SchemaPath $script:MIR4SemanticCompilerPolicyMigrationReceiptSchemaPath)){
      throw '[mir4-semantic-compiler-policy-migration-receipt-schema]'
    }
  }else{
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent)|Out-Null
    [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4SemanticCompilerPolicyMigrationReceiptPath
}
