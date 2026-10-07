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
foreach($name in @('elevated-rails','recycler','space-age')){[IO.Directory]::CreateDirectory((Join-Path $data $name))|Out-Null;Write-TestJson (Join-Path $data ($name+'/info.json')) @{name=$name;version='2.1.20';dependencies=@('base')}}
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
    Assert-LibraryTest (@($receipt.selected|Where-Object {-not $_.builtin -and $_.sha256 -ceq $hashes[$case[1]]}).Count -eq 1) 'receipt binds the selected archive bytes'
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
  # Invoke the actual K2 consumer's input boundary without running its engine
  # campaign. Only pure function declarations are imported from the harness.
  $tokens=$null;$errors=$null
  $harness=Join-Path $RepoRoot 'tests/runtime/Test-MIRK2213ImersiteContinuation.ps1'
  $ast=[Management.Automation.Language.Parser]::ParseFile($harness,[ref]$tokens,[ref]$errors)
  Assert-LibraryTest ($errors.Count -eq 0) 'K2 direct-library consumer parses'
  foreach($name in @('Fail-K2213','Assert-K2213','Get-K2213Sha256','Get-K2213ZipInfo','Assert-K2213ArchiveIdentity','Read-K2213DirectLibraryInputs')){
    $nodes=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$false))
    if($nodes.Count -ne 1){throw "K2 input function is absent or duplicated: $name"}
    . ([scriptblock]::Create($nodes[0].Extent.Text))
  }
  . (Join-Path $RepoRoot 'tools/lib/validation/FactorioProcess.ps1')
  $fixtureRoot=Join-Path $root 'fixture-source';[IO.Directory]::CreateDirectory($fixtureRoot)|Out-Null
  Write-TestJson (Join-Path $fixtureRoot 'info.json') @{name='mir-tiny-k2';version='0.1.0';factorio_version='2.1';dependencies=@('base','alpha >= 1.0.0')}
  [IO.File]::WriteAllText((Join-Path $fixtureRoot 'control.lua'),'-- tiny current fixture')
  $fixtureArchive=Publish-MIRModDirectoryArchive -Source $fixtureRoot -Name 'mir-tiny-k2' -Version '0.1.0' -ModsDir $library
  $tinyInputs=@([ordered]@{file_name='alpha_1.0.0.zip';expected_sha256=$hashes['alpha_1.0.0.zip'];identity=@{name='alpha';version='1.0.0'}})
  $direct=Read-K2213DirectLibraryInputs -Library $library -Inputs $tinyInputs -FixtureRoot $fixtureRoot
  Assert-LibraryTest ($direct.archive_hashes.Count -eq 2 -and $direct.mod_list.mods.Count -eq 7) 'actual K2 reader selects only locked archives, fixture and five exact builtins'
  $profileK2=Join-Path $profiles 'k2-input-boundary.json';Write-TestJson $profileK2 $direct.mod_list
  $activation=Start-MIRLibraryActivation $library $data $profileK2 $direct.archive_hashes
  . (Join-Path $RepoRoot 'tools/lib/validation/NativeProbeResources.ps1')
  $context=[pscustomobject]@{root=$run;aliases=@();shared_alias_bytes=0L;max_new_output_bytes=1MB;result_reserve_bytes=64KB}
  $beforeControls=Get-MIRNativeProbeRemainingOutputBytes -Context $context
  Add-MIRNativeProbeLibraryActivation -Context $context -Activation $activation
  Assert-LibraryTest ((Get-MIRNativeProbeRemainingOutputBytes -Context $context) -lt $beforeControls) 'existing output budget charges active controls and recovery journal'
  $terminal=Complete-MIRLibraryActivation $activation;$activation=$null
  Assert-LibraryTest ((Get-MIRNativeProbeRemainingOutputBytes -Context $context) -eq $beforeControls) 'restored controls release their temporary output charge'
  Assert-LibraryTest ($terminal.selected.Count -eq 7 -and $terminal.dependency_payload_bytes_copied -eq 0) 'K2 selection consumes the real direct-library adapter'
  $wrong=@([ordered]@{file_name='alpha_9.0.0.zip';expected_sha256=$hashes['alpha_1.0.0.zip'];identity=@{name='alpha';version='9.0.0'}})
  Assert-LibraryRefusal {Read-K2213DirectLibraryInputs -Library $library -Inputs $wrong -FixtureRoot $fixtureRoot} 'archive-missing:alpha'
  Assert-LibraryTest (-not(Test-Path -LiteralPath (Join-Path $library 'alpha_9.0.0.zip'))) 'missing K2 input was not copied or downloaded'
  [IO.File]::WriteAllText((Join-Path $fixtureRoot 'control.lua'),'-- changed fixture body')
  Assert-LibraryRefusal {Read-K2213DirectLibraryInputs -Library $library -Inputs $tinyInputs -FixtureRoot $fixtureRoot} 'library-fixture-source:control.lua'
  Assert-LibraryTest (@(Get-ChildItem -LiteralPath $profiles -Recurse -File|Where-Object Extension -EQ '.zip').Count -eq 0) 'definition-only profiles'
  # Consume the upgrade selector with both MIR versions installed together.
  # The fixture archive is built once; phase switching only changes controls.
  . (Join-Path $RepoRoot 'tests/support/MIR421SpaceFakeUpgrade.ps1')
  $null=New-TestArchive 'more-infinite-research' '4.2.21000'
  $null=New-TestArchive 'more-infinite-research' '4.2.21001'
  $upgradeFixture=Join-Path $root 'upgrade-assertions';[IO.Directory]::CreateDirectory($upgradeFixture)|Out-Null
  Write-TestJson (Join-Path $upgradeFixture 'info.json') @{name='assert-upgrade-control';version='1.0.0';factorio_version='2.1';dependencies=@('base >= 2.1.0','more-infinite-research >= 4.2.21000')}
  [IO.File]::WriteAllText((Join-Path $upgradeFixture 'control.lua'),'-- controlled upgrade assertions')
  $null=Publish-MIRModDirectoryArchive -Source $upgradeFixture -Name 'assert-upgrade-control' -Version '1.0.0' -ModsDir $library
  $upgradeSettings=Join-Path $root 'upgrade-settings.dat'
  foreach($version in @('4.2.21000','4.2.21001')){
    $archive=Join-Path $library ('more-infinite-research_'+$version+'.zip')
    $selection=Get-MIRUpgradeLibrarySelection -Library $library -EngineDataDirectory $data -Archive $archive -Version $version -ExpectedSha256 (Get-MIRImmutableInputSha256 $archive) -FixtureDirectories @($upgradeFixture)
    $profile=Join-Path $profiles ('upgrade-'+$version+'.json');Write-TestJson $profile $selection.mod_list
    $settingsArgs=if($version-ceq'4.2.21001'){@{SettingsMode='File';SettingsPath=$upgradeSettings;SettingsSha256=Get-MIRImmutableInputSha256 $upgradeSettings}}else{@{SettingsMode='Defaults'}}
    $activation=Start-MIRLibraryActivation $library $data $profile $selection.archive_hashes @settingsArgs
    Assert-LibraryTest (@($activation.selected|Where-Object {$_.name-ceq'more-infinite-research'-and$_.version-ceq$version}).Count-eq1) ('upgrade selects exact '+$version)
    if($version-ceq'4.2.21000'){
      [IO.File]::WriteAllBytes((Join-Path $library 'mod-settings.dat'),[byte[]](2,7,9))
      $settings=Read-MIRLibraryControl (Join-Path $library 'mod-settings.dat')
      [IO.File]::WriteAllBytes($upgradeSettings,[Convert]::FromBase64String($settings.bytes))
    }else{
      Assert-LibraryTest ((Get-MIRImmutableInputSha256 (Join-Path $library 'mod-settings.dat'))-ceq(Get-MIRImmutableInputSha256 $upgradeSettings)) 'upgrade preserves predecessor settings in a private input'
      $upgradeAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot 'tests/runtime/Test-MIRUpgrade.ps1'),[ref]$tokens,[ref]$errors)
      Assert-LibraryTest ($errors.Count-eq0) 'direct upgrade harness parses'
      $function=@($upgradeAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq'Invoke-MIRUpgradeMonitoredProcess'},$true))
      . ([scriptblock]::Create($function[0].Extent.Text))
      $script:upgradeActivation=$activation;$script:upgradeProcessIndex=0;$script:upgradeResourceRuns=@()
      $suiteRoot=$root;$root=Join-Path $suiteRoot 'upgrade-actor-run'
      [IO.Directory]::CreateDirectory($root)|Out-Null
      $script:upgradeResourceContext=[pscustomobject]@{root=$root;aliases=@();shared_alias_bytes=0L;max_new_output_bytes=2MB;result_reserve_bytes=64KB}
      Add-MIRNativeProbeLibraryActivation -Context $script:upgradeResourceContext -Activation $activation
      $upgradePolicy=@{};$upgradePeakBytes=1MB
      [IO.Directory]::CreateDirectory((Join-Path $root 'userdata'))|Out-Null
      $upgradeConfig=Join-Path $root 'upgrade-config.ini'
      [IO.File]::WriteAllLines($upgradeConfig,@('[path]',('read-data='+$data),('write-data='+(Join-Path $root 'userdata')),'[other]','enable-new-mods=false'))
      $actor=(Get-Command Invoke-MIR441MonitoredProcess).ScriptBlock
      function Invoke-MIR441MonitoredProcess {
        param($FilePath,$Arguments,$WorkRoot,$LedgerPath,$Policy,$EstimatedPeakBytes,$ExpectedPeakMemoryBytes,$TimeoutSeconds,$StdoutPath,$StderrPath,[switch]$AllowNonZeroExit,$CompletionPredicate)
        Assert-LibraryTest ($Arguments[[Array]::IndexOf($Arguments,'--mod-directory')+1]-ceq$library) 'upgrade process reads master library directly'
        $currentLines=@($script:upgradeActivation.selected|ForEach-Object {'0.1 Loading mod '+$_.name+' '+$_.version+' (data.lua)'})
        [IO.File]::WriteAllLines($StdoutPath,@('Performed 1 updates in 0.597 ms'))
        [IO.File]::WriteAllLines((Join-Path $WorkRoot 'userdata/factorio-current.log'),@(
          '0.001 2026-10-08 00:00:00; Factorio 2.1.21 (build controlled)',
          '0.1 Loading mod retired-predecessor 9.9.9 (data.lua)',
          '0.001 2026-10-08 00:01:00; Factorio 2.1.21 (build controlled)')+$currentLines)
        return [pscustomobject]@{exit_code=0;completion_predicate_observed=$false;peak_working_set_bytes=1024;duration_seconds=0.01}
      }
      try{
        $result=Invoke-MIRUpgradeMonitoredProcess -FilePath $engine -Arguments @('--config',$upgradeConfig,'--mod-directory',$library)
        Assert-LibraryTest ($result.exit_code-eq0-and$script:upgradeResourceRuns.Count-eq1) 'actual upgrade actor adapter verifies loaded versions and retains resource result'
      }finally{Set-Item Function:Invoke-MIR441MonitoredProcess -Value $actor;$root=$suiteRoot}
    }
    $terminal=Complete-MIRLibraryActivation $activation;$activation=$null
    Assert-LibraryTest ($terminal.archive_links_created-eq0-and$terminal.dependency_payload_bytes_copied-eq0) 'upgrade phase stages no dependency payload'
  }
  Assert-LibraryTest (-not(Test-Path -LiteralPath (Join-Path $root 'source-profile'))-and-not(Test-Path -LiteralPath (Join-Path $root 'candidate-profile'))) 'upgrade creates no populated phase profiles'
  $badArchive=Join-Path $library 'more-infinite-research_4.2.21001.zip'
  Assert-LibraryRefusal {Get-MIRUpgradeLibrarySelection -Library $library -EngineDataDirectory $data -Archive $badArchive -Version '4.2.21001' -ExpectedSha256 ('0'*64) -FixtureDirectories @($upgradeFixture)} 'mir-upgrade-library-input-hash'
  [IO.File]::WriteAllText((Join-Path $upgradeFixture 'control.lua'),'-- altered upgrade assertions')
  Assert-LibraryRefusal {Get-MIRUpgradeLibrarySelection -Library $library -EngineDataDirectory $data -Archive $badArchive -Version '4.2.21001' -ExpectedSha256 (Get-MIRImmutableInputSha256 $badArchive) -FixtureDirectories @($upgradeFixture)} 'mir-library-fixture-member'
  [IO.File]::WriteAllText((Join-Path $upgradeFixture 'control.lua'),'-- controlled upgrade assertionX')
  Assert-LibraryRefusal {Get-MIRUpgradeLibrarySelection -Library $library -EngineDataDirectory $data -Archive $badArchive -Version '4.2.21001' -ExpectedSha256 (Get-MIRImmutableInputSha256 $badArchive) -FixtureDirectories @($upgradeFixture)} 'mir-library-fixture-source'
  # Run the actual browser selection and launch adapters against tiny inputs.
  # Only the native actor is substituted; shared activation owns the controls.
  $browserPath=Join-Path $RepoRoot 'tests/runtime/Test-MIRResearchBrowser.ps1'
  $browserAst=[Management.Automation.Language.Parser]::ParseFile($browserPath,[ref]$tokens,[ref]$errors)
  Assert-LibraryTest ($errors.Count-eq0) 'direct browser harness parses'
  foreach($name in @('Get-MIRBrowserLibrarySelection','Invoke-BrowserEngine')){
    $function=@($browserAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$true))
    Assert-LibraryTest ($function.Count-eq1) ('browser adapter exists: '+$name)
    . ([scriptblock]::Create($function[0].Extent.Text))
  }
  Assert-LibraryRefusal {& $browserPath -RepoRoot $RepoRoot} 'mir-browser-direct-inputs-required'
  $browserFixture=Join-Path $root 'browser-assertions';[IO.Directory]::CreateDirectory($browserFixture)|Out-Null
  Write-TestJson (Join-Path $browserFixture 'info.json') @{name='mir-browser-test';version='1.0.0';factorio_version='2.1';dependencies=@('base','more-infinite-research')}
  [IO.File]::WriteAllText((Join-Path $browserFixture 'control.lua'),'-- controlled browser assertions')
  $browserArgs=@{Library=$library;EngineVersion='2.1.20';Candidate=$badArchive;Version='4.2.21001';ExpectedSha256=(Get-MIRImmutableInputSha256 $badArchive);FixtureDirectory=$browserFixture}
  Assert-LibraryRefusal {Get-MIRBrowserLibrarySelection @browserArgs} 'mir-library-fixture-missing'
  $null=Publish-MIRModDirectoryArchive -Source $browserFixture -Name 'mir-browser-test' -Version '1.0.0' -ModsDir $library
  $selection=Get-MIRBrowserLibrarySelection @browserArgs
  $profile=Join-Path $profiles 'browser.json';Write-TestJson $profile $selection.mod_list
  $activation=Start-MIRLibraryActivation $library $data $profile $selection.archive_hashes -SettingsMode Defaults
  Assert-LibraryTest (-not(Test-Path -LiteralPath (Join-Path $library 'mod-settings.dat'))) 'browser defaults do not inherit previous settings'
  $active=Get-Content -LiteralPath (Join-Path $library 'mod-list.json') -Raw|ConvertFrom-Json
  Assert-LibraryTest ((@($active.mods|Where-Object enabled|ForEach-Object name|Sort-Object)-join '|')-ceq'base|mir-browser-test|more-infinite-research') 'browser enables only its exact base profile'
  $run=Join-Path $root 'browser-actor-run';[IO.Directory]::CreateDirectory((Join-Path $run 'userdata'))|Out-Null
  [IO.File]::WriteAllLines((Join-Path $run 'config.ini'),@('[path]',('read-data='+$data),('write-data='+(Join-Path $run 'userdata')),'[other]','enable-new-mods=false'))
  $resources=[pscustomobject]@{root=$run;aliases=@();shared_alias_bytes=0L;max_new_output_bytes=2MB;result_reserve_bytes=64KB}
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
  $browserActor=(Get-Command Invoke-MIRNativeProbeFactorioProcess).ScriptBlock
  $browserWrongVersion=$false
  function Invoke-MIRNativeProbeFactorioProcess {
    param($Context,$FilePath,$Arguments,$TimeoutSeconds)
    Assert-LibraryTest ($Arguments[[Array]::IndexOf($Arguments,'--mod-directory')+1]-ceq$library) 'browser process reads master library directly'
    if($Arguments -contains '--benchmark-graphics'){
      Assert-LibraryTest ($Arguments -contains '--single-thread-loading') 'browser retains bounded graphics arguments'
    }
    $lines=@('0.001 2026-10-08 00:00:00; Factorio 2.1.20 (build controlled)')
    $lines+=@($activation.selected|ForEach-Object {'0.1 Loading mod '+$_.name+' '+$(if($browserWrongVersion-and$_.name-ceq'more-infinite-research'){'4.2.21000'}else{$_.version})+' (data.lua)'})
    [IO.File]::WriteAllLines((Join-Path $Context.root 'userdata/factorio-current.log'),$lines)
    return [pscustomobject]@{result=@{exit_code=0}}
  }
  try{
    Invoke-BrowserEngine @('--create',(Join-Path $run 'test.zip'))
    Invoke-BrowserEngine @('--benchmark-graphics',(Join-Path $run 'test.zip'),'--benchmark-ticks','1')
    $browserWrongVersion=$true
    Assert-LibraryRefusal {Invoke-BrowserEngine @('--benchmark',(Join-Path $run 'test.zip'))} 'mir-library-loaded-selection'
  }finally{Set-Item Function:Invoke-MIRNativeProbeFactorioProcess -Value $browserActor}
  $terminal=Complete-MIRLibraryActivation $activation;$activation=$null
  Assert-LibraryTest ($terminal.archive_links_created-eq0-and$terminal.dependency_payload_bytes_copied-eq0-and$terminal.archive_extractions-eq0-and-not(Test-Path -LiteralPath (Join-Path $run 'mods'))) 'browser switches controls without a populated mod directory'
  Assert-LibraryTest ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $library 'mod-list.json')))-ceq[Convert]::ToBase64String($oldList)) 'browser restores previous selection'
  $browserArgs.ExpectedSha256='0'*64
  Assert-LibraryRefusal {Get-MIRBrowserLibrarySelection @browserArgs} 'mir-browser-library-input-hash'
  $browserArgs.ExpectedSha256=Get-MIRImmutableInputSha256 $badArchive
  $browserArgs.Candidate='absent-candidate.zip'
  Assert-LibraryRefusal {Get-MIRBrowserLibrarySelection @browserArgs} 'mir-browser-library-input-missing'
  $browserArgs.Candidate=$badArchive
  [IO.File]::WriteAllText((Join-Path $browserFixture 'control.lua'),'-- changed browser assertions')
  Assert-LibraryRefusal {Get-MIRBrowserLibrarySelection @browserArgs} 'mir-library-fixture-member'
  # Execute the runner's actual outer catch. A delayed engine shutdown can
  # refuse restoration; preserve both that boundary and the original failure.
  $outerTry=@($browserAst.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})
  Assert-LibraryTest ($outerTry.Count-eq1-and$outerTry[0].CatchClauses.Count-eq1) 'browser has one terminal failure handler'
  $browserFailure=[scriptblock]::Create("try { throw '[mir441-resource-admission-commit]' } "+$outerTry[0].CatchClauses[0].Extent.Text)
  $completeLibrary=(Get-Command Complete-MIRLibraryActivation).ScriptBlock
  $writeResult=(Get-Command Write-MIRNativeProbeResult).ScriptBlock
  $originalResources=$resources
  $resources=@{runs=[Collections.Generic.List[object]]::new()}
  $Target='2.1';$candidate=$badArchive
  function Complete-MIRLibraryActivation {
    param($Activation)
    if($script:browserCleanupRefused){throw '[mir-library-factorio-active]'}
    return @{status='restored-direct-library-controls'}
  }
  function Write-MIRNativeProbeResult {
    param($Context,$Record)
    if($script:browserReceiptRefused){throw 'controlled receipt budget'}
    $script:browserFailureRecord=$Record
  }
  try{
    foreach($cleanupRefused in @($false,$true)){
      $script:browserCleanupRefused=$cleanupRefused;$script:browserReceiptRefused=$false
      $activation=@{closed=$false;library=$library}
      Assert-LibraryRefusal $browserFailure 'mir441-resource-admission-commit'
      $record=$script:browserFailureRecord
      Assert-LibraryTest ($record.status-ceq'failed'-and$record.error-ceq'[mir441-resource-admission-commit]') 'browser retains primary resource failure'
      if($cleanupRefused){
        Assert-LibraryTest ($record.library_activation.status-ceq'recovery-required'-and$record.library_activation.error-ceq'[mir-library-factorio-active]') 'browser records cleanup refusal separately'
      }else{
        Assert-LibraryTest ($record.library_activation.status-ceq'restored-direct-library-controls') 'browser records successful failure cleanup'
      }
    }
    $script:browserReceiptRefused=$true
    Assert-LibraryRefusal $browserFailure 'mir441-resource-admission-commit'
  }finally{
    Set-Item Function:Complete-MIRLibraryActivation -Value $completeLibrary
    Set-Item Function:Write-MIRNativeProbeResult -Value $writeResult
    $resources=$originalResources;$activation=$null
  }
  # Legacy helpers must refuse external endpoints before creating directories,
  # deleting an existing target or falling back to a physical copy. No files
  # are created outside this test's checkout-contained scratch root.
  . (Join-Path $RepoRoot 'tools/lib/validation/FactorioProcess.ps1')
  . (Join-Path $RepoRoot 'tools/lib/validation/ImmutableInputStaging.ps1')
  $inside=Join-Path $library 'alpha_1.0.0.zip'
  $outside=Join-Path (Split-Path -Parent $RepoRoot) ('must-not-create-'+[guid]::NewGuid().ToString('N'))
  $prefixCollision=$RepoRoot+'-not-this-checkout/file.zip'
  foreach($external in @($outside,$prefixCollision,(Join-Path $RepoRoot '../must-not-create-traversal.zip'))){
    Assert-LibraryRefusal {Assert-MIRCheckoutHardLinkBoundary -Source $inside -Destination $external} 'mir-hardlink-outside-checkout'
    Assert-LibraryRefusal {Assert-MIRCheckoutHardLinkBoundary -Source $external -Destination (Join-Path $root 'safe.zip')} 'mir-hardlink-outside-checkout'
  }
  $sentinel=Join-Path $root 'untouched.txt';[IO.File]::WriteAllText($sentinel,'keep prior bytes')
  Assert-LibraryRefusal {Copy-MIRFileWithHardlinkFallback -Source $outside -Destination $sentinel} 'mir-hardlink-outside-checkout'
  Assert-LibraryTest ([IO.File]::ReadAllText($sentinel)-ceq'keep prior bytes') 'external rejection precedes target deletion and fallback'
  Assert-LibraryRefusal {Copy-MIRModDirectory -Source $fixtureRoot -Name fixture -ModsDir $outside} 'mir-hardlink-outside-checkout'
  Assert-LibraryRefusal {Copy-MIRCachedModZips -CacheDir $library -ModsDir $outside -LockEntries @([pscustomobject]@{file_name='alpha_1.0.0.zip';sha256=$hashes['alpha_1.0.0.zip']})} 'mir-hardlink-outside-checkout'
  $guardRun=Join-Path $root 'guard-run';[IO.Directory]::CreateDirectory($guardRun)|Out-Null
  $guardInputs=@(@{source_path=$outside;file_name='outside.zip';expected_sha256=('0'*64);role='test';identity=@{};provenance=@{};immutable=$true})
  Assert-LibraryRefusal {New-MIRImmutableInputLease -RunRoot $guardRun -StageDirectory (Join-Path $guardRun 'mods') -Inputs $guardInputs} 'mir-hardlink-outside-checkout'
  Assert-LibraryTest (@(Get-ChildItem -LiteralPath $guardRun -Force).Count-eq0) 'external input rejected before lease or staging creation'
  $guardInputs[0].source_path=$inside
  Assert-LibraryRefusal {New-MIRImmutableInputLease -RunRoot (Split-Path -Parent $RepoRoot) -StageDirectory $outside -Inputs $guardInputs} 'mir-hardlink-outside-checkout'
  Assert-LibraryTest (-not(Test-Path -LiteralPath $outside)) 'external output never created'
  # Check the existing internal fixture helper still works, including identity.
  $alias=Join-Path $root 'internal-alias.txt'
  Copy-MIRFileWithHardlinkFallback -Source $sentinel -Destination $alias
  Assert-LibraryTest ((Get-MIRImmutableInputFileIdentity $alias)-ceq(Get-MIRImmutableInputFileIdentity $sentinel)) 'checkout-local fixture alias remains valid'
  $junction=Join-Path $root 'junction-check'
  New-Item -ItemType Junction -Path $junction -Target $library|Out-Null
  try{
    Assert-LibraryRefusal {Assert-MIRCheckoutHardLinkBoundary -Source (Join-Path $junction 'alpha_1.0.0.zip') -Destination $alias} 'mir-hardlink-reparse'
    Assert-LibraryRefusal {Assert-MIRCheckoutHardLinkBoundary -Source $sentinel -Destination (Join-Path $junction 'new/alias.txt')} 'mir-hardlink-reparse'
  }finally{[IO.Directory]::Delete($junction,$false)}
  $parameters=[scriptblock]::Create($ast.ParamBlock.Extent.Text+"`nreturn ,`$LocalModLibraryDirs")
  $defaults=& $parameters -FactorioBin unused -CandidateZip unused -SourceMaterializationPath unused -V5ObservationResultPath unused
  Assert-LibraryTest ($defaults.Count-eq0) 'K2 runner requires an explicit machine-local archive library'
  $missingLibrary=Join-Path $root 'missing-library'
  Assert-LibraryRefusal {Start-MIRLibraryActivation $missingLibrary $data $profileA @{'alpha_1.0.0.zip'=$hashes['alpha_1.0.0.zip']}} 'mir-library-missing'
  Assert-LibraryTest (-not(Test-Path -LiteralPath $missingLibrary)) 'missing library is not recreated'
  # A tiny relocated path fixture, not a Git clone/worktree: execute the real
  # path helper from another root and verify it derives that root itself.
  $relocated=Join-Path $root 'relocated-path-fixture'
  $relocatedTools=Join-Path $relocated 'tools/lib/workspace'
  [IO.Directory]::CreateDirectory($relocatedTools)|Out-Null
  [IO.File]::WriteAllText((Join-Path $relocated '.git'),'controlled path marker; no Git repository')
  Copy-Item -LiteralPath (Join-Path $RepoRoot 'tools/lib/workspace/RepoPaths.ps1') -Destination $relocatedTools
  $pathModule=New-Module -ArgumentList (Join-Path $relocatedTools 'RepoPaths.ps1'),$relocated,$sentinel -ScriptBlock {
    param($Implementation,$Root,$Outside)
    . $Implementation
    Assert-MIRCheckoutHardLinkBoundary -Source (Join-Path $Root 'input.txt') -Destination (Join-Path $Root 'build/output.txt')
    $refused=$false
    try{Assert-MIRCheckoutHardLinkBoundary -Source $Outside -Destination (Join-Path $Root 'build/output.txt')}catch{$refused=$_.Exception.Message.Contains('mir-hardlink-outside-checkout')}
    if(-not$refused){throw 'Relocated helper retained the original root'}
  }
  Assert-LibraryTest ($null-ne$pathModule) 'relocated implementation uses its own checkout boundary without machine paths'
  [ordered]@{status='passed';checks=$script:checks;root=$root;native_engine_runs=0}|ConvertTo-Json
}finally{if($null -ne $activation -and -not $activation.closed){$null=Complete-MIRLibraryActivation $activation}}
