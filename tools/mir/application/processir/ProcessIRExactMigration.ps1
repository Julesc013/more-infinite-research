. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot '../extensions/ModuleSdkMepMigration.ps1')
. (Join-Path $PSScriptRoot '../../domain/safety/SafetyKernel.ps1')
. (Join-Path $PSScriptRoot 'ProcessIR.ps1')

$script:MIR4ProcessIRExactMigrationAuthorityPath='governance/repository/migrations/processir-exact-tooling-v1.json'
$script:MIR4ProcessIRExactMigrationAuthoritySchemaPath='contracts/repository/mir4-processir-exact-migration-authority-v1.schema.json'
$script:MIR4ProcessIRExactMigrationProofPath='assurance/repository/processir-exact-tooling-v1.json'
$script:MIR4ProcessIRExactMigrationProofSchemaPath='contracts/repository/mir4-processir-exact-migration-proof-v1.schema.json'
$script:MIR4ProcessIRExactMigrationReceiptPath='releases/migrations/MIR4-ProcessIR-Exact-Tooling-MigrationV1.json'
$script:MIR4ProcessIRExactMigrationReceiptSchemaPath='contracts/repository/mir4-processir-exact-migration-receipt-v1.schema.json'
$script:MIR4ProcessIRExactPredecessorReceiptPath='releases/migrations/MIR4-Module-Sdk-Mep-Tooling-MigrationV1.json'
$script:MIR4ProcessIRExactPredecessorReceiptSha256='AFA11010DBAB95012433522BA99B1481D02709E0ACE50C8E6BDFCBC3D732C0FA'
$script:MIR4ProcessIRExactPreCutoverDigestV1='sha256:5ec65105a147e82af3e2d10abd00a75fc98ba60808974c2332564316b82858bd'
$script:MIR4ProcessIRExactParityDigestV1='sha256:39875970a8681a9f3c5aef1ded577362d41962c7744a5c5aace4f1afb5739ba8'

function Get-MIR4ProcessIRExactMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4ProcessIRExactMigrationAuthorityPath -SchemaPath $script:MIR4ProcessIRExactMigrationAuthoritySchemaPath)){throw '[mir4-processir-exact-migration-authority-schema]'}
  $authority=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4ProcessIRExactMigrationAuthorityPath
  if([string]$authority.predecessor_receipt.path-cne$script:MIR4ProcessIRExactPredecessorReceiptPath-or[string]$authority.predecessor_receipt.sha256-cne$script:MIR4ProcessIRExactPredecessorReceiptSha256){throw '[mir4-processir-exact-migration-predecessor-authority]'}
  if(@($authority.writers).Count-ne1-or[string]$authority.writers[0].path-cne'tools/mir/application/processir/ProcessIRExactMigration.ps1'){throw '[mir4-processir-exact-migration-single-writer]'}
  $finalPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path})
  if(@($finalPaths|Sort-Object -Unique).Count-ne$finalPaths.Count){throw '[mir4-processir-exact-migration-duplicate-final-path]'}
  if(@($authority.release_transition_authority.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-processir-exact-migration-release-authority]'}
  return $authority
}

function Get-MIR4ProcessIRExactMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4ProcessIRExactMigrationProofPath -SchemaPath $script:MIR4ProcessIRExactMigrationProofSchemaPath)){throw '[mir4-processir-exact-migration-proof-schema]'}
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4ProcessIRExactMigrationProofPath
}

