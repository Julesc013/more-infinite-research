# MIR4-CANONICAL-EXECUTABLE-TEST
param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$FactorioBin='',
 [string]$CandidateZip='',
 [string]$LibraryDirectory='',
 [switch]$PrepareInputsOnly,
 [ValidateSet('2.0','2.1')][string]$Target='2.1',
 [ValidateSet('4.2.1','4.2.2')][string]$SourceVersion='4.2.1',
 [switch]$Graphics,
 [ValidateSet('low','very-low')][string]$GraphicsPreset='low',
 [ValidateSet('None','Defaults','RawOptIn','ImportedOptIn','RawOptInImportedOff')][string]$DlcIconCase='None',
 [string]$OutputRoot='build/p/browser',
 [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB=0,
 [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/validation/SettingsOverrides.ps1')
if(-not $PrepareInputsOnly -and ($LibraryDirectory -eq '' -or $FactorioBin -eq '' -or $CandidateZip -eq '')) {
 throw '[mir-browser-direct-inputs-required] Supply the engine, current candidate and flat archive library; populated profile staging is retired.'
}
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxWorktrees 8 -MaxBranches 32 | Out-Host
# No engine lookup, package, stage or version query precedes admission.
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
Assert-MIR441CleanTrackedSource -RepoRoot $repo
function Resolve-BrowserEnginePath([ValidateSet('2.0','2.1')][string]$Line,[string]$Requested) {
 if([string]::IsNullOrWhiteSpace($Requested)){throw '[mir-browser-engine-location] Supply an explicit engine location.'}
 $selected=(Resolve-Path -LiteralPath $Requested).Path
 $engineRoot=Split-Path (Split-Path (Split-Path $selected -Parent) -Parent) -Parent
 $base=Get-Content -LiteralPath (Join-Path $engineRoot 'data/base/info.json') -Raw|ConvertFrom-Json
 if($base.name -cne 'base' -or [string]$base.version -cnotmatch ('^'+[regex]::Escape($Line)+'\.[0-9]+$')){throw '[mir-browser-engine-target] Selected engine data does not match the target.'}
 return $selected
}
$run=$resources.root
$activation=$null
$candidate=''
$targetKey=if($Target -ceq '2.0'){'f200'}else{'f210'}
$expectedIdentity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $targetKey.Substring(1) -SourceMinor 2 -SourcePatch ([int]$SourceVersion.Split('.')[2])
function Get-MIRBrowserIconCase([string]$Case) {
 switch -CaseSensitive ($Case) {
  'None' { return $null }
  'Defaults' { return @{case=$Case;raw=$false;imported=$null} }
  'RawOptIn' { return @{case=$Case;raw=$true;imported=$null} }
  'ImportedOptIn' { return @{case=$Case;raw=$false;imported=$true} }
  'RawOptInImportedOff' { return @{case=$Case;raw=$true;imported=$false} }
  default { throw '[mir-browser-icon-case]' }
 }
}
$iconCase=Get-MIRBrowserIconCase $DlcIconCase
$iconObservations=[Collections.Generic.List[object]]::new()
function Initialize-MIRBrowserIconFixture([string]$Fixture,[string]$Repository,[string]$Case) {
 $selected=Get-MIRBrowserIconCase $Case
 if($null -eq $selected){return}
 $rawLiteral=ConvertTo-MIRLuaLiteral $selected.raw
 $importLiteral=if($null -eq $selected.imported){'nil'}else{ConvertTo-MIRLuaLiteral $selected.imported}
 $settingsText="local option=data.raw['bool-setting']['mir-use-installed-space-age-icons']`nassert(option.default_value==false,'Production icon default must remain off')`noption.default_value=$rawLiteral`n"
 if($null -ne $selected.imported){
  $profileJson=[ordered]@{schema=1;kind='mir-settings-profile';settings=[ordered]@{'mir-use-installed-space-age-icons'=$selected.imported}}|ConvertTo-Json -Depth 4 -Compress
  $settingsText+="data.raw['string-setting']['mir-settings-profile-import'].default_value='MIRSET1:'..helpers.encode_string("+(ConvertTo-MIRLuaLiteral $profileJson)+")`n"
 }
 [IO.File]::WriteAllText((Join-Path $Fixture 'settings-final-fixes.lua'),$settingsText,[Text.UTF8Encoding]::new($false))
 $iconChecks=[IO.File]::ReadAllText((Join-Path $Repository 'tests/runtime/browser_fixture_icons.lua'))
 [IO.File]::WriteAllText((Join-Path $Fixture 'data-final-fixes.lua'),("local check=(function()`n"+$iconChecks+"`nend)()`ncheck{case="+(ConvertTo-MIRLuaLiteral $Case)+",raw=$rawLiteral,imported=$importLiteral}`n"),[Text.UTF8Encoding]::new($false))
}
function Test-BrowserCandidate([string]$Candidate,[string]$Line,$Identity,[string]$Repository) {
$candidate=$Candidate;$Target=$Line;$expectedIdentity=$Identity;$repo=$Repository
$archive=[IO.Compression.ZipFile]::OpenRead($candidate)
try {
 $infoEntries=@($archive.Entries | Where-Object FullName -Like '*/info.json')
 if($infoEntries.Count -ne 1) { throw 'Browser candidate requires one mod identity.' }
 if($infoEntries[0].Length -gt 64KB){throw '[mir-browser-candidate-info-budget]'}
 $infoReader=[IO.StreamReader]::new($infoEntries[0].Open())
 try { $info=$infoReader.ReadToEnd() | ConvertFrom-Json } finally { $infoReader.Dispose() }
 if([string]$info.name -cne 'more-infinite-research' -or [string]$info.factorio_version -cne $Target) {
  throw "Browser candidate target mismatch: requested $Target, archive declares $($info.factorio_version)."
 }
 $packageRoot='more-infinite-research_'+$expectedIdentity.distribution_version
 if([string]$info.version -cne $expectedIdentity.distribution_version -or
    [IO.Path]::GetFileName($candidate) -cne $expectedIdentity.package_name -or
    $infoEntries[0].FullName -cne ($packageRoot+'/info.json') -or
    @($archive.Entries | Where-Object {
      -not $_.FullName.StartsWith($packageRoot+'/',[StringComparison]::Ordinal) -or
      $_.FullName -cmatch '[\\\x00]' -or
      @($_.FullName.TrimEnd('/').Split('/') | Where-Object {$_ -in @('','.','..')}).Count -gt 0
    }).Count -ne 0) {
  throw '[mir-browser-candidate-identity] Candidate filename, root and metadata must encode the selected source version and target.'
 }
 $bindings=@{}
 foreach($name in @('research_browser.lua','research_browser_core.lua','research_browser_factorio_catalogue.lua','research_browser_mir_provider.lua','research_browser_actions.lua')) {
  $bindings["prototypes/mir/runtime/$name"]="source/prototypes/mir/runtime/$name"
 }
 foreach($stage in @('data','control')){$bindings["prototypes/mir/stage/$stage.lua"]="source/prototypes/mir/stage/$stage.lua"}
 $adapter=if($Target -ceq '2.1'){'f210'}else{'f200'}
 $bindings['prototypes/mir/runtime/scripted_techs.lua']="source/adapters/$adapter/prototypes/mir/runtime/scripted_techs.lua"
 $bindings['prototypes/mir/platform/factorio/target_profiles.lua']="source/adapters/$adapter/prototypes/mir/platform/factorio/target_profiles.lua"
 $bindings['prototypes/mir/platform/factorio/browser_host.lua']='source/prototypes/mir/platform/factorio/browser_host.lua'
 foreach($name in $bindings.Keys) {
  $sourcePath=Join-Path $repo $bindings[$name]
  $entry=@($archive.Entries | Where-Object FullName -CEQ "$packageRoot/$name")
  if($entry.Count -ne 1) { throw "Candidate must contain exactly one $name." }
  if($entry[0].Length -ne (Get-Item -LiteralPath $sourcePath).Length){throw "Candidate $name differs from the controlled source under test."}
  $stream=$entry[0].Open()
  try { $moduleHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) } finally { $stream.Dispose() }
  if($moduleHash -cne (Get-FileHash -LiteralPath $sourcePath).Hash) { throw "Candidate $name differs from the controlled source under test." }
 }
 return [pscustomobject]@{info=$info;sha256=(Get-FileHash -LiteralPath $candidate).Hash}
} finally { $archive.Dispose() }
}
function Get-MIRBrowserLibrarySelection([string]$Library,[string]$EngineVersion,[string]$Candidate,[string]$Version,[string]$ExpectedSha256,[string]$FixtureDirectory) {
 Assert-MIRLibraryPath $Library
 $name=[IO.Path]::GetFileName($Candidate);$installed=Join-Path $Library $name
 if(-not(Test-Path -LiteralPath $installed -PathType Leaf)){throw "[mir-browser-library-input-missing] $name"}
 Assert-MIRLibraryPath $installed
 if((Get-MIRImmutableInputSha256 $installed) -cne $ExpectedSha256){throw '[mir-browser-library-input-hash]'}
 $fixtureInfo=Get-Content -LiteralPath (Join-Path $FixtureDirectory 'info.json') -Raw|ConvertFrom-Json
 $fixtureName=$fixtureInfo.name+'_'+$fixtureInfo.version+'.zip';$fixtureArchive=Join-Path $Library $fixtureName
 Assert-MIRLibraryFixtureArchive -Archive $fixtureArchive -SourceDirectory $FixtureDirectory
 return [pscustomobject]@{
  mod_list=@{mods=@(@{name='base';version=$EngineVersion;enabled=$true},@{name='more-infinite-research';version=$Version;enabled=$true},@{name=$fixtureInfo.name;version=$fixtureInfo.version;enabled=$true})}
  archive_hashes=@{$name=$ExpectedSha256;$fixtureName=(Get-MIRImmutableInputSha256 $fixtureArchive)}
 }
}
New-Item -ItemType Directory -Path $run | Out-Null
try {
$sourceCommit=(& git -C $repo rev-parse HEAD).Trim()
$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$fixture=Join-Path $run 'fixture-source/mir-browser-test_1.0.0'
New-Item -ItemType Directory -Force $fixture | Out-Null
[ordered]@{name='mir-browser-test';version='1.0.0';title='MIR browser acceptance';author='MIR';factorio_version=$Target;dependencies=@('base','more-infinite-research')} | ConvertTo-Json | Set-Content (Join-Path $fixture 'info.json')
Copy-Item -LiteralPath (Join-Path $repo 'tests/runtime/browser_fixture_data.lua') -Destination (Join-Path $fixture 'data.lua')
Initialize-MIRBrowserIconFixture -Fixture $fixture -Repository $repo -Case $DlcIconCase
$lua=[Text.StringBuilder]::new()
foreach($module in @(@{name='browser_core';path='research_browser_core.lua'},@{name='browser_catalogue';path='research_browser_factorio_catalogue.lua'},@{name='browser_actions';path='research_browser_actions.lua'})) {
 [void]$lua.AppendLine("local $($module.name)=(function()")
 [void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo "source/prototypes/mir/runtime/$($module.path)")))
 [void]$lua.AppendLine('end)()')
}
[void]$lua.AppendLine('local browser_omission_prototypes={mod_data={},mod_setting={}}')
[void]$lua.AppendLine('local browser_omission_controller_bindings={}')
[void]$lua.AppendLine('local browser_omission_controller={runtime_settings_bindings=function() return browser_omission_controller_bindings end}')
[void]$lua.AppendLine('local browser_omission_runtime_settings={startup={}}')
[void]$lua.AppendLine('local browser_omission_registered_settings={["ips-max-level-bridge"]={name="ips-max-level-bridge",type="int-setting"}}')
[void]$lua.AppendLine('local browser_omission_fingerprint=(function()')
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo 'source/prototypes/mir/core/fingerprint.lua')))
[void]$lua.AppendLine('end)()')
[void]$lua.AppendLine(@'
local browser_omission_provider=(function()
  local prototypes=browser_omission_prototypes
  local settings=browser_omission_runtime_settings
  local require=function(name)
    if name=="prototypes.mir.core.fingerprint" then return browser_omission_fingerprint
    elseif name=="prototypes.mir.platform.factorio.browser_host" then return {
      prototype_collections=function() return browser_omission_prototypes end
    }
    elseif name=="prototypes.mir.runtime.maximum_level_control" then return browser_omission_controller
    elseif name=="prototypes.mir.settings.catalog" then return {
      spec=function(setting_name) return browser_omission_registered_settings[setting_name] end,
      validate_value=function(setting_name,value) return browser_omission_registered_settings[setting_name]~=nil
        and type(value)=="number" and value==value
        and value~=math.huge and value~=-math.huge and value>=0 and value==math.floor(value) end
    }
    elseif name=="prototypes.mir.runtime.startup_settings" then return {
      get=function(setting_name)
        local entry=browser_omission_runtime_settings.startup[setting_name]
        return entry and entry.value
      end
    }
    elseif name=="prototypes.mir.settings.profile_codec" then return {
      import_setting_name="mir-profile-import",decode=function() return nil end
    }
    end
    return {}
  end
'@)
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo 'source/prototypes/mir/runtime/research_browser_mir_provider.lua')))
[void]$lua.AppendLine('end)()')
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/research_browser_omissions.lua')))
[void]$lua.AppendLine('local check_browser_core_regressions=(function()')
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/research_browser_core_regressions.lua')))
[void]$lua.AppendLine('end)()')
$browserTestText=[IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/research_browser.lua'))
[void]$lua.AppendLine('local check_browser_hidden_regressions=(function()')
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/research_browser_hidden_regressions.lua')))
[void]$lua.AppendLine('end)()')
[void]$lua.AppendLine('check_browser_hidden_regressions(browser_catalogue,browser_actions,function(ok,message) assert(ok,message) end)')
[void]$lua.AppendLine('local check_browser_native_discovery=(function()')
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/research_browser_native_discovery.lua')))
[void]$lua.AppendLine('end)()')
$nativeDiscoverySource=[IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/research_browser_native_discovery.lua'))
$nativeDiscoveryDataSource=[IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/browser_fixture_data.lua'))
if($nativeDiscoverySource.Contains(']====]') -or $nativeDiscoveryDataSource.Contains(']====]')) { throw 'Native discovery fixture source collides with its Lua delimiter.' }
[void]$lua.AppendLine('local browser_native_discovery_source=[====['+$nativeDiscoverySource+']====]')
[void]$lua.AppendLine('local browser_native_discovery_data_source=[====['+$nativeDiscoveryDataSource+']====]')
[void]$lua.AppendLine('local check_browser_native_discovery_regressions=(function()')
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/research_browser_native_discovery_regressions.lua')))
[void]$lua.AppendLine('end)()')
$hostTestSource=[IO.File]::ReadAllText((Join-Path $repo 'source/prototypes/mir/runtime/research_browser.lua')).Replace("`r`n","`n")
if($hostTestSource.Contains(']====]')) { throw 'Host fixture source collides with its Lua string delimiter.' }
[void]$lua.AppendLine('local browser_host_test_source=[====[')
[void]$lua.AppendLine($hostTestSource)
[void]$lua.AppendLine(']====]')
[void]$lua.AppendLine('local browser_capability_sources={coordinators={},host_adapters={}}')
foreach($entry in @(
 @{key='data_stage';path='source/prototypes/mir/stage/data.lua'},
 @{key='control_stage';path='source/prototypes/mir/stage/control.lua'},
 @{key='coordinators.f210';path='source/adapters/f210/prototypes/mir/runtime/scripted_techs.lua'},
 @{key='coordinators.f200';path='source/adapters/f200/prototypes/mir/runtime/scripted_techs.lua'},
 @{key='host_adapters.modern';path='source/prototypes/mir/platform/factorio/browser_host.lua'},
 @{key='host_adapters.game';path='source/adapters/runtime-capabilities/game-browser-host.lua'})) {
 $text=[IO.File]::ReadAllText((Join-Path $repo $entry.path)).Replace("`r`n","`n")
 if($text.Contains(']====]')){throw 'Library capability source collides with its Lua delimiter.'}
 [void]$lua.AppendLine('browser_capability_sources.'+$entry.key+'=[====['+$text+']====]')
}
[void]$lua.AppendLine('local check_browser_handler_regressions=(function()')
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/research_browser_handler_regressions.lua')))
[void]$lua.AppendLine('end)()')
[void]$lua.AppendLine('local check_browser_discovery_regressions=(function()')
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/research_browser_discovery_regressions.lua')))
[void]$lua.AppendLine('end)()')
[void]$lua.AppendLine('local check_browser_production_regressions=(function()')
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/research_browser_production_regressions.lua')))
[void]$lua.AppendLine('end)()')
if(([regex]::Matches($browserTestText,[regex]::Escape('local force=game.forces.player'))).Count -ne 1) { throw 'Browser omission checks require one unambiguous controlled force entry.' }
$catalogueTestSource=[IO.File]::ReadAllText((Join-Path $repo 'source/prototypes/mir/runtime/research_browser_factorio_catalogue.lua')).Replace("`r`n","`n")
if($catalogueTestSource.Contains(']====]')) { throw 'Catalogue fixture source collides with its Lua string delimiter.' }
[void]$lua.AppendLine('local browser_catalogue_test_source=[====[')
[void]$lua.AppendLine($catalogueTestSource)
[void]$lua.AppendLine(']====]')
$coreTestSource=[IO.File]::ReadAllText((Join-Path $repo 'source/prototypes/mir/runtime/research_browser_core.lua')).Replace("`r`n","`n")
$capAnchor="and finite_nonnegative_integer(value.default)`n    and finite_nonnegative_integer(value.raw_direct)`n    and finite_positive_integer(value.effective)"
if(([regex]::Matches($coreTestSource,[regex]::Escape($capAnchor))).Count -ne 1) { throw 'Finite-cap negative control lost its precise mutation anchor.' }
$capMutant=$coreTestSource.Replace($capAnchor,$capAnchor.Replace('finite_nonnegative_integer','finite_positive_integer'))
[void]$lua.AppendLine('local browser_core_positive_default_mutant=(function()')
[void]$lua.AppendLine($capMutant)
[void]$lua.AppendLine('end)()')
$coreChecks='check_omissions(check); check_browser_core_regressions(browser_core,check); check_browser_handler_regressions(browser_host_test_source,check,browser_catalogue_test_source,browser_capability_sources); check_browser_discovery_regressions(browser_core,browser_catalogue,check,browser_host_test_source); check_browser_production_regressions(browser_core,browser_catalogue,browser_host_test_source,check,browser_capability_sources.host_adapters.modern); check_browser_production_regressions(browser_core,browser_catalogue,browser_host_test_source,check,browser_capability_sources.host_adapters.game,true); check_browser_native_discovery_regressions(browser_core,browser_catalogue,browser_native_discovery_source,browser_native_discovery_data_source,check); check(not pcall(check_browser_core_regressions,browser_core_positive_default_mutant,function(ok,message) assert(ok,message) end),"negative control detects positive-only default cap validation"); local force=game.forces.player'
[void]$lua.AppendLine($browserTestText.Replace('local force=game.forces.player',$coreChecks))
[IO.File]::WriteAllText((Join-Path $fixture 'control.lua'),$lua.ToString(),[Text.UTF8Encoding]::new($false))
if($PrepareInputsOnly) {
 $preparedRoot=Join-Path $run 'prepared-fixtures';[IO.Directory]::CreateDirectory($preparedRoot)|Out-Null
 $archive=Publish-MIRModDirectoryArchive -Source $fixture -Name 'mir-browser-test' -Version '1.0.0' -ModsDir $preparedRoot
 Write-MIRNativeProbeResult -Context $resources -Record ([ordered]@{kind='MIRBrowserPreparedInputsV1';status='prepared-not-native-tested';target=$Target;source_version=$SourceVersion;distribution_version=$expectedIdentity.distribution_version;source_commit=$sourceCommit;dlc_icon_case=$DlcIconCase;fixture=@{path=$archive;sha256=(Get-MIRImmutableInputSha256 $archive)};factorio_processes=0})
 Write-Output "Browser fixture prepared without native execution or library writes: $run"
 return
}
$engine=Resolve-BrowserEnginePath -Line $Target -Requested $FactorioBin
$engineSha256=(Get-FileHash -LiteralPath $engine).Hash
$candidateInput=if([IO.Path]::IsPathRooted($CandidateZip)){$CandidateZip}else{Join-Path $repo $CandidateZip}
$candidate=(Resolve-Path -LiteralPath $candidateInput).Path
$validatedCandidate=Test-BrowserCandidate -Candidate $candidate -Line $Target -Identity $expectedIdentity -Repository $repo
$versionActor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments @('--version') -TimeoutSeconds 10
$engineVersionText=Get-Content -LiteralPath $versionActor.stdout -Raw
if($engineVersionText -notmatch '(?m)^Version:\s*(?<version>[0-9]+\.[0-9]+\.[0-9]+)') { throw 'Browser test cannot identify the selected engine version.' }
$selectedEngineVersion=[string]$Matches.version
if(-not $selectedEngineVersion.StartsWith($Target + '.', [StringComparison]::Ordinal)) {
 throw "Browser engine target mismatch: requested $Target, selected engine is $selectedEngineVersion."
}
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
$library=(Resolve-Path -LiteralPath $LibraryDirectory).Path
$selection=Get-MIRBrowserLibrarySelection -Library $library -EngineVersion $selectedEngineVersion -Candidate $candidate -Version $expectedIdentity.distribution_version -ExpectedSha256 $validatedCandidate.sha256 -FixtureDirectory $fixture
$profile=Join-Path $run 'selection.json';$selection.mod_list|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $profile -Encoding utf8
$activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory (Join-Path $engineRoot 'data') -ProfilePath $profile -ArchiveHashes $selection.archive_hashes -SettingsMode Defaults
Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
# This fixture exercises research/GUI state, not the player's blueprint library.
# Keep Steam from copying that library into each isolated acceptance directory.
"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($run.Replace('\','/'))/userdata`n[other]`nenable-new-mods=false`ncheck-updates=false`ndisable-blueprint-storage=true`nenable-blueprint-storage-cloud-sync=false`n[graphics]`nfull-screen=false`ncache-sprite-atlas=false`n" | Set-Content (Join-Path $run 'config.ini')
$save=Join-Path $run 'probe.zip'
function Invoke-BrowserEngine([string[]]$Arguments) {
 $graphicsArguments=if($Arguments -contains '--benchmark-graphics') { @('--force-graphics-preset',$GraphicsPreset,'--video-memory-usage','low','--single-thread-loading') } else { @() }
 $nativeArguments=@('--config',(Join-Path $run 'config.ini'),'--mod-directory',$library)+$graphicsArguments+$Arguments
 Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $nativeArguments
 $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -TimeoutSeconds 120 `
  -Arguments $nativeArguments
 $null=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath (Join-Path $run 'userdata/factorio-current.log') -LatestInvocation
 if($null -ne $iconCase){
  $text=Get-Content -LiteralPath (Join-Path $run 'userdata/factorio-current.log') -Raw
  $markers=@([regex]::Matches($text,'\[mir-browser-icons\] PASS (?<json>\{[^\r\n]+\})'))
  if($markers.Count-ne1){throw '[mir-browser-icon-observation] Expected one current native artwork observation.'}
  $observation=$markers[0].Groups['json'].Value|ConvertFrom-Json
  if($observation.case-cne$DlcIconCase-or$observation.inactive_provider_references-ne0){throw '[mir-browser-icon-observation] Native case differs.'}
  $iconObservations.Add([ordered]@{process_index=$resources.process_index;graphics=($Arguments-contains'--benchmark-graphics');observation=$observation})
 }
}
Invoke-BrowserEngine @('--create',$save)
if($Graphics) { Invoke-BrowserEngine @('--benchmark-graphics',$save,'--benchmark-ticks','720','--disable-audio','--window-size','1024x768') }
else { Invoke-BrowserEngine @('--benchmark',$save,'--benchmark-ticks','3','--benchmark-runs','1') }
$resultPath=Join-Path $run 'userdata/script-output/browser-test.json'
if(-not (Test-Path $resultPath)) { throw "No browser acceptance result: $run" }
$result=Get-Content -Raw $resultPath | ConvertFrom-Json
if($result.status -ne 'passed') { throw "Browser acceptance did not finish: status=$($result.status); result=$resultPath; native log=$(Join-Path $run 'userdata/factorio-current.log')" }
if($Graphics -and $result.native_players -lt 1) { throw "Graphics test did not exercise a native player: $run" }
if($Graphics -and ($result.native_discovery.status -cne 'passed-native-connected-player-translations-and-GUI' -or $result.native_discovery.native_players -lt 1)) { throw "Graphics test did not complete native localized discovery: $run" }
if([string]$result.engine -cne $selectedEngineVersion) { throw 'Browser native result does not match the selected engine.' }
$result | Add-Member package_sha256 (Get-FileHash $candidate).Hash
$result | Add-Member engine_sha256 $engineSha256
$result | Add-Member core_sha256 (Get-FileHash (Join-Path $repo 'source/prototypes/mir/runtime/research_browser_core.lua')).Hash
$result | Add-Member host_sha256 (Get-FileHash (Join-Path $repo 'source/prototypes/mir/runtime/research_browser.lua')).Hash
$result | Add-Member provider_sha256 (Get-FileHash (Join-Path $repo 'source/prototypes/mir/runtime/research_browser_mir_provider.lua')).Hash
$result | Add-Member catalogue_adapter_sha256 (Get-FileHash (Join-Path $repo 'source/prototypes/mir/runtime/research_browser_factorio_catalogue.lua')).Hash
$result | Add-Member action_predicate_sha256 (Get-FileHash (Join-Path $repo 'source/prototypes/mir/runtime/research_browser_actions.lua')).Hash
$result | Add-Member harness_sha256 (Get-FileHash $PSCommandPath).Hash
$result | Add-Member fixture_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/browser_fixture_data.lua')).Hash
$result | Add-Member test_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/research_browser.lua')).Hash
$result | Add-Member omission_test_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/research_browser_omissions.lua')).Hash
$result | Add-Member core_regression_test_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/research_browser_core_regressions.lua')).Hash
$result | Add-Member discovery_regression_test_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/research_browser_discovery_regressions.lua')).Hash
$result | Add-Member production_regression_test_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/research_browser_production_regressions.lua')).Hash
$result | Add-Member native_discovery_test_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/research_browser_native_discovery.lua')).Hash
$result | Add-Member native_discovery_regression_test_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/research_browser_native_discovery_regressions.lua')).Hash
$result | Add-Member handler_regression_test_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/research_browser_handler_regressions.lua')).Hash
if($Graphics) {
 $saved=Join-Path $run 'userdata/saves/_autosave-mir-browser-acceptance.zip'
 if(-not (Test-Path $saved)) { throw "Native browser save capture missing: $saved" }
 Invoke-BrowserEngine @('--benchmark-graphics',$saved,'--benchmark-ticks','720','--disable-audio','--window-size','1024x768')
 $reloaded=Join-Path $run 'userdata/script-output/browser-reload.json'
 if(-not(Test-Path $reloaded)) { throw "Native browser reload result missing: $run" }
 $reload=Get-Content -Raw $reloaded | ConvertFrom-Json
 if($reload.status -ne 'passed') { throw 'Browser reload failed.' }
 if($reload.native_discovery.status -cne 'passed-native-connected-player-translations-and-GUI' -or $reload.native_discovery.native_players -lt 1) { throw 'Browser reload did not complete native localized discovery.' }
 $result | Add-Member reload $reload
 $result | Add-Member save_sha256 (Get-FileHash $saved).Hash
}
$result | Add-Member target $Target
$result | Add-Member graphics_preset $(if($Graphics){$GraphicsPreset}else{'not-used'})
$result | Add-Member dlc_icon_case $DlcIconCase
$result | Add-Member icon_observations $iconObservations.ToArray()
if($null -ne $iconCase){
 $settingsControl=Read-MIRLibraryControl (Join-Path $library 'mod-settings.dat')
 if(-not $settingsControl.exists){throw '[mir-browser-icon-settings-missing] Native settings were not saved.'}
 $settingsSnapshot=Join-Path $run 'observed-mod-settings.dat'
 [IO.File]::WriteAllBytes($settingsSnapshot,[Convert]::FromBase64String($settingsControl.bytes))
 $settingsHash=Get-MIRImmutableInputSha256 $settingsSnapshot
 if($settingsHash-cne$settingsControl.sha256){throw '[mir-browser-icon-settings-readback]'}
 $result|Add-Member icon_settings_snapshot @{path=$settingsSnapshot;sha256=$settingsHash;private_writable_copy=$true}
}
Assert-MIR441CleanTrackedSource -RepoRoot $repo
if((Get-FileHash -LiteralPath $engine).Hash -cne $engineSha256 -or
   (& git -C $repo rev-parse HEAD).Trim() -cne $sourceCommit){throw '[mir-browser-input-drift] Engine or source changed during the native run.'}
$result | Add-Member source_commit $sourceCommit
$result | Add-Member source_tree $sourceTree
$result | Add-Member source_version $SourceVersion
$result | Add-Member distribution_version $expectedIdentity.distribution_version
$result | Add-Member resource_policy @{declared_peak_memory_mib=$ExpectedPeakMemoryMiB;max_new_output_mib=$MaxNewOutputMiB;memory_enforcement='sampled-watchdog-not-hard-cap'}
$result | Add-Member resource_runs $resources.runs.ToArray()
$result | Add-Member factorio_driver_sha256 (Get-FileHash -LiteralPath (Join-Path $run 'factorio-driver.ps1')).Hash
$result | Add-Member resource_adapter_sha256 (Get-FileHash -LiteralPath (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')).Hash
$terminal=Complete-MIRLibraryActivation -Activation $activation
$activation=$null
$result | Add-Member library_activation $terminal
Write-MIRNativeProbeResult -Context $resources -Record $result
$result | ConvertTo-Json -Depth 30
Write-Output "Evidence: $run"
} catch {
 $failure=$_
 $cleanup=$null
 if($null -ne $activation -and -not $activation.closed){
  try{$cleanup=Complete-MIRLibraryActivation -Activation $activation;$activation=$null}
  catch{$cleanup=@{status='recovery-required';library=$activation.library;error=$_.Exception.Message}}
 }
 try { Write-MIRNativeProbeResult -Context $resources -Record ([ordered]@{status='failed';target=$Target;source_version=$SourceVersion;distribution_version=$expectedIdentity.distribution_version;candidate=$candidate;error=$failure.Exception.Message;library_activation=$cleanup;resource_runs=$resources.runs.ToArray()}) }
 catch { Write-Warning "Browser failure receipt exceeded its remaining budget; retained ledgers are in $run." }
 throw $failure
}
