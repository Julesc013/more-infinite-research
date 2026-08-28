. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot '../processir/ProcessIRExactMigration.ps1')
. (Join-Path $PSScriptRoot 'Inspector.ps1')
. (Join-Path $PSScriptRoot 'CompatibilityFactory.ps1')
. (Join-Path $PSScriptRoot 'CompatibilityCanary.ps1')

$script:MIR4InspectorCompatibilityMigrationAuthorityPath='governance/repository/migrations/inspector-compatibility-tooling-v1.json'
$script:MIR4InspectorCompatibilityMigrationAuthoritySchemaPath='contracts/repository/mir4-inspector-compatibility-migration-authority-v1.schema.json'
$script:MIR4InspectorCompatibilityMigrationProofPath='assurance/repository/inspector-compatibility-tooling-v1.json'
$script:MIR4InspectorCompatibilityMigrationProofSchemaPath='contracts/repository/mir4-inspector-compatibility-migration-proof-v1.schema.json'
$script:MIR4InspectorCompatibilityMigrationReceiptPath='releases/migrations/MIR4-Inspector-Compatibility-Tooling-MigrationV1.json'
$script:MIR4InspectorCompatibilityMigrationReceiptSchemaPath='contracts/repository/mir4-inspector-compatibility-migration-receipt-v1.schema.json'
$script:MIR4InspectorCompatibilityPredecessorReceiptPath='releases/migrations/MIR4-ProcessIR-Exact-Tooling-MigrationV1.json'
$script:MIR4InspectorCompatibilityPredecessorReceiptSha256='163714759F02DEFC8D6301923CC6796F1382D1ABF3841712FC87F4C9FEEACE8E'
$script:MIR4InspectorCompatibilityPreCutoverDigestV1='sha256:3b16e26301d2f2827369a9db0437e3c6c97ce0965096f921dd8b6d7d8c5bb527'
$script:MIR4InspectorCompatibilityParityDigestV1='sha256:3b16e26301d2f2827369a9db0437e3c6c97ce0965096f921dd8b6d7d8c5bb527'
$script:MIR4InspectorCompatibilityT13ReceiptSha256='D8AD00B861F0C31A7CE4A7DA239AF250EEED4F586F78921F80A10CF9E771FF9F'
$script:MIR4InspectorCompatibilityT13ManifestSha256='5184A4715F1E66714E36B53DC25EAE7DC3AE92978D9141000684978F0AEE925C'
$script:MIR4InspectorCompatibilityPolicySha256='54C226D32D092BD521AD016089944ED282AF2806FE7ED26A6F61197B731B0EE2'
$script:MIR4InspectorCompatibilityTerminalClaimsSha256='01953ECA6FC6EEF25145FEE865A1E7D8FF65E99E10941363B2A843569ABD8DC0'

function Get-MIR4InspectorCompatibilityMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4InspectorCompatibilityMigrationAuthorityPath -SchemaPath $script:MIR4InspectorCompatibilityMigrationAuthoritySchemaPath)){throw '[mir4-inspector-compatibility-migration-authority-schema]'}
  $authority=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4InspectorCompatibilityMigrationAuthorityPath
  if([string]$authority.predecessor_receipt.path-cne$script:MIR4InspectorCompatibilityPredecessorReceiptPath-or[string]$authority.predecessor_receipt.sha256-cne$script:MIR4InspectorCompatibilityPredecessorReceiptSha256){throw '[mir4-inspector-compatibility-migration-predecessor-authority]'}
  if(@($authority.writers).Count-ne1-or[string]$authority.writers[0].path-cne'tools/mir/application/inspection/InspectorCompatibilityMigration.ps1'){throw '[mir4-inspector-compatibility-migration-single-writer]'}
  $finalPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path});if(@($finalPaths|Sort-Object -Unique).Count-ne$finalPaths.Count){throw '[mir4-inspector-compatibility-migration-duplicate-final-path]'}
  if(@($authority.release_transition_authority.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-inspector-compatibility-migration-release-authority]'}
  return $authority
}