function Test-MIR4ProcessIRExactCompatibilityForwardersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $bindings=@(
    @{path='tools/lib/mir4/ProcessIR.ps1';target='mir/application/processir/ProcessIR.ps1';max=3},
    @{path='tools/lib/mir4/ExactProcessIR.ps1';target='mir/application/processir/ExactProcessIR.ps1';max=3},
    @{path='tools/commands/mir4/Export-MIR4ProcessIRSynthesisRecords.ps1';target='mir/cli/Export-MIR4ProcessIRSynthesisRecords.ps1';max=8},
    @{path='tools/commands/mir4/Export-MIR4ExactProcessIRRecords.ps1';target='mir/cli/Export-MIR4ExactProcessIRRecords.ps1';max=18}
  )
  foreach($binding in $bindings){$text=[IO.File]::ReadAllText((Join-Path $repo $binding.path)).Replace('\','/');if($text-cnotmatch[regex]::Escape([string]$binding.target)-or$text.Split([char]10).Count-gt[int]$binding.max-or$text-match'(?m)^function\s+'){throw "[mir4-processir-exact-compatibility-forwarder] $($binding.path)"}}
  return $true
}

function Test-MIR4ProcessIRExactDeclaredConsumersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$process='tools/mir/application/processir/ProcessIR.ps1';$exact='tools/mir/application/processir/ExactProcessIR.ps1';$exporter='tools/mir/cli/Export-MIR4ProcessIRSynthesisRecords.ps1';$exactExporter='tools/mir/cli/Export-MIR4ExactProcessIRRecords.ps1'
  $requirements=[ordered]@{
    'tools/lib/mir4/PlatformPreview.ps1'=@($process)
    'tools/lib/mir4/CompatibilityCanary.ps1'=@('mir/application/processir/ExactProcessIR.ps1')
    'tools/mir/application/compiler/CompilationRun.ps1'=@($process)
    'tools/mir.ps1'=@($exporter,$exactExporter,'tools/mir/cli/Invoke-MIR4ProcessIRExactMigration.ps1')
    'validation/tests/mir4/Test-MIR4ProcessIRSynthesisW06.ps1'=@($process,$exporter)
    'validation/tests/mir4/Test-MIR4ExactProcessIRT12.ps1'=@($exact,$exactExporter)
    '.mir/control/paths.yml'=@($process,$exact,$exporter,$exactExporter)
    '.mir/modules.yml'=@($process,$exact,$exporter,$exactExporter)
    '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json'=@($process,$exact)
    'docs/architecture/module-boundaries.md'=@($process)
  }
  foreach($entry in $requirements.GetEnumerator()){$text=[IO.File]::ReadAllText((Join-Path $repo ([string]$entry.Key))).Replace('\','/');foreach($required in @($entry.Value)){if($text-cnotmatch[regex]::Escape([string]$required)){throw "[mir4-processir-exact-consumer-final-path] $($entry.Key) -> $required"}}}
  return $true
}

function Get-MIR4ProcessIRExactFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$records=New-MIR4W06Records -RepoRoot $repo -SourceIdentity $null;$t12=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'sdk/preview/mir4/reference/t12/MIR4_T12_RECEIPT.json';$manifest=Join-Path $repo 'sdk/preview/mir4/reference/t12/MIR4_T12_EXACT_PROCESSIR_MANIFEST.json'
  $record=[ordered]@{processir_parity_digest=[string]$records.parity.digest;effect_channel_digest=[string]$records.effects.digest;synthesis_maturity_digest=[string]$records.synthesis.digest;fixture_classifications=@($records.parity.fixture_results|Sort-Object fixture_id|ForEach-Object{"$($_.fixture_id):$($_.actual_classification):$($_.actual_disposition)"});exact_manifest_sha256=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash;exact_receipt_digest=[string]$t12.digest;exact_status=[string]$t12.status;exact_capture_count=[int]$t12.capture_count;custody_blocker='BLOCKED-EXACT-ARCHIVE-CUSTODY-F200-K2SO';package_visible=$false;player_mutation_authorized=$false;release_transition_authority=$false}
  return [pscustomobject][ordered]@{record=$record;digest=(Get-MIR4CanonicalDigestV1 -Value $record -Domain 'mir4:processir-exact-functional-parity:1')}
}

function Test-MIR4ProcessIRExactFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $result=Get-MIR4ProcessIRExactFunctionalParityV1 -RepoRoot $RepoRoot;$record=$result.record
  if([int]$record.exact_capture_count-ne10-or[string]$record.exact_status-cne'completed-machine-work-with-custody-blocker'-or[string]$record.custody_blocker-cne'BLOCKED-EXACT-ARCHIVE-CUSTODY-F200-K2SO'-or[bool]$record.package_visible-or[bool]$record.player_mutation_authorized-or[bool]$record.release_transition_authority){throw '[mir4-processir-exact-functional-shape-parity]'}
  if([string]$result.digest-cne$script:MIR4ProcessIRExactParityDigestV1){throw "[mir4-processir-exact-functional-parity] $([string]$result.digest)"}
  return $result
}

