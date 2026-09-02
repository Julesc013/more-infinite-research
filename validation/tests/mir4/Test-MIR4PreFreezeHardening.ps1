param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
$legacyRootPackageSourceSha256='8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'
$historicalRootReadmeSha256='DF5D4D801DC4A416E4F7C9826EB2E3AE6CFD915937C8599CA7307CCEB343F947'

$receipt=Test-MIR4PreFreezeAuthorities -RepoRoot $repo
$rulesets=Test-MIR4RulesetSnapshot -RepoRoot $repo
$actions=Test-MIR4ProductionActionLock -RepoRoot $repo
if([string]$receipt.status-cne'DEV-READINESS-AUTHORIZED-RELEASE-BLOCKED'){throw '[mir4-prefreeze-receipt-status]'}
$evolution=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T02-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if(@($evolution.evolved_bindings).Count-ne1-or[string]$evolution.evolved_bindings[0].path-cne'.mir/releases/waves/mir4-r0/MIR4-Release-Workflow-ContractV1.json'-or
   [bool]$evolution.evolved_bindings[0].package_visible-or[bool]$evolution.evolved_bindings[0].release_authority-or
   [string]$evolution.player_package_source_sha256-cne'9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'){
  throw '[mir4-prefreeze-explicit-authority-evolution]'
}
$t03=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T03-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if(@($t03.evolved_bindings).Count-ne2-or@($t03.current_authorities).Count-ne6-or
   (@($t03.evolved_bindings.path|Sort-Object)-join'|')-cne'.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json|.mir/releases/waves/mir4-r0/MIR4-Release-Workflow-ContractV1.json'-or
   [string]$t03.player_package_source_sha256-cne'9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'-or
   @($t03.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-t03-authority-evolution]'
}
$t04=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T04-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if(@($t04.evolved_bindings).Count-ne3-or@($t04.current_authorities).Count-ne15-or
   (@($t04.evolved_bindings.path|Sort-Object)-join'|')-cne'.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json|.mir/releases/waves/mir4-r0/MIR4-Release-Workflow-ContractV1.json|tools/lib/mir4/ReleaseAdapters.ps1'-or
   [string]$t04.player_package_source_sha256-cne'9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'-or
   @($t04.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-t04-authority-evolution]'
}
$t05=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T05-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if(@($t05.evolved_bindings).Count-ne3-or@($t05.current_authorities).Count-ne21-or
   (@($t05.evolved_bindings.path|Sort-Object)-join'|')-cne'.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json|.mir/releases/waves/mir4-r0/MIR4-Release-Workflow-ContractV1.json|tools/lib/mir4/ReleaseAdapters.ps1'-or
   [string]$t05.player_package_source_sha256-cne'9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'-or
   @($t05.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-t05-authority-evolution]'
}
$t06=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T06-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if(@($t06.evolved_bindings).Count-ne2-or@($t06.current_authorities).Count-ne10-or
   (@($t06.evolved_bindings.path|Sort-Object)-join'|')-cne'.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json|.mir/releases/waves/mir4-r0/MIR4-Release-Workflow-ContractV1.json'-or
   [string]$t06.player_package_source_sha256-cne'9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'-or
   @($t06.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-t06-authority-evolution]'
}
$t07=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T07-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if(@($t07.evolved_bindings).Count-ne3-or@($t07.current_authorities).Count-ne32-or
   (@($t07.evolved_bindings.path|Sort-Object)-join'|')-cne'.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json|tools/lib/mir4/PlatformPreview.ps1|tools/lib/mir4/PreFreezeRelease.ps1'-or
   [string]$t07.player_package_source_sha256-cne'9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'-or
   @($t07.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-t07-authority-evolution]'
}
$t08=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T08-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if(@($t08.evolved_bindings).Count-ne4-or@($t08.current_authorities).Count-lt40-or
   (@($t08.evolved_bindings.path|Sort-Object)-join'|')-cne'.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json|tools/lib/mir4/ExperimentalApiSdk.ps1|tools/lib/mir4/PlatformPreview.ps1|tools/lib/mir4/PreFreezeRelease.ps1'-or
   [string]$t08.player_package_source_sha256-cne'9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'-or
   @($t08.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-t08-authority-evolution]'
}
$t11=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T11-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if(@($t11.evolved_bindings).Count-lt29-or@($t11.current_authorities).Count-lt40-or
   [string]$t11.turn-cne'T11'-or[string]$t11.status-cne'T11-F210-MEP-DISCOVERY-PASSED-PRODUCTION-UNAUTHORIZED'-or
   [string]$t11.player_package_source_sha256-cne'9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'-or
   -not[bool]$t11.conformance.permutation_digest_stable-or-not[bool]$t11.conformance.host_absence_inert-or
   -not[bool]$t11.conformance.conflict_quarantine_passed-or-not[bool]$t11.conformance.terminal_emitter_unchanged-or
   @($t11.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-t11-authority-evolution]'
}
$t12=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T12-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if(@($t12.evolved_bindings).Count-lt1-or@($t12.current_authorities).Count-lt15-or
   [string]$t12.turn-cne'T12'-or[string]$t12.status-cne'T12-EXACT-PROCESSIR-PASSED-WITH-DECLARED-CUSTODY-BLOCKER-PRODUCTION-UNAUTHORIZED'-or
   [string]$t12.player_package_source_sha256-cne'9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'-or
   [int]$t12.conformance.capture_count-ne10-or[int]$t12.conformance.required_capture_count-ne11-or
   -not[bool]$t12.conformance.all_deterministic-or-not[bool]$t12.conformance.t12_machine_work_complete-or
   [bool]$t12.conformance.f200_k2so_archive_custody_complete-or-not[bool]$t12.conformance.narrow_blocker_declared-or
   @($t12.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-t12-authority-evolution]'
}
$t13=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T13-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if(@($t13.evolved_bindings).Count-lt10-or@($t13.current_authorities).Count-lt25-or
   [string]$t13.turn-cne'T13'-or[string]$t13.status-cne'T13-EXACT-RELEASE-CANARIES-PASSED-T14-NEXT-PRODUCTION-UNAUTHORIZED'-or
   [string]$t13.player_package_source_sha256-cne'9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'-or
   [int]$t13.conformance.canary_count-ne8-or[int]$t13.conformance.capture_count-ne11-or[int]$t13.conformance.reload_count-ne22-or
   -not[bool]$t13.conformance.all_clean_loads_passed-or-not[bool]$t13.conformance.all_first_reloads_passed-or-not[bool]$t13.conformance.all_second_reloads_passed-or
   -not[bool]$t13.conformance.all_target_upgrades_passed-or-not[bool]$t13.conformance.all_claims_exact_and_expiring-or
   -not[bool]$t13.conformance.f200_k2so_archive_custody_complete-or-not[bool]$t13.conformance.t12_historical_blocker_superseded-or
   [bool]$t13.conformance.public_support_claim_authorized-or[bool]$t13.conformance.release_transition_authority-or
   @($t13.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-t13-authority-evolution]'
}
$t14=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T14-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if(@($t14.evolved_bindings).Count-lt15-or@($t14.current_authorities).Count-lt25-or
   [string]$t14.turn-cne'T14'-or[string]$t14.status-cne'T14-DOCUMENTATION-CONTINUITY-PASSED-T15-NEXT-PRODUCTION-UNAUTHORIZED'-or
   [string]$t14.player_package_source_sha256-cne'F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'-or
   [int]$t14.conformance.document_count-lt425-or[int]$t14.conformance.source_of_truth_count-lt341-or
   [int]$t14.conformance.generated_projection_count-ne6-or[int]$t14.conformance.root_document_count-ne11-or
   [int]$t14.conformance.developer_document_count-ne13-or-not[bool]$t14.conformance.clean_extracted_preview_tutorial_passed-or
   -not[bool]$t14.conformance.player_executable_sources_unchanged-or-not[bool]$t14.conformance.one_emitter_preserved-or
   (@($t14.conformance.package_visible_delta)-join'|')-cne'README.md'-or[bool]$t14.conformance.release_transition_authority-or
   @($t14.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-t14-authority-evolution]'
}
$t15=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
$t15Machine=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Supply-Chain-Preservation-T15V1.json')|ConvertFrom-Json -Depth 100
$t15Acceptance=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T15-Independent-Machine-AcceptanceV1.json')|ConvertFrom-Json -Depth 100
if(@($t15.evolved_bindings).Count-lt20-or@($t15.current_authorities).Count-lt20-or
   [string]$t15.turn-cne'T15'-or[string]$t15.status-cne'T15-SUPPLY-CHAIN-PRESERVATION-PASSED-T16-T17-HUMAN-GATES-NEXT-PRODUCTION-UNAUTHORIZED'-or
   [string]$t15.player_package_source_sha256-cne'F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'-or
   [string]$t15Machine.status-cne'T15-MACHINE-WORK-COMPLETE-INDEPENDENT-AUDIT-PASSED-HUMAN-GATES-REMAIN'-or
   [string]$t15Acceptance.verdict-cne'ACCEPTED-T15-MACHINE-SCOPE'-or
   [bool]$t15Acceptance.reviewer.human_reviewer_claimed-or[bool]$t15Acceptance.reviewer.human_acceptance_inferred-or
   [bool]$t15Acceptance.release_authority-or
   $null-ne$t15.execution_transition.next_dependency_ready_turn-or
   (@($t15.execution_transition.human_blocked_turns)-join'|')-cne'T16|T17'-or
   @($t15.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-t15-authority-evolution]'
}
$t17=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T17-Machine-Preparation-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if([string]$t17.turn-cne'T17'-or
   [string]$t17.execution_state.programme_status-cne'T15-COMPLETE-T16-T17-HUMAN-BLOCKED-RELEASE-BLOCKED'-or
   $null-ne$t17.execution_state.completed_turn-or[string]$t17.execution_state.t17_status-cne'blocked-human'-or
   $null-ne$t17.execution_state.next_dependency_ready_turn-or
   [bool]$t17.human_gate.f210_decision_recorded-or[bool]$t17.human_gate.f200_decision_recorded-or
   [bool]$t17.human_gate.acceptance_inferred-or[bool]$t17.human_gate.decision_template_is_evidence-or
   -not[bool](@($t17.target_handoff|Where-Object target -ceq 'F200')[0].exact_engine_custody_ready)-or
   [bool](@($t17.target_handoff|Where-Object target -ceq 'F210')[0].exact_engine_custody_ready)-or
   [string]$t17.player_package_source_sha256-cne'F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'-or
   @($t17.package_visible_delta).Count-ne0-or
   @($t17.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-t17-machine-preparation-authority-evolution]'
}
$closure=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Final-Release-Closure-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if([string]$closure.kind-cne'MIR4FinalReleaseClosureAuthorityEvolutionReceiptV1'-or
   [string]$closure.status-cne'FINAL-RELEASE-AUTHORIZATION-IMPORTED-EXACT-PLAYTEST-SESSIONS-PREPARED-HUMAN-EVIDENCE-AND-CUSTODY-GATES-REMAIN'-or
   [string]$closure.player_package_source_sha256-cne'F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'-or
   -not[bool]$closure.readme.exact_candidate_copy_preserved-or-not[bool]$closure.readme.post_release_update_deferred-or
   [bool]$closure.portal_copy.live_portal_mutation_authorized-or
   [string]$closure.branch_topology.legacy_role-cne'previous-major-alias'-or
   @($closure.package_visible_delta).Count-ne0-or
   @($closure.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-final-release-closure-authority-evolution]'
}
$postReleaseBaseline=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Post-Release-Package-Baseline-Authority-Evolution-ReceiptV1.json')|ConvertFrom-Json -Depth 100
if([string]$postReleaseBaseline.kind-cne'MIR4PostReleasePackageBaselineAuthorityEvolutionReceiptV1'-or
   [string]$postReleaseBaseline.status-cne'POST-RELEASE-PACKAGE-PRESENTATION-BASELINE-RECORDED-NO-RELEASE-TRANSITION'-or
   [string]$postReleaseBaseline.player_package_source_sha256-cne$legacyRootPackageSourceSha256-or
   (@($postReleaseBaseline.package_visible_delta)-join'|')-cne'README.md'-or
   -not[bool]$postReleaseBaseline.invariants.player_executable_sources_unchanged-or
   @($postReleaseBaseline.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-post-release-package-baseline-authority-evolution]'
}
$automationCutover=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-Post-Release-Automation-Authority-CutoverV1.json')|ConvertFrom-Json -Depth 100
if([string]$automationCutover.kind-cne'MIR4PostReleaseAutomationAuthorityCutoverV1'-or
   [string]$automationCutover.status-cne'CURRENT-AUTOMATION-AUTHORITY-VISIBLE-HISTORICAL-PREFREEZE-BINDINGS-RETIRED'-or
   @($automationCutover.retired_bindings).Count-lt30-or
   -not[bool]$automationCutover.invariants.historical_mir_lock_immutable-or
   -not[bool]$automationCutover.invariants.visible_current_authority-or
   @($automationCutover.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-post-release-automation-authority-cutover]'
}
$branchOperatingModel=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-Branch-Operating-Model-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100
if([string]$branchOperatingModel.kind-cne'MIR4BranchOperatingModelAuthorityEvolutionV1'-or
   [string]$branchOperatingModel.status-cne'BRANCH-OPERATING-MODEL-APPLIED-NO-RELEASE-TRANSITION'-or
   @($branchOperatingModel.evolved_bindings).Count-ne3-or
   @($branchOperatingModel.current_authorities).Count-ne8-or
   [string]$branchOperatingModel.player_package_source_sha256-cne$legacyRootPackageSourceSha256-or
   -not[bool]$branchOperatingModel.invariants.main_latest_stable-or
   -not[bool]$branchOperatingModel.invariants.dev_next_release_integration-or
   [int]$branchOperatingModel.invariants.ordinary_bypass_actor_count-ne0-or
   @($branchOperatingModel.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-post-release-branch-operating-model]'
}
$patchLaneRehearsal=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-Patch-Lane-Rehearsal-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100
if([string]$patchLaneRehearsal.kind-cne'MIR4PatchLaneRehearsalAuthorityEvolutionV1'-or
   [string]$patchLaneRehearsal.status-cne'PATCH-LANE-REHEARSAL-PROVED-NO-RELEASE-TRANSITION'-or
   @($patchLaneRehearsal.evolved_bindings).Count-ne5-or
   @($patchLaneRehearsal.current_authorities).Count-lt21-or
   [string]$patchLaneRehearsal.player_package_source_sha256-cne$legacyRootPackageSourceSha256-or
   -not[bool]$patchLaneRehearsal.invariants.release_4_0_base_exact-or
   -not[bool]$patchLaneRehearsal.invariants.disposable_branch_removed-or
   -not[bool]$patchLaneRehearsal.invariants.remote_refs_unchanged-or
   @($patchLaneRehearsal.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-post-release-patch-lane-rehearsal]'
}
$m4103=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-03-Change-And-Release-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100
if([string]$m4103.kind-cne'MIR4M4103ChangeAndReleaseAuthorityEvolutionV1'-or
   [string]$m4103.status-cne'M41-03-CHANGE-AND-RELEASE-AUTHORITY-COMPLETE-NO-RELEASE-TRANSITION'-or
   @($m4103.evolved_bindings).Count-lt10-or
   @($m4103.current_authorities).Count-lt20-or
   [string]$m4103.player_package_source_sha256-cne$legacyRootPackageSourceSha256-or
   -not[bool]$m4103.invariants.six_views_from_one_inventory-or
   -not[bool]$m4103.invariants.historical_4_0_0_shadow_only-or
   -not[bool]$m4103.invariants.selective_target_filtering-or
   @($m4103.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-m41-03-change-and-release-authority]'
}
$characterization=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-05A-M42-00A-Repository-Characterization-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100
if([string]$characterization.kind-cne'MIR4M4105AM4200ARepositoryCharacterizationAuthorityEvolutionV1'-or
   [string]$characterization.status-cne'M41-05A-M42-00A-CHARACTERIZATION-COMPLETE-NO-PACKAGE-CUTOVER'-or
   @($characterization.evolved_bindings).Count-lt10-or
   @($characterization.current_authorities).Count-lt8-or
   [string]$characterization.player_package_source_sha256-cne$legacyRootPackageSourceSha256-or
   [string]$characterization.root_readme_sha256-cne$historicalRootReadmeSha256-or
   -not[bool]$characterization.invariants.deterministic_reports-or
   -not[bool]$characterization.invariants.all_bridges_retained-or
   @($characterization.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-m41-05a-m42-00a-characterization-authority]'
}
$truthReconciliation=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F0-Truth-Reconciliation-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$truthReconciliation.kind-cne'MIR4M41F0TruthReconciliationAuthorityEvolutionV1'-or
   [string]$truthReconciliation.status-cne'M41-F0-TRUTH-RECONCILED-NO-PACKAGE-CUTOVER'-or
   [string]$truthReconciliation.predecessor_receipt.path-cne'releases/migrations/MIR4-M41-05A-M42-00A-Repository-Characterization-Authority-EvolutionV1.json'-or
   [string]$truthReconciliation.predecessor_receipt.sha256-cne'1D5F3F67701DB9F1281B6FA376D031AD7513118259FACF25DEAC82DD66CD8FBF'-or
   @($truthReconciliation.evolved_bindings).Count-lt20-or
   @($truthReconciliation.current_authorities).Count-lt10-or
   [string]$truthReconciliation.player_package_source_sha256-cne$legacyRootPackageSourceSha256-or
   [string]$truthReconciliation.root_readme_sha256-cne$historicalRootReadmeSha256-or
   -not[bool]$truthReconciliation.invariants.live_programme_is_current-or
   -not[bool]$truthReconciliation.invariants.mutable_candidate_state_removed-or
   -not[bool]$truthReconciliation.invariants.portal_hash_contradiction_reconciled-or
   -not[bool]$truthReconciliation.invariants.package_source_unchanged-or
   @($truthReconciliation.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-m41-f0-truth-reconciliation-authority]'
}
$goldenBaseline=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F1-Golden-Four-Target-Baseline-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$goldenBaseline.kind-cne'MIR4M41F1GoldenFourTargetBaselineAuthorityEvolutionV1'-or
   [string]$goldenBaseline.status-cne'M41-F1-GOLDEN-FOUR-TARGET-ARCHIVE-BASELINE-COMPLETE-RUNTIME-REPLAY-PENDING'-or
   [string]$goldenBaseline.predecessor_receipt.path-cne'releases/migrations/MIR4-M41-F0-Truth-Reconciliation-Authority-EvolutionV1.json'-or
   [string]$goldenBaseline.predecessor_receipt.sha256-cne'0CED3F46BFEEBD48F96E169B4591DC6E3894EC8226C19CEE71D3269809A8568C'-or
   @($goldenBaseline.evolved_bindings).Count-lt8-or
   @($goldenBaseline.current_authorities).Count-lt6-or
   [int]$goldenBaseline.baseline_proof.target_count-ne4-or
   [int]$goldenBaseline.baseline_proof.common_files-ne89-or
   [int]$goldenBaseline.baseline_proof.modern_family_files-ne202-or
   [int]$goldenBaseline.baseline_proof.legacy_family_files-ne81-or
   @($goldenBaseline.baseline_proof.archives).Count-ne4-or
   [string]$goldenBaseline.player_package_source_sha256-cne$legacyRootPackageSourceSha256-or
   [string]$goldenBaseline.root_readme_sha256-cne$historicalRootReadmeSha256-or
   -not[bool]$goldenBaseline.invariants.four_archives_exact-or
   -not[bool]$goldenBaseline.invariants.reconstruction_byte_exact-or
   -not[bool]$goldenBaseline.invariants.runtime_replay_pending-or
   @($goldenBaseline.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-m41-f1-golden-four-target-baseline-authority]'
}
$shadowMaterializer=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F2A-Shadow-Target-Materializer-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$shadowMaterializer.kind-cne'MIR4M41F2AShadowTargetMaterializerAuthorityEvolutionV1'-or
   [string]$shadowMaterializer.status-cne'M41-F2A-SHADOW-TARGET-MATERIALIZER-PARITY-COMPLETE-NO-CUTOVER'-or
   [string]$shadowMaterializer.predecessor_receipt.path-cne'releases/migrations/MIR4-M41-F1-Golden-Four-Target-Baseline-Authority-EvolutionV1.json'-or
   [string]$shadowMaterializer.predecessor_receipt.sha256-cne'B6365CE4015BCFAF5A0CE4EBCBE2D4DE0062D6BE42EF53FA2BBF231C5D3FD49C'-or
   @($shadowMaterializer.evolved_bindings).Count-lt8-or
   @($shadowMaterializer.current_authorities).Count-lt6-or
   [int]$shadowMaterializer.materializer_proof.target_count-ne4-or
   [int]$shadowMaterializer.materializer_proof.materialization_count-ne8-or
   -not[bool]$shadowMaterializer.materializer_proof.all_exact_tree_parity-or
   -not[bool]$shadowMaterializer.materializer_proof.all_deterministic_archive_bytes-or
   @($shadowMaterializer.materializer_proof.content_identities).Count-ne4-or
   [string]$shadowMaterializer.player_package_source_sha256-cne$legacyRootPackageSourceSha256-or
   [string]$shadowMaterializer.root_readme_sha256-cne$historicalRootReadmeSha256-or
   -not[bool]$shadowMaterializer.invariants.four_target_tree_parity-or
   -not[bool]$shadowMaterializer.invariants.current_writer_unchanged-or
   -not[bool]$shadowMaterializer.invariants.runtime_replay_pending-or
   @($shadowMaterializer.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-m41-f2a-shadow-target-materializer-authority]'
}
$shadowSourceModel=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F2B-Shadow-Source-Model-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$shadowSourceModel.kind-cne'MIR4M41F2BShadowSourceModelAuthorityEvolutionV1'-or
   [string]$shadowSourceModel.status-cne'M41-F2B-SHADOW-SOURCE-MODEL-COMPLETE-NO-EDITABLE-SOURCE-NO-CUTOVER'-or
   [string]$shadowSourceModel.predecessor_receipt.path-cne'releases/migrations/MIR4-M41-F2A-Shadow-Target-Materializer-Authority-EvolutionV1.json'-or
   [string]$shadowSourceModel.predecessor_receipt.sha256-cne'84209EA8150D0E2C93164E6A2667F9FD4CD347B031171CE0F55901D483664A48'-or
   @($shadowSourceModel.evolved_bindings).Count-lt8-or
   @($shadowSourceModel.current_authorities).Count-lt6-or
   [int]$shadowSourceModel.source_model_proof.binding_count-ne406-or
   [int]$shadowSourceModel.source_model_proof.target_count-ne4-or
   [int]$shadowSourceModel.source_model_proof.omission_count-ne264-or
   [int]$shadowSourceModel.source_model_proof.classification_counts.'common-semantic-source'-ne81-or
   [int]$shadowSourceModel.source_model_proof.classification_counts.'common-asset-locale'-ne60-or
   [int]$shadowSourceModel.source_model_proof.classification_counts.'target-overlay'-ne217-or
   [int]$shadowSourceModel.source_model_proof.classification_counts.'target-replacement'-ne18-or
   [int]$shadowSourceModel.source_model_proof.classification_counts.'target-compatibility-shim'-ne11-or
   [string]$shadowSourceModel.player_package_source_sha256-cne$legacyRootPackageSourceSha256-or
   [string]$shadowSourceModel.root_readme_sha256-cne$historicalRootReadmeSha256-or
   -not[bool]$shadowSourceModel.invariants.all_paths_classified-or
   -not[bool]$shadowSourceModel.invariants.no_path_collision-or
   -not[bool]$shadowSourceModel.invariants.no_unowned_path-or
   -not[bool]$shadowSourceModel.invariants.declaration_order_independent-or
   -not[bool]$shadowSourceModel.invariants.no_target_policy_in_common_domain_code-or
   -not[bool]$shadowSourceModel.invariants.current_writer_unchanged-or
   -not[bool]$shadowSourceModel.invariants.no_editable_source_created-or
   -not[bool]$shadowSourceModel.invariants.runtime_replay_pending-or
   @($shadowSourceModel.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-m41-f2b-shadow-source-model-authority]'
}
$editableSource=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F2C-Editable-Source-Materializer-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$editableSource.kind-cne'MIR4M41F2CEditableSourceMaterializerAuthorityEvolutionV1'-or
   [string]$editableSource.status-cne'M41-F2C-EDITABLE-SOURCE-MATERIALIZER-PARITY-COMPLETE-NO-PACKAGE-CUTOVER'-or
   [string]$editableSource.predecessor_receipt.path-cne'releases/migrations/MIR4-M41-F2B-Shadow-Source-Model-Authority-EvolutionV1.json'-or
   [string]$editableSource.predecessor_receipt.sha256-cne'3E990A1951F665183254ED1F0D9132A55E050B8F402274C49AC8F85BBA6ACB15'-or
   @($editableSource.evolved_bindings).Count-lt8-or
   @($editableSource.current_authorities).Count-lt12-or
   [string]$editableSource.materializer_proof.source_manifest_sha256-cne'0A291BA7EC59857BB3663A69D30FBCD62BE864B2829D37506C294B0D5B62DE33'-or
   [string]$editableSource.materializer_proof.proof_record_sha256-cne'258E530AA8877D21D06762654FB5402CB6EC73B38AD3886C2B359C9526314AF4'-or
   [int]$editableSource.materializer_proof.binding_count-ne406-or
   [int]$editableSource.materializer_proof.source_file_count-ne406-or
   [int]$editableSource.materializer_proof.target_count-ne4-or
   @($editableSource.materializer_proof.target_compositions).Count-ne4-or
   @($editableSource.materializer_proof.target_compositions|Where-Object{-not[bool]$_.deterministic_archive_bytes-or-not[bool]$_.exact_golden_tree_parity}).Count-ne0-or
   [string]$editableSource.player_package_source_sha256-cne$legacyRootPackageSourceSha256-or
   [string]$editableSource.root_readme_sha256-cne$historicalRootReadmeSha256-or
   -not[bool]$editableSource.invariants.editable_shadow_source_established-or
   -not[bool]$editableSource.invariants.all_source_hashes_verified-or
   -not[bool]$editableSource.invariants.four_target_tree_parity-or
   -not[bool]$editableSource.invariants.four_target_deterministic_archives-or
   -not[bool]$editableSource.invariants.no_target_full_source_copy-or
   -not[bool]$editableSource.invariants.production_materializer_has_no_archive_input-or
   -not[bool]$editableSource.invariants.bootstrap_importer_retired-or
   -not[bool]$editableSource.invariants.current_writer_unchanged-or
   -not[bool]$editableSource.invariants.runtime_replay_pending-or
   @($editableSource.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-m41-f2c-editable-source-materializer-authority]'
}
$f2dHarness=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F2D-Runtime-Replay-Harness-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$f2dHarness.kind-cne'MIR4M41F2DRuntimeReplayHarnessAuthorityEvolutionV1'-or
   [string]$f2dHarness.status-cne'M41-F2D-HARNESS-READY-RUNTIME-REPLAY-PENDING-NO-CUTOVER'-or
   -not[bool]$f2dHarness.invariants.latest_experimental_2_1_selector-or
   -not[bool]$f2dHarness.invariants.exact_execution_identity_required-or
   -not[bool]$f2dHarness.invariants.failure_retained_until_classified-or
   [bool]$f2dHarness.invariants.runtime_replay_complete-or
   [string]$f2dHarness.first_attempt.phase-cne'pre-runtime-static-authority-check'-or
   @($f2dHarness.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-prefreeze-f2d-harness-authority]'}
