# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/pre-freeze-release/ProtectedPromotionTopology.ps1')

$authorityPath=Join-Path $RepoRoot 'spec/releases/mir4-protected-main-promotion-topology-v1.json'
$schemaPath=Join-Path $RepoRoot 'spec/schemas/mir4-protected-main-promotion-topology-v1.schema.json'
$qualificationSchemaPath=Join-Path $RepoRoot 'spec/schemas/mir4-protected-main-qualification-v1.schema.json'
$authorityText=Get-Content -Raw -LiteralPath $authorityPath
if(-not($authorityText|Test-Json -SchemaFile $schemaPath)){throw '[mir4-a08-authority-schema]'}
$authority=$authorityText|ConvertFrom-Json -Depth 30
if([string]$authority.status-cne'accepted-and-synthetically-rehearsed-release-blocked'-or
   [string]$authority.strategy-cne'main-based-tree-transplant-protected-pr'-or
   -not[bool]$authority.candidate.exact_dev_tree-or-not[bool]$authority.candidate.create_only_ref-or
   -not[bool]$authority.qualification.before_promotion-or-not[bool]$authority.qualification.package_files_rehashed_at_readback-or
   -not[bool]$authority.readback.direct_main_child_required-or-not[bool]$authority.readback.commit_message_binding_required-or
   -not[bool]$authority.recovery.persist_before_effect-or-not[bool]$authority.recovery.remote_ref_readback_required-or
   [bool]$authority.authority.main_mutation-or[bool]$authority.authority.tagging-or[bool]$authority.authority.publication){throw '[mir4-a08-authority-contract]'}

function Expect-A08Failure {
  param([scriptblock]$Action,[string]$Code)
  try { & $Action | Out-Null } catch {
    if ($_.Exception.Message.StartsWith($Code,[StringComparison]::Ordinal)) { return }
    throw
  }
  throw "Expected A08 failure: $Code"
}

function Invoke-A08Git {
  param([string]$Root,[string[]]$Arguments)
  $output=@(& git -C $Root @Arguments 2>&1)
  if($LASTEXITCODE-ne0){throw "synthetic git failure: $($Arguments-join' ') :: $($output-join' ')"}
  return @($output)
}

function New-A08Zip {
  param([string]$Path,[string]$Target,[string]$Payload)
  $archive=[IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Create)
  try {
    $entry=$archive.CreateEntry("more-infinite-research_4.2.$Target/info.json")
    $writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false))
    try {$writer.Write($Payload)} finally {$writer.Dispose()}
  } finally {$archive.Dispose()}
}

