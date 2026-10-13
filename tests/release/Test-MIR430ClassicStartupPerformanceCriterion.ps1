# MIR4-CONTROLLED-STATIC-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42EvidenceReconciliation.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')

function Assert-MIR430PerformanceTest {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[mir430-performance-test-$Code]" }
}

function Write-MIR430PerformanceFixtureLedger {
  param([Parameter(Mandatory)][string]$Path,[switch]$Interrupted)
  $row = if ($Interrupted) {
    [ordered]@{phase='interrupted';timed_out=$true;error='controlled timeout';peak_working_set_bytes=1;peak_sampled_private_bytes=1}
  } else {
    [ordered]@{phase='completed';exit_code=0;peak_working_set_bytes=1;peak_sampled_private_bytes=1}
  }
  [IO.File]::WriteAllText($Path,($row | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
}

function New-MIR430PerformanceFixtureObservation {
  param(
    [Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)]$Authority,[Parameter(Mandatory)]$Candidate,
    [switch]$NoGeneratedTechnology,[switch]$Interrupted,[switch]$MissingProfile,[switch]$ForgedTotal,
    [switch]$BaseOnlyRelabel,[switch]$ProfileMismatch,[switch]$SettingsMismatch,[switch]$EngineMismatch,[switch]$CandidateMismatch,
    [switch]$CandidateSourceMismatch,[switch]$ArchiveMismatch,[switch]$ExecutionControlsMismatch,[switch]$RawSettingsClaim
  )

  $profiles = [Collections.Generic.List[object]]::new()
  $clock = 1.0
  $firstInvocation = $null
  foreach ($expected in @($Authority.profiles)) {
    $target = @($Candidate.target_rows | Where-Object { [string]$_.target -ceq [string]$expected.target })[0]
    $candidateTarget = Get-MIR430PerformanceCandidateTarget -Candidate $Candidate -Target ([string]$expected.target) -Code 'mir430-test-fixture'
    $selection = @(Get-MIR430ExpectedProfileLoadedSelection -ProfileDefinition $expected.profile -CandidateTarget $candidateTarget -Authority $Authority -Code 'mir430-test-fixture')
    $archives = @(Get-MIR430ExpectedProfileArchiveSelection -ProfileDefinition $expected.profile -CandidateTarget $candidateTarget -Authority $Authority -Code 'mir430-test-fixture' | ForEach-Object {
      [ordered]@{name=[string]$_.name;version=[string]$_.version;sha256=[string]$_.sha256;builtin=[bool]$_.builtin;bytes=$(if($null -eq $_.bytes){1}else{[int64]$_.bytes})}
    })
    $relativeRoot = [string]$expected.id
    $runRelative = 'runs/candidate-4.3.0/1/changed-configuration'
    $run = Join-Path $Root (Join-Path $relativeRoot $runRelative)
    New-Item -ItemType Directory -Force -Path $run | Out-Null
    $log = Join-Path $run 'factorio.log'
    $ledger = Join-Path $run 'sample.resources.jsonl'
    $selectionPath = Join-Path $run 'selection.json'
    $configPath = Join-Path $run 'config.ini'
    $mapGenerationPath = Join-Path $run 'map-gen-settings.json'
    $readySave = Join-Path (Join-Path $run 'saves') 'startup-ready.zip'
    $resultRoot = Join-Path $Root $relativeRoot
    $rawSettingsPath = Join-Path $resultRoot 'claimed-mod-settings.dat'
    $writeData = Join-Path $resultRoot 'write-data/candidate-4.3.0'
    $engineCurrentLog = Join-Path $writeData 'factorio-current.log'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $readySave),$writeData | Out-Null
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add(('0.000 2026-10-13 00:00:00; Factorio {0} (build 1)' -f [string]$expected.profile.engine.version))
    foreach ($identity in $selection) {
      $parts = $identity.Split('@',2)
      $lines.Add(('0.010 Loading mod {0} {1} (data.lua)' -f $parts[0],$parts[1]))
    }
    $stages = [Collections.Generic.List[object]]::new()
    foreach ($stage in @($Authority.record.required_stages)) {
      $begin = $clock;$end = $clock + 0.25;$clock = $end + 0.25
      $lines.Add(('{0:F3} Script: [more-infinite-research] startup-stage={1} begin' -f $begin,$stage))
      $lines.Add(('{0:F3} Script: [more-infinite-research] startup-stage={1} end' -f $end,$stage))
      $stages.Add([ordered]@{stage=$stage;begin_seconds=$begin;end_seconds=$end;elapsed_seconds=($end-$begin)})
    }
    $lines.Add(('{0:F3} Script @__{1}__/data-final-fixes.lua:1: [MIR_ACTIVE_MODS] {2}' -f $clock,[string]$Authority.record.allowed_observer.name,($selection -join '|')))
    $lines.Add(('{0:F3} Script: [MIR430-ABLATION] actual-profile=classic' -f $clock))
    $names = if ($NoGeneratedTechnology) {'{"automation"}'} else {'{"recipe-prod-research_character_mining_speed-1", "automation"}'}
    $lines.Add(('{0:F3} Script: [MIR430-ABLATION] technology-names={1}' -f ($clock + 0.01),$names))
    [IO.File]::WriteAllLines($log,$lines,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($engineCurrentLog,(Get-Content -Raw -LiteralPath $log),[Text.UTF8Encoding]::new($false))
    Write-MIR430PerformanceFixtureLedger -Path $ledger -Interrupted:$Interrupted
    [IO.File]::WriteAllText($selectionPath,(@{mods=@($selection | ForEach-Object { $parts=$_.Split('@',2);[ordered]@{name=$parts[0];version=$parts[1];enabled=$true} })}|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($configPath,("[path]`nread-data=C:\\controlled-engine-data`nwrite-data=$writeData`n`n[other]`n"+$(if($SettingsMismatch -and [string]$expected.id -ceq 'f200-bob-angel'){'enable-new-mods=true'}else{'enable-new-mods=false'})+"`n"),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($mapGenerationPath,(@{seed=400200}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($readySave,'controlled-ready-save',[Text.UTF8Encoding]::new($false))
    if($RawSettingsClaim -and [string]$expected.id -ceq 'f200-bob-angel') { [IO.File]::WriteAllText($rawSettingsPath,'claimed but unused settings',[Text.UTF8Encoding]::new($false)) }
    if($ArchiveMismatch -and [string]$expected.id -ceq 'f200-bob-angel') { $archives[0].sha256='0'*64 }
    $executionControls=[ordered]@{
      engine_sha256=[string]$expected.profile.engine.sha256
      arguments_sha256=''
      config=[ordered]@{path='config.ini';sha256=(Get-MIR4Sha256File -Path $configPath)}
      selection=[ordered]@{path='selection.json';sha256=(Get-MIR4Sha256File -Path $selectionPath)}
      mod_settings=[ordered]@{kind='canonical-absent-default';present=$false}
      library_directory='C:\\controlled-library'
    }
    $launchArguments=@('--config',$configPath,'--mod-directory',[string]$executionControls.library_directory,'--no-log-rotation','--disable-audio','--map-gen-settings',$mapGenerationPath,'--create',$readySave)
    $executionControls.arguments_sha256=Get-MIR430PerformanceTextSha256 -Text (ConvertTo-Json -InputObject $launchArguments -Compress)
    if($ExecutionControlsMismatch -and [string]$expected.id -ceq 'f200-bob-angel') { $executionControls.arguments_sha256='0'*64 }
    $raw = [ordered]@{
      schema=1;kind='MIRDirectLibraryStartupMeasurementV1';status='completed';mode='candidate-only-stress-diagnostic';target='f200';library=[string]$executionControls.library_directory
      factorio=[ordered]@{sha256=$(if($EngineMismatch -and [string]$expected.id -ceq 'f200-bob-angel'){'0'*64}else{[string]$expected.profile.engine.sha256});base_version=[string]$expected.profile.engine.version}
      inputs=[ordered]@{candidate=[ordered]@{source_version=[string]$Candidate.source_version;archive=[ordered]@{sha256=[string]$candidateTarget.archive.sha256};materialization=[ordered]@{source_version=[string]$Candidate.source_version;archive_sha256=$(if($CandidateMismatch -and [string]$expected.id -ceq 'f200-bob-angel'){'0'*64}else{[string]$candidateTarget.archive.sha256});package_source_sha256=$(if($CandidateSourceMismatch -and [string]$expected.id -ceq 'f200-bob-angel'){'0'*64}else{[string]$Candidate.source.package_source_sha256})}}}
      endpoint_class='headless-create-diagnostic';library_controls_restored=$true
      resource_context=[ordered]@{processes=@([ordered]@{status='passed';ledger=$ledger;result=[ordered]@{passed=$true;exit_code=0}})}
      samples=@([ordered]@{label='candidate-4.3.0';sample=1;run_relative_path=$runRelative;exit_code=0;endpoint_class='headless-create-diagnostic';ready_save='saves/startup-ready.zip';map_generation=[ordered]@{seed=400200;path=([IO.Path]::GetRelativePath($resultRoot,$mapGenerationPath).Replace('\','/'));sha256=(Get-MIR4Sha256File -Path $mapGenerationPath)};loaded_selection=$selection;active_mods_observer=[ordered]@{name=[string]$Authority.record.allowed_observer.name;version=[string]$Authority.record.allowed_observer.version;sha256=[string]$Authority.record.allowed_observer.archive_sha256};loaded_archives=$archives;resource_ledger=($runRelative + '/sample.resources.jsonl');log='factorio.log';engine_current_log=([IO.Path]::GetRelativePath($resultRoot,$engineCurrentLog).Replace('\','/'));execution_controls=$executionControls})
    }
    $invocationPath = Join-Path (Join-Path $Root $relativeRoot) 'result.json'
    [IO.File]::WriteAllText($invocationPath,($raw|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
    $sample = [ordered]@{label='controlled-sample';status='completed';endpoint_class='headless-create-diagnostic';exit_code=0
      log=[ordered]@{path=($relativeRoot + '/' + $runRelative + '/factorio.log');sha256=(Get-MIR4Sha256File -Path $log)}
      resource_ledger=[ordered]@{path=($relativeRoot + '/' + $runRelative + '/sample.resources.jsonl');sha256=(Get-MIR4Sha256File -Path $ledger)}
      stages=@($stages);total_seconds=$(if($ForgedTotal){99.0}else{1.0});invocation=[ordered]@{path=($relativeRoot + '/result.json');sha256=(Get-MIR4Sha256File -Path $invocationPath);sample_label='candidate-4.3.0';sample_ordinal=1}}
    $profile = [ordered]@{
      id=[string]$expected.id;target=[string]$expected.target;definition=$expected.definition
      settings=$(if($RawSettingsClaim -and [string]$expected.id -ceq 'f200-bob-angel'){
        [ordered]@{kind='raw-sha256';path=($relativeRoot + '/claimed-mod-settings.dat');sha256=(Get-MIR4Sha256File -Path $rawSettingsPath)}
      }else{[ordered]@{kind='canonical-absent-default'}});engine=$expected.profile.engine
      candidate=[ordered]@{target=[string]$target.target;source_version=[string]$Candidate.source_version;distribution_version=[string]$target.identity.distribution_version;archive=[ordered]@{sha256=[string]$target.archive.sha256;bytes=[int64]$target.archive.bytes;content_sha256=[string]$target.archive.content_sha256;entry_count=[int]$target.archive.entry_count}}
      observer=$Authority.record.allowed_observer;samples=@($sample)
    }
    if ($BaseOnlyRelabel -and [string]$expected.id -ceq 'f200-bob-angel') {
      $profile.samples[0].log = $firstInvocation.sample.log
      $profile.samples[0].resource_ledger = $firstInvocation.sample.resource_ledger
      $profile.samples[0].invocation = $firstInvocation.sample.invocation
    }
    if ($ProfileMismatch -and [string]$expected.id -ceq 'f200-bob-angel') { $profile.samples[0].invocation.sample_label='without-mir' }
    $profiles.Add($profile)
    if ($null -eq $firstInvocation) { $firstInvocation = [pscustomobject]@{sample=$sample} }
  }
  if ($MissingProfile) { $profiles.RemoveAt($profiles.Count - 1) }
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR430ClassicStartupStressObservationV1';status='completed';source=$Candidate.source;candidate_manifest=$Candidate.candidate_manifest
    authority=[ordered]@{path=$script:MIR430EmergencyPerformanceAuthorityPath;sha256=[string]$Authority.sha256;record_sha256=[string]$Authority.record.record_sha256}
    compiler_profile='classic';profiles=@($profiles);record_sha256=''
  }
  $path = Join-Path $Root 'observation.json'
  Write-MIR4BootstrapRecord -Record $record -Path $path | Out-Null
  return $path
}

$root = Join-Path $repo ('build/test-results/mir430-performance-criterion-' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $authority = Get-MIR430EmergencyPerformanceAuthority -RepoRoot $repo
  $sealDependencies = @($script:MIR42SealVerifierDependencyPaths)
  Assert-MIR430PerformanceTest -Condition ((@(@('tools/mir/application/release/readiness/MIR42EvidenceReconciliation.ps1','governance/repository/mir430-emergency-performance-v1.json','spec/schemas/mir430-classic-startup-stress-observation-v1.schema.json','fixtures/run-profiles/mir430-startup-galore-space-age-f200.json','fixtures/assert-mir430-startup-work/data-final-fixes.lua') | Where-Object { $_ -cnotin $sealDependencies })).Count -eq 0) -Code 'technical-seal-binds-performance-inputs'
  $archive = Join-Path $root 'more-infinite-research_4.3.20000.zip'
  [IO.File]::WriteAllText($archive,'controlled archive descriptor only',[Text.UTF8Encoding]::new($false))
  $source = [pscustomobject][ordered]@{commit=('a' * 40);tree=('b' * 40);package_source_sha256=('C' * 64)}
  $candidate = [pscustomobject][ordered]@{
    source=$source;candidate_manifest=[pscustomobject][ordered]@{sha256=('D' * 64);record_sha256=('E' * 64)};source_version='4.3.0'
    target_rows=@([pscustomobject][ordered]@{target='f200';identity=[pscustomobject][ordered]@{distribution_version='4.3.20000'};archive=[pscustomobject][ordered]@{path='assets/f200.zip';sha256=(Get-MIR4Sha256File -Path $archive);bytes=[int64](Get-Item -LiteralPath $archive).Length;content_sha256=('F' * 64);entry_count=1}})
  }
  $observation = New-MIR430PerformanceFixtureObservation -Root $root -Authority $authority -Candidate $candidate
  $accepted = Assert-MIR430ClassicStartupStressObservation -RepoRoot $repo -Path $observation -Candidate $candidate -Code 'mir430-test'
  Assert-MIR430PerformanceTest -Condition ([string]$accepted.record.kind -ceq 'MIR430ClassicStartupStressObservationV1' -and @($accepted.record.profiles).Count -eq 3) -Code 'accepted-three-pinned-profiles'
  $writerAccepted = Get-MIR42CriterionEvidenceObservation -Path $observation -Criterion 'performance-telemetry' -Candidate $candidate -Code 'mir430-test-writer' -SourceVersion '4.3.0'
  Assert-MIR430PerformanceTest -Condition ([string]$writerAccepted.record_sha256 -match '^[A-F0-9]{64}$') -Code 'writer-binds-completed-native-shape'
  $sealCandidate = [pscustomobject][ordered]@{
    source=$source;identity=[pscustomobject][ordered]@{sha256=[string]$candidate.candidate_manifest.sha256;record=[pscustomobject][ordered]@{record_sha256=[string]$candidate.candidate_manifest.record_sha256}}
    targets=@([pscustomobject][ordered]@{target='f200';distribution_version='4.3.20000';archive_path=$archive;archive_sha256=[string]$candidate.target_rows[0].archive.sha256;content_sha256=[string]$candidate.target_rows[0].archive.content_sha256;entry_count=1})
  }
  $criterionPath = Join-Path $root 'seal-criterion.json'
  $criterionRecord = [pscustomobject][ordered]@{schema=1;kind='MIR42NineTargetReleaseAcceptanceCriterionEvidenceV1';status='passed';criterion='performance-telemetry';source=$source;candidate_manifest=$candidate.candidate_manifest;observed_targets=@('f200');not_applicable_targets=@();evidence=@([ordered]@{path=$observation;sha256=(Get-MIR4Sha256File -Path $observation);record_sha256=[string]$accepted.record.record_sha256});limits=[ordered]@{claim='controlled seal fixture';known_limitations='native execution is not claimed'};record_sha256=''}
  Write-MIR4BootstrapRecord -Record $criterionRecord -Path $criterionPath | Out-Null
  $originalVersionContract = (Get-Item Function:Get-MIR42SealCandidateConstructionVersionContract).ScriptBlock
  try {
    Set-Item Function:Get-MIR42SealCandidateConstructionVersionContract -Value { param($RepoRoot,$Manifest) [pscustomobject]@{source_version='4.3.0'} }
    $sealed = Get-MIR42NineTargetCriterionEvidenceRecord -Path $criterionPath -Candidate $sealCandidate
    Assert-MIR430PerformanceTest -Condition ([string]$sealed.record.criterion -ceq 'performance-telemetry') -Code 'technical-seal-reparses-performance-evidence'
    $criterionRecord.evidence[0].record_sha256='0' * 64
    Write-MIR4BootstrapRecord -Record $criterionRecord -Path $criterionPath | Out-Null
    $sealRejected=$false
    try { Get-MIR42NineTargetCriterionEvidenceRecord -Path $criterionPath -Candidate $sealCandidate | Out-Null } catch { $sealRejected=$_.Exception.Message -ceq '[mir430-seal-performance-observation-binding]' }
    Assert-MIR430PerformanceTest -Condition $sealRejected -Code 'technical-seal-rejects-rehashed-observation-claim'
  } finally {
    Set-Item Function:Get-MIR42SealCandidateConstructionVersionContract -Value $originalVersionContract
  }
  $candidateRows = @(
    foreach ($target in @($script:MIR42QualificationNineTargets)) {
      [pscustomobject][ordered]@{
        target=$target;scope='nine-target';identity=[pscustomobject][ordered]@{source_version='4.3.0';distribution_version=$(if($target -ceq 'f200'){'4.3.20000'}else{'4.3.00000'})}
        source=$source;package_source_sha256=$source.package_source_sha256;candidate_manifest=$candidate.candidate_manifest
        archive=$(if($target -ceq 'f200'){$candidate.target_rows[0].archive}else{[pscustomobject][ordered]@{path=('assets/' + $target + '.zip');sha256=('A' * 64);bytes=1;content_sha256=('B' * 64);entry_count=1}})
      }
    }
  )
  $originalRows = (Get-Item Function:Get-MIR42QualificationCandidateRows).ScriptBlock
  try {
    Set-Item Function:Get-MIR42QualificationCandidateRows -Value { param($RepoRoot,$CandidateManifestPath) return @($candidateRows) }
    $notApplicable = @{}
    foreach ($target in @($script:MIR42QualificationNineTargets | Where-Object { $_ -cne 'f200' })) { $notApplicable[$target] = 'The adopted 4.3 emergency performance authority names only F200 stress profiles.' }
    $criterion = New-MIR42NineTargetCriterionEvidence -RepoRoot $repo -CandidateManifestPath (Join-Path $root 'synthetic-candidate.json') -Criterion 'performance-telemetry' `
      -ObservationPaths @($observation) -ObservedTargets @('f200') -NotApplicableTargetReasons $notApplicable -Claim 'controlled contract fixture only' `
      -KnownLimitations 'native execution is not claimed by this fixture' -OutputPath (Join-Path $root 'criterion.json')
    Assert-MIR430PerformanceTest -Condition ([string]$criterion.criterion -ceq 'performance-telemetry' -and @($criterion.observed_targets).Count -eq 1 -and @($criterion.not_applicable_targets).Count -eq 8) -Code '430-writer-permits-named-f200-criterion'
  } finally {
    Set-Item Function:Get-MIR42QualificationCandidateRows -Value $originalRows
  }
  $contract = Get-MIR42CriterionObservationContract -Criterion 'performance-telemetry' -PublishedMaintenance -SourceVersion '4.3.0'
  Assert-MIR430PerformanceTest -Condition ($null -eq $contract) -Code '430-maintenance-allows-nine-criteria'
  $legacyRejected = $false
  try { Get-MIR42CriterionObservationContract -Criterion 'performance-telemetry' -PublishedMaintenance -SourceVersion '4.2.3' | Out-Null } catch { $legacyRejected = $_.Exception.Message -ceq '[mir42-maintenance-criterion-input-scope]' }
  Assert-MIR430PerformanceTest -Condition $legacyRejected -Code '423-maintenance-restriction-retained'
  foreach ($case in @('forged-total','missing-profile','empty-generated','interrupted-ledger','base-only-relabel','profile-mismatch','settings-mismatch','engine-mismatch','candidate-mismatch','candidate-source-mismatch','archive-mismatch','execution-controls-mismatch','raw-settings-claim')) {
    $args = @{Root=$root;Authority=$authority;Candidate=$candidate}
    switch ($case) {
      'forged-total' { $args.ForgedTotal=$true; $expected='total-claim' }
      'missing-profile' { $args.MissingProfile=$true; $expected='schema' }
      'empty-generated' { $args.NoGeneratedTechnology=$true; $expected='generated-technology-count' }
      'interrupted-ledger' { $args.Interrupted=$true; $expected='mir430-performance-resource-ledger-incomplete' }
      'base-only-relabel' { $args.BaseOnlyRelabel=$true; $expected='invocation-selection' }
      'profile-mismatch' { $args.ProfileMismatch=$true; $expected='invocation-sample' }
      'settings-mismatch' { $args.SettingsMismatch=$true; $expected='invocation-config' }
      'engine-mismatch' { $args.EngineMismatch=$true; $expected='invocation-engine' }
      'candidate-mismatch' { $args.CandidateMismatch=$true; $expected='invocation-candidate' }
      'candidate-source-mismatch' { $args.CandidateSourceMismatch=$true; $expected='invocation-candidate' }
      'archive-mismatch' { $args.ArchiveMismatch=$true; $expected='invocation-archives' }
      'execution-controls-mismatch' { $args.ExecutionControlsMismatch=$true; $expected='invocation-controls' }
      'raw-settings-claim' { $args.RawSettingsClaim=$true; $expected='settings-binding' }
    }
    $path = New-MIR430PerformanceFixtureObservation @args
    $rejected = $false
    try { Assert-MIR430ClassicStartupStressObservation -RepoRoot $repo -Path $path -Candidate $candidate -Code 'mir430-test' | Out-Null } catch { $rejected = if ($expected -ceq 'mir430-performance-resource-ledger-incomplete') { $_.Exception.Message -ceq ('[' + $expected + ']') } else { $_.Exception.Message -match ('-' + [regex]::Escape($expected) + '\]') } }
    Assert-MIR430PerformanceTest -Condition $rejected -Code ($case + '-rehash-rejected')
  }
  Write-Output 'MIR430-CLASSIC-STARTUP-PERFORMANCE-CRITERION-PASSED assertions=21 native=0 controlled_evidence_only=true'
} finally {
  $build = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
  if (-not ([IO.Path]::GetFullPath($root) + [IO.Path]::DirectorySeparatorChar).StartsWith($build + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir430-performance-test-containment]' }
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
