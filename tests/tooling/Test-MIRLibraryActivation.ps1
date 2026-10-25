# Current MIR5 direct-library transaction controls. No Factorio process runs.
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')
$root=Join-Path $repo ('build/tmp/mir5-library-activation-controls-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Assert-Library([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir5-library-$Code]"};$script:checks++}
function Refuses-Library([scriptblock]$Action,[string]$Expected){$actual='';try{&$Action|Out-Null}catch{$actual=$_.Exception.Message};Assert-Library ($actual.Contains($Expected)) "refusal-$Expected"}
function New-TestArchive([string]$Library,[string]$Name,[string]$Version,[string]$FactorioVersion='2.1'){
  $path=Join-Path $Library ($Name+'_'+$Version+'.zip')
  $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
  try{$entry=$zip.CreateEntry($Name+'_'+$Version+'/info.json');$writer=[IO.StreamWriter]::new($entry.Open());try{$writer.Write((@{name=$Name;version=$Version;factorio_version=$FactorioVersion;dependencies=@('base')}|ConvertTo-Json -Compress))}finally{$writer.Dispose()}}finally{$zip.Dispose()}
  return $path
}
try {
  Assert-Library (-not[bool](Get-Command New-MIRCompatUserDataDir -ErrorAction SilentlyContinue)) 'no-compatibility-runner'
  $library=Join-Path $root 'library';$data=Join-Path $root 'engine/data';$profile=Join-Path $root 'profile.json'
  foreach($path in @($library,(Join-Path $data 'base'),(Join-Path $root 'engine/bin/x64'))){[IO.Directory]::CreateDirectory($path)|Out-Null}
  [IO.File]::WriteAllText((Join-Path $data 'base/info.json'),(@{name='base';version='2.1.23';dependencies=@()}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
  $archive=New-TestArchive -Library $library -Name 'controlled' -Version '1.0.0'
  $originalList='{"mods":[{"name":"base","enabled":true}]}'
  $originalSettings=[byte[]](1,2,3,4)
  [IO.File]::WriteAllText((Join-Path $library 'mod-list.json'),$originalList,[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllBytes((Join-Path $library 'mod-settings.dat'),$originalSettings)
  [IO.File]::WriteAllText($profile,(@{mods=@(@{name='base';version='2.1.23';enabled=$true},@{name='controlled';version='1.0.0';enabled=$true})}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $hashes=@{([IO.Path]::GetFileName($archive))=(Get-MIRImmutableInputSha256 $archive)}
  Refuses-Library {Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $data -ProfilePath $profile -ArchiveHashes @{([IO.Path]::GetFileName($archive))=('0'*64)}} '[mir-library-hash-mismatch]'
  Assert-Library ((Get-Content -Raw -LiteralPath (Join-Path $library 'mod-list.json'))-ceq$originalList) 'failed-activation-restores-list'
  $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $data -ProfilePath $profile -ArchiveHashes $hashes
  try {
    Assert-Library ($activation.selected.Count-eq2-and-not$activation.closed-and(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json'))) 'selection-journal'
    Refuses-Library {Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $data -ProfilePath $profile -ArchiveHashes $hashes} '[mir-library-busy]'
    $active=(Get-Content -Raw -LiteralPath (Join-Path $library 'mod-list.json')|ConvertFrom-Json)
    Assert-Library (@($active.mods|Where-Object {$_.name-ceq'controlled'-and$_.enabled}).Count-eq1-and-not(Test-Path -LiteralPath (Join-Path $library 'mod-settings.dat'))) 'selection-controls'
    $log=Join-Path $root 'factorio.log';[IO.File]::WriteAllText($log,"0.1 Loading mod base 2.1.23 (data.lua)`n0.1 Loading mod controlled 1.0.0 (data.lua)`n",[Text.UTF8Encoding]::new($false))
    Assert-Library (((Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log)-join'|') -ceq 'base@2.1.23|controlled@1.0.0') 'loaded-selection'
    $config=Join-Path $root 'config.ini';$write=Join-Path $root 'write';[IO.Directory]::CreateDirectory($write)|Out-Null
    New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $data -WriteDataDirectory $write
    $factorio=Join-Path $root 'engine/bin/x64/factorio.exe';[IO.File]::WriteAllText($factorio,'controlled binary',[Text.UTF8Encoding]::new($false))
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $factorio -Arguments @('--config',$config,'--mod-directory',$library)
    Refuses-Library {Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $factorio -Arguments @('--config',$config,'--mod-directory',$library,'--sync-mods')} '[mir-library-acquisition-or-ambiguous-argument]'
    # Exercise the actual launch guard, not a replacement idle implementation.
    # A transient enumeration may clear; a persistent client must still refuse
    # before the shared controls are rewritten. No engine process is created.
    $priorGetProcess=Get-Item Function:Get-Process -ErrorAction SilentlyContinue
    $script:libraryProcessPolls=0
    $script:libraryProcessPersistent=$false
    $controlPath=Join-Path $library 'mod-list.json'
    $script:libraryControlBefore=(Get-Item -LiteralPath $controlPath).LastWriteTimeUtc.Ticks
    function Get-Process {
      param([string]$Name,$ErrorAction)
      if($Name -cne 'factorio'){throw '[mir5-library-unexpected-process-query]'}
      $script:libraryProcessPolls++
      if((Get-Item -LiteralPath $controlPath).LastWriteTimeUtc.Ticks -ne $script:libraryControlBefore){throw '[mir5-library-controls-written-before-idle]'}
      if($script:libraryProcessPersistent -or $script:libraryProcessPolls -eq 1){[pscustomobject]@{ProcessName='factorio'}}
    }
    try {
      Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $factorio -Arguments @('--config',$config,'--mod-directory',$library)
      Assert-Library ($script:libraryProcessPolls -ge 2) 'launch-waits-for-transient-process'
      $script:libraryProcessPolls=0
      $script:libraryProcessPersistent=$true
      $script:libraryControlBefore=(Get-Item -LiteralPath $controlPath).LastWriteTimeUtc.Ticks
      Refuses-Library {Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $factorio -Arguments @('--config',$config,'--mod-directory',$library)} '[mir-library-factorio-active]'
      Assert-Library ($script:libraryProcessPolls -ge 2) 'persistent-process-remains-refused'
      Assert-Library ((Get-Item -LiteralPath $controlPath).LastWriteTimeUtc.Ticks -eq $script:libraryControlBefore) 'busy-launch-preserves-controls'
    } finally {
      Remove-Item Function:Get-Process
      if($null -ne $priorGetProcess){Set-Item Function:Get-Process $priorGetProcess.ScriptBlock}
    }
  } finally {if($null-ne$activation-and-not$activation.closed){$completion=Complete-MIRLibraryActivation -Activation $activation}}
  Assert-Library ($completion.status-ceq'restored-direct-library-controls'-and-not(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json'))) 'completion'
  Assert-Library ((Get-Content -Raw -LiteralPath (Join-Path $library 'mod-list.json'))-ceq$originalList-and([IO.File]::ReadAllBytes((Join-Path $library 'mod-settings.dat'))-join',')-ceq($originalSettings-join',')) 'restoration'
  # Exercise the existing legacy owned-name transaction with disposable
  # authored ZIPs only. No real engine or external mod library is accessed.
  $legacy=Join-Path $root 'legacy-library';$legacyData=Join-Path $root 'legacy-engine/data'
  foreach($path in @($legacy,(Join-Path $legacyData 'base'))){[IO.Directory]::CreateDirectory($path)|Out-Null}
  [IO.File]::WriteAllText((Join-Path $legacyData 'base/info.json'),'{"name":"base","version":"0.13.20","dependencies":[]}',[Text.UTF8Encoding]::new($false))
  $chosen=New-TestArchive $legacy 'more-infinite-research' '5.0.01300' '0.13'
  $alternate=New-TestArchive $legacy 'more-infinite-research' '4.7.01303' '0.13'
  $dependency=New-TestArchive $legacy 'controlled' '1.0.0' '0.13'
  $otherDependency=New-TestArchive $legacy 'controlled' '2.0.0' '0.13'
  $originals=@{}
  foreach($path in @($chosen,$alternate,$dependency,$otherDependency)){
    $originals[$path]=@{sha256=Get-MIRImmutableInputSha256 $path;identity=Get-MIRImmutableInputFileIdentity $path}
  }
  [IO.File]::WriteAllText((Join-Path $legacy 'mod-list.json'),$originalList,[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllBytes((Join-Path $legacy 'mod-settings.dat'),$originalSettings)
  $legacyProfile=Join-Path $root 'legacy-profile.json'
  [IO.File]::WriteAllText($legacyProfile,(@{mods=@(@{name='base';version='0.13.20';enabled=$true},@{name='more-infinite-research';version='5.0.01300';enabled=$true},@{name='controlled';version='1.0.0';enabled=$true})}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $legacyHashes=@{([IO.Path]::GetFileName($chosen))=$originals[$chosen].sha256;([IO.Path]::GetFileName($dependency))=$originals[$dependency].sha256}
  Refuses-Library {Start-MIRLibraryActivation -LibraryDirectory $legacy -EngineDataDirectory $legacyData -ProfilePath $legacyProfile -ArchiveHashes $legacyHashes -PrePinMIROwnedArchiveNames @('controlled')} '[mir-library-owned-version-dependency-forbidden]'
  $activation=Start-MIRLibraryActivation -LibraryDirectory $legacy -EngineDataDirectory $legacyData -ProfilePath $legacyProfile -ArchiveHashes $legacyHashes -PrePinMIROwnedArchiveNames @('more-infinite-research')
  try{
    $hidden=@(Get-ChildItem -LiteralPath $legacy -Filter '*.mir-hidden-*')
    Assert-Library ($hidden.Count-eq1-and-not(Test-Path -LiteralPath $alternate)) 'only-alternate-owned-version-hidden'
    Assert-Library ((Get-MIRImmutableInputSha256 $hidden[0].FullName)-ceq$originals[$alternate].sha256-and(Get-MIRImmutableInputFileIdentity $hidden[0].FullName)-ceq$originals[$alternate].identity) 'hidden-identity-and-bytes'
    foreach($path in @($chosen,$dependency,$otherDependency)){
      Assert-Library ((Get-MIRImmutableInputSha256 $path)-ceq$originals[$path].sha256-and(Get-MIRImmutableInputFileIdentity $path)-ceq$originals[$path].identity) 'selected-and-dependency-archives-untouched'
    }
  }finally{if($null-ne$activation-and-not$activation.closed){$completion=Complete-MIRLibraryActivation -Activation $activation}}
  foreach($path in $originals.Keys){
    Assert-Library ((Get-MIRImmutableInputSha256 $path)-ceq$originals[$path].sha256-and(Get-MIRImmutableInputFileIdentity $path)-ceq$originals[$path].identity) 'legacy-original-identity-and-bytes-restored'
  }
  Assert-Library ($completion.owned_archive_names_temporarily_hidden-eq1-and@(Get-ChildItem -LiteralPath $legacy -Filter '*.mir-hidden-*').Count-eq0-and-not(Test-Path -LiteralPath (Join-Path $legacy '.mir-active-profile.json'))) 'legacy-owned-selection-restored'
  Assert-Library ((Get-Content -Raw -LiteralPath (Join-Path $legacy 'mod-list.json'))-ceq$originalList-and([IO.File]::ReadAllBytes((Join-Path $legacy 'mod-settings.dat'))-join',')-ceq($originalSettings-join',')) 'legacy-controls-restored'
  [pscustomobject]@{status='passed';checks=$checks;native_execution=$false;package_materialization=$false}|ConvertTo-Json -Compress
} finally {
  if(Test-Path -LiteralPath $root){Remove-MIR441ContainedTree -AdmittedRoot (Join-Path $repo 'build/tmp') -Path $root}
}