function Write-A08Json {
  param([string]$Path,$Value)
  [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
}

$testRoot=Join-Path $RepoRoot ('build/tests/protected-promotion-a08/'+[guid]::NewGuid().ToString('N'))
$remoteRoot=Join-Path $testRoot 'protected-remote.git'
$packageRoot=Join-Path $testRoot 'qualified-packages'
$stateRoot=Join-Path $testRoot 'state'
New-Item -ItemType Directory -Force -Path $testRoot,$packageRoot,$stateRoot|Out-Null
try {
  $null=Invoke-A08Git $testRoot @('init','-q','--initial-branch=main')
  $null=Invoke-A08Git $testRoot @('config','user.name','MIR A08 Rehearsal')
  $null=Invoke-A08Git $testRoot @('config','user.email','mir-a08@example.invalid')
  [IO.File]::WriteAllText((Join-Path $testRoot 'README.md'),"base`n",[Text.UTF8Encoding]::new($false))
  $null=Invoke-A08Git $testRoot @('add','README.md');$null=Invoke-A08Git $testRoot @('commit','-q','-m','base')
  $base=((Invoke-A08Git $testRoot @('rev-parse','HEAD'))-join'').Trim()

  $null=Invoke-A08Git $testRoot @('switch','-q','-c','dev',$base)
  [IO.File]::WriteAllText((Join-Path $testRoot 'README.md'),"base`nstable repair`n",[Text.UTF8Encoding]::new($false))
  $null=Invoke-A08Git $testRoot @('add','README.md');$null=Invoke-A08Git $testRoot @('commit','-q','-m','forward-port stable repair')
  $null=Invoke-A08Git $testRoot @('switch','-q','main')
  [IO.File]::WriteAllText((Join-Path $testRoot 'README.md'),"base`nstable repair`n",[Text.UTF8Encoding]::new($false))
  $null=Invoke-A08Git $testRoot @('add','README.md');$null=Invoke-A08Git $testRoot @('commit','-q','-m','stable repair')
  $mainBefore=((Invoke-A08Git $testRoot @('rev-parse','HEAD'))-join'').Trim()
  $null=Invoke-A08Git $testRoot @('switch','-q','dev')
  [IO.File]::WriteAllText((Join-Path $testRoot 'feature.txt'),"qualified feature tree`n",[Text.UTF8Encoding]::new($false))
  $null=Invoke-A08Git $testRoot @('add','feature.txt');$null=Invoke-A08Git $testRoot @('commit','-q','-m','qualified feature')
  $source=((Invoke-A08Git $testRoot @('rev-parse','HEAD'))-join'').Trim()
  $null=Invoke-A08Git $testRoot @('init','-q','--bare',$remoteRoot)
  $null=Invoke-A08Git $testRoot @('remote','add','synthetic',$remoteRoot)
  $null=Invoke-A08Git $testRoot @('push','-q','synthetic','refs/heads/main:refs/heads/main','refs/heads/dev:refs/heads/dev')

  $policy=[pscustomobject][ordered]@{pull_request_required=$true;linear_history_required=$true;non_fast_forward_blocked=$true;deletion_blocked=$true;bypass_actor_count=0;squash_merge_enabled=$true;required_status_checks=@('verification-gate','branch-policy')}
  $candidateRef='refs/heads/candidate/mir42-a08-rehearsal'
  $plan=New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $testRoot -MainRef refs/heads/main -SourceRef refs/heads/dev -CandidateRef $candidateRef -EffectivePolicy $policy
  if([string]$plan.main_before.commit-cne$mainBefore-or[string]$plan.source.commit-cne$source-or[int]$plan.reconciliation.main_unique_commit_count-ne1-or[int]$plan.reconciliation.patch_equivalent_main_commit_count-ne1-or-not[bool]$plan.reconciliation.all_main_changes_integrated){throw '[mir4-a08-plan-contract]'}

  foreach($field in @('main_mutation_authority','tag_creation_authority','release_authority','publication_authority')) {
    $forged=$plan|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30;$forged.$field=$true;$forged.plan_sha256=Get-MIR4A08PlanSha256 $forged
    Expect-A08Failure {Assert-MIR4A08Plan $forged} '[mir4-a08-plan-invalid]'
  }
  $forgedDeletion=$plan|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30;$forgedDeletion.promotion.deletion_authorized=$true;$forgedDeletion.plan_sha256=Get-MIR4A08PlanSha256 $forgedDeletion
  Expect-A08Failure {Assert-MIR4A08Plan $forgedDeletion} '[mir4-a08-plan-invalid]'
  $forgedUnknown=$plan|ConvertTo-Json -Depth 30|ConvertFrom-Json -Depth 30;$forgedUnknown|Add-Member -NotePropertyName main_mutation_authority_override -NotePropertyValue $true;$forgedUnknown.plan_sha256=Get-MIR4A08PlanSha256 $forgedUnknown
  Expect-A08Failure {Assert-MIR4A08Plan $forgedUnknown} '[mir4-a08-plan-invalid]'
  $badPolicy=$policy|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badPolicy.linear_history_required=$false
  Expect-A08Failure {New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $testRoot -MainRef refs/heads/main -SourceRef refs/heads/dev -CandidateRef refs/heads/candidate/mir42-a08-policy -EffectivePolicy $badPolicy} '[mir4-a08-policy-incompatible]'

  $candidate=New-MIR4ProtectedMainCandidate -RepoRoot $testRoot -Plan $plan
  $adoptedCandidate=New-MIR4ProtectedMainCandidate -RepoRoot $testRoot -Plan $plan
  if(-not[bool]$candidate.created-or[bool]$adoptedCandidate.created-or[string]$candidate.commit-cne[string]$adoptedCandidate.commit-or[string]$candidate.parent_commit-cne$mainBefore){throw '[mir4-a08-candidate-recovery]'}
  $conflictRef='refs/heads/candidate/mir42-a08-conflict'
  $conflictPlan=New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $testRoot -MainRef refs/heads/main -SourceRef refs/heads/dev -CandidateRef $conflictRef -EffectivePolicy $policy
  $null=Invoke-A08Git $testRoot @('update-ref',$conflictRef,$base,('0'*40))
  Expect-A08Failure {New-MIR4ProtectedMainCandidate -RepoRoot $testRoot -Plan $conflictPlan} '[mir4-a08-candidate-ref-conflict]'

  New-A08Zip -Path (Join-Path $packageRoot 'F200.zip') -Target 'F200' -Payload '{"target":"F200"}'
  New-A08Zip -Path (Join-Path $packageRoot 'F210.zip') -Target 'F210' -Payload '{"target":"F210"}'
  $observed=@(
    (Get-MIR4A08PackageObservation -PackagePath (Join-Path $packageRoot 'F200.zip') -Target 'F200' -RelativePath 'F200.zip')
    (Get-MIR4A08PackageObservation -PackagePath (Join-Path $packageRoot 'F210.zip') -Target 'F210' -RelativePath 'F210.zip')
  )
  $qualificationRecord=[pscustomobject][ordered]@{schema=1;kind='MIR42ProtectedMainQualificationV1';status='independently-qualified';candidate=[pscustomobject][ordered]@{ref=$candidate.ref;commit=$candidate.commit;tree=$candidate.tree};packages=$observed;release_authority=$false;publication_authority=$false}
  $qualificationPath=Join-Path $testRoot 'qualification.json';Write-A08Json $qualificationPath $qualificationRecord
  if(-not((Get-Content -Raw -LiteralPath $qualificationPath)|Test-Json -SchemaFile $qualificationSchemaPath)){throw '[mir4-a08-qualification-schema]'}
  $qualificationSha=Get-MIR4A08FileSha256 $qualificationPath
  $f200Bytes=[IO.File]::ReadAllBytes((Join-Path $packageRoot 'F200.zip'))

  $null=Invoke-A08Git $remoteRoot @('update-ref','refs/heads/dev',$base,$source)
  Expect-A08Failure {New-MIR4A08PromotionIntention -RepoRoot $testRoot -Plan $plan -Candidate $candidate -QualificationRecordPath $qualificationPath -TrustedQualificationRecordSha256 $qualificationSha -PackageRoot $packageRoot -Remote $remoteRoot -RemoteMainRef refs/heads/main -RemoteSourceRef refs/heads/dev -StateRoot $stateRoot} '[mir4-a08-remote-source-ref-drift]'
  $null=Invoke-A08Git $remoteRoot @('update-ref','refs/heads/dev',$source,$base)
  Expect-A08Failure {New-MIR4A08PromotionIntention -RepoRoot $testRoot -Plan $plan -Candidate $candidate -QualificationRecordPath $qualificationPath -TrustedQualificationRecordSha256 ('A'*64) -PackageRoot $packageRoot -Remote $remoteRoot -RemoteMainRef refs/heads/main -RemoteSourceRef refs/heads/dev -StateRoot $stateRoot} '[mir4-a08-qualification-record-hash]'
  $intent=New-MIR4A08PromotionIntention -RepoRoot $testRoot -Plan $plan -Candidate $candidate -QualificationRecordPath $qualificationPath -TrustedQualificationRecordSha256 $qualificationSha -PackageRoot $packageRoot -Remote $remoteRoot -RemoteMainRef refs/heads/main -RemoteSourceRef refs/heads/dev -StateRoot $stateRoot
  $resumedIntent=New-MIR4A08PromotionIntention -RepoRoot $testRoot -Plan $plan -Candidate $candidate -QualificationRecordPath $qualificationPath -TrustedQualificationRecordSha256 $qualificationSha -PackageRoot $packageRoot -Remote $remoteRoot -RemoteMainRef refs/heads/main -RemoteSourceRef refs/heads/dev -StateRoot $stateRoot
  if($intent.path-cne$resumedIntent.path-or-not(Test-Path -LiteralPath $intent.path)){throw '[mir4-a08-intention-persistence]'}
  $tamperedIntentPath=Join-Path $stateRoot 'tampered-intention.json';[IO.File]::WriteAllText($tamperedIntentPath,((Get-Content -Raw -LiteralPath $intent.path)-replace $candidate.commit,$base),[Text.UTF8Encoding]::new($false))
  Expect-A08Failure {Invoke-MIR4A08CreateOnlyCandidatePush -RepoRoot $testRoot -IntentionPath $tamperedIntentPath -StateRoot $stateRoot} '[mir4-a08-intention-invalid]'

  $push=Invoke-MIR4A08CreateOnlyCandidatePush -RepoRoot $testRoot -IntentionPath $intent.path -StateRoot $stateRoot
  $resumedPush=Invoke-MIR4A08CreateOnlyCandidatePush -RepoRoot $testRoot -IntentionPath $intent.path -StateRoot $stateRoot
  if(-not[bool]$push.created-or[bool]$resumedPush.created-or[string]$push.remote_candidate_commit-cne[string]$candidate.commit){throw '[mir4-a08-create-only-resume]'}
  $null=Invoke-A08Git $remoteRoot @('update-ref',$candidateRef,$base,$candidate.commit)
  Expect-A08Failure {Invoke-MIR4A08CreateOnlyCandidatePush -RepoRoot $testRoot -IntentionPath $intent.path -StateRoot $stateRoot} '[mir4-a08-remote-candidate-conflict]'
  $null=Invoke-A08Git $remoteRoot @('update-ref',$candidateRef,$candidate.commit,$base)

  $request=New-MIR4A08ProtectedPromotionRequest -RepoRoot $testRoot -IntentionPath $intent.path -StateRoot $stateRoot
  $resumedRequest=New-MIR4A08ProtectedPromotionRequest -RepoRoot $testRoot -IntentionPath $intent.path -StateRoot $stateRoot
  if($request.path-cne$resumedRequest.path-or-not[bool]$request.protected_pr_required){throw '[mir4-a08-pr-request-persistence]'}
  $intentionValue=Read-MIR4A08Intention $intent.path
  $wrongMessageMain=((Invoke-A08Git $testRoot @('commit-tree',$candidate.tree,'-p',$mainBefore,'-m','unbound squash result'))-join'').Trim()
  $null=Invoke-A08Git $testRoot @('push','-q','synthetic',"$($wrongMessageMain):refs/heads/a08-objects/wrong-message")
  $null=Invoke-A08Git $remoteRoot @('update-ref','refs/heads/main',$wrongMessageMain,$mainBefore)
  Expect-A08Failure {Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intent.path -PromotionRequestPath $request.path -StateRoot $stateRoot} '[mir4-a08-readback-message-mismatch]'
  $finalMain=((Invoke-A08Git $testRoot @('commit-tree',$candidate.tree,'-p',$mainBefore,'-m',(Get-MIR4A08PromotionMessage $intentionValue)))-join'').Trim()
  $null=Invoke-A08Git $testRoot @('push','-q','synthetic',"$($finalMain):refs/heads/a08-objects/final")
  $null=Invoke-A08Git $remoteRoot @('update-ref','refs/heads/main',$finalMain,$wrongMessageMain)
  [IO.File]::WriteAllBytes((Join-Path $packageRoot 'F200.zip'),[Text.Encoding]::UTF8.GetBytes('not a zip'))
  Expect-A08Failure {Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intent.path -PromotionRequestPath $request.path -StateRoot $stateRoot} '[mir4-a08-package-archive]'
  [IO.File]::WriteAllBytes((Join-Path $packageRoot 'F200.zip'),$f200Bytes)
  $readback=Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intent.path -PromotionRequestPath $request.path -StateRoot $stateRoot
  $resumedReadback=Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intent.path -PromotionRequestPath $request.path -StateRoot $stateRoot
  if([string]$readback.status-cne'qualified-tree-on-main-awaiting-maintainer-playtest'-or-not[bool]$readback.commit_rewritten-or[string]$readback.main_after-cne$finalMain-or$readback.path-cne$resumedReadback.path-or-not(Test-Path -LiteralPath $readback.path)){throw '[mir4-a08-readback-contract]'}

  $intervening=((Invoke-A08Git $testRoot @('commit-tree',$candidate.tree,'-p',$finalMain,'-m',(Get-MIR4A08PromotionMessage $intentionValue)))-join'').Trim()
  $null=Invoke-A08Git $testRoot @('push','-q','synthetic',"$($intervening):refs/heads/a08-objects/intervening")
  $null=Invoke-A08Git $remoteRoot @('update-ref','refs/heads/main',$intervening,$finalMain)
  Expect-A08Failure {Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intent.path -PromotionRequestPath $request.path -StateRoot $stateRoot} '[mir4-a08-readback-not-direct-main-child]'
  $null=Invoke-A08Git $remoteRoot @('update-ref','refs/heads/main',$finalMain,$intervening)
  $null=Invoke-A08Git $remoteRoot @('update-ref','refs/heads/dev',$base,$source)
  Expect-A08Failure {Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -IntentionPath $intent.path -PromotionRequestPath $request.path -StateRoot $stateRoot} '[mir4-a08-remote-source-ref-drift-after-promotion]'
  $null=Invoke-A08Git $remoteRoot @('update-ref','refs/heads/dev',$source,$base)
  if(@(Invoke-A08Git $testRoot @('tag','--list')).Count-ne0-or@(Invoke-A08Git $remoteRoot @('tag','--list')).Count-ne0){throw '[mir4-a08-tag-created]'}
  Write-Host '[ok] A08 binds a hashed independent qualification record to exact candidate/package bytes, persists pre-effect intent and PR request, create-only pushes to a synthetic remote, and accepts only exact direct protected-squash readback without main/tag/publication effects.'
} finally {
  if(Test-Path -LiteralPath $testRoot){
    Get-ChildItem -LiteralPath $testRoot -Force -Recurse | ForEach-Object {
      if(($_.Attributes -band [IO.FileAttributes]::ReadOnly)-ne0){$_.Attributes=$_.Attributes-band(-bnot[IO.FileAttributes]::ReadOnly)}
    }
    [IO.Directory]::Delete($testRoot,$true)
  }
}
