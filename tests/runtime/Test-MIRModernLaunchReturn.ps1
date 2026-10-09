# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('f200','f210')][string]$Target,
  [Parameter(Mandatory)][string]$FactorioExe,
  [Parameter(Mandatory)][string]$LibraryDirectory,
  [Parameter(Mandatory)][string]$CandidateZip,
  [Parameter(Mandatory)][string]$SourceMaterializationPath,
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$OutputRoot='build/p/modern-launch-return',
  [ValidateRange(1,8192)][int]$ExpectedPeakMemoryMiB=768,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120,
  [switch]$PrepareInputs
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$Target=$Target.ToLowerInvariant()
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')

function Assert-Launch([bool]$Condition,[string]$Message){if(-not $Condition){throw "[mir-a04-launch] $Message"}}
function Get-LaunchArtifact([string]$Path){
  $item=Get-Item -LiteralPath $Path
  return [ordered]@{path=$item.FullName;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash;bytes=$item.Length}
}
function Read-LaunchObservation([string]$Text,[string]$Stage){
  $rows=@([regex]::Matches($Text,'\[mir-a04-launch\] RESULT (\{[^\r\n]+\})')|ForEach-Object {$_.Groups[1].Value|ConvertFrom-Json})
  $selected=@($rows|Where-Object stage -CEQ $Stage)
  Assert-Launch ($selected.Count-eq1) "expected one $Stage observation"
  return $selected[0]
}
function Assert-LaunchProduction($Row,[string]$Stage,[string]$BaseVersion,[string]$MirVersion){
  Assert-Launch ($Row.stage-ceq$Stage-and$Row.base-ceq$BaseVersion-and$Row.mir-ceq$MirVersion) 'observation identity differs'
  Assert-Launch ($Row.phase-ceq'complete'-and$Row.crafts-eq100-and$Row.rockets_launched-eq1-and$Row.return_count-eq1000-and$Row.launch_ordered-eq$true) 'native production differs'
  Assert-Launch ($Row.lab_transfer-gt0-and$Row.lab_transfer-lt1000-and$Row.pad_count-eq(1000-$Row.lab_transfer)) 'science transfer differs'
  Assert-Launch ($Row.technology-ceq'research-speed-7'-and$Row.progress-gt0-and$Row.progress-lt1-and$Row.progress-eq$Row.saved_progress) 'earned research differs'
  foreach($name in @('processing-unit','low-density-structure','rocket-fuel')){
    Assert-Launch ($Row.feed_remaining.$name-eq0-and$Row.consumed.$name-eq1000) "construction input differs: $name"
  }
}
function Invoke-LaunchEngine([string]$Stage,[string[]]$Arguments,[int]$Timeout=120,[scriptblock]$Completion){
  $live=Join-Path $userdata 'factorio-current.log'
  if(Test-Path -LiteralPath $live){Remove-Item -LiteralPath $live}
  $argsList=@('--config',$config,'--mod-directory',$library,'--no-log-rotation','--disable-audio')+$Arguments
  Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $argsList
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments $argsList -TimeoutSeconds $Timeout -CompletionPredicate $Completion
  Assert-Launch ([bool]$actor.result.passed) "engine failed: $Stage"
  $log=Join-Path $run ($Stage+'.factorio.log')
  Copy-Item -LiteralPath $live -Destination $log
  $loaded=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log
  $null=Get-MIRNativeProbeRemainingOutputBytes -Context $resources
  return [pscustomobject]@{log=$log;actor=$actor;loaded=$loaded}
}

