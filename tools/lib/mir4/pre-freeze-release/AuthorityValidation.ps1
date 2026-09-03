function Test-MIR4PreFreezeAuthorities {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
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
        [string]$commandRouter.preservation.package_source_sha256 -cne (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)) {
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
        [string]$validationRunner.preservation.package_source_sha256 -cne (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)) {
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
        [string]$assuranceEvidence.preservation.package_source_sha256 -cne (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)) {
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
        [string]$preFreezeRelease.preservation.package_source_sha256 -cne (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)) {
      throw '[mir4-prefreeze-m42-02-pre-freeze-release-scope]'
    }
    foreach ($property in $preFreezeRelease.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-pre-freeze-release-transition] $($property.Name)" }
    }
    $priorReceiptPath = $preFreezeReleaseReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }  $staleAuthorityBindings = @()
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
