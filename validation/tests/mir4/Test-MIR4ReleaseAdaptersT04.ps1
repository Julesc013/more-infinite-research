param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/mir4/ReleasePhaseEngine.ps1')
. (Join-Path $repo 'tools/lib/mir4/ReleaseAdapters.ps1')

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$developmentPlanPath='.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json'
$developmentPlan=Get-Content -Raw -LiteralPath (Join-Path $repo $developmentPlanPath)|ConvertFrom-Json -Depth 100
$inputs=[pscustomobject][ordered]@{
  source_release_record='.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json'
  candidate_id='DEV-T04-UNALLOCATED';source_commit=(& git -C $repo rev-parse HEAD).Trim();source_tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  target_distribution_record_set=$developmentPlanPath;release_plan_digest=[string]$developmentPlan.verification_plan.plan_sha256
  proof_root='build/mir4/release-phase-engine/tests/t04-proof';seal_root='not-allocated'
}
$testRunRoot='build/mir4/release-phase-engine/tests/t04-'+[guid]::NewGuid().ToString('N')

function Invoke-T04Phase([string]$Operation,[string]$Phase,[string]$Root,$Adapter,$UseInputs=$inputs){
  Invoke-MIR4ReleasePhaseEngine -RepoRoot $repo -Operation $Operation -Phase $Phase -Inputs $UseInputs -Adapter $Adapter -OutputRoot $Root
}
function New-T04QualificationReceipt($Expected,$Context,[string]$Target,[string]$Evidence){
  $record=[pscustomobject][ordered]@{
    schema=1;kind='MIR4TargetQualificationWorkerReceiptV1';producer_id='t04-exact-worker'
    source_commit=[string]$Context.plan.identity.source_commit;source_tree=[string]$Context.plan.identity.source_tree
    release_plan_digest=[string]$Context.plan.identity.release_plan_digest;target=$Target
    distribution_version=[string]$Expected.distribution_version;package=$Expected.package;engine=$Expected.engine
    evidence_sha256=$Evidence;status='passed';release_identity=$false;publication_authorized=$false;record_sha256=''
  }
  $record.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $record -HashProperty record_sha256
  return $record
}
function New-T04IndependentReceipt($Expected,$Context,[string]$Target,[string]$Evidence){
  $record=[pscustomobject][ordered]@{
    schema=1;kind='MIR4IndependentVerificationReceiptV1';producer_id='t04-independent-verifier';independent=$true
    source_commit=[string]$Context.plan.identity.source_commit;source_tree=[string]$Context.plan.identity.source_tree
    release_plan_digest=[string]$Context.plan.identity.release_plan_digest;target=$Target
    distribution_version=[string]$Expected.distribution_version;package_sha256=[string]$Expected.package.sha256
    engine_sha256=[string]$Expected.engine.sha256;evidence_sha256=$Evidence;status='passed'
    release_identity=$false;publication_authorized=$false;record_sha256=''
  }
  $record.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $record -HashProperty record_sha256
  return $record
}
$qualificationReceiptFactory=${function:New-T04QualificationReceipt}
$independentReceiptFactory=${function:New-T04IndependentReceipt}

$schemas=@(
  'spec/schemas/mir4-release-target-qualification-result-v1.schema.json',
  'spec/schemas/mir4-target-qualification-worker-receipt-v1.schema.json',
  'spec/schemas/mir4-release-preview-assets-result-v1.schema.json',
  'spec/schemas/mir4-release-independent-verification-result-v1.schema.json',
  'spec/schemas/mir4-independent-verification-receipt-v1.schema.json'
)
foreach($schema in $schemas){
  try{Get-Content -Raw -LiteralPath (Join-Path $repo $schema)|ConvertFrom-Json -Depth 100|Out-Null}catch{throw "[mir4-t04-schema-load] $schema"}
}

