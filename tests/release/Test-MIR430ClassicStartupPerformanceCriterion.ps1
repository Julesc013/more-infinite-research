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
    [switch]$CandidateSourceMismatch,[switch]$ArchiveMismatch,[switch]$ExecutionControlsMismatch,[switch]$RawSettingsClaim,
    [switch]$ClassicProfile,[switch]$DefaultProfileMismatch,[switch]$CatalogueDefinitionMismatch,
    [switch]$ForgedRawSummary,[switch]$DroppedNonCoreTechnology,[switch]$SemanticFieldMismatch
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
    # The preservation gate reads these full raw snapshots.  Do not feed it a
    # summary asserted by the candidate: include a non-MIR row so that an
    # accidental MIR-prefix filter cannot hide native technology changes.
    $sourceTechnologies = [ordered]@{
      automation = [ordered]@{enabled=$true;visible_when_disabled=$false;prototype=[ordered]@{order='a';hidden=$false;max_level=0;prerequisites=@();ingredients=@([ordered]@{name='automation-science-pack';amount=1});effects=@([ordered]@{type='unlock-recipe';recipe='automation-science-pack'});unit_count=10;unit_count_formula='';unit_energy=30}}
      'advanced-circuit' = [ordered]@{enabled=$true;visible_when_disabled=$false;prototype=[ordered]@{order='a';hidden=$false;max_level=0;prerequisites=@('automation');ingredients=@([ordered]@{name='automation-science-pack';amount=2});effects=@([ordered]@{type='unlock-recipe';recipe='advanced-circuit'});unit_count=100;unit_count_formula='';unit_energy=60}}
      'recipe-prod-research_character_mining_speed-1' = [ordered]@{enabled=$true;visible_when_disabled=$false;prototype=[ordered]@{order='z';hidden=$false;max_level='infinite';prerequisites=@('automation');ingredients=@([ordered]@{name='automation-science-pack';amount=3});effects=@([ordered]@{type='character-mining-speed';modifier=0.1;description=@('',@('technology-description.nothing'),'nested localised effect')});unit_count=100;unit_count_formula='100 * (L + 1)';unit_energy=60}}
    }
    $candidateTechnologies = (ConvertTo-Json -InputObject $sourceTechnologies -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String)
    if ($NoGeneratedTechnology -and [string]$expected.id -ceq 'f200-bob-angel') { $candidateTechnologies.PSObject.Properties.Remove('recipe-prod-research_character_mining_speed-1') }
    if ($DroppedNonCoreTechnology -and [string]$expected.id -ceq 'f200-bob-angel') { $candidateTechnologies.PSObject.Properties.Remove('advanced-circuit') }
    if (($CatalogueDefinitionMismatch -or $SemanticFieldMismatch) -and [string]$expected.id -ceq 'f200-bob-angel') { $candidateTechnologies.'recipe-prod-research_character_mining_speed-1'.prototype.effects[0].modifier = 0.2 }
    $sourceSelection = @($selection | ForEach-Object { if ($_ -match '^more-infinite-research@') { 'more-infinite-research@4.2.20002' } else { $_ } })
    $sourceActiveMods = [ordered]@{};foreach($identity in $sourceSelection){$parts=$identity.Split('@',2);$sourceActiveMods[$parts[0]]=$parts[1]}
    $candidateActiveMods = [ordered]@{};foreach($identity in $selection){$parts=$identity.Split('@',2);$candidateActiveMods[$parts[0]]=$parts[1]}
    $sourceSnapshot = [ordered]@{from_version='4.2.20002';to_version=[string]$candidateTarget.distribution_version;stage='source';active_mods=$sourceActiveMods;forces=[ordered]@{player=[ordered]@{technologies=$sourceTechnologies;settings=[ordered]@{difficulty='normal'}}}}
    $candidateSnapshot = [ordered]@{from_version='4.2.20002';to_version=[string]$candidateTarget.distribution_version;stage='upgrade';active_mods=$candidateActiveMods;forces=[ordered]@{player=[ordered]@{technologies=$candidateTechnologies;settings=[ordered]@{difficulty='normal';'mir-compiler-profile'='full'}}}}
    $baselineRawPath = Join-Path $resultRoot 'source-prototype-capture.json'
    $candidateRawPath = Join-Path $resultRoot 'upgrade-prototype-capture.json'
    [IO.File]::WriteAllText($baselineRawPath,($sourceSnapshot | ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
    if($ForgedRawSummary -and [string]$expected.id -ceq 'f200-bob-angel') {
      [IO.File]::WriteAllText($candidateRawPath,(([ordered]@{kind='matching-summary';technology_count=3;semantic_definitions_sha256=('0'*64)}) | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    } else {
      [IO.File]::WriteAllText($candidateRawPath,($candidateSnapshot | ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
    }
    $nativeRunPath = Join-Path $resultRoot 'native-run.json'
    $sourceActivation = @($sourceSelection | ForEach-Object {$parts=$_.Split('@',2);[ordered]@{name=$parts[0];version=$parts[1]}})
    $candidateActivation = @($selection | ForEach-Object {$parts=$_.Split('@',2);[ordered]@{name=$parts[0];version=$parts[1]}})
    $nativeRun = [ordered]@{
      status='passed'
      factorio_binary_version=([string]$expected.profile.engine.version + '.1')
      factorio_binary_sha256=[string]$expected.profile.engine.sha256
      from=[ordered]@{version='4.2.20002';sha256='14C2B23E0F4657F9F79585A982639463678D640C04916FEECC365D93B6894A65'}
      to=[ordered]@{version=[string]$candidateTarget.distribution_version;sha256=[string]$candidateTarget.archive.sha256}
      assertions=@('all-existing-technology-state-and-definitions-retained','all-exposed-earned-effects-retained','all-supported-research-queue-retained','full-state-oracle-executed-upgrade-and-two-reloads')
      full_state_evaluator_snapshots=@(
        [ordered]@{stage='source';path=$baselineRawPath;sha256=(Get-MIR4Sha256File -Path $baselineRawPath)}
        [ordered]@{stage='upgrade';path=$candidateRawPath;sha256=(Get-MIR4Sha256File -Path $candidateRawPath)}
      )
      source_library_activation=[ordered]@{selected=$sourceActivation}
      library_activation=[ordered]@{selected=$candidateActivation}
    }
    [IO.File]::WriteAllText($nativeRunPath,($nativeRun | ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
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
    $lines.Add(('{0:F3} Script: [MIR430-ABLATION] actual-profile={1}' -f $clock,$(if($ClassicProfile -and [string]$expected.id -ceq 'f200-bob-angel'){'classic'}else{'full'})))
    $lines.Add(('{0:F3} Script: [MIR430-ABLATION] declared-default={1}' -f ($clock + 0.005),$(if($DefaultProfileMismatch -and [string]$expected.id -ceq 'f200-bob-angel'){'classic'}else{'full'})))
    $names = ConvertTo-Json -InputObject @($candidateTechnologies.PSObject.Properties.Name | Sort-Object) -Compress
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
    $expectedUpstreamSelection = @($selection | Where-Object { $_ -notmatch '^more-infinite-research@' -and $_ -notmatch ('^' + [regex]::Escape([string]$Authority.record.allowed_observer.name) + '@') })
    $capture = [pscustomobject][ordered]@{
      schema=1;kind='MIR430FullDefaultPrototypeCaptureV1';status='completed';source=$Candidate.source;candidate_manifest=$Candidate.candidate_manifest
      profile=[ordered]@{id=[string]$expected.id;target=[string]$expected.target;definition=$expected.definition;engine=$expected.profile.engine;loaded_selection=$selection}
      compiler_profile='full';settings=[ordered]@{kind='canonical-absent-default'};capture_mode='upgrade-preservation-proof'
      baseline=[ordered]@{source_version='4.2.2';distribution_version='4.2.20002';profile_definition_sha256=[string]$expected.definition.sha256;engine_sha256=[string]$expected.profile.engine.sha256;settings_kind='canonical-absent-default';compiler_profile_marker='absent';upstream_selection_sha256=(Get-MIR430PerformanceTextSha256 -Text ($expectedUpstreamSelection -join "`n"));raw_snapshot=[ordered]@{path='source-prototype-capture.json';sha256=(Get-MIR4Sha256File -Path $baselineRawPath);stage='source'}}
      candidate_catalogue=[ordered]@{compiler_profile_marker='full';settings_kind='canonical-absent-default';upstream_selection_sha256=(Get-MIR430PerformanceTextSha256 -Text ($expectedUpstreamSelection -join "`n"));raw_snapshot=[ordered]@{path='upgrade-prototype-capture.json';sha256=(Get-MIR4Sha256File -Path $candidateRawPath);stage='upgrade'}}
      native_run=[ordered]@{path='native-run.json';sha256=(Get-MIR4Sha256File -Path $nativeRunPath)};record_sha256=''
    }
    $capturePath = Join-Path $resultRoot 'full-catalogue-capture.json'
    Write-MIR4BootstrapRecord -Record $capture -Path $capturePath | Out-Null
    $profile = [ordered]@{
      id=[string]$expected.id;target=[string]$expected.target;definition=$expected.definition
      settings=$(if($RawSettingsClaim -and [string]$expected.id -ceq 'f200-bob-angel'){
        [ordered]@{kind='raw-sha256';path=($relativeRoot + '/claimed-mod-settings.dat');sha256=(Get-MIR4Sha256File -Path $rawSettingsPath)}
      }else{[ordered]@{kind='canonical-absent-default'}});engine=$expected.profile.engine
      candidate=[ordered]@{target=[string]$target.target;source_version=[string]$Candidate.source_version;distribution_version=[string]$target.identity.distribution_version;archive=[ordered]@{sha256=[string]$target.archive.sha256;bytes=[int64]$target.archive.bytes;content_sha256=[string]$target.archive.content_sha256;entry_count=[int]$target.archive.entry_count}}
      observer=$Authority.record.allowed_observer
      full_catalogue_capture=[ordered]@{path=($relativeRoot + '/full-catalogue-capture.json');sha256=(Get-MIR4Sha256File -Path $capturePath);record_sha256=[string]$capture.record_sha256}
      samples=@($sample)
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
    schema=1;kind='MIR430FullStartupStressObservationV1';status='completed';source=$Candidate.source;candidate_manifest=$Candidate.candidate_manifest
    authority=[ordered]@{path=$script:MIR430EmergencyPerformanceAuthorityPath;sha256=[string]$Authority.sha256;record_sha256=[string]$Authority.record.record_sha256}
    compiler_profile='full';profiles=@($profiles);record_sha256=''
  }
  $path = Join-Path $Root 'observation.json'
  Write-MIR4BootstrapRecord -Record $record -Path $path | Out-Null
  return $path
}

$root = Join-Path $repo ('build/test-results/mir430-performance-criterion-' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $authority = Get-MIR430EmergencyPerformanceAuthority -RepoRoot $repo
  $settingsObserver = Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/assert-mir430-startup-work/settings-updates.lua')
  $finalObserver = Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/assert-mir430-startup-work/data-final-fixes.lua')
  Assert-MIR430PerformanceTest -Condition ($settingsObserver -notmatch '(?i)default_value\s*=' -and $settingsObserver -match 'data[.]raw\["string-setting"\]' -and $settingsObserver -match 'declared-default=') -Code 'observer-does-not-mutate-default'
  Assert-MIR430PerformanceTest -Condition ($finalObserver -notmatch 'data[.]raw\["string-setting"\]|declared-default=' -and $finalObserver -match 'settings[.]startup\["mir-compiler-profile"\]' -and $finalObserver -match 'actual-profile=') -Code 'observer-stage-isolation'
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
  $accepted = Assert-MIR430FullStartupStressObservation -RepoRoot $repo -Path $observation -Candidate $candidate -Code 'mir430-test'
  Assert-MIR430PerformanceTest -Condition ([string]$accepted.record.kind -ceq 'MIR430FullStartupStressObservationV1' -and @($accepted.record.profiles).Count -eq 3) -Code 'accepted-three-pinned-full-profiles'
  $captureControl = Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/assert-mir430-startup-work/control.lua')
  Assert-MIR430PerformanceTest -Condition ($captureControl -match 'technology[.]prototype[.]effects' -and $captureControl -notmatch 'technology[.]effects' -and
    $captureControl -match 'if type\(value\) == "table"' -and $captureControl -match 'out\[copy\(key\)\] = copy\(item\)') -Code 'runtime-capture-uses-prototype-effects-and-recursive-copy'
  # Exercise the distinct matched-startup producer.  It must be bound to a
  # real-shaped DirectLibrary result and raw runtime snapshots, not relabelled
  # as an upgrade/save proof or reduced to asserted digests.
  $matchedExpected = @($authority.profiles)[0]
  $matchedTarget = Get-MIR430PerformanceCandidateTarget -Candidate $candidate -Target 'f200' -Code 'mir430-matched-control'
  $matchedSelection = @(Get-MIR430ExpectedProfileLoadedSelection -ProfileDefinition $matchedExpected.profile -CandidateTarget $matchedTarget -Authority $authority -Code 'mir430-matched-control')
  $matchedBaselineSelection = @($matchedSelection | ForEach-Object { if ($_ -match '^more-infinite-research@') {'more-infinite-research@4.2.20002'} else {$_} })
  $matchedRoot = Join-Path $root 'matched-capture'
  $sourceOutput = Join-Path $matchedRoot 'write-data/released-4.2.2/script-output/mir430-full-technology-source.json'
  $candidateOutput = Join-Path $matchedRoot 'write-data/candidate-4.3.0/script-output/mir430-full-technology-candidate.json'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sourceOutput),(Split-Path -Parent $candidateOutput) | Out-Null
  $legacySource = Get-Content -Raw -LiteralPath (Join-Path $root 'f200-galore-space-age/source-prototype-capture.json') | ConvertFrom-Json -Depth 100 -DateKind String
  $legacyCandidate = Get-Content -Raw -LiteralPath (Join-Path $root 'f200-galore-space-age/upgrade-prototype-capture.json') | ConvertFrom-Json -Depth 100 -DateKind String
  $legacySource | Add-Member -Force NoteProperty schema 1; $legacySource | Add-Member -Force NoteProperty kind 'MIR430FullTechnologySnapshotV1'; $legacySource | Add-Member -Force NoteProperty package_version '4.2.20002'; $legacySource.stage='source'
  $legacyCandidate | Add-Member -Force NoteProperty schema 1; $legacyCandidate | Add-Member -Force NoteProperty kind 'MIR430FullTechnologySnapshotV1'; $legacyCandidate | Add-Member -Force NoteProperty package_version ([string]$matchedTarget.distribution_version); $legacyCandidate.stage='candidate'
  [IO.File]::WriteAllText($sourceOutput,($legacySource | ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($candidateOutput,($legacyCandidate | ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
  $writeMatchedLog = {
    param([string]$Path,[string[]]$Selection,[string]$Profile,[string]$Stage,[string]$Package)
    $rows = [Collections.Generic.List[string]]::new()
    $rows.Add(('0.000 2026-10-13 00:00:00; Factorio {0} (build 1)' -f [string]$matchedExpected.profile.engine.version))
    foreach($identity in $Selection){$parts=$identity.Split('@',2);$rows.Add(('0.010 Loading mod {0} {1} (data.lua)' -f $parts[0],$parts[1]))}
    $rows.Add(('1.000 Script @__{0}__/data-final-fixes.lua:1: [MIR_ACTIVE_MODS] {1}' -f [string]$authority.record.allowed_observer.name,($Selection -join '|')))
    $rows.Add(('1.001 Script: [MIR430-ABLATION] actual-profile={0}' -f $Profile))
    $rows.Add(('1.002 Script: [MIR430-ABLATION] declared-default={0}' -f $Profile))
    $rows.Add(('1.003 Script @__{0}__/control.lua:1: [MIR430-CAPTURE] stage={1} package={2} technologies=3 output=mir430-full-technology-{1}.json' -f [string]$authority.record.allowed_observer.name,$Stage,$Package))
    [IO.File]::WriteAllLines($Path,$rows,[Text.UTF8Encoding]::new($false))
  }
  $sourceRun = Join-Path $matchedRoot 'runs/released-4.2.2/1/changed-configuration'; $candidateRun = Join-Path $matchedRoot 'runs/candidate-4.3.0/1/changed-configuration'
  New-Item -ItemType Directory -Force -Path $sourceRun,$candidateRun | Out-Null
  $sourceLog=Join-Path $sourceRun 'factorio.log';$candidateLog=Join-Path $candidateRun 'factorio.log'
  & $writeMatchedLog $sourceLog $matchedBaselineSelection 'absent' 'source' '4.2.20002'
  & $writeMatchedLog $candidateLog $matchedSelection 'full' 'candidate' ([string]$matchedTarget.distribution_version)
  $writeMatchedConfig = { param([string]$Run,[string]$WriteData) $path=Join-Path $Run 'config.ini';[IO.File]::WriteAllText($path,("[path]`nwrite-data="+$WriteData+"`n"),[Text.UTF8Encoding]::new($false));return $path }
  $sourceConfig=& $writeMatchedConfig $sourceRun (Split-Path -Parent (Split-Path -Parent $sourceOutput));$candidateConfig=& $writeMatchedConfig $candidateRun (Split-Path -Parent (Split-Path -Parent $candidateOutput))
  $sourceSample=[ordered]@{label='released-4.2.2';cache_state='changed-configuration';exit_code=0;endpoint_class='headless-create-diagnostic';run_relative_path='runs/released-4.2.2/1/changed-configuration';log='factorio.log';loaded_selection=$matchedBaselineSelection;execution_controls=[ordered]@{config=[ordered]@{path='config.ini'}}}
  $candidateSample=[ordered]@{label='candidate-4.3.0';cache_state='changed-configuration';exit_code=0;endpoint_class='headless-create-diagnostic';run_relative_path='runs/candidate-4.3.0/1/changed-configuration';log='factorio.log';loaded_selection=$matchedSelection;execution_controls=[ordered]@{config=[ordered]@{path='config.ini'}}}
  $matchedResultPath=Join-Path $matchedRoot 'result.json'
  $matchedResult=[ordered]@{
    schema=1
    kind='MIRDirectLibraryStartupMeasurementV1'
    status='completed'
    mode='matched-three-input'
    source_observation=[ordered]@{requested_commit=[string]$candidate.source.commit;head_commit=[string]$candidate.source.commit;working_tree_dirty=$false}
    factorio=[ordered]@{sha256=[string]$matchedExpected.profile.engine.sha256;base_version=[string]$matchedExpected.profile.engine.version}
    inputs=[ordered]@{
      published_422=[ordered]@{archive=[ordered]@{version='4.2.20002';sha256='14C2B23E0F4657F9F79585A982639463678D640C04916FEECC365D93B6894A65'}}
      candidate=[ordered]@{
        source_version='4.3.0'
        archive=[ordered]@{sha256=[string]$matchedTarget.archive.sha256}
        materialization=[ordered]@{source_version=[string]$matchedTarget.source_version;archive_sha256=[string]$matchedTarget.archive.sha256;package_source_sha256=[string]$matchedTarget.package_source_sha256}
      }
    }
    resource_context=[ordered]@{processes=@(
      [ordered]@{status='passed';result=[ordered]@{passed=$true;exit_code=0;timed_out=$false}}
      [ordered]@{status='passed';result=[ordered]@{passed=$true;exit_code=0;timed_out=$false}}
    )}
    samples=@($sourceSample,$candidateSample)
  }
  $matchedCapturePath=Join-Path $matchedRoot 'capture.json'
  $matchedCapture=[pscustomobject][ordered]@{schema=1;kind='MIR430FullDefaultPrototypeCaptureV1';status='completed';source=$candidate.source;candidate_manifest=$candidate.candidate_manifest;profile=[ordered]@{id=[string]$matchedExpected.id;target='f200';definition=$matchedExpected.definition;engine=$matchedExpected.profile.engine;loaded_selection=$matchedSelection};compiler_profile='full';settings=[ordered]@{kind='canonical-absent-default'};capture_mode='matched-startup-capture';baseline=[ordered]@{source_version='4.2.2';distribution_version='4.2.20002';profile_definition_sha256=[string]$matchedExpected.definition.sha256;engine_sha256=[string]$matchedExpected.profile.engine.sha256;settings_kind='canonical-absent-default';compiler_profile_marker='absent';upstream_selection_sha256=(Get-MIR430PerformanceTextSha256 -Text (@($matchedSelection|?{$_ -notmatch '^more-infinite-research@' -and $_ -notmatch ('^'+[regex]::Escape([string]$authority.record.allowed_observer.name)+'@')}) -join "`n"));raw_snapshot=[ordered]@{path='write-data/released-4.2.2/script-output/mir430-full-technology-source.json';sha256='';stage='source'}};candidate_catalogue=[ordered]@{compiler_profile_marker='full';settings_kind='canonical-absent-default';upstream_selection_sha256=(Get-MIR430PerformanceTextSha256 -Text (@($matchedSelection|?{$_ -notmatch '^more-infinite-research@' -and $_ -notmatch ('^'+[regex]::Escape([string]$authority.record.allowed_observer.name)+'@')}) -join "`n"));raw_snapshot=[ordered]@{path='write-data/candidate-4.3.0/script-output/mir430-full-technology-candidate.json';sha256='';stage='candidate'}};native_run=[ordered]@{path='result.json';sha256='';source_sample_label='released-4.2.2';candidate_sample_label='candidate-4.3.0'};record_sha256=''}
  [IO.File]::WriteAllText($matchedResultPath,($matchedResult|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
  $writeMatchedCapture={$matchedCapture.baseline.raw_snapshot.sha256=Get-MIR4Sha256File -Path $sourceOutput;$matchedCapture.candidate_catalogue.raw_snapshot.sha256=Get-MIR4Sha256File -Path $candidateOutput;$matchedCapture.native_run.sha256=Get-MIR4Sha256File -Path $matchedResultPath;$matchedCapture.record_sha256='';Write-MIR4BootstrapRecord -Record $matchedCapture -Path $matchedCapturePath|Out-Null}
  & $writeMatchedCapture
  $matchedDescriptor=[pscustomobject][ordered]@{path='capture.json';sha256=(Get-MIR4Sha256File -Path $matchedCapturePath);record_sha256=([string](Get-Content -Raw $matchedCapturePath|ConvertFrom-Json).record_sha256)}
  $matchedAccepted=Assert-MIR430FullCatalogueDefinitionCapture -ObservationPath $matchedCapturePath -Descriptor $matchedDescriptor -Profile $matchedExpected -Expected $matchedExpected -Candidate $candidate -CandidateTarget $matchedTarget -Authority $authority -Code 'mir430-matched-control'
  Assert-MIR430PerformanceTest -Condition (@($matchedAccepted.candidate.technology_ids).Count -eq 3) -Code 'matched-startup-capture-accepted'
  $writerCapture = New-MIR430MatchedStartupCaptureRecord -RepoRoot $repo -MeasurementPath $matchedRoot -OutputPath (Join-Path $matchedRoot 'writer-capture.json') -Candidate $candidate -ProfileId ([string]$matchedExpected.id) -Code 'mir430-matched-writer'
  Assert-MIR430PerformanceTest -Condition (@($writerCapture.candidate.technology_ids).Count -eq 3) -Code 'matched-startup-capture-writer-readback'
  $invokeMatchedReject={param([string]$Label,[string]$Expected,[scriptblock]$Mutate,[scriptblock]$Restore)&$Mutate;&$writeMatchedCapture;$descriptor=[pscustomobject][ordered]@{path='capture.json';sha256=(Get-MIR4Sha256File -Path $matchedCapturePath);record_sha256=([string](Get-Content -Raw $matchedCapturePath|ConvertFrom-Json).record_sha256)};$rejected=$false;try{Assert-MIR430FullCatalogueDefinitionCapture -ObservationPath $matchedCapturePath -Descriptor $descriptor -Profile $matchedExpected -Expected $matchedExpected -Candidate $candidate -CandidateTarget $matchedTarget -Authority $authority -Code 'mir430-matched-control'|Out-Null}catch{$rejected=$_.Exception.Message -match ('-'+[regex]::Escape($Expected)+'\]')}&$Restore;&$writeMatchedCapture;Assert-MIR430PerformanceTest -Condition $rejected -Code ('matched-'+$Label+'-rejected')}
  $originalCandidateSnapshot=Get-Content -Raw $candidateOutput;$originalMatchedResult=Get-Content -Raw $matchedResultPath;$originalCandidatePath=[string]$matchedCapture.candidate_catalogue.raw_snapshot.path
  & $invokeMatchedReject 'forged-summary' 'raw-snapshot-shape' {[IO.File]::WriteAllText($candidateOutput,(@{summary='forged';technology_count=3}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))} {[IO.File]::WriteAllText($candidateOutput,$originalCandidateSnapshot,[Text.UTF8Encoding]::new($false))}
  & $invokeMatchedReject 'dropped-noncore' 'catalogue-definition-binding' {$value=Get-Content -Raw $candidateOutput|ConvertFrom-Json -Depth 100;$value.forces.player.technologies.PSObject.Properties.Remove('advanced-circuit');[IO.File]::WriteAllText($candidateOutput,($value|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))} {[IO.File]::WriteAllText($candidateOutput,$originalCandidateSnapshot,[Text.UTF8Encoding]::new($false))}
  & $invokeMatchedReject 'altered-nested-modifier' 'catalogue-definition-binding' {$value=Get-Content -Raw $candidateOutput|ConvertFrom-Json -Depth 100;$value.forces.player.technologies.'recipe-prod-research_character_mining_speed-1'.prototype.effects[0].modifier=0.2;[IO.File]::WriteAllText($candidateOutput,($value|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))} {[IO.File]::WriteAllText($candidateOutput,$originalCandidateSnapshot,[Text.UTF8Encoding]::new($false))}
  & $invokeMatchedReject 'wrong-settings' 'raw-snapshot-settings' {$value=Get-Content -Raw $candidateOutput|ConvertFrom-Json -Depth 100;$value.forces.player.settings.'mir-compiler-profile'='classic';[IO.File]::WriteAllText($candidateOutput,($value|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))} {[IO.File]::WriteAllText($candidateOutput,$originalCandidateSnapshot,[Text.UTF8Encoding]::new($false))}
  & $invokeMatchedReject 'wrong-engine' 'matched-run-binding' {$value=Get-Content -Raw $matchedResultPath|ConvertFrom-Json -Depth 100;$value.factorio.sha256='0'*64;[IO.File]::WriteAllText($matchedResultPath,($value|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))} {[IO.File]::WriteAllText($matchedResultPath,$originalMatchedResult,[Text.UTF8Encoding]::new($false))}
  & $invokeMatchedReject 'wrong-archive' 'matched-run-binding' {$value=Get-Content -Raw $matchedResultPath|ConvertFrom-Json -Depth 100;$value.inputs.candidate.archive.sha256='0'*64;[IO.File]::WriteAllText($matchedResultPath,($value|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))} {[IO.File]::WriteAllText($matchedResultPath,$originalMatchedResult,[Text.UTF8Encoding]::new($false))}
  & $invokeMatchedReject 'wrong-selection' 'matched-run-sample' {$value=Get-Content -Raw $matchedResultPath|ConvertFrom-Json -Depth 100;$value.samples[1].loaded_selection=@('base@2.0.77');[IO.File]::WriteAllText($matchedResultPath,($value|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))} {[IO.File]::WriteAllText($matchedResultPath,$originalMatchedResult,[Text.UTF8Encoding]::new($false))}
  & $invokeMatchedReject 'wrong-capture-path' 'matched-run-capture-path' {$copy=Join-Path $matchedRoot 'write-data/candidate-4.3.0/script-output/wrong.json';Copy-Item -LiteralPath $candidateOutput -Destination $copy -Force;$matchedCapture.candidate_catalogue.raw_snapshot.path='write-data/candidate-4.3.0/script-output/wrong.json'} {$matchedCapture.candidate_catalogue.raw_snapshot.path=$originalCandidatePath}
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
  # 4.3.1 must use the ordinary nine-target criterion path. It must not
  # silently reuse the 4.3.0 emergency stress authority, and its one normal
  # observation must resolve the authenticated individual engine-run reader.
  $normalTargets = @(
    foreach ($target in @($script:MIR42QualificationNineTargets)) {
      [pscustomobject][ordered]@{target=$target;distribution_version=('4.3.'+$target.Substring(1)+'01');archive_path=$archive;archive_sha256=('A'*64);content_sha256=('B'*64);entry_count=1}
    }
  )
  $normalSealCandidate = [pscustomobject][ordered]@{
    source=$source;identity=[pscustomobject][ordered]@{sha256=[string]$candidate.candidate_manifest.sha256;record=[pscustomobject][ordered]@{record_sha256=[string]$candidate.candidate_manifest.record_sha256}}
    scope='nine-target';targets=$normalTargets
  }
  $normalEngineReference = [ordered]@{path='individual-engine-run.json';sha256=('F'*64);record_sha256=('1'*64)}
  $normalObservationRecord = [ordered]@{
    schema=1;kind='MIR42NineTargetCriterionObservationV1';status='passed';criterion='performance-telemetry'
    telemetry_scope='bounded-candidate-load-and-upgrade-resource-observation';compiler_profile='full';source=$source;candidate_manifest=$candidate.candidate_manifest
    individual_engine_run=$normalEngineReference;record_sha256=''
  }
  $normalObservationPath = Join-Path $root 'normal-431-observation.json'
  Write-MIR4BootstrapRecord -Record ([pscustomobject]$normalObservationRecord) -Path $normalObservationPath | Out-Null
  $normalObservation = Read-MIR42SealRecord -Path $normalObservationPath -Code 'mir431-test-normal-observation'
  $normalCriterionPath = Join-Path $root 'normal-431-criterion.json'
  $normalCriterionRecord = [pscustomobject][ordered]@{
    schema=1;kind='MIR42NineTargetReleaseAcceptanceCriterionEvidenceV1';status='passed';criterion='performance-telemetry';source=$source;candidate_manifest=$candidate.candidate_manifest
    observed_targets=@($script:MIR42QualificationNineTargets);not_applicable_targets=@();evidence=@([ordered]@{path=$normalObservationPath;sha256=(Get-MIR4Sha256File -Path $normalObservationPath);record_sha256=[string]$normalObservation.record.record_sha256})
    limits=[ordered]@{claim='controlled normal-431 contract fixture only';known_limitations='native execution is not claimed by this fixture'};record_sha256=''
  }
  Write-MIR4BootstrapRecord -Record $normalCriterionRecord -Path $normalCriterionPath | Out-Null
  $normalPublishedInputs = [pscustomobject][ordered]@{targets=@($script:MIR42QualificationNineTargets | ForEach-Object {[pscustomobject][ordered]@{target=$_}})}
  $originalVersionContract = (Get-Item Function:Get-MIR42SealCandidateConstructionVersionContract).ScriptBlock
  $originalBoundEngineRun = (Get-Item Function:Get-MIR42BoundEngineRun).ScriptBlock
  try {
    Set-Item Function:Get-MIR42SealCandidateConstructionVersionContract -Value { param($RepoRoot,$Manifest) [pscustomobject]@{source_version='4.3.1'} }
    Set-Item Function:Get-MIR42BoundEngineRun -Value {
      param($Reference,$Candidate,$PublishedMaintenanceInputs)
      [pscustomobject][ordered]@{path='individual-engine-run.json';sha256=('F'*64);input_kind='individual-upgrade-receipts-and-fresh-loads';record=[pscustomobject][ordered]@{record_sha256=('1'*64);targets=@($script:MIR42QualificationNineTargets | ForEach-Object {[pscustomobject][ordered]@{target=$_}})}}
    }
    $sealed = Get-MIR42NineTargetCriterionEvidenceRecord -Path $normalCriterionPath -Candidate $normalSealCandidate -PublishedMaintenanceInputs $normalPublishedInputs
    Assert-MIR430PerformanceTest -Condition ([string]$sealed.record.criterion -ceq 'performance-telemetry') -Code '431-technical-seal-binds-normal-engine-evidence'
    $normalObservationRecord.individual_engine_run.sha256='0'*64
    Write-MIR4BootstrapRecord -Record ([pscustomobject]$normalObservationRecord) -Path $normalObservationPath | Out-Null
    $changedObservation = Read-MIR42SealRecord -Path $normalObservationPath -Code 'mir431-test-normal-observation-changed'
    $normalCriterionRecord.evidence[0].sha256=(Get-MIR4Sha256File -Path $normalObservationPath)
    $normalCriterionRecord.evidence[0].record_sha256=[string]$changedObservation.record.record_sha256
    Write-MIR4BootstrapRecord -Record $normalCriterionRecord -Path $normalCriterionPath | Out-Null
    $rejected=$false
    try { Get-MIR42NineTargetCriterionEvidenceRecord -Path $normalCriterionPath -Candidate $normalSealCandidate -PublishedMaintenanceInputs $normalPublishedInputs | Out-Null } catch { $rejected=$_.Exception.Message -match '^\[mir431-seal-performance-observation-(?:engine-run-binding|binding)\]$' }
    Assert-MIR430PerformanceTest -Condition $rejected -Code '431-technical-seal-rejects-changed-engine-reference'
  } finally {
    Set-Item Function:Get-MIR42SealCandidateConstructionVersionContract -Value $originalVersionContract
    Set-Item Function:Get-MIR42BoundEngineRun -Value $originalBoundEngineRun
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
  foreach ($case in @('forged-total','missing-profile','empty-catalogue-capture','catalogue-definition-mismatch','forged-raw-summary','dropped-noncore-technology','semantic-field-mismatch','classic-profile','default-profile-mismatch','interrupted-ledger','base-only-relabel','profile-mismatch','settings-mismatch','engine-mismatch','candidate-mismatch','candidate-source-mismatch','archive-mismatch','execution-controls-mismatch','raw-settings-claim')) {
    $args = @{Root=$root;Authority=$authority;Candidate=$candidate}
    switch ($case) {
      'forged-total' { $args.ForgedTotal=$true; $expected='total-claim' }
      'missing-profile' { $args.MissingProfile=$true; $expected='schema' }
      'empty-catalogue-capture' { $args.NoGeneratedTechnology=$true; $expected='catalogue-definition-binding' }
      'catalogue-definition-mismatch' { $args.CatalogueDefinitionMismatch=$true; $expected='catalogue-definition-binding' }
      'forged-raw-summary' { $args.ForgedRawSummary=$true; $expected='raw-snapshot-shape' }
      'dropped-noncore-technology' { $args.DroppedNonCoreTechnology=$true; $expected='catalogue-definition-binding' }
      'semantic-field-mismatch' { $args.SemanticFieldMismatch=$true; $expected='catalogue-definition-binding' }
      'classic-profile' { $args.ClassicProfile=$true; $expected='full-selection' }
      'default-profile-mismatch' { $args.DefaultProfileMismatch=$true; $expected='default-selection' }
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
    try { Assert-MIR430FullStartupStressObservation -RepoRoot $repo -Path $path -Candidate $candidate -Code 'mir430-test' | Out-Null } catch { $rejected = if ($expected -ceq 'mir430-performance-resource-ledger-incomplete') { $_.Exception.Message -ceq ('[' + $expected + ']') } else { $_.Exception.Message -match ('-' + [regex]::Escape($expected) + '\]') } }
    Assert-MIR430PerformanceTest -Condition $rejected -Code ($case + '-rehash-rejected')
  }
  Write-Output 'MIR430-FULL-STARTUP-PERFORMANCE-CRITERION-PASSED assertions=38 native=0 controlled_evidence_only=true'
} finally {
  $build = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
  if (-not ([IO.Path]::GetFullPath($root) + [IO.Path]::DirectorySeparatorChar).StartsWith($build + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir430-performance-test-containment]' }
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
