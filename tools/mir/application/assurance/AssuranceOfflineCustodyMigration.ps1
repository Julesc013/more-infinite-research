. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot '../inspection/InspectorCompatibilityMigration.ps1')
. (Join-Path $PSScriptRoot 'AssuranceScale.ps1')
. (Join-Path $PSScriptRoot 'ReleaseBudget.ps1')
. (Join-Path $PSScriptRoot 'OfflineDrill.ps1')
. (Join-Path $PSScriptRoot 'EnvironmentEvidence.ps1')
. (Join-Path $PSScriptRoot '../custody/OfflineCandidateCustody.ps1')

$script:MIR4AssuranceOfflineCustodyMigrationAuthorityPath='governance/repository/migrations/assurance-offline-custody-tooling-v1.json'
$script:MIR4AssuranceOfflineCustodyMigrationAuthoritySchemaPath='contracts/repository/mir4-assurance-offline-custody-migration-authority-v1.schema.json'
$script:MIR4AssuranceOfflineCustodyMigrationProofPath='assurance/repository/assurance-offline-custody-tooling-v1.json'
$script:MIR4AssuranceOfflineCustodyMigrationProofSchemaPath='contracts/repository/mir4-assurance-offline-custody-migration-proof-v1.schema.json'
$script:MIR4AssuranceOfflineCustodyMigrationReceiptPath='releases/migrations/MIR4-Assurance-Offline-Custody-Tooling-MigrationV1.json'
$script:MIR4AssuranceOfflineCustodyMigrationReceiptSchemaPath='contracts/repository/mir4-assurance-offline-custody-migration-receipt-v1.schema.json'
$script:MIR4AssuranceOfflineCustodyPredecessorReceiptPath='releases/migrations/MIR4-Inspector-Compatibility-Tooling-MigrationV1.json'
$script:MIR4AssuranceOfflineCustodyPredecessorReceiptSha256='BD60E60AB7E5B12711CC7B11274FBA92EE202708790B84863B4FCB54B8195B81'
$script:MIR4AssuranceOfflineCustodyPreCutoverDigestV1='sha256:96d98127324aadfba99f876cb4c72587135c7b6a04f1f6653bfcddc9494eaacd'
$script:MIR4AssuranceOfflineCustodyParityDigestV1='sha256:96d98127324aadfba99f876cb4c72587135c7b6a04f1f6653bfcddc9494eaacd'
$script:MIR4AssuranceOfflineCustodyCompatibilityPolicySha256='54C226D32D092BD521AD016089944ED282AF2806FE7ED26A6F61197B731B0EE2'
$script:MIR4AssuranceOfflineCustodyT10ReceiptSha256='7407D577451932536EA6DDF568CF58929D982E10CEE092A8963319A50809E40F'
$script:MIR4AssuranceOfflineCustodyT15ReceiptSha256='294A1E2001F3BA8E6813329E3C8BC609B0D07413AC365A0AFEF525A1188D76F0'
$script:MIR4AssuranceOfflineCustodyT15AcceptanceSha256='5CE4D1504FBD03D96B23948E591832CAA0C2B9C48DFBDA6002C13761560EC8BE'
$script:MIR4AssuranceV4PreservationDigestV1='258A613A59B70EF0C33B1FFE7EF79BD78A04D68190700B6F1128B30857F2E8F8'
$script:MIR4AssuranceOfflineCustodyMigrationReceiptSha256='3B6F3B057BD74353B4A12FB5F7C108C3AE41470C375D74DAC424E888668ED749'
$script:MIR4AssuranceOfflineCustodyMigrationReceiptBytes=53137

function Get-MIR4AssuranceOfflineCustodyMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4AssuranceOfflineCustodyMigrationAuthorityPath -SchemaPath $script:MIR4AssuranceOfflineCustodyMigrationAuthoritySchemaPath)){throw '[mir4-assurance-offline-custody-migration-authority-schema]'}
  $authority=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4AssuranceOfflineCustodyMigrationAuthorityPath
  if([string]$authority.predecessor_receipt.path-cne$script:MIR4AssuranceOfflineCustodyPredecessorReceiptPath-or[string]$authority.predecessor_receipt.sha256-cne$script:MIR4AssuranceOfflineCustodyPredecessorReceiptSha256){throw '[mir4-assurance-offline-custody-migration-predecessor-authority]'}
  if(@($authority.writers).Count-ne1-or[string]$authority.writers[0].path-cne'tools/mir/application/assurance/AssuranceOfflineCustodyMigration.ps1'){throw '[mir4-assurance-offline-custody-migration-single-writer]'}
  $finalPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path});if(@($finalPaths|Sort-Object -Unique).Count-ne$finalPaths.Count){throw '[mir4-assurance-offline-custody-migration-duplicate-final-path]'}
  if(@($authority.release_transition_authority.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-assurance-offline-custody-migration-release-authority]'}
  return $authority
}

function Get-MIR4AssuranceOfflineCustodyMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4AssuranceOfflineCustodyMigrationProofPath -SchemaPath $script:MIR4AssuranceOfflineCustodyMigrationProofSchemaPath)){throw '[mir4-assurance-offline-custody-migration-proof-schema]'}
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4AssuranceOfflineCustodyMigrationProofPath
}

function Get-MIR4AssuranceV4PreservationDigestV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $paths=@('scripts/Invoke-MIRAssurance.ps1','tools/lib/assurance/Core.ps1','tools/lib/assurance/Domains.ps1','tools/lib/assurance/Hashing.ps1','tools/lib/assurance/Release.ps1')
  $rows=@($paths|ForEach-Object{"$_`n$((Get-FileHash -LiteralPath (Join-Path $repo $_) -Algorithm SHA256).Hash)"})
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes(($rows-join"`n"))))
}

function Test-MIR4AssuranceOfflineCustodyForwardersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $bindings=@(
    @{path='tools/lib/mir4/AssuranceScale.ps1';target='mir/application/assurance/AssuranceScale.ps1'},
    @{path='tools/lib/mir4/ReleaseBudget.ps1';target='mir/application/assurance/ReleaseBudget.ps1'},
    @{path='tools/lib/mir4/OfflineDrill.ps1';target='mir/application/assurance/OfflineDrill.ps1'},
    @{path='tools/lib/mir4/EnvironmentEvidence.ps1';target='mir/application/assurance/EnvironmentEvidence.ps1'},
    @{path='tools/lib/mir4/OfflineCandidateCustody.ps1';target='mir/application/custody/OfflineCandidateCustody.ps1'},
    @{path='tools/commands/mir4/Export-MIR4AssuranceScaleRecords.ps1';target='mir/cli/Export-MIR4AssuranceScaleRecords.ps1'},
    @{path='tools/commands/mir4/Invoke-MIR4EnvironmentEvidence.ps1';target='mir/cli/Invoke-MIR4EnvironmentEvidence.ps1'}
  )
  foreach($binding in $bindings){$text=[IO.File]::ReadAllText((Join-Path $repo $binding.path)).Replace('\','/');if($text-cnotmatch[regex]::Escape([string]$binding.target)-or$text.Split([char]10).Count-gt3-or$text-match'(?m)^function\s+'){throw "[mir4-assurance-offline-custody-forwarder] $($binding.path)"}}
  return $true
}

function Test-MIR4AssuranceOfflineCustodyDeclaredConsumersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $custody='tools/mir/application/custody/OfflineCandidateCustody.ps1';$exporter='tools/mir/cli/Export-MIR4AssuranceScaleRecords.ps1';$environmentCli='tools/mir/cli/Invoke-MIR4EnvironmentEvidence.ps1'
  $requirements=[ordered]@{
    'tools/mir/application/inspection/CompatibilityFactory.ps1'=@('../assurance/EnvironmentEvidence.ps1')
    'tools/mir/application/processir/ExactProcessIR.ps1'=@('../assurance/EnvironmentEvidence.ps1')
    'tools/lib/mir4/PlatformPreview.ps1'=@('tools/mir/application/assurance/EnvironmentEvidence.ps1',$environmentCli)
    'tools/lib/mir4/PreFreezeRelease.ps1'=@('tools/mir/application/assurance/AssuranceScale.ps1')
    'tools/lib/mir4/SupplyChainAttestation.ps1'=@('../../mir/application/custody/OfflineCandidateCustody.ps1')
    'tools/lib/mir4/SigningCeremonyPreparation.ps1'=@('../../mir/application/custody/OfflineCandidateCustody.ps1')
    'validation/tests/mir4/Test-MIR4AssuranceScaleW08.ps1'=@('tools/mir/application/assurance/AssuranceScale.ps1','tools/mir/application/assurance/ReleaseBudget.ps1','tools/mir/application/assurance/OfflineDrill.ps1',$exporter)
    'validation/tests/mir4/Test-MIR4EnvironmentEvidenceT10.ps1'=@('tools/mir/application/assurance/EnvironmentEvidence.ps1',$environmentCli)
    'validation/tests/release/Test-MIR4OfflineCandidateCustody.ps1'=@($custody)
    'validation/tests.yml'=@('tools/mir/application/assurance/AssuranceScale.ps1','tools/mir/application/assurance/EnvironmentEvidence.ps1',$custody,$exporter,$environmentCli)
    '.mir/control/paths.yml'=@('tools/mir/application/assurance/AssuranceScale.ps1','tools/mir/application/assurance/EnvironmentEvidence.ps1',$custody,$exporter,$environmentCli)
    '.mir/modules.yml'=@('tools/mir/application/assurance/AssuranceScale.ps1','tools/mir/application/assurance/EnvironmentEvidence.ps1',$custody,$exporter,$environmentCli)
    '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json'=@('tools/mir/application/assurance/AssuranceScale.ps1','tools/mir/application/assurance/EnvironmentEvidence.ps1',$custody)
    '.mir/releases/governance/mir4/supply-chain.json'=@($custody)
    'tools/mir.ps1'=@($environmentCli,$exporter,'tools/mir/cli/Invoke-MIR4AssuranceOfflineCustodyMigration.ps1')
    'docs/architecture/module-boundaries.md'=@('tools/mir/application/assurance','tools/mir/application/custody')
  }
  foreach($entry in $requirements.GetEnumerator()){$text=[IO.File]::ReadAllText((Join-Path $repo ([string]$entry.Key))).Replace('\','/');foreach($required in @($entry.Value)){if($text-cnotmatch[regex]::Escape([string]$required)){throw "[mir4-assurance-offline-custody-consumer-final-path] $($entry.Key) -> $required"}}}
  return $true
}

function Get-MIR4AssuranceOfflineCustodyFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $critical=Get-MIR4W08CriticalPath -Tasks @([pscustomobject]@{id='capture';p95_seconds=3;depends_on=@()},[pscustomobject]@{id='verify';p95_seconds=5;depends_on=@('capture')},[pscustomobject]@{id='review';p95_seconds=4;depends_on=@('capture')},[pscustomobject]@{id='close';p95_seconds=2;depends_on=@('verify','review')})
  $proof=New-MIR4W08ProofCover -Obligations @([pscustomobject]@{id='f210';target='f210';environment='exact';trust='local'},[pscustomobject]@{id='f200';target='f200';environment='exact';trust='local'}) -Candidates @([pscustomobject]@{id='reuse-f200';covers=@('f200');target='f200';environment='exact';trust='local';action='REUSE';evidence_digest=('b'*64)},[pscustomobject]@{id='run-f210';covers=@('f210');target='f210';environment='exact';trust='local';action='RUN';evidence_digest=('a'*64)})
  $expected=@([pscustomobject]@{task_id='a';identity_key='i1';candidate_sha256='c1';target='f210';abi=1;trust='local'},[pscustomobject]@{task_id='b';identity_key='i2';candidate_sha256='c2';target='f200';abi=1;trust='local'})
  $completed=@([pscustomobject]@{task_id='a';identity_key='i1';candidate_sha256='c1';target='f210';abi=1;trust='local';status='passed';revoked=$false;object_digest='o1'})
  $recovery=Resolve-MIR4W08PartialRecovery -Expected $expected -Completed $completed
  $environment=New-MIR4ReferenceEnvironmentEvidenceV1 -RepoRoot $repo
  $binding=New-MIR4CustodyRecordBindingV1 -Role 'player-source-identity' -Record ([pscustomobject]@{kind='MIR4MigrationProbeV1';record_sha256=('c'*64)}) -Path (Join-Path $repo 'info.json')
  $invalidMode='';try{Assert-MIR4OfflineCustodyModeV1 -Mode 'publish' -Allowed 'proof-only'}catch{$invalidMode=$_.Exception.Message}
  $record=[ordered]@{
    w08=[ordered]@{critical_path=$critical;proof_cover=$proof;recovery=$recovery}
    environment=[ordered]@{f210_digest=[string]$environment.f210.digest;f200_digest=[string]$environment.f200.digest;diff_digest=[string]$environment.diff.digest;diff_summary=$environment.diff.summary;bundle_digest=[string]$environment.bundle.digest;minimized_digest=[string]$environment.minimized.digest}
    custody=[ordered]@{repo_root_ok=((Get-MIR4CustodyRepoRootV1 -RepoRoot $repo)-ceq$repo);descendant=(Test-MIR4CustodyDescendantPathV1 -Root (Join-Path $repo 'build') -Path (Join-Path $repo 'build/probe/value.json'));sibling=(Test-MIR4CustodyDescendantPathV1 -Root (Join-Path $repo 'build') -Path (Join-Path $repo 'dist/value.json'));binding=$binding;invalid_mode=$invalidMode}
    authority=[ordered]@{package_visible=$false;player_mutation_authorized=$false;prototype_write_authorized=$false;production_signing=$false;publication=$false;release_transition=$false}
  }
  $json=ConvertTo-MIR4CanonicalJsonV1 $record;$digest='sha256:'+([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($json))).ToLowerInvariant())
  return [pscustomobject][ordered]@{record=$record;digest=$digest}
}

function Test-MIR4AssuranceOfflineCustodyFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $result=Get-MIR4AssuranceOfflineCustodyFunctionalParityV1 -RepoRoot $RepoRoot;$record=$result.record
  if([int]$record.w08.critical_path.seconds-ne10-or@($record.w08.proof_cover.uncovered).Count-or@($record.w08.recovery.reusable).Count-ne1-or-not[bool]$record.custody.descendant-or[bool]$record.custody.sibling-or[bool]$record.authority.release_transition){throw '[mir4-assurance-offline-custody-functional-shape-parity]'}
  if([string]$result.digest-cne$script:MIR4AssuranceOfflineCustodyParityDigestV1){throw "[mir4-assurance-offline-custody-functional-parity] $([string]$result.digest)"}
  return $result
}

function New-MIR4AssuranceOfflineCustodyMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$migration=Get-MIR4AssuranceOfflineCustodyMigrationAuthorityV1 -RepoRoot $repo;$proof=Get-MIR4AssuranceOfflineCustodyMigrationProofPolicyV1 -RepoRoot $repo
  $prior=Get-MIR4PreFreezeAuthorityState -RepoRoot $repo -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration
  [void](Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4AssuranceOfflineCustodyPredecessorReceiptPath -ExpectedSha256 $script:MIR4AssuranceOfflineCustodyPredecessorReceiptSha256 -SchemaPath 'contracts/repository/mir4-inspector-compatibility-migration-receipt-v1.schema.json' -Kind 'MIR4InspectorCompatibilityMigrationReceiptV1' -DigestDomain 'mir4:inspector-compatibility-migration-receipt:1' -ErrorPrefix 'mir4-assurance-offline-custody-predecessor')
  [void](Test-MIR4AssuranceOfflineCustodyForwardersV1 -RepoRoot $repo);[void](Test-MIR4AssuranceOfflineCustodyDeclaredConsumersV1 -RepoRoot $repo);[void](Test-MIR4AssuranceOfflineCustodyFunctionalParityV1 -RepoRoot $repo)
  if((Get-MIR4AssuranceV4PreservationDigestV1 -RepoRoot $repo)-cne$script:MIR4AssuranceV4PreservationDigestV1){throw '[mir4-assurance-v4-authority-mutated]'}
  if((Get-FileHash -LiteralPath (Join-Path $repo '.mir/compatibility.yml') -Algorithm SHA256).Hash-cne$script:MIR4AssuranceOfflineCustodyCompatibilityPolicySha256){throw '[mir4-assurance-offline-custody-compatibility-policy-mutated]'}
  foreach($binding in @(@{path='.mir/releases/waves/mir4-r0/MIR4-T10-Authority-Evolution-ReceiptV1.json';sha=$script:MIR4AssuranceOfflineCustodyT10ReceiptSha256},@{path='.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json';sha=$script:MIR4AssuranceOfflineCustodyT15ReceiptSha256},@{path='.mir/releases/waves/mir4-r0/MIR4-T15-Independent-Machine-AcceptanceV1.json';sha=$script:MIR4AssuranceOfflineCustodyT15AcceptanceSha256})){if((Get-FileHash -LiteralPath (Join-Path $repo $binding.path) -Algorithm SHA256).Hash-cne[string]$binding.sha){throw "[mir4-assurance-offline-custody-historical-evidence-mutated] $($binding.path)"}}
  $integrationPaths=@(
    '.gitattributes','.mir/assurance.json','.mir/compatibility.yml','.mir/control/repository-fixed-point.json','.mir/control/paths.yml','.mir/control-plane/ownership.json','.mir/modules.yml','.mir/docs.yml','.mir/releases/governance/mir4/supply-chain.json',
    '.mir/releases/waves/mir4-r0/MIR4-Assurance-Scale-ProgrammeV1.json','.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json','.mir/releases/waves/mir4-r0/MIR4-T10-Authority-Evolution-ReceiptV1.json','.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json','.mir/releases/waves/mir4-r0/MIR4-T15-Independent-Machine-AcceptanceV1.json',
    'assurance/.mir-root.json','governance/.mir-root.json','tests/.mir-root.json','validation/tests.yml','tools/mir.ps1','mir.lock','spec/schemas/mir4-assurance-scale-programme-v1.schema.json',
    'tools/lib/mir4/PlatformPreview.ps1','tools/lib/mir4/PreFreezeRelease.ps1','tools/lib/mir4/SupplyChainAttestation.ps1','tools/lib/mir4/SigningCeremonyPreparation.ps1','tools/lib/assurance/Evidence.ps1','tools/mir/application/processir/ExactProcessIR.ps1','tools/mir/application/inspection/CompatibilityFactory.ps1',
    'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1','tools/mir/application/inspection/InspectorCompatibilityMigration.ps1','tools/mir/cli/Invoke-MIR4InspectorCompatibilityMigration.ps1','tests/inspection/Test-MIR4InspectorCompatibilityMigration.ps1',
    'validation/tests/mir4/Test-MIR4AssuranceScaleW08.ps1','validation/tests/mir4/Test-MIR4EnvironmentEvidenceT10.ps1','validation/tests/release/Test-MIR4OfflineCandidateCustody.ps1','validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1','validation/tests/tooling/Test-MIRAssurance.ps1',
    'docs/architecture/mir4-repository-fixed-point.md','docs/architecture/mir4-assurance-scale.md','docs/architecture/module-boundaries.md','docs/developer/environment-locks.md','docs/reference/generated/mir4-platform-component-matrix.md','docs/reference/generated/mir4-whole-platform-matrix.md','docs/releases/mir4-4.0-whole-platform-programme.md'
  )
  $parity=[ordered]@{canonical_writer_count=@($migration.writers).Count;shared_migration_engine=$true;compatibility_forwarders_verified=$true;assurance_functional_parity=$true;environment_evidence_functional_parity=$true;offline_custody_functional_parity=$true;assurance_export_command_parity=$true;environment_cli_command_parity=$true;declared_consumers_use_final_paths=$true;focused_test_registered=$true;assurance_v4_read_only=$true;compatibility_policy_read_only=$true;historical_t10_evidence_read_only=$true;historical_t15_evidence_read_only=$true;player_runtime_authority_read_only=$true;predecessor_writer_disabled=$true;release_history_successor_verified=$true;release_history_fingerprint_bound=$true;authority_schema_verified=$true;assurance_schema_verified=$true;rollback_recorded=(-not[string]::IsNullOrWhiteSpace([string]$migration.rollback.command));duplicate_writers=@()}
  return New-MIR4AppendOnlyAuthorityMigrationReceiptV1 -RepoRoot $repo -Migration $migration -Proof $proof -Prior $prior -ReceiptKind 'MIR4AssuranceOfflineCustodyMigrationReceiptV1' -ReceiptState 'ASSURANCE-ENVIRONMENT-AND-OFFLINE-CUSTODY-APPLICATION-CLI-AND-TEST-CUTOVER-VERIFIED-COMPATIBILITY-RETAINED' -ReceiptPath $script:MIR4AssuranceOfflineCustodyMigrationReceiptPath -MigrationAuthorityPath $script:MIR4AssuranceOfflineCustodyMigrationAuthorityPath -AssurancePath $script:MIR4AssuranceOfflineCustodyMigrationProofPath -Scope 'package-excluded-assurance-offline-custody-migration' -EvolutionReason 'Package-excluded W08 assurance-scale, T10 environment-evidence, and proof-only offline-custody tooling migration with Assurance v4, compatibility policy, immutable historical T10/T15 evidence, player-runtime, and release-authority firewalls.' -DigestDomain 'mir4:assurance-offline-custody-migration-receipt:1' -Parity $parity -IntegrationPaths $integrationPaths
}

