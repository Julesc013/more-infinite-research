# Current MIR5 direct-library helper controls. No engine is launched or timed.
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')
$root=Join-Path $repo ('build/tmp/mir5-direct-library-controls-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Assert-Direct([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir5-direct-library-$Code]"};$script:checks++}
function Refuses-Direct([scriptblock]$Action,[string]$Expected){$actual='';try{&$Action|Out-Null}catch{$actual=$_.Exception.Message};Assert-Direct ($actual.Contains($Expected)) "refusal-$Expected"}
function New-TestArchive([string]$Library){
  $path=Join-Path $Library 'controlled_1.0.0.zip';$zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
  try{$entry=$zip.CreateEntry('controlled_1.0.0/info.json');$writer=[IO.StreamWriter]::new($entry.Open());try{$writer.Write((@{name='controlled';version='1.0.0';factorio_version='2.1';dependencies=@('base')}|ConvertTo-Json -Compress))}finally{$writer.Dispose()}}finally{$zip.Dispose()}
  return $path
}
try {
  $library=Join-Path $root 'library';$data=Join-Path $root 'engine/data';$profile=Join-Path $root 'profile.json';$factorio=Join-Path $root 'engine/bin/x64/factorio.exe'
  foreach($path in @($library,(Join-Path $data 'base'),(Split-Path -Parent $factorio))){[IO.Directory]::CreateDirectory($path)|Out-Null}
  [IO.File]::WriteAllText((Join-Path $data 'base/info.json'),(@{name='base';version='2.1.23';dependencies=@()}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText($factorio,'controlled',[Text.UTF8Encoding]::new($false))
  $archive=New-TestArchive $library
  [IO.File]::WriteAllText($profile,(@{mods=@(@{name='base';version='2.1.23';enabled=$true},@{name='controlled';version='1.0.0';enabled=$true},@{name='more-infinite-research';version='5.0.0';enabled=$true})}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $base=@(Read-MIRDirectLibraryStartupProfile -Path $profile)
  Assert-Direct ($base.Count-eq2-and@($base|Where-Object {$_.name -ceq'more-infinite-research'}).Count-eq0) 'profile-filter'
  $selection=Join-Path $root 'selection.json';Write-MIRDirectLibraryStartupProfile -Path $selection -BaseRows $base -MirArchive ([pscustomobject]@{version='5.0.0'})
  $selected=(Get-Content -Raw -LiteralPath $selection|ConvertFrom-Json).mods
  Assert-Direct (@($selected|Where-Object {$_.name-ceq'more-infinite-research'-and$_.version-ceq'5.0.0'-and$_.enabled}).Count-eq1) 'profile-write'
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $base -MirArchive $null
  Assert-Direct ($hashes.Count-eq1-and$hashes.ContainsKey('controlled_1.0.0.zip')-and$hashes['controlled_1.0.0.zip']-ceq(Get-MIRImmutableInputSha256 $archive)) 'archive-hash'
  $config=Join-Path $root 'fresh.ini';$write=Join-Path $root 'write';New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $data -WriteDataDirectory $write
  Assert-Direct ((Get-Content -Raw -LiteralPath $config)-match'(?m)^enable-new-mods=false$') 'fresh-config'
  $engine=Get-MIRDirectLibraryStartupEngineIdentity -FactorioBin $factorio -EngineDataDirectory $data
  Assert-Direct ($engine.base_version-ceq'2.1.23'-and$engine.sha256-ceq(Get-MIRImmutableInputSha256 $factorio)) 'engine-identity'
  $ordinary=Join-Path $root 'ordinary.ini';[IO.File]::WriteAllText($ordinary,"[path]`nread-data=old`nwrite-data=old`n`n[other]`nenable-new-mods=true`ncustom-setting=keep`n",[Text.UTF8Encoding]::new($false))
  $ordinaryInput=Get-MIRDirectLibraryOrdinaryPlayerConfigInput -Path $ordinary
  $private=New-MIRDirectLibraryOrdinaryPlayerConfig -PlayerConfigInput $ordinaryInput -Path (Join-Path $root 'private.ini') -EngineDataDirectory $data -WriteDataDirectory $write
  $privateText=Get-Content -Raw -LiteralPath $private.private_config.path
  Assert-Direct ($privateText-match'custom-setting=keep'-and$privateText-match'(?m)^enable-new-mods=false$'-and$private.overrides.read_data-ceq$data) 'ordinary-config'
  $duplicate=Join-Path $root 'duplicate.ini';[IO.File]::WriteAllText($duplicate,"[path]`nread-data=a`nread-data=b`nwrite-data=c`n[other]`n",[Text.UTF8Encoding]::new($false))
  Refuses-Direct {New-MIRDirectLibraryOrdinaryPlayerConfig -PlayerConfigInput (Get-MIRDirectLibraryOrdinaryPlayerConfigInput $duplicate) -Path (Join-Path $root 'bad.ini') -EngineDataDirectory $data -WriteDataDirectory $write} '[mir-direct-startup-ordinary-player-config-keys]'
  $player=Join-Path $root 'player-data.json';[IO.File]::WriteAllText($player,(@{'last-played-version'=@{game_version='2.1.23'};'service-username'='';'service-token'=''}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
  $playerInput=Get-MIRDirectLibraryOrdinaryMenuPlayerDataInput -Path $player -ExpectedEngineVersion '2.1.23'
  Refuses-Direct {Get-MIRDirectLibraryOrdinaryMenuPlayerDataInput -Path $player -ExpectedEngineVersion '2.1.22'} '[mir-direct-startup-ordinary-menu-player-data-engine-version]'
  $preparation=Initialize-MIRDirectLibraryOrdinaryMenuSharedWriteData -WriteDataRoot (Join-Path $root 'shared') -PlayerData $playerInput
  Assert-Direct ($preparation.primary_measurement-eq$false-and(Test-Path -LiteralPath $preparation.destination.path)) 'player-data-copy'
  $actor=Get-MIRDirectLibraryResponsiveMenuActor -RepoRoot $repo
  Assert-Direct ((Test-Path -LiteralPath $actor.path)-and$actor.sha256-match'^[0-9A-F]{64}$'-and$actor.observation_sha256-match'^[0-9A-F]{64}$') 'responsive-actor'
  Assert-Direct (-not(Test-Path -LiteralPath (Join-Path $root 'shared-again'))) 'preparation-boundary'
  [pscustomobject]@{status='passed';checks=$checks;native_execution=$false;timing_execution=$false;package_materialization=$false}|ConvertTo-Json -Compress
} finally {
  if(Test-Path -LiteralPath $root){Remove-MIR441ContainedTree -AdmittedRoot (Join-Path $repo 'build/tmp') -Path $root}
}
