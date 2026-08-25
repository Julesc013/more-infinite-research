param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)

$ErrorActionPreference='Stop'
$recordPath=Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Release-Readiness-ReconciliationV1.json'
$schemaPath=Join-Path $RepoRoot 'spec/schemas/mir4-release-readiness-reconciliation-v1.schema.json'
$json=Get-Content -Raw -LiteralPath $recordPath
if(-not($json|Test-Json -SchemaFile $schemaPath)){throw '[mir4-readiness-reconciliation-schema]'}
$record=$json|ConvertFrom-Json -Depth 100
if([string]$record.source_baseline.commit-cne'3a58d3753bedcaf1107b76655117e0ff84dac960'-or[int]$record.source_baseline.integration_pr-ne151){throw '[mir4-readiness-reconciliation-baseline]'}
if(@($record.queue_reconciliation).Count-ne7){throw '[mir4-readiness-reconciliation-queue]'}
if(@($record.blockers|Where-Object{$_.scope-eq'stable-player-release'-and$_.state-eq'OPEN'}).Count-lt3){throw '[mir4-readiness-release-blockers]'}
if(@($record.blockers|Where-Object{$_.scope-eq'component-graduation'-and$_.id-eq'independent-mep-production-consumer'}).Count-ne1){throw '[mir4-readiness-component-scope]'}
if($record.transition_gate.source_freeze-or$record.transition_gate.candidate_allocation-or$record.transition_gate.promotion_to_main-or$record.transition_gate.tagging-or$record.transition_gate.publication){throw '[mir4-readiness-transition-authority]'}
if(@($record.planning_inputs|Where-Object authority -ne 'planning-input-user-request-is-execution-authority').Count){throw '[mir4-readiness-input-authority]'}

$currentPath=Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json'
$currentSchema=Join-Path $RepoRoot 'spec/schemas/mir4-pre-freeze-execution-programme-v1.schema.json'
$currentJson=Get-Content -Raw -LiteralPath $currentPath
if(-not($currentJson|Test-Json -SchemaFile $currentSchema)){throw '[mir4-current-execution-schema]'}
$current=$currentJson|ConvertFrom-Json -Depth 100
if([string]$current.source_baseline.commit-cne'8e269b6379ef3958f92fb747cef389f0f098feb6'-or
   [string]$current.source_baseline.tree-cne'dc3c7415c725bf10c0908d35ed93e530a49a77b1'-or
   [string]$current.status-cne'T07-COMPLETE-T08-T09-T10-READY-RELEASE-BLOCKED'-or
   [string]$current.next_dependency_ready_turn-cne'T08'){
  throw '[mir4-current-execution-baseline]'
}
if(@($current.planning_inputs|Where-Object classification -ne 'planning-evidence-only-not-execution-authority').Count-ne0){
  throw '[mir4-current-execution-planning-boundary]'
}
$expectedMaturity=@('workflow_registered','workflow_fail_closed','workflow_executor_implemented','workflow_dry_run_passed','workflow_production_rehearsal_passed','workflow_production_authorized')
if((@($current.workflow_maturity_vocabulary)-join'|')-cne($expectedMaturity-join'|')){throw '[mir4-current-execution-maturity-vocabulary]'}
if(@($current.blockers|Where-Object{$_.id-eq'release-workflow-executor-maturity'-and$_.state-eq'SATISFIED'-and$_.scope-eq'stable-player-release'}).Count-ne1-or
   @($current.blockers|Where-Object{$_.id-eq'protected-signing-and-recovery'-and$_.state-eq'OPEN'}).Count-ne1-or
   @($current.blockers|Where-Object{$_.id-in@('maintainer-playtest-f210','maintainer-playtest-f200')-and$_.state-eq'OPEN'}).Count-ne2){
  throw '[mir4-current-execution-release-blockers]'
}
if(@($current.turns).Count-ne22-or
   @($current.turns|Where-Object{$_.id-in@('T00','T01','T02','T03','T04','T05','T06','T07')-and$_.state-eq'completed'}).Count-ne8-or
   @($current.turns|Where-Object{$_.id-in@('T08','T09','T10')-and$_.state-eq'ready'}).Count-ne3-or
   @($current.mir3_residuals|Where-Object{$_.id-in@('github-pr-149','github-pr-146')-and$_.release_blocking}).Count-ne2){
  throw '[mir4-current-execution-queue]'
}
if(@($current.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){throw '[mir4-current-execution-transition-authority]'}

$dashboardJson=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/dashboard.json')
$queueJson=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/queue.json')
$statusSchema=Join-Path $RepoRoot 'spec/schemas/mir4-r0-status.schema.json'
if(-not($dashboardJson|Test-Json -SchemaFile $statusSchema)-or-not($queueJson|Test-Json -SchemaFile $statusSchema)){throw '[mir4-current-execution-generated-schema]'}
$dashboard=$dashboardJson|ConvertFrom-Json -Depth 100
$queue=$queueJson|ConvertFrom-Json -Depth 100
if(@($dashboard.generated_from).Count-ne1-or[string]$dashboard.generated_from[0].path-cne'.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json'-or
   [string]$dashboard.payload.next_executable_task-cne'T07'-or@($queue.payload.tasks).Count-ne22-or
   @($queue.payload.tasks|Where-Object{$_.id-eq'T07'-and$_.state-eq'ready'}).Count-ne1-or
   @($queue.payload.tasks|Where-Object{$_.id-eq'T06'-and$_.state-eq'completed'}).Count-ne1){
  throw '[mir4-current-execution-generated-view]'
}

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
$packageFiles=@(Get-MIRPackageSourceFiles -RepoRoot $RepoRoot)
foreach($path in @('.mir/releases/waves/mir4-r0/MIR4-Release-Readiness-ReconciliationV1.json','.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json','.mir/releases/waves/mir4-r0/dashboard.json','.mir/releases/waves/mir4-r0/queue.json','spec/schemas/mir4-release-readiness-reconciliation-v1.schema.json','spec/schemas/mir4-pre-freeze-execution-programme-v1.schema.json','validation/tests/mir4/Test-MIR4ReleaseReadinessReconciliation.ps1')){
  if($path-in$packageFiles){throw "[mir4-readiness-package-visible] $path"}
}
Write-Host '[ok] MIR 4 release-readiness reconciliation is typed, current, generated, scoped, and release-blocked.'
