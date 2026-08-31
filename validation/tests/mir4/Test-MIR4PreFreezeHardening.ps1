param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

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
   [string]$postReleaseBaseline.player_package_source_sha256-cne(Get-MIRPackageSourceFingerprint -RepoRoot $repo)-or
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
   [string]$branchOperatingModel.player_package_source_sha256-cne(Get-MIRPackageSourceFingerprint -RepoRoot $repo)-or
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
   [string]$patchLaneRehearsal.player_package_source_sha256-cne(Get-MIRPackageSourceFingerprint -RepoRoot $repo)-or
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
   [string]$m4103.player_package_source_sha256-cne(Get-MIRPackageSourceFingerprint -RepoRoot $repo)-or
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
   [string]$characterization.player_package_source_sha256-cne(Get-MIRPackageSourceFingerprint -RepoRoot $repo)-or
   (Get-MIRFileContentSha256 -Path (Join-Path $repo 'README.md') -RelativePath 'README.md')-cne[string]$characterization.root_readme_sha256-or
   -not[bool]$characterization.invariants.deterministic_reports-or
   -not[bool]$characterization.invariants.all_bridges_retained-or
   @($characterization.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-prefreeze-m41-05a-m42-00a-characterization-authority]'
}
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

$cli=Get-Content -Raw -LiteralPath (Join-Path $repo 'tools/mir.ps1')
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
