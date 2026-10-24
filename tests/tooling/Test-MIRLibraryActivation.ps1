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
function New-TestArchive([string]$Library,[string]$Name,[string]$Version){
  $path=Join-Path $Library ($Name+'_'+$Version+'.zip')
  $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
  try{$entry=$zip.CreateEntry($Name+'_'+$Version+'/info.json');$writer=[IO.StreamWriter]::new($entry.Open());try{$writer.Write((@{name=$Name;version=$Version;factorio_version='2.1';dependencies=@('base')}|ConvertTo-Json -Compress))}finally{$writer.Dispose()}}finally{$zip.Dispose()}
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
  } finally {if($null-ne$activation-and-not$activation.closed){$completion=Complete-MIRLibraryActivation -Activation $activation}}
  Assert-Library ($completion.status-ceq'restored-direct-library-controls'-and-not(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json'))) 'completion'
  Assert-Library ((Get-Content -Raw -LiteralPath (Join-Path $library 'mod-list.json'))-ceq$originalList-and([IO.File]::ReadAllBytes((Join-Path $library 'mod-settings.dat'))-join',')-ceq($originalSettings-join',')) 'restoration'
  [pscustomobject]@{status='passed';checks=$checks;native_execution=$false;package_materialization=$false}|ConvertTo-Json -Compress
} finally {
  if(Test-Path -LiteralPath $root){Remove-MIR441ContainedTree -AdmittedRoot (Join-Path $repo 'build/tmp') -Path $root}
}
