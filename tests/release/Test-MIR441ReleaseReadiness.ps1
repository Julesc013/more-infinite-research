# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,[switch]$ResourceRecoveryOnly)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
function Test-MIR441ResourceRecovery {
  . (Join-Path $repo 'tools/mir/application/release/readiness/ResourceGovernor.ps1')
  $actual=Get-MIR441ResourceSnapshot -WorkRoot (Join-Path $repo 'build/tmp')
  if($actual.memory.commit_limit_bytes-le0-or$actual.memory.committed_bytes-le0-or$actual.memory.free_bytes-le0){throw 'Native physical/commit readings unavailable'}
  $root=Join-Path $repo ('build/tmp/mir441-recovery-fixture-'+[guid]::NewGuid().ToString('N'))
  $policy=[pscustomobject]@{minimum_free_ram_gib=4}
  $script:RecoveryFault='';$script:RecoveryChildPid=Join-Path $root 'child.pid'
  function Get-MIR441ResourceSnapshot {
    param([string]$WorkRoot)
    if($script:RecoveryFault-eq'monitor'-and(Test-Path -LiteralPath $script:RecoveryChildPid)){throw 'simulated-monitor-failure'}
    $snapshot=[pscustomobject]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');memory=[pscustomobject]@{total_bytes=16GB;free_bytes=12GB;committed_bytes=4GB;commit_limit_bytes=20GB};system_volume=[pscustomobject]@{free_bytes=100GB};work_volume=[pscustomobject]@{free_bytes=100GB}}
    switch($script:RecoveryFault){'physical'{$snapshot.memory.free_bytes=4GB};'commit'{$snapshot.memory.committed_bytes=16GB};'disk'{$snapshot.system_volume.free_bytes=20GB};'work'{$snapshot.work_volume.free_bytes=20GB};'runtime-commit'{if(Test-Path -LiteralPath $script:RecoveryChildPid){$snapshot.memory.committed_bytes=19GB}}}
    return $snapshot
  }
  function Write-MIR441Json {
    param($Value,[string]$Path,[switch]$Append)
    [IO.File]::AppendAllText($Path,($Value|ConvertTo-Json -Depth 8 -Compress)+[Environment]::NewLine)
  }
  function Refuses([scriptblock]$Action,[string]$Expected){
    $caught='';try{&$Action|Out-Null}catch{$caught=$_.Exception.Message}
    if($caught-notmatch[regex]::Escape($Expected)){throw "Expected $Expected, got $caught"}
  }
  foreach($case in @(@('physical','memory'),@('commit','commit'),@('disk','system-disk'),@('work','work-disk'))){
    $script:RecoveryFault=$case[0]
    Refuses {Assert-MIR441ResourceAdmission -Policy $policy -WorkRoot $root -EstimatedPeakBytes 1MB -ExpectedPeakMemoryBytes 1MB} ('resource-admission-'+$case[1])
    if(Test-Path -LiteralPath $root){throw 'Admission allocated output before refusing'}
  }
  $script:RecoveryFault=''
  Refuses {Resolve-MIR441RecoveryScratchPath -Path (Join-Path $repo 'build/tmp-other/escape')} 'resource-output-root'
  Refuses {Resolve-MIR441RecoveryScratchPath -Path 'D:\MIR-RECOVERY-OUTSIDE'} 'resource-output-root'
  Refuses {Assert-MIR441ResourceAdmission -Policy $policy -WorkRoot $root -EstimatedPeakBytes 3GB} 'resource-staging-budget'
  $pwsh=(Get-Command pwsh).Source
  $invoke=@{FilePath=$pwsh;Arguments=@('-NoProfile','-Command','Write-Output $env:TEMP');WorkRoot=$root;LedgerPath=(Join-Path $root 'ledger.jsonl');Policy=$policy;EstimatedPeakBytes=1MB;ExpectedPeakMemoryBytes=1GB;TimeoutSeconds=12;StdoutPath=(Join-Path $root 'stdout.txt');StderrPath=(Join-Path $root 'stderr.txt')}
  Refuses {Invoke-MIR441MonitoredProcess -FilePath $pwsh -Arguments @('-NoProfile','-Command','exit') -WorkRoot $root -LedgerPath $invoke.LedgerPath -Policy $policy} 'resource-peak-budget-required'
  New-Item -ItemType Directory -Path $root|Out-Null
  $originalTemp=$env:TEMP;$originalTmp=$env:TMP
  try{
    $lockPath=Join-Path $repo 'build/tmp/mir-heavy.lock'
    $held=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{Refuses {Invoke-MIR441MonitoredProcess @invoke} 'resource-heavy-job-active'}finally{$held.Dispose()}
    $passed=Invoke-MIR441MonitoredProcess @invoke
    $jobTemp=[IO.File]::ReadAllText($invoke.StdoutPath).Trim()
    if(-not$passed.passed-or-not$jobTemp.StartsWith($root+'\')-or(Test-Path -LiteralPath $jobTemp)){throw 'Per-job temp isolation or post-run cleanup failed'}
    if($env:TEMP-cne$originalTemp-or$env:TMP-cne$originalTmp){throw 'Global temp environment changed'}
    $parent=Join-Path $root 'parent.ps1'
    $parentText=@'
$child=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-Command','Start-Sleep -Seconds 20') -WindowStyle Hidden -PassThru
[IO.File]::WriteAllText('__CHILD_PID__',[string]$child.Id)
Start-Sleep -Seconds 20
'@
    [IO.File]::WriteAllText($parent,$parentText.Replace('__CHILD_PID__',$script:RecoveryChildPid))
    $invoke.Arguments=@('-NoProfile','-File',$parent)
    foreach($fault in @('runtime-commit','monitor')){
      Remove-Item -LiteralPath $script:RecoveryChildPid -Force -ErrorAction SilentlyContinue
      $script:RecoveryFault=$fault
      $expected=if($fault-eq'monitor'){'simulated-monitor-failure'}else{'resource-admission-commit'}
      Refuses {Invoke-MIR441MonitoredProcess @invoke} $expected
      $childId=[int][IO.File]::ReadAllText($script:RecoveryChildPid)
      if(Get-Process -Id $childId -ErrorAction SilentlyContinue){throw 'Owned child survived cancellation'}
      if(@(Get-ChildItem -LiteralPath $root -Directory -Filter 'temp-*').Count){throw 'Cancelled job left temporary output'}
      $last=Get-Content -LiteralPath $invoke.LedgerPath -Tail 1|ConvertFrom-Json
      if($last.phase-cne'interrupted'){throw 'Interrupted job was not recorded as interrupted'}
    }
    $script:RecoveryFault=''
    . (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
    $config=Join-Path $root 'factorio.ini'
    [IO.File]::WriteAllText($config,"[path]`nwrite-data=D:\MIR-RECOVERY-OUTSIDE`n")
    Refuses {Invoke-MIRCompatFactorioProcess -FactorioBin $pwsh -ArgumentList @('--config',$config) -StdoutPath $invoke.StdoutPath -StderrPath $invoke.StderrPath -TimeoutSeconds 12 -EstimatedPeakBytes 1MB -ExpectedPeakMemoryBytes 1GB} 'resource-output-root'
    Refuses {Invoke-MIRCompatFactorioProcess -FactorioBin $pwsh -ArgumentList @('--config',$config,'--config',$config) -StdoutPath $invoke.StdoutPath -StderrPath $invoke.StderrPath -TimeoutSeconds 12 -EstimatedPeakBytes 1MB -ExpectedPeakMemoryBytes 1GB} 'resource-factorio-duplicate-output-argument'
    $link=Join-Path $root 'outside-link'
    New-Item -ItemType Junction -Path $link -Target $repo|Out-Null
    try{Refuses {Resolve-MIR441RecoveryScratchPath -Path (Join-Path $link 'README.md')} 'resource-output-reparse'}finally{Remove-Item -LiteralPath $link -Force}
  }finally{
    $null=Resolve-MIR441RecoveryScratchPath -Path $root
    Remove-Item -LiteralPath $root -Recurse -Force
  }
  [pscustomobject]@{status='MIR441-RESOURCE-RECOVERY-TESTS-PASSED';thresholds=4;out_of_root=$true;serialization=$true;child_cancellation=$true;monitor_failure_cancellation=$true;temp_cleanup=$true;real_disk_fill=$false;real_memory_exhaustion=$false;memory_enforcement='sampled-watchdog-not-hard-cap'}
}
if($ResourceRecoveryOnly){Test-MIR441ResourceRecovery;return}
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/mir/application/release/MIR441ReleaseReadiness.ps1')

function Assert-MIR441Test([bool]$Condition,[string]$Code){if(-not$Condition){throw "[$Code]"}}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$contract=Get-MIR441ReleaseReadinessContract -RepoRoot $repo
$check=Test-MIR441ReleaseReadinessContract -RepoRoot $repo
Assert-MIR441Test ([string]$check.status-ceq'MIR-4.1-RELEASE-READINESS-HISTORICAL-SUCCESSOR-CONTRACT-PASSED'-and[bool]$check.historical_contract-and-not[bool]$check.private_build_authorized-and-not[bool]$check.technical_seal_authorized-and-not[bool]$check.exact_main_promotion_authorized-and-not[bool]$check.tagging_authorized-and-not[bool]$check.publication_authorized) 'mir441-contract-gates'
Assert-MIR441Test ([bool]$contract.historical_transition_gate.private_build-and[bool]$contract.historical_transition_gate.technical_seal-and[bool]$contract.historical_transition_gate.promotion-and-not[bool]$contract.historical_transition_gate.tagging-and-not[bool]$contract.historical_transition_gate.publication) 'mir441-historical-contract-gates'
Assert-MIR441Test ((@($contract.targets.distribution_version)-join'|')-ceq'4.1.21000|4.1.20000|4.1.11000|4.1.10000') 'mir441-target-versions'
Assert-MIR441Test (@($contract.targets|Where-Object qualification_role -eq 'technical-required').Count-eq4) 'mir441-four-target-technical-role'
Assert-MIR441Test (@($contract.targets|Where-Object publication_role -eq 'primary').Count-eq2-and@($contract.targets|Where-Object publication_role -eq 'supplemental-lts').Count-eq2) 'mir441-publication-role'
Assert-MIR441Test ([string]$contract.package_source.current_sha256-ceq'0DEDF851B388D8523110A2ABEDB3A7B2091E1CC119944F5EA7D4C1E7C01698DA'-and[string]$contract.package_source.predecessor_sha256-ceq'0DEDF851B388D8523110A2ABEDB3A7B2091E1CC119944F5EA7D4C1E7C01698DA'-and[string]$contract.composable_source_successor.current_package_source_sha256-ceq$packageBefore) 'mir441-package-source-succession'
foreach($operation in @('private_build','qualification','technical_seal','promotion')){
  try{Assert-MIR441CurrentReleaseOperationAuthorized -Contract $contract -Operation $operation;throw "[mir441-current-operation-open] $operation"}catch{Assert-MIR441Test ($_.Exception.Message-match'mir441-current-release-operation-not-authorized') "mir441-current-operation-closed-$operation"}
}

$modules=@('Common.ps1','Contract.ps1','ComposableSourceSuccession.ps1','ResourceGovernor.ps1','CandidateBuild.ps1','QualificationResume.ps1','Qualification.ps1','IndependentVerification.ps1','TechnicalSeal.ps1','Promotion.ps1')
foreach($name in $modules){$path=Join-Path $repo "tools/mir/application/release/readiness/$name";$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors);Assert-MIR441Test ($errors.Count-eq0) "mir441-module-syntax-$name";Assert-MIR441Test (([IO.File]::ReadAllLines($path).Count)-le260) "mir441-module-bound-$name"}

$resourceText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/release/readiness/ResourceGovernor.ps1'))
$commonText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/release/readiness/Common.ps1'))
$buildText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/release/readiness/CandidateBuild.ps1'))
$materializerText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1'))
$promotionText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/release/readiness/Promotion.ps1'))
$qualificationText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/release/readiness/Qualification.ps1'))
$resumeText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/release/readiness/QualificationResume.ps1'))
$compilerFixtureText=[IO.File]::ReadAllText((Join-Path $repo 'fixtures/assert-compiler-contracts/data-final-fixes.lua'))
$f210UpgradeData=[IO.File]::ReadAllText((Join-Path $repo 'fixtures/assert-upgrade-4-0-21000-to-4-1-21000/data.lua'))
$f210UpgradeSettings=[IO.File]::ReadAllText((Join-Path $repo 'fixtures/assert-upgrade-4-0-21000-to-4-1-21000/settings-updates.lua'))
$releaseNarrativeText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/release/ReleaseNarratives.ps1'))
$technicalSealText=[IO.File]::ReadAllText((Join-Path $repo 'tools/mir/application/release/readiness/TechnicalSeal.ps1'))
$releaseNarrativePlan=Get-Content -Raw -LiteralPath (Join-Path $repo 'releases/governance/MIR4-Source-Changelog-PlanV1.json')|ConvertFrom-Json -Depth 100
$acceptedChangePaths=@(Get-ChildItem -LiteralPath (Join-Path $repo 'changes/unreleased') -Filter '*.json' -File|ForEach-Object{
  $record=Get-Content -Raw -LiteralPath $_.FullName|ConvertFrom-Json -Depth 100
  if([string]$record.status-ceq'accepted'){[IO.Path]::GetRelativePath($repo,$_.FullName).Replace('\','/')}
}|Sort-Object)
Assert-MIR441Test ($resourceText-match'EnumerateFileSystemInfos'-and$resourceText-match'Write-MIR441Json'-and$resourceText-match'commit_limit_bytes'-and$commonText-match'AppendAllText'-and$commonText-match'Assert-MIR441CleanTrackedSource') 'mir441-streaming-resource-governor'
Assert-MIR441Test ($buildText-notmatch'ForEach-Object\s+-Parallel|Start-Job|Start-ThreadJob'-and$buildText-match'foreach\(\$target') 'mir441-serial-materializer'
Assert-MIR441Test ($commonText-match'merge-base --is-ancestor'-and$buildText-match'Assert-MIR441MainAncestor') 'mir441-main-ancestry-before-candidate-build'
Assert-MIR441Test ($buildText-match"-SourceVersion '4[.]1[.]0'"-and$materializerText-match'\$info[.]version\s*=\s*\[string\]\$identity[.]distribution_version') 'mir441-candidate-version-materialized-from-intent'
Assert-MIR441Test ($promotionText-match'fast_forward=\$true'-and$promotionText-match'finally\s*\{'-and$promotionText-match'post_promotion_tests=\$false'-and$promotionText-notmatch'--force|reset --hard') 'mir441-exact-promotion-boundary'
Assert-MIR441Test ($qualificationText-match'fresh-\$slug[.]checkpoint[.]json'-and$qualificationText-match'Get-MIR441ValidatedTargetCheckpoint'-and$resumeText-match'MIR441FreshQualificationCheckpointV1'-and$resumeText-match'MIR441UpgradeQualificationCheckpointV1'-and$resumeText-match'mir441-qualification-resume'-and$resumeText-match'validation_harness_git_dirty') 'mir441-exact-resumable-qualification'
Assert-MIR441Test ($compilerFixtureText-match'\^4%[.]\[01\]%[.]%d\+\$'-and$compilerFixtureText-notmatch'\^4%[.]0%[.]%d\+\$') 'mir441-compiler-contract-package-succession'
Assert-MIR441Test ($f210UpgradeData-match'mir-fixture-assert-upgrade-4-0-21000-to-4-1-21000'-and$f210UpgradeData-notmatch'mir-fixture-assert-upgrade-3-2-11-to-4-0-21000') 'mir441-upgrade-fixture-current-applicability'
Assert-MIR441Test ($f210UpgradeSettings-match'missing 4[.]0[.]21000 to 4[.]1[.]21000 upgrade setting'-and$f210UpgradeSettings-notmatch'missing 3[.]2[.]11 to 4[.]0[.]21000 upgrade setting') 'mir441-upgrade-fixture-current-diagnostic'
Assert-MIR441Test (-not(Test-MIR441ForbiddenPackageRelativePath -Path 'prototypes/mir/domain/evidence/compiler_evidence.lua')) 'mir441-package-membership-nested-evidence-allowed'
Assert-MIR441Test (Test-MIR441ForbiddenPackageRelativePath -Path 'evidence/internal.json') 'mir441-package-membership-top-evidence-rejected'
Assert-MIR441Test (Test-MIR441ForbiddenPackageRelativePath -Path 'docs/maintainer/internal.md') 'mir441-package-membership-top-docs-rejected'
Assert-MIR441Test (-not(Test-MIR441ForbiddenPackageRelativePath -Path 'prototypes/docs.lua')) 'mir441-package-membership-file-name-allowed'
Assert-MIR441Test ($releaseNarrativeText-match'PackageIdentity[.]ps1'-and$releaseNarrativeText-match'CanonicalJsonV1[.]ps1'-and$releaseNarrativeText-match'Get-MIR4CanonicalDigestV1') 'mir441-release-narrative-self-contained-dependencies'
Assert-MIR441Test ((@($releaseNarrativePlan.change_fragments|Sort-Object)-join'|')-ceq($acceptedChangePaths-join'|')) 'mir441-release-narrative-complete-accepted-inventory'
Assert-MIR441Test ($technicalSealText-match'Get-MIR441PublicEngineIdentity'-and$technicalSealText-match'targets=@\(\$publicTargetRows\)'-and$technicalSealText-match'outputs=@\(\$publicTargetRows\)') 'mir441-public-release-metadata-redacted'

$external=Assert-MIR441ExternalRoot -RepoRoot $repo -Path 'E:\MIR-READINESS-TEST' -Name test
Assert-MIR441Test ($external-ceq'E:\MIR-READINESS-TEST') 'mir441-external-root-positive'
try{Assert-MIR441ExternalRoot -RepoRoot $repo -Path (Join-Path $repo 'build/test') -Name invalid|Out-Null;throw '[mir441-external-root-negative-missed]'}catch{Assert-MIR441Test ($_.Exception.Message-match'mir441-external-root-repository') 'mir441-external-root-negative'}
Assert-MIR441Test (Test-MIR441PathContained -Root 'E:\MIR-READINESS-TEST' -Path 'E:\MIR-READINESS-TEST\child') 'mir441-containment-positive'
Assert-MIR441Test (-not(Test-MIR441PathContained -Root 'E:\MIR-READINESS-TEST' -Path 'E:\MIR-READINESS-TEST-OTHER\child')) 'mir441-containment-prefix-rejection'
$rulesetA=[pscustomobject][ordered]@{name='synthetic';target='branch';enforcement='active';bypass_actors=@();conditions=[pscustomobject]@{ref_name=[pscustomobject]@{include=@('refs/heads/main');exclude=@()}};rules=@([pscustomobject]@{type='pull_request'},[pscustomobject]@{type='required_linear_history'})}
$rulesetB=[pscustomobject][ordered]@{name=$rulesetA.name;target=$rulesetA.target;enforcement=$rulesetA.enforcement;bypass_actors=@();conditions=$rulesetA.conditions;rules=@($rulesetA.rules[1],$rulesetA.rules[0])}
$rulesPayloadA=ConvertTo-MIR441CanonicalJson -Value (ConvertTo-MIR441RulesetPayload -Ruleset $rulesetA) -Compress;$rulesPayloadB=ConvertTo-MIR441CanonicalJson -Value (ConvertTo-MIR441RulesetPayload -Ruleset $rulesetB) -Compress
Assert-MIR441Test ($rulesPayloadA-ceq$rulesPayloadB-and@((ConvertTo-MIR441RulesetPayload -Ruleset $rulesetA -WithoutPullRequest).rules).Count-eq1) 'mir441-ruleset-order-normalization'

$resumeRoot=Join-Path ([IO.Path]::GetTempPath()) ('mir441-resume-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $resumeRoot|Out-Null
try{
  $resumeSource=[pscustomobject]@{commit=('a'*40);tree=('b'*40)}
  $resumeEngine=[pscustomobject]@{version='2.1.17';binary_sha256=('C'*64)}
  $resumeCandidate=[pscustomobject]@{asset=[pscustomobject]@{sha256=('D'*64);bytes=10;path='candidate.zip'};content_sha256=('E'*64);entry_count=3}
  $summaryPath=Join-Path $resumeRoot 'fresh.json'
  Write-MIR441Json -Path $summaryPath -Value ([ordered]@{status='passed';git_commit=$resumeSource.commit;package_source_git_dirty=$false;validation_harness_git_dirty=$false;factorio_binary_version=$resumeEngine.version;validation_package_sha256=$resumeCandidate.asset.sha256;validation_package_content_sha256=$resumeCandidate.content_sha256})
  $summaryIdentity=Get-MIR441FileIdentity -Path $summaryPath -RelativePath 'fresh.json'
  $freshResult=[pscustomobject][ordered]@{name='synthetic';status='passed';assertions=1;duration_seconds=0.1;process_peak_working_set_bytes=1;evidence=$summaryIdentity}
  $freshCheckpoint=Join-Path $resumeRoot 'fresh.checkpoint.json'
  Write-MIR441FreshCheckpoint -Path $freshCheckpoint -Name 'synthetic' -Source $resumeSource -Engine $resumeEngine -Candidate $resumeCandidate -SummaryIdentity $summaryIdentity -Result $freshResult|Out-Null
  $fresh=Get-MIR441ValidatedFreshCheckpoint -Path $freshCheckpoint -SummaryPath $summaryPath -Name 'synthetic' -Source $resumeSource -Engine $resumeEngine -Candidate $resumeCandidate
  Assert-MIR441Test ([string]$fresh.result.status-ceq'passed') 'mir441-resume-fresh-positive'
  try{Get-MIR441ValidatedFreshCheckpoint -Path $freshCheckpoint -SummaryPath $summaryPath -Name 'synthetic' -Source $resumeSource -Engine ([pscustomobject]@{version='2.1.18';binary_sha256=$resumeEngine.binary_sha256}) -Candidate $resumeCandidate|Out-Null;throw '[mir441-resume-fresh-negative-missed]'}catch{Assert-MIR441Test ($_.Exception.Message-match'mir441-qualification-resume-fresh') 'mir441-resume-fresh-negative'}
  $upgradePath=Join-Path $resumeRoot 'upgrade.json'
  Write-MIR441Json -Path $upgradePath -Value ([ordered]@{status='passed';rows=@([ordered]@{status='passed'});expanded_roots_retained=0})
  $upgradeIdentity=Get-MIR441FileIdentity -Path $upgradePath -RelativePath 'upgrade-matrix.json'
  $upgradeResult=[pscustomobject][ordered]@{fixture='synthetic';archetypes=@('base-default');first_reload=$true;second_reload=$true;evidence=$upgradeIdentity;process_peak_working_set_bytes=1}
  $upgradeCheckpoint=Join-Path $resumeRoot 'upgrade.checkpoint.json'
  Write-MIR441UpgradeCheckpoint -Path $upgradeCheckpoint -Source $resumeSource -Engine $resumeEngine -Candidate $resumeCandidate -PredecessorSha256 ('F'*64) -SummaryIdentity $upgradeIdentity -Result $upgradeResult -DurationSeconds 0.2|Out-Null
  $upgrade=Get-MIR441ValidatedUpgradeCheckpoint -Path $upgradeCheckpoint -SummaryPath $upgradePath -Source $resumeSource -Engine $resumeEngine -Candidate $resumeCandidate -PredecessorSha256 ('F'*64)
  Assert-MIR441Test ([bool]$upgrade.result.first_reload-and[bool]$upgrade.result.second_reload) 'mir441-resume-upgrade-positive'
}finally{if(Test-Path -LiteralPath $resumeRoot){Remove-Item -LiteralPath $resumeRoot -Recurse -Force}}

foreach($script in @(@{name='prepare';text=Get-MIR441PrepareTagScriptText},@{name='playtest';text=Get-MIR441PlaytestScriptText},@{name='finalize';text=Get-MIR441FinalizeScriptText})){$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput([string]$script.text,[ref]$tokens,[ref]$errors);Assert-MIR441Test ($errors.Count-eq0) "mir441-generated-$([string]$script.name)-syntax"}
$tagScript=Get-MIR441PrepareTagScriptText;$finalizer=Get-MIR441FinalizeScriptText
$publicEngine=Get-MIR441PublicEngineIdentity -Engine ([pscustomobject][ordered]@{path='C:\private\factorio.exe';version='2.1.17';binary_sha256=('A'*64);api_version='2.0'})
Assert-MIR441Test (-not($publicEngine.PSObject.Properties.Name-ccontains'path')-and[string]$publicEngine.version-ceq'2.1.17'-and[string]$publicEngine.binary_sha256-ceq('A'*64)) 'mir441-public-engine-identity-excludes-local-path'
Assert-MIR441Test ($tagScript-match' tag -s '-and$tagScript-match'verify-tag'-and$tagScript-notmatch'push origin') 'mir441-signed-tag-prepared-not-pushed'
Assert-MIR441Test ($finalizer-match'--verify-tag'-and$finalizer-match'--draft'-and$finalizer-match'release download'-and$finalizer-notmatch'Invoke-MIRValidation|New-MIR4TargetPackage|candidate-build|qualification') 'mir441-finalizer-publisher-cannot-build'
Assert-MIR441Test ($finalizer-match'manifest_asset[.]label'-and$finalizer-match'github_assets\)[.]Count\+1'-and$finalizer-match'mir441-final-public-manifest-byte') 'mir441-finalizer-publishes-and-verifies-manifest'

& (Join-Path $repo 'tools/commands/mir4/Update-MIR441UpgradeFixtures.ps1') -RepoRoot $repo -Check|Out-Null
# The 4.1 presentation receipt remains a historical package claim.  Its
# source paths were deliberately retired by the governed V2 composition
# cutover, so current release readiness is anchored by the successor record
# rather than attempting to regenerate the frozen receipt against V2 paths.
& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M41ToM42ComposableSourceSuccessionAuthority.ps1') -RepoRoot $repo -Check|Out-Null
$source=Update-MIR4SourceChangelogV1 -RepoRoot $repo -PlanPath 'releases/governance/MIR4-Source-Changelog-PlanV1.json' -Check
Assert-MIR441Test ([string]$source.status-ceq'current') 'mir441-source-changelog-current'
$cli=& (Join-Path $repo 'tools/mir.ps1') mir4 release-engine readiness-check 2>&1|Out-String
Assert-MIR441Test ($cli-match'MIR-4.1-RELEASE-READINESS-HISTORICAL-SUCCESSOR-PASSED') 'mir441-public-cli'
Assert-MIR441Test ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir441-test-package-noninterference'

Test-MIR441ResourceRecovery|Out-Null
[pscustomobject][ordered]@{status='MIR-4.1-RELEASE-READINESS-STATIC-PROOF-PASSED';module_count=$modules.Count;targets=4;publisher_can_build=$false;package_source_sha256=$packageBefore}
