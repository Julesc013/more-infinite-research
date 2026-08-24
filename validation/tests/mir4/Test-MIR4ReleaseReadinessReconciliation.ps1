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
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
$packageFiles=@(Get-MIRPackageSourceFiles -RepoRoot $RepoRoot)
foreach($path in @('.mir/releases/waves/mir4-r0/MIR4-Release-Readiness-ReconciliationV1.json','spec/schemas/mir4-release-readiness-reconciliation-v1.schema.json','validation/tests/mir4/Test-MIR4ReleaseReadinessReconciliation.ps1')){
  if($path-in$packageFiles){throw "[mir4-readiness-package-visible] $path"}
}
Write-Host '[ok] MIR 4 release-readiness reconciliation is typed, append-only, scoped, and release-blocked.'