$f210Replay=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F2D-F210-Runtime-Replay-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$f210Replay.kind-cne'MIR4M41F2DF210RuntimeReplayAuthorityEvolutionV1'-or
   [string]$f210Replay.status-cne'M41-F2D-210-PASSED-NO-CUTOVER'-or
   [string]$f210Replay.replay_proof.engine.version-cne'2.1.17'-or
   [int]$f210Replay.replay_proof.fresh_load.scenario_count-ne14-or
   [int]$f210Replay.replay_proof.upgrade.archetype_count-ne5-or
   -not[bool]$f210Replay.replay_proof.upgrade.first_reload-or-not[bool]$f210Replay.replay_proof.upgrade.second_reload-or
   -not[bool]$f210Replay.invariants.f210_runtime_replay_complete-or[bool]$f210Replay.invariants.f2d_four_target_complete-or
   -not[bool]$f210Replay.invariants.expanded_work_released_after_verified_custody-or
   @($f210Replay.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-prefreeze-f2d-f210-runtime-replay-authority]'}
$f200Replay=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F2D-F200-Runtime-Replay-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$f200Replay.kind-cne'MIR4M41F2DTargetRuntimeReplayAuthorityEvolutionV1'-or
   [string]$f200Replay.status-cne'M41-F2D-200-PASSED-NO-CUTOVER'-or
   [string]$f200Replay.predecessor_receipt.path-cne'releases/migrations/MIR4-M41-F2D-F210-Runtime-Replay-Authority-EvolutionV1.json'-or
   [string]$f200Replay.predecessor_receipt.sha256-cne'A690D41B0B37D4BAF78B615BB3042F51D97E3A9E552723DBCA3EE717943FBA8C'-or
   [string]$f200Replay.replay_proof.engine.version-cne'2.0.77'-or
   [string]$f200Replay.replay_proof.engine.file_version-cne'2.0.77.84539'-or
   [string]$f200Replay.replay_proof.engine.binary_sha256-cne'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B'-or
   [int]$f200Replay.replay_proof.fresh_load.scenario_count-ne1-or
   @($f200Replay.replay_proof.upgrade.archetypes).Count-ne1-or
   -not[bool]$f200Replay.replay_proof.upgrade.first_reload-or-not[bool]$f200Replay.replay_proof.upgrade.second_reload-or
   [string]$f200Replay.target_results.f210-cne'complete'-or[string]$f200Replay.target_results.f200-cne'complete'-or
   [string]$f200Replay.target_results.f110-cne'pending'-or[string]$f200Replay.target_results.f100-cne'pending'-or
   [string]$f200Replay.f2d_aggregate-cne'pending'-or[string]$f200Replay.f2e-cne'blocked'-or
   @($f200Replay.package_visible_delta).Count-ne0-or
   @($f200Replay.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-prefreeze-f2d-f200-runtime-replay-authority]'}