Assert-Launch (@(& git -C $repo status --porcelain).Count-eq0) 'clean committed source required'
$source=(& git -C $repo rev-parse HEAD).Trim()
$fixture=Join-Path $repo 'fixtures/assert-modern-launch-return'
$scenario=Get-Content -LiteralPath (Join-Path $fixture 'scenario.json') -Raw|ConvertFrom-Json
$binding=$scenario.targets.$Target
$engine=(Resolve-Path -LiteralPath $FactorioExe).Path
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
Assert-Launch ((Get-FileHash -LiteralPath $engine).Hash-ceq$binding.engine_sha256) 'engine hash differs from selected scenario'
Assert-Launch ((Get-FileHash -LiteralPath (Join-Path $engineRoot 'doc-html/runtime-api.json')).Hash-ceq$binding.runtime_api_sha256) 'installed runtime API differs'
$base=Get-Content -LiteralPath (Join-Path $engineRoot 'data/base/info.json') -Raw|ConvertFrom-Json
Assert-Launch ($base.version-ceq$binding.engine_version) 'installed base version differs'
$candidate=Read-MIRNativeProbeCurrentCandidate -Repository $repo -Archive $CandidateZip -ReceiptPath $SourceMaterializationPath -Target $Target -SourceVersion $scenario.source_version
$library=(Resolve-Path -LiteralPath $LibraryDirectory).Path
$installed=Join-Path $library ([IO.Path]::GetFileName($CandidateZip))
Assert-Launch (Test-Path -LiteralPath $installed -PathType Leaf) "install the supplied MIR candidate once in the selected library: $installed"
Assert-Launch ((Get-FileHash -LiteralPath $installed).Hash-ceq$candidate.receipt.archive_sha256) 'installed MIR candidate bytes differ'
Assert-MIRLibraryIdle
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 2 -MaxEntriesPerRoot 500 | Out-Host
# Preparing only the small fixture runs no engine or package builder. Run mode
# retains the separately declared native memory allowance and unchanged reserve.
$peak=if($PrepareInputs){32}else{$ExpectedPeakMemoryMiB}
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $peak -MaxNewOutputMiB $MaxNewOutputMiB
$run=$resources.root
$prepared=Join-Path $run 'fixture-source'
[IO.Directory]::CreateDirectory($prepared)|Out-Null
$info=Get-Content -LiteralPath (Join-Path $fixture 'info.json') -Raw|ConvertFrom-Json
$info.factorio_version=$binding.factorio_line
$info.dependencies=@("base = $($binding.engine_version)","more-infinite-research = $($candidate.receipt.distribution_version)")
$info|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $prepared 'info.json') -Encoding utf8NoBOM
[IO.File]::WriteAllBytes((Join-Path $prepared 'control.lua'),[IO.File]::ReadAllBytes((Join-Path $fixture 'control.lua')))
$fixtureArchive=Join-Path $library ($info.name+'_'+$info.version+'.zip')
$installedFixtureBytes=0L
$preparationReceipt=$null
if(-not(Test-Path -LiteralPath $fixtureArchive)){
  Assert-Launch ([bool]$PrepareInputs) 'fixture archive missing; run PrepareInputs once for this selected library'
  $prepareSelection=Join-Path $run 'prepare-selection.json'
  @{mods=@(@{name='base';version=$binding.engine_version;enabled=$true},@{name='more-infinite-research';version=$candidate.receipt.distribution_version;enabled=$true})}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $prepareSelection -Encoding utf8NoBOM
  $prepareHashes=@{};$prepareHashes[[IO.Path]::GetFileName($installed)]=$candidate.receipt.archive_sha256
  $lease=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory (Join-Path $engineRoot 'data') -ProfilePath $prepareSelection -ArchiveHashes $prepareHashes -SettingsMode Defaults
  try{
    Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $lease
    # Recheck under the actual library lock; another checkout may have prepared it.
    if(-not(Test-Path -LiteralPath $fixtureArchive)){
      $fixtureArchive=Publish-MIRModDirectoryArchive -Source $prepared -Name $info.name -Version $info.version -ModsDir $library
      $installedFixtureBytes=(Get-Item -LiteralPath $fixtureArchive).Length
      $resources.max_new_output_bytes-=$installedFixtureBytes
    }
    Assert-MIRLibraryFixtureArchive -Archive $fixtureArchive -SourceDirectory $prepared
  }finally{$preparationReceipt=Complete-MIRLibraryActivation -Activation $lease}
}
# Existing same-identity fixture bytes are verified, never overwritten.
Assert-MIRLibraryFixtureArchive -Archive $fixtureArchive -SourceDirectory $prepared
$record=[ordered]@{kind='MIRModernLaunchReturnV1';status='prepared';source_commit=$source;target=$Target;scenario=Get-LaunchArtifact (Join-Path $fixture 'scenario.json');fixture_source=Get-LaunchArtifact (Join-Path $fixture 'control.lua');candidate=$candidate.receipt;engine=Get-LaunchArtifact $engine;fixture=Get-LaunchArtifact $fixtureArchive;scope=$scenario.scope;new_fixture_bytes_installed=$installedFixtureBytes;dependency_payload_bytes_copied=0;archive_links_created=0;dependency_extractions=0;native_qualification=$false}
$record.preparation_control_restoration=$preparationReceipt
if($PrepareInputs){Write-MIRNativeProbeResult -Context $resources -Record $record;return}
$userdata=Join-Path $run 'userdata'
[IO.Directory]::CreateDirectory((Join-Path $userdata 'saves'))|Out-Null
$config=Join-Path $run 'config.ini'
"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($userdata.Replace('\','/'))`n[other]`nenable-new-mods=false`ncheck-updates=false`ndisable-blueprint-storage=true`nenable-blueprint-storage-cloud-sync=false`n[graphics]`ncache-sprite-atlas=false`n"|Set-Content -LiteralPath $config -Encoding utf8NoBOM
$server=Join-Path $run 'server-settings.json'
@{name='MIR A04 private launch fixture';visibility=@{public=$false;lan=$false};require_user_verification=$false;auto_pause=$false;autosave_interval=0}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $server -Encoding utf8NoBOM
$selection=Join-Path $run 'selection.json'
@{mods=@(@{name='base';version=$binding.engine_version;enabled=$true},@{name='more-infinite-research';version=$candidate.receipt.distribution_version;enabled=$true},@{name=$info.name;version=$info.version;enabled=$true})}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $selection -Encoding utf8NoBOM
$hashes=@{};$hashes[[IO.Path]::GetFileName($installed)]=$candidate.receipt.archive_sha256;$hashes[[IO.Path]::GetFileName($fixtureArchive)]=(Get-FileHash -LiteralPath $fixtureArchive).Hash
$activation=$null
try{
  $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory (Join-Path $engineRoot 'data') -ProfilePath $selection -ArchiveHashes $hashes -SettingsMode Defaults
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
  $seed=Join-Path $userdata 'saves/seed.zip'
  $create=Invoke-LaunchEngine -Stage create -Arguments @('--create',$seed)
  $initial=Read-LaunchObservation -Text (Get-Content -LiteralPath $create.log -Raw) -Stage create
  Assert-Launch ($initial.phase-ceq'constructing'-and$initial.pad_count-eq0-and$initial.rockets_launched-eq0) 'fresh factory state differs'
  $seedArtifact=Get-LaunchArtifact $seed
  $complete=Join-Path $userdata 'saves/mir-a04-launch-complete.zip'
  $live=Join-Path $userdata 'factorio-current.log'
  $done={
    if(-not(Test-Path -LiteralPath $complete)-or-not(Test-Path -LiteralPath $live)){return $false}
    try{$text=Get-Content -LiteralPath $live -Raw -ErrorAction Stop}catch [IO.IOException]{return $false}
    return ($null-ne$text-and$text.Contains('[mir-a04-launch] RESULT ')-and$text.Contains('Saving finished'))
  }.GetNewClosure()
  $production=Invoke-LaunchEngine -Stage production -Arguments @('--server-settings',$server,'--bind','127.0.0.1','--start-server',$seed) -Timeout $scenario.production_timeout_seconds -Completion $done
  Assert-Launch ([bool]$production.actor.result.completion_predicate_observed) 'completed production save not observed'
  $produced=Read-LaunchObservation -Text (Get-Content -LiteralPath $production.log -Raw) -Stage production
  Assert-LaunchProduction $produced production $binding.engine_version $candidate.receipt.distribution_version
  $saved=Get-LaunchArtifact $complete
  $reload=Invoke-LaunchEngine -Stage reload -Arguments @('--benchmark',$complete,'--benchmark-ticks','10','--benchmark-runs','1','--benchmark-sanitize')
  $reloaded=Read-LaunchObservation -Text (Get-Content -LiteralPath $reload.log -Raw) -Stage reload
  Assert-LaunchProduction $reloaded reload $binding.engine_version $candidate.receipt.distribution_version
  Assert-Launch ($reloaded.progress-eq$produced.progress-and$reloaded.lab_transfer-eq$produced.lab_transfer-and$reloaded.pad_count-eq$produced.pad_count) 'reloaded earned state differs'
  Assert-Launch ((Get-FileHash -LiteralPath $complete).Hash-ceq$saved.sha256) 'benchmark mutated saved input'
  Assert-Launch ((Get-FileHash -LiteralPath $seed).Hash-ceq$seedArtifact.sha256) 'production mutated its initial save'
  Assert-Launch ((& git -C $repo rev-parse HEAD).Trim()-ceq$source-and@(& git -C $repo status --porcelain).Count-eq0) 'source changed during native execution'
  Assert-Launch ((Get-FileHash -LiteralPath $engine).Hash-ceq$binding.engine_sha256) 'engine changed during native execution'
  $record.status='passed-focused-native-launch-return'
  $record.native_qualification=$true
  $record.create=$create;$record.production=$production;$record.reload=$reload
  $record.produced=$produced;$record.reloaded=$reloaded;$record.initial_save=$seedArtifact;$record.completed_save=$saved
  $record.library_receipt=Complete-MIRLibraryActivation -Activation $activation
  $activation=$null
  Write-MIRNativeProbeResult -Context $resources -Record $record
}catch{
  $record.status='failed';$record.native_qualification=$false;$record.failure=$_.Exception.Message
  Write-MIRNativeProbeResult -Context $resources -Record $record
  throw
}finally{if($null-ne$activation){$null=Complete-MIRLibraryActivation -Activation $activation}}
