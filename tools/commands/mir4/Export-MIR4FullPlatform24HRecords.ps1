param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot = 'build/mir4/m4c02-full-platform-24h',
  [string]$VerificationPlanPath = '',
  [string]$VerificationSummaryPath = '',
  [string]$EvidenceBundlePath = '',
  [string]$LunaAuditPath = '',
  [switch]$Check
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/FullPlatformCloseout.ps1')

$tracked = @(& git -C $repo status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0 -or $tracked.Count -ne 0) { throw '[mir4-full-platform-source-dirty]' }
$source = [pscustomobject][ordered]@{
  programme_id = 'M4C02-09-24H'
  commit = (& git -C $repo rev-parse HEAD).Trim()
  tree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  source_version = '4.0.0'
  package_source_sha256 = Get-MIRPackageSourceFingerprint -RepoRoot $repo
}
$output = [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$allowed = [IO.Path]::GetFullPath((Join-Path $repo 'build/mir4')).TrimEnd('\') + '\'
if (-not ($output + '\').StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw "[mir4-full-platform-output-boundary] $output" }

function Read-RepoJson([string]$Path) {
  $full = Join-Path $repo $Path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-full-platform-input-missing] $Path" }
  return Get-Content -Raw -LiteralPath $full | ConvertFrom-Json -Depth 100
}
function Get-ObservedStatus($Record) {
  foreach ($name in @('status','state','classification','result')) {
    if ($Record.PSObject.Properties.Name -contains $name -and -not [string]::IsNullOrWhiteSpace([string]$Record.$name)) { return [string]$Record.$name }
  }
  return 'recorded'
}
function Assert-CurrentSourceBinding($Record, [string]$Path) {
  if ($Record.PSObject.Properties.Name -contains 'source_identity') {
    if ($Record.source_identity.PSObject.Properties.Name -contains 'commit' -and [string]$Record.source_identity.commit -cne [string]$source.commit) { throw "[mir4-full-platform-stale-commit] $Path" }
    if ($Record.source_identity.PSObject.Properties.Name -contains 'tree' -and [string]$Record.source_identity.tree -cne [string]$source.tree) { throw "[mir4-full-platform-stale-tree] $Path" }
  }
  if ($Record.PSObject.Properties.Name -contains 'source_commit' -and [string]$Record.source_commit -cne [string]$source.commit) { throw "[mir4-full-platform-stale-commit] $Path" }
  if ($Record.PSObject.Properties.Name -contains 'source_tree' -and [string]$Record.source_tree -cne [string]$source.tree) { throw "[mir4-full-platform-stale-tree] $Path" }
}
function Add-Record([string]$Name, $Value) { $script:records[$Name] = $Value }
function New-AuthorityRef([string]$Path, [string]$Role='authority') { return New-MIR4FullPlatformEvidenceRef -RepoRoot $repo -Path $Path -Role $Role }
function New-WrappedWaveRecord($Definition) {
  $record = Read-RepoJson $Definition.path
  Assert-CurrentSourceBinding $record $Definition.path
  $refs = @((New-AuthorityRef $Definition.path 'source-record'), (New-AuthorityRef $Definition.authority 'governing-authority'))
  if ($Definition.schema) { $refs += New-AuthorityRef $Definition.schema 'source-record-schema' }
  $payload = [ordered]@{
    wave = $Definition.wave
    source_record_path = $Definition.path
    source_record_sha256 = Get-MIR4FullPlatformFileSha256 (Join-Path $repo $Definition.path)
    source_record_validator = $Definition.validator
    source_record = $record
  }
  return New-MIR4FullPlatformRecord -SourceIdentity $source -Kind $Definition.kind -Status (Get-ObservedStatus $record) -Maturity $Definition.maturity -AuthorityId $Definition.authority_id -AuthorityMode 'read-only-composition' -AuthoritySourcePaths @($Definition.authority) -EvidenceRefs $refs -Payload $payload
}

$records = [ordered]@{}
$governancePath = '.mir/releases/governance/mir4/release-governance.json'
$signersPath = '.mir/releases/governance/mir4/allowed-signers.json'
$governance = Read-RepoJson $governancePath
$allowedSigners = Read-RepoJson $signersPath
$governanceRefs = @((New-AuthorityRef $governancePath 'governing-authority'), (New-AuthorityRef 'validation/tests/mir4/Test-MIR4ReleaseGovernanceW00.ps1' 'validator'))
$signerRefs = @((New-AuthorityRef $signersPath 'governing-authority'), (New-AuthorityRef $governancePath 'governance-contract'))

$readiness = & (Join-Path $repo 'tools/commands/mir4/Invoke-MIR4ReleaseGovernance.ps1') -Command check -RepoRoot $repo | Out-String | ConvertFrom-Json -Depth 100
$publisherStatus = if ($readiness.publisher.inventory.exists -and @($readiness.publisher.inventory.forbidden).Count -eq 0) { 'confinement-passed' } else { 'confinement-failed' }
Add-Record 'MIR4_RELEASE_GOVERNANCE_READINESS.json' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4ReleaseGovernanceReadinessFinalV1' -Status ([string]$readiness.classification) -Maturity 'blocked-with-evidence' -AuthorityId 'mir4-release-governance-v1' -AuthorityMode canonical -AuthoritySourcePaths @($governancePath) -EvidenceRefs $governanceRefs -Payload ([ordered]@{readiness=$readiness;secret_values_present=$false}))
Add-Record 'MIR4_SIGNING_AUTHORITY_PUBLIC.json' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4SigningAuthorityPublicFinalV1' -Status ([string]$governance.state) -Maturity 'blocked-with-evidence' -AuthorityId 'mir4-release-governance-v1' -AuthorityMode canonical -AuthoritySourcePaths @($governancePath) -EvidenceRefs $governanceRefs -Payload ([ordered]@{signing_authority=$governance.signing_authority;secret_values_present=$false;production_signing_authorized=$false}))
Add-Record 'MIR4_ALLOWED_SIGNERS' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4AllowedSignersFinalV1' -Status ([string]$allowedSigners.state) -Maturity 'blocked-with-evidence' -AuthorityId 'mir4-allowed-signers-v1' -AuthorityMode canonical -AuthoritySourcePaths @($signersPath) -EvidenceRefs $signerRefs -Payload ([ordered]@{allowed_signers=$allowedSigners;production_signing_authorized=$false}))
Add-Record 'MIR4_KEY_RECOVERY_TEST.json' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4KeyRecoveryTestFinalV1' -Status 'BLOCKED-HUMAN-SECRET-INPUT' -Maturity 'blocked-with-evidence' -AuthorityId 'mir4-release-governance-v1' -AuthorityMode canonical -AuthoritySourcePaths @($governancePath) -EvidenceRefs $governanceRefs -Payload ([ordered]@{requirements=$governance.recovery;test_executed=$false;reason='Protected private-key authority is unavailable; no substitute or plaintext recovery material was created.'}))
Add-Record 'MIR4_LEDGER_INITIALIZATION.json' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4LedgerInitializationFinalV1' -Status 'BLOCKED-HUMAN-SECRET-INPUT' -Maturity 'blocked-with-evidence' -AuthorityId 'mir4-release-governance-v1' -AuthorityMode canonical -AuthoritySourcePaths @($governancePath) -EvidenceRefs $governanceRefs -Payload ([ordered]@{ledger=$governance.ledger;initialized=$false;reason='The append-only ledger must not be initialized unsigned or with a substitute key.'}))
Add-Record 'MIR4_PUBLISHER_CONFINEMENT.json' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4PublisherConfinementFinalV1' -Status $publisherStatus -Maturity 'stable-governance' -AuthorityId 'mir4-release-governance-v1' -AuthorityMode canonical -AuthoritySourcePaths @($governancePath) -EvidenceRefs $governanceRefs -Payload ([ordered]@{publisher=$governance.publisher;observation=$readiness.publisher;publication_authorized=$false}))

$fixedPath = '.mir/control/repository-fixed-point.json'
$ownershipPath = '.mir/control-plane/ownership.json'
$pathsPath = '.mir/control/paths.yml'
$modulesPath = '.mir/modules.yml'
$fixed = Read-RepoJson $fixedPath
$ownership = Read-RepoJson $ownershipPath
$fixedResult = & (Join-Path $repo 'tools/commands/mir4/Invoke-MIR4RepositoryFixedPoint.ps1') -Command check -RepoRoot $repo | Out-String | ConvertFrom-Json -Depth 100
$fixedRefs = @((New-AuthorityRef $fixedPath 'governing-authority'), (New-AuthorityRef $pathsPath 'path-authority'), (New-AuthorityRef $ownershipPath 'ownership-authority'), (New-AuthorityRef 'validation/tests/mir4/Test-MIR4RepositoryFixedPointW01.ps1' 'validator'))
Add-Record 'MIR4_AUTHORITY_MAP_FINAL.json' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4AuthorityMapFinalV1' -Status 'accepted-one-writer-authority-map' -Maturity 'stable-shadow' -AuthorityId 'mir4-control-plane-ownership' -AuthorityMode canonical -AuthoritySourcePaths @($ownershipPath,$modulesPath,$pathsPath) -EvidenceRefs (@($fixedRefs)+(New-AuthorityRef $modulesPath 'module-boundary-authority')) -Payload ([ordered]@{ownership=$ownership;one_writable_authority_required=$true;physical_cutover=$false}))
Add-Record 'MIR4_REPOSITORY_FIXED_POINT.json' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4RepositoryFixedPointFinalV1' -Status ([string]$fixed.state) -Maturity 'stable-shadow' -AuthorityId 'mir4-repository-fixed-point-v1' -AuthorityMode canonical -AuthoritySourcePaths @($fixedPath) -EvidenceRefs $fixedRefs -Payload ([ordered]@{authority=$fixed;observation=$fixedResult}))
$pathRows = @($fixed.visible_roots | ForEach-Object { [ordered]@{root=[string]$_.id;destination=[string]$_.path;mode=[string]$_.mode;current_authorities=@($_.current_authorities);writer_cutover=$false;deletion_authorized=$false} })
Add-Record 'MIR4_PATH_MIGRATION_MATRIX.json' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4PathMigrationMatrixFinalV1' -Status 'shadow-readers-active-physical-cutover-deferred' -Maturity 'stable-shadow' -AuthorityId 'mir4-repository-fixed-point-v1' -AuthorityMode canonical -AuthoritySourcePaths @($fixedPath,$pathsPath) -EvidenceRefs $fixedRefs -Payload ([ordered]@{rows=$pathRows;move_gate=@($fixed.move_gate);physical_cutover=$false;rollback=[string]$fixed.remaining_move.rollback}))
$shimRows = @($fixed.visible_roots | Where-Object { [string]$_.mode -match '^shadow' } | ForEach-Object { [ordered]@{root=[string]$_.id;shim_path=[string]$_.path;mode=[string]$_.mode;debt='bounded-shadow-reader';removal_gate=@($fixed.move_gate)} })
Add-Record 'MIR4_SHIM_DEBT_REGISTER.json' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4ShimDebtRegisterFinalV1' -Status 'bounded-shadow-debt' -Maturity 'stable-shadow' -AuthorityId 'mir4-repository-fixed-point-v1' -AuthorityMode canonical -AuthoritySourcePaths @($fixedPath) -EvidenceRefs $fixedRefs -Payload ([ordered]@{rows=$shimRows;remaining_move=$fixed.remaining_move;writer_cutover_authorized=$false}))

$definitions = @(
  @{name='MIR4_TARGET_PROVIDER_MATRIX.json';kind='MIR4TargetProviderMatrixFinalV1';wave='W02';path='build/mir4/m4c02-target-products/MIR4_TARGET_PROVIDER_MATRIX.json';authority='.mir/releases/waves/mir4-r0/MIR4-Target-Compiler-ProgrammeV1.json';authority_id='mir4-target-compiler-v1';maturity='mixed';schema='';validator='static.mir4-target-compiler-w02'},
  @{name='MIR4_TARGET_DISPOSITION_MATRIX.json';kind='MIR4TargetDispositionMatrixFinalV1';wave='W02';path='build/mir4/m4c02-target-products/MIR4_TARGET_DISPOSITION_MATRIX.json';authority='.mir/releases/waves/mir4-r0/MIR4-Target-Compiler-ProgrammeV1.json';authority_id='mir4-target-compiler-v1';maturity='mixed';schema='';validator='static.mir4-target-compiler-w02'},
  @{name='MIR4_PRIVATE_PACKAGE_MATRIX.json';kind='MIR4PrivatePackageMatrixFinalV1';wave='W02';path='build/mir4/m4c02-target-products/MIR4_PRIVATE_PACKAGE_MATRIX.json';authority='.mir/releases/waves/mir4-r0/MIR4-Target-Compiler-ProgrammeV1.json';authority_id='mir4-target-compiler-v1';maturity='mixed';schema='';validator='static.mir4-target-compiler-w02'},
  @{name='MIR4_COMPILATION_RUN_CONTRACT.json';kind='MIR4CompilationRunContractFinalV1';wave='W03';path='build/mir4/m4c02-semantic-compiler/MIR4_COMPILATION_RUN_CONTRACT.json';authority='.mir/releases/waves/mir4-r0/MIR4-Semantic-Compiler-ProgrammeV1.json';authority_id='mir4-semantic-compiler-v1';maturity='shadow';schema='spec/schemas/mir4-compilation-run-v1.schema.json';validator='static.mir4-semantic-compiler-w03'},
  @{name='MIR4_FEATURE_SETTING_CUTOVER_MATRIX.json';kind='MIR4FeatureSettingCutoverMatrixFinalV1';wave='W03';path='build/mir4/m4c02-semantic-compiler/MIR4_FEATURE_SETTING_CUTOVER_MATRIX.json';authority='.mir/releases/waves/mir4-r0/MIR4-Semantic-Compiler-ProgrammeV1.json';authority_id='mir4-semantic-compiler-v1';maturity='shadow';schema='';validator='static.mir4-semantic-compiler-w03'},
  @{name='MIR4_PROVIDER_MICRO_PROTOCOL_MATRIX.json';kind='MIR4ProviderMicroProtocolMatrixFinalV1';wave='W03';path='build/mir4/m4c02-semantic-compiler/MIR4_PROVIDER_MICRO_PROTOCOL_MATRIX.json';authority='.mir/releases/waves/mir4-r0/MIR4-Semantic-Compiler-ProgrammeV1.json';authority_id='mir4-semantic-compiler-v1';maturity='shadow';schema='';validator='static.mir4-semantic-compiler-w03'},
  @{name='MIR4_MERGE_LAW_CATALOGUE.json';kind='MIR4MergeLawCatalogueFinalV1';wave='W03';path='build/mir4/m4c02-semantic-compiler/MIR4_MERGE_LAW_CATALOGUE.json';authority='.mir/releases/waves/mir4-r0/MIR4-Semantic-Compiler-ProgrammeV1.json';authority_id='mir4-semantic-compiler-v1';maturity='shadow';schema='';validator='static.mir4-semantic-compiler-w03'},
  @{name='MIR4_RUNTIME_STATE_MATRIX.json';kind='MIR4RuntimeStateMatrixFinalV1';wave='W04';path='build/mir4/m4c02-runtime-continuity/MIR4_RUNTIME_STATE_MATRIX.json';authority='.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json';authority_id='mir4-runtime-continuity-v1';maturity='shadow';schema='spec/schemas/mir4-runtime-state-matrix-v1.schema.json';validator='static.mir4-runtime-continuity-w04'},
  @{name='MIR4_MIGRATION_GRAPH_MATRIX.json';kind='MIR4MigrationGraphMatrixFinalV1';wave='W04';path='build/mir4/m4c02-runtime-continuity/MIR4_MIGRATION_GRAPH_MATRIX.json';authority='.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json';authority_id='mir4-runtime-continuity-v1';maturity='shadow';schema='spec/schemas/mir4-migration-graph-matrix-v1.schema.json';validator='static.mir4-runtime-continuity-w04'},
  @{name='MIR4_CONTINUITY_BUNDLE.json';kind='MIR4ContinuityBundleFinalV1';wave='W04';path='build/mir4/m4c02-runtime-continuity/MIR4_CONTINUITY_BUNDLE.json';authority='.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json';authority_id='mir4-runtime-continuity-v1';maturity='shadow';schema='spec/schemas/mir4-continuity-bundle-v1.schema.json';validator='static.mir4-runtime-continuity-w04'},
  @{name='MIR4_MEP_CONFORMANCE.json';kind='MIR4MEPConformanceFinalV1';wave='W05';path='build/mir4/m4c02-module-ecosystem/MIR4_MEP_CONFORMANCE.json';authority='.mir/releases/waves/mir4-r0/MIR4-Module-Ecosystem-ProgrammeV1.json';authority_id='mir4-module-ecosystem-v1';maturity='preview';schema='';validator='static.mir4-module-ecosystem-w05'},
  @{name='MIR4_API_SDK_GRADUATION_MATRIX.json';kind='MIR4ApiSdkGraduationMatrixFinalV1';wave='W05';path='build/mir4/m4c02-module-ecosystem/MIR4_API_SDK_GRADUATION_MATRIX.json';authority='.mir/releases/waves/mir4-r0/MIR4-Module-Ecosystem-ProgrammeV1.json';authority_id='mir4-module-ecosystem-v1';maturity='preview';schema='';validator='static.mir4-module-ecosystem-w05'},
  @{name='MIR4_REFERENCE_CONSUMER_RESULT.json';kind='MIR4ReferenceConsumerResultFinalV1';wave='W05';path='build/mir4/m4c02-module-ecosystem/MIR4_REFERENCE_CONSUMER_RESULT.json';authority='.mir/releases/waves/mir4-r0/MIR4-Module-Ecosystem-ProgrammeV1.json';authority_id='mir4-module-ecosystem-v1';maturity='preview';schema='';validator='static.mir4-module-ecosystem-w05'},
  @{name='MIR4_PROCESSIR_PARITY_RESULT.json';kind='MIR4ProcessIRParityResultFinalV1';wave='W06';path='build/mir4/m4c02-processir-synthesis/MIR4_PROCESSIR_PARITY_RESULT.json';authority='.mir/releases/waves/mir4-r0/MIR4-ProcessIR-Synthesis-ProgrammeV1.json';authority_id='mir4-processir-synthesis-v1';maturity='preview';schema='spec/schemas/mir4-process-ir-v1.schema.json';validator='static.mir4-processir-synthesis-w06'},
  @{name='MIR4_EFFECT_CHANNEL_REGISTRY.json';kind='MIR4EffectChannelRegistryFinalV1';wave='W06';path='build/mir4/m4c02-processir-synthesis/MIR4_EFFECT_CHANNEL_REGISTRY.json';authority='.mir/releases/waves/mir4-r0/MIR4-ProcessIR-Synthesis-ProgrammeV1.json';authority_id='mir4-processir-synthesis-v1';maturity='preview';schema='spec/schemas/mir4-effect-channel-registry-v1.schema.json';validator='static.mir4-processir-synthesis-w06'},
  @{name='MIR4_SYNTHESIS_MATURITY_MATRIX.json';kind='MIR4SynthesisMaturityMatrixFinalV1';wave='W06';path='build/mir4/m4c02-processir-synthesis/MIR4_SYNTHESIS_MATURITY_MATRIX.json';authority='.mir/releases/waves/mir4-r0/MIR4-ProcessIR-Synthesis-ProgrammeV1.json';authority_id='mir4-processir-synthesis-v1';maturity='preview';schema='spec/schemas/mir4-synthesis-maturity-matrix-v1.schema.json';validator='static.mir4-processir-synthesis-w06'},
  @{name='MIR4_INSPECTOR_WORKBENCH_RESULT.json';kind='MIR4InspectorWorkbenchResultFinalV1';wave='W07';path='build/mir4/m4c02-inspector-compatibility/MIR4_INSPECTOR_WORKBENCH_RESULT.json';authority='.mir/releases/waves/mir4-r0/MIR4-Inspector-Compatibility-ProgrammeV1.json';authority_id='mir4-inspector-compatibility-v1';maturity='preview';schema='spec/schemas/mir4-inspector-workbench-result-v1.schema.json';validator='static.mir4-inspector-compatibility-w07'},
  @{name='MIR4_COMPATIBILITY_SUBJECT_LEDGER.json';kind='MIR4CompatibilitySubjectLedgerFinalV1';wave='W07';path='build/mir4/m4c02-inspector-compatibility/MIR4_COMPATIBILITY_SUBJECT_LEDGER.json';authority='.mir/releases/waves/mir4-r0/MIR4-Inspector-Compatibility-ProgrammeV1.json';authority_id='mir4-inspector-compatibility-v1';maturity='preview';schema='spec/schemas/mir4-compatibility-subject-ledger-v1.schema.json';validator='static.mir4-inspector-compatibility-w07'},
  @{name='MIR4_ASSURANCE_SCALE_RESULT.json';kind='MIR4AssuranceScaleResultFinalV1';wave='W08';path='build/mir4/m4c02-assurance-scale/MIR4_ASSURANCE_SCALE_RESULT.json';authority='.mir/releases/waves/mir4-r0/MIR4-Assurance-Scale-ProgrammeV1.json';authority_id='mir4-assurance-scale-v1';maturity='mixed';schema='spec/schemas/mir4-assurance-scale-result-v1.schema.json';validator='static.mir4-assurance-scale-w08'},
  @{name='MIR4_RELEASE_BUDGET_PLAN.json';kind='MIR4ReleaseBudgetPlanFinalV1';wave='W08';path='build/mir4/m4c02-assurance-scale/MIR4_RELEASE_BUDGET_PLAN.json';authority='.mir/releases/waves/mir4-r0/MIR4-Assurance-Scale-ProgrammeV1.json';authority_id='mir4-assurance-scale-v1';maturity='mixed';schema='spec/schemas/mir4-release-budget-plan-v1.schema.json';validator='static.mir4-assurance-scale-w08'},
  @{name='MIR4_OFFLINE_DRILL_RESULT.json';kind='MIR4OfflineDrillResultFinalV1';wave='W08';path='build/mir4/m4c02-assurance-scale/MIR4_OFFLINE_DRILL_RESULT.json';authority='.mir/releases/waves/mir4-r0/MIR4-Assurance-Scale-ProgrammeV1.json';authority_id='mir4-assurance-scale-v1';maturity='mixed';schema='spec/schemas/mir4-offline-drill-result-v1.schema.json';validator='static.mir4-assurance-scale-w08'},
  @{name='MIR4_HISTORICAL_MUSEUM_MATRIX.json';kind='MIR4HistoricalMuseumMatrixFinalV1';wave='W09';path='build/mir4/m4c02-historical-succession/MIR4_HISTORICAL_MUSEUM_MATRIX.json';authority='.mir/releases/waves/mir4-r0/MIR4-Historical-Succession-ProgrammeV1.json';authority_id='mir4-historical-succession-v1';maturity='mixed';schema='spec/schemas/mir4-historical-museum-matrix-v1.schema.json';validator='static.mir4-historical-succession-w09'},
  @{name='MIR4_SUCCESSOR_HOST_RESULT.json';kind='MIR4SuccessorHostResultFinalV1';wave='W09';path='build/mir4/m4c02-historical-succession/MIR4_SUCCESSOR_HOST_RESULT.json';authority='.mir/releases/waves/mir4-r0/MIR4-Historical-Succession-ProgrammeV1.json';authority_id='mir4-historical-succession-v1';maturity='mixed';schema='spec/schemas/mir4-successor-host-result-v1.schema.json';validator='static.mir4-historical-succession-w09'}
)
foreach ($definition in $definitions) { Add-Record $definition.name (New-WrappedWaveRecord $definition) }

$gateRefs = @()
$gatePaths = @($VerificationPlanPath,$VerificationSummaryPath,$EvidenceBundlePath)
if (@($gatePaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -notin @(0,3)) { throw '[mir4-full-platform-gate-input-set-incomplete]' }
if (-not [string]::IsNullOrWhiteSpace($VerificationPlanPath)) {
  $verificationPlan = Read-RepoJson $VerificationPlanPath
  $verificationSummary = Read-RepoJson $VerificationSummaryPath
  $evidenceBundle = Read-RepoJson $EvidenceBundlePath
  if (-not (Test-MIR4FullPlatformGateBinding -Plan $verificationPlan -Summary $verificationSummary -Bundle $evidenceBundle -SourceIdentity $source)) { throw '[mir4-full-platform-gate-evidence-invalid-or-stale]' }
}
foreach ($gate in @(
  @{path=$VerificationPlanPath;role='verification-plan'},
  @{path=$VerificationSummaryPath;role='verification-summary'},
  @{path=$EvidenceBundlePath;role='aggregate-evidence-bundle'}
)) { if (-not [string]::IsNullOrWhiteSpace([string]$gate.path)) { $gateRefs += New-AuthorityRef $gate.path $gate.role } }
if ($gateRefs.Count -eq 0) { $gateRefs += New-AuthorityRef 'validation/tests.yml' 'required-test-registry' }

$audit = $null
$auditAccepted = $false
$auditRefs = @()
if (-not [string]::IsNullOrWhiteSpace($LunaAuditPath)) {
  $auditFull = if ([IO.Path]::IsPathRooted($LunaAuditPath)) { $LunaAuditPath } else { Join-Path $repo $LunaAuditPath }
  $audit = Get-Content -Raw -LiteralPath $auditFull | ConvertFrom-Json -Depth 100
  if (-not ((Get-Content -Raw -LiteralPath $auditFull) | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-luna-audit-input-v1.schema.json')) -or -not (Test-MIR4FullPlatformAuditInput -Audit $audit -SourceIdentity $source)) { throw '[mir4-full-platform-luna-audit-invalid-or-stale]' }
  $auditAccepted = [string]$audit.decision -ceq 'ACCEPT' -and [string]$audit.merge_recommendation -ceq 'APPROVE'
  $auditRefs += New-MIR4FullPlatformEvidenceRef -RepoRoot $repo -Path $auditFull -Role 'independent-luna-audit-input'
} else {
  $auditRefs += New-AuthorityRef 'spec/schemas/mir4-luna-audit-input-v1.schema.json' 'independent-audit-input-contract'
}

$blockers = @(Get-MIR4FullPlatformBlockers)
$waveRows = @(
  [ordered]@{wave='W00';status='partial-with-bounded-blocker';blocking_ids=@('BLOCKED-HUMAN-SECRET-INPUT')},
  [ordered]@{wave='W01';status='accepted-shadow-fixed-point';blocking_ids=@()},
  [ordered]@{wave='W02';status='accepted-private-target-compiler';blocking_ids=@('BLOCKED-MUSEUM-RIGHTS-CUSTODY-RESTORE-CLOSURE')},
  [ordered]@{wave='W03';status='accepted-shadow-semantic-compiler';blocking_ids=@()},
  [ordered]@{wave='W04';status='accepted-private-runtime-continuity';blocking_ids=@()},
  [ordered]@{wave='W05';status='partial-with-bounded-blocker';blocking_ids=@('BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER')},
  [ordered]@{wave='W06';status='accepted-exact-target-preview-with-custody-gap';blocking_ids=@('BLOCKED-EXACT-ARCHIVE-CUSTODY-F200-K2SO')},
  [ordered]@{wave='W07';status='accepted-private-inspector-compatibility';blocking_ids=@('BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER')},
  [ordered]@{wave='W08';status='partial-with-bounded-blocker';blocking_ids=@('BLOCKED-MISSING-TRUSTED-TIMING-CAPACITY-EVIDENCE')},
  [ordered]@{wave='W09';status='partial-with-bounded-blockers';blocking_ids=@('BLOCKED-FUTURE-INDEPENDENT-PRODUCTION-HOST','BLOCKED-MISSING-EXACT-ENGINE-f018','BLOCKED-MUSEUM-RIGHTS-CUSTODY-RESTORE-CLOSURE')}
)
$finalAuthority = @('tools/commands/mir4/Export-MIR4FullPlatform24HRecords.ps1','spec/schemas/mir4-full-platform-record-v1.schema.json')
$finalRefs = @($gateRefs) + @((New-AuthorityRef 'spec/schemas/mir4-full-platform-record-v1.schema.json' 'final-record-schema'))
Add-Record 'MIR4_FULL_PLATFORM_24H_COMPLETION_RECORD.json' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4FullPlatform24HCompletionRecordV1' -Status $(if($auditAccepted){'PARTIAL-WITH-BOUNDED-BLOCKERS'}else{'PENDING-INDEPENDENT-LUNA-AUDIT'}) -Maturity mixed -AuthorityId 'mir4-full-platform-closeout-v1' -AuthorityMode evidence-only-aggregation -AuthoritySourcePaths $finalAuthority -EvidenceRefs $finalRefs -Payload ([ordered]@{result_class=$(if($auditAccepted){'PARTIAL-WITH-BOUNDED-BLOCKERS'}else{'PENDING-INDEPENDENT-LUNA-AUDIT'});waves=$waveRows;required_records=39;implementation_complete=$true;private_fixed_point_complete=$true;mandatory_release_gates_green=$false;source_frozen=$false;production_seal_created=$false;publication_authorized=$false;dev_sync_authorized=$false}))
Add-Record 'MIR4_FULL_PLATFORM_24H_BLOCKER_MATRIX.json' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4FullPlatform24HBlockerMatrixV1' -Status 'bounded-external-and-human-blockers-open' -Maturity blocked-with-evidence -AuthorityId 'mir4-full-platform-closeout-v1' -AuthorityMode evidence-only-aggregation -AuthoritySourcePaths $finalAuthority -EvidenceRefs $finalRefs -Payload ([ordered]@{blockers=$blockers;hard_safety_blockers=@('BLOCKED-HUMAN-SECRET-INPUT');forced_completion_permitted=$false}))
Add-Record 'MIR4_FULL_PLATFORM_24H_LUNA_ACCEPTANCE.json' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4FullPlatform24HLunaAcceptanceV1' -Status $(if($auditAccepted){'accepted'}else{'pending-independent-audit'}) -Maturity mixed -AuthorityId 'independent-luna-audit' -AuthorityMode external-independent-audit -AuthoritySourcePaths @('spec/schemas/mir4-luna-audit-input-v1.schema.json') -EvidenceRefs $auditRefs -Payload ([ordered]@{audit_supplied=($null-ne$audit);accepted=$auditAccepted;audit=$audit}))
Add-Record 'MIR4_FULL_PLATFORM_24H_DEV_MERGE_RECEIPT.json' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4FullPlatform24HDevMergeReceiptV1' -Status 'blocked-not-attempted' -Maturity blocked-with-evidence -AuthorityId 'mir4-dev-integration-gate' -AuthorityMode evidence-only-aggregation -AuthoritySourcePaths $finalAuthority -EvidenceRefs (@($finalRefs)+$auditRefs) -Payload ([ordered]@{push_attempted=$false;pr_opened=$false;dev_merge_attempted=$false;remote_dev_readback=$false;reason='Dev integration preconditions are false because open hard-safety and external proof blockers remain; hosted CI was therefore not invoked as a bypass.';main_modified=$false;legacy_modified=$false}))
Add-Record 'MIR4_SOURCE_FREEZE_READINESS_FINAL.json' (New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4SourceFreezeReadinessFinalV1' -Status 'blocked-not-authorized' -Maturity blocked-with-evidence -AuthorityId 'mir4-release-governance-v1' -AuthorityMode read-only-composition -AuthoritySourcePaths @($governancePath) -EvidenceRefs (@($governanceRefs)+$gateRefs) -Payload ([ordered]@{source_freeze_ready=$false;source_freeze_performed=$false;candidate_m4rc1_allocated=$false;signing_performed=$false;sealing_performed=$false;tag_created=$false;publication_performed=$false;blockers=@('BLOCKED-HUMAN-SECRET-INPUT','BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER','BLOCKED-MISSING-TRUSTED-TIMING-CAPACITY-EVIDENCE')}))

$schemaPath = Join-Path $repo 'spec/schemas/mir4-full-platform-record-v1.schema.json'
$expectedBytes = [ordered]@{}
foreach ($entry in $records.GetEnumerator()) {
  $json = ConvertTo-MIR4BootstrapCanonicalJson -Value $entry.Value
  if (-not ($json | Test-Json -SchemaFile $schemaPath)) { throw "[mir4-full-platform-record-schema] $($entry.Key)" }
  if (-not (Test-MIR4BootstrapRecordHash -Record $entry.Value)) { throw "[mir4-full-platform-record-hash] $($entry.Key)" }
  $expectedBytes[$entry.Key] = [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
}
$checksumRows = @($expectedBytes.GetEnumerator() | Sort-Object Key | ForEach-Object {
  $sha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([byte[]]$_.Value))
  [ordered]@{path=[string]$_.Key;bytes=[int64]$_.Value.Length;sha256=$sha;schema='spec/schemas/mir4-full-platform-record-v1.schema.json'}
})
$checksumRecord = New-MIR4FullPlatformRecord -SourceIdentity $source -Kind 'MIR4FullPlatform24HChecksumsV1' -Status 'complete' -Maturity mixed -AuthorityId 'mir4-full-platform-closeout-v1' -AuthorityMode evidence-only-aggregation -AuthoritySourcePaths $finalAuthority -EvidenceRefs @((New-AuthorityRef 'spec/schemas/mir4-full-platform-record-v1.schema.json' 'final-record-schema')) -Payload ([ordered]@{files=$checksumRows;self_excluded_from_inventory=$true})
$checksumJson = ConvertTo-MIR4BootstrapCanonicalJson -Value $checksumRecord
if (-not ($checksumJson | Test-Json -SchemaFile $schemaPath) -or -not (Test-MIR4BootstrapRecordHash -Record $checksumRecord)) { throw '[mir4-full-platform-checksum-schema-or-hash]' }
$expectedBytes['SHA256SUMS.json'] = [Text.UTF8Encoding]::new($false).GetBytes($checksumJson + "`n")

if ($Check) {
  foreach ($entry in $expectedBytes.GetEnumerator()) {
    $path = Join-Path $output $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not [Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($path), [byte[]]$entry.Value)) { throw "[mir4-full-platform-record-stale] $($entry.Key)" }
  }
  $unexpected = @(Get-ChildItem -LiteralPath $output -File | Where-Object { $_.Name -notin @($expectedBytes.Keys) })
  if ($unexpected.Count) { throw "[mir4-full-platform-unexpected-record] $($unexpected.Name -join ',')" }
} else {
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  foreach ($entry in $expectedBytes.GetEnumerator()) { [IO.File]::WriteAllBytes((Join-Path $output $entry.Key), [byte[]]$entry.Value) }
}

[pscustomobject][ordered]@{status=$(if($auditAccepted){'PARTIAL-WITH-BOUNDED-BLOCKERS'}else{'PENDING-INDEPENDENT-LUNA-AUDIT'});source_identity=$source;output=$output;records=$expectedBytes.Count;open_blockers=@($blockers.id);luna_accepted=$auditAccepted;dev_merge_attempted=$false;source_freeze_performed=$false;publication_authorized=$false} | ConvertTo-Json -Depth 12