$f110Replay=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F2D-F110-Runtime-Replay-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$f110Replay.kind-cne'MIR4M41F2DTargetRuntimeReplayAuthorityEvolutionV1'-or
   [string]$f110Replay.status-cne'M41-F2D-110-PASSED-NO-CUTOVER'-or
   [string]$f110Replay.predecessor_receipt.path-cne'releases/migrations/MIR4-M41-F2D-F200-Runtime-Replay-Authority-EvolutionV1.json'-or
   [string]$f110Replay.predecessor_receipt.sha256-cne'079CCD4FC9B61A0D4CAB53F1DBE633D5FD142AC81441E95A3FF7D379E7086C9F'-or
   [string]$f110Replay.replay_proof.engine.version-cne'1.1.110'-or
   [string]$f110Replay.replay_proof.engine.file_version-cne'1.1.110.62357'-or
   [string]$f110Replay.replay_proof.engine.binary_sha256-cne'B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1'-or
   [string]$f110Replay.replay_proof.package.content_sha256-cne'B3DAA35E6E72741D8054C4EC22435CC8216CB6A5E2566D10CF9E3B934E3FF682'-or
   [int]$f110Replay.replay_proof.package.entry_count-ne174-or
   [int]$f110Replay.replay_proof.fresh_load.scenario_count-ne1-or
   @($f110Replay.replay_proof.upgrade.archetypes).Count-ne1-or
   -not[bool]$f110Replay.replay_proof.upgrade.first_reload-or-not[bool]$f110Replay.replay_proof.upgrade.second_reload-or
   [string]$f110Replay.target_results.f210-cne'complete'-or[string]$f110Replay.target_results.f200-cne'complete'-or
   [string]$f110Replay.target_results.f110-cne'complete'-or[string]$f110Replay.target_results.f100-cne'pending'-or
   [string]$f110Replay.f2d_aggregate-cne'pending'-or[string]$f110Replay.f2e-cne'blocked'-or
   @($f110Replay.package_visible_delta).Count-ne0-or
   @($f110Replay.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-prefreeze-f2d-f110-runtime-replay-authority]'}
