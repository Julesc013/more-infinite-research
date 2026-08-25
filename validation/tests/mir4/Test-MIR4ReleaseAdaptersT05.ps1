param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/mir4/ReleasePhaseEngine.ps1')
. (Join-Path $repo 'tools/lib/mir4/ReleaseAdapters.ps1')
. (Join-Path $repo 'tools/lib/mir4/ReleaseLifecycleAdapters.ps1')

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$developmentPlanPath='.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json'
$developmentPlan=Get-Content -Raw -LiteralPath (Join-Path $repo $developmentPlanPath)|ConvertFrom-Json -Depth 100
$inputs=[pscustomobject][ordered]@{
  source_release_record='.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json'
  candidate_id='DEV-T05-UNALLOCATED';source_commit=(& git -C $repo rev-parse HEAD).Trim();source_tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  target_distribution_record_set=$developmentPlanPath;release_plan_digest=[string]$developmentPlan.verification_plan.plan_sha256
  proof_root='build/mir4/release-phase-engine/tests/t05-proof';seal_root='not-allocated'
}
$testRoot='build/mir4/release-phase-engine/tests/t05-'+[guid]::NewGuid().ToString('N')
function Invoke-T05([string]$Operation,[string]$Phase,[string]$Root,$Adapter,$UseInputs=$inputs){
  Invoke-MIR4ReleasePhaseEngine -RepoRoot $repo -Operation $Operation -Phase $Phase -Inputs $UseInputs -Adapter $Adapter -OutputRoot $Root
}
function Complete-T05([string]$Phase,[string]$Root,$Adapter,$UseInputs=$inputs){
  $plan=Invoke-T05 Plan $Phase $Root $Adapter $UseInputs
  $dry=Invoke-T05 DryRun $Phase $Root $Adapter $UseInputs
  $execute=Invoke-T05 Execute $Phase $Root $Adapter $UseInputs
  $verify=Invoke-T05 Verify $Phase $Root $Adapter $UseInputs
  $receipt=Invoke-T05 Receipt $Phase $Root $Adapter $UseInputs
  if([string]$dry.state-cne'dry-run-passed'-or[string]$execute.state-cne'executed'-or[string]$verify.state-cne'verified'-or
     [string]$receipt.final_state-cne'verified'-or[bool]$receipt.production_authorized){throw "[mir4-t05-phase-incomplete] $Phase"}
  $state=Get-MIR4ReleasePhaseAttemptState -AttemptRoot ([string]$plan.attempt_root)
  return [pscustomobject][ordered]@{plan=$plan;state=$state;execute=@($state.events|Where-Object{[string]$_.operation-ceq'Execute'-and[string]$_.status-ceq'passed'}|Select-Object -Last 1)[0]}
}

$schemas=@(
  'spec/schemas/mir4-release-seal-result-v1.schema.json',
  'spec/schemas/mir4-release-promotion-result-v1.schema.json',
  'spec/schemas/mir4-release-target-publication-result-v1.schema.json',
  'spec/schemas/mir4-release-public-readback-result-v1.schema.json',
  'spec/schemas/mir4-release-restore-drill-result-v1.schema.json'
)
foreach($schema in $schemas){Get-Content -Raw -LiteralPath (Join-Path $repo $schema)|ConvertFrom-Json -Depth 100|Out-Null}

$sealAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase release-seal
$seal=Complete-T05 release-seal (Join-Path $testRoot 'seal') $sealAdapter
if([bool]$seal.execute.result.detail.signing_invoked-or[bool]$seal.execute.result.detail.seal_created-or
   @($seal.execute.result.detail.identity.targets).Count-ne2){throw '[mir4-t05-seal-assembly]'}

$tamperInputs=$inputs.PSObject.Copy();$tamperInputs.candidate_id='DEV-T05-TAMPER'
$tamperRoot=Join-Path $testRoot 'seal-tamper';$tamperPlan=Invoke-T05 Plan release-seal $tamperRoot $sealAdapter $tamperInputs
$null=Invoke-T05 DryRun release-seal $tamperRoot $sealAdapter $tamperInputs;$null=Invoke-T05 Execute release-seal $tamperRoot $sealAdapter $tamperInputs
$tamperPath=Join-Path ([string]$tamperPlan.attempt_root) 'artifacts/execute/unsigned-seal-assembly.json'
$tampered=Get-Content -Raw -LiteralPath $tamperPath|ConvertFrom-Json -Depth 100;$tampered.identity.targets[0].package_sha256='F'*64
$tampered.record_sha256=Get-MIR4ReleasePhaseSelfHash -Record $tampered -HashProperty record_sha256
[IO.File]::WriteAllText($tamperPath,(ConvertTo-MIR4ReleasePhaseCanonicalJson $tampered)+"`n",[Text.UTF8Encoding]::new($false))
$tamperRejected=$false
try{$null=Invoke-T05 Verify release-seal $tamperRoot $sealAdapter $tamperInputs}catch{if($_.Exception.Message.StartsWith('[mir4-release-lifecycle-record]')-or$_.Exception.Message.StartsWith('[mir4-release-seal-post-assembly-mutation]')){$tamperRejected=$true}else{throw}}
if(-not$tamperRejected){throw '[mir4-t05-post-seal-mutation-accepted]'}

$promotionAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase promotion
$promotion=Complete-T05 promotion (Join-Path $testRoot 'promotion') $promotionAdapter
if(-not[bool]$promotion.execute.result.detail.fast_forward_proven-or[bool]$promotion.execute.result.detail.ref_update_performed-or
   [bool]$promotion.execute.result.detail.tag_created){throw '[mir4-t05-promotion-plan]'}

