# MIR4-CANONICAL-EXECUTABLE-TEST
# Focused edition consumer of the existing native governor, archive lease and
# complete-state upgrade oracles. No dependency staging or benchmark campaign.
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [Parameter(Mandatory)][ValidateSet('f013','f014','f015','f016','f017','f100','f110','f200','f210')][string]$Target,
  [Parameter(Mandatory)][string]$CandidateZip,
  [Parameter(Mandatory)][string]$CandidateSha256,
  [Parameter(Mandatory)][string]$PublishedZip,
  [Parameter(Mandatory)][string]$PublishedSha256,
  [Parameter(Mandatory)][string]$LibraryDirectory,
  [Parameter(Mandatory)][string]$FactorioBin,
  [string]$OutputRoot='build/tmp/mir471-editions',
  [string]$ResumeSourceRun='',
  [ValidateSet('4.7.1','4.7.2')][string]$SourceVersion='4.7.1',
  [switch]$CryogenicReproducer,
  [switch]$CandidateOnly
)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $RepoRoot 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $RepoRoot 'tests/support/MIR421SpaceFakeUpgrade.ps1')
$code=$Target.Substring(1);$patch=[int]$SourceVersion.Split(".")[2];$from="4.7.${code}0$($patch-1)";$to="4.7.${code}0$patch"
$line=switch($Target){f210{'2.1'};f200{'2.0'};f110{'1.1'};f100{'1.0'};default{'0.'+[int]$code}}
$engineData=Join-Path (Split-Path (Split-Path (Split-Path $FactorioBin))) 'data'
$engineInfo=Get-Content (Join-Path $engineData 'base/info.json') -Raw|ConvertFrom-Json
$engineHash=(Get-FileHash -LiteralPath $FactorioBin).Hash
foreach($pair in @(@($CandidateZip,$CandidateSha256),@($PublishedZip,$PublishedSha256))){if((Get-FileHash -LiteralPath $pair[0]).Hash-cne$pair[1]){throw 'Exact package bytes differ'}}
# These bounded Base/Space Age cases measured at most 425 MiB in the accepted
# 4.7.1 receipts. Keep 768 MiB of child headroom and the unchanged 4 GiB reserve.
$nativePeakMiB=768
$resources=New-MIRNativeProbeResourceContext -RepoRoot $RepoRoot -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $nativePeakMiB -MaxNewOutputMiB 100
$root=$resources.root;[IO.Directory]::CreateDirectory($root)|Out-Null
$userdata=Join-Path $root 'u';[IO.Directory]::CreateDirectory((Join-Path $userdata 'saves'))|Out-Null
$config=Join-Path $root 'config.ini'
[IO.File]::WriteAllText($config,"[path]`nread-data=$($engineData.Replace('\','/'))`nwrite-data=$($userdata.Replace('\','/'))`n[other]`ncheck-updates=false`nenable-new-mods=false`n",[Text.UTF8Encoding]::new($false))
$server=Join-Path $root 'server.json'
@{name='MIR471 edition qualification';description='Private bounded acceptance';visibility=@{public=$false;lan=$false};require_user_verification=$false;auto_pause=$false}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $server
$fixtureName='mir-fixture-471-edition-parity'
$fixtures=@{}
foreach($role in @('source','candidate')){
  $directory=Join-Path $root ('fixture-'+$role);[IO.Directory]::CreateDirectory($directory)|Out-Null
  $fixtureEpoch=if($CryogenicReproducer){2470}elseif($Target-ceq'f210'-and$CandidateOnly){570}else{470}
  $version=if($SourceVersion-ceq'4.7.1'-and-not$CryogenicReproducer){if($role-ceq'source'){'0.3.0'}else{'0.3.1'}}else{'0.'+($fixtureEpoch+$patch)+'.'+$(if($role-ceq'source'){0}elseif($CryogenicReproducer){2}else{1})}
  [ordered]@{name=$fixtureName;version=$version;title='MIR 4.7.1 focused edition acceptance';author='MIR maintainers';factorio_version=$line;dependencies=@("base >= $($engineInfo.version)","more-infinite-research >= $from")}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $directory 'info.json')
  $observer=Get-Content (Join-Path $RepoRoot 'fixtures/assert-mir471-edition-parity/data-final-fixes.lua') -Raw
  if($CryogenicReproducer){$observer+="`n"+(Get-Content (Join-Path $RepoRoot 'fixtures/assert-startup-cryogenic-472/data-final-fixes.lua') -Raw)}
  Copy-Item -LiteralPath (Join-Path $RepoRoot 'source/prototypes/mir/core/fingerprint.lua') -Destination (Join-Path $directory 'mir471_fingerprint.lua')
  [IO.File]::WriteAllText((Join-Path $directory 'data-final-fixes.lua'),$observer,[Text.UTF8Encoding]::new($false))
  if($CryogenicReproducer){
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-startup-cryogenic-472/data-updates.lua') -Destination (Join-Path $directory 'data-updates.lua')
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-startup-cryogenic-472/settings-updates.lua') -Destination (Join-Path $directory 'settings-updates.lua')
  }
  if($Target-ceq'f210'-and-not$CandidateOnly){
    Copy-Item (Join-Path $RepoRoot 'fixtures/assert-upgrade-4-0-21000-to-4-1-21000/*') $directory
    $control=Get-Content (Join-Path $directory 'control.lua') -Raw
    $control=$control.Replace('"4.0.21000"',('"'+$from+'"')).Replace('"4.1.21000"',('"'+$to+'"')).Replace('mir-4121000-upgraded',('mir-'+$to.Replace('.','')+'-upgraded'))
    $control=$control.Replace('  and (from_version:match("^4%.1%.21000$") or from_version:match("^4%.2%.210%d%d$"))',('  and from_version == "'+$from+'"')).Replace('  and to_version:match("^4%.2%.210%d%d$")',('  and to_version == "'+$to+'"'))
    [IO.File]::WriteAllText((Join-Path $directory 'control.lua'),$control,[Text.UTF8Encoding]::new($false))
    [ordered]@{name=$fixtureName;version=$version;title='MIR focused edition acceptance';author='MIR maintainers';factorio_version=$line;dependencies=@("base >= $($engineInfo.version)","space-age >= $($engineInfo.version)","more-infinite-research >= $from")}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $directory 'info.json')
  }elseif($Target-ceq'f200'){
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-upgrade-4-0-20000-to-4-1-20000/settings.lua') -Destination (Join-Path $directory 'settings.lua')
    $settings=Get-Content (Join-Path $directory 'settings.lua') -Raw
    $settings=$settings.Replace('default_value = "space-age-native-owner"','default_value = "base-default"')
    [IO.File]::WriteAllText((Join-Path $directory 'settings.lua'),$settings,[Text.UTF8Encoding]::new($false))
    Set-MIR422F200CompleteStateUpgradeOracle -RepoRoot $RepoRoot -FixtureDirectory $directory -FromVersion $from -ToVersion $to
  }elseif($Target-cne'f210'){
    $control=Get-Content (Join-Path $RepoRoot 'fixtures/assert-upgrade-historical-terminal-to-mir42/control.lua') -Raw
    $infinite=if($Target-cin@('f013','f014')){''}else{'mining-productivity-4'}
    $control=$control.Replace('__MIR_UPGRADE_FROM_VERSION__',$from).Replace('__MIR_UPGRADE_TO_VERSION__',$to).Replace('__MIR_FACTORIO_LINE__',$line).Replace('__MIR_INFINITE_TECHNOLOGY__',$infinite).Replace('__MIR_UPGRADE_SAVE_NAME__','mir471-upgraded')
    $control=$control.Replace('if factorio_line == "0.17" then','if factorio_line == "0.17" or factorio_line == "1.0" or factorio_line == "1.1" then')
    $control=$control.Replace('  seed_source_state()',"  seed_source_state()`n  complete_state_oracle.capture()")
    $control=$control.Replace('local function assert_retained_state(phase)',"local function assert_retained_state(phase)`n  complete_state_oracle.verify(phase == 'reload' and 'reload' or 'upgrade')")
    $prefix='local complete_state_oracle = require("mir422_complete_state").new("'+$line+'", "'+$from+'", "'+$to+'")'+"`n"
    [IO.File]::WriteAllText((Join-Path $directory 'control.lua'),$prefix+$control,[Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'tests/support/MIR422HistoricalCompleteState.lua') -Destination (Join-Path $directory 'mir422_complete_state.lua')
  }
  $fixtures[$role]=@{directory=$directory;version=$version}
}
if(-not(Test-Path -LiteralPath $LibraryDirectory)){[IO.Directory]::CreateDirectory($LibraryDirectory)|Out-Null}
$lock=[IO.File]::Open((Join-Path $LibraryDirectory '.mir-library.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
  Assert-MIRLibraryIdle
  foreach($pair in @(@($CandidateZip,$CandidateSha256),@($PublishedZip,$PublishedSha256))){
    $destination=Join-Path $LibraryDirectory ([IO.Path]::GetFileName($pair[0]))
    if(Test-Path -LiteralPath $destination){if((Get-FileHash $destination).Hash-cne$pair[1]){throw "Library archive differs: $destination"}}
    else{[IO.File]::Copy($pair[0],$destination)}
  }
  foreach($fixture in $fixtures.Values){$archive=Join-Path $LibraryDirectory ($fixtureName+'_'+$fixture.version+'.zip');if(Test-Path $archive){Assert-MIRLibraryFixtureArchive -Archive $archive -SourceDirectory $fixture.directory}else{$null=Publish-MIRModDirectoryArchive -Source $fixture.directory -Name $fixtureName -Version $fixture.version -ModsDir $LibraryDirectory}}
}finally{$lock.Dispose()}
$activation=$null;$projections=@{}
function Activate([string]$Role){
  $version=if($Role-ceq'source'){$from}else{$to};$hash=if($Role-ceq'source'){$PublishedSha256}else{$CandidateSha256};$fixture=$fixtures[$Role]
  $profile=Join-Path $root ($Role+'-selection.json')
  $selected=@(@{name='base';version=[string]$engineInfo.version;enabled=$true},@{name='more-infinite-research';version=$version;enabled=$true},@{name=$fixtureName;version=$fixture.version;enabled=$true})
  if($Target-ceq'f210'-and(-not$CandidateOnly-or$CryogenicReproducer)){
    $builtins=@('quality','elevated-rails','space-age')
    if(Test-Path (Join-Path $engineData 'recycler/info.json')){$builtins+='recycler'}
    foreach($builtin in $builtins){$selected+=@{name=$builtin;version=[string]$engineInfo.version;enabled=$true}}
  }
  @{mods=$selected}|ConvertTo-Json -Depth 6|Set-Content $profile
  $fixtureFile=$fixtureName+'_'+$fixture.version+'.zip'
  $extra=if($Target-cin@('f013','f014','f015','f016')){@{PrePinMIROwnedArchiveNames=@('more-infinite-research',$fixtureName)}}else{@{}}
  $script:activation=Start-MIRLibraryActivation -LibraryDirectory $LibraryDirectory -EngineDataDirectory $engineData -ProfilePath $profile -ArchiveHashes @{("more-infinite-research_$version.zip")=$hash;$fixtureFile=(Get-FileHash (Join-Path $LibraryDirectory $fixtureFile)).Hash} @extra
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $script:activation
}
function Run([string]$Phase,[string[]]$EngineArguments,[string]$Save=''){
  $arguments=@('--config',$config,'--no-log-rotation','--mod-directory',$LibraryDirectory)+$EngineArguments
  if($Target-cnotin@('f013','f014')){$arguments+='--disable-audio'}
  $log=Join-Path $userdata 'factorio-current.log';if(Test-Path $log){[IO.File]::WriteAllText($log,'')}
  Assert-MIRLibraryLaunch -Activation $script:activation -FactorioBin $FactorioBin -Arguments $arguments
  $completion=if($Save){ {
    if(-not(Test-Path -LiteralPath $log)-or-not(Test-Path -LiteralPath $Save)){return $false}
    try{$text=[string](Get-Content -LiteralPath $log -Raw -ErrorAction Stop)}catch [IO.IOException]{return $false}
    if(-not$text.Contains('Hosting game')-or-not($text-match '\[mir-fixture\] complete (research|Space Age) state retained')){return $false}
    if($Phase-like'reload*'){return $text.Contains('upgraded save reload proof complete')}
    $saved=$text.Contains('Saving finished')
    if(-not$saved){try{$z=[IO.Compression.ZipFile]::OpenRead($Save);try{$saved=@($z.Entries|Where-Object {$_.FullName.EndsWith('/level.dat')-and$_.Length-gt0}).Count-eq1}finally{$z.Dispose()}}catch [IO.IOException]{return $false}}
    return $saved-and$text.Contains('upgrade proof complete')
  }.GetNewClosure() }else{$null}
  $run=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $FactorioBin -Arguments $arguments -TimeoutSeconds 120 -AdmissionWaitSeconds 30 -AdmissionPhase ($Target+'-'+$Phase) -CompletionPredicate $completion
  if($Save-and-not$run.result.completion_predicate_observed){throw "Incomplete $Phase save oracle"}
  $null=Assert-MIRLibraryLoadedSelection -Activation $script:activation -LogPath $log
  $text=Get-Content -LiteralPath $log -Raw
  if($text-match '(?im)(Error Util|Error ModManager|Failed to load|stack traceback)'){throw 'Native log failure'}
  if($CryogenicReproducer-and-not$text.Contains('[mir472] cryogenic science, native owner and generated prerequisite retained')){throw 'Cryogenic behavior proof did not execute'}
  Copy-Item -LiteralPath $log -Destination (Join-Path $root ($Phase+'.log'))
  $rows=[regex]::Matches($text,'\[MIR471_PROJECTION\] ([a-z]+)=([^\r\n]+)')
  if($rows.Count-ne3){throw 'Native prototype projection did not execute'}
  $projection=($rows|ForEach-Object {$_.Groups[1].Value+'='+$_.Groups[2].Value})-join'|'
  $script:projections[$Phase]=$projection
  if($Phase-cne'source'-and-not$CandidateOnly-and$projection-cne$script:projections['source']){throw 'Default technology, recipe or lab projection changed'}
  foreach($stage in @('source','upgrade','reload')){$snapshot=Join-Path $userdata ('script-output/mir-upgrade-full-state-'+$stage+'.json');if(Test-Path $snapshot){Copy-Item $snapshot (Join-Path $root ($Phase+'-'+$stage+'-state.json'))}}
}
try{
  if($CandidateOnly){Activate 'candidate';Run 'candidate' @('--create',(Join-Path $root 'candidate.zip'))}
  else{
    if($ResumeSourceRun){
      $prior=Resolve-MIR441RecoveryScratchPath -Path $ResumeSourceRun
      if((Get-FileHash (Join-Path $prior 'fixture-source/control.lua')).Hash-cne(Get-FileHash (Join-Path $fixtures.source.directory 'control.lua')).Hash){throw 'Resume fixture differs'}
      $text=Get-Content (Join-Path $prior 'source.log') -Raw
      if(-not$text.Contains($from+' upgrade source proof complete')){throw 'Resume source proof is absent'}
      $rows=[regex]::Matches($text,'\[MIR471_PROJECTION\] ([a-z]+)=([^\r\n]+)');if($rows.Count-ne3){throw 'Resume source projection is absent'}
      $projections['source']=($rows|ForEach-Object {$_.Groups[1].Value+'='+$_.Groups[2].Value})-join'|'
      $source=Join-Path $prior 'source.zip';Copy-Item (Join-Path $prior 'source.log') (Join-Path $root 'source.log')
      foreach($snapshot in Get-ChildItem $prior -Filter 'source-*-state.json' -File){Copy-Item $snapshot.FullName (Join-Path $root $snapshot.Name)}
    }else{
      Activate 'source';$source=Join-Path $root 'source.zip';Run 'source' @('--create',$source)
      $null=Complete-MIRLibraryActivation -Activation $script:activation
    }
    Activate 'candidate'
    $saveName=if($Target-cin@('f200','f210')){'mir-'+$to.Replace('.','')+'-upgraded.zip'}else{'mir471-upgraded.zip'}
    $upgraded=Join-Path $userdata ('saves/'+$saveName)
    [string[]]$serverArgs=if($Target-ceq'f013'){@('--no-auto-pause')}else{@('--server-settings',$server)}
    Run 'upgrade' ($serverArgs+@('--start-server',$source)) $upgraded
    foreach($reload in 1..2){Run ('reload-'+$reload) ($serverArgs+@('--start-server',$upgraded)) $upgraded}
  }
  $terminal=Complete-MIRLibraryActivation -Activation $script:activation
  Write-MIRNativeProbeResult -Context $resources -Record @{status='passed';target=$Target;candidate_sha256=$CandidateSha256;published_sha256=$PublishedSha256;engine_version=$engineInfo.version;engine_sha256=$engineHash;source_commit=(&git -C $RepoRoot rev-parse HEAD).Trim();projections=$projections;ownership_control_scope='separate actual-packaged-adapter Lua host evidence';two_cold_reloads=(-not$CandidateOnly);library_restored=$terminal;runs=@($resources.runs)}
  Write-Host "[ok] $Target native parity and continuity: $root"
}finally{if($null-ne$script:activation-and-not$script:activation.closed){$null=Complete-MIRLibraryActivation -Activation $script:activation}}
