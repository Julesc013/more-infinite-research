# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if(-not $RepoRoot){$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path}
. (Join-Path $RepoRoot 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/ResourceGovernor.ps1')
. (Join-Path $RepoRoot 'tests/support/MIR421SpaceFakeUpgrade.ps1')
$root=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $RepoRoot ('build/tmp/library-activation-'+[guid]::NewGuid().ToString('N')))
[IO.Directory]::CreateDirectory($root)|Out-Null
$library=Join-Path $root 'library';$data=Join-Path $root 'engine/data';$profiles=Join-Path $root 'profiles'
foreach($path in @($library,$profiles,(Join-Path $data 'base'),(Join-Path $data 'quality'),(Join-Path $root 'engine/bin/x64'))){[IO.Directory]::CreateDirectory($path)|Out-Null}
$script:checks=0
function Assert-LibraryTest([bool]$Condition,[string]$Name){if(-not $Condition){throw "[library-test] $Name"};$script:checks++;Write-Host "[ok] $Name"}
function Assert-LibraryRefusal([scriptblock]$Action,[string]$Code){$caught='';try{& $Action|Out-Null}catch{$caught=$_.Exception.Message};Assert-LibraryTest ($caught.Contains($Code)) "refused $Code"}
function Write-TestJson($Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
function New-TestArchive([string]$Name,[string]$Version,[string[]]$Dependencies=@('base >= 2.1.0'),[string]$InfoJson=''){
  $path=Join-Path $library ($Name+'_'+$Version+'.zip')
  $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
  try{
    $entry=$zip.CreateEntry($Name+'_'+$Version+'/info.json')
    $writer=[IO.StreamWriter]::new($entry.Open())
    try{$writer.Write($(if($InfoJson){$InfoJson}else{@{name=$Name;version=$Version;factorio_version='2.1';dependencies=$Dependencies}|ConvertTo-Json}))}finally{$writer.Dispose()}
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
$fixtureName='mir-fixture-assert-upgrade-4-0-21000-to-4-1-21000'
$baseFixture=Join-Path $root 'owned-fixtures/base';$sifFixture=Join-Path $root 'owned-fixtures/sif';$f200Fixture=Join-Path $root 'owned-fixtures/f200'
foreach($directory in @($baseFixture,$sifFixture,$f200Fixture)){[IO.Directory]::CreateDirectory($directory)|Out-Null}
foreach($directory in @($baseFixture,$sifFixture)){Write-TestJson (Join-Path $directory 'info.json') @{name=$fixtureName;version='0.1.0';factorio_version='2.1';dependencies=@('base');title='Owned fixture probe'}}
Write-TestJson (Join-Path $f200Fixture 'info.json') @{name='mir-fixture-assert-upgrade-4-0-20000-to-4-1-20000';version='0.1.0';factorio_version='2.0';dependencies=@('base')}
$sifInfoHash=Get-MIRImmutableInputSha256 (Join-Path $sifFixture 'info.json')
Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $baseFixture -Target f210
Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $f200Fixture -Target f200
$baseInfo=Get-Content -LiteralPath (Join-Path $baseFixture 'info.json') -Raw|ConvertFrom-Json
Assert-LibraryTest ($baseInfo.version-ceq'0.1.1'-and$baseInfo.name-ceq$fixtureName-and$baseInfo.title-ceq'Owned fixture probe') 'modern base fixture has distinct version and retained metadata'
Assert-LibraryTest ((Get-Content -LiteralPath (Join-Path $f200Fixture 'info.json') -Raw|ConvertFrom-Json).version-ceq'0.1.1') 'F200 base fixture has distinct version'
Assert-LibraryTest ((Get-MIRImmutableInputSha256 (Join-Path $sifFixture 'info.json'))-ceq$sifInfoHash) 'SIF fixture bytes and 0.1.0 identity remain unchanged'
$baseInfoHash=Get-MIRImmutableInputSha256 (Join-Path $baseFixture 'info.json')
Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $baseFixture -Target f210
Assert-LibraryTest ((Get-MIRImmutableInputSha256 (Join-Path $baseFixture 'info.json'))-ceq$baseInfoHash) 'prepared base fixture identity is idempotent'
Assert-LibraryRefusal {Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $baseFixture -Target f200} 'mir421-modern-base-fixture-template'
Assert-LibraryTest ((Get-MIRImmutableInputSha256 (Join-Path $baseFixture 'info.json'))-ceq$baseInfoHash) 'wrong-target refusal preserves fixture bytes'
foreach($target422 in @('f210','f200','f110','f100')){
  $fixture422=Join-Path $root ('owned-fixtures/'+$target422+'-422')
  [IO.Directory]::CreateDirectory($fixture422)|Out-Null
  $info422=Join-Path $fixture422 'info.json';$code422=$target422.Substring(1)
  Write-TestJson $info422 @{name="mir-fixture-assert-upgrade-4-0-${code422}00-to-4-1-${code422}00";version='0.1.0';factorio_version=switch($target422){f210{'2.1'};f200{'2.0'};f110{'1.1'};f100{'1.0'}};dependencies=@('base')}
  Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $fixture422 -Target $target422 -SourceVersion '4.2.2'
  Assert-LibraryTest ((Get-Content -LiteralPath $info422 -Raw|ConvertFrom-Json).version-ceq'0.1.2') "4.2.2 $target422 fixture does not collide with prior upgrades"
  $hash422=Get-MIRImmutableInputSha256 $info422
  Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $fixture422 -Target $target422 -SourceVersion '4.2.2'
  Assert-LibraryTest ((Get-MIRImmutableInputSha256 $info422)-ceq$hash422) "4.2.2 $target422 fixture identity is idempotent"
  Assert-LibraryRefusal {Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $fixture422 -Target $target422} 'mir421-modern-base-fixture-template'
  Assert-LibraryTest ((Get-MIRImmutableInputSha256 $info422)-ceq$hash422) 'default source cannot rebrand a prepared 4.2.2 fixture'
}
foreach($target in @('f017','f016','f015','f014','f013')){foreach($patch in @(1,2)){
  $prepared=Join-Path $root "owned-fixtures/historical-$target-$patch"
  [IO.Directory]::CreateDirectory($prepared)|Out-Null
  $path=Join-Path $prepared 'info.json'
  $info=Get-Content -LiteralPath (Join-Path $RepoRoot 'fixtures/assert-upgrade-historical-terminal-to-mir42/info.json') -Raw|ConvertFrom-Json
  $info.factorio_version='0.'+[int]$target.Substring(1)
  $info.dependencies=@('base',('more-infinite-research >= 4.2.'+$target.Substring(1)+'0'+($patch-1)))
  Write-TestJson $path $info
  Set-MIR42HistoricalMaintenanceUpgradeFixtureIdentity -FixtureDirectory $prepared -Target $target -SourceVersion "4.2.$patch"
  $read=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
  Assert-LibraryTest ($read.version-ceq"1.0.$patch"-and$read.name-ceq$info.name-and($read.dependencies-join'|')-ceq($info.dependencies-join'|')) "$target maintenance fixture $patch retains metadata under a distinct identity"
  $hash=Get-MIRImmutableInputSha256 $path
  Set-MIR42HistoricalMaintenanceUpgradeFixtureIdentity -FixtureDirectory $prepared -Target $target -SourceVersion "4.2.$patch"
  Assert-LibraryTest ((Get-MIRImmutableInputSha256 $path)-ceq$hash) "$target historical fixture identity is idempotent"
  Assert-LibraryRefusal {Set-MIR42HistoricalMaintenanceUpgradeFixtureIdentity -FixtureDirectory $prepared -Target $target -SourceVersion $(if($patch-eq1){'4.2.2'}else{'4.2.1'})} 'mir42-historical-maintenance-fixture-template'
  $otherTarget=if($target-ceq'f013'){'f014'}else{'f013'}
  Assert-LibraryRefusal {Set-MIR42HistoricalMaintenanceUpgradeFixtureIdentity -FixtureDirectory $prepared -Target $otherTarget -SourceVersion "4.2.$patch"} 'mir42-historical-maintenance-fixture-template'
  Assert-LibraryTest ((Get-MIRImmutableInputSha256 $path)-ceq$hash) "$target historical refusal preserves bytes"
}}
Assert-LibraryRefusal {Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $baseFixture -Target f210 -SourceVersion '4.2.2'} 'mir421-modern-base-fixture-template'
Assert-LibraryRefusal {Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory (Join-Path $RepoRoot 'fixtures/assert-upgrade-4-0-21000-to-4-1-21000') -Target f210} 'mir441-resource-output-root'
function Test-MaintenanceFixtureCallSites {
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot 'tests/runtime/Test-MIRUpgrade.ps1'),[ref]$tokens,[ref]$errors)
  Assert-LibraryTest (-not$errors.Count) 'upgrade fixture caller parses'
  $resolver=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name-ceq'Resolve-MIRHistoricalUpgradeTransition'},$true))
  $modern=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.StartsWith("if (`$FixtureName -in @('assert-upgrade-4-0-21000-to-4-1-21000'")},$true))
  $historicalBlocks=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.StartsWith('if ($isHistoricalTerminalFixture) {') -and $n.Extent.Text.Contains('$historical = Resolve-MIRHistoricalUpgradeTransition')},$true))
  Assert-LibraryTest ($resolver.Count-eq1-and$modern.Count-eq1-and$historicalBlocks.Count-eq1) 'upgrade fixture specialization call sites are unambiguous'
  . ([scriptblock]::Create($resolver[0].Extent.Text))
  foreach($targetToken in @('210','200','110','100','017','016','015','014','013')){foreach($patch in @(1,2)){
    $code=$targetToken
    $SourceVersion="4.2.$patch";$FromVersion="4.2.${code}0$($patch-1)";$ToVersion="4.2.${code}0$patch"
    $isHistoricalTerminalFixture=$code.StartsWith('0');$SpaceIsFake=$false;$Archetype='base-default'
    $FixtureName=if($isHistoricalTerminalFixture){'assert-upgrade-historical-terminal-to-mir42'}else{"assert-upgrade-4-0-${code}00-to-4-1-${code}00"}
    $stagedFixture=Join-Path $root "owned-fixtures/caller-$code-$patch"
    Copy-Item -LiteralPath (Join-Path $RepoRoot ('fixtures/'+$FixtureName)) -Destination $stagedFixture -Recurse
    $block=if($isHistoricalTerminalFixture){$historicalBlocks[0]}else{$modern[0]}
    . ([scriptblock]::Create($block.Extent.Text))
    $read=Get-Content -LiteralPath (Join-Path $stagedFixture 'info.json') -Raw|ConvertFrom-Json
    $version=if($isHistoricalTerminalFixture){"1.0.$patch"}else{"0.1.$patch"}
    Assert-LibraryTest ($read.version-ceq$version-and$read.dependencies -ccontains "more-infinite-research >= $FromVersion") "$code/$patch real caller chooses a distinct prepared fixture and predecessor"
    $control=Get-Content -LiteralPath (Join-Path $stagedFixture 'control.lua') -Raw
    Assert-LibraryTest ($control.Contains($FromVersion)-and$control.Contains($ToVersion)-and-not$control.Contains('__MIR_UPGRADE_')) "$code/$patch real caller specializes continuity assertions"
  }}
}
Test-MaintenanceFixtureCallSites
$baseFixtureArchive=New-TestArchive $fixtureName '0.1.1' -InfoJson (Get-Content -LiteralPath (Join-Path $baseFixture 'info.json') -Raw)
$sifFixtureArchive=New-TestArchive $fixtureName '0.1.0' -InfoJson (Get-Content -LiteralPath (Join-Path $sifFixture 'info.json') -Raw)
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
  foreach($case in @(@('0.1.0',$sifFixture,$sifFixtureArchive),@('0.1.1',$baseFixture,$baseFixtureArchive),@('0.1.0',$sifFixture,$sifFixtureArchive))){
    Assert-MIRLibraryFixtureArchive -Archive $case[2] -SourceDirectory $case[1]
    $profile=Join-Path $profiles ('owned-fixture-'+$case[0]+'.json')
    Write-TestJson $profile @{mods=@(@{name='base';version='2.1.20';enabled=$true},@{name=$fixtureName;version=$case[0];enabled=$true})}
    $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $data -ProfilePath $profile -ArchiveHashes @{([IO.Path]::GetFileName($case[2]))=$hashes[[IO.Path]::GetFileName($case[2])]}
    Assert-LibraryTest ((@($activation.selected|Where-Object {$_.name-ceq$fixtureName})[0].version)-ceq$case[0]) 'actual library selects exact SIF/base/SIF fixture version'
    $active=Get-Content -LiteralPath (Join-Path $library 'mod-list.json') -Raw|ConvertFrom-Json
    Assert-LibraryTest ((@($active.mods|Where-Object {$_.name-ceq$fixtureName})[0].version)-ceq$case[0]) 'active control pins owned fixture version with both archives present'
    $null=Complete-MIRLibraryActivation $activation;$activation=$null
  }
  # Exercise the actual entry points in fresh hosts with deliberately missing
  # inputs. Retirement must win before repository/engine lookup, construction
  # or staging; these controls cannot launch Factorio even if a guard regresses.
  $retired=@(
    'MIR4HistoricalPrivateRuntime','MIR4A05K2Materials','MIR4A05K203Imersite','MIR4A03K2K2SOIntake',
    'MIRA06BobGoldQualification','MIRA06BobAluminiumQualification','MIRA06BobLeadQualification',
    'MIRA06BobOrdinaryAlloysQualification','MIRA06AluminiumFinalState',
    'MIRBobAngelTinRouteSafety','MIRBobAngelTinFinalStateAudit','MIRAngelTinFinalStateAudit',
    'MIRBobTinBrowserExplanation','MIRBobTinPersistedState','MIRBobTinProductionGain',
    'MIRBobTinMachineMatrix','MIRBobTinProgressionFrontier','MIRBobTinQualification',
    'MIRF200BobTinPersistedState','MIRF200BobTinProductionGain',
    'MIRF210CurrentBobAngelFinalRoutesObserver','MIRF210CurrentBobAngelTinRouteObserver',
    'MIRF210CurrentBobAngelGunmetalInvarQualification','MIRK2213ImersiteMigration','MIRPassiveRepair',
    'MIRCandidateRetention','MIRPortableResearchSurfaceNoMir',
    'scripts/Measure-MIRPerformanceRegression.ps1','scripts/Invoke-MIRPerformanceQualification.ps1'
  )
  $absentRoot=Join-Path $root 'must-not-create-retired-run'
  foreach($name in $retired){
    $runnerDirectory=if($name-ceq'MIRCandidateRetention'){'tests/package/'}else{'tests/runtime/'}
    $runner=Join-Path $RepoRoot $(if($name.StartsWith('scripts/')){$name}else{$runnerDirectory+'Test-'+$name+'.ps1'})
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors)
    Assert-LibraryTest ($errors.Count-eq0) "$name entry parses"
    $parameters=@($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
    $argsList=@('-NoProfile','-NonInteractive','-File',$runner)
    if('RepoRoot' -in $parameters){$argsList+=@('-RepoRoot',$absentRoot)}
    if('OutputRoot' -in $parameters){$argsList+=@('-OutputRoot',$absentRoot)}
    foreach($inputName in @('FactorioBin','Candidate','PriorRelease','CandidateZip','OldCandidateZip','NewCandidateZip','V5ObservationResultPath')){
      if($inputName -in $parameters){$argsList+=@(('-'+$inputName),(Join-Path $absentRoot $inputName))}
    }
    if('ExpectedSourceCommit' -in $parameters){$argsList+=@('-ExpectedSourceCommit',('1'*40))}
    if('ExpectedBaselineVersion' -in $parameters){$argsList+=@('-ExpectedBaselineVersion','4.2.21000')}
    if('ExpectedFactorioVersion' -in $parameters){$argsList+=@('-ExpectedFactorioVersion','2.1.21')}
    if($name-ceq'MIR4HistoricalPrivateRuntime'){$argsList+=@('-Target','f013')}
    $text=@(& pwsh @argsList 2>&1)|Out-String
    $exitCode=$LASTEXITCODE;$global:LASTEXITCODE=0
    if($exitCode-eq0 -or -not$text.Contains('[mir-native-obsolete-runner]')){throw "[library-test] $name retirement diagnostic differs: $text"}
    Assert-LibraryTest ($exitCode-ne0) "$name refuses before accessing inputs"
    Assert-LibraryTest (-not(Test-Path -LiteralPath $absentRoot)) "$name allocated no retired environment"
  }
  # Native compatibility sweeps must refuse before policy/input discovery can
  # allocate their legacy cache or populated run directory. Metadata mode keeps
  # reaching its normal input validation; missing policies keep both cases tiny.
  foreach($native in @($true,$false)){
    $entry=Join-Path $RepoRoot 'tools/commands/compatibility/Invoke-MIRCompatAudit.ps1'
    $argsList=@('-NoProfile','-NonInteractive','-File',$entry,('-RunLoadTests:'+('$'+$native.ToString().ToLowerInvariant())),'-Offline','-SanitationBudgetPath',(Join-Path $absentRoot 'missing-policy.json'),'-OutputDir',$absentRoot,'-ModCacheDir',(Join-Path $absentRoot 'cache'))
    $text=@(& pwsh @argsList 2>&1)|Out-String
    $exitCode=$LASTEXITCODE;$global:LASTEXITCODE=0
    Assert-LibraryTest ($exitCode-ne0-and$text.Contains('[mir-native-obsolete-runner]')-eq$native) "compatibility audit native=$native has the expected entry boundary"
    Assert-LibraryTest (-not(Test-Path -LiteralPath $absentRoot)) "compatibility audit native=$native creates no cache or staging"
  }
  # The control-plane wrapper used to clone an overlay before reaching the
  # guarded performance command. Execute its real function without importing
  # prerequisites: retirement must precede context lookup and clone creation.
  $tokens=$null;$errors=$null
  $performanceAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot 'tools/lib/control/executor/RuntimeMeasurements.ps1'),[ref]$tokens,[ref]$errors)
  Assert-LibraryTest ($errors.Count-eq0) 'performance executor parses'
  $performanceEntry=@($performanceAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name-ceq'Invoke-MIRCPPerformanceMeasurement'},$true))
  Assert-LibraryTest ($performanceEntry.Count-eq1) 'one consumed performance executor'
  . ([scriptblock]::Create($performanceEntry[0].Extent.Text))
  Assert-LibraryRefusal {Invoke-MIRCPPerformanceMeasurement -ContextPath $absentRoot -FactorioBin $absentRoot -PriorRelease $absentRoot -RepoRoot $absentRoot} 'mir-native-obsolete-runner'
  Assert-LibraryTest (-not(Test-Path -LiteralPath $absentRoot)) 'performance executor creates no overlay or output'
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
    $complete=@($activation.selected|Sort-Object name|ForEach-Object {$_.name+'@'+$_.version})-join '|'
    $stageLine='0.2 Loading mod base 2.1.20 (data.lua)'
    $observerLine='0.3 Script @__alpha__/data-final-fixes.lua:8: [MIR_ACTIVE_MODS] '+$complete
    [IO.File]::WriteAllLines($log,@($stageLine,$observerLine))
    Assert-LibraryRefusal {Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log} 'mir-library-loaded-selection'
    Assert-LibraryTest (@(Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -ActiveModsObserver alpha).Count-eq2) 'explicit native observer includes asset-only identities'
    Assert-LibraryRefusal {Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -ActiveModsObserver unrequested} 'mir-library-loaded-observer'
    foreach($invalid in @('base@2.1.20','base@2.1.20|alpha@9.0.0','base@2.1.20|base@2.1.20',($complete+'|unrequested@1.0.0'))){
      [IO.File]::WriteAllLines($log,@($stageLine,('0.3 Script @__alpha__/data-final-fixes.lua:8: [MIR_ACTIVE_MODS] '+$invalid)))
      Assert-LibraryRefusal {Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -ActiveModsObserver alpha} 'mir-library-loaded-selection'
    }
    [IO.File]::WriteAllLines($log,@($stageLine,$observerLine,$observerLine))
    Assert-LibraryRefusal {Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -ActiveModsObserver alpha} 'mir-library-loaded-observation'
    [IO.File]::WriteAllLines($log,@($stageLine,$observerLine,'0.4 Loading mod alpha 9.0.0 (data.lua)'))
    Assert-LibraryRefusal {Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -ActiveModsObserver alpha} 'mir-library-loaded-selection'
    [IO.File]::WriteAllLines($log,@($stageLine,$observerLine.Replace('@__alpha__/','@__unrequested__/')))
    Assert-LibraryRefusal {Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -ActiveModsObserver alpha} 'mir-library-loaded-observation'
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
  # The durable owner timestamp must remain an exact string. PowerShell's
  # automatic date conversion otherwise permits recovery under a live owner.
  $journalPath=Join-Path $library '.mir-active-profile.json'
  $listPath=Join-Path $library 'mod-list.json';$settingsPath=Join-Path $library 'mod-settings.dat'
  $originalControls=@{'mod-list.json'=(Read-MIRLibraryControl $listPath);'mod-settings.dat'=(Read-MIRLibraryControl $settingsPath)}
  $ownerStarted=(Get-Process -Id $PID).StartTime.ToUniversalTime()
  foreach($matchingOwner in @($true,$false)){
    [IO.File]::WriteAllText($listPath,'{"mods":[{"name":"live-owner-selection","enabled":true}]}')
    [IO.File]::WriteAllBytes($settingsPath,[byte[]](3,2,1))
    $recordedStart=if($matchingOwner){$ownerStarted}else{$ownerStarted.AddSeconds(-1)}
    Write-TestJson $journalPath @{kind='MIRDirectLibraryActivationV1';library=$library;owner_pid=$PID;owner_started_utc=$recordedStart.ToString('o');controls=$originalControls}
    $ownedHashes=@{};foreach($path in @($listPath,$settingsPath,$journalPath)){$ownedHashes[$path]=Get-MIRImmutableInputSha256 $path}
    $missingProfile=Join-Path $profiles 'missing-next-profile.json'
    if($matchingOwner){
      Assert-LibraryRefusal {Start-MIRLibraryActivation $library $data $missingProfile @{}} 'mir-library-recovery-owner-alive'
      foreach($path in @($listPath,$settingsPath,$journalPath)){
        Assert-LibraryTest ((Test-Path -LiteralPath $path)-and(Get-MIRImmutableInputSha256 $path)-ceq$ownedHashes[$path]) ('live owner preserves '+[IO.Path]::GetFileName($path))
      }
    }else{
      Assert-LibraryRefusal {Start-MIRLibraryActivation $library $data $missingProfile @{}} 'mir-library-profile-missing'
      Assert-LibraryTest (-not(Test-Path -LiteralPath $journalPath)) 'different birth identity permits stale-journal recovery'
      Assert-LibraryTest ([Convert]::ToBase64String([IO.File]::ReadAllBytes($listPath))-ceq[Convert]::ToBase64String($oldList)) 'stale identity restores original mod-list'
      Assert-LibraryTest ([Convert]::ToBase64String([IO.File]::ReadAllBytes($settingsPath))-ceq[Convert]::ToBase64String($oldSettings)) 'stale identity restores original settings'
    }
  }
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
  & {
    # Bounded process observations, not an engine run: additional clients may
    # read one active selection but must never rewrite it under a live server.
    $server=[pscustomobject]@{Id=901;StartTime=[DateTime]'2026-10-08';HasExited=$false;Path=$engine}
    $script:observedEngines=@($server);$script:observedParent=$PID
    function Get-Process {param($Name) if($Name-cne'factorio'){throw 'Unexpected process query'};return $script:observedEngines}
    function Get-CimInstance {param($ClassName,$Filter) [pscustomobject]@{ParentProcessId=$script:observedParent}}
    function Write-MIRLibraryControl {throw 'Controls were rewritten while a server was live'}
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $arguments -OwnedProcesses @($server)
    Assert-LibraryTest $true 'owned live server permits read-only client admission'
    $script:observedEngines=@($server,[pscustomobject]@{Id=902})
    Assert-LibraryRefusal {Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $arguments -OwnedProcesses @($server)} 'mir-library-unowned-process'
    $script:observedEngines=@($server);$script:observedParent=$PID+1
    Assert-LibraryRefusal {Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $arguments -OwnedProcesses @($server)} 'mir-library-unowned-process'
    $script:observedParent=$PID
    $stale=[pscustomobject]@{Id=901;StartTime=[DateTime]'2026-10-07';HasExited=$false;Path=$engine}
    Assert-LibraryRefusal {Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $arguments -OwnedProcesses @($stale)} 'mir-library-unowned-process'
    $changed=[Text.Encoding]::UTF8.GetString($activation.mod_list_bytes)|ConvertFrom-Json
    ($changed.mods|Where-Object name -EQ 'unrequested').enabled=$true
    [IO.File]::WriteAllText((Join-Path $library 'mod-list.json'),($changed|ConvertTo-Json -Depth 8))
    Assert-LibraryRefusal {Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $arguments -OwnedProcesses @($server)} 'mir-library-live-selection'
    [IO.File]::WriteAllBytes((Join-Path $library 'mod-list.json'),$activation.mod_list_bytes)
  }
  $savedGuard=(Get-Command Assert-MIRLibraryIdle).ScriptBlock
  & {
    $script:idleObservations=0;$script:engineRemains=$false
    function Get-Process {
      param($Name)
      if($Name-cne'factorio'){throw 'Unexpected process query'}
      $script:idleObservations++
      if($script:engineRemains -or $script:idleObservations-le2){return [pscustomobject]@{Id=901}}
    }
    Assert-LibraryRefusal {Assert-MIRLibraryIdle} 'mir-library-factorio-active'
    Assert-LibraryTest ($script:idleObservations-eq1) 'initial admission refuses a live client immediately'
    $script:idleObservations=0
    Assert-MIRLibraryIdle -WaitMilliseconds 500
    Assert-LibraryTest ($script:idleObservations-eq3) 'bounded restoration wait observes complete process exit'
    $script:engineRemains=$true
    Assert-LibraryRefusal {Assert-MIRLibraryIdle -WaitMilliseconds 100} 'mir-library-factorio-active'
  }
  function Assert-MIRLibraryIdle {
    param($WaitMilliseconds)
    Assert-LibraryTest ($WaitMilliseconds-eq3000) 'restoration waits under the existing exclusive lock'
    throw '[mir-library-factorio-active] controlled live client'
  }
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
  $current=Read-K2213DirectLibraryInputs -Library $library -Inputs $tinyInputs -FixtureRoot $fixtureRoot -EngineVersion '2.1.21'
  Assert-LibraryTest (@($current.mod_list.mods|Where-Object {$_.version -ceq '2.1.21'}).Count -eq 5 -and $current.archive_hashes.Count -eq 2) 'K2 current engine selection changes bundled versions without staging archives'
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
  # Exercise Tin's actual selector with tiny archives and the real shared
  # activation. This tests the staging conversion without replaying gameplay.
  $tinHarness=Join-Path $RepoRoot 'tests/runtime/Test-MIRF210CurrentBobTinLevel4Continuation.ps1'
  $tinAst=[Management.Automation.Language.Parser]::ParseFile($tinHarness,[ref]$tokens,[ref]$errors)
  Assert-LibraryTest ($errors.Count-eq0) 'Tin direct-library runner parses'
  foreach($name in @('Assert-Tin','Get-TinSha','Get-TinRelative','Get-TinArtifact','Resolve-TinEngineBinding','Save-TinSettingsObservation','Read-TinDirectLibraryInputs')){
    $nodes=@($tinAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$false))
    if($nodes.Count-ne1){throw "Tin input function is absent or duplicated: $name"}
    . ([scriptblock]::Create($nodes[0].Extent.Text))
  }
  $tinDossier=[pscustomobject]@{target=@{factorio_version='2.1.20';engine_sha256=('A'*64)}}
  $historicalBinding=Resolve-TinEngineBinding -Dossier $tinDossier -Version '' -Sha256 ''
  Assert-LibraryTest ($historicalBinding.version-ceq'2.1.20'-and$historicalBinding.sha256-ceq('A'*64)-and-not$historicalBinding.explicit) 'Tin retains historical engine binding by default'
  $freshBinding=Resolve-TinEngineBinding -Dossier $tinDossier -Version '2.1.21' -Sha256 ('B'*64)
  Assert-LibraryTest ($freshBinding.version-ceq'2.1.21'-and$freshBinding.sha256-ceq('B'*64)-and$freshBinding.prior_engine_version-ceq'2.1.20'-and$freshBinding.explicit) 'Tin fresh engine binding preserves historical provenance'
  Assert-LibraryRefusal {Resolve-TinEngineBinding -Dossier $tinDossier -Version '2.1.21' -Sha256 ''} 'supply both expected engine'
  Assert-LibraryRefusal {Resolve-TinEngineBinding -Dossier $tinDossier -Version '' -Sha256 ('B'*64)} 'supply both expected engine'
  Assert-LibraryRefusal {Resolve-TinEngineBinding -Dossier $tinDossier -Version '2.0.77' -Sha256 ('B'*64)} 'invalid F210 engine binding'
  Assert-LibraryRefusal {Resolve-TinEngineBinding -Dossier $tinDossier -Version '2.1.21' -Sha256 'bad'} 'invalid F210 engine binding'
  $emptyControls=Join-Path $root 'tin-default-controls';[IO.Directory]::CreateDirectory($emptyControls)|Out-Null
  $absentSnapshot=Join-Path $run 'tin-absent-settings.dat'
  $observed=Save-TinSettingsObservation $RepoRoot $emptyControls $absentSnapshot
  Assert-LibraryTest ($observed.absent-and$observed.bytes-eq0-and-not(Test-Path -LiteralPath $absentSnapshot)) 'Tin records explicit default settings without inventing an input file'
  $tinExpected=[ordered]@{'alpha_1.0.0.zip'=@{name='alpha';version='1.0.0';sha256=$hashes['alpha_1.0.0.zip']}}
  $tinCandidate=[pscustomobject]@{path=(Join-Path $library 'more-infinite-research_4.2.21001.zip');receipt=@{distribution_version='4.2.21001'}}
  $tinArguments=@{Library=$library;ExpectedArchives=$tinExpected;Candidate=$tinCandidate;FixtureRoot=$upgradeFixture;EngineVersion='2.1.20';OfficialMods=@('base','elevated-rails','quality','recycler','space-age')}
  $tinZipCount=@(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.zip').Count
  $tinDirect=Read-TinDirectLibraryInputs @tinArguments
  Assert-LibraryTest ($tinDirect.archive_hashes.Count-eq3-and$tinDirect.mod_list.mods.Count-eq8) 'Tin projects full identity records into resolver hashes and exact profile rows'
  $tinProfile=Join-Path $profiles 'tin-selection.json';Write-TestJson $tinProfile $tinDirect.mod_list
  $activation=Start-MIRLibraryActivation $library $data $tinProfile $tinDirect.archive_hashes -SettingsMode File -SettingsPath $privateSettings -SettingsSha256 (Get-MIRImmutableInputSha256 $privateSettings)
  Assert-LibraryTest (@($activation.selected|Where-Object {$_.name-ceq'alpha'-and$_.version-ceq'1.0.0'}).Count-eq1) 'Tin selects the pinned older archive with multiple versions installed'
  Assert-LibraryTest (@($activation.selected|Where-Object {$_.name-ceq'more-infinite-research'-and$_.version-ceq'4.2.21001'}).Count-eq1) 'Tin selects source patch one'
  Assert-LibraryTest ((Get-MIRImmutableInputFileIdentity (Join-Path $library 'mod-settings.dat'))-cne(Get-MIRImmutableInputFileIdentity $privateSettings)) 'Tin settings remain private writable bytes'
  $settingsSnapshot=Join-Path $run 'tin-selected-settings.dat'
  $observed=Save-TinSettingsObservation $RepoRoot $library $settingsSnapshot
  Assert-LibraryTest ($observed.raw_sha256-ceq(Get-MIRImmutableInputSha256 $privateSettings)-and(Get-MIRImmutableInputFileIdentity $settingsSnapshot)-cne(Get-MIRImmutableInputFileIdentity (Join-Path $library 'mod-settings.dat'))) 'Tin captures active settings privately before restoration'
  $terminal=Complete-MIRLibraryActivation $activation;$activation=$null
  Assert-LibraryTest ($terminal.dependency_payload_bytes_copied-eq0) 'Tin restores controls without archive staging'
  $tinArguments.ExpectedArchives=[ordered]@{'alpha_9.0.0.zip'=@{name='alpha';version='9.0.0';sha256=$hashes['alpha_1.0.0.zip']}}
  Assert-LibraryRefusal {Read-TinDirectLibraryInputs @tinArguments} 'dependency-missing'
  $tinArguments.ExpectedArchives=$tinExpected
  $tinExpected['alpha_1.0.0.zip'].sha256='0'*64
  Assert-LibraryRefusal {Read-TinDirectLibraryInputs @tinArguments} 'dependency-hash'
  $tinExpected['alpha_1.0.0.zip'].sha256=$hashes['alpha_1.0.0.zip']
  $tinDonor=Join-Path $root 'tin-candidate-donor';[IO.Directory]::CreateDirectory($tinDonor)|Out-Null
  $tinCandidate.path=Join-Path $tinDonor 'more-infinite-research_4.2.21001.zip'
  [IO.File]::WriteAllText($tinCandidate.path,'different controlled candidate bytes')
  Assert-LibraryRefusal {Read-TinDirectLibraryInputs @tinArguments} 'library candidate bytes differ'
  $tinCandidate.path=Join-Path $library 'more-infinite-research_4.2.21001.zip'
  [IO.File]::WriteAllText((Join-Path $upgradeFixture 'control.lua'),'-- changed controlled upgrade assertions')
  Assert-LibraryRefusal {Read-TinDirectLibraryInputs @tinArguments} 'mir-library-fixture-member'
  [IO.File]::WriteAllText((Join-Path $upgradeFixture 'control.lua'),'-- controlled upgrade assertions')
  Assert-LibraryTest (@(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.zip').Count-eq($tinZipCount+1)) 'Tin adds no archives beyond the explicit tiny mismatch fixture'
  $tinParameters=[scriptblock]::Create($tinAst.ParamBlock.Extent.Text+"`nreturn ,`$LocalModLibraryDirs")
  Assert-LibraryTest ((& $tinParameters -RepoRoot $RepoRoot -FactorioBin unused).Count-eq0) 'Tin requires an explicit machine-local library'
  Assert-LibraryRefusal {& $tinHarness -FactorioBin unused -RecoverRun retired} 'mir-tin-obsolete-runner-mode'
  Assert-LibraryRefusal {& $tinHarness -FactorioBin unused -ExactStageRoot retired} 'mir-tin-obsolete-runner-mode'
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
      # This controlled actor represents the ordinary base upgrade. The actual
      # adapter also supports a K2 observer; initialize that scenario explicitly.
      $k2Scenario=$false
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
  foreach($name in @('Get-MIRBrowserLibrarySelection','Get-MIRBrowserIconCase','Initialize-MIRBrowserIconFixture','Invoke-BrowserEngine')){
    $function=@($browserAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$true))
    Assert-LibraryTest ($function.Count-eq1) ('browser adapter exists: '+$name)
    . ([scriptblock]::Create($function[0].Extent.Text))
  }
  Assert-LibraryRefusal {& $browserPath -RepoRoot $RepoRoot} 'mir-browser-direct-inputs-required'
  Assert-LibraryTest ($null-eq(Get-MIRBrowserIconCase 'None')) 'ordinary browser fixture has no icon-setting override'
  foreach($row in @(@('Defaults',$false,$null),@('RawOptIn',$true,$null),@('ImportedOptIn',$false,$true),@('RawOptInImportedOff',$true,$false))){
    $selected=Get-MIRBrowserIconCase $row[0]
    Assert-LibraryTest ($selected.raw-eq$row[1]-and$selected.imported-eq$row[2]) ('explicit icon settings: '+$row[0])
  }
  Assert-LibraryRefusal {Get-MIRBrowserIconCase 'unknown'} 'mir-browser-icon-case'
  # Preparation and execution happen in different PowerShell processes.
  # Hashtable JSON ordering must not change the verified fixture bytes.
  $iconBuilder=Join-Path $root 'build-icon-fixture.ps1'
  @'
param($Repository,$Fixture,$Case)
$ErrorActionPreference='Stop'
. (Join-Path $Repository 'tools/lib/validation/SettingsOverrides.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Repository 'tests/runtime/Test-MIRResearchBrowser.ps1'),[ref]$tokens,[ref]$errors)
foreach($name in @('Get-MIRBrowserIconCase','Initialize-MIRBrowserIconFixture')){
  $function=$ast.Find({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq$name},$true)
  . ([scriptblock]::Create($function.Extent.Text))
}
Initialize-MIRBrowserIconFixture -Fixture $Fixture -Repository $Repository -Case $Case
'@|Set-Content -LiteralPath $iconBuilder
  foreach($case in @('ImportedOptIn','RawOptInImportedOff')){
    $digests=@()
    foreach($attempt in 1..3){
      $generated=Join-Path $root ('icons-'+$case+'-'+$attempt);[IO.Directory]::CreateDirectory($generated)|Out-Null
      & (Get-Command pwsh).Source -NoProfile -File $iconBuilder -Repository $RepoRoot -Fixture $generated -Case $case
      Assert-LibraryTest ($LASTEXITCODE-eq0) 'actual icon fixture builder succeeds in a fresh process'
      $digests+=(@(Get-ChildItem -LiteralPath $generated -File|Sort-Object Name|ForEach-Object {(Get-FileHash -LiteralPath $_.FullName).Hash})-join '|')
    }
    Assert-LibraryTest (@($digests|Sort-Object -Unique).Count-eq1) ('prepared/executed icon fixture bytes are deterministic: '+$case)
  }
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
  $iconCase=$null
  $DlcIconCase='None';$iconObservations=[Collections.Generic.List[object]]::new()
  $GraphicsPreset='very-low'
  $resources|Add-Member process_index 0
  $browserIconMarker='present'
  function Invoke-MIRNativeProbeFactorioProcess {
    param($Context,$FilePath,$Arguments,$TimeoutSeconds)
    Assert-LibraryTest ($Arguments[[Array]::IndexOf($Arguments,'--mod-directory')+1]-ceq$library) 'browser process reads master library directly'
    if($Arguments -contains '--benchmark-graphics'){
      Assert-LibraryTest ($Arguments -contains '--single-thread-loading') 'browser retains bounded graphics arguments'
      Assert-LibraryTest ($Arguments[[Array]::IndexOf($Arguments,'--force-graphics-preset')+1]-ceq$GraphicsPreset) 'browser forwards its selected graphics preset'
    }
    $lines=@('0.001 2026-10-08 00:00:00; Factorio 2.1.20 (build controlled)')
    $lines+=@($activation.selected|ForEach-Object {'0.1 Loading mod '+$_.name+' '+$(if($browserWrongVersion-and$_.name-ceq'more-infinite-research'){'4.2.21000'}else{$_.version})+' (data.lua)'})
    if($null-ne$iconCase-and$browserIconMarker-cne'absent'){
      $observedCase=if($browserIconMarker-ceq'wrong-case'){'Defaults'}else{$DlcIconCase}
      $line='0.2 Script: [mir-browser-icons] PASS '+(@{case=$observedCase;inactive_provider_references=0}|ConvertTo-Json -Compress)
      $lines+=$line;if($browserIconMarker-ceq'duplicate'){$lines+=$line}
    }
    [IO.File]::WriteAllLines((Join-Path $Context.root 'userdata/factorio-current.log'),$lines)
    return [pscustomobject]@{result=@{exit_code=0}}
  }
  try{
    Invoke-BrowserEngine @('--create',(Join-Path $run 'test.zip'))
    Invoke-BrowserEngine @('--benchmark-graphics',(Join-Path $run 'test.zip'),'--benchmark-ticks','1')
    $DlcIconCase='ImportedOptIn';$iconCase=Get-MIRBrowserIconCase $DlcIconCase
    Invoke-BrowserEngine @('--benchmark-graphics',(Join-Path $run 'test.zip'),'--benchmark-ticks','1')
    Assert-LibraryTest ($iconObservations.Count-eq1-and$iconObservations[0].graphics-and$iconObservations[0].observation.case-ceq$DlcIconCase) 'browser binds native icon observation to graphical actor'
    foreach($browserIconMarker in @('absent','duplicate','wrong-case')){
      Assert-LibraryRefusal {Invoke-BrowserEngine @('--create',(Join-Path $run 'test.zip'))} 'mir-browser-icon-observation'
    }
    $iconCase=$null
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
  $SourceVersion='4.2.2';$expectedIdentity=@{distribution_version='4.2.21002'}
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
      Assert-LibraryTest ($record.source_version-ceq'4.2.2'-and$record.distribution_version-ceq'4.2.21002') 'browser failure retains the selected maintenance identity'
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