$f100Replay=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F2D-F100-Runtime-Replay-Authority-EvolutionV1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$f100Replay.kind-cne'MIR4M41F2DTargetRuntimeReplayAuthorityEvolutionV1'-or
   [string]$f100Replay.status-cne'M41-F2D-100-PASSED-NO-CUTOVER'-or
   [string]$f100Replay.predecessor_receipt.path-cne'releases/migrations/MIR4-M41-F2D-F110-Runtime-Replay-Authority-EvolutionV1.json'-or
   [string]$f100Replay.predecessor_receipt.sha256-cne'28E355521A5921F4021F358E044B64895643152A6BD1D37721E382AF2580C31F'-or
   [string]$f100Replay.replay_proof.engine.version-cne'1.0.0'-or
   [string]$f100Replay.replay_proof.engine.file_version-cne'1.0.0.54889'-or
   [string]$f100Replay.replay_proof.engine.binary_sha256-cne'99F1CE207A04296EF7D797E4A98AA98DDE4F02EE653C9DF736AC33A676FD4F70'-or
   [string]$f100Replay.replay_proof.package.content_sha256-cne'1ABDA788DE4B287A48AB0B8787C8F7826256E4ECAB7085C3A6FDDD1E9DF145B2'-or
   [int]$f100Replay.replay_proof.package.entry_count-ne174-or
   [int]$f100Replay.replay_proof.fresh_load.scenario_count-ne1-or
   @($f100Replay.replay_proof.upgrade.archetypes).Count-ne1-or
   -not[bool]$f100Replay.replay_proof.upgrade.first_reload-or-not[bool]$f100Replay.replay_proof.upgrade.second_reload-or
   [string]$f100Replay.target_results.f210-cne'complete'-or[string]$f100Replay.target_results.f200-cne'complete'-or
   [string]$f100Replay.target_results.f110-cne'complete'-or[string]$f100Replay.target_results.f100-cne'complete'-or
   [string]$f100Replay.f2d_aggregate-cne'pending'-or[string]$f100Replay.f2e-cne'blocked'-or
   @($f100Replay.package_visible_delta).Count-ne0-or
   @($f100Replay.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-prefreeze-f2d-f100-runtime-replay-authority]'}
