function Read-MIRResearchAllObservation {
  param([Parameter(Mandatory)]$Observation,[Parameter(Mandatory)][string]$LogText,[Parameter(Mandatory)][string]$MirVersion,[Parameter(Mandatory)][string]$EngineVersion)
  if($Observation.schema-ne1-or$Observation.status-cne'observed'-or$Observation.engine-cne$EngineVersion-or$Observation.mir_version-cne$MirVersion-or$Observation.connected_players-ne0-or@($Observation.observations).Count-ne2){throw '[mir-research-all-observation-identity]'}
  $rows=@();$index=0
  foreach($phase in @('first','repeat')){
    $row=$Observation.observations[$index++]
    if($row.phase-cne$phase-or$row.completion_events-lt1-or$row.technologies-lt1){throw '[mir-research-all-observation-events]'}
    $markers=@([regex]::Matches($LogText,'(?m)\[mir-research-all\] '+$phase+'=(?<value>[^\r\n]+)'))
    if($markers.Count-ne1-or$markers[0].Groups['value'].Value-notmatch '^\s*(?<ms>[0-9]+(?:\.[0-9]+)?)\s+ms\s*$'){throw '[mir-research-all-observation-timer]'}
    $milliseconds=[double]::Parse($Matches.ms,[Globalization.CultureInfo]::InvariantCulture)
    if([double]::IsInfinity($milliseconds)-or[double]::IsNaN($milliseconds)){throw '[mir-research-all-observation-timer]'}
    $rows+=@{phase=$phase;milliseconds=$milliseconds;completion_events=[int]$row.completion_events;technologies=[int]$row.technologies}
  }
  return $rows
}

