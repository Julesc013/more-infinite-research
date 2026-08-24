param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/ReleasePhaseEngine.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$contract=Get-MIR4ReleasePhaseContract -RepoRoot $repo
if([string]$contract.record.kind-cne'MIR4ReleasePhaseEngineContractV1'-or
   [bool]$contract.record.production_capable-or[bool]$contract.record.production_authorized-or
   [bool]$contract.record.release_transition_authorized-or@($contract.record.phases).Count-ne10){throw '[mir4-phase-engine-contract]'}
$portModes=@{};foreach($port in @($contract.record.ports)){$portModes[[string]$port.id]=[string]$port.mode}
if($portModes.git-cne'read-only'-or$portModes.build-cne'sandbox-only'-or$portModes.engine-cne'sandbox-only'-or
   $portModes.sign-cne'denied'-or$portModes.publish-cne'denied'){throw '[mir4-phase-engine-port-boundary]'}

$developmentPlanPath='.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json'
$developmentPlan=Get-Content -Raw -LiteralPath (Join-Path $repo $developmentPlanPath)|ConvertFrom-Json -Depth 100
$inputs=[pscustomobject][ordered]@{
  source_release_record='.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json'
  candidate_id='DEV-T02-UNALLOCATED';source_commit=(& git -C $repo rev-parse HEAD).Trim();source_tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  target_distribution_record_set=$developmentPlanPath;release_plan_digest=[string]$developmentPlan.verification_plan.plan_sha256
  proof_root='development-proof-root';seal_root='not-allocated'
}
$implementationHash=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToUpperInvariant()
$script:MIR4T02FailExecuteOnce=$false
$adapter=[pscustomobject][ordered]@{
  descriptor=[pscustomobject][ordered]@{
    id='mir4.test.non-production.v1';version=1;implementation_sha256=$implementationHash;production_capable=$false
    supported_operations=@('DryRun','Execute','Verify','Compensate');required_ports=@('git','build','engine')
  }
  invoke={
    param($Context)
    if($script:MIR4T02FailExecuteOnce-and[string]$Context.operation-ceq'Execute'){$script:MIR4T02FailExecuteOnce=$false;throw '[mir4-phase-engine-fixture-once]'}
    [pscustomobject][ordered]@{
      schema=1;kind='MIR4ReleasePhaseAdapterResultV1';operation=[string]$Context.operation;status='passed'
      idempotency_key=[string]$Context.idempotency_key;artifact_root=[string]$Context.artifact_root
      production_mutation_performed=$false;observed_port_modes=@($Context.ports|ForEach-Object{"$($_.id):$($_.mode)"})
    }
  }
}
function Invoke-T02([string]$Operation,[string]$Root,[string]$Phase='independent-verification',$UseAdapter=$adapter){
  Invoke-MIR4ReleasePhaseEngine -RepoRoot $repo -Operation $Operation -Phase $Phase -Inputs $inputs -Adapter $UseAdapter -OutputRoot $Root
}

$happyRoot='build/mir4/release-phase-engine/tests/t02-happy'
$planA=Invoke-T02 Plan $happyRoot
$planB=Invoke-T02 Plan $happyRoot
if([string]$planA.plan.phase_fingerprint-cne[string]$planB.plan.phase_fingerprint-or[bool]$planA.plan.production_authorized-or
   @($planB.events).Count-ne1-or[string]$planB.state-cne'planned'){throw '[mir4-phase-engine-plan-idempotency]'}
$dry=Invoke-T02 DryRun $happyRoot
$execute=Invoke-T02 Execute $happyRoot
$executeReuse=Invoke-T02 Execute $happyRoot
$verify=Invoke-T02 Verify $happyRoot
$receipt=Invoke-T02 Receipt $happyRoot
$receiptReuse=Invoke-T02 Receipt $happyRoot
$happyState=Get-MIR4ReleasePhaseAttemptState -AttemptRoot ([string]$planA.attempt_root)
if([string]$dry.state-cne'dry-run-passed'-or[string]$execute.state-cne'executed'-or-not[bool]$executeReuse.idempotent_reuse-or
   [string]$verify.state-cne'verified'-or[string]$receipt.final_state-cne'verified'-or
   [string]$receipt.receipt_sha256-cne[string]$receiptReuse.receipt_sha256-or[bool]$receipt.production_authorized-or
   [string]$happyState.state-cne'complete'-or@($happyState.events).Count-ne5){throw '[mir4-phase-engine-happy-path]'}
$operationKeys=@($happyState.events|ForEach-Object{"$($_.operation):$($_.idempotency_key)"})
if(@($operationKeys|Sort-Object -Unique).Count-ne5-or@($happyState.events|Where-Object{[string]$_.previous_event_sha256-cne'GENESIS'}).Count-ne4){throw '[mir4-phase-engine-event-chain-shape]'}

$compensateRoot='build/mir4/release-phase-engine/tests/t02-compensate'
$null=Invoke-T02 Plan $compensateRoot 'restore-drill';$null=Invoke-T02 DryRun $compensateRoot 'restore-drill';$null=Invoke-T02 Execute $compensateRoot 'restore-drill'
$compensated=Invoke-T02 Compensate $compensateRoot 'restore-drill';$compensationReceipt=Invoke-T02 Receipt $compensateRoot 'restore-drill'
if([string]$compensated.state-cne'compensated'-or[string]$compensationReceipt.final_state-cne'compensated'){throw '[mir4-phase-engine-compensation]'}

