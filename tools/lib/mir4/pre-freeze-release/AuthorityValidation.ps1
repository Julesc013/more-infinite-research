function Test-MIR4PreFreezeAuthorities {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  if (-not (Get-Command Get-MIR4BootstrapRecordSha256 -ErrorAction SilentlyContinue)) {
    . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
  }
  $schemas = [ordered]@{
    '.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json' = 'spec/schemas/mir4-post-readiness-merge-receipt-sol15-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json' = 'spec/schemas/mir4-pre-freeze-development-plan-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-F210-Release-Qualification-PolicyV1.json' = 'spec/schemas/mir4-f210-release-qualification-policy-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Release-Workflow-ContractV1.json' = 'spec/schemas/mir4-release-workflow-contract-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Release-Phase-Engine-ContractV1.json' = 'spec/schemas/mir4-release-phase-engine-contract-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T02-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t02-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T03-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t03-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T04-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t04-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T05-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t05-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Release-Fault-CorpusV1.json' = 'spec/schemas/mir4-release-fault-corpus-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T06-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t06-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T07-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t07-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T08-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t08-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T09-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t09-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T10-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t10-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T11-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t11-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T12-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t12-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Release-Compatibility-Canaries-T13V1.json' = 'spec/schemas/mir4-release-compatibility-canaries-t13-v1.schema.json'
    'sdk/preview/mir4/reference/t13/MIR4_T13_RECEIPT.json' = 'spec/schemas/preview/mir4-t13-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T13-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t13-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Documentation-Continuity-T14V1.json' = 'spec/schemas/mir4-documentation-continuity-t14-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T14-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t14-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Supply-Chain-Preservation-T15V1.json' = 'spec/schemas/mir4-supply-chain-preservation-t15-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T15-Independent-Machine-AcceptanceV1.json' = 'spec/schemas/mir4-t15-independent-machine-acceptance-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t15-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T17-Machine-Preparation-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t17-machine-preparation-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-F210-Qualification-Policy-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-f210-qualification-policy-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Tooling-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-final-mile-tooling-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Final-Release-Closure-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-final-release-closure-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Post-Release-Package-Baseline-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-post-release-package-baseline-authority-evolution-receipt-v1.schema.json'
    'releases/migrations/MIR4-Post-Release-Automation-Authority-CutoverV1.json' = 'contracts/repository/mir4-post-release-automation-authority-cutover-v1.schema.json'
    'releases/migrations/MIR4-Branch-Operating-Model-Authority-EvolutionV1.json' = 'contracts/repository/mir4-branch-operating-model-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-Patch-Lane-Rehearsal-Authority-EvolutionV1.json' = 'contracts/repository/mir4-patch-lane-rehearsal-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-03-Change-And-Release-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-03-change-and-release-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-05A-M42-00A-Repository-Characterization-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-05a-m42-00a-repository-characterization-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F0-Truth-Reconciliation-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f0-truth-reconciliation-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F1-Golden-Four-Target-Baseline-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f1-golden-four-target-baseline-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F2A-Shadow-Target-Materializer-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f2a-shadow-target-materializer-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F2B-Shadow-Source-Model-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f2b-shadow-source-model-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F2C-Editable-Source-Materializer-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f2c-editable-source-materializer-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F2D-Runtime-Replay-Harness-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f2d-runtime-replay-harness-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F2D-F210-Runtime-Replay-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f2d-f210-runtime-replay-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F2D-F200-Runtime-Replay-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f2d-target-runtime-replay-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F2E-Package-Authority-CutoverV1.json' = 'contracts/repository/mir4-m41-f2e-package-authority-cutover-v1.schema.json'
    'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json' = 'contracts/repository/mir4-m41-05b-documentation-cutover-v1.schema.json'
    'releases/migrations/MIR4-M42-01A-CLI-Release-ConvergenceV1.json' = 'contracts/repository/mir4-m42-01a-cli-release-convergence-v1.schema.json'
    'releases/migrations/MIR4-M42-01B-Test-Workflow-ConvergenceV1.json' = 'contracts/repository/mir4-m42-01b-test-workflow-convergence-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Compilation-Plan-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-compilation-plan-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Base-Continuations-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-base-continuations-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Stream-Compiler-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-stream-compiler-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Technology-Catalog-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-technology-catalog-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Effect-Ownership-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-effect-ownership-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Compiler-Orchestrator-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-compiler-orchestrator-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Pre-Freeze-Release-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-pre-freeze-release-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Bootstrap-Materialization-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-bootstrap-materialization-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Assurance-Release-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-assurance-release-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Compatibility-Audit-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-compatibility-audit-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Offline-Custody-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-offline-custody-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M41-Current-Product-Bridge-RetirementV1.json' = 'contracts/repository/mir4-m41-current-product-bridge-retirement-v1.schema.json'
    'releases/migrations/MIR4-M41-Source-Freeze-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-source-freeze-authority-evolution-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Maintainer-Final-GitHub-Release-AuthorizationV1.json' = 'spec/schemas/mir4-maintainer-final-github-release-authorization-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Playtest-Candidate-AuthorityV1.json' = 'spec/schemas/mir4-final-mile-playtest-candidate-authority-v1.schema.json'
    'releases/migrations/MIR4-Repository-Fixed-Point-Tooling-MigrationV1.json' = 'contracts/repository/mir4-repository-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Canonicalization-Tooling-MigrationV1.json' = 'contracts/repository/mir4-canonicalization-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Diagnostics-Tooling-MigrationV1.json' = 'contracts/repository/mir4-diagnostics-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Target-Key-Tooling-MigrationV1.json' = 'contracts/repository/mir4-target-key-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Whole-Platform-Tooling-MigrationV1.json' = 'contracts/repository/mir4-whole-platform-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Technology-Acceptance-Tooling-MigrationV1.json' = 'contracts/repository/mir4-technology-acceptance-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Target-Compiler-Tooling-MigrationV1.json' = 'contracts/repository/mir4-target-compiler-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Semantic-Compiler-Policy-Tooling-MigrationV1.json' = 'contracts/repository/mir4-semantic-compiler-policy-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Runtime-Continuity-Tooling-MigrationV1.json' = 'contracts/repository/mir4-runtime-continuity-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Module-Sdk-Mep-Tooling-MigrationV1.json' = 'contracts/repository/mir4-module-sdk-mep-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-ProcessIR-Exact-Tooling-MigrationV1.json' = 'contracts/repository/mir4-processir-exact-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Inspector-Compatibility-Tooling-MigrationV1.json' = 'contracts/repository/mir4-inspector-compatibility-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Assurance-Offline-Custody-Tooling-MigrationV1.json' = 'contracts/repository/mir4-assurance-offline-custody-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Historical-Tooling-MigrationV1.json' = 'contracts/repository/mir4-historical-tooling-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Release-Tooling-MigrationV1.json' = 'contracts/repository/mir4-release-tooling-migration-receipt-v1.schema.json'
  }
  $lowerTargetReceiptPaths = [ordered]@{
    f110 = 'releases/migrations/MIR4-M41-F2D-F110-Runtime-Replay-Authority-EvolutionV1.json'
    f100 = 'releases/migrations/MIR4-M41-F2D-F100-Runtime-Replay-Authority-EvolutionV1.json'
  }
  $lowerTargetReceiptPresence = @{}
  foreach ($target in $lowerTargetReceiptPaths.Keys) {
    $relativePath = [string]$lowerTargetReceiptPaths[$target]
    $present = Test-Path -LiteralPath (Join-Path $repo $relativePath) -PathType Leaf
    $lowerTargetReceiptPresence[$target] = $present
    if ($present) {
      $schemas[$relativePath] = 'contracts/repository/mir4-m41-f2d-target-runtime-replay-authority-evolution-v1.schema.json'
    }
  }
  if ($lowerTargetReceiptPresence.f100 -and -not $lowerTargetReceiptPresence.f110) {
    throw '[mir4-prefreeze-lower-target-receipt-order] f100 requires f110'
  }
  $aggregateReceiptPath = 'releases/migrations/MIR4-M41-F2D-Four-Target-Runtime-Replay-AggregateV1.json'
  $aggregateReceiptPresent = Test-Path -LiteralPath (Join-Path $repo $aggregateReceiptPath) -PathType Leaf
  if ($aggregateReceiptPresent) {
    if (-not $lowerTargetReceiptPresence.f100) { throw '[mir4-prefreeze-f2d-aggregate-requires-f100]' }
    $schemas[$aggregateReceiptPath] = 'contracts/repository/mir4-m41-f2d-four-target-runtime-replay-aggregate-v1.schema.json'
  }
  foreach ($entry in $schemas.GetEnumerator()) {
    $json = Get-Content -Raw -LiteralPath (Join-Path $repo $entry.Key)
    if (-not ($json | Test-Json -SchemaFile (Join-Path $repo $entry.Value))) { throw "[mir4-prefreeze-schema] $($entry.Key)" }
  }
  $receipt = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json' -Kind 'MIR4PostReadinessMergeReceiptSOL15V1'
  $authorityHashes = @{}
  $authorityHashModes = @{}
  foreach ($binding in @($receipt.authority_bindings)) {
    $authorityHashes[[string]$binding.path] = [string]$binding.sha256
    $authorityHashModes[[string]$binding.path] = $(if($binding.PSObject.Properties.Name-contains'hash_mode'){[string]$binding.hash_mode}else{'raw-bytes'})
  }
  $priorReceiptPath = '.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json'
  $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  $evolutionLinks = @(
    @{path='.mir/releases/waves/mir4-r0/MIR4-T02-Authority-Evolution-ReceiptV1.json';kind='MIR4T02AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T03-Authority-Evolution-ReceiptV1.json';kind='MIR4T03AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T04-Authority-Evolution-ReceiptV1.json';kind='MIR4T04AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T05-Authority-Evolution-ReceiptV1.json';kind='MIR4T05AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T06-Authority-Evolution-ReceiptV1.json';kind='MIR4T06AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T07-Authority-Evolution-ReceiptV1.json';kind='MIR4T07AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T08-Authority-Evolution-ReceiptV1.json';kind='MIR4T08AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T09-Authority-Evolution-ReceiptV1.json';kind='MIR4T09AuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-T10-Authority-Evolution-ReceiptV1.json';kind='MIR4T10AuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-T11-Authority-Evolution-ReceiptV1.json';kind='MIR4T11AuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-T12-Authority-Evolution-ReceiptV1.json';kind='MIR4T12AuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-T13-Authority-Evolution-ReceiptV1.json';kind='MIR4T13AuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-T14-Authority-Evolution-ReceiptV1.json';kind='MIR4T14AuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json';kind='MIR4T15AuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-T17-Machine-Preparation-Authority-Evolution-ReceiptV1.json';kind='MIR4T17MachinePreparationAuthorityEvolutionReceiptV1'}
    @{path='releases/migrations/MIR4-Repository-Fixed-Point-Tooling-MigrationV1.json';kind='MIR4RepositoryMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Canonicalization-Tooling-MigrationV1.json';kind='MIR4CanonicalizationMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Diagnostics-Tooling-MigrationV1.json';kind='MIR4DiagnosticsMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Target-Key-Tooling-MigrationV1.json';kind='MIR4TargetKeyMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Whole-Platform-Tooling-MigrationV1.json';kind='MIR4WholePlatformMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Technology-Acceptance-Tooling-MigrationV1.json';kind='MIR4TechnologyAcceptanceMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Target-Compiler-Tooling-MigrationV1.json';kind='MIR4TargetCompilerMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Semantic-Compiler-Policy-Tooling-MigrationV1.json';kind='MIR4SemanticCompilerPolicyMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Runtime-Continuity-Tooling-MigrationV1.json';kind='MIR4RuntimeContinuityMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Module-Sdk-Mep-Tooling-MigrationV1.json';kind='MIR4ModuleSdkMepMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-ProcessIR-Exact-Tooling-MigrationV1.json';kind='MIR4ProcessIRExactMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Inspector-Compatibility-Tooling-MigrationV1.json';kind='MIR4InspectorCompatibilityMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Assurance-Offline-Custody-Tooling-MigrationV1.json';kind='MIR4AssuranceOfflineCustodyMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Historical-Tooling-MigrationV1.json';kind='MIR4HistoricalToolingMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Release-Tooling-MigrationV1.json';kind='MIR4ReleaseToolingMigrationReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-F210-Qualification-Policy-Authority-Evolution-ReceiptV1.json';kind='MIR4F210QualificationPolicyAuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Tooling-Authority-Evolution-ReceiptV1.json';kind='MIR4FinalMileToolingAuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-Final-Release-Closure-Authority-Evolution-ReceiptV1.json';kind='MIR4FinalReleaseClosureAuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-Post-Release-Package-Baseline-Authority-Evolution-ReceiptV1.json';kind='MIR4PostReleasePackageBaselineAuthorityEvolutionReceiptV1'}
    @{path='releases/migrations/MIR4-Post-Release-Automation-Authority-CutoverV1.json';kind='MIR4PostReleaseAutomationAuthorityCutoverV1'}
    @{path='releases/migrations/MIR4-Branch-Operating-Model-Authority-EvolutionV1.json';kind='MIR4BranchOperatingModelAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-Patch-Lane-Rehearsal-Authority-EvolutionV1.json';kind='MIR4PatchLaneRehearsalAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-03-Change-And-Release-Authority-EvolutionV1.json';kind='MIR4M4103ChangeAndReleaseAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-05A-M42-00A-Repository-Characterization-Authority-EvolutionV1.json';kind='MIR4M4105AM4200ARepositoryCharacterizationAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F0-Truth-Reconciliation-Authority-EvolutionV1.json';kind='MIR4M41F0TruthReconciliationAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F1-Golden-Four-Target-Baseline-Authority-EvolutionV1.json';kind='MIR4M41F1GoldenFourTargetBaselineAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F2A-Shadow-Target-Materializer-Authority-EvolutionV1.json';kind='MIR4M41F2AShadowTargetMaterializerAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F2B-Shadow-Source-Model-Authority-EvolutionV1.json';kind='MIR4M41F2BShadowSourceModelAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F2C-Editable-Source-Materializer-Authority-EvolutionV1.json';kind='MIR4M41F2CEditableSourceMaterializerAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F2D-Runtime-Replay-Harness-Authority-EvolutionV1.json';kind='MIR4M41F2DRuntimeReplayHarnessAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F2D-F210-Runtime-Replay-Authority-EvolutionV1.json';kind='MIR4M41F2DF210RuntimeReplayAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F2D-F200-Runtime-Replay-Authority-EvolutionV1.json';kind='MIR4M41F2DTargetRuntimeReplayAuthorityEvolutionV1'}
  )
  foreach ($target in $lowerTargetReceiptPaths.Keys) {
    if ($lowerTargetReceiptPresence[$target]) {
      $evolutionLinks += @{
        path = [string]$lowerTargetReceiptPaths[$target]
        kind = 'MIR4M41F2DTargetRuntimeReplayAuthorityEvolutionV1'
      }
    }
  }
  if ($aggregateReceiptPresent) {
    $evolutionLinks += @{path=$aggregateReceiptPath;kind='MIR4M41F2DFourTargetRuntimeReplayAggregateV1'}
  }
  foreach ($link in $evolutionLinks) {
    $evolution = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $link.path -Kind $link.kind
    if ([string]$evolution.predecessor_receipt.path -cne $priorReceiptPath -or
        [string]$evolution.predecessor_receipt.sha256 -cne $priorReceiptSha256) {
      throw "[mir4-prefreeze-evolution-predecessor] $($link.path)"
    }
    $evolvedPaths = @{}
    foreach ($binding in @($evolution.evolved_bindings)) {
      $path = [string]$binding.path
      $allowedPackageVisibleSuccessor = [string]$evolution.kind -ceq 'MIR4PostReleasePackageBaselineAuthorityEvolutionReceiptV1' -and
        $path -ceq 'README.md' -and [bool]$binding.package_visible
      if (-not $authorityHashes.ContainsKey($path) -or [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          ([bool]$binding.package_visible -and -not $allowedPackageVisibleSuccessor) -or [bool]$binding.release_authority -or $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-evolution-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $evolvedPaths[$path] = $true
    }
    foreach ($binding in @($evolution.current_authorities)) {
      $path = [string]$binding.path
      if ($authorityHashes.ContainsKey($path) -and [string]$authorityHashes[$path] -cne [string]$binding.sha256 -and
          -not $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-current-authority-evolution-missing] $path"
      }
      $authorityHashes[$path] = [string]$binding.sha256
      $authorityHashModes[$path] = $(if($binding.PSObject.Properties.Name-contains'hash_mode'){[string]$binding.hash_mode}else{'raw-bytes'})
    }
    if ($evolution.PSObject.Properties.Name -contains 'retired_bindings') {
      if ([string]$evolution.kind -cne 'MIR4PostReleaseAutomationAuthorityCutoverV1') { throw "[mir4-prefreeze-retired-binding-kind] $($link.path)" }
      $retiredPaths = @{}
      foreach ($binding in @($evolution.retired_bindings)) {
        $path = [string]$binding.path
        if (-not $authorityHashes.ContainsKey($path) -or
            [string]$authorityHashes[$path] -cne [string]$binding.historical_sha256 -or
            $retiredPaths.ContainsKey($path)) {
          throw "[mir4-prefreeze-retired-binding] $path"
        }
        [void]$authorityHashes.Remove($path)
        [void]$authorityHashModes.Remove($path)
        $retiredPaths[$path] = $true
      }
    }
    foreach ($property in $evolution.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-evolution-transition] $($link.path):$($property.Name)" }
    }
    $priorReceiptPath = [string]$link.path
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $f2eReceiptPath = 'releases/migrations/MIR4-M41-F2E-Package-Authority-CutoverV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $f2eReceiptPath) -PathType Leaf) {
    $f2e = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $f2eReceiptPath -Kind 'MIR4M41F2EPackageAuthorityCutoverV1'
    if ([string]$f2e.predecessor_receipt.path -cne $priorReceiptPath -or
        [string]$f2e.predecessor_receipt.sha256 -cne $priorReceiptSha256) {
      throw '[mir4-prefreeze-f2e-predecessor]'
    }
    $supersededPaths = @{}
    foreach ($binding in @($f2e.superseded_pre_cutover_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path) -or
          [string]$authorityHashes[$path] -cne [string]$binding.historical_sha256 -or
          [string]$binding.hash_mode -cne [string]$authorityHashModes[$path] -or
          $supersededPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-f2e-superseded-binding] $path"
      }
      [void]$authorityHashes.Remove($path)
      [void]$authorityHashModes.Remove($path)
      $supersededPaths[$path] = $true
    }
    if (-not [bool]$f2e.transition_gate.package_cutover -or
        -not [bool]$f2e.transition_gate.old_writer_retirement -or
        @($f2e.transition_gate.PSObject.Properties | Where-Object {
          $_.Name -notin @('package_cutover','old_writer_retirement') -and [bool]$_.Value
        }).Count -ne 0) {
      throw '[mir4-prefreeze-f2e-transition-boundary]'
    }
    $priorReceiptPath = $f2eReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $documentationReceiptPath = 'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $documentationReceiptPath) -PathType Leaf) {
    $documentation = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $documentationReceiptPath -Kind 'MIR4M4105BDocumentationCutoverV1'
    if ([string]$documentation.predecessor_receipt.path -cne $priorReceiptPath -or
        [string]$documentation.predecessor_receipt.sha256 -cne $priorReceiptSha256) {
      throw '[mir4-prefreeze-m41-05b-predecessor]'
    }
    $evolvedPaths = @{}
    foreach ($binding in @($documentation.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path) -or
          [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m41-05b-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $evolvedPaths[$path] = $true
    }
    foreach ($binding in @($documentation.current_authorities)) {
      $path = [string]$binding.path
      if ($authorityHashes.ContainsKey($path) -and
          [string]$authorityHashes[$path] -cne [string]$binding.sha256 -and
          -not $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m41-05b-current-authority-evolution-missing] $path"
      }
      if ([bool]$binding.package_visible -or [bool]$binding.release_authority) {
        throw "[mir4-prefreeze-m41-05b-current-authority-boundary] $path"
      }
      $authorityHashes[$path] = [string]$binding.sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
    }
    foreach ($property in $documentation.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m41-05b-transition] $($property.Name)" }
    }
    $priorReceiptPath = $documentationReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $cliReleaseReceiptPath = 'releases/migrations/MIR4-M42-01A-CLI-Release-ConvergenceV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $cliReleaseReceiptPath) -PathType Leaf) {
    $cliRelease = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $cliReleaseReceiptPath -Kind 'MIR4M4201ACliReleaseConvergenceV1'
    if ([string]$cliRelease.predecessor_receipt.path -cne $priorReceiptPath -or
        [string]$cliRelease.predecessor_receipt.sha256 -cne $priorReceiptSha256) {
      throw '[mir4-prefreeze-m42-01a-predecessor]'
    }
    $evolvedPaths = @{}
    foreach ($binding in @($cliRelease.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path) -or
          [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-01a-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $evolvedPaths[$path] = $true
    }
    foreach ($binding in @($cliRelease.current_authorities)) {
      $path = [string]$binding.path
      if ($authorityHashes.ContainsKey($path) -and
          [string]$authorityHashes[$path] -cne [string]$binding.sha256 -and
          -not $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-01a-current-authority-evolution-missing] $path"
      }
      if ([bool]$binding.package_visible -or [bool]$binding.release_authority) {
        throw "[mir4-prefreeze-m42-01a-current-authority-boundary] $path"
      }
      $authorityHashes[$path] = [string]$binding.sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
    }
    if (-not [bool]$cliRelease.invariants.one_public_cli -or
        -not [bool]$cliRelease.invariants.one_command_route_per_key -or
        -not [bool]$cliRelease.invariants.one_release_application_dag -or
        -not [bool]$cliRelease.invariants.publisher_cannot_build) {
      throw '[mir4-prefreeze-m42-01a-invariants]'
    }
    foreach ($property in $cliRelease.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-01a-transition] $($property.Name)" }
    }
    $priorReceiptPath = $cliReleaseReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $testWorkflowReceiptPath = 'releases/migrations/MIR4-M42-01B-Test-Workflow-ConvergenceV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $testWorkflowReceiptPath) -PathType Leaf) {
    $testWorkflow = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $testWorkflowReceiptPath -Kind 'MIR4M4201BTestWorkflowConvergenceV1'
    if ([string]$testWorkflow.predecessor_receipt.path -cne $priorReceiptPath -or
        [string]$testWorkflow.predecessor_receipt.sha256 -cne $priorReceiptSha256) {
      throw '[mir4-prefreeze-m42-01b-predecessor]'
    }
    foreach ($binding in @($testWorkflow.evolved_bindings)) {
      $path = [string]$binding.path
      if (($authorityHashes.ContainsKey($path) -and [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256) -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority) {
        throw "[mir4-prefreeze-m42-01b-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
    }
    foreach ($binding in @($testWorkflow.projection_bindings)) {
      $path = [string]$binding.path
      if ($authorityHashes.ContainsKey($path) -and [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256) {
        throw "[mir4-prefreeze-m42-01b-projection-binding] $path"
      }
      if ([bool]$binding.package_visible -or [bool]$binding.release_authority) { throw "[mir4-prefreeze-m42-01b-projection-boundary] $path" }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
    }
    foreach ($binding in @($testWorkflow.relocated_bindings)) {
      $fromPath = [string]$binding.from_path
      $toPath = [string]$binding.to_path
      if ($fromPath -notmatch '^validation/tests/.+\.ps1$' -or $toPath -notmatch '^tests/.+\.ps1$' -or
          (Test-Path -LiteralPath (Join-Path $repo $fromPath)) -or
          -not (Test-Path -LiteralPath (Join-Path $repo $toPath) -PathType Leaf) -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority) {
        throw "[mir4-prefreeze-m42-01b-relocation] $fromPath"
      }
      if ($authorityHashes.ContainsKey($fromPath)) {
        [void]$authorityHashes.Remove($fromPath)
        [void]$authorityHashModes.Remove($fromPath)
      }
      $authorityHashes[$toPath] = [string]$binding.current_sha256
      $authorityHashModes[$toPath] = [string]$binding.hash_mode
    }
    foreach ($binding in @($testWorkflow.current_authorities)) {
      $path = [string]$binding.path
      if ($authorityHashes.ContainsKey($path) -and [string]$authorityHashes[$path] -cne [string]$binding.sha256) {
        throw "[mir4-prefreeze-m42-01b-current-authority-evolution-missing] $path"
      }
      if ([bool]$binding.package_visible -or [bool]$binding.release_authority) { throw "[mir4-prefreeze-m42-01b-current-authority-boundary] $path" }
      $authorityHashes[$path] = [string]$binding.sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
    }
    if (@($testWorkflow.invariants.PSObject.Properties | Where-Object { -not [bool]$_.Value }).Count -ne 0) { throw '[mir4-prefreeze-m42-01b-invariants]' }
    foreach ($property in $testWorkflow.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-01b-transition] $($property.Name)" }
    }
    $priorReceiptPath = $testWorkflowReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $compilationPlanReceiptPath = 'releases/migrations/MIR4-M42-02-Compilation-Plan-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $compilationPlanReceiptPath) -PathType Leaf) {
    $compilationPlan = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $compilationPlanReceiptPath -Kind 'MIR4M4202CompilationPlanDecompositionV1'
    if ([string]$compilationPlan.predecessor.receipt -cne $priorReceiptPath -or
        [string]$compilationPlan.predecessor.receipt_sha256 -cne $priorReceiptSha256) {
      throw '[mir4-prefreeze-m42-02-predecessor]'
    }
    $evolvedPaths = @{}
    foreach ($binding in @($compilationPlan.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path) -or
          [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $evolvedPaths[$path] = $true
    }
    if ($evolvedPaths.Count -ne 8 -or
        [string]$compilationPlan.responsibility -cne 'compilation-plan' -or
        [string]$compilationPlan.status -cne 'M42-02-L1-COMPILATION-PLAN-DECOMPOSED') {
      throw '[mir4-prefreeze-m42-02-scope]'
    }
    $currentPaths = @{}
    foreach ($binding in @($compilationPlan.current_authorities)) {
      $path = [string]$binding.path
      if ($authorityHashes.ContainsKey($path) -and
          [string]$authorityHashes[$path] -cne [string]$binding.sha256 -and
          -not $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-current-authority-evolution-missing] $path"
      }
      if ([bool]$binding.package_visible -or [bool]$binding.release_authority -or $currentPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-current-authority-boundary] $path"
      }
      $authorityHashes[$path] = [string]$binding.sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $currentPaths[$path] = $true
    }
    if ($currentPaths.Count -ne 2) { throw '[mir4-prefreeze-m42-02-current-authority-count]' }
    foreach ($property in $compilationPlan.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-transition] $($property.Name)" }
    }
    $priorReceiptPath = $compilationPlanReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $baseContinuationsReceiptPath = 'releases/migrations/MIR4-M42-02-Base-Continuations-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $baseContinuationsReceiptPath) -PathType Leaf) {
    $baseContinuations = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $baseContinuationsReceiptPath -Kind 'MIR4M4202BaseContinuationsDecompositionV1'
    if ([string]$baseContinuations.predecessor.receipt -cne $priorReceiptPath -or
        [string]$baseContinuations.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$baseContinuations.predecessor.record_sha256 -cne [string]$compilationPlan.record_sha256 -or
        [string]$baseContinuations.predecessor.package_source_sha256 -cne [string]$compilationPlan.package_authority.package_source_sha256) {
      throw '[mir4-prefreeze-m42-02-l2-predecessor]'
    }
    $baseContinuationEvolvedPaths = @{}
    foreach ($binding in @($baseContinuations.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path) -or
          [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $baseContinuationEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-l2-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $baseContinuationEvolvedPaths[$path] = $true
    }
    if ($baseContinuationEvolvedPaths.Count -ne 6 -or
        [string]$baseContinuations.responsibility -cne 'base-continuations' -or
        [string]$baseContinuations.status -cne 'M42-02-L2-BASE-CONTINUATIONS-DECOMPOSED') {
      throw '[mir4-prefreeze-m42-02-l2-scope]'
    }
    foreach ($property in $baseContinuations.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-l2-transition] $($property.Name)" }
    }
    $priorReceiptPath = $baseContinuationsReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $streamCompilerReceiptPath = 'releases/migrations/MIR4-M42-02-Stream-Compiler-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $streamCompilerReceiptPath) -PathType Leaf) {
    $streamCompiler = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $streamCompilerReceiptPath -Kind 'MIR4M4202StreamCompilerDecompositionV1'
    if ([string]$streamCompiler.predecessor.receipt -cne $priorReceiptPath -or
        [string]$streamCompiler.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$streamCompiler.predecessor.record_sha256 -cne [string]$baseContinuations.record_sha256 -or
        [string]$streamCompiler.predecessor.package_source_sha256 -cne [string]$baseContinuations.package_authority.package_source_sha256) {
      throw '[mir4-prefreeze-m42-02-l3-predecessor]'
    }
    $streamCompilerEvolvedPaths = @{}
    $streamCompilerEnrollmentBaselines = @{
      'spec/schemas/mir4-package-source-manifest-v1.schema.json' = 'A8B04D8ADE76EF2718F88EF7E0B47ABA4B3699377B8FB054C99C43BA1C4358E8'
      'tests/repository/Test-MIR4RepositoryFixedPoint.ps1' = 'B3A535D84A910E776F4F76F5D1DB3E97381EED817A439AF90C7D2AF16BF92254'
    }
    foreach ($binding in @($streamCompiler.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $streamCompilerEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$streamCompilerEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-l3-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if (-not $authorityHashes.ContainsKey($path) -or
          [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $streamCompilerEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-l3-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $streamCompilerEvolvedPaths[$path] = $true
    }
    if ($streamCompilerEvolvedPaths.Count -ne 12 -or
        [string]$streamCompiler.responsibility -cne 'stream-compiler' -or
        [string]$streamCompiler.status -cne 'M42-02-L3-STREAM-COMPILER-DECOMPOSED') {
      throw '[mir4-prefreeze-m42-02-l3-scope]'
    }
    foreach ($property in $streamCompiler.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-l3-transition] $($property.Name)" }
    }
    $priorReceiptPath = $streamCompilerReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $technologyCatalogReceiptPath = 'releases/migrations/MIR4-M42-02-Technology-Catalog-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $technologyCatalogReceiptPath) -PathType Leaf) {
    $technologyCatalog = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $technologyCatalogReceiptPath -Kind 'MIR4M4202TechnologyCatalogDecompositionV1'
    if ([string]$technologyCatalog.predecessor.receipt -cne $priorReceiptPath -or
        [string]$technologyCatalog.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$technologyCatalog.predecessor.record_sha256 -cne [string]$streamCompiler.record_sha256 -or
        [string]$technologyCatalog.predecessor.package_source_sha256 -cne [string]$streamCompiler.package_authority.package_source_sha256) {
      throw '[mir4-prefreeze-m42-02-l4-predecessor]'
    }
    $technologyCatalogEvolvedPaths = @{}
    $technologyCatalogEnrollmentBaselines = @{
      'tests/compiler/Test-MIR4CompilationPlanDecompositionM4202.ps1' = 'A5326EA3FBE5941AD0FE86934306EC7267F8ABC25079235DBFE8349C845A03B5'
      'tests/compiler/Test-MIR4BaseContinuationsDecompositionM4202.ps1' = 'C933AF6E213C5ABCF482FFF2CFC6375A053A7ADACA8847F98CF4E8AD50E870EF'
      'tests/compiler/Test-MIR4StreamCompilerDecompositionM4202.ps1' = '1D74336F21F11F6CBD1A11660615621993E75A9F1E98B421C271335502B5071D'
    }
    foreach ($binding in @($technologyCatalog.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $technologyCatalogEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$technologyCatalogEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-l4-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $technologyCatalogEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-l4-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $technologyCatalogEvolvedPaths[$path] = $true
    }
    if ($technologyCatalogEvolvedPaths.Count -ne 14 -or
        [string]$technologyCatalog.responsibility -cne 'technology-catalog' -or
        [string]$technologyCatalog.status -cne 'M42-02-L4-TECHNOLOGY-CATALOG-DECOMPOSED') {
      throw '[mir4-prefreeze-m42-02-l4-scope]'
    }
    foreach ($property in $technologyCatalog.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-l4-transition] $($property.Name)" }
    }
    $priorReceiptPath = $technologyCatalogReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $effectOwnershipReceiptPath = 'releases/migrations/MIR4-M42-02-Effect-Ownership-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $effectOwnershipReceiptPath) -PathType Leaf) {
    $effectOwnership = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $effectOwnershipReceiptPath -Kind 'MIR4M4202EffectOwnershipDecompositionV1'
    if ([string]$effectOwnership.predecessor.receipt -cne $priorReceiptPath -or
        [string]$effectOwnership.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$effectOwnership.predecessor.record_sha256 -cne [string]$technologyCatalog.record_sha256 -or
        [string]$effectOwnership.predecessor.package_source_sha256 -cne [string]$technologyCatalog.package_authority.package_source_sha256) {
      throw '[mir4-prefreeze-m42-02-l5-predecessor]'
    }
    $effectOwnershipEvolvedPaths = @{}
    $effectOwnershipEnrollmentBaselines = @{
      'tests/compiler/Test-MIR4TechnologyCatalogDecompositionM4202.ps1' = '5177840DC386C2075D96F7A86EC679874E091001273C1F3211B81A1334428902'
    }
    foreach ($binding in @($effectOwnership.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $effectOwnershipEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$effectOwnershipEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-l5-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $effectOwnershipEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-l5-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $effectOwnershipEvolvedPaths[$path] = $true
    }
    if ($effectOwnershipEvolvedPaths.Count -ne 15 -or
        [string]$effectOwnership.responsibility -cne 'effect-ownership' -or
        [string]$effectOwnership.status -cne 'M42-02-L5-EFFECT-OWNERSHIP-DECOMPOSED') {
      throw '[mir4-prefreeze-m42-02-l5-scope]'
    }
    foreach ($property in $effectOwnership.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-l5-transition] $($property.Name)" }
    }
    $priorReceiptPath = $effectOwnershipReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $compilerOrchestratorReceiptPath = 'releases/migrations/MIR4-M42-02-Compiler-Orchestrator-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $compilerOrchestratorReceiptPath) -PathType Leaf) {
    $compilerOrchestrator = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $compilerOrchestratorReceiptPath -Kind 'MIR4M4202CompilerOrchestratorDecompositionV1'
    if ([string]$compilerOrchestrator.predecessor.receipt -cne $priorReceiptPath -or
        [string]$compilerOrchestrator.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$compilerOrchestrator.predecessor.record_sha256 -cne [string]$effectOwnership.record_sha256 -or
        [string]$compilerOrchestrator.predecessor.package_source_sha256 -cne [string]$effectOwnership.package_authority.package_source_sha256) {
      throw '[mir4-prefreeze-m42-02-l6-predecessor]'
    }
    $compilerOrchestratorEvolvedPaths = @{}
    $compilerOrchestratorEnrollmentBaselines = @{
      'tests/compiler/Test-MIR4EffectOwnershipDecompositionM4202.ps1' = 'E761F5D6F931A3F9FECCEB34DAA979D5630CA1804659F46C210A7371CEFE7808'
    }
    foreach ($binding in @($compilerOrchestrator.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $compilerOrchestratorEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$compilerOrchestratorEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-l6-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $compilerOrchestratorEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-l6-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $compilerOrchestratorEvolvedPaths[$path] = $true
    }
    if ($compilerOrchestratorEvolvedPaths.Count -ne 16 -or
        [string]$compilerOrchestrator.responsibility -cne 'compiler-orchestrator' -or
        [string]$compilerOrchestrator.status -cne 'M42-02-L6-COMPILER-ORCHESTRATOR-DECOMPOSED') {
      throw '[mir4-prefreeze-m42-02-l6-scope]'
    }
    foreach ($property in $compilerOrchestrator.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-l6-transition] $($property.Name)" }
    }
    $m4202PackageSourceSha256 = [string]$compilerOrchestrator.package_authority.package_source_sha256
    $priorReceiptPath = $compilerOrchestratorReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $powerShellCharacterizationReceiptPath = 'releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $powerShellCharacterizationReceiptPath) -PathType Leaf) {
    $powerShellCharacterization = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $powerShellCharacterizationReceiptPath -Kind 'MIR4M4202PowerShellCharacterizationV1'
    if ([string]$powerShellCharacterization.predecessor.receipt -cne $priorReceiptPath -or
        [string]$powerShellCharacterization.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$powerShellCharacterization.predecessor.record_sha256 -cne [string]$compilerOrchestrator.record_sha256) {
      throw '[mir4-prefreeze-m42-02-powershell-characterization-predecessor]'
    }
    $powerShellCharacterizationPaths = @{}
    foreach ($binding in @($powerShellCharacterization.authority_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path) -or
          [string]$binding.hash_mode -cne 'canonical-text-v1' -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or
          $powerShellCharacterizationPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-powershell-characterization-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.sha256
      $powerShellCharacterizationPaths[$path] = $true
    }
    if ($powerShellCharacterizationPaths.Count -ne 12 -or
        [string]$powerShellCharacterization.status -cne 'M42-02-RESIDUAL-POWERSHELL-CHARACTERIZED' -or
        [string]$powerShellCharacterization.next_fixed_point -cne 'M42-02-PS1-COMMAND-ROUTER') {
      throw '[mir4-prefreeze-m42-02-powershell-characterization-scope]'
    }
    foreach ($property in $powerShellCharacterization.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-powershell-characterization-transition] $($property.Name)" }
    }
    $priorReceiptPath = $powerShellCharacterizationReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $commandRouterReceiptPath = 'releases/migrations/MIR4-M42-02-PowerShell-Command-Router-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $commandRouterReceiptPath) -PathType Leaf) {
    if (-not (Get-Command Get-MIR4CanonicalPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
      . (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
    }
    $commandRouter = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $commandRouterReceiptPath -Kind 'MIR4M4202PowerShellCommandRouterDecompositionV1'
    if ([string]$commandRouter.predecessor.receipt -cne $priorReceiptPath -or
        [string]$commandRouter.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$commandRouter.predecessor.record_sha256 -cne [string]$powerShellCharacterization.record_sha256) {
      throw '[mir4-prefreeze-m42-02-command-router-predecessor]'
    }
    $commandRouterEnrollmentBaselines = @{
      'contracts/repository/mir4-command-inventory-v1.schema.json'='790EE7D6CA662D8A4E7A51DEEEBC6BF9A14754D4FF828204DFE8DACA034BF099'
      'docs/architecture/module-boundaries.md'='24D5CB06F955FC6189D5CA02B4B0769547F16069D20692B4D7F909AB07824F6F'
      'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1'='5BE01F0320FDC1074CD7524B951CE5D56C624AF4BAE07C77362B9444483CD2AD'
      'tests/tooling/Test-MIRAssurance.ps1'='7E6C860FB364052EF0ED8852D8DF2AAB9131DFBEB6A23CB45E43BB3A86403603'
      'tests/tooling/Test-MIR4CliReleaseConvergence.ps1'='FECB62355A5E37EA3CA33F9D52F3B36F99BD01011FA7E7C0E341156479BB101A'
      'tools/mir/application/repository/RepositoryFixedPoint.ps1'='E33A3D0761FE92D03CC32000A033FF5C3C70FE7802982E796FBB2933B84F42C9'
      'tools/mir/application/tooling/CommandInventory.ps1'='B29A081BC21EC057B22D3A1E61946D3BA7BBC5DCFA5D14B973E9A94D895DD01E'
      'tools/mir/cli/Invoke-MIRCommandRouter.ps1'='AA50E7DF8CD41C756B3270A47A23E13F4F8B911F9ED89B05813D4B99376E7E25'
    }
    $commandRouterEvolvedPaths = @{}
    foreach ($binding in @($commandRouter.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $commandRouterEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$commandRouterEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-command-router-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $commandRouterEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-command-router-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $commandRouterEvolvedPaths[$path] = $true
    }
    if ($commandRouterEvolvedPaths.Count -ne 17 -or
        [string]$commandRouter.status -cne 'M42-02-PS1-COMMAND-ROUTER-DECOMPOSED' -or
        [string]$commandRouter.decomposition.responsibility -cne 'command-router' -or
        [string]$commandRouter.next_fixed_point -cne 'M42-02-PS2-VALIDATION-RUNNER' -or
        @($commandRouter.decomposition.modules).Count -ne 12 -or
        -not [bool]$commandRouter.public_contract.unchanged -or
        [int]$commandRouter.public_contract.command_count -ne 85 -or
        [string]$commandRouter.preservation.package_source_sha256 -cne $m4202PackageSourceSha256) {
      throw '[mir4-prefreeze-m42-02-command-router-scope]'
    }
    foreach ($property in $commandRouter.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-command-router-transition] $($property.Name)" }
    }
    $priorReceiptPath = $commandRouterReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $validationRunnerReceiptPath = 'releases/migrations/MIR4-M42-02-Validation-Runner-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $validationRunnerReceiptPath) -PathType Leaf) {
    $validationRunner = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $validationRunnerReceiptPath -Kind 'MIR4M4202ValidationRunnerDecompositionV1'
    if ([string]$validationRunner.predecessor.receipt -cne $priorReceiptPath -or
        [string]$validationRunner.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$validationRunner.predecessor.record_sha256 -cne [string]$commandRouter.record_sha256) {
      throw '[mir4-prefreeze-m42-02-validation-runner-predecessor]'
    }
    $validationRunnerEnrollmentBaselines = @{
      '.mir/assurance.json'='3AA87C735CE38E72E329B57CE18128E12F2EDC766AAB9C8B1E99D653D993F86A'
      '.mir/control/paths.yml'='A1BEA739D39299E51074974F247E7365D042F6521B7AF671777D61905E47BB79'
      '.mir/modules.yml'='A283CC23AA08E3C0143F5F2DC2EBDFB0ECC84DDAF83596C18F01E7EA257EE7EE'
      '.mir/test-impact.yml'='86F2CE6C8B7D2C3DDC814E28334AD38AEB9B74E95CB3BEDDAAB454E7C134EEC2'
      'assurance/catalog/tests.json'='5EE78F1AB37240161CF56FC24A3E0237F823C7AD0BD5C26082D2F51A10AE1E40'
      'docs/architecture/module-boundaries.md'='62F4004A4F5BB77416F05041AD5584FED137EB128F1F7656A9DAADF297682E49'
      'governance/automation/mir4-command-inventory-v1.json'='E5463D974FC0B64C2EA9F9C49AD05A749DE4C892822F049861DC5EEE37CB5F35'
      'scripts/Invoke-MIRValidation.ps1'='29961C5D5EFA6B241C2F4A4DDF3AC485867ACC7C6D17E312F30704DD04A2BEBB'
      'tests/architecture/Test-MIRArchitecture.ps1'='0E6A5E35DB8BF08843C46BFD18ECA5FD84FF289C1FCC68BF78483D466E504FF5'
      'tests/repository/Test-MIR4RepositoryFixedPoint.ps1'='302723E073CDD5E8360B6DF64B4E6C514F958ABD54E22A010A364609B74A4325'
      'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'='B53C546FA9199A46262513705E33BB0A8ED303432BB124EF6870E3704FAF7DFC'
      'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1'='5DE299D8848FF5DA115161AEF756D326A4A908841649E031C557684DC0C5EE5C'
      'tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1'='CD37C8F5A32AEFF9CC63CC700AFDB93C68D7139131C0237B9039B787FCABA943'
      'tests/tooling/Test-MIRAssurance.ps1'='9D6D27B80DC9E6A8A40810868D8BC9195CCF4A2F919CA836790A1B4DA24707B5'
      'tools/lib/mir4/PreFreezeRelease.ps1'='DE1535857373D38F4DA508C8559CA7378470CDF325FEF09A86A33CC6D11D9D7E'
      'tools/mir/application/repository/RepositoryFixedPoint.ps1'='4E7EF5247D81FA5AC477FFF950B85D522FCFF18E0929B309E7E5E5F68ACE3B9A'
      'validation/tests.yml'='B89B0CD861D87B12B3DA565EE26457E8B40AE150842FA8B8EFB490BBB9BF7B5A'
    }
    $validationRunnerEvolvedPaths = @{}
    foreach ($binding in @($validationRunner.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $validationRunnerEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$validationRunnerEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-validation-runner-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $validationRunnerEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-validation-runner-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $validationRunnerEvolvedPaths[$path] = $true
    }
    if ($validationRunnerEvolvedPaths.Count -ne 17 -or
        [string]$validationRunner.status -cne 'M42-02-PS2-VALIDATION-RUNNER-DECOMPOSED' -or
        [string]$validationRunner.decomposition.responsibility -cne 'validation-runner' -or
        [string]$validationRunner.next_fixed_point -cne 'M42-02-PS3-ASSURANCE-EVIDENCE' -or
        @($validationRunner.decomposition.modules).Count -ne 21 -or
        -not [bool]$validationRunner.public_contract.unchanged -or
        -not [bool]$validationRunner.semantic_contract.source_segments_exact -or
        [string]$validationRunner.preservation.package_source_sha256 -cne $m4202PackageSourceSha256) {
      throw '[mir4-prefreeze-m42-02-validation-runner-scope]'
    }
    foreach ($property in $validationRunner.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-validation-runner-transition] $($property.Name)" }
    }
    $priorReceiptPath = $validationRunnerReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $assuranceEvidenceReceiptPath = 'releases/migrations/MIR4-M42-02-Assurance-Evidence-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $assuranceEvidenceReceiptPath) -PathType Leaf) {
    $assuranceEvidence = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $assuranceEvidenceReceiptPath -Kind 'MIR4M4202AssuranceEvidenceDecompositionV1'
    if ([string]$assuranceEvidence.predecessor.receipt -cne $priorReceiptPath -or
        [string]$assuranceEvidence.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$assuranceEvidence.predecessor.record_sha256 -cne [string]$validationRunner.record_sha256) {
      throw '[mir4-prefreeze-m42-02-assurance-evidence-predecessor]'
    }
    $assuranceEvidenceEnrollmentBaselines = @{
      '.mir/assurance.json'='EAFF5A9CEB72E143F3054115E971E9FCB04D8EF1EF9B912B7DB8C2C8AD8F9DDC'
      '.mir/control/paths.yml'='17B027743B5F8114D3E339DD5502ADD421FB50C4F4340D832EB3F0078039C390'
      '.mir/modules.yml'='20A679746AEF6D9B1995FAD720DC31E493F3163EF5D0067EBCE5819C235B5B09'
      '.mir/test-impact.yml'='C76E65B8B612F21C6C7F08D265787F1AE31E09E97DF4D9F2ACD811A3CA5B4399'
      'assurance/catalog/tests.json'='FC1FFDDAD38370043049BBC6BA838163A9B568CD1446148D6D8385F72B6B1EF8'
      'docs/architecture/module-boundaries.md'='DE0C8EF7A7D7E99C3C416893740F69CF3580607432303820B826A95D33D0F915'
      'governance/automation/mir4-command-inventory-v1.json'='C4B5BCC28CEBF3695C7EB682CF9650FF269C2B5C77B80A6807BBC61FA1131FBC'
      'tests/architecture/Test-MIRArchitecture.ps1'='84E7CF5D35BB7CE2DB2820606EE1213486D7032CDCFE963DC80FA1BE5A505E07'
      'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'='BF9A86C8C72CF1F7F9A43CDE0B60E768835FF01218C96873071D2037C4392EB4'
      'tests/repository/Test-MIR4RepositoryFixedPoint.ps1'='F81313D89D0FF8097652BDFC1EA0DBDC6CEA87FBF4A50501382739E84B49B4B9'
      'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1'='43B525DFE427559BCF7D0F34D819C4475A18348DB289B3063E9D883732620E8E'
      'tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1'='2157159773AB3CD45391FE38FC4836492014952275B3CCBD0ACCF7BA58FBC4DC'
      'tests/tooling/Test-MIR4ValidationRunnerDecompositionM4202.ps1'='D29666D2CA1291017EC06652707C5EC185D3AD974767DBE8B1F47C2B2AA92451'
      'tests/tooling/Test-MIRAssurance.ps1'='9D6D27B80DC9E6A8A40810868D8BC9195CCF4A2F919CA836790A1B4DA24707B5'
      'tests/tooling/Test-MIRVerificationSchemas.ps1'='B01D23C94046A084959DEB7307F9B20C0623F910A36CEBBFCDEB46D3BD53EA65'
      'tools/lib/mir4/PreFreezeRelease.ps1'='96FFA2284711537E22D4C7CCFB636A8DE285D6F646DEA37F154BDAF9A113AED9'
      'tools/mir/application/repository/RepositoryFixedPoint.ps1'='4E7EF5247D81FA5AC477FFF950B85D522FCFF18E0929B309E7E5E5F68ACE3B9A'
      'validation/tests.yml'='165C08D736F83D9B4E05CB7FDAC4CF1A3D8F0E5FC4C36C230B0B4339B6750498'
    }
    $assuranceEvidenceEvolvedPaths = @{}
    foreach ($binding in @($assuranceEvidence.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $assuranceEvidenceEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$assuranceEvidenceEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-assurance-evidence-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $assuranceEvidenceEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-assurance-evidence-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $assuranceEvidenceEvolvedPaths[$path] = $true
    }
    if ($assuranceEvidenceEvolvedPaths.Count -ne 18 -or
        [string]$assuranceEvidence.status -cne 'M42-02-PS3-ASSURANCE-EVIDENCE-DECOMPOSED' -or
        [string]$assuranceEvidence.decomposition.responsibility -cne 'assurance-evidence' -or
        [string]$assuranceEvidence.next_fixed_point -cne 'M42-02-PS4-PRE-FREEZE-RELEASE' -or
        @($assuranceEvidence.decomposition.modules).Count -ne 9 -or
        -not [bool]$assuranceEvidence.public_contract.unchanged -or
        [int]$assuranceEvidence.public_contract.function_count -ne 62 -or
        -not [bool]$assuranceEvidence.semantic_contract.source_segments_exact -or
        [string]$assuranceEvidence.preservation.package_source_sha256 -cne $m4202PackageSourceSha256) {
      throw '[mir4-prefreeze-m42-02-assurance-evidence-scope]'
    }
    foreach ($property in $assuranceEvidence.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-assurance-evidence-transition] $($property.Name)" }
    }
    $priorReceiptPath = $assuranceEvidenceReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $preFreezeReleaseReceiptPath = 'releases/migrations/MIR4-M42-02-Pre-Freeze-Release-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $preFreezeReleaseReceiptPath) -PathType Leaf) {
    $preFreezeRelease = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $preFreezeReleaseReceiptPath -Kind 'MIR4M4202PreFreezeReleaseDecompositionV1'
    if ([string]$preFreezeRelease.predecessor.receipt -cne $priorReceiptPath -or
        [string]$preFreezeRelease.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$preFreezeRelease.predecessor.record_sha256 -cne [string]$assuranceEvidence.record_sha256) {
      throw '[mir4-prefreeze-m42-02-pre-freeze-release-predecessor]'
    }
    $preFreezeReleaseEnrollmentBaselines = @{
      'tests/tooling/Test-MIR4AssuranceEvidenceDecompositionM4202.ps1'='FBBB2E0CFB321E0B24A6CA8EA8670487725FBD55D0BC0D1892F8AC01263690F9'
    }
    $preFreezeReleaseEvolvedPaths = @{}
    foreach ($binding in @($preFreezeRelease.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $preFreezeReleaseEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$preFreezeReleaseEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-pre-freeze-release-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $preFreezeReleaseEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-pre-freeze-release-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $preFreezeReleaseEvolvedPaths[$path] = $true
    }
    if ($preFreezeReleaseEvolvedPaths.Count -ne 20 -or
        [string]$preFreezeRelease.status -cne 'M42-02-PS4-PRE-FREEZE-RELEASE-DECOMPOSED' -or
        [string]$preFreezeRelease.decomposition.responsibility -cne 'pre-freeze-release' -or
        [string]$preFreezeRelease.next_fixed_point -cne 'M42-02-PS5-BOOTSTRAP-MATERIALIZATION' -or
        @($preFreezeRelease.decomposition.modules).Count -ne 6 -or
        -not [bool]$preFreezeRelease.public_contract.unchanged -or
        [int]$preFreezeRelease.public_contract.function_count -ne 25 -or
        -not [bool]$preFreezeRelease.semantic_contract.source_segments_exact_except_declared_self_successor -or
        -not [bool]$preFreezeRelease.semantic_contract.declared_self_successor_extension -or
        [string]$preFreezeRelease.preservation.package_source_sha256 -cne $m4202PackageSourceSha256) {
      throw '[mir4-prefreeze-m42-02-pre-freeze-release-scope]'
    }
    foreach ($property in $preFreezeRelease.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-pre-freeze-release-transition] $($property.Name)" }
    }
    $priorReceiptPath = $preFreezeReleaseReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }  $bootstrapMaterializationReceiptPath = 'releases/migrations/MIR4-M42-02-Bootstrap-Materialization-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $bootstrapMaterializationReceiptPath) -PathType Leaf) {
    $bootstrapMaterialization = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $bootstrapMaterializationReceiptPath -Kind 'MIR4M4202BootstrapMaterializationDecompositionV1'
    if ([string]$bootstrapMaterialization.predecessor.receipt -cne $priorReceiptPath -or
        [string]$bootstrapMaterialization.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$bootstrapMaterialization.predecessor.record_sha256 -cne [string]$preFreezeRelease.record_sha256) {
      throw '[mir4-prefreeze-m42-02-bootstrap-materialization-predecessor]'
    }
    $bootstrapMaterializationEnrollmentBaselines = @{
      'tests/tooling/Test-MIR4PreFreezeReleaseDecompositionM4202.ps1'='B382CC2260F41B89207C690642DE41A405D51F00C9B5E439B3A8F41BADC996EB'
      'tools/lib/mir4/BootstrapMaterialization.ps1'='3B496E1D8DA0A772E4B1856761EBB3C40921742D0161D59811E360256901FB30'
      'tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1'='B3816A485BC68DB696598D2BAB637DE2EAD46DAE48ACA34DFAE6BAB904AA85C3'
    }
    $bootstrapMaterializationEvolvedPaths = @{}
    foreach ($binding in @($bootstrapMaterialization.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $bootstrapMaterializationEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$bootstrapMaterializationEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-bootstrap-materialization-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $bootstrapMaterializationEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-bootstrap-materialization-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $bootstrapMaterializationEvolvedPaths[$path] = $true
    }
    if ($bootstrapMaterializationEvolvedPaths.Count -ne 21 -or
        [string]$bootstrapMaterialization.status -cne 'M42-02-PS5-BOOTSTRAP-MATERIALIZATION-DECOMPOSED' -or
        [string]$bootstrapMaterialization.decomposition.responsibility -cne 'bootstrap-materialization' -or
        [string]$bootstrapMaterialization.next_fixed_point -cne 'M42-02-PS6-ASSURANCE-RELEASE' -or
        @($bootstrapMaterialization.decomposition.modules).Count -ne 6 -or
        -not [bool]$bootstrapMaterialization.public_contract.unchanged -or
        [int]$bootstrapMaterialization.public_contract.function_count -ne 51 -or
        -not [bool]$bootstrapMaterialization.semantic_contract.source_segments_exact -or
        [string]$bootstrapMaterialization.preservation.package_source_sha256 -cne $m4202PackageSourceSha256) {
      throw '[mir4-prefreeze-m42-02-bootstrap-materialization-scope]'
    }
    foreach ($property in $bootstrapMaterialization.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-bootstrap-materialization-transition] $($property.Name)" }
    }
    $priorReceiptPath = $bootstrapMaterializationReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $assuranceReleaseReceiptPath = 'releases/migrations/MIR4-M42-02-Assurance-Release-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $assuranceReleaseReceiptPath) -PathType Leaf) {
    $assuranceRelease = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $assuranceReleaseReceiptPath -Kind 'MIR4M4202AssuranceReleaseDecompositionV1'
    if ([string]$assuranceRelease.predecessor.receipt -cne $priorReceiptPath -or
        [string]$assuranceRelease.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$assuranceRelease.predecessor.record_sha256 -cne [string]$bootstrapMaterialization.record_sha256) {
      throw '[mir4-prefreeze-m42-02-assurance-release-predecessor]'
    }
    $assuranceReleaseEnrollmentBaselines = @{
      'scripts/Invoke-MIRAssurance.ps1'='FAB4B763803218D33E584958BA92403FB3631B6BB3B1A893BEC5DC3F59D52600'
      'tests/tooling/Test-MIR4BootstrapMaterializationDecompositionM4202.ps1'='DE64AAA6E87D27C00B0AE01A71B2297805E10753F6101DE5AF8499A3A22807F7'
      'tools/lib/assurance/Release.ps1'='B9B0F07F385A59C000E3F5D627481A28DA6BE9522F34B08BAADCF1B1B48E9AB9'
    }
    $assuranceReleaseEvolvedPaths = @{}
    foreach ($binding in @($assuranceRelease.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $assuranceReleaseEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$assuranceReleaseEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-assurance-release-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $assuranceReleaseEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-assurance-release-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $assuranceReleaseEvolvedPaths[$path] = $true
    }
    if ($assuranceReleaseEvolvedPaths.Count -ne 23 -or
        [string]$assuranceRelease.status -cne 'M42-02-PS6-ASSURANCE-RELEASE-DECOMPOSED' -or
        [string]$assuranceRelease.decomposition.responsibility -cne 'assurance-release' -or
        [string]$assuranceRelease.next_fixed_point -cne 'M42-02-PS7-COMPATIBILITY-AUDIT' -or
        @($assuranceRelease.decomposition.modules).Count -ne 4 -or
        [string]$assuranceRelease.decomposition.self_test.authority -cne 'canonical-executable-test-support' -or
        -not [bool]$assuranceRelease.public_contract.unchanged -or
        -not [bool]$assuranceRelease.semantic_contract.embedded_self_test_removed_from_release_authority -or
        [string]$assuranceRelease.preservation.package_source_sha256 -cne $m4202PackageSourceSha256) {
      throw '[mir4-prefreeze-m42-02-assurance-release-scope]'
    }
    foreach ($property in $assuranceRelease.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-assurance-release-transition] $($property.Name)" }
    }
    $priorReceiptPath = $assuranceReleaseReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $compatibilityAuditReceiptPath = 'releases/migrations/MIR4-M42-02-Compatibility-Audit-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $compatibilityAuditReceiptPath) -PathType Leaf) {
    $compatibilityAudit = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $compatibilityAuditReceiptPath -Kind 'MIR4M4202CompatibilityAuditDecompositionV1'
    if ([string]$compatibilityAudit.predecessor.receipt -cne $priorReceiptPath -or
        [string]$compatibilityAudit.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$compatibilityAudit.predecessor.record_sha256 -cne [string]$assuranceRelease.record_sha256) {
      throw '[mir4-prefreeze-m42-02-compatibility-audit-predecessor]'
    }
    $compatibilityAuditEnrollmentBaselines = @{
      '.mir/assurance.json'='FFA6C939C2CF591512E54CFB41CA6A38838DDF2B1A4DEFDDC6E9FE5D2D33CAC1'
      '.mir/control/paths.yml'='427E544638FE65F65F2FDB3B167F0626A841572BA9CB5AE3D27EFDC77EE6C8CD'
      '.mir/modules.yml'='B41DB3EDD41D3B5F2174E3BF60BBF802AB16E92F30EDE2F3B670D74F81A4FBF1'
      '.mir/test-impact.yml'='ADB4D4567E5F2193BBEFA6D84A2E6106D77C47BB6A5E11B190DCA0D98B87A834'
      'assurance/catalog/tests.json'='D91884182E68AAD4C96209B746DFF8433563B59CA9C703A28E0A253C7A00BC3B'
      'docs/architecture/module-boundaries.md'='AC8ED63B44A1BFEA3309ACC67184CBD73E77BDFB5F4A3200EAA087AF992B47DB'
      'governance/automation/mir4-command-inventory-v1.json'='2FAF910B6A14771560E681A13563BE9CA232F19CB3217D259CDAE9B0355FDB55'
      'tests/architecture/Test-MIRArchitecture.ps1'='1256814BF49DF197E283FBAEE418E4B72056FFE20C53A8EA44B705CE3E1AFC95'
      'tests/compatibility/Test-MIRScenarioManifests.ps1'='AF917005C6C4CA4AB4A3B42BF5F1C7729860D381239C12BB18DB26EB44254444'
      'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'='1F6C581BDED30F3C78FCE5F72FF9FF512C0C044662E83B9DB649D9745124C5CF'
      'tests/release/Test-MIRPerformanceBudgets.ps1'='F80A084A5709B2210467F302A40C1CEE8CE61D2E9443C4A87DB16D38E12480C4'
      'tests/release/Test-MIRSanitationBudgets.ps1'='2E7851964290F2C6BA725D15FA56EEAA18A14CD2C221FBD218BDD263AAC4313B'
      'tests/repository/Test-MIR4RepositoryFixedPoint.ps1'='46BB7E373F0D4D553B459C34B83A524626AE7E6E913E38A2A1CC3DB75485CDA3'
      'tests/tooling/Test-MIRControlPlaneExecutor.ps1'='501506F3FBA2C217626EF2C6E016F88F6F121061EE1828146CF18CBF30F60D2D'
      'tests/tooling/Test-MIRVerificationSchemas.ps1'='A3B9C57E29ACE6EC402059F31CAF0C255147FC9DD3B95D7861FA0E38DE5E50BB'
      'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1'='4A985AB9AA38C43612310D149D36C93BC1E0079580AD5559662B4148A7AFF12D'
      'tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1'='84BAA21F2DC5C1C9E054BD8A83C0621F9487204A726AAA175CAA049F939C8FF1'
      'tests/tooling/Test-MIR4ValidationRunnerDecompositionM4202.ps1'='AB360BF6F9371A0E9542E0FDCD7878AFEF406E9F7986DA0DD782FF6B768E87A5'
      'tests/tooling/Test-MIR4AssuranceEvidenceDecompositionM4202.ps1'='7E332E69C58185DDB4BA0E482452616E6F32BF57373E99D17D84B1FFB0FD6335'
      'tests/tooling/Test-MIR4PreFreezeReleaseDecompositionM4202.ps1'='618844C65187D827D9FA5AC8A89927619D9BC73750AF3E9B30220070EFF0C017'
      'tests/tooling/Test-MIR4BootstrapMaterializationDecompositionM4202.ps1'='C601A98894C258624FA96D135B2570AE6931F91AA40B588E0EB6E8156DE8D2FF'
      'tests/tooling/Test-MIR4AssuranceReleaseDecompositionM4202.ps1'='71A7870E50BCB41BCC3E04327F48A2F41AA9E9FA550BDA0FB956E60D2F9C1D79'
      'tools/commands/compatibility/Invoke-MIRCompatAudit.ps1'='A6776583D9C3D03D001D3E38AFFE66BEC61E307B16077D1F8D63C47E02CEC664'
      'tools/lib/control/Executor.ps1'='0DE88F7E2E2BB1FE90E3823D52880C5E54CC772BEEFB783BCD2FD87595600A3E'
      'tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1'='C3F5A139EB4E5247D7ADF4D9A5A07155A0718EA5F9D687CB10B959789C9FD4F3'
      'tools/lib/validation/runner/StaticCompatibilityTooling.ps1'='F0F7F15DA01F124AF6C58F95EBD877D5509C0AED067C09E85AB3EB57D4CE0D28'
      'tools/lib/validation/runner/StaticCompilerDiagnostics.ps1'='416348AF7D2F49AEB9D5325F41384AA2BB80B22D5C62AD9CFD773DAB7C5B28B1'
      'tools/mir/application/repository/RepositoryFixedPoint.ps1'='4E7EF5247D81FA5AC477FFF950B85D522FCFF18E0929B309E7E5E5F68ACE3B9A'
      'validation/tests.yml'='DEBEC2826D9B9E99577743F69CCB19195D2CB593696637EDB562D79225D86DE4'
    }
    $compatibilityAuditEvolvedPaths = @{}
    foreach ($binding in @($compatibilityAudit.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $compatibilityAuditEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$compatibilityAuditEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-compatibility-audit-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $compatibilityAuditEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-compatibility-audit-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $compatibilityAuditEvolvedPaths[$path] = $true
    }
    if ($compatibilityAuditEvolvedPaths.Count -ne 29 -or
        [string]$compatibilityAudit.status -cne 'M42-02-PS7-COMPATIBILITY-AUDIT-DECOMPOSED' -or
        [string]$compatibilityAudit.decomposition.responsibility -cne 'compatibility-audit' -or
        [string]$compatibilityAudit.next_fixed_point -cne 'M42-02-PS8-OFFLINE-CUSTODY' -or
        @($compatibilityAudit.decomposition.modules).Count -ne 6 -or
        [int]$compatibilityAudit.public_contract.function_count -ne 35 -or
        -not [bool]$compatibilityAudit.public_contract.unchanged -or
        -not [bool]$compatibilityAudit.semantic_contract.compatibility_claims_unchanged -or
        -not [bool]$compatibilityAudit.semantic_contract.stream_authority_unchanged -or
        [string]$compatibilityAudit.preservation.package_source_sha256 -cne $m4202PackageSourceSha256) {
      throw '[mir4-prefreeze-m42-02-compatibility-audit-scope]'
    }
    foreach ($property in $compatibilityAudit.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-compatibility-audit-transition] $($property.Name)" }
    }
    $priorReceiptPath = $compatibilityAuditReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }

  $offlineCustodyReceiptPath = 'releases/migrations/MIR4-M42-02-Offline-Custody-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $offlineCustodyReceiptPath) -PathType Leaf) {
    $offlineCustody = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $offlineCustodyReceiptPath -Kind 'MIR4M4202OfflineCustodyDecompositionV1'
    if ([string]$offlineCustody.predecessor.receipt -cne $priorReceiptPath -or
        [string]$offlineCustody.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$offlineCustody.predecessor.record_sha256 -cne [string]$compatibilityAudit.record_sha256) {
      throw '[mir4-prefreeze-m42-02-offline-custody-predecessor]'
    }
    $offlineCustodyEnrollmentBaselines = @{
      '.mir/assurance.json'='0B749CDAEB870923403411F07B389FE6913A38ADDB063B9D3AA299C0AB10A36D'
      '.mir/control/paths.yml'='BE26A4A7EC49C6D1D77746FB150082396975A12DFEBDB63EDBC8535301A4CF12'
      '.mir/modules.yml'='A3A41A9D503E9AAE14239B614B77E8CA868C9E88D8B309A60C7C73FFC1C9AF5B'
      '.mir/test-impact.yml'='D962D8EC56F71214CECB501824BFE505A053EDDFFEBE91C042142B3CEB56BFD3'
      'assurance/catalog/tests.json'='2139F94C9C72AB47ABD90BFAC58893FBA49FE04483472EDDFA8A7BE8D617B473'
      'docs/architecture/module-boundaries.md'='D00D962D9BEA93392A301082D9609D76453F0EF47A4748C98C0084B7CF6FE2D2'
      'governance/automation/mir4-command-inventory-v1.json'='5728591A48C9FB7E8E5CD7DDA3F038EAD89747465BA6FA223ED0250B10DEA135'
      'tests/architecture/Test-MIRArchitecture.ps1'='348D59F62EC68D2D6B9ECAF561BD2DB1C662C591207ED73E121A88EFF2E40BFA'
      'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'='8D577E9B5016BE52466F36E0731EF2F2ABFD0C124538DE4752F19228047C917E'
      'tests/repository/Test-MIR4RepositoryFixedPoint.ps1'='50C4B51A9A727D4B27C3DBD24A3D36FA16773A8D7828D5DB0E13411E83821ABA'
      'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1'='92D7BE9F26256A60B2536D634C78CE2667C152FAF58A915DE6F6254F17BD9A36'
      'tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1'='D511D9B980973E68E3ACB7410547DAE1D25AC18E0F4AA7CC3592DE27C7B6AF99'
      'tests/tooling/Test-MIR4ValidationRunnerDecompositionM4202.ps1'='876AC1D2671A74D7D2F8EA5BD57879F3C789A0D2A45F527CF0A164FD04C6AE68'
      'tests/tooling/Test-MIR4AssuranceEvidenceDecompositionM4202.ps1'='0247BD182DEC78FC8CA3A1C5D372332169D76C23F2FA352CAFC76BB1125530A1'
      'tests/tooling/Test-MIR4PreFreezeReleaseDecompositionM4202.ps1'='270D14278253118BE76E2AAB91E57A83D03CD7D09719D3F7B26AD97D4F35674F'
      'tests/tooling/Test-MIR4BootstrapMaterializationDecompositionM4202.ps1'='8F6495AA860277E49796478464F9001DD77FE32BBE06766E191981BA2AA2E70D'
      'tests/tooling/Test-MIR4AssuranceReleaseDecompositionM4202.ps1'='A54CFE0A1356C07493F4A603666B944A7AF75A358D86B03028B495C84196F0CD'
      'tests/tooling/Test-MIR4CompatibilityAuditDecompositionM4202.ps1'='B10BAA98151FCDB16ED4CABDEF0459C76F68E2D506A3F26587C414261FDCD07E'
      'tools/mir/application/custody/OfflineCandidateCustody.ps1'='4AA7219BC19A02895F7076DF92E923D64F7C4D440DC4CBC0E937FA8C1CFB5A15'
      'tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1'='DF91B0F2C0AD0B3DB7F01ADE3468F400583B36C6B646CE41395C16579DCA16E8'
      'validation/tests.yml'='001F2A85C4883EEBA22CCF0C9112D613DB2DDE123B4C8475AC7BA77835F3E7B1'
    }
    $offlineCustodyEvolvedPaths = @{}
    foreach ($binding in @($offlineCustody.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $offlineCustodyEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$offlineCustodyEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-offline-custody-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $offlineCustodyEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-offline-custody-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $offlineCustodyEvolvedPaths[$path] = $true
    }
    if ($offlineCustodyEvolvedPaths.Count -ne 21 -or
        [string]$offlineCustody.status -cne 'M42-02-PS8-OFFLINE-CUSTODY-DECOMPOSED' -or
        [string]$offlineCustody.decomposition.responsibility -cne 'offline-custody' -or
        [string]$offlineCustody.next_fixed_point -cne 'M42-02-PS9-RELEASE-CAPSULE' -or
        @($offlineCustody.decomposition.modules).Count -ne 8 -or
        [int]$offlineCustody.public_contract.function_count -ne 26 -or
        -not [bool]$offlineCustody.public_contract.unchanged -or
        -not [bool]$offlineCustody.semantic_contract.ordered_source_slices_preserved_with_declared_substitutions -or
        -not [bool]$offlineCustody.semantic_contract.custody_admission_unchanged -or
        -not [bool]$offlineCustody.semantic_contract.historical_compatibility_check_explicit -or
        -not [bool]$offlineCustody.semantic_contract.seal_inputs_unchanged -or
        -not [bool]$offlineCustody.semantic_contract.signature_verification_unchanged -or
        -not [bool]$offlineCustody.semantic_contract.qualification_evidence_unchanged -or
        -not [bool]$offlineCustody.semantic_contract.publication_dry_run_unchanged -or
        -not [bool]$offlineCustody.semantic_contract.offline_seal_unchanged -or
        -not [bool]$offlineCustody.semantic_contract.offline_restore_unchanged -or
        -not [bool]$offlineCustody.semantic_contract.emergency_completion_unchanged -or
        [string]$offlineCustody.preservation.package_source_sha256 -cne $m4202PackageSourceSha256) {
      throw '[mir4-prefreeze-m42-02-offline-custody-scope]'
    }
    foreach ($property in $offlineCustody.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-offline-custody-transition] $($property.Name)" }
    }
    $priorReceiptPath = $offlineCustodyReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }

  $releaseCapsuleReceiptPath = 'releases/migrations/MIR4-M42-02-Release-Capsule-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $releaseCapsuleReceiptPath) -PathType Leaf) {
    $releaseCapsule = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $releaseCapsuleReceiptPath -Kind 'MIR4M4202ReleaseCapsuleDecompositionV1'
    if ([string]$releaseCapsule.predecessor.receipt -cne $priorReceiptPath -or
        [string]$releaseCapsule.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$releaseCapsule.predecessor.record_sha256 -cne [string]$offlineCustody.record_sha256) {
      throw '[mir4-prefreeze-m42-02-release-capsule-predecessor]'
    }
    $releaseCapsuleEnrollmentBaselines = @{
      '.mir/assurance.json'='1CFEC2D544570DA8B014BA9BF551374841E43444123A9EB679F18EED0F5D8E83'
      '.mir/control/paths.yml'='421DE7110CB44D8A2A0127F8F198F3E75BE619091BEEAEF4E0445D4C2FEBD035'
      '.mir/modules.yml'='1EBA10825236568CDEB9ACE1B7C767FA090B71DF362CBF7F17653D3FFDE5FCE2'
      '.mir/test-impact.yml'='9C574D442AB9154939F751B2D0C765C56E4304A0FCDF8C41592FA631D29E03ED'
      'assurance/catalog/tests.json'='7682E36C159AC0417DD89AAA5AB744B2C6B3B907D24BA7C47EFA31FF3C0A5661'
      'docs/architecture/module-boundaries.md'='4EFAA272FB40CCC3E1E0AF6B558DD3F5498FE3BCF1C1B412DFB4EF622B66DC38'
      'fixtures/mir4-mep-discovery-v1/negative/invalid-envelope.json'='4086019A6D7D3B49B372A53CD379D16388F04ACD34C104AF38A9C278F2924731'
      'fixtures/mir4-mep-discovery-v1/positive/host-absent.json'='D572197BE574778AE4F022B6B43A92D99F6139BDC1014F88286125AC9156F635'
      'fixtures/mir4-mep-discovery-v1/positive/order-a.json'='F285B5BB86941B93CB0E4323C8F0A526898779A1BF45CB55FFEFC9C3667F30AE'
      'fixtures/mir4-mep-discovery-v1/positive/order-b.json'='93AD01247A8E25DDF4FBB2C4718E09C151D64B5463D07E3101B34E2852690072'
      'fixtures/mir4-mep-v1/negative/cycle-a.json'='37F7A46FB88D3BB66AF81E2CB3B1F9A8779541DA8CD0B98C004F4C2A54361772'
      'fixtures/mir4-mep-v1/negative/cycle-b.json'='8F7FAE575D2D3F0F87C53A5E90CB4D06EE2C0D8E3B0E785D053F5AE1BE4D02D3'
      'fixtures/mir4-mep-v1/negative/forbidden-callback.json'='47630C59D5D38A56FE78D209009617A4514D43ADA00C190BA27049DC05D304FE'
      'fixtures/mir4-mep-v1/negative/missing-dependency.json'='ACB9A706046F2B5C40AD6CDEDBD70FE4E4CA2EC181E02C8DD2B52DE5FD5C958D'
      'fixtures/mir4-mep-v1/positive/reference-extension.json'='43CE13A4C6103FDDCFD834098AD5051D7083EA701A104A203B42392FD47A01FD'
      'governance/automation/mir4-command-inventory-v1.json'='D8334F5166C4300BD9CED2AAA6DCACDD68B23A3BA299E1B59C82B587F1408A41'
      'mir.lock'='267782F1F3FBD4C792E9C45850B334953CB02951637E5FE214831EE87F4AFE3A'
      'sdk/preview/mir4/mep-v1/templates/all-fragments/extension.json'='43CE13A4C6103FDDCFD834098AD5051D7083EA701A104A203B42392FD47A01FD'
      'sdk/preview/mir4/reference-extension-v1/extension.json'='43CE13A4C6103FDDCFD834098AD5051D7083EA701A104A203B42392FD47A01FD'
      'sdk/preview/mir4/reference/compatibility-factory-plan-v1.json'='956B0C6A50103E3B51AC6E97AC0A96BF028CE2CCFEDAC3A4799C24F5666F9625'
      'sdk/preview/mir4/reference/compatibility-subject-ledger-v1.json'='192FEEB48A5E296E0C43625D4D8B576422AA382E8C91DC9B4194A2315C632B86'
      'sdk/preview/mir4/reference/compilation-runs.json'='D5E4AD6468B97E79A603CC3326D7B9D07E94AA411C22805609A43FD804A0AE10'
      'sdk/preview/mir4/reference/continuity-bundle-template.json'='5BC2B8398F4DC754B3DC59AECF2060687A7379257678E1B6C4681C25BD53A450'
      'sdk/preview/mir4/reference/extension-closure-v1.json'='722A328F6E02DB5463F0EF8D379E45EB15CBB7244505D86978D2EF0A470BFCA0'
      'sdk/preview/mir4/reference/f210-mep-discovery-v1.json'='A9DDFC2BC23A7123E3B2608E745F75C01FF444FB244E941CF822152D0E83F23E'
      'sdk/preview/mir4/reference/inspection-bundle-v1.json'='1C24278BA48A7B7170B6F2A4348EAA3A4EF8028F8B84693DE5BA9B8FBAF7EED8'
      'sdk/preview/mir4/reference/inspector-workbench-result-v1.json'='2C4188D2D843D9D96F0CB5A0074B761A8E88442D59689AB340A51134938EADE2'
      'sdk/preview/mir4/reference/merge-law-catalogue.json'='7DD6C44528EDCDC60F8531141AFC3C1E18B5CBBD8FF022C9BCC8FC8E9B851628'
      'sdk/preview/mir4/reference/migration-graph-matrix.json'='6D06895B1E27E380D8998DA844B3CEAA198AB3C64F9321D387BA12BFB5B40E8A'
      'sdk/preview/mir4/reference/query-snapshot-f210.json'='36FDDB8CFC0327CCC80DB25A8492775E857FF90022F6B2D26875A6A24C09F503'
      'sdk/preview/mir4/reference/shadow-extension-run-v1-f210.json'='163AAB741E58B110C66C253D4FBA4DEC6B2F858A17CF76828DACA8933DA6F9F9'
      'sdk/preview/mir4/reference/support-bundle-v1.json'='E7EF52B0D1E110DAB15D1E0F0BEB66A0CFAAFB30685ADFBF87C559C755C15D31'
      'tests/architecture/Test-MIRArchitecture.ps1'='C622984802E0E91448181EE7CD88E789F0FC66978BF372686BA7912EDA1489D9'
      'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'='A46D0613629A48C168DE8A007B7F54458D3D15F02BFDE55C41468E14EC198DA3'
      'tests/mir4/Test-MIR4ReleaseCapsule.ps1'='EFFF8A24C4772B8B1D64EAFEACC693CE6AFB0BE8BB513AAF4B4157417746BCC3'
      'tests/repository/Test-MIR4RepositoryFixedPoint.ps1'='D86ACF1BA7E064F3A238B1AFE6D3E668248E37AA82DECAF67EF8FE6B1BF9AE5B'
      'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1'='1F26D831680A85505CC0AA7703D009BF812BBA4E06D68CD318FEC4D5BB88BC1E'
      'tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1'='40D3799CECD8067849101B6001B103AFD161FAF44DC3FB953BAEB72875D292A5'
      'tests/tooling/Test-MIR4ValidationRunnerDecompositionM4202.ps1'='98D679A58447D0C39E1FA818C9A5AD3CC9C25F88053C41F3A2EEC68558A9C616'
      'tests/tooling/Test-MIR4AssuranceEvidenceDecompositionM4202.ps1'='B70AFCE7D7DD75D507F7040E217FFF986135E622DB42E1EAB0F9B06D4E520CD2'
      'tests/tooling/Test-MIR4PreFreezeReleaseDecompositionM4202.ps1'='901A4AD6DA490A05EEA7E9B32AD53F1F27A09216606210F3DE9D3AE736FF1706'
      'tests/tooling/Test-MIR4BootstrapMaterializationDecompositionM4202.ps1'='922F735624BAE610B8375CDE0BA77715E8FDF298FBA48FE7CE32F47AF5381B33'
      'tests/tooling/Test-MIR4AssuranceReleaseDecompositionM4202.ps1'='0026BFFB18547A4CF2D62C7E7DF691E8FE6A09E0127156CB5C86CDE749EDACAB'
      'tests/tooling/Test-MIR4CompatibilityAuditDecompositionM4202.ps1'='5C549D64EB1460AEC86D8A15C0FC66F9AB8A3965E9A5C03FBCF7C74699740FCC'
      'tests/tooling/Test-MIR4OfflineCustodyDecompositionM4202.ps1'='B77F35E1FE0FBE861B27115562F6E6DF4C1B8EC6C9F682CCD3C43B28AD5A2159'
      'tools/lib/mir4/ReleaseCapsule.ps1'='6F35762B10F47084B71759E2A36B9163FF1B83CB336B325D67A48D426CCDB51D'
      'tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1'='50BF2AE38E48B7A6F8829A38016BCCEE1D63975947033B87636D4AEDA8B2B707'
      'validation/tests.yml'='EB048D1907D1693299257004C08AFB4F97F16D3DAA49B313A3A0EC7441075431'
    }
    $releaseCapsuleEvolvedPaths = @{}
    foreach ($binding in @($releaseCapsule.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $releaseCapsuleEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$releaseCapsuleEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-release-capsule-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $releaseCapsuleEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-release-capsule-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $releaseCapsuleEvolvedPaths[$path] = $true
    }
    if ($releaseCapsuleEvolvedPaths.Count -ne 48 -or
        [string]$releaseCapsule.status -cne 'M42-02-PS9-RELEASE-CAPSULE-DECOMPOSED' -or
        [string]$releaseCapsule.decomposition.responsibility -cne 'release-capsule' -or
        [string]$releaseCapsule.next_fixed_point -cne 'M42-02-PS10-CONTROL-EXECUTOR' -or
        @($releaseCapsule.decomposition.modules).Count -ne 8 -or
        [int]$releaseCapsule.public_contract.function_count -ne 19 -or
        -not [bool]$releaseCapsule.public_contract.unchanged -or
        -not [bool]$releaseCapsule.semantic_contract.ordered_source_slices_preserved -or
        -not [bool]$releaseCapsule.semantic_contract.custody_inventory_unchanged -or
        -not [bool]$releaseCapsule.semantic_contract.source_archive_unchanged -or
        -not [bool]$releaseCapsule.semantic_contract.capsule_construction_unchanged -or
        -not [bool]$releaseCapsule.semantic_contract.capsule_verification_unchanged -or
        -not [bool]$releaseCapsule.semantic_contract.offline_restore_unchanged -or
        -not [bool]$releaseCapsule.semantic_contract.platform_projections_regenerated -or
        -not [bool]$releaseCapsule.semantic_contract.post_cutover_package_non_interference_assertion -or
        [string]$releaseCapsule.preservation.package_source_sha256 -cne $m4202PackageSourceSha256) {
      throw '[mir4-prefreeze-m42-02-release-capsule-scope]'
    }
    foreach ($property in $releaseCapsule.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-release-capsule-transition] $($property.Name)" }
    }
    $priorReceiptPath = $releaseCapsuleReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }

  $controlExecutorReceiptPath = 'releases/migrations/MIR4-M42-02-Control-Executor-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $controlExecutorReceiptPath) -PathType Leaf) {
    $controlExecutor = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $controlExecutorReceiptPath -Kind 'MIR4M4202ControlExecutorDecompositionV1'
    if ([string]$controlExecutor.predecessor.receipt -cne $priorReceiptPath -or
        [string]$controlExecutor.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$controlExecutor.predecessor.record_sha256 -cne [string]$releaseCapsule.record_sha256) {
      throw '[mir4-prefreeze-m42-02-control-executor-predecessor]'
    }
    $controlExecutorEnrollmentBaselines = @{
      '.mir/assurance.json'='553F22FF847BEDE417BC06B633D4F3668C66F6EAFD61CB2DD52B010B2E311D54'
      '.mir/control/paths.yml'='14834D0DE9ECF66A19A09B1BF44DBDC0BE823A18D5CD3A402690BF519E16E09F'
      '.mir/modules.yml'='496E1464A7A894D2F1595F85DDB03506E140E3786847DF2A1CB549B6316F82EA'
      '.mir/test-impact.yml'='715053A085F3CBADB91195FC5149F5A9D375EF5003599E0903AA333700169272'
      'assurance/catalog/tests.json'='41EBA8CAE25B9A48A96F392BAED519EA05F4FD32083DFC86E44507732FAF77A4'
      'docs/architecture/module-boundaries.md'='C4A1FAAC20FB532F94AC10BFA4BC200F4A203C887ED0A7B73D20235249D3A639'
      'fixtures/mir4-mep-discovery-v1/negative/invalid-envelope.json'='487BF819B10D8CB3B4EA2E1A273E15ED1B2F87CC59407BF7688F13CC49F8DF92'
      'fixtures/mir4-mep-discovery-v1/positive/host-absent.json'='7A9127D687E450D226C92CA03F725902493D32F24634356AEDE3EAD163EE7E8E'
      'fixtures/mir4-mep-discovery-v1/positive/order-a.json'='BBBBD855F0618D797352F3F14A66964BFDA02B057D7E9830577ED281FCD8C08A'
      'fixtures/mir4-mep-discovery-v1/positive/order-b.json'='69EE5AC03B3D21C35D8A1EDA6919365F8D75260A9B8EF8FB644556A86DE5F160'
      'fixtures/mir4-mep-v1/negative/cycle-a.json'='DE051B6A777E316A7F30CA4FC17A3C2054C44455A3C17C15C29736400F55A2F6'
      'fixtures/mir4-mep-v1/negative/cycle-b.json'='F59B79AA680B214C12358070FE7A52723FDE9D7EA8B915E5A0FA1B0A12331531'
      'fixtures/mir4-mep-v1/negative/forbidden-callback.json'='FA0165D6EFB121A2407173E5E78A5E3A750A6B90DD2FE8E1D5A6076CC7F21253'
      'fixtures/mir4-mep-v1/negative/missing-dependency.json'='694B7CCF39D4EEDBF24CAF1960281C3C1605CC872BBDFD775B495EBC6206518B'
      'fixtures/mir4-mep-v1/positive/reference-extension.json'='0A96672A6E9C365E1B6A9FEE1E307636AFEB74AAFC88C8E7B89CD1D9436AE08D'
      'governance/automation/mir4-command-inventory-v1.json'='E4A7CD40233C782F611EB9781539F2896E418CF0EBB2494ECB2766727ED023C8'
      'mir.lock'='E4803065EDD8A1FA465ADEB4B9BD723B76DDC87E616C9CAE90FF2CB9636FEE00'
      'sdk/preview/mir4/mep-v1/templates/all-fragments/extension.json'='0A96672A6E9C365E1B6A9FEE1E307636AFEB74AAFC88C8E7B89CD1D9436AE08D'
      'sdk/preview/mir4/reference-extension-v1/extension.json'='0A96672A6E9C365E1B6A9FEE1E307636AFEB74AAFC88C8E7B89CD1D9436AE08D'
      'sdk/preview/mir4/reference/compatibility-factory-plan-v1.json'='BEED8DE3FC2DE9F0ADC5FD442DD2F0EA63B2B53812365A61C715491CA485386E'
      'sdk/preview/mir4/reference/compatibility-subject-ledger-v1.json'='1EBEACD3E05A89F11824B0842A9F0FEC723C65F6D418D8FD387523952C0E0845'
      'sdk/preview/mir4/reference/compilation-runs.json'='36296CBA4551DED4E5CDBF29D99BD4301874CF6C301C8F8E5000EFD897A45CF7'
      'sdk/preview/mir4/reference/continuity-bundle-template.json'='E1602E14FC2844505CF06527B2B58B488F6DA16F99E8DAB7AB5C868DDF36F42E'
      'sdk/preview/mir4/reference/extension-closure-v1.json'='8C2217DAFFDF17AED798D2595BA45D011299BCB410E3E9CF742C1E9B6CE01E84'
      'sdk/preview/mir4/reference/f210-mep-discovery-v1.json'='7B01ECF495F8D1CF5E5F27B460D4011EBB2831CE08CA9EE74F64B9D26C6BBBCE'
      'sdk/preview/mir4/reference/inspection-bundle-v1.json'='8D40D16709E25D47D83493C4D3BC8B8D5CB63B79BE12680CDDDE0C04BE8F700D'
      'sdk/preview/mir4/reference/inspector-workbench-result-v1.json'='8AE814401627EB25B5583CED3854559DFD9EC8A89A938A65BE669C96DF2B8C33'
      'sdk/preview/mir4/reference/merge-law-catalogue.json'='B91A737603C05AAB0B80F0881CFD23E4737B69BE1D883553896A9B636FC54A24'
      'sdk/preview/mir4/reference/migration-graph-matrix.json'='14D5CBD11E27D1BBB6CEAF5FFE24E4C3337AFCBCBCBB87F89DF3673A08387037'
      'sdk/preview/mir4/reference/query-snapshot-f210.json'='CFDC03A5F80C7F04B6131ACB060030A59C0D63942B22DCDC6838CD15985CA57F'
      'sdk/preview/mir4/reference/shadow-extension-run-v1-f210.json'='004B471EEDFC5AF91DE2A24A90483BA9467E2ADD4A81CD393168086EBDB6100E'
      'sdk/preview/mir4/reference/support-bundle-v1.json'='164F10F035FD5E2866D89D0DE272B7F514377E64FE357F0DB4F896BDCF0A5B49'
      'tests/architecture/Test-MIRArchitecture.ps1'='8DBA2D29DCE7B93206E83ECC88E7916989C1C6CCFC257B3B3605BC2DBAC7308B'
      'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'='E64E9BE9F47E89231E8238FC10AACE00F06E0C0FEE08E6118D7D3E43E9D369F2'
      'tests/repository/Test-MIR4RepositoryFixedPoint.ps1'='AE636247B4108F5314F0426F00C192E5FA074D318C843CE03DD3F37B29B19511'
      'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1'='DF9F57E353512CA16B5D39FF1D74AD2224CB2286134FE38B8208F1FB43F4F614'
      'tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1'='D7DCD4781F9CF6C6C533E6B980B552F5735C1DCA8C74A999B6A0D1D23CD6922A'
      'tests/tooling/Test-MIR4ValidationRunnerDecompositionM4202.ps1'='2F57EA68ED12D690C6BB1204E4518A94D4F9F2A751DF4622AEA1D6F2A47F8BAC'
      'tests/tooling/Test-MIR4AssuranceEvidenceDecompositionM4202.ps1'='B598B433AB3ED32A2F4479C7A27F984318DA9FA3789E864031D0C6D57D38EB53'
      'tests/tooling/Test-MIR4PreFreezeReleaseDecompositionM4202.ps1'='5C0220D190C96FA7BCFFF451A7F511627A9808EE488B2A865BEEBDF2B6C97C38'
      'tests/tooling/Test-MIR4BootstrapMaterializationDecompositionM4202.ps1'='B5159AA4C74B43FF28A189B8B48C9A4D8B35537F5AEEE0A782077885B00CB990'
      'tests/tooling/Test-MIR4AssuranceReleaseDecompositionM4202.ps1'='E825ED9BB68A74FB1614489AF83B45D2123F78ABD87121AC77C5E90CA01697A5'
      'tests/tooling/Test-MIR4CompatibilityAuditDecompositionM4202.ps1'='6ABCA4326A74760E8E63303F20AFF4298D198FE43CD53E6B09F9F29F62F0475E'
      'tests/tooling/Test-MIR4OfflineCustodyDecompositionM4202.ps1'='3553C812748A19608FE020628974872D874E5F708377B19E3B237595356154C8'
      'tests/tooling/Test-MIR4ReleaseCapsuleDecompositionM4202.ps1'='5A6492F78C03ABD18BF2BFB3952FF7BCE9272E088C281914FE8838D07BE11682'
      'tools/lib/control/Executor.ps1'='97EACF68C080CF9D38102A5BF26E96A42C015020F78DBA049461422E5673AF66'
      'tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1'='916092C4A10D4312C2943E6B715CE5122D2024723904F09ECD810B11C6C5ADF9'
      'validation/tests.yml'='898975509609396F25849763A9BA156B3358F66D51BD2A39D98246C96DAADF50'
    }
    $controlExecutorEvolvedPaths = @{}
    foreach ($binding in @($controlExecutor.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $controlExecutorEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$controlExecutorEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-control-executor-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if (
          [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $controlExecutorEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-control-executor-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $controlExecutorEvolvedPaths[$path] = $true
    }
    if ($controlExecutorEvolvedPaths.Count -ne 48 -or
        [string]$controlExecutor.status -cne 'M42-02-PS10-CONTROL-EXECUTOR-DECOMPOSED' -or
        [string]$controlExecutor.decomposition.responsibility -cne 'control-executor' -or
        [string]$controlExecutor.next_fixed_point -cne 'M42-02-PS11-SUPPLY-CHAIN' -or
        @($controlExecutor.decomposition.modules).Count -ne 6 -or
        [int]$controlExecutor.public_contract.function_count -ne 27 -or
        -not [bool]$controlExecutor.public_contract.unchanged -or
        -not [bool]$controlExecutor.semantic_contract.ordered_current_source_slices_preserved -or
        -not [bool]$controlExecutor.semantic_contract.function_names_and_order_unchanged -or
        -not [bool]$controlExecutor.semantic_contract.context_execution_state_unchanged -or
        -not [bool]$controlExecutor.semantic_contract.environment_execution_unchanged -or
        -not [bool]$controlExecutor.semantic_contract.performance_source_and_artifact_custody_unchanged -or
        -not [bool]$controlExecutor.semantic_contract.runtime_measurements_unchanged -or
        -not [bool]$controlExecutor.semantic_contract.package_and_delta_measurements_unchanged -or
        -not [bool]$controlExecutor.semantic_contract.aggregate_gate_unchanged -or
        -not [bool]$controlExecutor.semantic_contract.ps7_source_evolution_preserved -or
        [string]$controlExecutor.preservation.package_source_sha256 -cne $m4202PackageSourceSha256) {
      throw '[mir4-prefreeze-m42-02-control-executor-scope]'
    }
    foreach ($property in $controlExecutor.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-control-executor-transition] $($property.Name)" }
    }
    $priorReceiptPath = $controlExecutorReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }

  $supplyChainReceiptPath = 'releases/migrations/MIR4-M42-02-Supply-Chain-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $supplyChainReceiptPath) -PathType Leaf) {
    $supplyChain = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $supplyChainReceiptPath -Kind 'MIR4M4202SupplyChainDecompositionV1'
    if ([string]$supplyChain.predecessor.receipt -cne $priorReceiptPath -or
        [string]$supplyChain.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$supplyChain.predecessor.record_sha256 -cne [string]$controlExecutor.record_sha256) {
      throw '[mir4-prefreeze-m42-02-supply-chain-predecessor]'
    }
    $supplyChainEnrollmentBaselines = @{
      'docs/releases/mir4-post-4.0-roadmap.md'='24E6D2555808C1C940102FAF56C22F71CEDEECE84BED18C4E7177FECF9D6C8D4'
      'spec/programmes/mir4-4x-operating-programme-v1.json'='15197FD8F9A6A47224C491B1AFAF9A334F380BB4A96F5301DB68D627E950F846'
      'todo.md'='D70A5B24BB7CEB42D3F541920E7DC4BE2C4095B263CC6FD25C72EAF692BA3BE2'
      'tests/tooling/Test-MIR4ControlExecutorDecompositionM4202.ps1'='3C65D44E2A99D0455AD472AF90BFE28778A3F57C5B9DD5D59A7C8199623F5E91'
      'tools/lib/mir4/SupplyChain.ps1'='3D1CAF10F2EA14B21743BA3E8B1018930695816B7181D26A8B704B63152DC1D4'
    }
    $supplyChainEvolvedPaths = @{}
    foreach ($binding in @($supplyChain.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $supplyChainEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$supplyChainEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-supply-chain-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $supplyChainEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-supply-chain-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $supplyChainEvolvedPaths[$path] = $true
    }
    if ($supplyChainEvolvedPaths.Count -ne 36 -or
        [string]$supplyChain.status -cne 'M42-02-PS11-SUPPLY-CHAIN-DECOMPOSED-POWERSHELL-SEQUENCE-COMPLETE' -or
        [string]$supplyChain.decomposition.responsibility -cne 'supply-chain' -or
        [string]$supplyChain.next_fixed_point -cne 'M41-BRIDGE-RETIREMENT' -or
        @($supplyChain.decomposition.modules).Count -ne 5 -or
        [int]$supplyChain.public_contract.function_count -ne 28 -or
        -not [bool]$supplyChain.public_contract.unchanged -or
        -not [bool]$supplyChain.semantic_contract.ordered_current_source_slices_preserved -or
        -not [bool]$supplyChain.semantic_contract.inventory_and_source_identity_unchanged -or
        -not [bool]$supplyChain.semantic_contract.archive_and_selection_unchanged -or
        -not [bool]$supplyChain.semantic_contract.component_inventory_unchanged -or
        -not [bool]$supplyChain.semantic_contract.spdx_attestation_unchanged -or
        -not [bool]$supplyChain.semantic_contract.slsa_provenance_unchanged -or
        -not [bool]$supplyChain.semantic_contract.policy_verification_unchanged -or
        -not [bool]$supplyChain.semantic_contract.custody_record_writing_unchanged -or
        -not [bool]$supplyChain.semantic_contract.powershell_decomposition_sequence_complete -or
        [string]$supplyChain.programme_transition.current_state -cne 'complete' -or
        [string]$supplyChain.programme_transition.next_programme_state -cne 'queued' -or
        -not [bool]$supplyChain.programme_transition.mir41_qualification_still_required -or
        [string]$supplyChain.preservation.package_source_sha256 -cne $m4202PackageSourceSha256) {
      throw '[mir4-prefreeze-m42-02-supply-chain-scope]'
    }
    foreach ($property in $supplyChain.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-supply-chain-transition] $($property.Name)" }
    }
    $priorReceiptPath = $supplyChainReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }

  $sourceFreezeReceiptPath = 'releases/migrations/MIR4-M41-Source-Freeze-Authority-EvolutionV1.json'
  $sourceFreeze = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $sourceFreezeReceiptPath -Kind 'MIR4M41SourceFreezeAuthorityEvolutionV1'
  $bridgeRetirementReceiptPath = 'releases/migrations/MIR4-M41-Current-Product-Bridge-RetirementV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $bridgeRetirementReceiptPath) -PathType Leaf) {
    if ($priorReceiptPath -cne 'releases/migrations/MIR4-M42-02-Supply-Chain-DecompositionV1.json') {
      throw '[mir4-prefreeze-bridge-retirement-requires-supply-chain]'
    }
    $bridgeRetirement = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $bridgeRetirementReceiptPath -Kind 'MIR4M41CurrentProductBridgeRetirementReceiptV1'
    if ([string]$bridgeRetirement.predecessor.path -cne $priorReceiptPath -or
        [string]$bridgeRetirement.predecessor.sha256 -cne $priorReceiptSha256 -or
        [string]$bridgeRetirement.predecessor.record_sha256 -cne [string]$supplyChain.record_sha256) {
      throw '[mir4-prefreeze-bridge-retirement-predecessor]'
    }
    $bridgeRetirementPaths = @{}
    $bridgePredecessorCommit = '03737ccaefbda04001166e6b5e2fffe20ccadf96'
    foreach ($binding in @($bridgeRetirement.evolved_bindings)) {
      $path = [string]$binding.path
      if ($bridgeRetirementPaths.ContainsKey($path)) { throw "[mir4-prefreeze-bridge-retirement-duplicate-binding] $path" }
      if (-not $authorityHashes.ContainsKey($path)) {
        $predecessorSha = Get-MIRGitTextAtCommitSha256 -RepoRoot $repo -Commit $bridgePredecessorCommit -RelativePath $path
        if ([string]$binding.previous_sha256 -cne $predecessorSha) {
          throw "[mir4-prefreeze-bridge-retirement-enrollment-binding] $path"
        }
        $authorityHashes[$path] = $predecessorSha
        $authorityHashModes[$path] = 'canonical-text-v1'
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority) {
        throw "[mir4-prefreeze-bridge-retirement-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $bridgeRetirementPaths[$path] = $true
    }
    foreach ($binding in @($bridgeRetirement.current_authorities)) {
      $path = [string]$binding.path
      if ($bridgeRetirementPaths.ContainsKey($path) -or
          ($authorityHashes.ContainsKey($path) -and [string]$authorityHashes[$path] -cne [string]$binding.sha256)) {
        throw "[mir4-prefreeze-bridge-retirement-current-authority] $path"
      }
      $authorityHashes[$path] = [string]$binding.sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $bridgeRetirementPaths[$path] = $true
    }
    if ($bridgeRetirementPaths.Count -lt 1 -or
        [string]$bridgeRetirement.status -cne 'M41-CURRENT-PRODUCT-BRIDGES-RETIRED-PRIVATE-QUALIFICATION-PENDING' -or
        [string]$bridgeRetirement.package_source.predecessor_sha256 -cne $m4202PackageSourceSha256 -or
        [string]$bridgeRetirement.package_source.current_sha256 -cne [string]$sourceFreeze.package_source.predecessor_sha256 -or
        @($bridgeRetirement.package_visible_delta).Count -ne 0) {
      throw '[mir4-prefreeze-bridge-retirement-scope]'
    }
    foreach ($property in $bridgeRetirement.transition_gate.PSObject.Properties) {
      $expected = $property.Name -ceq 'bridge_retirement'
      if ([bool]$property.Value -ne $expected) { throw "[mir4-prefreeze-bridge-retirement-transition] $($property.Name)" }
    }
    $priorReceiptPath = $bridgeRetirementReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }

  $sourceFreezeChainChecks=[ordered]@{
    predecessor_path=([string]$sourceFreeze.predecessor.path -ceq $priorReceiptPath)
    predecessor_sha256=([string]$sourceFreeze.predecessor.sha256 -ceq $priorReceiptSha256)
    predecessor_record_sha256=([string]$sourceFreeze.predecessor.record_sha256 -ceq [string]$bridgeRetirement.record_sha256)
    base_branch=([string]$sourceFreeze.base.branch -ceq 'dev')
    base_commit=([string]$sourceFreeze.base.commit -ceq '65bb11c1226a8160c27ab074ddb503c20df98c69')
    base_tree=([string]$sourceFreeze.base.tree -ceq 'bebfd455f7f13d724eabb43c3ed48362d8d7901e')
    record_sha256=([string]$sourceFreeze.record_sha256 -ceq (Get-MIR4BootstrapRecordSha256 -Record $sourceFreeze))
    package_source_sha256=([string]$sourceFreeze.package_source.current_sha256 -ceq (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo))
    package_authority_record_sha256=([string]$sourceFreeze.package_source.authority_record_sha256 -ceq [string](Get-MIR4CanonicalPackageAuthority -RepoRoot $repo).record_sha256)
  }
  $failedSourceFreezeChainChecks=@($sourceFreezeChainChecks.GetEnumerator()|Where-Object{-not[bool]$_.Value}|ForEach-Object{[string]$_.Key})
  if ($failedSourceFreezeChainChecks.Count -ne 0) {
    throw "[mir4-prefreeze-m41-source-freeze-chain] failed=$($failedSourceFreezeChainChecks-join',')"
  }
  $sourceFreezePaths = @{}
  foreach ($binding in @($sourceFreeze.evolved_bindings)) {
    $path = [string]$binding.path
    if ($sourceFreezePaths.ContainsKey($path) -or [string]$binding.hash_mode -cne 'canonical-text-v1' -or [bool]$binding.package_visible) {
      throw "[mir4-prefreeze-m41-source-freeze-evolved-binding] $path"
    }
    if ($authorityHashes.ContainsKey($path)) {
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode) {
        throw "[mir4-prefreeze-m41-source-freeze-predecessor-binding] $path"
      }
    } else {
      $baseSha = Get-MIRGitTextAtCommitSha256 -RepoRoot $repo -Commit ([string]$sourceFreeze.base.commit) -RelativePath $path
      if ([string]$binding.previous_sha256 -cne $baseSha) { throw "[mir4-prefreeze-m41-source-freeze-base-binding] $path" }
    }
    if ([bool]$binding.release_authority -ne ($path -ceq 'governance/release/mir4-4.1-release-readiness-v1.json')) {
      throw "[mir4-prefreeze-m41-source-freeze-release-authority] $path"
    }
    $authorityHashes[$path]=[string]$binding.current_sha256;$authorityHashModes[$path]=[string]$binding.hash_mode;$sourceFreezePaths[$path]=$true
  }
  foreach ($binding in @($sourceFreeze.current_authorities)) {
    $path=[string]$binding.path
    if ($sourceFreezePaths.ContainsKey($path) -or $authorityHashes.ContainsKey($path) -or [string]$binding.hash_mode -cne 'canonical-text-v1' -or [bool]$binding.package_visible) {
      throw "[mir4-prefreeze-m41-source-freeze-current-binding] $path"
    }
    & git -C $repo cat-file -e (([string]$sourceFreeze.base.commit)+':'+$path) 2>$null
    if ($LASTEXITCODE -eq 0) { throw "[mir4-prefreeze-m41-source-freeze-new-path] $path" }
    if ([bool]$binding.release_authority -ne ($path -ceq 'governance/release/mir4-4.1-release-readiness-v1.json')) {
      throw "[mir4-prefreeze-m41-source-freeze-release-authority] $path"
    }
    $authorityHashes[$path]=[string]$binding.sha256;$authorityHashModes[$path]=[string]$binding.hash_mode;$sourceFreezePaths[$path]=$true
  }
  $trackedSourceFreezeChanges=@(& git -C $repo diff --name-only ([string]$sourceFreeze.base.commit) --)
  if($LASTEXITCODE-ne0){throw '[mir4-prefreeze-m41-source-freeze-diff]'}
  $untrackedSourceFreezeChanges=@(& git -C $repo ls-files --others --exclude-standard)
  if($LASTEXITCODE-ne0){throw '[mir4-prefreeze-m41-source-freeze-untracked]'}
  $actualSourceFreezePaths=@($trackedSourceFreezeChanges+$untrackedSourceFreezeChanges|ForEach-Object{([string]$_).Replace('\','/')}|Where-Object{$_-and$_-cne$sourceFreezeReceiptPath}|Sort-Object -Unique)
  $boundSourceFreezePaths=@($sourceFreezePaths.Keys|Sort-Object)
  if (($actualSourceFreezePaths-join"`n") -cne ($boundSourceFreezePaths-join"`n") -or
      [int]$sourceFreeze.changed_path_count -ne $sourceFreezePaths.Count -or
      [string]$sourceFreeze.status -cne 'MIR41-RELEASE-READINESS-AUTHORITY-EVOLVED-SOURCE-FREEZE-PENDING' -or
      (@($sourceFreeze.package_visible_delta|ForEach-Object{[string]$_.target})-join'|') -cne 'f210|f200|f110|f100' -or
      @($sourceFreeze.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value -ne ($_.Name-in@('version_allocation','private_build','qualification'))}).Count -ne 0) {
    throw '[mir4-prefreeze-m41-source-freeze-scope]'
  }
  $priorReceiptPath=$sourceFreezeReceiptPath
  $priorReceiptSha256=Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)

  $staleAuthorityBindings = @()
  foreach ($binding in $authorityHashes.GetEnumerator()) {
    $full = Join-Path $repo ([string]$binding.Key)
    $hashMode = if($authorityHashModes.ContainsKey([string]$binding.Key)){[string]$authorityHashModes[[string]$binding.Key]}else{'raw-bytes'}
    if (-not (Test-Path -LiteralPath $full -PathType Leaf) -or
        (Get-MIR4PreFreezeFileSha256 -Path $full -Mode $hashMode) -cne [string]$binding.Value) {
      $currentBindingSha256 = if (Test-Path -LiteralPath $full -PathType Leaf) {
        Get-MIR4PreFreezeFileSha256 -Path $full -Mode $hashMode
      } else {
        'ABSENT'
      }
      $staleAuthorityBindings += "$([string]$binding.Key)|$([string]$binding.Value)|$currentBindingSha256|$hashMode"
    }
  }
  if ($staleAuthorityBindings.Count -ne 0) {
    throw "[mir4-prefreeze-current-authority-binding] $(@($staleAuthorityBindings | Sort-Object) -join ',')"
  }
  $review = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-PR152-Independent-Readiness-Acceptance-LUNAV1.json' -Kind 'MIR4IndependentReadinessAcceptanceLunaV1'
  if ([string]$review.verdict -cne 'ACCEPTED-RELEASE-READINESS' -or [bool]$review.maintainer_acceptance) {
    throw '[mir4-prefreeze-independent-review]'
  }
  $t15Review = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-T15-Independent-Machine-AcceptanceV1.json' -Kind 'MIR4T15IndependentMachineAcceptanceV1'
  if ([string]$t15Review.verdict -cne 'ACCEPTED-T15-MACHINE-SCOPE' -or
      [bool]$t15Review.reviewer.human_reviewer_claimed -or
      [bool]$t15Review.reviewer.human_acceptance_inferred -or
      [bool]$t15Review.release_authority) {
    throw '[mir4-prefreeze-t15-independent-machine-review]'
  }
  return $receipt
}
