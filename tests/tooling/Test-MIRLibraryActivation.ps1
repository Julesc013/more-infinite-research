# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if(-not $RepoRoot){$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path}
. (Join-Path $RepoRoot 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/ResourceGovernor.ps1')
$root=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $RepoRoot ('build/tmp/library-activation-'+[guid]::NewGuid().ToString('N')))
[IO.Directory]::CreateDirectory($root)|Out-Null
$library=Join-Path $root 'library';$data=Join-Path $root 'engine/data';$profiles=Join-Path $root 'profiles'
foreach($path in @($library,$profiles,(Join-Path $data 'base'),(Join-Path $data 'quality'),(Join-Path $root 'engine/bin/x64'))){[IO.Directory]::CreateDirectory($path)|Out-Null}
$script:checks=0
function Assert-LibraryTest([bool]$Condition,[string]$Name){if(-not $Condition){throw "[library-test] $Name"};$script:checks++;Write-Host "[ok] $Name"}
function Assert-LibraryRefusal([scriptblock]$Action,[string]$Code){$caught='';try{& $Action|Out-Null}catch{$caught=$_.Exception.Message};Assert-LibraryTest ($caught.Contains($Code)) "refused $Code"}
function Write-TestJson($Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
function New-TestArchive([string]$Name,[string]$Version,[string[]]$Dependencies=@('base >= 2.1.0')){
  $path=Join-Path $library ($Name+'_'+$Version+'.zip')
  $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
  try{
    $entry=$zip.CreateEntry($Name+'_'+$Version+'/info.json')
    $writer=[IO.StreamWriter]::new($entry.Open())
    try{$writer.Write((@{name=$Name;version=$Version;factorio_version='2.1';dependencies=$Dependencies}|ConvertTo-Json))}finally{$writer.Dispose()}
  }finally{$zip.Dispose()}
  return $path
}
Write-TestJson (Join-Path $data 'base/info.json') @{name='base';version='2.1.20';dependencies=@()}
Write-TestJson (Join-Path $data 'quality/info.json') @{name='quality';version='2.1.20';dependencies=@('base')}
$first=New-TestArchive 'alpha' '1.0.0';$second=New-TestArchive 'alpha' '2.0.0';$extra=New-TestArchive 'unrequested' '1.0.0'
$spaceName=New-TestArchive 'Flare Stack' '4.3.1'
$dependent=New-TestArchive 'dependent' '1.0.0' @('base','alpha >= 2.0.0')
$optional=New-TestArchive 'optional' '1.0.0' @('? alpha >= 2.0.0')
$incompatible=New-TestArchive 'incompatible' '1.0.0' @('! alpha >= 99.0.0')
$hashes=@{};foreach($file in @(Get-ChildItem -LiteralPath $library -File)){$hashes[$file.Name]=Get-MIRImmutableInputSha256 $file.FullName}
$before=@{};foreach($file in @(Get-ChildItem -LiteralPath $library -File)){$before[$file.Name]=Get-MIRImmutableInputFileIdentity $file.FullName}
$profileA=Join-Path $profiles 'a.json';$profileB=Join-Path $profiles 'b.json'
Write-TestJson $profileA @{mods=@(@{name='base';version='2.1.20';enabled=$true},@{name='alpha';version='1.0.0';enabled=$true})}
Write-TestJson $profileB @{mods=@(@{name='base';version='2.1.20';enabled=$true},@{name='alpha';version='2.0.0';enabled=$true})}
$oldList=[Text.Encoding]::UTF8.GetBytes('{"mods":[{"name":"personal-selection","enabled":true}]}')
$oldSettings=[byte[]](1,4,6,8,0,255)
[IO.File]::WriteAllBytes((Join-Path $library 'mod-list.json'),$oldList)
[IO.File]::WriteAllBytes((Join-Path $library 'mod-settings.dat'),$oldSettings)
$privateSettings=Join-Path $root 'selected-settings.dat';[IO.File]::WriteAllBytes($privateSettings,[byte[]](9,8,7,6,5))
$activation=$null
try{
  foreach($case in @(@($profileA,'alpha_1.0.0.zip','Defaults'),@($profileB,'alpha_2.0.0.zip','File'),@($profileA,'alpha_1.0.0.zip','Defaults'))){
    $arguments=@{LibraryDirectory=$library;EngineDataDirectory=$data;ProfilePath=$case[0];ArchiveHashes=@{$case[1]=$hashes[$case[1]]};SettingsMode=$case[2]}
    if($case[2] -ceq 'File'){$arguments.SettingsPath=$privateSettings;$arguments.SettingsSha256=Get-MIRImmutableInputSha256 $privateSettings}
    $activation=Start-MIRLibraryActivation @arguments
    $active=Get-Content -LiteralPath (Join-Path $library 'mod-list.json') -Raw|ConvertFrom-Json
    Assert-LibraryTest (@($active.mods|Where-Object enabled).Count -eq 2) 'only requested names enabled'
    Assert-LibraryTest (@($active.mods|Where-Object {$_.name -in @('quality','unrequested','Flare Stack') -and -not $_.enabled}).Count -eq 3) 'unrequested archive, space-containing name and bundled DLC disabled'
    Assert-LibraryTest ((@($active.mods|Where-Object name -EQ 'alpha')[0].version) -ceq (@($activation.selected|Where-Object name -EQ 'alpha')[0].version)) 'exact version pinned'
    if($case[2] -ceq 'Defaults'){Assert-LibraryTest (-not(Test-Path -LiteralPath (Join-Path $library 'mod-settings.dat'))) 'defaults do not inherit prior settings'}
    else{Assert-LibraryTest ((Get-MIRImmutableInputFileIdentity (Join-Path $library 'mod-settings.dat')) -cne (Get-MIRImmutableInputFileIdentity $privateSettings)) 'settings are private writable bytes'}
    Assert-LibraryRefusal {Start-MIRLibraryActivation @arguments} 'mir-library-busy'
    Assert-LibraryRefusal {[IO.File]::Open((Join-Path $library $case[1]),[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::Read).Dispose()} 'another process'
    $log=Join-Path $root 'selection.log'
    [IO.File]::WriteAllLines($log,@('0.1 Loading mod core 0.0.0 (data.lua)')+@($activation.selected|ForEach-Object {'0.2 Loading mod '+$_.name+' '+$_.version+' (data.lua)'}))
    Assert-LibraryTest (@(Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log).Count -eq 2) 'loaded names and versions read back'
    [IO.File]::AppendAllText($log,"`n0.3 Loading mod unrequested 1.0.0 (data.lua)`n")
    Assert-LibraryRefusal {Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log} 'mir-library-loaded-selection'
    $receipt=Complete-MIRLibraryActivation $activation;$activation=$null
    Assert-LibraryTest ($receipt.archive_links_created -eq 0 -and $receipt.dependency_payload_bytes_copied -eq 0) 'no archive staging'
    Assert-LibraryTest ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $library 'mod-list.json'))) -ceq [Convert]::ToBase64String($oldList)) 'prior mod-list restored byte for byte'
    Assert-LibraryTest ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $library 'mod-settings.dat'))) -ceq [Convert]::ToBase64String($oldSettings)) 'prior settings restored byte for byte'
  }
  $bad=Join-Path $profiles 'bad.json'
  $base=@{name='base';version='2.1.20';enabled=$true}
  Write-TestJson $bad @{mods=@($base,@{name='alpha';version='9.0.0';enabled=$true})}
  Assert-LibraryRefusal {Start-MIRLibraryActivation $library $data $bad @{}} 'mir-library-version-missing'
  foreach($case in @(@('dependent',@(), 'mir-library-dependency-missing'),@('dependent',@(@{name='alpha';version='1.0.0';enabled=$true}),'mir-library-dependency-version'),@('optional',@(@{name='alpha';version='1.0.0';enabled=$true}),'mir-library-dependency-version'),@('incompatible',@(@{name='alpha';version='1.0.0';enabled=$true}),'mir-library-incompatible'))){
    Write-TestJson $bad @{mods=@($base,@{name=$case[0];version='1.0.0';enabled=$true})+@($case[1])}
    $locked=@{($case[0]+'_1.0.0.zip')=$hashes[$case[0]+'_1.0.0.zip']};if(@($case[1]).Count){$locked['alpha_1.0.0.zip']=$hashes['alpha_1.0.0.zip']}
    Assert-LibraryRefusal {Start-MIRLibraryActivation $library $data $bad $locked} $case[2]
  }
  Assert-LibraryRefusal {Start-MIRLibraryActivation $library $data $profileA @{'alpha_1.0.0.zip'=('A'*64)}} 'mir-library-hash-mismatch'
  Assert-LibraryTest (-not(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json'))) 'rejected selections leave no active transaction'
  # Real child exit: a finally block cannot restore these controls. The next
  # invocation must consume the durable backup, then start its own selection.
  $child=Join-Path $root 'abandon.ps1'
  [IO.File]::WriteAllText($child,@'
param([string]$Repository,[string]$Library,[string]$Data,[string]$Profile,[string]$Hash)
$ErrorActionPreference='Stop'
. (Join-Path $Repository 'tools/lib/compatibility/FactorioRunner.ps1')
$activation=Start-MIRLibraryActivation -LibraryDirectory $Library -EngineDataDirectory $Data -ProfilePath $Profile -ArchiveHashes @{'alpha_1.0.0.zip'=$Hash}
[Environment]::Exit(23)
'@)
  $start=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
  $start.UseShellExecute=$false;$start.CreateNoWindow=$true
  foreach($arg in @('-NoProfile','-File',$child,'-Repository',$RepoRoot,'-Library',$library,'-Data',$data,'-Profile',$profileA,'-Hash',$hashes['alpha_1.0.0.zip'])){[void]$start.ArgumentList.Add($arg)}
  $childProcess=[Diagnostics.Process]::Start($start)
  if(-not $childProcess.WaitForExit(20000)){$childProcess.Kill($true);throw 'Owned tiny activation child exceeded its deadline.'}
  Assert-LibraryTest ($childProcess.ExitCode -eq 23 -and (Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json'))) 'interrupted owner leaves a recovery journal'
  $childProcess.Dispose()
  $activation=Start-MIRLibraryActivation $library $data $profileB @{'alpha_2.0.0.zip'=$hashes['alpha_2.0.0.zip']}
  Assert-LibraryTest ($activation.journal.controls['mod-list.json'].bytes -ceq [Convert]::ToBase64String($oldList)) 'next owner restores original controls before selecting B'
  $null=Complete-MIRLibraryActivation $activation;$activation=$null
  Assert-LibraryTest ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $library 'mod-settings.dat'))) -ceq [Convert]::ToBase64String($oldSettings)) 'settings recover after owner exit'

  # Exercise the existing create/reload collector through its new launch seam.
  # Only the native actor is substituted; no Factorio result is claimed here.
  function Invoke-MIRCompatFactorioProcess {
    param($FactorioBin,$ArgumentList,$StdoutPath,$StderrPath,$TimeoutSeconds,$LibraryActivation)
    Assert-MIRLibraryLaunch -Activation $LibraryActivation -FactorioBin $FactorioBin -Arguments $ArgumentList
    Assert-LibraryTest ($ArgumentList[[Array]::IndexOf($ArgumentList,'--mod-directory')+1] -ceq $library) 'collector launches against the master library'
    [IO.File]::WriteAllText($StdoutPath,'controlled actor');[IO.File]::WriteAllText($StderrPath,'')
    $userData=Split-Path -Parent $StdoutPath
    [IO.File]::WriteAllLines((Join-Path $userData 'factorio-current.log'),@($LibraryActivation.selected|ForEach-Object {'0.1 Loading mod '+$_.name+' '+$_.version+' (data.lua)'}))
    $index=[Array]::IndexOf($ArgumentList,'--create')
    if($index -ge 0){[IO.File]::WriteAllText($ArgumentList[$index+1],'controlled save')}
    return [pscustomobject]@{exit_code=0;timed_out=$false;duration_seconds=0.01;passed=$true}
  }
  $engine=Join-Path $root 'engine/bin/x64/factorio.exe';[IO.File]::WriteAllText($engine,'test actor path only')
  $run=Join-Path $root 'run';[IO.Directory]::CreateDirectory((Join-Path $run 'saves'))|Out-Null
  $activation=Start-MIRLibraryActivation $library $data $profileA @{'alpha_1.0.0.zip'=$hashes['alpha_1.0.0.zip']}
  $load=Invoke-MIRFactorioLoadCheck -FactorioBin $engine -UserDataDir $run -ScenarioName 'direct-library' -LibraryActivation $activation
  $reload=Invoke-MIRFactorioReloadContract -FactorioBin $engine -UserDataDir $run -ScenarioName 'direct-library' -SavePath $load.save -RequiredReloadCount 1 -MaxReloadDurationSeconds 1 -LibraryActivation $activation
  Assert-LibraryTest ($load.passed -and $reload.passed -and -not(Test-Path -LiteralPath (Join-Path $run 'mods'))) 'create/reload collectors need no populated mods directory'
  $arguments=@('--config',(Join-Path $run 'mir-compat-config.ini'),'--mod-directory',$library)
  Assert-LibraryRefusal {Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments ($arguments+@('--sync-mods','unused.zip'))} 'mir-library-acquisition-or-ambiguous-argument'
  Assert-LibraryRefusal {Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments ($arguments+@('--mod-directory','elsewhere'))} 'mir-library-launch-path-argument'
  $savedGuard=(Get-Command Assert-MIRLibraryIdle).ScriptBlock
  function Assert-MIRLibraryIdle {throw '[mir-library-factorio-active] controlled live client'}
  Assert-LibraryRefusal {Complete-MIRLibraryActivation $activation} 'mir-library-factorio-active'
  Assert-LibraryTest ($activation.lock.CanRead -and -not $activation.closed) 'live engine retains lock and read handles'
  Set-Item -Path Function:Assert-MIRLibraryIdle -Value $savedGuard
  $null=Complete-MIRLibraryActivation $activation;$activation=$null
  foreach($file in @(Get-ChildItem -LiteralPath $library -Filter '*.zip')){
    Assert-LibraryTest ((Get-MIRImmutableInputFileIdentity $file.FullName) -ceq $before[$file.Name] -and (Get-MIRImmutableInputSha256 $file.FullName) -ceq $hashes[$file.Name]) ('archive unchanged '+$file.Name)
  }
  Assert-LibraryTest (@(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.zip'|Where-Object FullName -CNE $load.save).Count -eq $before.Count) 'only original mod archives and the owned output save exist'
  Assert-LibraryTest (@(Get-ChildItem -LiteralPath $profiles -Recurse -File|Where-Object Extension -EQ '.zip').Count -eq 0) 'definition-only profiles'
  [ordered]@{status='passed';checks=$script:checks;root=$root;native_engine_runs=0}|ConvertTo-Json
}finally{if($null -ne $activation -and -not $activation.closed){$null=Complete-MIRLibraryActivation $activation}}
