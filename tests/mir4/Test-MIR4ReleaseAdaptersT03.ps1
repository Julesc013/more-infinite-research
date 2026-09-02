# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/mir4/ReleasePhaseEngine.ps1')
. (Join-Path $repo 'tools/lib/mir4/ReleaseAdapters.ps1')
. (Join-Path $repo 'tools/lib/mir4/PreFreezeRelease.ps1')

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$developmentPlanPath='.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json'
$developmentPlan=Get-Content -Raw -LiteralPath (Join-Path $repo $developmentPlanPath)|ConvertFrom-Json -Depth 100
$inputs=[pscustomobject][ordered]@{
  source_release_record='.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json'
  candidate_id='DEV-T03-UNALLOCATED';source_commit=(& git -C $repo rev-parse HEAD).Trim();source_tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  target_distribution_record_set=$developmentPlanPath;release_plan_digest=[string]$developmentPlan.verification_plan.plan_sha256
  proof_root='development-proof-root';seal_root='not-allocated'
}
$testRunRoot='build/mir4/release-phase-engine/tests/t03-'+[guid]::NewGuid().ToString('N')

function Invoke-T03Phase([string]$Operation,[string]$Phase,[string]$Root,$Adapter,$UseInputs=$inputs){
  Invoke-MIR4ReleasePhaseEngine -RepoRoot $repo -Operation $Operation -Phase $Phase -Inputs $UseInputs -Adapter $Adapter -OutputRoot $Root
}

$sourceAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase source-freeze
$targetAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase target-build
foreach($binding in @(
  @{phase='source-freeze';adapter=$sourceAdapter;schema='spec/schemas/mir4-release-source-freeze-result-v1.schema.json'},
  @{phase='target-build';adapter=$targetAdapter;schema='spec/schemas/mir4-release-target-build-result-v1.schema.json'}
)){
  if([bool]$binding.adapter.descriptor.production_capable-or
     @($binding.adapter.descriptor.required_ports|Where-Object{$_-in@('sign','publish')}).Count-ne0-or
     [string]$binding.adapter.descriptor.result_schema-cne[string]$binding.schema){throw "[mir4-t03-adapter-boundary] $($binding.phase)"}
  try{Get-Content -Raw -LiteralPath (Join-Path $repo $binding.schema)|ConvertFrom-Json -Depth 100|Out-Null}catch{throw "[mir4-t03-schema-load] $($binding.phase)"}
}

$sourceRoot=Join-Path $testRunRoot 'source-happy'
$sourcePlan=Invoke-T03Phase Plan source-freeze $sourceRoot $sourceAdapter
$sourceDry=Invoke-T03Phase DryRun source-freeze $sourceRoot $sourceAdapter
$sourceExecute=Invoke-T03Phase Execute source-freeze $sourceRoot $sourceAdapter
$sourceVerify=Invoke-T03Phase Verify source-freeze $sourceRoot $sourceAdapter
$sourceReceipt=Invoke-T03Phase Receipt source-freeze $sourceRoot $sourceAdapter
$sourceState=Get-MIR4ReleasePhaseAttemptState -AttemptRoot ([string]$sourcePlan.attempt_root)
if([string]$sourceDry.state-cne'dry-run-passed'-or[string]$sourceExecute.state-cne'executed'-or[string]$sourceVerify.state-cne'verified'-or
   [string]$sourceReceipt.final_state-cne'verified'-or@($sourceState.events).Count-ne5-or[bool]$sourceReceipt.production_authorized-or
   [bool]$sourceState.events[2].result.release_transition_performed){throw '[mir4-t03-source-happy]'}

$sourceCompensateInputs=$inputs.PSObject.Copy();$sourceCompensateInputs.candidate_id='DEV-T03-COMPENSATE'
$sourceCompensateRoot=Join-Path $testRunRoot 'source-compensate'
$null=Invoke-T03Phase Plan source-freeze $sourceCompensateRoot $sourceAdapter $sourceCompensateInputs
$null=Invoke-T03Phase DryRun source-freeze $sourceCompensateRoot $sourceAdapter $sourceCompensateInputs
$null=Invoke-T03Phase Execute source-freeze $sourceCompensateRoot $sourceAdapter $sourceCompensateInputs
$compensated=Invoke-T03Phase Compensate source-freeze $sourceCompensateRoot $sourceAdapter $sourceCompensateInputs
$compensationReceipt=Invoke-T03Phase Receipt source-freeze $sourceCompensateRoot $sourceAdapter $sourceCompensateInputs
if([string]$compensated.state-cne'compensated'-or[string]$compensationReceipt.final_state-cne'compensated'){throw '[mir4-t03-source-compensation]'}

