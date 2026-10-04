function Test-MIR4PreFreezeAuthorities {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  if (-not (Get-Command Get-MIR4BootstrapRecordSha256 -ErrorAction SilentlyContinue)) {
    . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
  }
  if (-not (Get-Command Test-MIR4M41ToM42ComposableSourceSuccession -ErrorAction SilentlyContinue)) {
    . (Join-Path $repo 'tools/mir/application/release/readiness/ComposableSourceSuccession.ps1')
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
  . (Join-Path $repo 'tools/lib/mir4/pre-freeze-release/AuthoritySuccessionValidation.ps1')

  $sourceFreezeChainChecks=[ordered]@{
    predecessor_path=([string]$sourceFreeze.predecessor.path -ceq $priorReceiptPath)
    predecessor_sha256=([string]$sourceFreeze.predecessor.sha256 -ceq $priorReceiptSha256)
    predecessor_record_sha256=([string]$sourceFreeze.predecessor.record_sha256 -ceq [string]$bridgeRetirement.record_sha256)
    base_branch=([string]$sourceFreeze.base.branch -ceq 'dev')
    base_commit=([string]$sourceFreeze.base.commit -ceq '65bb11c1226a8160c27ab074ddb503c20df98c69')
    base_tree=([string]$sourceFreeze.base.tree -ceq 'bebfd455f7f13d724eabb43c3ed48362d8d7901e')
    record_sha256=([string]$sourceFreeze.record_sha256 -ceq (Get-MIR4BootstrapRecordSha256 -Record $sourceFreeze))
    historical_package_source_sha256=([string]$sourceFreeze.package_source.current_sha256 -ceq '0DEDF851B388D8523110A2ABEDB3A7B2091E1CC119944F5EA7D4C1E7C01698DA')
    historical_package_authority_record_sha256=([string]$sourceFreeze.package_source.authority_record_sha256 -ceq '325CFA978C191C93E41F85D8F9AEB664B3A045D34D6721D647F8BE4E4F7F3CDB')
  }
  $failedSourceFreezeChainChecks=@($sourceFreezeChainChecks.GetEnumerator()|Where-Object{-not[bool]$_.Value}|ForEach-Object{[string]$_.Key})
  if ($failedSourceFreezeChainChecks.Count -ne 0) {
    throw "[mir4-prefreeze-m41-source-freeze-chain] failed=$($failedSourceFreezeChainChecks-join',')"
  }
  try {
    $composableSourceSuccessor = Test-MIR4M41ToM42ComposableSourceSuccession -RepoRoot $repo
  } catch {
    throw "[mir4-prefreeze-m41-composable-source-successor] $($_.Exception.Message)"
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
  # The published freeze receipt authenticates its original source. An explicit,
  # separately validated documentation successor binds every later changed path.
  . (Join-Path $repo 'tools/lib/mir4/PostReleaseDocumentation.ps1')
  $postReleaseDocumentation=Get-MIR4PostReleaseDocumentation -RepoRoot $repo -Historical:$true
  if($null -ne $postReleaseDocumentation){
    $trackedSourceFreezeChanges=@(& git -C $repo diff --name-only ([string]$sourceFreeze.base.commit) ([string]$postReleaseDocumentation.base_commit) --)
  }else{
    $trackedSourceFreezeChanges=@(& git -C $repo diff --name-only ([string]$sourceFreeze.base.commit) --)
  }
  if($LASTEXITCODE-ne0){throw '[mir4-prefreeze-m41-source-freeze-diff]'}
  $untrackedSourceFreezeChanges=@(& git -C $repo ls-files --others --exclude-standard)
  if($null -ne $postReleaseDocumentation){$untrackedSourceFreezeChanges=@()} # Already checked against the exact successor scope.
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

  if($null -ne $postReleaseDocumentation){
    foreach($binding in @($postReleaseDocumentation.bindings)){
      $path=[string]$binding.path
      if($authorityHashes.ContainsKey($path)){
        if([string]$authorityHashModes[$path] -cne 'canonical-text-v1' -or
           [string]$binding.previous_sha256 -cne [string]$authorityHashes[$path]){
          throw "[mir4-post-release-docs-authority-chain] $path"
        }
        $authorityHashes[$path]=[string]$binding.current_sha256
      }
    }
  }
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
    # These hashes are the immutable MIR 4.1 authority lineage just replayed
    # above.  They are not allowed to impersonate current authority after the
    # governed V2 source-composition cutover.  The successor validator binds
    # the actual current package source and authority, while its closed gates
    # ensure that no current 4.1 release operation can use this historical
    # lineage.  A direct comparison to the current tree would otherwise turn
    # the historical record into a false authority and reject the approved
    # successor merely because its paths were intentionally superseded.
    if ([bool]$composableSourceSuccessor.current_release_operations_authorized) {
      throw '[mir4-prefreeze-m41-composable-source-successor-release-firewall]'
    }
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