$f2dAggregate=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/migrations/MIR4-M41-F2D-Four-Target-Runtime-Replay-AggregateV1.json')|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$f2dAggregate.kind-cne'MIR4M41F2DFourTargetRuntimeReplayAggregateV1'-or
   [string]$f2dAggregate.status-cne'M41-F2D-FOUR-TARGET-RUNTIME-REPLAY-PASSED-NO-CUTOVER'-or
   [string]$f2dAggregate.predecessor_receipt.path-cne'releases/migrations/MIR4-M41-F2D-F100-Runtime-Replay-Authority-EvolutionV1.json'-or
   [string]$f2dAggregate.predecessor_receipt.sha256-cne'03F214C9F0ED630D497D450C64B0E1000299E6763D18EBE3D1F64CE81936CE54'-or
   (@($f2dAggregate.verification.targets.target)-join'|')-cne'f210|f200|f110|f100'-or
   [string]$f2dAggregate.verification.receipt_chain-cne'verified'-or
   [string]$f2dAggregate.verification.external_custody-cne'verified'-or
   [string]$f2dAggregate.verification.evidence_path_redaction-cne'verified'-or
   -not[bool]$f2dAggregate.invariants.old_writer_remains_authoritative-or
   @($f2dAggregate.package_visible_delta).Count-ne0-or
   @($f2dAggregate.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-prefreeze-f2d-four-target-aggregate-authority]'}
