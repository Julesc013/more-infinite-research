# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$CandidateZip,
  [Parameter(Mandatory)][string]$SourceMaterializationPath,
  [ValidateSet('f210','f200')][string]$Target='f210',
  [string]$FactorioExe='',
  [string]$LibraryDirectory='',
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$OutputRoot='build/p/secretas-finite-hotfix',
  [ValidateRange(1,8192)][int]$ExpectedPeakMemoryMiB=1024,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120,
  [switch]$PrepareInputsOnly
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tests/support/MIR421SpaceFakeUpgrade.ps1')
function Assert-Secretas([bool]$Condition,[string]$Message){if(-not$Condition){throw "[mir422-secretas] $Message"}}
function Get-SecretasArtifact([string]$Path){$f=Get-Item -LiteralPath $Path;[ordered]@{path=$f.FullName;sha256=(Get-FileHash -LiteralPath $Path).Hash;bytes=$f.Length}}
function New-SecretasSelectedFixture([string]$Source,[string]$Run,[string]$SelectedTarget){
  if($SelectedTarget-ceq'f210'){return $Source}
  $selected=Join-Path $Run 'fixture-source'
  [IO.Directory]::CreateDirectory($selected)|Out-Null
  $info=Get-Content -LiteralPath (Join-Path $Source 'info.json') -Raw|ConvertFrom-Json
  $info.version='0.1.3';$info.factorio_version='2.0'
  $info.dependencies=@('base = 2.0.77','space-age = 2.0.77','secretas = 1.0.33','pretty-frozeta = 0.1.0','more-infinite-research = 4.2.20002')
  $info|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $selected 'info.json')
  $control=Get-Content -LiteralPath (Join-Path $Source 'control.lua') -Raw
  foreach($pair in @(@('"4.2.21002"','"4.2.20002"'),@('"1.0.37"','"1.0.33"'),@('"1.0.1"','"0.1.0"'),@('"2.1.21"','"2.0.77"'))){
    Assert-Secretas ($control.Contains($pair[0])) 'selected fixture specialization anchor missing'
    $control=$control.Replace($pair[0],$pair[1])
  }
  [IO.File]::WriteAllText((Join-Path $selected 'control.lua'),$control,[Text.UTF8Encoding]::new($false))
  Copy-Item -LiteralPath (Join-Path $Source 'data-final-fixes.lua') -Destination (Join-Path $selected 'data-final-fixes.lua')
  return $selected
}
function Assert-SecretasMarker([string]$Text,[string]$Stage){
  Assert-Secretas ($Text.Contains("[mir-fixture] Secretas finite continuation verified stage=$Stage;level=10;")) "missing $Stage complete-state marker"
}
function Invoke-SecretasEngine([string]$Stage,[string[]]$Arguments,[scriptblock]$Completion=$null){
  $live=Join-Path $userdata 'factorio-current.log'
  if(Test-Path -LiteralPath $live){Remove-Item -LiteralPath $live}
  $argsList=@('--config',$config,'--mod-directory',$library,'--no-log-rotation','--disable-audio')+$Arguments
  Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $argsList
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments $argsList -TimeoutSeconds $scenario.timeout_seconds -CompletionPredicate $Completion
  Assert-Secretas ([bool]$actor.result.passed) "$Stage engine failed"
  $log=Join-Path $run ($Stage+'.factorio.log');Copy-Item -LiteralPath $live -Destination $log
  $loaded=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -ActiveModsObserver $info.name
  $null=Get-MIRNativeProbeRemainingOutputBytes -Context $resources
  [pscustomobject]@{log=$log;actor=$actor;loaded=$loaded}
}
$source=(& git -C $repo rev-parse HEAD).Trim()
if(-not$PrepareInputsOnly){Assert-Secretas (@(& git -C $repo status --porcelain).Count-eq0) 'clean committed source required'}
$fixture=Join-Path $repo 'fixtures/assert-secretas-finite-continuation-hotfix'
$scenarioPath=Join-Path $fixture $(if($Target-ceq'f200'){'scenario-f200.json'}else{'scenario.json'})
$scenario=Get-Content -LiteralPath $scenarioPath -Raw|ConvertFrom-Json
$info=Get-Content -LiteralPath (Join-Path $fixture 'info.json') -Raw|ConvertFrom-Json
$candidate=Read-MIRNativeProbeCurrentCandidate -Repository $repo -Archive $CandidateZip -ReceiptPath $SourceMaterializationPath -Target $scenario.target -SourceVersion $scenario.source_version
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 2 -MaxEntriesPerRoot 500 | Out-Host
$root=if([IO.Path]::IsPathRooted($OutputRoot)){$OutputRoot}else{Join-Path $repo $OutputRoot}
$root=Resolve-MIR441RecoveryScratchPath -Path $root
if($PrepareInputsOnly){
  Assert-Secretas ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($root)).AvailableFreeSpace-ge544MB) 'small fixture preparation disk headroom'
  $run=Join-Path $root ([guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($run)|Out-Null
  $fixture=New-SecretasSelectedFixture -Source $fixture -Run $run -SelectedTarget $Target
  $info=Get-Content -LiteralPath (Join-Path $fixture 'info.json') -Raw|ConvertFrom-Json
  $zip=Publish-MIRModDirectoryArchive -Source $fixture -Name $info.name -Version $info.version -ModsDir $run
  [ordered]@{kind='MIRSecretasFinitePreparedV1';status='prepared-not-native-tested';source_commit=$source;scenario=Get-SecretasArtifact $scenarioPath;fixture=Get-SecretasArtifact $zip;candidate=$candidate.receipt;factorio_processes=0;archive_library_writes=0;dependency_payload_bytes_copied=0;archive_links_created=0}|ConvertTo-Json -Depth 40|Set-Content -LiteralPath (Join-Path $run 'result.json')
  Write-Host "Secretas fixture prepared without Factorio or library writes: $run"
  return
}
Assert-Secretas ([bool]$FactorioExe-and[bool]$LibraryDirectory) 'supply explicit engine and flat library'
$engine=(Resolve-Path -LiteralPath $FactorioExe).Path
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
Assert-Secretas ((Get-FileHash -LiteralPath $engine).Hash-ceq$scenario.engine_sha256) 'selected engine differs'
Assert-Secretas ((Get-FileHash -LiteralPath (Join-Path $engineRoot 'doc-html/runtime-api.json')).Hash-ceq$scenario.runtime_api_sha256) 'selected API differs'
$library=(Resolve-Path -LiteralPath $LibraryDirectory).Path
$deps=@(foreach($row in $scenario.dependencies){
  [ordered]@{file_name=$row.name+'_'+$row.version+'.zip';expected_sha256=$row.sha256;identity=@{name=$row.name;version=$row.version}}
})
$hashes=[ordered]@{};foreach($row in $deps){$hashes[$row.file_name]=$row.expected_sha256}
$null=Resolve-MIRNativeProbeDependencyInputs -ExpectedArchives $hashes -LocalModLibraryDirs @($library)
$installed=Join-Path $library ([IO.Path]::GetFileName($CandidateZip))
Assert-Secretas (Test-Path -LiteralPath $installed -PathType Leaf) "install the supplied MIR candidate once in the library: $installed"
Assert-Secretas ((Get-FileHash -LiteralPath $installed).Hash-ceq$candidate.receipt.archive_sha256) 'installed candidate differs'
Assert-MIRLibraryIdle
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
$run=$resources.root;[IO.Directory]::CreateDirectory($run)|Out-Null
$fixture=New-SecretasSelectedFixture -Source $fixture -Run $run -SelectedTarget $Target
$info=Get-Content -LiteralPath (Join-Path $fixture 'info.json') -Raw|ConvertFrom-Json
$engineData=Join-Path $engineRoot 'data'
# Preparing the tiny assertion archive uses the existing actual library lock.
# Dependencies remain immutable library inputs; only the new fixture is written.
$selection=Get-MIRUpgradeLibrarySelection -Library $library -EngineDataDirectory $engineData -Archive $installed -Version $candidate.receipt.distribution_version -ExpectedSha256 $candidate.receipt.archive_sha256 -Dependencies $deps -FixtureDirectories @() -EnableDlc $true
$profile=Join-Path $run 'prepare-selection.json';$selection.mod_list|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $profile
$prepare=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $engineData -ProfilePath $profile -ArchiveHashes $selection.archive_hashes -SettingsMode Defaults
$newFixtureBytes=0L
try{
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $prepare
  $fixtureArchive=Join-Path $library ($info.name+'_'+$info.version+'.zip')
  if(-not(Test-Path -LiteralPath $fixtureArchive)){
    $fixtureArchive=Publish-MIRModDirectoryArchive -Source $fixture -Name $info.name -Version $info.version -ModsDir $library
    $newFixtureBytes=(Get-Item -LiteralPath $fixtureArchive).Length
    $resources.max_new_output_bytes-=$newFixtureBytes
  }
  Assert-MIRLibraryFixtureArchive -Archive $fixtureArchive -SourceDirectory $fixture
}finally{$preparationReceipt=Complete-MIRLibraryActivation -Activation $prepare}
$selection=Get-MIRUpgradeLibrarySelection -Library $library -EngineDataDirectory $engineData -Archive $installed -Version $candidate.receipt.distribution_version -ExpectedSha256 $candidate.receipt.archive_sha256 -Dependencies $deps -FixtureDirectories @($fixture) -EnableDlc $true
$profile=Join-Path $run 'selection.json';$selection.mod_list|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $profile
$userdata=Join-Path $run 'userdata';[IO.Directory]::CreateDirectory((Join-Path $userdata 'saves'))|Out-Null
$config=Join-Path $run 'config.ini'
"[path]`nread-data=$($engineData.Replace('\','/'))`nwrite-data=$($userdata.Replace('\','/'))`n[other]`nenable-new-mods=false`ncheck-updates=false`ndisable-blueprint-storage=true`nenable-blueprint-storage-cloud-sync=false`n[graphics]`ncache-sprite-atlas=false`n"|Set-Content -LiteralPath $config
$server=Join-Path $run 'server-settings.json';@{name='MIR private Secretas hotfix';visibility=@{public=$false;lan=$false};require_user_verification=$false;auto_pause=$false;autosave_interval=0}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $server
$record=[ordered]@{kind='MIRSecretasFiniteContinuationV1';status='pending';native_qualification=$false;source_commit=$source;scenario=Get-SecretasArtifact $scenarioPath;fixture=Get-SecretasArtifact $fixtureArchive;candidate=$candidate.receipt;engine=Get-SecretasArtifact $engine;scope=$scenario.scope;preparation_controls=$preparationReceipt;new_fixture_bytes_installed=$newFixtureBytes;dependency_payload_bytes_copied=0;archive_links_created=0;dependency_extractions=0}
$activation=$null
try{
  $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $engineData -ProfilePath $profile -ArchiveHashes $selection.archive_hashes -SettingsMode Defaults
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
  $seed=Join-Path $userdata 'saves/seed.zip';$create=Invoke-SecretasEngine -Stage create -Arguments @('--create',$seed)
  $seedArtifact=Get-SecretasArtifact $seed
  $complete=Join-Path $userdata 'saves/mir-secretas-finite-continuation.zip';$live=Join-Path $userdata 'factorio-current.log'
  $done={
    if(-not(Test-Path -LiteralPath $complete)-or-not(Test-Path -LiteralPath $live)){return $false}
    try{$text=Get-Content -LiteralPath $live -Raw -ErrorAction Stop}catch [IO.IOException]{return $false}
    return ($text.Contains('[mir-fixture] Secretas finite continuation verified stage=source;level=10;')-and$text.Contains('Saving finished'))
  }.GetNewClosure()
  $award=Invoke-SecretasEngine -Stage award -Arguments @('--server-settings',$server,'--bind','127.0.0.1','--start-server',$seed) -Completion $done
  Assert-Secretas ([bool]$award.actor.result.completion_predicate_observed) 'completed native award/save not observed'
  Assert-SecretasMarker -Text (Get-Content -LiteralPath $award.log -Raw) -Stage source
  $saved=Get-SecretasArtifact $complete
  $reloads=@(foreach($pass in 1..2){
    $reload=Invoke-SecretasEngine -Stage ('reload-'+$pass) -Arguments @('--benchmark',$complete,'--benchmark-ticks','10','--benchmark-runs','1','--benchmark-sanitize')
    Assert-SecretasMarker -Text (Get-Content -LiteralPath $reload.log -Raw) -Stage reload
    Assert-Secretas ((Get-FileHash -LiteralPath $complete).Hash-ceq$saved.sha256) 'reload mutated input save'
    $reload
  })
  Assert-Secretas ((Get-FileHash -LiteralPath $seed).Hash-ceq$seedArtifact.sha256) 'award run mutated source save'
  Assert-Secretas ((& git -C $repo rev-parse HEAD).Trim()-ceq$source-and@(& git -C $repo status --porcelain).Count-eq0) 'source changed during execution'
  Assert-Secretas ((Get-FileHash -LiteralPath $engine).Hash-ceq$scenario.engine_sha256) 'engine changed during execution'
  $record.status='passed-focused-native-secretas-continuation';$record.native_qualification=$true
  $record.create=$create;$record.award=$award;$record.reloads=$reloads;$record.initial_save=$seedArtifact;$record.completed_save=$saved
  $record.library_receipt=Complete-MIRLibraryActivation -Activation $activation;$activation=$null
  Write-MIRNativeProbeResult -Context $resources -Record $record
}catch{
  $record.status='failed';$record.native_qualification=$false;$record.failure=$_.Exception.Message
  Write-MIRNativeProbeResult -Context $resources -Record $record
  throw
}finally{if($null-ne$activation){$null=Complete-MIRLibraryActivation -Activation $activation}}