function New-MIR4ProcessIRExactMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$migration=Get-MIR4ProcessIRExactMigrationAuthorityV1 -RepoRoot $repo;$proof=Get-MIR4ProcessIRExactMigrationProofPolicyV1 -RepoRoot $repo
  $prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration
  [void](Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4ProcessIRExactPredecessorReceiptPath -ExpectedSha256 $script:MIR4ProcessIRExactPredecessorReceiptSha256 -SchemaPath 'contracts/repository/mir4-module-sdk-mep-migration-receipt-v1.schema.json' -Kind 'MIR4ModuleSdkMepMigrationReceiptV1' -DigestDomain 'mir4:module-sdk-mep-migration-receipt:1' -ErrorPrefix 'mir4-processir-exact-predecessor')
  [void](Test-MIR4ProcessIRExactCompatibilityForwardersV1 -RepoRoot $repo);[void](Test-MIR4ProcessIRExactDeclaredConsumersV1 -RepoRoot $repo);[void](Test-MIR4ProcessIRExactFunctionalParityV1 -RepoRoot $repo)
  $integrationPaths=@(
    '.gitattributes','.mir/assurance.json','.mir/control/repository-fixed-point.json','.mir/control/paths.yml','.mir/control-plane/ownership.json','.mir/modules.yml','.mir/docs.yml',
    '.mir/releases/waves/mir4-r0/MIR4-ProcessIR-Synthesis-ProgrammeV1.json','.mir/releases/waves/mir4-r0/MIR4-Exact-ProcessIR-T12V1.json','.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json',
    'assurance/.mir-root.json','governance/.mir-root.json','tests/.mir-root.json','validation/tests.yml','tools/mir.ps1','mir.lock',
    'tools/lib/mir4/PlatformPreview.ps1','tools/lib/mir4/CompatibilityCanary.ps1','tools/lib/mir4/PreFreezeRelease.ps1','tools/lib/assurance/Evidence.ps1',
    'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1','tools/mir/application/extensions/ModuleSdkMepMigration.ps1','tools/mir/cli/Invoke-MIR4ModuleSdkMepMigration.ps1','tests/extensions/Test-MIR4ModuleSdkMepMigration.ps1',
    'tools/mir/application/compiler/CompilationRun.ps1','validation/tests/mir4/Test-MIR4ProcessIRSynthesisW06.ps1','validation/tests/mir4/Test-MIR4ExactProcessIRT12.ps1',
    'validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1','validation/tests/tooling/Test-MIRAssurance.ps1',
    'docs/architecture/mir4-repository-fixed-point.md','docs/architecture/mir4-processir-synthesis.md','docs/architecture/mir4-platform-preview.md','docs/architecture/module-boundaries.md',
    'docs/reference/generated/mir4-platform-component-matrix.md','docs/reference/generated/mir4-whole-platform-matrix.md','docs/releases/mir4-4.0-whole-platform-programme.md',
    'sdk/preview/mir4/reference/t12/MIR4_T12_EXACT_PROCESSIR_MANIFEST.json','sdk/preview/mir4/reference/t12/MIR4_T12_RECEIPT.json'
  )
  $parity=[ordered]@{canonical_writer_count=@($migration.writers).Count;shared_migration_engine=$true;compatibility_forwarders_verified=$true;processir_functional_parity=$true;processir_export_command_parity=$true;exact_check_command_parity=$true;declared_consumers_use_final_paths=$true;focused_test_registered=$true;compatibility_policy_read_only=$true;player_runtime_authority_read_only=$true;predecessor_writer_disabled=$true;exact_custody_blocker_retained=$true;historical_t12_evidence_read_only=$true;release_history_successor_verified=$true;release_history_fingerprint_bound=$true;authority_schema_verified=$true;assurance_schema_verified=$true;rollback_recorded=(-not[string]::IsNullOrWhiteSpace([string]$migration.rollback.command));duplicate_writers=@()}
  return New-MIR4AppendOnlyAuthorityMigrationReceiptV1 -RepoRoot $repo -Migration $migration -Proof $proof -Prior $prior -ReceiptKind 'MIR4ProcessIRExactMigrationReceiptV1' -ReceiptState 'PROCESSIR-EXACT-APPLICATION-CLI-AND-TEST-CUTOVER-VERIFIED-COMPATIBILITY-RETAINED' -ReceiptPath $script:MIR4ProcessIRExactMigrationReceiptPath -MigrationAuthorityPath $script:MIR4ProcessIRExactMigrationAuthorityPath -AssurancePath $script:MIR4ProcessIRExactMigrationProofPath -Scope 'package-excluded-processir-exact-migration' -EvolutionReason 'Package-excluded W06 ProcessIR and T12 exact-observation tooling migration with immutable historical exact evidence, retained custody blocker, player-runtime firewall, and release-history successor proof.' -DigestDomain 'mir4:processir-exact-migration-receipt:1' -Parity $parity -IntegrationPaths $integrationPaths
}

function Get-MIR4ProcessIRExactMigrationReceiptTextV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (ConvertTo-MIR4CanonicalJsonV1 -Value (New-MIR4ProcessIRExactMigrationReceiptV1 -RepoRoot $RepoRoot))+[char]10
}

function Invoke-MIR4ProcessIRExactMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$path=Join-Path $repo $script:MIR4ProcessIRExactMigrationReceiptPath;$text=Get-MIR4ProcessIRExactMigrationReceiptTextV1 -RepoRoot $repo
  if($Check){if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or[IO.File]::ReadAllText($path)-cne$text){throw '[mir4-processir-exact-migration-receipt-stale]'};if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4ProcessIRExactMigrationReceiptPath -SchemaPath $script:MIR4ProcessIRExactMigrationReceiptSchemaPath)){throw '[mir4-processir-exact-migration-receipt-schema]'}}else{New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent)|Out-Null;[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))}
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4ProcessIRExactMigrationReceiptPath
}