$fixtureDescriptor={
  param([string]$FixtureRepo,[string]$Path)
  $item=Get-Item -LiteralPath $Path
  [pscustomobject][ordered]@{
    path=([IO.Path]::GetRelativePath($FixtureRepo,[IO.Path]::GetFullPath($Path))).Replace('\','/')
    sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    bytes=[long]$item.Length
  }
}.GetNewClosure()
$fixtureConstructor={
  param([string]$FixtureRepo,[string]$Target,[string]$OutputRoot)
  $version=if($Target-ceq'F210'){'4.0.21000'}else{'4.0.20000'}
  $packageRoot=Join-Path $OutputRoot 'distributions';$manifestRoot=Join-Path $OutputRoot 'manifests'
  New-Item -ItemType Directory -Path $packageRoot,$manifestRoot -Force|Out-Null
  $packagePath=Join-Path $packageRoot "more-infinite-research_$version.zip"
  [IO.File]::WriteAllText($packagePath,"MIR4-T03-ADAPTER-FIXTURE:$Target`n",[Text.UTF8Encoding]::new($false))
  $manifestPath=Join-Path $manifestRoot ($Target.ToLowerInvariant()+'.json')
  [IO.File]::WriteAllText($manifestPath,('{"kind":"MIR4T03TargetBuildDelegateFixtureV1","target":"'+$Target+'","version":"'+$version+'"}')+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
  $package=&$fixtureDescriptor $FixtureRepo $packagePath
  $manifest=&$fixtureDescriptor $FixtureRepo $manifestPath
  [pscustomobject][ordered]@{target=$Target;distribution_version=$version;state='built-private-unqualified';manifest=$manifest;package=$package;content_sha256=[string]$package.sha256;entry_count=1;source_frozen=$false;release_identity=$false;publication_authorized=$false}
}.GetNewClosure()
$fixtureAdapter=Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase target-build -TargetConstructor $fixtureConstructor -TargetConstructorIdentity ('A'*64)
$targetRoot=Join-Path $testRunRoot 'target-happy'
$targetPlan=Invoke-T03Phase Plan target-build $targetRoot $fixtureAdapter
$targetDry=Invoke-T03Phase DryRun target-build $targetRoot $fixtureAdapter
$targetExecute=Invoke-T03Phase Execute target-build $targetRoot $fixtureAdapter
$targetExecuteReuse=Invoke-T03Phase Execute target-build $targetRoot $fixtureAdapter
$targetVerify=Invoke-T03Phase Verify target-build $targetRoot $fixtureAdapter
$targetReceipt=Invoke-T03Phase Receipt target-build $targetRoot $fixtureAdapter
$targetState=Get-MIR4ReleasePhaseAttemptState -AttemptRoot ([string]$targetPlan.attempt_root)
$builtTargets=@($targetState.events|Where-Object operation -eq Execute|Where-Object status -eq passed|Select-Object -Last 1|ForEach-Object{$_.result.targets})
if([string]$targetDry.state-cne'dry-run-passed'-or[string]$targetExecute.state-cne'executed'-or-not[bool]$targetExecuteReuse.idempotent_reuse-or
   [string]$targetVerify.state-cne'verified'-or[string]$targetReceipt.final_state-cne'verified'-or@($builtTargets).Count-ne2-or
   (@($builtTargets.target|Sort-Object)-join'|')-cne'F200|F210'-or@($builtTargets|Where-Object{$_.release_identity-or$_.publication_authorized}).Count-ne0){
  throw '[mir4-t03-target-happy]'
}

$invalidSetPath=Join-Path (Join-Path $repo $testRunRoot) 'invalid-target-set.json'
New-Item -ItemType Directory -Path (Split-Path -Parent $invalidSetPath) -Force|Out-Null
[IO.File]::WriteAllText($invalidSetPath,'{"targets":[{"target":"F210","distribution_version":"4.0.21000"}]}'+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
$invalidInputs=$inputs.PSObject.Copy();$invalidInputs.candidate_id='DEV-T03-INVALID-TARGETS';$invalidInputs.target_distribution_record_set=Get-MIR4ReleaseAdapterRelativePath -RepoRoot $repo -Path $invalidSetPath
$invalidRejected=$false
try{$null=Invoke-T03Phase DryRun target-build (Join-Path $testRunRoot 'target-invalid') $targetAdapter $invalidInputs}catch{if($_.Exception.Message-ceq'[mir4-target-build-mandatory-target-set]'){$invalidRejected=$true}else{throw}}
if(-not$invalidRejected){throw '[mir4-t03-target-cardinality-accepted]'}

$validationParameters=@{RepoRoot=$repo;Phase='source-freeze';SourceReleaseRecord=[string]$inputs.source_release_record;CandidateId=[string]$inputs.candidate_id;SourceCommit=[string]$inputs.source_commit;SourceTree=[string]$inputs.source_tree;TargetDistributionRecordSet=[string]$inputs.target_distribution_record_set;ReleasePlanDigest=[string]$inputs.release_plan_digest;ProofRoot=[string]$inputs.proof_root;SealRoot=[string]$inputs.seal_root}
$validated=Test-MIR4ReleaseWorkflowInvocation @validationParameters -NonProductionRehearsal
if([string]$validated.status-cne'validated-non-production-rehearsal'-or[bool]$validated.production_authorized){throw '[mir4-t03-rehearsal-validation]'}
$productionRejected=$false
try{$blocked=$validationParameters.Clone();$blocked.CandidateId='M4RC1';$null=Test-MIR4ReleaseWorkflowInvocation @blocked -NonProductionRehearsal}catch{if($_.Exception.Message-ceq'[mir4-release-transition-blocked] source-freeze'){$productionRejected=$true}else{throw}}
if(-not$productionRejected){throw '[mir4-t03-production-transition-accepted]'}

if((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-cne$packageBefore){throw '[mir4-t03-package-mutation]'}
Write-Host '[ok] MIR 4 T03 source-freeze and target-build adapters, schemas, dry-runs, idempotency, compensation, cardinality, and production boundary passed.'
