# MIR4-CANONICAL-EXECUTABLE-TEST
# Bounded consumer of the existing direct-library, resource and full-state fixture harness.
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [Parameter(Mandatory)][string]$CandidateZip,
  [Parameter(Mandatory)][string]$SourceMaterializationPath,
  [Parameter(Mandatory)][string]$PublishedZip,
  [Parameter(Mandatory)][string]$LibraryDirectory,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$OutputRoot='build/tmp/mir471-native',
  [string]$ResumeSourceRun='',
  [string]$ResumeUpgradeRun='',
  [ValidateSet('All','Base','Continuity','Representative')][string]$Selection='All'
)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $RepoRoot 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $RepoRoot 'tests/support/MIR421SpaceFakeUpgrade.ps1')
if((Get-Item -LiteralPath $FactorioBin).VersionInfo.ProductVersion -notmatch '^2[.]1[.]23(?:[.]|$)'){throw 'Pinned Factorio 2.1.23 is required'}
if((& git -C $RepoRoot rev-parse 'v4.7.0^{commit}').Trim() -cne '84bd157ad7b63b7d171fac2311bf30de70429c11'){throw 'Published source tag differs'}
$publishedHash='708A529F1F6D649E0A732216CD8D8FEFE68F2C6C2DF2B40DA030C2C4C51558D1'
if((Get-FileHash -LiteralPath $PublishedZip).Hash -cne $publishedHash){throw 'Published F210 archive differs'}
$candidate=Read-MIRNativeProbeCurrentCandidate -Repository $RepoRoot -Archive $CandidateZip -ReceiptPath $SourceMaterializationPath -Target f210 -SourceVersion 4.7.1
$resources=New-MIRNativeProbeResourceContext -RepoRoot $RepoRoot -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB 1400 -MaxNewOutputMiB 120
$root=$resources.root
[IO.Directory]::CreateDirectory($root)|Out-Null
$engineData=Join-Path (Split-Path (Split-Path (Split-Path $FactorioBin))) 'data'
$userdata=Join-Path $root 'u'
[IO.Directory]::CreateDirectory((Join-Path $userdata 'saves'))|Out-Null
$config=Join-Path $root 'config.ini'
[IO.File]::WriteAllText($config,"[path]`nread-data=$($engineData.Replace('\','/'))`nwrite-data=$($userdata.Replace('\','/'))`n[other]`ncheck-updates=false`nenable-new-mods=false`n",[Text.UTF8Encoding]::new($false))
$server=Join-Path $root 'server.json'
@{name='MIR471 focused qualification';description='Private ephemeral upgrade validation server';visibility=@{public=$false;lan=$false};require_user_verification=$false;auto_pause=$false}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $server
$activation=$null
$results=[Collections.Generic.List[object]]::new()
function Install-OwnedInput([string]$Path,[string]$Hash){
  $destination=Join-Path $LibraryDirectory ([IO.Path]::GetFileName($Path))
  if(Test-Path -LiteralPath $destination){if((Get-FileHash -LiteralPath $destination).Hash-cne$Hash){throw "Conflicting library identity: $destination"};return}
  [IO.File]::Copy($Path,$destination)
  if((Get-FileHash -LiteralPath $destination).Hash-cne$Hash){throw 'Installed archive hash differs'}
}
function Activate([string]$Version,[bool]$SpaceAge,[string]$Fixture=''){
  $inventory=@(Get-MIRLibraryInventory -LibraryDirectory $LibraryDirectory -EngineDataDirectory $engineData)
  $names=@('base');if($SpaceAge){$names+=@('quality','elevated-rails','space-age');if(@($inventory|Where-Object {$_.builtin-and$_.name-ceq'recycler'}).Count){$names+='recycler'}}
  $mods=@(foreach($name in $names){$row=@($inventory|Where-Object {$_.builtin-and$_.name-ceq$name});if($row.Count-ne1){throw "Missing builtin $name"};@{name=$name;version=$row[0].version;enabled=$true}})
  $mods+=@{name='more-infinite-research';version=$Version;enabled=$true}
  $hashes=@{("more-infinite-research_$Version.zip")=$(if($Version-ceq'4.7.21000'){$publishedHash}else{$candidate.receipt.archive_sha256})}
  if($Fixture){$info=Get-Content (Join-Path $Fixture 'info.json') -Raw|ConvertFrom-Json;$mods+=@{name=$info.name;version=$info.version;enabled=$true};$filename=$info.name+'_'+$info.version+'.zip';$hashes[$filename]=(Get-FileHash (Join-Path $LibraryDirectory $filename)).Hash}
  $profile=Join-Path $root ('selection-'+[guid]::NewGuid().ToString('N')+'.json')
  @{mods=$mods}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $profile
  $script:activation=Start-MIRLibraryActivation -LibraryDirectory $LibraryDirectory -EngineDataDirectory $engineData -ProfilePath $profile -ArchiveHashes $hashes
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $script:activation
}
function Run([string[]]$EngineArguments,[string]$Marker='',[string]$Save=''){
  $arguments=@('--config',$config,'--no-log-rotation','--disable-audio','--mod-directory',$LibraryDirectory)+$EngineArguments
  Assert-MIRLibraryLaunch -Activation $script:activation -FactorioBin $FactorioBin -Arguments $arguments
  $log=Join-Path $userdata 'factorio-current.log'
  # Save/reload completion remains the existing fixture's native full-state oracle.
  $predicate=if($Marker){ {
    if(-not(Test-Path -LiteralPath $log)-or-not(Test-Path -LiteralPath $Save)){return $false}
    try{$all=[string](Get-Content -LiteralPath $log -Raw -ErrorAction Stop)}catch [IO.IOException]{return $false}
    $starts=[regex]::Matches($all,'(?m)^[ \t]*[0-9]+\.[0-9]+ [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}; Factorio ')
    if($starts.Count-eq0){return $false}
    $text=$all.Substring($starts[$starts.Count-1].Index)
    return $text.Contains($Marker)-and$text.Contains('Hosting game')-and
      ($text-match '\[mir-fixture\] complete (?:Space Age|research) state retained technologies=')-and
      ($text.Contains('Saving finished')-or$Marker.Contains('reload proof'))
  }.GetNewClosure() }else{$null}
  $run=Invoke-MIRNativeProbeProcess -Context $resources -FilePath $FactorioBin -Arguments $arguments -TimeoutSeconds 120 -FactorioSteamIdentity -CompletionPredicate $predicate
  if($Marker-and-not$run.result.completion_predicate_observed){throw "Missing native save/reload marker $Marker"}
  $null=Assert-MIRLibraryLoadedSelection -Activation $script:activation -LogPath $log -LatestInvocation
  $latest=Get-MIRLibraryLatestInvocationText -Text (Get-Content -LiteralPath $log -Raw)
  if($latest-match 'Error while|Error ModManager|stack traceback'){throw 'Native log reports a failure'}
  return $latest
}
try{
  # The shared flat-library lock spans every worktree. Preparation installs only
  # new MIR-owned inputs; dependency archives and existing controls stay intact.
  $prep=[IO.File]::Open((Join-Path $LibraryDirectory '.mir-library.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try{
    Assert-MIRLibraryIdle
    Install-OwnedInput $CandidateZip $candidate.receipt.archive_sha256
    Install-OwnedInput $PublishedZip $publishedHash
    $fixture=Join-Path $root 'upgrade-fixture'
    [IO.Directory]::CreateDirectory($fixture)|Out-Null
    foreach($file in Get-ChildItem (Join-Path $RepoRoot 'fixtures/assert-upgrade-4-0-21000-to-4-1-21000') -File){[IO.File]::Copy($file.FullName,(Join-Path $fixture $file.Name),$false)}
    $control=Get-Content (Join-Path $fixture 'control.lua') -Raw
    $control=$control.Replace('"4.0.21000"','"4.7.21000"').Replace('"4.1.21000"','"4.7.21001"').Replace('mir-4121000-upgraded','mir-4721001-upgraded')
    $control=$control.Replace('  and (from_version:match("^4%.1%.21000$") or from_version:match("^4%.2%.210%d%d$"))','  and from_version == "4.7.21000"').Replace('  and to_version:match("^4%.2%.210%d%d$")','  and to_version == "4.7.21001"')
    [IO.File]::WriteAllText((Join-Path $fixture 'control.lua'),$control,[Text.UTF8Encoding]::new($false))
    $info=Get-Content (Join-Path $fixture 'info.json') -Raw|ConvertFrom-Json
    $info.version='0.1.1471';$info.dependencies=@('base >= 2.1.23','space-age >= 2.1.23','more-infinite-research >= 4.7.21000')
    $info|ConvertTo-Json -Depth 5|Set-Content (Join-Path $fixture 'info.json')
    $null=Publish-MIRModDirectoryArchive -Source $fixture -Name $info.name -Version $info.version -ModsDir $LibraryDirectory
    $representative=Join-Path $RepoRoot 'fixtures/assert-startup-hotfix-f210-471'
    $repInfo=Get-Content (Join-Path $representative 'info.json') -Raw|ConvertFrom-Json
    $null=Publish-MIRModDirectoryArchive -Source $representative -Name $repInfo.name -Version $repInfo.version -ModsDir $LibraryDirectory
  }finally{$prep.Dispose()}
  if($Selection-in@('All','Base')){
    Activate '4.7.21001' $false
    $save=Join-Path $root 'base.zip';$text=Run @('--create',$save)
    if(-not(Test-Path $save)){throw 'Base save was not created'}
    $results.Add(@{scenario='final-package-base';status='passed'})
    $null=Complete-MIRLibraryActivation $script:activation
  }
  if($Selection-in@('All','Continuity')){
    if($ResumeSourceRun){
      $prior=Resolve-MIR441RecoveryScratchPath -Path $ResumeSourceRun
      $priorState=[Text.Json.JsonDocument]::Parse([IO.File]::ReadAllText((Join-Path $prior 'source-state.json')))
      try{
        $state=$priorState.RootElement;$active=$state.GetProperty('active_mods')
        if($state.GetProperty('from_version').GetString()-cne'4.7.21000'-or$state.GetProperty('to_version').GetString()-cne'4.7.21001'-or$state.GetProperty('stage').GetString()-cne'source'-or
          $active.GetProperty('base').GetString()-cne'2.1.23'-or$active.GetProperty('more-infinite-research').GetString()-cne'4.7.21000'){throw 'Resume source identity differs'}
      }finally{$priorState.Dispose();$priorState=$null;$state=$null;$active=$null}
      if((Get-FileHash (Join-Path $prior 'upgrade-fixture/control.lua')).Hash-cne(Get-FileHash (Join-Path $fixture 'control.lua')).Hash){throw 'Resume fixture bytes differ'}
      $save=Join-Path $prior 'source.zip'
      Copy-Item (Join-Path $prior 'source-state.json') (Join-Path $root 'source-state.json')
    }else{
      Activate '4.7.21000' $true $fixture
      $save=Join-Path $root 'source.zip';$text=Run @('--create',$save)
      if(-not$text.Contains('4.7.21000 upgrade source proof complete')){throw 'Source fixture did not seed research'}
      Copy-Item (Join-Path $userdata 'script-output/mir-upgrade-full-state-source.json') (Join-Path $root 'source-state.json')
      $null=Complete-MIRLibraryActivation $script:activation
    }
    Activate '4.7.21001' $true $fixture
    if($ResumeUpgradeRun){
      $priorUpgrade=Resolve-MIR441RecoveryScratchPath -Path $ResumeUpgradeRun
      $priorLog=Get-MIRLibraryLatestInvocationText -Text (Get-Content (Join-Path $priorUpgrade 'u/factorio-current.log') -Raw)
      if(-not$priorLog.Contains('4.7.21000 to 4.7.21001 upgrade proof complete')-or-not$priorLog.Contains('Saving finished')){throw 'Interrupted upgrade did not finish its save'}
      Assert-MIR42CompleteCatalogueUpgradeMarker -Text $priorLog
      $upgraded=Join-Path $priorUpgrade 'u/saves/mir-4721001-upgraded.zip'
      Copy-Item (Join-Path $priorUpgrade 'u/script-output/mir-upgrade-full-state-upgrade.json') (Join-Path $root 'upgrade-state.json')
    }else{
      $upgraded=Join-Path $userdata 'saves/mir-4721001-upgraded.zip'
      $text=Run @('--server-settings',$server,'--start-server',$save) '4.7.21000 to 4.7.21001 upgrade proof complete' $upgraded
      Assert-MIR42CompleteCatalogueUpgradeMarker -Text $text
      Copy-Item (Join-Path $userdata 'script-output/mir-upgrade-full-state-upgrade.json') (Join-Path $root 'upgrade-state.json')
    }
    foreach($reload in 1..2){
      $text=Run @('--server-settings',$server,'--start-server',$upgraded) '4.7.21001 upgraded save reload proof complete' $upgraded
      Assert-MIR42CompleteCatalogueUpgradeMarker -Text $text
      Copy-Item (Join-Path $userdata 'script-output/mir-upgrade-full-state-reload.json') (Join-Path $root "reload-$reload-state.json")
    }
    $results.Add(@{scenario='published-470-to-471-space-age-full-state-two-reloads';status='passed';source_save_sha256=(Get-FileHash $save).Hash;upgraded_save_sha256=(Get-FileHash $upgraded).Hash})
    $null=Complete-MIRLibraryActivation $script:activation
  }
  if($Selection-in@('All','Representative')){
    Activate '4.7.21001' $false $representative
    $save=Join-Path $root 'representative.zip';$text=Run @('--create',$save)
    if(-not$text.Contains('[mir471] representative startup research, science, effects and foreign ownership retained')){throw 'Representative behavior assertion did not run'}
    $results.Add(@{scenario='representative-unrelated-owner-and-replacement-science';status='passed'})
    $null=Complete-MIRLibraryActivation $script:activation
  }
  Write-MIRNativeProbeResult -Context $resources -Record @{status='passed';source_commit=(&git -C $RepoRoot rev-parse HEAD).Trim();engine_sha256=(Get-FileHash $FactorioBin).Hash;candidate_sha256=$candidate.receipt.archive_sha256;scenarios=@($results);runs=@($resources.runs)}
  Write-Host "[ok] Focused MIR 4.7.1 native evidence: $root"
}finally{if($null-ne$script:activation-and-not$script:activation.closed){$null=Complete-MIRLibraryActivation $script:activation}}
