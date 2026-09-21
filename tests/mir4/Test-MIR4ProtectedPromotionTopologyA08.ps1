# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $repo 'tools/lib/mir4/pre-freeze-release/ProtectedPromotionTopology.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

# The routed command is a read-only preflight and must reject an absent
# candidate ref before it can contact GitHub or construct local candidate state.
$dispatchPath=Join-Path $repo 'tools/commands/mir4/Invoke-MIR4PreFreeze.ps1'
$dispatchOutput=@(& pwsh -NoProfile -File $dispatchPath -Command protected-promotion-a08-preflight -RepoRoot $repo 2>&1|ForEach-Object{[string]$_})
if ($LASTEXITCODE-eq0-or($dispatchOutput-join"`n")-notmatch'requires --candidate-ref') { throw '[mir4-a08-dispatch-candidate-gate]' }

function Expect-A08Failure {
  param([scriptblock]$Action,[string]$Code)
  try { & $Action | Out-Null } catch { if ($_.Exception.Message.StartsWith($Code,[StringComparison]::Ordinal)) { return }; throw }
  throw "Expected A08 failure: $Code"
}
function Invoke-A08Git {
  param([string]$Root,[string[]]$Arguments)
  $output=@(& git -C $Root -c commit.gpgSign=false @Arguments 2>&1)
  if ($LASTEXITCODE-ne0){throw "synthetic git failure: $($Arguments-join' ') :: $($output-join' ')"};return @($output)
}
function Write-A08Json { param([string]$Path,$Value) [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false)) }
function New-A08Zip {
  param([string]$Path,[string]$Target,[string]$Marker='')
  $version=Get-MIR4A08ExpectedFactorioVersion $Target
  if (Test-Path -LiteralPath $Path) { [IO.File]::Delete($Path) }
  $archive=[IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Create)
  try {
    $entry=$archive.CreateEntry("more-infinite-research_4.2.$Target/info.json");$writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false));try{$writer.Write((@{name='more-infinite-research';version='4.2.0';factorio_version=$version}|ConvertTo-Json -Compress))}finally{$writer.Dispose()}
    if (-not[string]::IsNullOrEmpty($Marker)) {$markerEntry=$archive.CreateEntry("more-infinite-research_4.2.$Target/marker.txt");$writer=[IO.StreamWriter]::new($markerEntry.Open(),[Text.UTF8Encoding]::new($false));try{$writer.Write($Marker)}finally{$writer.Dispose()}}
  } finally {$archive.Dispose()}
}
function New-A08Policy {
  param([int]$RulesetId=20833408,[bool]$Enabled=$true)
  $value=[pscustomobject][ordered]@{schema=1;kind='MIR42GitHubMainPolicyObservationV1';observation_source='synthetic-github-readonly-v1';repository='Julesc013/more-infinite-research';canonical_remote_url='synthetic://Julesc013/more-infinite-research';main_ref='refs/heads/main';observed_at='2026-09-15T00:00:00Z';ruleset=[pscustomobject][ordered]@{id=$RulesetId;enforcement=$(if ($Enabled){'active'}else{'disabled'});pull_request_required=$Enabled;linear_history_required=$Enabled;non_fast_forward_blocked=$Enabled;deletion_blocked=$Enabled;bypass_actor_count=0;required_status_checks=@('branch-policy','verification-gate')};protection=[pscustomobject][ordered]@{observed=$Enabled;squash_merge_enabled=$Enabled};policy_sha256=''};$value.policy_sha256=Get-MIR4A08PolicySha256 $value;return $value
}
function New-A08TargetAuthority {
  param($Candidate,[string]$Target)
  $issuer="synthetic-target-qualification-$Target"
  return [pscustomobject][ordered]@{kind='MIR4GovernedTargetQualificationAuthorityV2';issuer_id=$issuer;trust_policy='validation/trust.json';producer=[pscustomobject][ordered]@{repository='Julesc013/more-infinite-research';workflow='synthetic-target-qualification';run_id="synthetic-$Target";run_attempt='1';job=$issuer;actor='synthetic';workflow_commit=[string]$Candidate.commit;workflow_ref='refs/heads/main';source_commit=[string]$Candidate.commit;source_tree=[string]$Candidate.tree;target=$Target;factorio_version=(Get-MIR4A08ExpectedFactorioVersion $Target);event='synthetic-merge';environment='synthetic';runner_identity='synthetic';trust_class='synthetic-protected-release';verifier_sha256=('E'*64);policy_sha256=('F'*64)}}
}
function New-A08TargetProof {
  param($Observation,[string]$Target)
  return [pscustomobject][ordered]@{
    context=[pscustomobject][ordered]@{id=('A'*64);release='4.2.0';candidate_id="synthetic-$Target";plan_id=('B'*64);manifest_sha256=('C'*64);candidate_descriptor_sha256=('D'*64);environment_locks_sha256=('E'*64)}
    package=[pscustomobject][ordered]@{archive_sha256=[string]$Observation.archive_sha256;content_sha256=[string]$Observation.content_sha256;bytes=[long]$Observation.bytes;entry_count=[int]$Observation.entry_count;source_sha256=('F'*64)}
    engine=[pscustomobject][ordered]@{version=$(if($Target-ceq'F200'){'2.0.77'}else{'2.1.18'});installation_sha256=('1'*64);binary_sha256=('2'*64);binary_bytes=1;official_data_sha256=('3'*64);official_data_file_count=1}
    evidence=[pscustomobject][ordered]@{qualification_manifest_sha256=('4'*64);aggregate_result_sha256=('5'*64);worker_import_sha256=('6'*64);seal_result_sha256=('7'*64);promotion_result_sha256=('8'*64);seal_object_sha256=('9'*64);seal_task_object_sha256=('A'*64);promotion_task_object_sha256=('B'*64)}
  }
}
function New-A08Qualification {
  param([string]$Root,$Candidate)
  $presentationPath='spec/distribution/mir4-current-package-presentation-v6.json'
  $manifestPath='source/package-source.json'
  $authorityRecordPath='targets/package-authority.json'
  $presentation=Read-MIR4A08CommitJson -RepoRoot $testRoot -Commit $Candidate.commit -Path $presentationPath -Code '[mir4-a08-test-presentation]'
  $manifest=Read-MIR4A08CommitJson -RepoRoot $testRoot -Commit $Candidate.commit -Path $manifestPath -Code '[mir4-a08-test-presentation]'
  $packageAuthority=Read-MIR4A08CommitJson -RepoRoot $testRoot -Commit $Candidate.commit -Path $authorityRecordPath -Code '[mir4-a08-test-presentation]'
  $observed=@((Get-MIR4A08PackageObservation -PackagePath (Join-Path $Root 'F200.zip') -Target F200 -RelativePath F200.zip),(Get-MIR4A08PackageObservation -PackagePath (Join-Path $Root 'F210.zip') -Target F210 -RelativePath F210.zip))
  $rows=@(foreach ($item in $observed){[pscustomobject][ordered]@{target=[string]$item.target;distribution_version=$(if ($item.target-ceq'F200'){'4.2.20000'}else{'4.2.21000'});relative_path=[string]$item.relative_path;archive_sha256=[string]$item.archive_sha256;content_sha256=[string]$item.content_sha256;bytes=[long]$item.bytes;entry_count=[int]$item.entry_count;root=[string]$item.root;factorio_version=[string]$item.factorio_version;authority=(New-A08TargetAuthority -Candidate $Candidate -Target $item.target);proof=(New-A08TargetProof -Observation $item -Target $item.target)}})
  $record=[pscustomobject][ordered]@{
    schema=1
    kind='MIR42ProtectedMainQualificationBindingV4'
    status='independently-qualified'
    candidate=[pscustomobject][ordered]@{ref=$Candidate.ref;commit=$Candidate.commit;tree=$Candidate.tree}
    materializer=[pscustomobject][ordered]@{path='tools/mir/application/package/TargetMaterializer.ps1';git_blob=(Resolve-MIR4A08Blob -RepoRoot $testRoot -Commit $Candidate.commit -Path 'tools/mir/application/package/TargetMaterializer.ps1')}
    package_presentation=[pscustomobject][ordered]@{
      path=$presentationPath
      kind=[string]$presentation.kind
      git_blob=(Resolve-MIR4A08Blob -RepoRoot $testRoot -Commit $Candidate.commit -Path $presentationPath)
      record_sha256=[string]$presentation.record_sha256
      package_source_fingerprint_sha256=[string]$presentation.package_source.fingerprint_sha256
      source_manifest=[pscustomobject][ordered]@{path=$manifestPath;kind=[string]$manifest.kind;git_blob=(Resolve-MIR4A08Blob -RepoRoot $testRoot -Commit $Candidate.commit -Path $manifestPath);record_sha256=[string]$manifest.record_sha256}
      package_authority=[pscustomobject][ordered]@{path=$authorityRecordPath;kind=[string]$packageAuthority.kind;git_blob=(Resolve-MIR4A08Blob -RepoRoot $testRoot -Commit $Candidate.commit -Path $authorityRecordPath);record_sha256=[string]$packageAuthority.record_sha256}
    }
    expected_targets=@('F200','F210')
    targets=$rows
    release_authority=$false
    publication_authority=$false
    record_sha256=''
  }
  $record.record_sha256=Get-MIR4A08SelfSha256 $record 'record_sha256'
  return $record
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
  $singleRule=[pscustomobject][ordered]@{type='pull_request'}
  Expect-A08Failure {Get-MIR4A08EffectiveRule -Rules @([pscustomobject][ordered]@{type='deletion'}) -Type 'pull_request'} '[mir4-a08-policy-rule]'
  Expect-A08Failure {Get-MIR4A08EffectiveRule -Rules @($singleRule,$singleRule) -Type 'pull_request'} '[mir4-a08-policy-rule]'
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
  New-A08Zip -Path (Join-Path $packageRoot 'F200.zip') -Target F200
  New-A08Zip -Path (Join-Path $packageRoot 'F210.zip') -Target F210
  $f200Presentation=Get-MIR4A08PackageObservation -PackagePath (Join-Path $packageRoot 'F200.zip') -Target F200 -RelativePath F200.zip
  $f210Presentation=Get-MIR4A08PackageObservation -PackagePath (Join-Path $packageRoot 'F210.zip') -Target F210 -RelativePath F210.zip
  $manifest=[pscustomobject][ordered]@{schema=2;kind='MIR4ComposablePackageSourceV2';record_sha256=''}
  $manifest.record_sha256=Get-MIR4A08SelfSha256 $manifest 'record_sha256'
  $packageAuthority=[pscustomobject][ordered]@{schema=2;kind='MIR4CanonicalPackageAuthorityV2';record_sha256=''}
  $packageAuthority.record_sha256=Get-MIR4A08SelfSha256 $packageAuthority 'record_sha256'
  $compositionRecords=[ordered]@{}
  foreach ($target in @('f210','f200','f110','f100')) {$composition=[pscustomobject][ordered]@{schema=2;kind='MIR4TargetCompositionV2';target=$target;record_sha256=''};$composition.record_sha256=Get-MIR4A08SelfSha256 $composition 'record_sha256';$compositionRecords[$target]=$composition}
  New-Item -ItemType Directory -Force -Path (Join-Path $testRoot 'source'),(Join-Path $testRoot 'targets'),(Join-Path $testRoot 'spec/distribution'),(Join-Path $testRoot 'tools/mir/application/package')|Out-Null
  Write-A08Json (Join-Path $testRoot 'source/package-source.json') $manifest
  Write-A08Json (Join-Path $testRoot 'targets/package-authority.json') $packageAuthority
  foreach ($target in $compositionRecords.Keys) {New-Item -ItemType Directory -Force -Path (Join-Path $testRoot "targets/$target")|Out-Null;Write-A08Json (Join-Path $testRoot "targets/$target/composition.json") $compositionRecords[$target]}
  $syntheticPackageSourceFingerprint=Get-MIRPackageSourceFingerprint -RepoRoot $testRoot
  $presentation=[pscustomobject][ordered]@{
    schema=1
    kind='MIR4CurrentPackagePresentationV6'
    package_source=[pscustomobject][ordered]@{fingerprint_sha256=$syntheticPackageSourceFingerprint;materializer_abi='mir4-target-materializer/1';roots=@('source','targets');sole_writer='tools/mir/application/package/TargetMaterializer.ps1';legacy_root_state='retired-historical-read-only'}
    source_manifest=[pscustomobject][ordered]@{record_sha256=$manifest.record_sha256}
    package_authority=[pscustomobject][ordered]@{record_sha256=$packageAuthority.record_sha256}
    target_compositions=@($compositionRecords.Keys|ForEach-Object{[pscustomobject][ordered]@{target=$_;path="targets/$_/composition.json";record_sha256=$compositionRecords[$_].record_sha256}})
    target_content_identities=@(
      [pscustomobject][ordered]@{target='f210';content_sha256=$f210Presentation.content_sha256;entry_count=$f210Presentation.entry_count},
      [pscustomobject][ordered]@{target='f200';content_sha256=$f200Presentation.content_sha256;entry_count=$f200Presentation.entry_count}
    )
    authority_invariants=[pscustomobject][ordered]@{current_package_contract_bound=$true;promotion_authorized=$false}
    transition_gate=[pscustomobject][ordered]@{main_promotion=$false}
    record_sha256=''
  }
  $presentation.record_sha256=Get-MIR4A08SelfSha256 $presentation 'record_sha256'
  Write-A08Json (Join-Path $testRoot 'spec/distribution/mir4-current-package-presentation-v6.json') $presentation
  [IO.File]::WriteAllText((Join-Path $testRoot 'README.md'),"base`n",[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText((Join-Path $testRoot 'tools/mir/application/package/TargetMaterializer.ps1'),"# synthetic materializer`n",[Text.UTF8Encoding]::new($false));$null=Invoke-A08Git $testRoot @('add','.');$null=Invoke-A08Git $testRoot @('commit','-q','-m','base');$base=((Invoke-A08Git $testRoot @('rev-parse','HEAD'))-join'').Trim()
  $null=Invoke-A08Git $testRoot @('switch','-q','-c','dev',$base);[IO.File]::AppendAllText((Join-Path $testRoot 'README.md'),"stable repair`n",[Text.UTF8Encoding]::new($false));$null=Invoke-A08Git $testRoot @('add','README.md');$null=Invoke-A08Git $testRoot @('commit','-q','-m','forward-port stable repair');$null=Invoke-A08Git $testRoot @('switch','-q','main');[IO.File]::AppendAllText((Join-Path $testRoot 'README.md'),"stable repair`n",[Text.UTF8Encoding]::new($false));$null=Invoke-A08Git $testRoot @('add','README.md');$null=Invoke-A08Git $testRoot @('commit','-q','-m','stable repair');$mainBefore=((Invoke-A08Git $testRoot @('rev-parse','HEAD'))-join'').Trim();$null=Invoke-A08Git $testRoot @('switch','-q','dev');[IO.File]::WriteAllText((Join-Path $testRoot 'feature.txt'),"qualified feature tree`n",[Text.UTF8Encoding]::new($false));$null=Invoke-A08Git $testRoot @('add','feature.txt');$null=Invoke-A08Git $testRoot @('commit','-q','-m','qualified feature');$source=((Invoke-A08Git $testRoot @('rev-parse','HEAD'))-join'').Trim()
  $null=Invoke-A08Git $testRoot @('init','-q','--bare',$remoteRoot);$null=Invoke-A08Git $testRoot @('remote','add','synthetic',$remoteRoot);$null=Invoke-A08Git $testRoot @('push','-q','synthetic','refs/heads/main:refs/heads/main','refs/heads/dev:refs/heads/dev')
  $script:policyState=New-A08Policy;$policyProvider={param($Repository,$Branch) return $script:policyState};$candidateRef='refs/heads/candidate/mir42-a08-rehearsal';$null=Invoke-A08Git $testRoot @('branch','side',$source);Expect-A08Failure {New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $testRoot -MainRef refs/heads/main -SourceRef refs/heads/side -CandidateRef $candidateRef -PolicyProvider $policyProvider -Rehearsal} '[mir4-a08-source-ref-authority]';$plan=New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $testRoot -MainRef refs/heads/main -SourceRef refs/heads/dev -CandidateRef $candidateRef -PolicyProvider $policyProvider -Rehearsal
  if ([string]$plan.main_before.commit-cne$mainBefore-or[string]$plan.source.commit-cne$source-or[string]$plan.policy.repository-cne'Julesc013/more-infinite-research'-or-not[bool]$plan.qualification.exact_package_presentation_required-or-not[bool]$plan.qualification.exact_source_manifest_identity_required-or-not[bool]$plan.qualification.exact_package_authority_identity_required){throw '[mir4-a08-plan-contract]'}
  foreach ($field in @('main_mutation_authority','tag_creation_authority','release_authority','publication_authority')){$forged=$plan|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$forged.$field=$true;$forged.plan_sha256=Get-MIR4A08PlanSha256 $forged;Expect-A08Failure {Assert-MIR4A08Plan $forged} '[mir4-a08-plan-invalid]'}
  $forged=$plan|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$forged.promotion.deletion_authorized=$true;$forged.plan_sha256=Get-MIR4A08PlanSha256 $forged;Expect-A08Failure {Assert-MIR4A08Plan $forged} '[mir4-a08-plan-invalid]';$script:policyState=New-A08Policy -Enabled:$false;Expect-A08Failure {New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $testRoot -MainRef refs/heads/main -SourceRef refs/heads/dev -CandidateRef refs/heads/candidate/mir42-a08-policy -PolicyProvider $policyProvider -Rehearsal} '[mir4-a08-policy-incompatible]';$script:policyState=New-A08Policy
  Expect-A08Failure {New-MIR4ProtectedMainCandidate -RepoRoot $testRoot -Plan $plan} '[mir4-a08-external-effect-not-authorized]';if($null-ne(Get-MIR4A08OptionalRef -RepoRoot $testRoot -Ref $candidateRef)){throw '[mir4-a08-production-candidate-allocation]'};$candidate=New-MIR4ProtectedMainCandidate -RepoRoot $testRoot -Plan $plan -Rehearsal;$adopted=New-MIR4ProtectedMainCandidate -RepoRoot $testRoot -Plan $plan;if (-not[bool]$candidate.created-or[bool]$adopted.created-or[string]$candidate.commit-cne[string]$adopted.commit){throw '[mir4-a08-candidate-recovery]'}
  $qualification=New-A08Qualification -Root $packageRoot -Candidate $candidate;$qualificationPath=Join-Path $testRoot 'qualification.json';Write-A08Json $qualificationPath $qualification;if (-not((Get-Content -Raw -LiteralPath $qualificationPath)|Test-Json -SchemaFile $qualificationSchema)){throw '[mir4-a08-qualification-schema]'}
  $null=Invoke-A08Git $testRoot @('switch','-q','-c','stale-package-source',$source);$staleManifest=Get-Content -Raw -LiteralPath (Join-Path $testRoot 'source/package-source.json')|ConvertFrom-Json -Depth 100;$staleManifest|Add-Member marker 'changed-after-presentation';$staleManifest.record_sha256=Get-MIR4A08SelfSha256 $staleManifest 'record_sha256';Write-A08Json (Join-Path $testRoot 'source/package-source.json') $staleManifest;$stalePresentation=Get-Content -Raw -LiteralPath (Join-Path $testRoot 'spec/distribution/mir4-current-package-presentation-v6.json')|ConvertFrom-Json -Depth 100;$stalePresentation.source_manifest.record_sha256=$staleManifest.record_sha256;$stalePresentation.record_sha256=Get-MIR4A08SelfSha256 $stalePresentation 'record_sha256';Write-A08Json (Join-Path $testRoot 'spec/distribution/mir4-current-package-presentation-v6.json') $stalePresentation;$null=Invoke-A08Git $testRoot @('add','source/package-source.json','spec/distribution/mir4-current-package-presentation-v6.json');$null=Invoke-A08Git $testRoot @('commit','-q','-m','stale package source fingerprint');$staleCommit=((Invoke-A08Git $testRoot @('rev-parse','HEAD'))-join'').Trim();$staleTree=((Invoke-A08Git $testRoot @('rev-parse','HEAD^{tree}'))-join'').Trim();$null=Invoke-A08Git $testRoot @('switch','-q','dev');$staleCandidate=[pscustomobject][ordered]@{ref=$candidate.ref;commit=$staleCommit;tree=$staleTree};$staleQualification=New-A08Qualification -Root $packageRoot -Candidate $staleCandidate;$staleQualificationPath=Join-Path $testRoot 'stale-package-source.json';Write-A08Json $staleQualificationPath $staleQualification;Expect-A08Failure {Read-MIR4A08QualificationRecord -RepoRoot $testRoot -Plan $plan -Candidate $staleCandidate -RecordPath $staleQualificationPath -PackageRoot $packageRoot -Rehearsal} '[mir4-a08-package-presentation]'
  $selfIssued=$qualification|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$selfIssued.targets[0].authority.issuer_id='forged-target-authority';$selfIssued.record_sha256=Get-MIR4A08SelfSha256 $selfIssued 'record_sha256';$selfIssuedPath=Join-Path $testRoot 'self-issued.json';Write-A08Json $selfIssuedPath $selfIssued;Expect-A08Failure {Read-MIR4A08QualificationRecord -RepoRoot $testRoot -Plan $plan -Candidate $candidate -RecordPath $selfIssuedPath -PackageRoot $packageRoot -Rehearsal} '[mir4-a08-qualification-authority]'
  $badEngine=$qualification|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badEngine.targets[0].proof.engine.binary_sha256='not-a-sha256';$badEngine.record_sha256=Get-MIR4A08SelfSha256 $badEngine 'record_sha256';$badEnginePath=Join-Path $testRoot 'bad-engine.json';Write-A08Json $badEnginePath $badEngine;Expect-A08Failure {Read-MIR4A08QualificationRecord -RepoRoot $testRoot -Plan $plan -Candidate $candidate -RecordPath $badEnginePath -PackageRoot $packageRoot -Rehearsal} '[mir4-a08-qualification-record]'
  $differentEngine=$qualification|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$differentEngine.targets[0].proof.engine.version='2.1';$differentEngine.record_sha256=Get-MIR4A08SelfSha256 $differentEngine 'record_sha256';$differentEnginePath=Join-Path $testRoot 'different-engine.json';Write-A08Json $differentEnginePath $differentEngine;Expect-A08Failure {Read-MIR4A08QualificationRecord -RepoRoot $testRoot -Plan $plan -Candidate $candidate -RecordPath $differentEnginePath -PackageRoot $packageRoot -Rehearsal} '[mir4-a08-qualification-record]'
  Expect-A08Failure {Assert-MIR4A08ExactEngineVersion -Target F210 -Version '2.1.17'} '[mir4-a08-qualification-record]';Assert-MIR4A08ExactEngineVersion -Target F210 -Version '2.1.18'
  $badPresentation=$qualification|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$badPresentation.package_presentation.source_manifest.record_sha256=('0'*64);$badPresentation.record_sha256=Get-MIR4A08SelfSha256 $badPresentation 'record_sha256';$badPresentationPath=Join-Path $testRoot 'bad-presentation.json';Write-A08Json $badPresentationPath $badPresentation;Expect-A08Failure {Read-MIR4A08QualificationRecord -RepoRoot $testRoot -Plan $plan -Candidate $candidate -RecordPath $badPresentationPath -PackageRoot $packageRoot -Rehearsal} '[mir4-a08-package-presentation]'
  $f200Bytes=[IO.File]::ReadAllBytes((Join-Path $packageRoot 'F200.zip'));$f210Bytes=[IO.File]::ReadAllBytes((Join-Path $packageRoot 'F210.zip'));[IO.File]::WriteAllBytes((Join-Path $packageRoot 'F210.zip'),$f200Bytes);Expect-A08Failure {Read-MIR4A08QualificationRecord -RepoRoot $testRoot -Plan $plan -Candidate $candidate -RecordPath $qualificationPath -PackageRoot $packageRoot -Rehearsal} '[mir4-a08-package-target-identity]';[IO.File]::WriteAllBytes((Join-Path $packageRoot 'F210.zip'),$f210Bytes)
  New-A08Zip -Path (Join-Path $packageRoot 'F210.zip') -Target F210 -Marker 'different-valid-content';$presentationMismatch=New-A08Qualification -Root $packageRoot -Candidate $candidate;$presentationMismatchPath=Join-Path $testRoot 'presentation-target-mismatch.json';Write-A08Json $presentationMismatchPath $presentationMismatch;Expect-A08Failure {Read-MIR4A08QualificationRecord -RepoRoot $testRoot -Plan $plan -Candidate $candidate -RecordPath $presentationMismatchPath -PackageRoot $packageRoot -Rehearsal} '[mir4-a08-package-presentation-target-mismatch]';[IO.File]::WriteAllBytes((Join-Path $packageRoot 'F210.zip'),$f210Bytes);$qualification=New-A08Qualification -Root $packageRoot -Candidate $candidate;Write-A08Json $qualificationPath $qualification
  $productionAuthority=$qualification.targets[0].authority|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100
  $productionAuthority.issuer_id='verification-gate';$productionAuthority.producer.workflow='MIR Control Plane v5';$productionAuthority.producer.run_id='123';$productionAuthority.producer.run_attempt='1';$productionAuthority.producer.job='verification-gate';$productionAuthority.producer.actor='synthetic';$productionAuthority.producer.workflow_commit=$source;$productionAuthority.producer.workflow_ref='refs/heads/dev';$productionAuthority.producer.source_commit=[string]$candidate.commit;$productionAuthority.producer.source_tree=[string]$candidate.tree;$productionAuthority.producer.target='F200';$productionAuthority.producer.factorio_version='2.0';$productionAuthority.producer.event='workflow_dispatch';$productionAuthority.producer.environment='release-candidate';$productionAuthority.producer.runner_identity='self-hosted-windows';$productionAuthority.producer.trust_class='protected-release';$productionAuthority.producer.policy_sha256=Get-MIR4A08FileSha256 (Join-Path $repo 'validation/trust.json')
  $oldEnvironment=@{};foreach($name in @('A08_RUN_JSON','A08_JOBS_JSON','A08_ARTIFACTS_JSON','A08_ATTESTATION_JSON')){$oldEnvironment[$name]=[Environment]::GetEnvironmentVariable($name)}
  $goodRun=[pscustomobject][ordered]@{id=123;name='MIR Control Plane v5';event='workflow_dispatch';head_sha=$source;head_branch='dev';run_attempt=1;status='completed';conclusion='success';actor=[pscustomobject]@{login='synthetic'}}
  $goodJobs=[pscustomobject]@{jobs=@([pscustomobject][ordered]@{name='MIR / verification-gate';status='completed';conclusion='success';runner_name='synthetic-runner';labels=@('self-hosted','Windows')})}
  $artifactName='mir-v5-target-qualification-2.0-123-attempt-1';$goodArtifacts=[pscustomobject]@{total_count=1;artifacts=@([pscustomobject][ordered]@{id=42;name=$artifactName;size_in_bytes=1024;expired=$false;workflow_run=[pscustomobject]@{id=123}})}
  $targetProof=$qualification.targets[0].proof
  $goodAttestation=[pscustomobject][ordered]@{schema=1;kind='MIR4TargetQualificationAttestationV1';repository='Julesc013/more-infinite-research';workflow='MIR Control Plane v5';workflow_run_id='123';workflow_run_attempt='1';workflow_job='verification-gate';workflow_ref='refs/heads/dev';workflow_commit=$source;source_ref=[string]$candidate.commit;source_commit=[string]$candidate.commit;source_tree=[string]$candidate.tree;target='F200';factorio_version='2.0';context=$targetProof.context;package=$targetProof.package;engine=$targetProof.engine;evidence=$targetProof.evidence}
  $env:A08_RUN_JSON=$goodRun|ConvertTo-Json -Depth 10 -Compress;$env:A08_JOBS_JSON=$goodJobs|ConvertTo-Json -Depth 10 -Compress;$env:A08_ARTIFACTS_JSON=$goodArtifacts|ConvertTo-Json -Depth 10 -Compress;$env:A08_ATTESTATION_JSON=$goodAttestation|ConvertTo-Json -Depth 10 -Compress
  $fakeGh=Join-Path $testRoot 'fake-gh.cmd';[IO.File]::WriteAllText($fakeGh,@'
@echo off
if "%~1"=="run" (
  if not exist "%~9" mkdir "%~9"
  >"%~9\target-qualification-attestation.json" echo %A08_ATTESTATION_JSON%
  exit /b 0
)
echo %* | %SystemRoot%\System32\findstr.exe /C:"/jobs" >nul
if not errorlevel 1 (
  echo %A08_JOBS_JSON%
  exit /b 0
)
echo %* | %SystemRoot%\System32\findstr.exe /C:"/artifacts" >nul
if not errorlevel 1 (
  echo %A08_ARTIFACTS_JSON%
  exit /b 0
)
echo %A08_RUN_JSON%
'@,[Text.UTF8Encoding]::new($false))
  $qualificationProvider=New-MIR4A08GitHubRestQualificationAuthorityProvider -GhExecutable $fakeGh;$null=Assert-MIR4A08TrustedIssuer -Authority $productionAuthority -Candidate $candidate -Target F200 -CanonicalRepository 'Julesc013/more-infinite-research' -QualificationAuthorityProvider $qualificationProvider
  # protected-release currently permits main as a general trust-class ref, but
  # A08 attestations must prove the workflow implementation came from the
  # exact frozen dev source, not merely any allowed controller branch.
  $trustedButWrongController=$productionAuthority|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$trustedButWrongController.producer.workflow_ref='refs/heads/main';$trustedButWrongController.producer.workflow_commit=$mainBefore;Expect-A08Failure {Assert-MIR4A08TrustedIssuer -Authority $trustedButWrongController -Candidate $candidate -Target F200 -CanonicalRepository 'Julesc013/more-infinite-research' -QualificationAuthorityProvider $qualificationProvider} '[mir4-a08-qualification-authority]'
  $productionAuthority.producer.run_id='124';Expect-A08Failure {Assert-MIR4A08TrustedIssuer -Authority $productionAuthority -Candidate $candidate -Target F200 -CanonicalRepository 'Julesc013/more-infinite-research' -QualificationAuthorityProvider $qualificationProvider} '[mir4-a08-qualification-authority-provider]';$productionAuthority.producer.run_id='123'
  $badRunner=$goodJobs|ConvertTo-Json -Depth 10|ConvertFrom-Json -Depth 10;$badRunner.jobs[0].labels=@('Windows');$env:A08_JOBS_JSON=$badRunner|ConvertTo-Json -Depth 10 -Compress;Expect-A08Failure {Assert-MIR4A08TrustedIssuer -Authority $productionAuthority -Candidate $candidate -Target F200 -CanonicalRepository 'Julesc013/more-infinite-research' -QualificationAuthorityProvider $qualificationProvider} '[mir4-a08-qualification-authority-provider]';$env:A08_JOBS_JSON=$goodJobs|ConvertTo-Json -Depth 10 -Compress
  $badRef=$goodRun|ConvertTo-Json -Depth 10|ConvertFrom-Json -Depth 10;$badRef.head_branch='side';$env:A08_RUN_JSON=$badRef|ConvertTo-Json -Depth 10 -Compress;Expect-A08Failure {Assert-MIR4A08TrustedIssuer -Authority $productionAuthority -Candidate $candidate -Target F200 -CanonicalRepository 'Julesc013/more-infinite-research' -QualificationAuthorityProvider $qualificationProvider} '[mir4-a08-qualification-authority-provider]';$env:A08_RUN_JSON=$goodRun|ConvertTo-Json -Depth 10 -Compress
  $badSource=$goodAttestation|ConvertTo-Json -Depth 10|ConvertFrom-Json -Depth 10;$badSource.source_commit=('0'*40);$env:A08_ATTESTATION_JSON=$badSource|ConvertTo-Json -Depth 10 -Compress;Expect-A08Failure {Assert-MIR4A08TrustedIssuer -Authority $productionAuthority -Candidate $candidate -Target F200 -CanonicalRepository 'Julesc013/more-infinite-research' -QualificationAuthorityProvider $qualificationProvider} '[mir4-a08-qualification-authority-provider]';$env:A08_ATTESTATION_JSON=$goodAttestation|ConvertTo-Json -Depth 10 -Compress
  $providerObservation=[pscustomobject][ordered]@{run_id='123';run_attempt='1';workflow='MIR Control Plane v5';event='workflow_dispatch';actor='synthetic';workflow_commit=$source;workflow_ref='refs/heads/dev';source_commit=[string]$candidate.commit;source_tree=[string]$candidate.tree;job='MIR / verification-gate';runner_name='synthetic-runner';runner_identity='self-hosted-windows';target_attestation_artifact=$artifactName;attestation=$goodAttestation}
  $changedEvidence=$qualification.targets[0]|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$changedEvidence.proof.evidence.aggregate_result_sha256=('0'*64);Expect-A08Failure {Assert-MIR4A08TargetQualificationProof -Row $changedEvidence -Candidate $candidate -Observed $f200Presentation -AuthorityObservation $providerObservation} '[mir4-a08-qualification-authority-provider]'
  $changedPackage=$qualification.targets[0]|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$changedPackage.proof.package.archive_sha256=('0'*64);Expect-A08Failure {Assert-MIR4A08TargetQualificationProof -Row $changedPackage -Candidate $candidate -Observed $f200Presentation -AuthorityObservation $providerObservation} '[mir4-a08-qualification-record]'
  $forgedArtifactPackage=$goodAttestation|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$forgedArtifactPackage.package.archive_sha256=('0'*64);$forgedPackageObservation=$providerObservation|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$forgedPackageObservation.attestation=$forgedArtifactPackage;Expect-A08Failure {Assert-MIR4A08TargetQualificationProof -Row $qualification.targets[0] -Candidate $candidate -Observed $f200Presentation -AuthorityObservation $forgedPackageObservation} '[mir4-a08-qualification-authority-provider]'
  $swappedTargetAttestation=$goodAttestation|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100;$swappedTargetAttestation.target='F210';$swappedTargetAttestation.factorio_version='2.1';$env:A08_ATTESTATION_JSON=$swappedTargetAttestation|ConvertTo-Json -Depth 10 -Compress;Expect-A08Failure {Assert-MIR4A08TrustedIssuer -Authority $productionAuthority -Candidate $candidate -Target F200 -CanonicalRepository 'Julesc013/more-infinite-research' -QualificationAuthorityProvider $qualificationProvider} '[mir4-a08-qualification-authority-provider]';$env:A08_ATTESTATION_JSON=$goodAttestation|ConvertTo-Json -Depth 10 -Compress
  Expect-A08Failure {Assert-MIR4A08TrustedIssuer -Authority $productionAuthority -Candidate $candidate -Target F210 -CanonicalRepository 'Julesc013/more-infinite-research' -QualificationAuthorityProvider $qualificationProvider} '[mir4-a08-qualification-authority]'
  $missingArtifacts=[pscustomobject]@{total_count=0;artifacts=@()};$env:A08_ARTIFACTS_JSON=$missingArtifacts|ConvertTo-Json -Depth 10 -Compress;Expect-A08Failure {Assert-MIR4A08TrustedIssuer -Authority $productionAuthority -Candidate $candidate -Target F200 -CanonicalRepository 'Julesc013/more-infinite-research' -QualificationAuthorityProvider $qualificationProvider} '[mir4-a08-qualification-authority-provider]'
  $duplicateArtifacts=[pscustomobject]@{total_count=2;artifacts=@($goodArtifacts.artifacts[0],$goodArtifacts.artifacts[0])};$env:A08_ARTIFACTS_JSON=$duplicateArtifacts|ConvertTo-Json -Depth 10 -Compress;Expect-A08Failure {Assert-MIR4A08TrustedIssuer -Authority $productionAuthority -Candidate $candidate -Target F200 -CanonicalRepository 'Julesc013/more-infinite-research' -QualificationAuthorityProvider $qualificationProvider} '[mir4-a08-qualification-authority-provider]';$env:A08_ARTIFACTS_JSON=$goodArtifacts|ConvertTo-Json -Depth 10 -Compress
  foreach($name in $oldEnvironment.Keys){if($null-eq$oldEnvironment[$name]){Remove-Item "Env:$name" -ErrorAction SilentlyContinue}else{[Environment]::SetEnvironmentVariable($name,[string]$oldEnvironment[$name])}}
  Expect-A08Failure {New-MIR4A08PromotionIntention -RepoRoot $testRoot -Plan $plan -Candidate $candidate -QualificationRecordPath $qualificationPath -PackageRoot $packageRoot -RemoteName synthetic -RemoteSourceRef refs/heads/side -StateRoot $stateRoot -Rehearsal} '[mir4-a08-source-ref-authority]'
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