if(@($rulesets.rulesets).Count-ne3-or@($actions.actions).Count-ne6-or@($actions.repository_workflows).Count-ne22){throw '[mir4-prefreeze-control-count]'}

$planPath='.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json'
$plan=Get-Content -Raw -LiteralPath (Join-Path $repo $planPath)|ConvertFrom-Json -Depth 100
if([string]$plan.source_baseline.package_source_sha256-cne[string]$t13.player_package_source_sha256-or
   [string]$t14.player_package_source_sha256-cne'F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'){throw '[mir4-prefreeze-package-diff]'}
if([int]$plan.verification_plan.invalid-ne0-or[int]$plan.verification_plan.passed-ne30-or
   @($plan.targets|Where-Object{$_.release_role-cne'mandatory'-or$_.development_package.release_identity-or[string]::IsNullOrWhiteSpace([string]$_.engine.sha256)}).Count-ne0){
  throw '[mir4-prefreeze-zero-invalid-plan]'
}
$luna=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Hardening-Independent-Acceptance-LUNAV1.json')|ConvertFrom-Json -Depth 100
if([string]$luna.verdict-cne'ACCEPTED'-or@($luna.findings).Count-ne0-or
   [bool]$luna.package_visible-or[bool]$luna.source_freeze_authorized-or[bool]$luna.candidate_allocation_authorized-or
   [bool]$luna.production_release_authorized-or[bool]$luna.publication_authorized-or
   [string]$luna.review_input.player_package_source_sha256-cne[string]$plan.source_baseline.package_source_sha256){
  throw '[mir4-prefreeze-independent-acceptance]'
}

