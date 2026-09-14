# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $repo 'tools/lib/mir4/pre-freeze-release/ProtectedPromotionTopology.ps1')

function Expect-A08Failure {
  param([scriptblock]$Action,[string]$Code)
  try { & $Action | Out-Null } catch { if ($_.Exception.Message.StartsWith($Code,[StringComparison]::Ordinal)) { return }; throw }
  throw "Expected A08 failure: $Code"
}
function Invoke-A08Git {
  param([string]$Root,[string[]]$Arguments)
  $output=@(& git -C $Root @Arguments 2>&1)
  if ($LASTEXITCODE-ne0){throw "synthetic git failure: $($Arguments-join' ') :: $($output-join' ')"};return @($output)
}
function Write-A08Json { param([string]$Path,$Value) [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false)) }
function New-A08Zip {
  param([string]$Path,[string]$Target)
  $version=Get-MIR4A08ExpectedFactorioVersion $Target
  if (Test-Path -LiteralPath $Path) { [IO.File]::Delete($Path) }
  $archive=[IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Create)
  try {$entry=$archive.CreateEntry("more-infinite-research_4.2.$Target/info.json");$writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false));try{$writer.Write((@{name='more-infinite-research';version='4.2.0';factorio_version=$version}|ConvertTo-Json -Compress))}finally{$writer.Dispose()}}finally{$archive.Dispose()}
}
function New-A08Policy {
  param([int]$RulesetId=20833408,[bool]$Enabled=$true)
  $value=[pscustomobject][ordered]@{schema=1;kind='MIR42GitHubMainPolicyObservationV1';observation_source='synthetic-github-readonly-v1';repository='Julesc013/more-infinite-research';canonical_remote_url='synthetic://Julesc013/more-infinite-research';main_ref='refs/heads/main';observed_at='2026-09-15T00:00:00Z';ruleset=[pscustomobject][ordered]@{id=$RulesetId;enforcement=$(if ($Enabled){'active'}else{'disabled'});pull_request_required=$Enabled;linear_history_required=$Enabled;non_fast_forward_blocked=$Enabled;deletion_blocked=$Enabled;bypass_actor_count=0;required_status_checks=@('branch-policy','verification-gate')};protection=[pscustomobject][ordered]@{observed=$Enabled;squash_merge_enabled=$Enabled};policy_sha256=''};$value.policy_sha256=Get-MIR4A08PolicySha256 $value;return $value
}
function New-A08WorkerReceipt {
  param($Candidate,$Observation,[string]$Target,[string]$Digest)
  $record=[pscustomobject][ordered]@{schema=1;kind='MIR4TargetQualificationWorkerReceiptV1';producer_id='target-qualification-worker';source_commit=[string]$Candidate.commit;source_tree=[string]$Candidate.tree;release_plan_digest=$Digest;target=$Target;distribution_version=$(if ($Target-ceq'F200'){'4.2.20000'}else{'4.2.21000'});package=[pscustomobject][ordered]@{sha256=[string]$Observation.archive_sha256;content_sha256=[string]$Observation.content_sha256;bytes=[long]$Observation.bytes;entry_count=[int]$Observation.entry_count};engine=[pscustomobject][ordered]@{version=(Get-MIR4A08ExpectedFactorioVersion $Target);path='synthetic';sha256=('B'*64)};evidence_sha256=('C'*64);status='passed';release_identity=$false;publication_authorized=$false;record_sha256=''};$record.record_sha256=Get-MIR4A08SelfSha256 $record 'record_sha256';return $record
}
function New-A08IndependentReceipt {
  param($Candidate,$Observation,[string]$Target,[string]$Digest,[string]$Issuer)
  $record=[pscustomobject][ordered]@{schema=1;kind='MIR4IndependentVerificationReceiptV1';producer_id=$Issuer;independent=$true;source_commit=[string]$Candidate.commit;source_tree=[string]$Candidate.tree;release_plan_digest=$Digest;target=$Target;distribution_version=$(if ($Target-ceq'F200'){'4.2.20000'}else{'4.2.21000'});package_sha256=[string]$Observation.archive_sha256;engine_sha256=('B'*64);evidence_sha256=('D'*64);status='passed';release_identity=$false;publication_authorized=$false;record_sha256=''};$record.record_sha256=Get-MIR4A08SelfSha256 $record 'record_sha256';return $record
}
function New-A08Qualification {
  param([string]$Root,$Candidate)
  $issuer='synthetic-independent-verifier';$digest=('A'*64);$observed=@((Get-MIR4A08PackageObservation -PackagePath (Join-Path $Root 'F200.zip') -Target F200 -RelativePath F200.zip),(Get-MIR4A08PackageObservation -PackagePath (Join-Path $Root 'F210.zip') -Target F210 -RelativePath F210.zip))
  $producer=[pscustomobject][ordered]@{repository='Julesc013/more-infinite-research';workflow='synthetic-independent-verification';run_id='synthetic-run';run_attempt='1';job=$issuer;actor='synthetic';commit=[string]$Candidate.commit;ref='refs/heads/main';event='synthetic-merge';environment='synthetic';runner_identity='synthetic';trust_class='synthetic-protected-release';verifier_sha256=('E'*64);policy_sha256=('F'*64)}
  $rows=@(foreach ($item in $observed){[pscustomobject][ordered]@{target=[string]$item.target;distribution_version=$(if ($item.target-ceq'F200'){'4.2.20000'}else{'4.2.21000'});relative_path=[string]$item.relative_path;archive_sha256=[string]$item.archive_sha256;content_sha256=[string]$item.content_sha256;bytes=[long]$item.bytes;entry_count=[int]$item.entry_count;root=[string]$item.root;factorio_version=[string]$item.factorio_version;worker_receipt=(New-A08WorkerReceipt -Candidate $Candidate -Observation $item -Target $item.target -Digest $digest);independent_receipt=(New-A08IndependentReceipt -Candidate $Candidate -Observation $item -Target $item.target -Digest $digest -Issuer $issuer)}})
  $record=[pscustomobject][ordered]@{schema=1;kind='MIR42ProtectedMainQualificationBindingV2';status='independently-qualified';candidate=[pscustomobject][ordered]@{ref=$Candidate.ref;commit=$Candidate.commit;tree=$Candidate.tree};materializer=[pscustomobject][ordered]@{path='tools/mir/application/package/TargetMaterializer.ps1';git_blob=(Resolve-MIR4A08Blob -RepoRoot $testRoot -Commit $Candidate.commit -Path 'tools/mir/application/package/TargetMaterializer.ps1')};authority=[pscustomobject][ordered]@{kind='MIR4GovernedIndependentQualificationAuthorityV1';issuer_id=$issuer;trust_policy='validation/trust.json';producer=$producer};expected_targets=@('F200','F210');targets=$rows;release_authority=$false;publication_authority=$false;record_sha256=''};$record.record_sha256=Get-MIR4A08SelfSha256 $record 'record_sha256';return $record
}