$qualificationCalls=@{}
$qualificationProvider={
  param([string]$FixtureRepo,[string]$Target,$Expected,$Context)
  $qualificationCalls[$Target]=1+[int]$qualificationCalls[$Target]
  if($Target-ceq'F210'-and[int]$qualificationCalls[$Target]-eq1){throw '[mir4-t04-fixture-worker-interruption] F210'}
  &$qualificationReceiptFactory -Expected $Expected -Context $Context -Target $Target -Evidence $(if($Target-ceq'F210'){'1'*64}else{'2'*64})
}.GetNewClosure()
$qualificationAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase target-qualification -QualificationWorkerProvider $qualificationProvider -QualificationWorkerProviderIdentity ('3'*64)
if([bool]$qualificationAdapter.descriptor.production_capable-or[string]$qualificationAdapter.descriptor.result_schema-cne$schemas[0]){throw '[mir4-t04-qualification-descriptor]'}
$qualificationRoot=Join-Path $testRunRoot 'qualification-resume'
$qualificationPlan=Invoke-T04Phase Plan target-qualification $qualificationRoot $qualificationAdapter
$qualificationDry=Invoke-T04Phase DryRun target-qualification $qualificationRoot $qualificationAdapter
$interrupted=$false
try{$null=Invoke-T04Phase Execute target-qualification $qualificationRoot $qualificationAdapter}catch{if($_.Exception.Message-ceq'[mir4-t04-fixture-worker-interruption] F210'){$interrupted=$true}else{throw}}
$partialPath=Join-Path ([string]$qualificationPlan.attempt_root) 'artifacts/execute/worker-receipts/f200.json'
if(-not$interrupted-or-not(Test-Path -LiteralPath $partialPath -PathType Leaf)){throw '[mir4-t04-qualification-partial-not-preserved]'}
$qualificationResume=Invoke-T04Phase Resume target-qualification $qualificationRoot $qualificationAdapter
$qualificationVerify=Invoke-T04Phase Verify target-qualification $qualificationRoot $qualificationAdapter
$qualificationReceipt=Invoke-T04Phase Receipt target-qualification $qualificationRoot $qualificationAdapter
$qualificationState=Get-MIR4ReleasePhaseAttemptState -AttemptRoot ([string]$qualificationPlan.attempt_root)
$qualificationExecution=@($qualificationState.events|Where-Object{[string]$_.operation-ceq'Execute'-and[string]$_.status-ceq'passed'}|Select-Object -Last 1)[0]
if([string]$qualificationDry.state-cne'dry-run-passed'-or[string]$qualificationResume.state-cne'executed'-or
   [string]$qualificationVerify.state-cne'verified'-or[string]$qualificationReceipt.final_state-cne'verified'-or
   [int]$qualificationExecution.result.worker_receipts_adopted-ne1-or@($qualificationExecution.result.targets).Count-ne2-or
   @($qualificationExecution.result.targets|Where-Object{$_.release_identity-or$_.publication_authorized}).Count-ne0){
  throw '[mir4-t04-qualification-resume]'
}

$wrongProvider={
  param([string]$FixtureRepo,[string]$Target,$Expected,$Context)
  $receipt=&$qualificationReceiptFactory -Expected $Expected -Context $Context -Target $Target -Evidence ('4'*64)
  $receipt.package.sha256='F'*64
  $receipt.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $receipt -HashProperty record_sha256
  return $receipt
}.GetNewClosure()
$wrongAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase target-qualification -QualificationWorkerProvider $wrongProvider -QualificationWorkerProviderIdentity ('5'*64)
$wrongInputs=$inputs.PSObject.Copy();$wrongInputs.candidate_id='DEV-T04-WRONG-PACKAGE'
$wrongRoot=Join-Path $testRunRoot 'qualification-wrong'
$null=Invoke-T04Phase Plan target-qualification $wrongRoot $wrongAdapter $wrongInputs
$null=Invoke-T04Phase DryRun target-qualification $wrongRoot $wrongAdapter $wrongInputs
$wrongRejected=$false
try{$null=Invoke-T04Phase Execute target-qualification $wrongRoot $wrongAdapter $wrongInputs}catch{if($_.Exception.Message-ceq'[mir4-target-qualification-worker-mismatch] F200'){$wrongRejected=$true}else{throw}}
if(-not$wrongRejected){throw '[mir4-t04-wrong-package-accepted]'}

$previewAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase preview-assets
if([bool]$previewAdapter.descriptor.production_capable-or[string]$previewAdapter.descriptor.result_schema-cne$schemas[2]){throw '[mir4-t04-preview-descriptor]'}
$previewHashes=@()
foreach($suffix in @('A','B')){
  $previewInputs=$inputs.PSObject.Copy();$previewInputs.candidate_id="DEV-T04-PREVIEW-$suffix"
  $previewRoot=Join-Path $testRunRoot ("preview-"+$suffix.ToLowerInvariant())
  $previewPlan=Invoke-T04Phase Plan preview-assets $previewRoot $previewAdapter $previewInputs
  $null=Invoke-T04Phase DryRun preview-assets $previewRoot $previewAdapter $previewInputs
  $null=Invoke-T04Phase Execute preview-assets $previewRoot $previewAdapter $previewInputs
  $null=Invoke-T04Phase Verify preview-assets $previewRoot $previewAdapter $previewInputs
  $previewReceipt=Invoke-T04Phase Receipt preview-assets $previewRoot $previewAdapter $previewInputs
  $previewState=Get-MIR4ReleasePhaseAttemptState -AttemptRoot ([string]$previewPlan.attempt_root)
  $previewExecution=@($previewState.events|Where-Object{[string]$_.operation-ceq'Execute'-and[string]$_.status-ceq'passed'}|Select-Object -Last 1)[0]
  if([string]$previewReceipt.final_state-cne'verified'-or@($previewExecution.result.assets).Count-ne4-or
     [bool]$previewExecution.result.release_transition_performed){throw "[mir4-t04-preview-execution] $suffix"}
  $previewHashes += ,@($previewExecution.result.assets|Sort-Object name|ForEach-Object{"$($_.name):$($_.sha256)"})
}
if((@($previewHashes[0])-join'|')-cne(@($previewHashes[1])-join'|')){throw '[mir4-t04-preview-nondeterministic]'}