$expectedInputs=@('source_release_record','candidate_id','source_commit','source_tree','target_distribution_record_set','release_plan_digest','proof_root','seal_root')
$contract=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Release-Workflow-ContractV1.json')|ConvertFrom-Json -Depth 100
if(@($contract.phases).Count-ne10){throw '[mir4-prefreeze-workflow-count]'}
if(-not[bool]$contract.phase_engine.kernel_implemented-or-not[bool]$contract.phase_engine.event_sourcing_implemented-or
   -not[bool]$contract.phase_engine.idempotency_and_resume_tested-or[bool]$contract.phase_engine.production_capable-or
   [bool]$contract.phase_engine.production_authorized){throw '[mir4-prefreeze-phase-engine-boundary]'}
$maturity=@(Get-MIR4ReleaseWorkflowMaturity -RepoRoot $repo)
if(@($maturity|Where-Object{-not$_.workflow_registered-or-not$_.workflow_fail_closed}).Count-ne0-or
   @($maturity|Where-Object{-not$_.workflow_executor_implemented-or-not$_.workflow_dry_run_passed-or-not$_.workflow_production_rehearsal_passed}).Count-ne0-or
   @($maturity|Where-Object{$_.workflow_production_authorized}).Count-ne0){
  throw '[mir4-prefreeze-workflow-maturity]'
}
foreach($phase in @($contract.phases)){
  $workflow=Join-Path $repo ([string]$phase.workflow)
  $text=Get-Content -Raw -LiteralPath $workflow
  foreach($input in $expectedInputs){if($text-notmatch("(?m)^\s{6}"+[regex]::Escape($input)+":")){throw "[mir4-prefreeze-workflow-input] $($phase.id):$input"}}
  if($text-match'(?m)^\s{6}archive_sha256:'){throw "[mir4-prefreeze-ad-hoc-hash-input] $($phase.id)"}
}
$publisher=Get-Content -Raw -LiteralPath (Join-Path $repo '.github/workflows/mir4-target-publication.yml')
if($publisher-match'actions/checkout|Build-MIRPackage|mir4\s+platform\s+package'-or
   $publisher-notmatch'permissions:\s*\{contents:\s*read\}'-or
   $publisher-notmatch'seal-verifier/Test-MIR4PublicationAdmission\.ps1'-or
   $publisher-notmatch'publication_authorized'){throw '[mir4-prefreeze-publisher-capability]'}
