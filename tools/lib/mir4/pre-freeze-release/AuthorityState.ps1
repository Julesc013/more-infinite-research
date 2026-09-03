function Get-MIR4PreFreezeAuthorityState {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [switch]$IncludeT17MachinePreparation,
    [switch]$IncludeRepositoryMigration,
    [switch]$IncludeCanonicalizationMigration,
    [switch]$IncludeDiagnosticsMigration,
    [switch]$IncludeTargetKeyMigration,
    [switch]$IncludeWholePlatformMigration,
    [switch]$IncludeTechnologyAcceptanceMigration,
    [switch]$IncludeTargetCompilerMigration,
    [switch]$IncludeSemanticCompilerPolicyMigration,
    [switch]$IncludeRuntimeContinuityMigration,
    [switch]$IncludeModuleSdkMepMigration,
    [switch]$IncludeProcessIRExactMigration,
    [switch]$IncludeInspectorCompatibilityMigration,
    [switch]$IncludeAssuranceOfflineCustodyMigration,
    [switch]$IncludeHistoricalToolingMigration,
    [switch]$IncludeReleaseToolingMigration,
    [switch]$IncludeF210QualificationPolicyEvolution,
    [switch]$IncludeFinalMileToolingEvolution,
    [switch]$IncludeFinalReleaseClosureEvolution,
    [switch]$IncludePostReleasePackageBaselineEvolution,
    [switch]$IncludePostReleaseAutomationCutover,
    [switch]$IncludePostReleaseBranchOperatingModel,
    [switch]$IncludePostReleasePatchLaneRehearsal,
    [switch]$IncludeM4103ChangeReleaseAuthority,
    [switch]$IncludeM4105AM4200ACharacterizationAuthority,
    [switch]$IncludeM41F0TruthReconciliationAuthority,
    [switch]$IncludeM41F1GoldenBaselineAuthority,
    [switch]$IncludeM41F2AShadowMaterializerAuthority,
    [switch]$IncludeM41F2BShadowSourceModelAuthority,
    [switch]$IncludeM41F2CEditableSourceMaterializerAuthority,
    [switch]$IncludeM41F2DHarnessAuthority,
    [switch]$IncludeM41F2DF210RuntimeReplayAuthority,
    [string[]]$M41F2DTargetRuntimeReplayTargets = @(),
    [switch]$IncludeM41F2DAggregateAuthority
  )
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $receipt = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json' -Kind 'MIR4PostReadinessMergeReceiptSOL15V1'
  $authorityHashes = @{}
  $authorityHashModes = @{}
  foreach ($binding in @($receipt.authority_bindings)) {
    $authorityHashes[[string]$binding.path] = [string]$binding.sha256
    $authorityHashModes[[string]$binding.path] = $(if($binding.PSObject.Properties.Name-contains'hash_mode'){[string]$binding.hash_mode}else{'raw-bytes'})
  }
  $priorReceiptPath = '.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json'
  $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  $links = @(
    @{path='.mir/releases/waves/mir4-r0/MIR4-T02-Authority-Evolution-ReceiptV1.json';kind='MIR4T02AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T03-Authority-Evolution-ReceiptV1.json';kind='MIR4T03AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T04-Authority-Evolution-ReceiptV1.json';kind='MIR4T04AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T05-Authority-Evolution-ReceiptV1.json';kind='MIR4T05AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T06-Authority-Evolution-ReceiptV1.json';kind='MIR4T06AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T07-Authority-Evolution-ReceiptV1.json';kind='MIR4T07AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T08-Authority-Evolution-ReceiptV1.json';kind='MIR4T08AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T09-Authority-Evolution-ReceiptV1.json';kind='MIR4T09AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T10-Authority-Evolution-ReceiptV1.json';kind='MIR4T10AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T11-Authority-Evolution-ReceiptV1.json';kind='MIR4T11AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T12-Authority-Evolution-ReceiptV1.json';kind='MIR4T12AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T13-Authority-Evolution-ReceiptV1.json';kind='MIR4T13AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T14-Authority-Evolution-ReceiptV1.json';kind='MIR4T14AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json';kind='MIR4T15AuthorityEvolutionReceiptV1'}
  )
  if ($IncludeT17MachinePreparation) {
    $links += @{path='.mir/releases/waves/mir4-r0/MIR4-T17-Machine-Preparation-Authority-Evolution-ReceiptV1.json';kind='MIR4T17MachinePreparationAuthorityEvolutionReceiptV1'}
  }
  if ($IncludeRepositoryMigration) {
    if (-not $IncludeT17MachinePreparation) { throw '[mir4-prefreeze-repository-migration-requires-t17]' }
    $links += @{path='releases/migrations/MIR4-Repository-Fixed-Point-Tooling-MigrationV1.json';kind='MIR4RepositoryMigrationReceiptV1'}
  }
  if ($IncludeCanonicalizationMigration) {
    if (-not $IncludeRepositoryMigration) { throw '[mir4-prefreeze-canonicalization-migration-requires-repository-migration]' }
    $links += @{path='releases/migrations/MIR4-Canonicalization-Tooling-MigrationV1.json';kind='MIR4CanonicalizationMigrationReceiptV1'}
  }
  if ($IncludeDiagnosticsMigration) {
    if (-not $IncludeCanonicalizationMigration) { throw '[mir4-prefreeze-diagnostics-migration-requires-canonicalization-migration]' }
    $links += @{path='releases/migrations/MIR4-Diagnostics-Tooling-MigrationV1.json';kind='MIR4DiagnosticsMigrationReceiptV1'}
  }
  if ($IncludeTargetKeyMigration) {
    if (-not $IncludeDiagnosticsMigration) { throw '[mir4-prefreeze-target-key-migration-requires-diagnostics-migration]' }
    $links += @{path='releases/migrations/MIR4-Target-Key-Tooling-MigrationV1.json';kind='MIR4TargetKeyMigrationReceiptV1'}
  }
  if ($IncludeWholePlatformMigration) {
    if (-not $IncludeTargetKeyMigration) { throw '[mir4-prefreeze-whole-platform-migration-requires-target-key-migration]' }
    $links += @{path='releases/migrations/MIR4-Whole-Platform-Tooling-MigrationV1.json';kind='MIR4WholePlatformMigrationReceiptV1'}
  }
  if ($IncludeTechnologyAcceptanceMigration) {
    if (-not $IncludeWholePlatformMigration) { throw '[mir4-prefreeze-technology-acceptance-migration-requires-whole-platform-migration]' }
    $links += @{path='releases/migrations/MIR4-Technology-Acceptance-Tooling-MigrationV1.json';kind='MIR4TechnologyAcceptanceMigrationReceiptV1'}
  }
  if ($IncludeTargetCompilerMigration) {
    if (-not $IncludeTechnologyAcceptanceMigration) { throw '[mir4-prefreeze-target-compiler-migration-requires-technology-acceptance-migration]' }
    $links += @{path='releases/migrations/MIR4-Target-Compiler-Tooling-MigrationV1.json';kind='MIR4TargetCompilerMigrationReceiptV1'}
  }
  if ($IncludeSemanticCompilerPolicyMigration) {
    if (-not $IncludeTargetCompilerMigration) { throw '[mir4-prefreeze-semantic-compiler-policy-migration-requires-target-compiler-migration]' }
    $links += @{path='releases/migrations/MIR4-Semantic-Compiler-Policy-Tooling-MigrationV1.json';kind='MIR4SemanticCompilerPolicyMigrationReceiptV1'}
  }
  if ($IncludeRuntimeContinuityMigration) {
    if (-not $IncludeSemanticCompilerPolicyMigration) { throw '[mir4-prefreeze-runtime-continuity-migration-requires-semantic-compiler-policy-migration]' }
    $links += @{path='releases/migrations/MIR4-Runtime-Continuity-Tooling-MigrationV1.json';kind='MIR4RuntimeContinuityMigrationReceiptV1'}
  }
  if ($IncludeModuleSdkMepMigration) {
    if (-not $IncludeRuntimeContinuityMigration) { throw '[mir4-prefreeze-module-sdk-mep-migration-requires-runtime-continuity-migration]' }
    $links += @{path='releases/migrations/MIR4-Module-Sdk-Mep-Tooling-MigrationV1.json';kind='MIR4ModuleSdkMepMigrationReceiptV1'}
  }
  if ($IncludeProcessIRExactMigration) {
    if (-not $IncludeModuleSdkMepMigration) { throw '[mir4-prefreeze-processir-exact-migration-requires-module-sdk-mep-migration]' }
    $links += @{path='releases/migrations/MIR4-ProcessIR-Exact-Tooling-MigrationV1.json';kind='MIR4ProcessIRExactMigrationReceiptV1'}
  }
  if ($IncludeInspectorCompatibilityMigration) {
    if (-not $IncludeProcessIRExactMigration) { throw '[mir4-prefreeze-inspector-compatibility-migration-requires-processir-exact-migration]' }
    $links += @{path='releases/migrations/MIR4-Inspector-Compatibility-Tooling-MigrationV1.json';kind='MIR4InspectorCompatibilityMigrationReceiptV1'}
  }
  if ($IncludeAssuranceOfflineCustodyMigration) {
    if (-not $IncludeInspectorCompatibilityMigration) { throw '[mir4-prefreeze-assurance-offline-custody-migration-requires-inspector-compatibility-migration]' }
    $links += @{path='releases/migrations/MIR4-Assurance-Offline-Custody-Tooling-MigrationV1.json';kind='MIR4AssuranceOfflineCustodyMigrationReceiptV1'}
  }
  if ($IncludeHistoricalToolingMigration) {
    if (-not $IncludeAssuranceOfflineCustodyMigration) { throw '[mir4-prefreeze-historical-tooling-migration-requires-assurance-offline-custody-migration]' }
    $links += @{path='releases/migrations/MIR4-Historical-Tooling-MigrationV1.json';kind='MIR4HistoricalToolingMigrationReceiptV1'}
  }
  if ($IncludeReleaseToolingMigration) {
    if (-not $IncludeHistoricalToolingMigration) { throw '[mir4-prefreeze-release-tooling-migration-requires-historical-tooling-migration]' }
    $links += @{path='releases/migrations/MIR4-Release-Tooling-MigrationV1.json';kind='MIR4ReleaseToolingMigrationReceiptV1'}
  }
  if ($IncludeF210QualificationPolicyEvolution) {
    if (-not $IncludeReleaseToolingMigration) { throw '[mir4-prefreeze-f210-policy-evolution-requires-release-tooling-migration]' }
    $links += @{path='.mir/releases/waves/mir4-r0/MIR4-F210-Qualification-Policy-Authority-Evolution-ReceiptV1.json';kind='MIR4F210QualificationPolicyAuthorityEvolutionReceiptV1'}
  }
  if ($IncludeFinalMileToolingEvolution) {
    if (-not $IncludeF210QualificationPolicyEvolution) { throw '[mir4-prefreeze-final-mile-tooling-evolution-requires-f210-policy-evolution]' }
    $links += @{path='.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Tooling-Authority-Evolution-ReceiptV1.json';kind='MIR4FinalMileToolingAuthorityEvolutionReceiptV1'}
  }
  if ($IncludeFinalReleaseClosureEvolution) {
    if (-not $IncludeFinalMileToolingEvolution) { throw '[mir4-prefreeze-final-release-closure-evolution-requires-final-mile-tooling-evolution]' }
    $links += @{path='.mir/releases/waves/mir4-r0/MIR4-Final-Release-Closure-Authority-Evolution-ReceiptV1.json';kind='MIR4FinalReleaseClosureAuthorityEvolutionReceiptV1'}
  }
  if ($IncludePostReleasePackageBaselineEvolution) {
    if (-not $IncludeFinalReleaseClosureEvolution) { throw '[mir4-prefreeze-post-release-package-baseline-evolution-requires-final-release-closure-evolution]' }
    $links += @{path='.mir/releases/waves/mir4-r0/MIR4-Post-Release-Package-Baseline-Authority-Evolution-ReceiptV1.json';kind='MIR4PostReleasePackageBaselineAuthorityEvolutionReceiptV1'}
  }
  if ($IncludePostReleaseAutomationCutover) {
    if (-not $IncludePostReleasePackageBaselineEvolution) { throw '[mir4-prefreeze-post-release-automation-cutover-requires-package-baseline-evolution]' }
    $links += @{path='releases/migrations/MIR4-Post-Release-Automation-Authority-CutoverV1.json';kind='MIR4PostReleaseAutomationAuthorityCutoverV1'}
  }
  if ($IncludePostReleaseBranchOperatingModel) {
    if (-not $IncludePostReleaseAutomationCutover) { throw '[mir4-prefreeze-post-release-branch-operating-model-requires-automation-cutover]' }
    $links += @{path='releases/migrations/MIR4-Branch-Operating-Model-Authority-EvolutionV1.json';kind='MIR4BranchOperatingModelAuthorityEvolutionV1'}
  }
  if ($IncludePostReleasePatchLaneRehearsal) {
    if (-not $IncludePostReleaseBranchOperatingModel) { throw '[mir4-prefreeze-post-release-patch-lane-rehearsal-requires-branch-operating-model]' }
    $links += @{path='releases/migrations/MIR4-Patch-Lane-Rehearsal-Authority-EvolutionV1.json';kind='MIR4PatchLaneRehearsalAuthorityEvolutionV1'}
  }
  if ($IncludeM4103ChangeReleaseAuthority) {
    if (-not $IncludePostReleasePatchLaneRehearsal) { throw '[mir4-prefreeze-m41-03-requires-patch-lane-rehearsal]' }
    $links += @{path='releases/migrations/MIR4-M41-03-Change-And-Release-Authority-EvolutionV1.json';kind='MIR4M4103ChangeAndReleaseAuthorityEvolutionV1'}
  }
  if ($IncludeM4105AM4200ACharacterizationAuthority) {
    if (-not $IncludeM4103ChangeReleaseAuthority) { throw '[mir4-prefreeze-m41-05a-m42-00a-requires-m41-03]' }
    $links += @{path='releases/migrations/MIR4-M41-05A-M42-00A-Repository-Characterization-Authority-EvolutionV1.json';kind='MIR4M4105AM4200ARepositoryCharacterizationAuthorityEvolutionV1'}
  }
  if ($IncludeM41F0TruthReconciliationAuthority) {
    if (-not $IncludeM4105AM4200ACharacterizationAuthority) { throw '[mir4-prefreeze-m41-f0-requires-characterization]' }
    $links += @{path='releases/migrations/MIR4-M41-F0-Truth-Reconciliation-Authority-EvolutionV1.json';kind='MIR4M41F0TruthReconciliationAuthorityEvolutionV1'}
  }
  if ($IncludeM41F1GoldenBaselineAuthority) {
    if (-not $IncludeM41F0TruthReconciliationAuthority) { throw '[mir4-prefreeze-m41-f1-requires-m41-f0]' }
    $links += @{path='releases/migrations/MIR4-M41-F1-Golden-Four-Target-Baseline-Authority-EvolutionV1.json';kind='MIR4M41F1GoldenFourTargetBaselineAuthorityEvolutionV1'}
  }
  if ($IncludeM41F2AShadowMaterializerAuthority) {
    if (-not $IncludeM41F1GoldenBaselineAuthority) { throw '[mir4-prefreeze-m41-f2a-requires-m41-f1]' }
    $links += @{path='releases/migrations/MIR4-M41-F2A-Shadow-Target-Materializer-Authority-EvolutionV1.json';kind='MIR4M41F2AShadowTargetMaterializerAuthorityEvolutionV1'}
  }
  if ($IncludeM41F2BShadowSourceModelAuthority) {
    if (-not $IncludeM41F2AShadowMaterializerAuthority) { throw '[mir4-prefreeze-m41-f2b-requires-m41-f2a]' }
    $links += @{path='releases/migrations/MIR4-M41-F2B-Shadow-Source-Model-Authority-EvolutionV1.json';kind='MIR4M41F2BShadowSourceModelAuthorityEvolutionV1'}
  }
  if ($IncludeM41F2CEditableSourceMaterializerAuthority) {
    if (-not $IncludeM41F2BShadowSourceModelAuthority) { throw '[mir4-prefreeze-m41-f2c-requires-m41-f2b]' }
    $links += @{path='releases/migrations/MIR4-M41-F2C-Editable-Source-Materializer-Authority-EvolutionV1.json';kind='MIR4M41F2CEditableSourceMaterializerAuthorityEvolutionV1'}
  }
  if ($IncludeM41F2DHarnessAuthority) {
    if (-not $IncludeM41F2CEditableSourceMaterializerAuthority) { throw '[mir4-prefreeze-m41-f2d-harness-requires-m41-f2c]' }
    $links += @{path='releases/migrations/MIR4-M41-F2D-Runtime-Replay-Harness-Authority-EvolutionV1.json';kind='MIR4M41F2DRuntimeReplayHarnessAuthorityEvolutionV1'}
  }
  if ($IncludeM41F2DF210RuntimeReplayAuthority) {
    if (-not $IncludeM41F2DHarnessAuthority) { throw '[mir4-prefreeze-m41-f2d-f210-requires-f2d-harness]' }
    $links += @{path='releases/migrations/MIR4-M41-F2D-F210-Runtime-Replay-Authority-EvolutionV1.json';kind='MIR4M41F2DF210RuntimeReplayAuthorityEvolutionV1'}
  }
  $orderedF2DTargets = @('f200','f110','f100')
  $requestedF2DTargets = @($M41F2DTargetRuntimeReplayTargets | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)
  if (@($requestedF2DTargets | Where-Object { $_ -notin $orderedF2DTargets }).Count -ne 0) { throw '[mir4-prefreeze-m41-f2d-target-unsupported]' }
  $acceptedF2DTargets = [Collections.Generic.List[string]]::new()
  foreach ($target in $orderedF2DTargets) {
    if ($target -notin $requestedF2DTargets) { continue }
    if ($target -eq 'f200' -and -not $IncludeM41F2DF210RuntimeReplayAuthority) { throw '[mir4-prefreeze-m41-f2d-f200-requires-f210]' }
    if ($target -eq 'f110' -and 'f200' -notin $acceptedF2DTargets) { throw '[mir4-prefreeze-m41-f2d-f110-requires-f200]' }
    if ($target -eq 'f100' -and 'f110' -notin $acceptedF2DTargets) { throw '[mir4-prefreeze-m41-f2d-f100-requires-f110]' }
    $code = $target.Substring(1).ToUpperInvariant()
    $links += @{path="releases/migrations/MIR4-M41-F2D-F$code-Runtime-Replay-Authority-EvolutionV1.json";kind='MIR4M41F2DTargetRuntimeReplayAuthorityEvolutionV1'}
    $acceptedF2DTargets.Add($target)
  }
  if ($IncludeM41F2DAggregateAuthority) {
    if ((@($acceptedF2DTargets) -join '|') -cne 'f200|f110|f100') { throw '[mir4-prefreeze-m41-f2d-aggregate-requires-four-targets]' }
    $links += @{path='releases/migrations/MIR4-M41-F2D-Four-Target-Runtime-Replay-AggregateV1.json';kind='MIR4M41F2DFourTargetRuntimeReplayAggregateV1'}
  }
  foreach ($link in $links) {
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
  return [pscustomobject][ordered]@{
    authority_hashes = $authorityHashes
    authority_hash_modes = $authorityHashModes
    prior_receipt_path = $priorReceiptPath
    prior_receipt_sha256 = $priorReceiptSha256
  }
}