function Invoke-MIRResearchAllPerformance {
  param([string]$RepoRoot,[ValidateSet('f200','f210')][string]$Target,[string]$Candidate,[string]$PriorRelease,[string]$FactorioBin,[string]$ExpectedSourceCommit,[string]$LibraryDirectory,[string]$SourceMaterializationPath,[string]$OutputRoot,[switch]$PrepareInputsOnly,[int]$ExpectedPeakMemoryMiB=1024,[int]$MaxNewOutputMiB=120)
  $ErrorActionPreference='Stop'
  if(-not$PrepareInputsOnly-and(-not$LibraryDirectory-or-not$FactorioBin-or-not$SourceMaterializationPath)){throw '[mir-research-all-direct-inputs] Supply explicit engine/library locations and the current materialization receipt.'}
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
  . (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
  . (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
  . (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
  Assert-MIR441CleanTrackedSource -RepoRoot $repo
  $source=(&git -C $repo rev-parse HEAD).Trim()
  if($source-cne$ExpectedSourceCommit){throw '[mir-research-all-source]'}
  if(-not$OutputRoot){$OutputRoot='build/p/research-all'}
  & (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxWorktrees 8 -MaxBranches 32 | Out-Host
  $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
  $profilePath=Join-Path $repo ('fixtures/run-profiles/research-all-'+$Target+'.json')
  $profile=Get-Content -LiteralPath $profilePath -Raw|ConvertFrom-Json
  if($profile.target-cne$Target-or$profile.settings-cne'defaults'-or($profile.official_mods-join',')-cne'base'){throw '[mir-research-all-profile]'}
  $fixture=Join-Path $resources.root 'fixture-source';[IO.Directory]::CreateDirectory($fixture)|Out-Null
  $info=[ordered]@{name=$profile.fixture.name;version=$profile.fixture.version;title='MIR research-all observation';author='MIR tests';factorio_version=$profile.factorio_line;dependencies=@(('base = '+$profile.engine_version),'more-infinite-research')}
  [IO.File]::WriteAllText((Join-Path $fixture 'info.json'),(($info|ConvertTo-Json -Depth 4).Replace("`r`n","`n")+"`n"),[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllBytes((Join-Path $fixture 'control.lua'),[IO.File]::ReadAllBytes((Join-Path $repo 'fixtures/performance-regression-probe/research-all.lua')))
  if($PrepareInputsOnly){
    $archive=Publish-MIRModDirectoryArchive -Source $fixture -Name $profile.fixture.name -Version $profile.fixture.version -ModsDir $resources.root
    Write-MIRNativeProbeResult -Context $resources -Record @{status='prepared-not-native-tested';target=$Target;source_commit=$source;fixture=@{path=$archive;sha256=(Get-FileHash -LiteralPath $archive).Hash};factorio_processes=0}
    return
  }
  $activation=$null
  $record=[ordered]@{kind='MIR421ResearchAllPairedObservationV1';status='started';source_commit=$source;target=$Target;profile=@{path=$profilePath;sha256=(Get-FileHash -LiteralPath $profilePath).Hash};observations=@();scope=$profile.scope;dependency_payload_bytes_copied=0;archive_links_created=0;error=''}
  try{
    $engine=(Resolve-Path -LiteralPath $FactorioBin).Path
    if((Get-FileHash -LiteralPath $engine).Hash-cne$profile.engine_sha256){throw '[mir-research-all-engine]'}
    $current=Read-MIRNativeProbeCurrentCandidate -Repository $repo -Archive $Candidate -ReceiptPath $SourceMaterializationPath -Target $Target
    $baseline=(Resolve-Path -LiteralPath $PriorRelease).Path
    if((Get-FileHash -LiteralPath $baseline).Hash-cne$profile.baseline.sha256-or[IO.Path]::GetFileName($baseline)-cne('more-infinite-research_'+$profile.baseline.version+'.zip')){throw '[mir-research-all-baseline]'}
    $library=(Resolve-Path -LiteralPath $LibraryDirectory).Path
    $fixtureName=$profile.fixture.name+'_'+$profile.fixture.version+'.zip'
    Assert-MIRLibraryFixtureArchive -Archive (Join-Path $library $fixtureName) -SourceDirectory $fixture
    $fixtureHash=(Get-FileHash -LiteralPath (Join-Path $library $fixtureName)).Hash
    $data=Join-Path (Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent) 'data'
    $record.engine=@{path=$engine;version=$profile.engine_version;sha256=$profile.engine_sha256}
    $record.fixture=@{path=(Join-Path $library $fixtureName);sha256=$fixtureHash}
    foreach($packageInput in @(@{label='baseline';path=$baseline;version=$profile.baseline.version;sha256=$profile.baseline.sha256},@{label='candidate';path=$current.path;version=$profile.candidate_version;sha256=$current.receipt.archive_sha256})){
      $run=Join-Path $resources.root $packageInput.label;[IO.Directory]::CreateDirectory($run)|Out-Null
      $selection=Join-Path $run 'selection.json'
      @{mods=@(@{name='base';version=$profile.engine_version;enabled=$true},@{name='more-infinite-research';version=$packageInput.version;enabled=$true},@{name=$profile.fixture.name;version=$profile.fixture.version;enabled=$true})}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $selection -Encoding utf8
      $hashes=@{};$hashes[[IO.Path]::GetFileName($packageInput.path)]=$packageInput.sha256;$hashes[$fixtureName]=$fixtureHash
      $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $data -ProfilePath $selection -ArchiveHashes $hashes -SettingsMode Defaults
      Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
      $config=Join-Path $run 'config.ini'
      [IO.File]::WriteAllLines($config,@('[path]',('read-data='+$data.Replace('\','/')),('write-data='+$run.Replace('\','/')),'[general]','locale=en','[other]','enable-new-mods=false','check-updates=false','disable-blueprint-storage=true','enable-blueprint-storage-cloud-sync=false'),[Text.UTF8Encoding]::new($false))
      $save=Join-Path $run 'source.zip';$stages=@()
      foreach($stage in @('create','research')){
        $arguments=@('--config',$config,'--mod-directory',$library,'--disable-audio','--no-log-rotation')
        $arguments+=if($stage-ceq'create'){@('--create',$save)}else{@('--benchmark',$save,'--benchmark-ticks','3','--benchmark-runs','1')}
        Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $arguments
        $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments $arguments -TimeoutSeconds 120
        if(-not$actor.result.passed){throw '[mir-research-all-native]'}
        $log=Join-Path $run 'factorio-current.log'
        $loaded=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -LatestInvocation
        $logCopy=Join-Path $run ($stage+'.log');[IO.File]::Copy($log,$logCopy,$false)
        $stages+=@{stage=$stage;log=@{path=$logCopy;sha256=(Get-FileHash -LiteralPath $logCopy).Hash};loaded=$loaded;process=$actor.result}
      }
      $observationPath=Join-Path $run 'script-output/research-all.json'
      $observation=Get-Content -LiteralPath $observationPath -Raw|ConvertFrom-Json
      $timings=@(Read-MIRResearchAllObservation -Observation $observation -LogText ([IO.File]::ReadAllText((Join-Path $run 'research.log'))) -MirVersion $packageInput.version -EngineVersion $profile.engine_version)
      $terminal=Complete-MIRLibraryActivation $activation;$activation=$null
      $record.observations+=@{label=$packageInput.label;archive=$packageInput;timings=$timings;native_observation=@{path=$observationPath;sha256=(Get-FileHash -LiteralPath $observationPath).Hash};save=@{path=$save;sha256=(Get-FileHash -LiteralPath $save).Hash};stages=$stages;library_activation=$terminal}
    }
    Assert-MIR441CleanTrackedSource -RepoRoot $repo
    if((&git -C $repo rev-parse HEAD).Trim()-cne$source-or(Get-FileHash -LiteralPath $engine).Hash-cne$profile.engine_sha256){throw '[mir-research-all-input-drift]'}
    $record.status='observed-exact-package-pair-not-full-performance-qualification'
  }catch{$record.status='failed';$record.error=$_.Exception.Message}
  finally{
    if($null-ne$activation){try{$record.failure_controls=Complete-MIRLibraryActivation $activation}catch{$record.status='failed';$record.control_restoration_error=$_.Exception.Message}}
    $record.resource_runs=$resources.runs.ToArray()
    Write-MIRNativeProbeResult -Context $resources -Record $record
  }
  if($record.status-ceq'failed'){throw $record.error}
}