Test-MIR4PublisherAdmissionBindings -WorkflowText $publisher|Out-Null
$publisherBindings=[ordered]@{source_release_record='MIR4_SOURCE_RELEASE_RECORD';candidate_id='MIR4_CANDIDATE_ID';source_commit='MIR4_SOURCE_COMMIT';source_tree='MIR4_SOURCE_TREE';target_distribution_record_set='MIR4_TARGET_RECORD_SET';release_plan_digest='MIR4_RELEASE_PLAN_DIGEST';proof_root='MIR4_PROOF_ROOT';seal_root='MIR4_SEAL_ROOT'}
foreach($binding in $publisherBindings.GetEnumerator()){
  $field=[string]$binding.Key
  $environmentVariable=[string]$binding.Value
  foreach($pattern in @(
    ('(?m)^\s+'+[regex]::Escape($environmentVariable)+':\s*\$\{\{\s*inputs\.'+[regex]::Escape($field)+'\s*\}\}\s*$')
    ('\[string\]\$admission\.'+[regex]::Escape($field)+'\s*-cne\s*\$env:'+[regex]::Escape($environmentVariable))
  )){
    $negative=([regex]::new($pattern)).Replace($publisher,'',1)
    try{
      Test-MIR4PublisherAdmissionBindings -WorkflowText $negative|Out-Null
      throw "[mir4-prefreeze-publisher-negative-not-detected] $field"
    }catch{
      if($_.Exception.Message-notmatch'^\[mir4-publisher-admission-binding-missing\]'){throw}
    }
  }
}
$previewWorkflow=Get-Content -Raw -LiteralPath (Join-Path $repo '.github/workflows/mir4-preview-assets.yml')
if($previewWorkflow-match'build/mir4/platform-preview/\*'-or
   @('mir4-api-sdk-v1-preview.zip','mir4-mep-v1-preview.zip','mir4-reference-extension-v1-preview.zip','mir4-inspector-v1-preview.zip','preview-assets.json'|Where-Object{$previewWorkflow-notmatch[regex]::Escape($_)}).Count-ne0){
  throw '[mir4-prefreeze-preview-upload-set]'
}

$head=(& git -C $repo rev-parse HEAD).Trim()
$tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$invocation=@{
  RepoRoot=$repo;SourceReleaseRecord='.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json'
  CandidateId='DEV-PREFREEZE-UNALLOCATED';SourceCommit=$head;SourceTree=$tree
  TargetDistributionRecordSet=$planPath;ReleasePlanDigest=[string]$plan.verification_plan.plan_sha256
  ProofRoot='development-proof-root';SealRoot='not-allocated'
}
$nonProduction=Test-MIR4ReleaseWorkflowInvocation @invocation -Phase independent-verification
if([string]$nonProduction.status-cne'validated'-or$nonProduction.mutation_performed){throw '[mir4-prefreeze-nonproduction-controller]'}
$blocked=$false
try{
  $invocation.CandidateId='M4RC1'
  Test-MIR4ReleaseWorkflowInvocation @invocation -Phase source-freeze|Out-Null
}catch{if($_.Exception.Message.StartsWith('[mir4-release-transition-blocked]')){$blocked=$true}else{throw}}
if(-not$blocked){throw '[mir4-prefreeze-source-freeze-accepted]'}

$toml=Get-Content -Raw -LiteralPath (Join-Path $repo 'mir.toml')
if($toml-notmatch'reference-extension-v1/extension\.json'-or$toml-match'--extension sdk/preview/mir4/reference-extension/extension\.json'){throw '[mir4-prefreeze-v1-default]'}

$cli=@(
  Get-Content -Raw -LiteralPath (Join-Path $repo 'tools/mir.ps1')
  Get-Content -Raw -LiteralPath (Join-Path $repo 'tools/mir/cli/Invoke-MIRCommandRouter.ps1')
)-join"`n"
foreach($command in @('release doctor','playtest prepare','playtest capture','playtest finalize','rulesets audit')){
  if($cli-notmatch[regex]::Escape($command)){throw "[mir4-prefreeze-cli] $command"}
}
$decisionRejected=$false
try{& (Join-Path $repo 'tools/mir.ps1') playtest finalize --session missing --reviewer test 2>$null|Out-Null}catch{if($_.Exception.Message-match'explicit --decision'){$decisionRejected=$true}else{throw}}
if(-not$decisionRejected){throw '[mir4-prefreeze-playtest-inferred-decision]'}

foreach($source in @('tools/lib/mir4/PreFreezeRelease.ps1','tools/lib/mir4/ReleasePhaseEngine.ps1','tools/commands/mir4/Invoke-MIR4PreFreeze.ps1','tools/commands/mir4/Invoke-MIR4ReleaseWorkflow.ps1')){
  $text=Get-Content -Raw -LiteralPath (Join-Path $repo $source)
  if($text-match'(?i)source_freeze_authorized\s*=\s*\$true|production_release_authorized\s*=\s*\$true|publication_authorized\s*=\s*\$true'){throw "[mir4-prefreeze-forbidden-authority] $source"}
}
Write-Host '[ok] MIR 4 T02-T15 completion and the T17 machine-preparation authority evolution passed; T16/T17 human decisions and every release transition remain blocked.'