$authorityPath=Join-Path $repo 'spec/releases/mir4-protected-main-promotion-topology-v1.json';$authoritySchema=Join-Path $repo 'spec/schemas/mir4-protected-main-promotion-topology-v1.schema.json';$qualificationSchema=Join-Path $repo 'spec/schemas/mir4-protected-main-qualification-v1.schema.json'
if (-not((Get-Content -Raw -LiteralPath $authorityPath)|Test-Json -SchemaFile $authoritySchema)){throw '[mir4-a08-authority-schema]'}
$null=Test-MIR4A08PromotionTopologyAuthority -RepoRoot $repo
$testRoot=Join-Path $repo ('build/tests/protected-promotion-a08/'+[guid]::NewGuid().ToString('N'));$remoteRoot=Join-Path $testRoot 'protected-remote.git';$packageRoot=Join-Path $testRoot 'qualified-packages';$stateRoot=Join-Path $testRoot 'state';New-Item -ItemType Directory -Force -Path $testRoot,$packageRoot,$stateRoot|Out-Null
try {
  $queuedProgramme=Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/programmes/mir4-4x-operating-programme-v1.json')|ConvertFrom-Json -Depth 100
  $queuedA08=@($queuedProgramme.synthesis.tasks|Where-Object{[string]$_.id-ceq'A08'})[0];$queuedA08.state='queued';$queuedA08.evidence=@()
  $queuedProgrammePath=Join-Path $testRoot 'programme-a08-queued.json';Write-A08Json $queuedProgrammePath $queuedProgramme
  Expect-A08Failure {Test-MIR4A08PromotionTopologyAuthority -RepoRoot $repo -ProgrammePath $queuedProgrammePath} '[mir4-a08-authority-wiring]'
  # Mirror GitHub's effective branch-rules response: ruleset_id is a sibling
  # of ruleset_source, rather than a nested ruleset_source.id field.
  $fakePolicyGh=Join-Path $testRoot 'fake-policy-gh.cmd'
  $fakePolicyGhBody=@'
@echo off
setlocal EnableExtensions
if not "%~1"=="api" exit /b 12
if "%~2"=="repos/Julesc013/more-infinite-research" (
  echo {"full_name":"Julesc013/more-infinite-research","default_branch":"main","clone_url":"https://github.com/Julesc013/more-infinite-research.git","allow_squash_merge":true}
  exit /b 0
)
if "%~2"=="repos/Julesc013/more-infinite-research/rules/branches/main" (
  echo [{"type":"deletion","ruleset_source_type":"Repository","ruleset_source":"Julesc013/more-infinite-research","ruleset_id":20833408},{"type":"non_fast_forward","ruleset_source_type":"Repository","ruleset_source":"Julesc013/more-infinite-research","ruleset_id":20833408},{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"branch-policy"},{"context":"verification-gate"}]},"ruleset_source_type":"Repository","ruleset_source":"Julesc013/more-infinite-research","ruleset_id":20833408},{"type":"pull_request","ruleset_source_type":"Repository","ruleset_source":"Julesc013/more-infinite-research","ruleset_id":20833408},{"type":"required_linear_history","ruleset_source_type":"Repository","ruleset_source":"Julesc013/more-infinite-research","ruleset_id":20833408}]
  exit /b 0
)
if "%~2"=="repos/Julesc013/more-infinite-research/rulesets/20833408" (
  echo {"id":20833408,"enforcement":"active","bypass_actors":[]}
  exit /b 0
)
exit /b 13
'@
  [IO.File]::WriteAllText($fakePolicyGh,$fakePolicyGhBody,[Text.UTF8Encoding]::new($false));$restPolicyProvider=New-MIR4A08GitHubRestPolicyProvider -GhExecutable $fakePolicyGh;$restPolicy=& $restPolicyProvider 'Julesc013/more-infinite-research' 'main';if([int]$restPolicy.ruleset.id-ne20833408-or(@($restPolicy.ruleset.required_status_checks|Sort-Object)-join'|')-cne'branch-policy|verification-gate'){throw '[mir4-a08-live-ruleset-id-observation]'}
  $null=Invoke-A08Git $testRoot @('init','-q','--initial-branch=main');$null=Invoke-A08Git $testRoot @('config','user.name','MIR A08 Rehearsal');$null=Invoke-A08Git $testRoot @('config','user.email','mir-a08@example.invalid')
  New-Item -ItemType Directory -Force -Path (Join-Path $testRoot 'tools/mir/application/package')|Out-Null;[IO.File]::WriteAllText((Join-Path $testRoot 'README.md'),"base`n",[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText((Join-Path $testRoot 'tools/mir/application/package/TargetMaterializer.ps1'),"# synthetic materializer`n",[Text.UTF8Encoding]::new($false));$null=Invoke-A08Git $testRoot @('add','.');$null=Invoke-A08Git $testRoot @('commit','-q','-m','base');$base=((Invoke-A08Git $testRoot @('rev-parse','HEAD'))-join'').Trim()
  $null=Invoke-A08Git $testRoot @('switch','-q','-c','dev',$base);[IO.File]::AppendAllText((Join-Path $testRoot 'README.md'),"stable repair`n",[Text.UTF8Encoding]::new($false));$null=Invoke-A08Git $testRoot @('add','README.md');$null=Invoke-A08Git $testRoot @('commit','-q','-m','forward-port stable repair');$null=Invoke-A08Git $testRoot @('switch','-q','main');[IO.File]::AppendAllText((Join-Path $testRoot 'README.md'),"stable repair`n",[Text.UTF8Encoding]::new($false));$null=Invoke-A08Git $testRoot @('add','README.md');$null=Invoke-A08Git $testRoot @('commit','-q','-m','stable repair');$mainBefore=((Invoke-A08Git $testRoot @('rev-parse','HEAD'))-join'').Trim();$null=Invoke-A08Git $testRoot @('switch','-q','dev');[IO.File]::WriteAllText((Join-Path $testRoot 'feature.txt'),"qualified feature tree`n",[Text.UTF8Encoding]::new($false));$null=Invoke-A08Git $testRoot @('add','feature.txt');$null=Invoke-A08Git $testRoot @('commit','-q','-m','qualified feature');$source=((Invoke-A08Git $testRoot @('rev-parse','HEAD'))-join'').Trim()
  $null=Invoke-A08Git $testRoot @('init','-q','--bare',$remoteRoot);$null=Invoke-A08Git $testRoot @('remote','add','synthetic',$remoteRoot);$null=Invoke-A08Git $testRoot @('push','-q','synthetic','refs/heads/main:refs/heads/main','refs/heads/dev:refs/heads/dev')
  $script:policyState=New-A08Policy;$policyProvider={param($Repository,$Branch) return $script:policyState};$candidateRef='refs/heads/candidate/mir42-a08-rehearsal';$plan=New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $testRoot -MainRef refs/heads/main -SourceRef refs/heads/dev -CandidateRef $candidateRef -PolicyProvider $policyProvider -Rehearsal
  if ([string]$plan.main_before.commit-cne$mainBefore-or[string]$plan.source.commit-cne$source-or[string]$plan.policy.repository-cne'Julesc013/more-infinite-research'){throw '[mir4-a08-plan-contract]'}
  foreach ($field in @('main_mutation_authority','tag_creation_authority','release_authority','publication_authority')){$forged=$plan|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$forged.$field=$true;$forged.plan_sha256=Get-MIR4A08PlanSha256 $forged;Expect-A08Failure {Assert-MIR4A08Plan $forged} '[mir4-a08-plan-invalid]'}
  $forged=$plan|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$forged.promotion.deletion_authorized=$true;$forged.plan_sha256=Get-MIR4A08PlanSha256 $forged;Expect-A08Failure {Assert-MIR4A08Plan $forged} '[mir4-a08-plan-invalid]';$script:policyState=New-A08Policy -Enabled:$false;Expect-A08Failure {New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $testRoot -MainRef refs/heads/main -SourceRef refs/heads/dev -CandidateRef refs/heads/candidate/mir42-a08-policy -PolicyProvider $policyProvider -Rehearsal} '[mir4-a08-policy-incompatible]';$script:policyState=New-A08Policy
  $candidate=New-MIR4ProtectedMainCandidate -RepoRoot $testRoot -Plan $plan;$adopted=New-MIR4ProtectedMainCandidate -RepoRoot $testRoot -Plan $plan;if (-not[bool]$candidate.created-or[bool]$adopted.created-or[string]$candidate.commit-cne[string]$adopted.commit){throw '[mir4-a08-candidate-recovery]'}
  New-A08Zip -Path (Join-Path $packageRoot 'F200.zip') -Target F200;New-A08Zip -Path (Join-Path $packageRoot 'F210.zip') -Target F210;$qualification=New-A08Qualification -Root $packageRoot -Candidate $candidate;$qualificationPath=Join-Path $testRoot 'qualification.json';Write-A08Json $qualificationPath $qualification;if (-not((Get-Content -Raw -LiteralPath $qualificationPath)|Test-Json -SchemaFile $qualificationSchema)){throw '[mir4-a08-qualification-schema]'}
  $selfIssued=$qualification|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$selfIssued.targets[0].worker_receipt.producer_id=$selfIssued.authority.issuer_id;$selfIssued.targets[0].worker_receipt.record_sha256=Get-MIR4A08SelfSha256 $selfIssued.targets[0].worker_receipt 'record_sha256';$selfIssued.record_sha256=Get-MIR4A08SelfSha256 $selfIssued 'record_sha256';$selfIssuedPath=Join-Path $testRoot 'self-issued.json';Write-A08Json $selfIssuedPath $selfIssued;Expect-A08Failure {Read-MIR4A08QualificationRecord -RepoRoot $testRoot -Plan $plan -Candidate $candidate -RecordPath $selfIssuedPath -PackageRoot $packageRoot -Rehearsal} '[mir4-a08-qualification-record]'
  $f200Bytes=[IO.File]::ReadAllBytes((Join-Path $packageRoot 'F200.zip'));[IO.File]::WriteAllBytes((Join-Path $packageRoot 'F210.zip'),$f200Bytes);Expect-A08Failure {Read-MIR4A08QualificationRecord -RepoRoot $testRoot -Plan $plan -Candidate $candidate -RecordPath $qualificationPath -PackageRoot $packageRoot -Rehearsal} '[mir4-a08-package-target-identity]';New-A08Zip -Path (Join-Path $packageRoot 'F210.zip') -Target F210;$qualification=New-A08Qualification -Root $packageRoot -Candidate $candidate;Write-A08Json $qualificationPath $qualification
  $productionAuthority=$qualification.authority|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$productionAuthority.issuer_id='verification-gate';$productionAuthority.producer.workflow='MIR Control Plane v5';$productionAuthority.producer.run_id='123';$productionAuthority.producer.run_attempt='1';$productionAuthority.producer.job='verification-gate';$productionAuthority.producer.actor='synthetic';$productionAuthority.producer.ref='refs/heads/dev';$productionAuthority.producer.event='workflow_dispatch';$productionAuthority.producer.environment='release-candidate';$productionAuthority.producer.runner_identity='self-hosted-windows';$productionAuthority.producer.trust_class='protected-release';$productionAuthority.producer.policy_sha256=Get-MIR4A08FileSha256 (Join-Path $repo 'validation/trust.json');$fakeGh=Join-Path $testRoot 'fake-gh.cmd';$oldCandidate=$env:A08_CANDIDATE;$env:A08_CANDIDATE=[string]$candidate.commit;[IO.File]::WriteAllText($fakeGh,"@echo off`r`nsetlocal EnableExtensions`r`nif `"%~2`"==`"-X`" (`r`n  echo {`"jobs`":[{`"name`":`"MIR / verification-gate`",`"status`":`"completed`",`"conclusion`":`"success`",`"runner_name`":`"synthetic-runner`",`"labels`":[`"self-hosted`",`"Windows`"]}]}`r`n  exit /b 0`r`n)`r`necho {`"id`":123,`"name`":`"MIR Control Plane v5`",`"event`":`"workflow_dispatch`",`"head_sha`":`"%A08_CANDIDATE%`",`"run_attempt`":1,`"status`":`"completed`",`"conclusion`":`"success`",`"actor`":{`"login`":`"synthetic`"}}`r`n",[Text.UTF8Encoding]::new($false));$qualificationProvider=New-MIR4A08GitHubRestQualificationAuthorityProvider -GhExecutable $fakeGh;$null=Assert-MIR4A08TrustedIssuer -Authority $productionAuthority -Candidate $candidate -CanonicalRepository 'Julesc013/more-infinite-research' -QualificationAuthorityProvider $qualificationProvider;$productionAuthority.producer.run_id='124';Expect-A08Failure {Assert-MIR4A08TrustedIssuer -Authority $productionAuthority -Candidate $candidate -CanonicalRepository 'Julesc013/more-infinite-research' -QualificationAuthorityProvider $qualificationProvider} '[mir4-a08-qualification-authority-provider]';$productionAuthority.producer.run_id='123';if($null-eq$oldCandidate){Remove-Item Env:A08_CANDIDATE}else{$env:A08_CANDIDATE=$oldCandidate}
  Expect-A08Failure {New-MIR4A08PromotionIntention -RepoRoot $testRoot -Plan $plan -Candidate $candidate -QualificationRecordPath $qualificationPath -PackageRoot $packageRoot -RemoteName synthetic -RemoteSourceRef refs/heads/dev -StateRoot $stateRoot} '[mir4-a08-remote-identity]'
  $intention=New-MIR4A08PromotionIntention -RepoRoot $testRoot -Plan $plan -Candidate $candidate -QualificationRecordPath $qualificationPath -PackageRoot $packageRoot -RemoteName synthetic -RemoteSourceRef refs/heads/dev -StateRoot $stateRoot -Rehearsal;$resumedIntention=New-MIR4A08PromotionIntention -RepoRoot $testRoot -Plan $plan -Candidate $candidate -QualificationRecordPath $qualificationPath -PackageRoot $packageRoot -RemoteName synthetic -RemoteSourceRef refs/heads/dev -StateRoot $stateRoot -Rehearsal;if ($intention.path-cne$resumedIntention.path){throw '[mir4-a08-intention-persistence]'};if ((Get-Command New-MIR4A08PromotionIntention).Parameters.ContainsKey('TrustedQualificationRecordSha256')){throw '[mir4-a08-caller-hash-trust]'}
  $push=Invoke-MIR4A08CreateOnlyCandidatePush -RepoRoot $testRoot -IntentionPath $intention.path -StateRoot $stateRoot;$resumedPush=Invoke-MIR4A08CreateOnlyCandidatePush -RepoRoot $testRoot -IntentionPath $intention.path -StateRoot $stateRoot;if (-not[bool]$push.created-or[bool]$resumedPush.created){throw '[mir4-a08-create-only-resume]'}
  $script:policyState=New-A08Policy -RulesetId 20833409;Expect-A08Failure {New-MIR4A08ProtectedPromotionRequest -RepoRoot $testRoot -IntentionPath $intention.path -StateRoot $stateRoot -PolicyProvider $policyProvider} '[mir4-a08-policy-drift-before-merge]';$script:policyState=New-A08Policy;$request=New-MIR4A08ProtectedPromotionRequest -RepoRoot $testRoot -IntentionPath $intention.path -StateRoot $stateRoot -PolicyProvider $policyProvider;$resumedRequest=New-MIR4A08ProtectedPromotionRequest -RepoRoot $testRoot -IntentionPath $intention.path -StateRoot $stateRoot -PolicyProvider $policyProvider;if ($request.path-cne$resumedRequest.path){throw '[mir4-a08-pr-request-persistence]'}
  $intentionValue=Read-MIR4A08Intention $intention.path;$finalMain=((Invoke-A08Git $testRoot @('commit-tree',$candidate.tree,'-p',$mainBefore,'-m',(Get-MIR4A08PromotionMessage $intentionValue)))-join'').Trim();$null=Invoke-A08Git $testRoot @('push','-q','synthetic',"$finalMain`:refs/heads/a08-objects/final");$null=Invoke-A08Git $remoteRoot @('update-ref','refs/heads/main',$finalMain,$mainBefore)
  $script:prMode='direct';$script:prMerge=$finalMain;$script:prBase=$mainBefore;$script:prHead='';$script:prMethod='squash';$script:prChecks=@([pscustomobject][ordered]@{context='branch-policy';conclusion='success'},[pscustomobject][ordered]@{context='verification-gate';conclusion='success'})
  $pullProvider={
    param($Repository,$Ref,$Commit,$MainAfter)
    $headCommit = if ([string]::IsNullOrWhiteSpace([string]$script:prHead)) { $Commit } else { [string]$script:prHead }
    $record=[pscustomobject][ordered]@{
      schema=1;kind='MIR42GitHubPullRequestReadbackV1';observation_source='synthetic-github-readonly-v1';repository=$Repository;canonical_remote_url='synthetic://Julesc013/more-infinite-research';number=42;state='MERGED'
      base=[pscustomobject][ordered]@{ref='main';commit=$script:prBase};head=[pscustomobject][ordered]@{ref=($Ref-replace'^refs/heads/','');commit=$headCommit}
      merge=[pscustomobject][ordered]@{method=$script:prMethod;commit=$script:prMerge};required_checks=@($script:prChecks);policy_sha256=$script:policyState.policy_sha256;direct_ref_update=($script:prMode-ceq'direct');record_sha256=''
    }
    $record.record_sha256=Get-MIR4A08SelfSha256 $record 'record_sha256';return $record
  }
  Expect-A08Failure {Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intention.path -PromotionRequestPath $request.path -StateRoot $stateRoot -PolicyProvider $policyProvider -PullRequestProvider $pullProvider} '[mir4-a08-pr-bypass]'
  $script:prMode='protected';$script:prBase=$source;Expect-A08Failure {Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intention.path -PromotionRequestPath $request.path -StateRoot $stateRoot -PolicyProvider $policyProvider -PullRequestProvider $pullProvider} '[mir4-a08-pr-observation]'
  $script:prBase=$mainBefore;$script:prHead=$source;Expect-A08Failure {Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intention.path -PromotionRequestPath $request.path -StateRoot $stateRoot -PolicyProvider $policyProvider -PullRequestProvider $pullProvider} '[mir4-a08-pr-observation]'
  $script:prHead='';$script:prMethod='rebase';Expect-A08Failure {Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intention.path -PromotionRequestPath $request.path -StateRoot $stateRoot -PolicyProvider $policyProvider -PullRequestProvider $pullProvider} '[mir4-a08-pr-observation]'
  $script:prMethod='squash';$script:prChecks=@([pscustomobject][ordered]@{context='branch-policy';conclusion='failure'},[pscustomobject][ordered]@{context='verification-gate';conclusion='success'});Expect-A08Failure {Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intention.path -PromotionRequestPath $request.path -StateRoot $stateRoot -PolicyProvider $policyProvider -PullRequestProvider $pullProvider} '[mir4-a08-pr-required-check]'
  $script:prChecks=@([pscustomobject][ordered]@{context='branch-policy';conclusion='success'},[pscustomobject][ordered]@{context='verification-gate';conclusion='success'});$script:policyState=New-A08Policy -RulesetId 20833410;Expect-A08Failure {Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intention.path -PromotionRequestPath $request.path -StateRoot $stateRoot -PolicyProvider $policyProvider -PullRequestProvider $pullProvider} '[mir4-a08-policy-drift-readback]';$script:policyState=New-A08Policy;[IO.File]::WriteAllBytes((Join-Path $packageRoot 'F200.zip'),[Text.Encoding]::UTF8.GetBytes('not-a-zip'));Expect-A08Failure {Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intention.path -PromotionRequestPath $request.path -StateRoot $stateRoot -PolicyProvider $policyProvider -PullRequestProvider $pullProvider} '[mir4-a08-package-archive]';[IO.File]::WriteAllBytes((Join-Path $packageRoot 'F200.zip'),$f200Bytes)
  $readback=Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intention.path -PromotionRequestPath $request.path -StateRoot $stateRoot -PolicyProvider $policyProvider -PullRequestProvider $pullProvider;$resumedReadback=Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intention.path -PromotionRequestPath $request.path -StateRoot $stateRoot -PolicyProvider $policyProvider -PullRequestProvider $pullProvider;if ([string]$readback.main_after-cne$finalMain-or$readback.path-cne$resumedReadback.path-or-not[bool]$readback.commit_rewritten){throw '[mir4-a08-readback-contract]'}
  $intervening=((Invoke-A08Git $testRoot @('commit-tree',$candidate.tree,'-p',$finalMain,'-m',(Get-MIR4A08PromotionMessage $intentionValue)))-join'').Trim();$null=Invoke-A08Git $testRoot @('push','-q','synthetic',"$intervening`:refs/heads/a08-objects/intervening");$null=Invoke-A08Git $remoteRoot @('update-ref','refs/heads/main',$intervening,$finalMain);$script:prMerge=$intervening;Expect-A08Failure {Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intention.path -PromotionRequestPath $request.path -StateRoot $stateRoot -PolicyProvider $policyProvider -PullRequestProvider $pullProvider} '[mir4-a08-readback-not-direct-main-child]';$null=Invoke-A08Git $remoteRoot @('update-ref','refs/heads/main',$finalMain,$intervening);$script:prMerge=$finalMain
  $null=Invoke-A08Git $remoteRoot @('update-ref','refs/heads/dev',$base,$source);Expect-A08Failure {Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intention.path -PromotionRequestPath $request.path -StateRoot $stateRoot -PolicyProvider $policyProvider -PullRequestProvider $pullProvider} '[mir4-a08-remote-source-ref-drift-after-promotion]';$null=Invoke-A08Git $remoteRoot @('update-ref','refs/heads/dev',$source,$base)
  if (@(Invoke-A08Git $testRoot @('tag','--list')).Count-ne0-or@(Invoke-A08Git $remoteRoot @('tag','--list')).Count-ne0){throw '[mir4-a08-tag-created]'}
  Write-Host '[ok] A08 fails closed on policy drift, direct ref bypass, bad PR/checks, self-issued or swapped qualification, and unbound package bytes; synthetic rehearsal persists only candidate/receipt state.'
} finally {
  if (Test-Path -LiteralPath $testRoot) {
    $cleanupFailure = $null
    foreach ($attempt in 1..5) {
      try {
        # Git marks loose objects read-only on this Windows runner.  These are
        # exclusively inside this GUID-scoped synthetic repository; clearing
        # that attribute is required before Directory.Delete can reclaim it.
        Get-ChildItem -LiteralPath $testRoot -Force -Recurse | ForEach-Object {
          if ($_.Attributes -band [IO.FileAttributes]::ReadOnly) {
            $_.Attributes = $_.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)
          }
        }
        [IO.Directory]::Delete($testRoot, $true)
        $cleanupFailure = $null
        break
      } catch {
        $cleanupFailure = $_
        Start-Sleep -Milliseconds (200 * $attempt)
      }
    }
    if ($null -ne $cleanupFailure -and (Test-Path -LiteralPath $testRoot)) {
      throw "[mir4-a08-test-cleanup] $($cleanupFailure.Exception.Message)"
    }
  }
}