$transferCalls=[Collections.Generic.List[object]]::new()
$transferProvider={
  param([string]$FixtureRepo,$Request,[string]$Mode,$Context)
  $transferCalls.Add([pscustomobject][ordered]@{transfer_id=[string]$Request.transfer_id;mode=$Mode})|Out-Null
  if($Mode-ceq'Transfer'){return [pscustomobject][ordered]@{state='uncertain';transfer_id=[string]$Request.transfer_id;observed_sha256=$null;network_calls=0;production_mutation_performed=$false}}
  return [pscustomobject][ordered]@{state='already-present-exact';transfer_id=[string]$Request.transfer_id;observed_sha256=[string]$Request.package_sha256;network_calls=0;production_mutation_performed=$false}
}.GetNewClosure()
$publicationAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase target-publication -PublicationTransferProvider $transferProvider -PublicationTransferProviderIdentity ('A'*64)
$publication=Complete-T05 target-publication (Join-Path $testRoot 'publication') $publicationAdapter
$transferGroups=@($transferCalls|Group-Object transfer_id)
if($transferGroups.Count-ne4-or@($transferGroups|Where-Object{$_.Count-ne2-or(@($_.Group.mode)-join'|')-cne'Transfer|Reconcile'}).Count-ne0-or
   [int]$publication.execute.result.detail.reconciled_count-ne4-or[bool]$publication.execute.result.detail.builder_available-or
   [bool]$publication.execute.result.detail.source_checkout_required){throw '[mir4-t05-publication-reconciliation]'}

$readbackAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase public-readback
$readback=Complete-T05 public-readback (Join-Path $testRoot 'readback') $readbackAdapter
if(-not[bool]$readback.execute.result.detail.all_bytes_equal-or[bool]$readback.execute.result.detail.public_observation-or
   @($readback.execute.result.detail.observations).Count-ne4){throw '[mir4-t05-readback]'}
$wrongReadback={
  param([string]$FixtureRepo,$Request,$Context)
  [pscustomobject][ordered]@{target=[string]$Request.target;channel=[string]$Request.channel;observed_sha256=('E'*64);observed_bytes=[long]$Request.bytes;network_calls=0;public_observation=$false}
}
$wrongAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase public-readback -PublicReadbackProvider $wrongReadback -PublicReadbackProviderIdentity ('B'*64)
$wrongInputs=$inputs.PSObject.Copy();$wrongInputs.candidate_id='DEV-T05-WRONG-READBACK';$wrongRoot=Join-Path $testRoot 'readback-wrong'
$null=Invoke-T05 Plan public-readback $wrongRoot $wrongAdapter $wrongInputs;$null=Invoke-T05 DryRun public-readback $wrongRoot $wrongAdapter $wrongInputs
$wrongRejected=$false
try{$null=Invoke-T05 Execute public-readback $wrongRoot $wrongAdapter $wrongInputs}catch{if($_.Exception.Message.StartsWith('[mir4-public-readback-mismatch]')){$wrongRejected=$true}else{throw}}
if(-not$wrongRejected){throw '[mir4-t05-readback-mismatch-accepted]'}

$restoreAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase restore-drill
$restore=Complete-T05 restore-drill (Join-Path $testRoot 'restore') $restoreAdapter
if(-not[bool]$restore.execute.result.detail.clean_destination-or-not[bool]$restore.execute.result.detail.all_bytes_equal-or
   @($restore.execute.result.detail.files).Count-ne2-or[bool]$restore.execute.result.detail.source_repository_access-or
   [bool]$restore.execute.result.detail.credential_access){throw '[mir4-t05-clean-restore]'}

$compensateInputs=$inputs.PSObject.Copy();$compensateInputs.candidate_id='DEV-T05-COMPENSATE';$compensateRoot=Join-Path $testRoot 'promotion-compensate'
$compensatePlan=Invoke-T05 Plan promotion $compensateRoot $promotionAdapter $compensateInputs;$null=Invoke-T05 DryRun promotion $compensateRoot $promotionAdapter $compensateInputs;$null=Invoke-T05 Execute promotion $compensateRoot $promotionAdapter $compensateInputs
$compensated=Invoke-T05 Compensate promotion $compensateRoot $promotionAdapter $compensateInputs;$receipt=Invoke-T05 Receipt promotion $compensateRoot $promotionAdapter $compensateInputs
if([string]$compensated.state-cne'compensated'-or[string]$receipt.final_state-cne'compensated'-or
   (Test-Path -LiteralPath (Join-Path ([string]$compensatePlan.attempt_root) 'artifacts/execute/fast-forward-promotion-plan.json'))){throw '[mir4-t05-compensation]'}

$publisherWorkflow=Get-Content -Raw -LiteralPath (Join-Path $repo '.github/workflows/mir4-target-publication.yml')
if($publisherWorkflow-match'actions/checkout|Build-MIRPackage|New-MIR4BootstrapLocalCandidate|mir4\s+platform\s+package'-or
   $publisherWorkflow-notmatch'publisher-forbidden-capability'){throw '[mir4-t05-publisher-has-builder]'}
if((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-cne$packageBefore){throw '[mir4-t05-package-mutation]'}
Write-Host '[ok] MIR 4 T05 unsigned seal assembly, fast-forward promotion plan, builder-free publication reconciliation, exact readback, clean restore, tamper rejection, and compensation passed.'