function Get-MIR4InspectorCompatibilityMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4InspectorCompatibilityMigrationProofPath -SchemaPath $script:MIR4InspectorCompatibilityMigrationProofSchemaPath)){throw '[mir4-inspector-compatibility-migration-proof-schema]'}
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4InspectorCompatibilityMigrationProofPath
}

function Test-MIR4InspectorCompatibilityForwardersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $bindings=@(
    @{path='tools/lib/mir4/SupportAssessment.ps1';target='mir/application/inspection/SupportAssessment.ps1';max=3},
    @{path='tools/lib/mir4/CompatibilityIndex.ps1';target='mir/application/inspection/CompatibilityIndex.ps1';max=3},
    @{path='tools/lib/mir4/CompatibilityFactory.ps1';target='mir/application/inspection/CompatibilityFactory.ps1';max=3},
    @{path='tools/lib/mir4/Inspector.ps1';target='mir/application/inspection/Inspector.ps1';max=3},
    @{path='tools/lib/mir4/CompatibilityCanary.ps1';target='mir/application/inspection/CompatibilityCanary.ps1';max=3},
    @{path='tools/commands/mir4/Export-MIR4InspectorCompatibilityRecords.ps1';target='mir/cli/Export-MIR4InspectorCompatibilityRecords.ps1';max=3},
    @{path='tools/commands/mir4/Export-MIR4CompatibilityCanaryRecords.ps1';target='mir/cli/Export-MIR4CompatibilityCanaryRecords.ps1';max=3}
  )
  foreach($binding in $bindings){$text=[IO.File]::ReadAllText((Join-Path $repo $binding.path)).Replace('\','/');if($text-cnotmatch[regex]::Escape([string]$binding.target)-or$text.Split([char]10).Count-gt[int]$binding.max-or$text-match'(?m)^function\s+'){throw "[mir4-inspector-compatibility-forwarder] $($binding.path)"}}
  return $true
}

function Test-MIR4InspectorCompatibilityDeclaredConsumersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $root='tools/mir/application/inspection/';$inspector=$root+'Inspector.ps1';$factory=$root+'CompatibilityFactory.ps1';$index=$root+'CompatibilityIndex.ps1';$assessment=$root+'SupportAssessment.ps1';$canary=$root+'CompatibilityCanary.ps1';$exporter='tools/mir/cli/Export-MIR4InspectorCompatibilityRecords.ps1';$canaryExporter='tools/mir/cli/Export-MIR4CompatibilityCanaryRecords.ps1'
  $requirements=[ordered]@{
    'tools/lib/mir4/PlatformPreview.ps1'=@($inspector,$factory,$index,$assessment)
    'tools/mir/cli/Export-MIR4ExactProcessIRRecords.ps1'=@($inspector)
    'tools/mir.ps1'=@($exporter,$canaryExporter,'tools/mir/cli/Invoke-MIR4InspectorCompatibilityMigration.ps1')
    'validation/tests/mir4/Test-MIR4InspectorCompatibilityW07.ps1'=@($inspector,$factory,$index,$assessment,$exporter)
    'validation/tests/mir4/Test-MIR4ExactProcessIRT12.ps1'=@($inspector)
    'validation/tests/mir4/Test-MIR4ReleaseCompatibilityCanariesT13.ps1'=@($canary,$canaryExporter)
    '.mir/control/paths.yml'=@($inspector,$factory,$index,$assessment,$canary,$exporter,$canaryExporter)
    '.mir/modules.yml'=@($inspector,$factory,$index,$assessment,$canary,$exporter,$canaryExporter)
    '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json'=@($inspector,$factory,$index,$assessment,$canary)
    'docs/architecture/module-boundaries.md'=@('tools/mir/application/inspection')
    'docs/architecture/mir4-inspector-compatibility.md'=@($assessment,$factory,'tools/mir/application/inspection')
  }
  foreach($entry in $requirements.GetEnumerator()){$text=[IO.File]::ReadAllText((Join-Path $repo ([string]$entry.Key))).Replace('\','/');foreach($required in @($entry.Value)){if($text-cnotmatch[regex]::Escape([string]$required)){throw "[mir4-inspector-compatibility-consumer-final-path] $($entry.Key) -> $required"}}}
  return $true
}

function Get-MIR4InspectorCompatibilityFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $ledger=New-MIR4CompatibilitySubjectLedger -RepoRoot $repo -SourceIdentity $null
  $support=New-MIR4ReferenceSupportBundleV1 -Ledger $ledger -RepoRoot $repo -Target f210
  $plan=New-MIR4CompatibilityFactoryPlanV1 -SupportBundle $support -Ledger $ledger -RepoRoot $repo -SourceIdentity $null
  $bundle=New-MIR4InspectionBundleV1 -RepoRoot $repo -Ledger $ledger -SourceIdentity $null
  $package=[pscustomobject][ordered]@{path='semantic-probe.zip';bytes=0;sha256=('0'*64);entry_count=9;status='probe'}
  $workbench=(New-MIR4InspectorWorkbenchResultV1 -RepoRoot $repo -Ledger $ledger -FactoryPlan $plan -FactoryPackage $package -SourceIdentity $null).result
  $t13=Get-MIR4T13Authority -RepoRoot $repo
  $t13Receipt=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path 'sdk/preview/mir4/reference/t13/MIR4_T13_RECEIPT.json'
  $record=[ordered]@{
    subjects=@($ledger.subjects|Sort-Object subject_id|ForEach-Object{[ordered]@{id=[string]$_.subject_id;availability=[string]$_.availability.state;choice=[string]$_.implementation.preferred_safe_choice;proof=[string]$_.proof.state;targets=@($_.target_bindings.target|Sort-Object);blockers=@($_.blockers|Sort-Object)}})
    target_dispositions=@($ledger.target_dispositions|Sort-Object target|ForEach-Object{[ordered]@{target=[string]$_.target;disposition=[string]$_.disposition}})
    support=@($support.subjects|Sort-Object subject_id|ForEach-Object{[ordered]@{id=[string]$_.subject_id;choice=[string]$_.safe_choice}})
    plan=@($plan.plans|Sort-Object subject_id|ForEach-Object{[ordered]@{id=[string]$_.subject_id;choice=[string]$_.selected_choice;disposition=[string]$_.terminal_disposition;target=[string]$_.target;evidence=[string]$_.evidence_state}})
    sections=@($bundle.sections|ForEach-Object{[ordered]@{id=[string]$_.id;label=[string]$_.label;count=[int]$_.item_count;returned=[int]$_.returned;truncated=[bool]$_.truncated}})
    workbench=[ordered]@{section_count=[int]$workbench.workbench.section_count;offline=$workbench.offline;accessibility=$workbench.accessibility;blockers=$workbench.blockers;passed=[bool]$workbench.passed}
    canaries=@($t13.canaries|Sort-Object id|ForEach-Object{[ordered]@{id=[string]$_.id;captures=@($_.capture_ids|Sort-Object);subjects=@($_.subjects|Sort-Object);statement=[string]$_.support_statement;limitations=@($_.limitations)}})
    t13=[ordered]@{required_canary_count=[int]$t13.required_canary_count;required_capture_count=[int]$t13.required_capture_count;expiry=@($null);receipt_status=[string]$t13Receipt.status;receipt_canary_count=[int]$t13Receipt.canary_count;receipt_capture_count=[int]$t13Receipt.capture_count;package_unchanged=[bool]$t13Receipt.package_source_unchanged;public_claim=[bool]$t13Receipt.public_support_claim_authorized;release=[bool]$t13Receipt.release_transition_authorized}
  }
  $json=ConvertTo-MIR4ProcessIRCanonicalJson $record;$bytes=[Text.UTF8Encoding]::new($false).GetBytes($json);$digest='sha256:'+([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant())
  return [pscustomobject][ordered]@{record=$record;digest=$digest}
}

function Test-MIR4InspectorCompatibilityFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $result=Get-MIR4InspectorCompatibilityFunctionalParityV1 -RepoRoot $RepoRoot;$record=$result.record
  if(@($record.subjects).Count-ne10-or@($record.sections).Count-ne11-or@($record.canaries).Count-ne8-or[int]$record.t13.required_capture_count-ne11-or[bool]$record.t13.public_claim-or[bool]$record.t13.release){throw '[mir4-inspector-compatibility-functional-shape-parity]'}
  if([string]$result.digest-cne$script:MIR4InspectorCompatibilityParityDigestV1){throw "[mir4-inspector-compatibility-functional-parity] $([string]$result.digest)"}
  return $result
}

function New-MIR4InspectorCompatibilityMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$migration=Get-MIR4InspectorCompatibilityMigrationAuthorityV1 -RepoRoot $repo;$proof=Get-MIR4InspectorCompatibilityMigrationProofPolicyV1 -RepoRoot $repo
  $prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration
  [void](Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4InspectorCompatibilityPredecessorReceiptPath -ExpectedSha256 $script:MIR4InspectorCompatibilityPredecessorReceiptSha256 -SchemaPath 'contracts/repository/mir4-processir-exact-migration-receipt-v1.schema.json' -Kind 'MIR4ProcessIRExactMigrationReceiptV1' -DigestDomain 'mir4:processir-exact-migration-receipt:1' -ErrorPrefix 'mir4-inspector-compatibility-predecessor')
  [void](Test-MIR4InspectorCompatibilityForwardersV1 -RepoRoot $repo);[void](Test-MIR4InspectorCompatibilityDeclaredConsumersV1 -RepoRoot $repo);[void](Test-MIR4InspectorCompatibilityFunctionalParityV1 -RepoRoot $repo)
  if((Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash-cne$script:MIR4InspectorCompatibilityPolicySha256){throw '[mir4-inspector-compatibility-policy-mutated]'}
  if((Get-FileHash -LiteralPath (Join-Path $repo 'spec/compatibility/claims.json') -Algorithm SHA256).Hash-cne$script:MIR4InspectorCompatibilityTerminalClaimsSha256){throw '[mir4-inspector-compatibility-terminal-claims-mutated]'}
  if((Get-FileHash -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/t13/MIR4_T13_RECEIPT.json') -Algorithm SHA256).Hash-cne$script:MIR4InspectorCompatibilityT13ReceiptSha256-or(Get-FileHash -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/t13/MIR4_T13_MANIFEST.json') -Algorithm SHA256).Hash-cne$script:MIR4InspectorCompatibilityT13ManifestSha256){throw '[mir4-inspector-compatibility-t13-evidence-mutated]'}
  $integrationPaths=@(
    '.gitattributes','.mir/assurance.json','.mir/compatibility.yml','.mir/control/repository-fixed-point.json','.mir/control/paths.yml','.mir/control-plane/ownership.json','.mir/modules.yml','.mir/docs.yml',
    '.mir/releases/waves/mir4-r0/MIR4-Inspector-Compatibility-ProgrammeV1.json','.mir/releases/waves/mir4-r0/MIR4-Release-Compatibility-Canaries-T13V1.json','.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json',
    'assurance/.mir-root.json','governance/.mir-root.json','tests/.mir-root.json','validation/tests.yml','tools/mir.ps1','mir.lock','spec/compatibility/claims.json','spec/schemas/mir4-inspector-compatibility-programme-v1.schema.json',
    'tools/lib/mir4/PlatformPreview.ps1','tools/lib/mir4/PreFreezeRelease.ps1','tools/lib/assurance/Evidence.ps1','tools/mir/cli/Export-MIR4ExactProcessIRRecords.ps1',
    'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1','tools/mir/application/processir/ProcessIRExactMigration.ps1','tools/mir/cli/Invoke-MIR4ProcessIRExactMigration.ps1','tests/processir/Test-MIR4ProcessIRExactMigration.ps1',
    'validation/tests/mir4/Test-MIR4InspectorCompatibilityW07.ps1','validation/tests/mir4/Test-MIR4ExactProcessIRT12.ps1','validation/tests/mir4/Test-MIR4ReleaseCompatibilityCanariesT13.ps1',
    'validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1','validation/tests/tooling/Test-MIRAssurance.ps1',
    'docs/architecture/mir4-repository-fixed-point.md','docs/architecture/mir4-inspector-compatibility.md','docs/architecture/mir4-platform-preview.md','docs/architecture/module-boundaries.md','docs/compatibility/mir4-release-canaries.md',
    'docs/reference/generated/mir4-platform-component-matrix.md','docs/reference/generated/mir4-whole-platform-matrix.md','docs/releases/mir4-4.0-whole-platform-programme.md',
    'sdk/preview/mir4/reference/t13/MIR4_T13_MANIFEST.json','sdk/preview/mir4/reference/t13/MIR4_T13_RECEIPT.json'
  )
  $parity=[ordered]@{canonical_writer_count=@($migration.writers).Count;shared_migration_engine=$true;compatibility_forwarders_verified=$true;inspector_functional_parity=$true;inspector_export_command_parity=$true;canary_check_command_parity=$true;declared_consumers_use_final_paths=$true;focused_test_registered=$true;compatibility_policy_read_only=$true;terminal_claims_read_only=$true;player_runtime_authority_read_only=$true;predecessor_writer_disabled=$true;historical_t13_evidence_read_only=$true;exact_canary_claim_boundary_retained=$true;release_history_successor_verified=$true;release_history_fingerprint_bound=$true;authority_schema_verified=$true;assurance_schema_verified=$true;rollback_recorded=(-not[string]::IsNullOrWhiteSpace([string]$migration.rollback.command));duplicate_writers=@()}
  return New-MIR4AppendOnlyAuthorityMigrationReceiptV1 -RepoRoot $repo -Migration $migration -Proof $proof -Prior $prior -ReceiptKind 'MIR4InspectorCompatibilityMigrationReceiptV1' -ReceiptState 'INSPECTOR-COMPATIBILITY-APPLICATION-CLI-AND-TEST-CUTOVER-VERIFIED-COMPATIBILITY-RETAINED' -ReceiptPath $script:MIR4InspectorCompatibilityMigrationReceiptPath -MigrationAuthorityPath $script:MIR4InspectorCompatibilityMigrationAuthorityPath -AssurancePath $script:MIR4InspectorCompatibilityMigrationProofPath -Scope 'package-excluded-inspector-compatibility-migration' -EvolutionReason 'Package-excluded W07 Inspector and compatibility plus T13 exact-canary tooling migration with immutable historical canary evidence, terminal claim and player-runtime firewalls, and release-history successor proof.' -DigestDomain 'mir4:inspector-compatibility-migration-receipt:1' -Parity $parity -IntegrationPaths $integrationPaths
}

function Get-MIR4InspectorCompatibilityMigrationReceiptTextV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (ConvertTo-MIR4CanonicalJsonV1 -Value (New-MIR4InspectorCompatibilityMigrationReceiptV1 -RepoRoot $RepoRoot))+[char]10
}

function Invoke-MIR4InspectorCompatibilityMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$path=Join-Path $repo $script:MIR4InspectorCompatibilityMigrationReceiptPath;$text=Get-MIR4InspectorCompatibilityMigrationReceiptTextV1 -RepoRoot $repo
  if($Check){if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or[IO.File]::ReadAllText($path)-cne$text){throw '[mir4-inspector-compatibility-migration-receipt-stale]'};if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4InspectorCompatibilityMigrationReceiptPath -SchemaPath $script:MIR4InspectorCompatibilityMigrationReceiptSchemaPath)){throw '[mir4-inspector-compatibility-migration-receipt-schema]'}}else{New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent)|Out-Null;[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))}
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4InspectorCompatibilityMigrationReceiptPath
}
