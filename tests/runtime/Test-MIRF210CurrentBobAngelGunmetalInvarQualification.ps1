# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string[]]$LocalModLibraryDirs,
  [Parameter(Mandatory)][string]$SettingsPath,
  [Parameter(Mandatory)][ValidatePattern('^[0-9A-F]{64}$')][string]$SettingsSha256,
  [Parameter(Mandatory)][string]$CandidateZip,
  [Parameter(Mandatory)][string]$SourceMaterializationPath,
  [ValidateSet('Observe','Qualification')][string]$Mode='Observe',
  [ValidatePattern('^4[.](?:0|[1-9][0-9]{0,4})[.](?:0|[1-9][0-9]?)$')][string]$SourceVersion='4.7.0',
  [string]$OutputRoot='build/tmp/f210-ba-gunmetal-invar',
  [ValidateRange(1,8192)][int]$ExpectedPeakMemoryMiB=2048,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=384,
  [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Assert-GI([bool]$Condition,[string]$Message) { if(-not $Condition){throw "[mir-f210-current-ba-gunmetal-invar] $Message"} }
function Get-GISha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()}
function Get-GIRelative([string]$Repository,[string]$Path){
  $full=[IO.Path]::GetFullPath($Path);$prefix=$Repository.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  Assert-GI ($full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) "artifact outside repository: $full"
  $full.Substring($prefix.Length).Replace('\','/')
}
function Get-GIArtifact([string]$Repository,[string]$Path,[switch]$AllowExternalInput){
  $item=Get-Item -LiteralPath $Path -ErrorAction Stop;Assert-MIRLibraryPath $item.FullName
  [ordered]@{path=$(if($AllowExternalInput){$item.FullName}else{Get-GIRelative $Repository $item.FullName});path_kind=$(if($AllowExternalInput){'machine-local-input'}else{'repository-relative'});bytes=[int64]$item.Length;raw_sha256=Get-GISha $item.FullName}
}
function Assert-GIPath([string]$Path,[string]$Context){Assert-MIRFactorioPathBudget -Path $Path -Context $Context -MaximumLength 240}
function Copy-GIRecord($Value){($Value|ConvertTo-Json -Depth 50)|ConvertFrom-Json -AsHashtable -Depth 50}
function Get-GIFailureCode($ErrorRecord){
  $message=[string]$ErrorRecord.Exception.Message
  if($message -match '^\[(?<code>[^\]]+)\]'){return '['+$Matches.code+']'}
  return '[mir-f210-current-ba-gunmetal-invar-unclassified-failure]'
}
function Read-GICandidate([string]$Repository,[string]$Archive,[string]$Receipt,[string]$Version){Read-MIRNativeProbeF210CurrentCandidate -Repository $Repository -Archive $Archive -ReceiptPath $Receipt -SourceVersion $Version}
function Read-GIDossier([string]$Path){
  $dossier=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json -Depth 50 -DateKind String
  Assert-GI ([int]$dossier.schema -eq 1 -and [string]$dossier.kind -ceq 'MIRF210CurrentBobAngelGunmetalInvarDirectLibraryQualificationV3') 'fixture direct-library dossier identity differs'
  Assert-GI ([string]$dossier.target.engine.version -ceq '2.1.22' -and [string]$dossier.target.engine.sha256 -ceq 'D8C745FD4E8C901BF0FC250C4D0FF75B454987857C1AEAADF8E775F0E65A9E4B') 'fixture 2.1.22 engine identity differs'
  Assert-GI ((@($dossier.target.official_mods).Count -eq 5) -and (@($dossier.target.archives).Count -eq 11)) 'fixture closure cardinality differs'
  Assert-GI ([string]$dossier.settings.mode -ceq 'File' -and [bool]$dossier.settings.portable_input_required) 'fixture settings contract differs'
  foreach($fixtureMode in @('observe','qualification')){
    $fixture=$dossier.fixtures.$fixtureMode
    Assert-GI ($null -ne $fixture -and [string]$fixture.name -match '^mir-fixture-' -and [string]$fixture.version -cmatch '^(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)$') "fixture contract differs: $fixtureMode"
  }
  $dossier
}
function Read-GIDirectLibraryInputs($Dossier,[string]$Library,$Candidate,[string]$FixtureRoot,$FixtureSpec){
  Assert-GI (Test-Path -LiteralPath $Library -PathType Container) 'selected direct library is absent';Assert-MIRLibraryPath $Library
  $hashes=[ordered]@{};$rows=@(foreach($name in @($Dossier.target.official_mods)){[ordered]@{name=[string]$name;version=[string]$Dossier.target.engine.version;enabled=$true}})
  foreach($archive in @($Dossier.target.archives)){
    $file=[string]$archive.file;Assert-GI ($file -ceq (([string]$archive.name)+'_'+([string]$archive.version)+'.zip')) "dossier archive filename differs: $file"
    $hashes[$file]=[string]$archive.sha256;$rows+=[ordered]@{name=[string]$archive.name;version=[string]$archive.version;enabled=$true}
  }
  $null=Resolve-MIRNativeProbeDependencyInputs -ExpectedArchives $hashes -LocalModLibraryDirs @($Library)
  $candidateName=[IO.Path]::GetFileName([string]$Candidate.path);$candidatePath=Join-Path $Library $candidateName
  Assert-GI (Test-Path -LiteralPath $candidatePath -PathType Leaf) 'install-selected-candidate-once-in-library';Assert-MIRLibraryPath $candidatePath
  $candidateSha=Get-GISha $Candidate.path;Assert-GI ((Get-GISha $candidatePath) -ceq $candidateSha) 'library candidate bytes differ'
  $hashes[$candidateName]=$candidateSha;$rows+=[ordered]@{name='more-infinite-research';version=[string]$Candidate.receipt.distribution_version;enabled=$true}
  $fixtureInfo=Get-Content -LiteralPath (Join-Path $FixtureRoot 'info.json') -Raw|ConvertFrom-Json -Depth 20
  Assert-GI ([string]$fixtureInfo.name -ceq [string]$FixtureSpec.name -and [string]$fixtureInfo.version -ceq [string]$FixtureSpec.version) 'selected fixture identity differs'
  $fixtureName=([string]$fixtureInfo.name)+'_'+([string]$fixtureInfo.version)+'.zip';$fixtureArchive=Join-Path $Library $fixtureName
  Assert-GI (Test-Path -LiteralPath $fixtureArchive -PathType Leaf) 'install-prebuilt-fixture-once-in-library';Assert-MIRLibraryFixtureArchive -Archive $fixtureArchive -SourceDirectory $FixtureRoot
  $hashes[$fixtureName]=Get-GISha $fixtureArchive;$rows+=[ordered]@{name=[string]$fixtureInfo.name;version=[string]$fixtureInfo.version;enabled=$true}
  [pscustomobject]@{mod_list=[ordered]@{mods=$rows};archive_hashes=$hashes;candidate=$candidatePath;fixture_archive=$fixtureArchive}
}
function Invoke-GIGovernedEngine([string]$Scenario,[string[]]$Arguments,[int]$TimeoutSeconds){
  $safe=Get-MIRSafeScenarioFileName -Name $Scenario;Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $Arguments
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
  $log=Join-Path $run ($safe+'.factorio.log');$captured=Copy-MIRCompatFactorioCurrentLog -UserDataDir $run -Destination $log
  $null=Get-MIRNativeProbeRemainingOutputBytes -Context $resources;Assert-GI (-not [string]::IsNullOrWhiteSpace($captured)) 'Factorio log is absent'
  # Factorio appends to the raw current log across cold launches. Keep that raw
  # file, and bind each scenario capture/assertion to its own native invocation.
  $currentInvocation=Get-MIRLibraryLatestInvocationText -Text ([IO.File]::ReadAllText($captured))
  [IO.File]::WriteAllText($captured,$currentInvocation,[Text.UTF8Encoding]::new($false))
  $null=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $captured -LatestInvocation -ActiveModsObserver ([string]$fixtureSpec.name)
  [pscustomobject]@{scenario=$Scenario;passed=$true;duration_seconds=$actor.result.duration_seconds;stdout=$actor.stdout;stderr=$actor.stderr;factorio_log=$captured}
}
function Invoke-GIReload([string]$SavePath,[int]$Ordinal,[int]$TimeoutSeconds){
  $save=(Resolve-Path -LiteralPath $SavePath).Path;$before=Get-GISha $save
  $arguments=@('--config',(Join-Path $run 'mir-compat-config.ini'),'--no-log-rotation','--disable-audio','--mod-directory',$activation.library,'--benchmark',$save,'--benchmark-ticks','30000','--benchmark-runs','1','--benchmark-sanitize')
  $process=Invoke-GIGovernedEngine -Scenario ('f210-ba-gunmetal-invar.reload-'+$Ordinal.ToString('00')) -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
  $after=Get-GISha $save
  [pscustomobject]@{ordinal=$Ordinal;cold_process=true;passed=[bool]($process.passed -and $before -ceq $after);duration_seconds=$process.duration_seconds;maximum_duration_seconds=$TimeoutSeconds;input_save_sha256=$before;save_sha256=$after;save_byte_identical=[bool]($before -ceq $after);stdout=$process.stdout;stderr=$process.stderr;factorio_log=$process.factorio_log}
}
function Convert-GIObservationLine([string]$Kind,[string]$Text){
  $row=[ordered]@{kind=$Kind}
  foreach($part in @($Text -split ' ')){
    $pair=$part.Split('=',2)
    if($pair.Count -eq 2 -and $pair[0] -match '^[a-z_]+$'){$row[$pair[0]]=$pair[1]}
  }
  $row
}
function Get-GIObservation([string]$LogText){
  Assert-GI ($LogText.Contains('[mir-f210-current-ba-gunmetal-invar-observer] DATA PASS read-only-finalized-fact-capture',[StringComparison]::Ordinal)) 'read-only data marker is absent'
  $rows=@();foreach($match in [regex]::Matches($LogText,'(?m)^.*\[mir-f210-current-ba-gunmetal-invar-observer\] (?<kind>ROUTE|CERTIFICATE|BINDING|EMISSION) (?<text>[^\r\n]+)$')){$rows+=,(Convert-GIObservationLine $match.Groups['kind'].Value $match.Groups['text'].Value)}
  foreach($kind in @('ROUTE','CERTIFICATE','BINDING','EMISSION')){
    $selected=@($rows|Where-Object {$_.kind -ceq $kind}|Sort-Object family)
    Assert-GI ($selected.Count -eq 2 -and ((@($selected.family)-join ',') -ceq 'gunmetal,invar')) "read-only $kind records differ"
  }
  [ordered]@{records=$rows;runtime_markers=@([regex]::Matches($LogText,'\[mir-f210-current-ba-gunmetal-invar-observer\] RUNTIME stage=(?:create|reload) [^\r\n]+')|ForEach-Object {$_.Value})}
}

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $repo 'tools/lib/compatibility/LibraryActivation.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
$dossierPath=Join-Path $repo 'fixtures/run-profiles/f210-bob-angel-gunmetal-invar-2122.json'
Assert-GI (Test-Path -LiteralPath $dossierPath -PathType Leaf) 'direct-library dossier is absent'
$dossier=Read-GIDossier $dossierPath
$fixtureSpec=if($Mode -ceq 'Observe'){$dossier.fixtures.observe}else{$dossier.fixtures.qualification}
$fixtureRoot=Join-Path $repo ([string]$fixtureSpec.source_path)
foreach($file in @('info.json','data-final-fixes.lua','control.lua')){Assert-GI (Test-Path -LiteralPath (Join-Path $fixtureRoot $file) -PathType Leaf) "fixture is incomplete: $file"}
if($Mode -ceq 'Observe'){Assert-GI (Test-Path -LiteralPath (Join-Path $fixtureRoot 'settings-updates.lua') -PathType Leaf) 'observer phase-aware setting path is absent'}
Assert-GI ($LocalModLibraryDirs.Count -eq 1) 'supply exactly one explicit flat archive library'
$library=(Resolve-Path -LiteralPath $LocalModLibraryDirs[0]).Path;$settings=(Resolve-Path -LiteralPath $SettingsPath).Path
$portableSettings=(Resolve-Path -LiteralPath (Join-Path $repo ([string]$dossier.settings.portable_path))).Path
Assert-MIRLibraryPath $settings;Assert-GI ($settings -ceq $portableSettings -and $SettingsSha256 -ceq [string]$dossier.settings.portable_sha256 -and (Get-GISha $settings) -ceq $SettingsSha256) 'portable settings identity differs'
$candidate=Read-GICandidate -Repository $repo -Archive $CandidateZip -Receipt $SourceMaterializationPath -Version $SourceVersion
$direct=Read-GIDirectLibraryInputs -Dossier $dossier -Library $library -Candidate $candidate -FixtureRoot $fixtureRoot -FixtureSpec $fixtureSpec
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path;Assert-MIRLibraryPath $engine;Assert-GI ((Get-GISha $engine) -ceq [string]$dossier.target.engine.sha256) 'selected engine binary differs'
$sourceCommit=(& git -C $repo rev-parse HEAD).Trim();$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim();Assert-GI ($sourceCommit -match '^[0-9a-f]{40}$' -and $sourceTree -match '^[0-9a-f]{40}$') 'source Git identity is invalid'
$prepared=[ordered]@{
  schema=3;kind='MIRF210CurrentBobAngelGunmetalInvarDirectLibraryQualificationV3';status='prepared-direct-library-not-run';mode=$Mode
  scope=if($Mode -ceq 'Observe'){'Read-only finalized Gunmetal/Invar fact capture with fresh create and two cold reloads. It does not assert generated technologies, mutate force state, admit a route, or establish production or upgrade investment.'}else{'Narrow structural admission only: emitted effects, fresh create, and two distinct cold reloads. It sets fixture research state but does not establish earned production, force effects, investment, compatibility breadth, performance, multiplayer or release readiness.'}
  source=[ordered]@{commit=$sourceCommit;tree=$sourceTree;source_version=$candidate.receipt.source_version;distribution_version=$candidate.receipt.distribution_version;package_source_sha256=$candidate.receipt.package_source_sha256}
  prior_environment=$dossier.historical_2_1_20
  target=[ordered]@{engine=[ordered]@{version=$dossier.target.engine.version;sha256=$dossier.target.engine.sha256};official_mods=@($dossier.target.official_mods);archives=@($dossier.target.archives);settings=[ordered]@{mode='File';portable_input=$true;sha256=$SettingsSha256}}
  candidate=Get-GIArtifact $repo $candidate.path -AllowExternalInput;fixture=@(Get-ChildItem -LiteralPath $fixtureRoot -Recurse -File|Sort-Object FullName|ForEach-Object{Get-GIArtifact $repo $_.FullName});portable_settings=Get-GIArtifact $repo $portableSettings;harness=Get-GIArtifact $repo $PSCommandPath
  non_claims=@($dossier.explicit_non_claims)
}
if($PrepareOnly){$prepared|ConvertTo-Json -Depth 50;return}
$output=[IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($OutputRoot)){$OutputRoot}else{Join-Path $repo $OutputRoot}));$buildPrefix=[IO.Path]::GetFullPath((Join-Path $repo 'build')).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar;Assert-GI ($output.StartsWith($buildPrefix,[StringComparison]::OrdinalIgnoreCase)) 'output root must be inside build'
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxWorktrees 8 -MaxBranches 32|Out-Host
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
$run=$resources.root;Assert-GIPath $run 'F210 Gunmetal/Invar direct-library run root';$activation=$null;$terminal=$null;$restoration=[ordered]@{attempted=$false;status='not-needed'};$stage='initialize';$failure=$null
try{
  New-Item -ItemType Directory -Force -Path (Join-Path $run 'saves')|Out-Null
  $profile=Join-Path $run 'selection.json';[IO.File]::WriteAllText($profile,($direct.mod_list|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
  $engineRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $engine))
  $stage='activate-direct-library';$activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory (Join-Path $engineRoot 'data') -ProfilePath $profile -ArchiveHashes $direct.archive_hashes -SettingsMode File -SettingsPath $settings -SettingsSha256 $SettingsSha256;Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
  $config=Join-Path $run 'mir-compat-config.ini';[IO.File]::WriteAllText($config,"[path]`nread-data=$(Join-Path $engineRoot 'data')`nwrite-data=$run`n`n[general]`nlocale=auto`n`n[other]`nenable-new-mods=false`nenable-steam-networking=false`ndisable-blueprint-storage=true`n",[Text.UTF8Encoding]::new($false))
  $stage='verify-engine';$versionActor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments @('--version') -TimeoutSeconds 10;$version=Get-Content -LiteralPath $versionActor.stdout -Raw;Assert-GI ($version -match 'Version:\s+2[.]1[.]22(?:\s|$)') 'engine reported a different version'
  $stage='fresh-create';$save=Join-Path $run 'saves/f210-ba-gunmetal-invar.zip';$fresh=Invoke-GIGovernedEngine -Scenario ('f210-ba-gunmetal-invar.'+$Mode.ToLowerInvariant()+'.create') -Arguments @('--config',$config,'--no-log-rotation','--create',$save,'--mod-directory',$library,'--disable-audio') -TimeoutSeconds 300;Assert-GI (Test-Path -LiteralPath $save -PathType Leaf) 'fresh create save is absent'
  $freshLog=[IO.File]::ReadAllText($fresh.factorio_log)
  if($Mode -ceq 'Observe'){$observation=Get-GIObservation $freshLog;Assert-GI (@($observation.runtime_markers|Where-Object {$_ -match 'stage=create'}).Count -eq 1) 'read-only create marker differs'}else{Assert-GI ($freshLog.Contains([string]$fixtureSpec.data_marker,[StringComparison]::Ordinal) -and $freshLog.Contains([string]$fixtureSpec.create_marker,[StringComparison]::Ordinal)) 'fresh structural/create markers differ'}
  $reloads=@();foreach($ordinal in 1..2){$stage='cold-reload-'+$ordinal;$reload=Invoke-GIReload -SavePath $save -Ordinal $ordinal -TimeoutSeconds 300;Assert-GI ([bool]$reload.passed) "bounded cold reload failed: $ordinal";$reloadLog=[IO.File]::ReadAllText($reload.factorio_log);if($Mode -ceq 'Observe'){Assert-GI ($reloadLog.Contains('[mir-f210-current-ba-gunmetal-invar-observer] RUNTIME stage=reload',[StringComparison]::Ordinal)) "read-only reload marker differs: $ordinal"}else{Assert-GI ($reloadLog.Contains([string]$fixtureSpec.data_marker,[StringComparison]::Ordinal) -and $reloadLog.Contains([string]$fixtureSpec.reload_marker,[StringComparison]::Ordinal)) "reload structural/state markers differ: $ordinal"};$reloads+=,$reload}
  $stage='source-stability';Assert-GI ((Get-GISha $engine) -ceq [string]$dossier.target.engine.sha256 -and (&git -C $repo rev-parse HEAD).Trim() -ceq $sourceCommit -and @(&git -C $repo status --porcelain --untracked-files=all).Count -eq 0) 'engine or source changed during run'
  $stage='restore-direct-library';$restoration.attempted=$true
  try{$terminal=Complete-MIRLibraryActivation $activation;$activation=$null;$restoration.status='restored';$restoration.record=$terminal}catch{$restoration.status='restore-failed';$restoration.failure_code=Get-GIFailureCode $_;throw}
  $result=Copy-GIRecord $prepared;$result.status=if($Mode -ceq 'Observe'){'observed-read-only'}else{'passed-narrow-structural-admission'};$result.engine=[ordered]@{version=([regex]::Match($version,'Version:\s+[^\r\n]+').Value).Trim();executable_sha256=Get-GISha $engine};$result.run_root=Get-GIRelative $repo $run;$result.fresh_create=[ordered]@{passed=$fresh.passed;duration_seconds=$fresh.duration_seconds;save=Get-GIArtifact $repo $save;stdout=Get-GIArtifact $repo $fresh.stdout;stderr=Get-GIArtifact $repo $fresh.stderr;factorio_log=Get-GIArtifact $repo $fresh.factorio_log};$result.cold_reloads=@($reloads|ForEach-Object{[ordered]@{ordinal=$_.ordinal;cold_process=$_.cold_process;passed=$_.passed;duration_seconds=$_.duration_seconds;maximum_duration_seconds=$_.maximum_duration_seconds;input_save_sha256=$_.input_save_sha256;save_sha256=$_.save_sha256;save_byte_identical=$_.save_byte_identical;stdout=Get-GIArtifact $repo $_.stdout;stderr=Get-GIArtifact $repo $_.stderr;factorio_log=Get-GIArtifact $repo $_.factorio_log}});if($Mode -ceq 'Observe'){$result.observation=$observation};$result.mod_closure=[ordered]@{candidate=Get-GIArtifact $repo $direct.candidate -AllowExternalInput;fixture=Get-GIArtifact $repo $direct.fixture_archive -AllowExternalInput;settings=[ordered]@{mode='File';sha256=$SettingsSha256};library_activation=$terminal};$result.controls_restoration=$restoration;$result.resource_runs=$resources.runs.ToArray();Write-MIRNativeProbeResult -Context $resources -Record $result;Write-Output "[MIR-F210-BA-GUNMETAL-INVAR] $(Get-GIRelative $repo (Join-Path $run 'result.json'))"
}catch{$failure=$_}finally{
  if($null -ne $activation -and -not $activation.closed){$restoration.attempted=$true;try{$terminal=Complete-MIRLibraryActivation $activation;$activation=$null;$restoration.status='restored-after-terminal-failure';$restoration.record=$terminal}catch{$restoration.status='restore-failed-after-terminal-failure';$restoration.failure_code=Get-GIFailureCode $_;if($null -eq $failure){$failure=$_}}}
  if($null -ne $failure){$failed=Copy-GIRecord $prepared;$failed.status='failed-terminal-result-retained';$failed.terminal=[ordered]@{stage=$stage;failure_code=Get-GIFailureCode $failure;exception_type=$failure.Exception.GetType().FullName;controls_restoration=$restoration};$failed.run_root=if($null -ne $resources -and (Test-Path -LiteralPath $resources.root -PathType Container)){Get-GIRelative $repo $resources.root}else{''};if($null -ne $resources){$failed.resource_runs=$resources.runs.ToArray();try{Write-MIRNativeProbeResult -Context $resources -Record $failed}catch{}}}
}
if($null -ne $failure){throw $failure}