$resumeRoot='build/mir4/release-phase-engine/tests/t02-resume'
$null=Invoke-T02 Plan $resumeRoot
$resumedDry=Invoke-T02 Resume $resumeRoot
$script:MIR4T02FailExecuteOnce=$true;$failed=$false
try{$null=Invoke-T02 Resume $resumeRoot}catch{if($_.Exception.Message-ceq'[mir4-phase-engine-fixture-once]'){$failed=$true}else{throw}}
if(-not$failed){throw '[mir4-phase-engine-failure-not-captured]'}
$failedState=Get-MIR4ReleasePhaseAttemptState -AttemptRoot ([string]$resumedDry.attempt_root)
if([string]$failedState.state-cne'dry-run-passed'-or[string]$failedState.last_failed_operation-cne'Execute'-or[string]$failedState.events[-1].status-cne'failed'){throw '[mir4-phase-engine-failure-state]'}
$resumedExecute=Invoke-T02 Resume $resumeRoot;$resumedVerify=Invoke-T02 Resume $resumeRoot;$resumedReceipt=Invoke-T02 Resume $resumeRoot
if([string]$resumedExecute.state-cne'executed'-or[string]$resumedVerify.state-cne'verified'-or[string]$resumedReceipt.kind-cne'MIR4ReleasePhaseReceiptV1'){throw '[mir4-phase-engine-resume]'}
$resumeEvents=@((Get-MIR4ReleasePhaseAttemptState -AttemptRoot ([string]$resumedDry.attempt_root)).events)
$executeKeys=@($resumeEvents|Where-Object operation -eq Execute|Select-Object -ExpandProperty idempotency_key -Unique)
if($executeKeys.Count-ne1){throw '[mir4-phase-engine-retry-idempotency-key]'}

$tamperPlanRoot='build/mir4/release-phase-engine/tests/t02-plan-tamper'
$tamperPlan=Invoke-T02 Plan $tamperPlanRoot
$tamperPlanPath=Join-Path ([string]$tamperPlan.attempt_root) 'plan.json'
$tampered=Get-Content -Raw -LiteralPath $tamperPlanPath|ConvertFrom-Json -Depth 100;$tampered.identity.candidate_id='DIVERGED'
[IO.File]::WriteAllText($tamperPlanPath,($tampered|ConvertTo-Json -Depth 100 -Compress)+"`n",[Text.UTF8Encoding]::new($false))
$divergenceRejected=$false;try{$null=Invoke-T02 Plan $tamperPlanRoot}catch{if($_.Exception.Message-ceq'[mir4-phase-engine-fingerprint-divergence]'){$divergenceRejected=$true}else{throw}}
if(-not$divergenceRejected){throw '[mir4-phase-engine-divergence-accepted]'}

$tamperEventRoot='build/mir4/release-phase-engine/tests/t02-event-tamper'
$tamperEvent=Invoke-T02 Plan $tamperEventRoot;$null=Invoke-T02 DryRun $tamperEventRoot
$eventPath=Get-ChildItem -LiteralPath (Join-Path ([string]$tamperEvent.attempt_root) 'events') -Filter '*.json'|Sort-Object Name|Select-Object -Last 1
$event=Get-Content -Raw -LiteralPath $eventPath.FullName|ConvertFrom-Json -Depth 100;$event.result.status='changed'
[IO.File]::WriteAllText($eventPath.FullName,($event|ConvertTo-Json -Depth 100 -Compress)+"`n",[Text.UTF8Encoding]::new($false))
$eventRejected=$false;try{$null=Get-MIR4ReleasePhaseAttemptState -AttemptRoot ([string]$tamperEvent.attempt_root)}catch{if($_.Exception.Message.StartsWith('[mir4-phase-engine-event-chain]')){$eventRejected=$true}else{throw}}
if(-not$eventRejected){throw '[mir4-phase-engine-event-tamper-accepted]'}

$productionAdapter=[pscustomobject][ordered]@{descriptor=[pscustomobject][ordered]@{id='mir4.test.production.v1';version=1;implementation_sha256=$implementationHash;production_capable=$true;supported_operations=@('DryRun');required_ports=@('git')};invoke=$adapter.invoke}
$productionRejected=$false;try{$null=Invoke-T02 Plan 'build/mir4/release-phase-engine/tests/t02-production' 'promotion' $productionAdapter}catch{if($_.Exception.Message-ceq'[mir4-phase-engine-adapter-boundary]'){$productionRejected=$true}else{throw}}
if(-not$productionRejected){throw '[mir4-phase-engine-production-adapter-accepted]'}
$signAdapter=[pscustomobject][ordered]@{descriptor=[pscustomobject][ordered]@{id='mir4.test.sign.v1';version=1;implementation_sha256=$implementationHash;production_capable=$false;supported_operations=@('DryRun');required_ports=@('sign')};invoke=$adapter.invoke}
$signRejected=$false;try{$null=Invoke-T02 Plan 'build/mir4/release-phase-engine/tests/t02-sign' 'release-seal' $signAdapter}catch{if($_.Exception.Message.StartsWith('[mir4-phase-engine-adapter-port]')){$signRejected=$true}else{throw}}
if(-not$signRejected){throw '[mir4-phase-engine-sign-port-accepted]'}
$boundaryRejected=$false;try{$null=Invoke-T02 Plan 'build/mir4/not-release-phase-engine' 'independent-verification'}catch{if($_.Exception.Message.StartsWith('[mir4-phase-engine-output-boundary]')){$boundaryRejected=$true}else{throw}}
if(-not$boundaryRejected){throw '[mir4-phase-engine-output-escape-accepted]'}

if((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-cne$packageBefore){throw '[mir4-phase-engine-package-mutation]'}
Write-Host '[ok] MIR 4 release phase engine identity, event chain, idempotency, resume, compensation, receipts, ports, and non-production boundary passed.'