$independentCalls=@{}
$independentProvider={
  param([string]$FixtureRepo,[string]$Target,$Expected,$Context)
  $independentCalls[$Target]=1+[int]$independentCalls[$Target]
  if($Target-ceq'F210'-and[int]$independentCalls[$Target]-eq1){throw '[mir4-t04-fixture-independent-interruption] F210'}
  &$independentReceiptFactory -Expected $Expected -Context $Context -Target $Target -Evidence $(if($Target-ceq'F210'){'6'*64}else{'7'*64})
}.GetNewClosure()
$independentAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase independent-verification -IndependentReceiptProvider $independentProvider -IndependentReceiptProviderIdentity ('8'*64)
if([bool]$independentAdapter.descriptor.production_capable-or[string]$independentAdapter.descriptor.result_schema-cne$schemas[3]){throw '[mir4-t04-independent-descriptor]'}
$independentInputs=$inputs.PSObject.Copy();$independentInputs.candidate_id='DEV-T04-INDEPENDENT'
$independentRoot=Join-Path $testRunRoot 'independent-resume'
$independentPlan=Invoke-T04Phase Plan independent-verification $independentRoot $independentAdapter $independentInputs
$null=Invoke-T04Phase DryRun independent-verification $independentRoot $independentAdapter $independentInputs
$independentInterrupted=$false
try{$null=Invoke-T04Phase Execute independent-verification $independentRoot $independentAdapter $independentInputs}catch{if($_.Exception.Message-ceq'[mir4-t04-fixture-independent-interruption] F210'){$independentInterrupted=$true}else{throw}}
$independentPartial=Join-Path ([string]$independentPlan.attempt_root) 'artifacts/execute/independent-receipts/f200.json'
if(-not$independentInterrupted-or-not(Test-Path -LiteralPath $independentPartial -PathType Leaf)){throw '[mir4-t04-independent-partial-not-preserved]'}
$independentResume=Invoke-T04Phase Resume independent-verification $independentRoot $independentAdapter $independentInputs
$independentVerify=Invoke-T04Phase Verify independent-verification $independentRoot $independentAdapter $independentInputs
$independentReceipt=Invoke-T04Phase Receipt independent-verification $independentRoot $independentAdapter $independentInputs
$independentState=Get-MIR4ReleasePhaseAttemptState -AttemptRoot ([string]$independentPlan.attempt_root)
$independentExecution=@($independentState.events|Where-Object{[string]$_.operation-ceq'Execute'-and[string]$_.status-ceq'passed'}|Select-Object -Last 1)[0]
if([string]$independentResume.state-cne'executed'-or[string]$independentVerify.state-cne'verified'-or
   [string]$independentReceipt.final_state-cne'verified'-or[int]$independentExecution.result.independent_receipts_adopted-ne1-or
   @($independentExecution.result.targets|Where-Object{-not$_.independent-or$_.release_identity-or$_.publication_authorized}).Count-ne0){
  throw '[mir4-t04-independent-resume]'
}

$wrongIndependentProvider={
  param([string]$FixtureRepo,[string]$Target,$Expected,$Context)
  $receipt=&$independentReceiptFactory -Expected $Expected -Context $Context -Target $Target -Evidence ('9'*64)
  $receipt.engine_sha256='A'*64
  $receipt.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $receipt -HashProperty record_sha256
  return $receipt
}.GetNewClosure()
$wrongIndependentAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase independent-verification -IndependentReceiptProvider $wrongIndependentProvider -IndependentReceiptProviderIdentity ('B'*64)
$wrongIndependentInputs=$inputs.PSObject.Copy();$wrongIndependentInputs.candidate_id='DEV-T04-WRONG-ENGINE'
$wrongIndependentRoot=Join-Path $testRunRoot 'independent-wrong'
$null=Invoke-T04Phase Plan independent-verification $wrongIndependentRoot $wrongIndependentAdapter $wrongIndependentInputs
$null=Invoke-T04Phase DryRun independent-verification $wrongIndependentRoot $wrongIndependentAdapter $wrongIndependentInputs
$wrongIndependentRejected=$false
try{$null=Invoke-T04Phase Execute independent-verification $wrongIndependentRoot $wrongIndependentAdapter $wrongIndependentInputs}catch{if($_.Exception.Message-ceq'[mir4-independent-verification-receipt-mismatch] F200'){$wrongIndependentRejected=$true}else{throw}}
if(-not$wrongIndependentRejected){throw '[mir4-t04-wrong-independent-engine-accepted]'}

if((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-cne$packageBefore){throw '[mir4-t04-package-mutation]'}
Write-Host '[ok] MIR 4 T04 exact qualification plans, resumable worker adoption, deterministic preview assets, independent receipt imports, mismatch rejection, and production boundaries passed.'