function Get-MIR4AssuranceOfflineCustodyMigrationReceiptTextV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (ConvertTo-MIR4CanonicalJsonV1 -Value (New-MIR4AssuranceOfflineCustodyMigrationReceiptV1 -RepoRoot $RepoRoot))+[char]10
}

function Invoke-MIR4AssuranceOfflineCustodyMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  if(-not$Check){throw '[mir4-assurance-offline-custody-migration-receipt-immutable] generation-disabled-after-successor-cutover'}
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $receipt=Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $repo -ReceiptPath $script:MIR4AssuranceOfflineCustodyMigrationReceiptPath -ExpectedSha256 $script:MIR4AssuranceOfflineCustodyMigrationReceiptSha256 -SchemaPath $script:MIR4AssuranceOfflineCustodyMigrationReceiptSchemaPath -Kind 'MIR4AssuranceOfflineCustodyMigrationReceiptV1' -DigestDomain 'mir4:assurance-offline-custody-migration-receipt:1' -ErrorPrefix 'mir4-assurance-offline-custody-migration'
  if((Get-Item -LiteralPath (Join-Path $repo $script:MIR4AssuranceOfflineCustodyMigrationReceiptPath)).Length-ne$script:MIR4AssuranceOfflineCustodyMigrationReceiptBytes){throw '[mir4-assurance-offline-custody-migration-receipt-byte-length]'}
  return $receipt
}
