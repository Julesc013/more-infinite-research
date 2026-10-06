# MIR4-CANONICAL-EXECUTABLE-TEST
param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$FactorioBin='',
 [string]$CandidateZip='',
 [ValidateSet('2.0','2.1')][string]$Target='2.1',
 [switch]$Graphics,
 [string]$OutputRoot='build/p/browser',
 [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB=0,
 [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxWorktrees 8 -MaxBranches 32 | Out-Host
# No engine lookup, package, stage or version query precedes admission.
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
Assert-MIR441CleanTrackedSource -RepoRoot $repo
function Resolve-BrowserEnginePath([ValidateSet('2.0','2.1')][string]$Line,[string]$Requested) {
 $expected=if($Line -ceq '2.0'){'D:\Programs\Factorio\2.0\bin\x64\factorio.exe'}else{'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'}
 $selected=if([string]::IsNullOrWhiteSpace($Requested)){$expected}else{[IO.Path]::GetFullPath($Requested)}
 if(-not $selected.Equals($expected,[StringComparison]::OrdinalIgnoreCase)){throw '[mir-browser-engine-location] Select the target-authorized local engine.'}
 return $selected
}
$engine=(Resolve-Path -LiteralPath (Resolve-BrowserEnginePath -Line $Target -Requested $FactorioBin)).Path
$run=$resources.root
$lease=$null
$candidate=''
$targetKey=if($Target -ceq '2.0'){'f200'}else{'f210'}
$expectedIdentity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $targetKey.Substring(1) -SourceMinor 2 -SourcePatch 1
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
  throw '[mir-browser-candidate-identity] Candidate filename, root and metadata must encode source 4.2.1 for the selected target.'
 }
 foreach($name in @('research_browser.lua','research_browser_core.lua','research_browser_factorio_catalogue.lua','research_browser_mir_provider.lua','research_browser_actions.lua')) {
  $entry=@($archive.Entries | Where-Object FullName -CEQ "$packageRoot/prototypes/mir/runtime/$name")
  if($entry.Count -ne 1) { throw "Candidate must contain exactly one $name." }
  if($entry[0].Length -ne (Get-Item -LiteralPath (Join-Path $repo "source/prototypes/mir/runtime/$name")).Length){throw "Candidate $name differs from the controlled source under test."}
  $stream=$entry[0].Open()
  try { $moduleHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) } finally { $stream.Dispose() }
  if($moduleHash -cne (Get-FileHash (Join-Path $repo "source/prototypes/mir/runtime/$name")).Hash) { throw "Candidate $name differs from the controlled source under test." }
 }
 return [pscustomobject]@{info=$info;sha256=(Get-FileHash -LiteralPath $candidate).Hash}
} finally { $archive.Dispose() }
}
New-Item -ItemType Directory -Path $run | Out-Null
try {
$sourceCommit=(& git -C $repo rev-parse HEAD).Trim()
$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
$engineSha256=(Get-FileHash -LiteralPath $engine).Hash
if(-not [string]::IsNullOrWhiteSpace($CandidateZip)) {
 $candidateInput=if([IO.Path]::IsPathRooted($CandidateZip)){$CandidateZip}else{Join-Path $repo $CandidateZip}
 $candidate=(Resolve-Path -LiteralPath $candidateInput).Path
 $validatedCandidate=Test-BrowserCandidate -Candidate $candidate -Line $Target -Identity $expectedIdentity -Repository $repo
}
$versionActor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -Arguments @('--version') -TimeoutSeconds 10
$engineVersionText=Get-Content -LiteralPath $versionActor.stdout -Raw
if($engineVersionText -notmatch '(?m)^Version:\s*(?<version>[0-9]+\.[0-9]+\.[0-9]+)') { throw 'Browser test cannot identify the selected engine version.' }
$selectedEngineVersion=[string]$Matches.version
if(-not $selectedEngineVersion.StartsWith($Target + '.', [StringComparison]::Ordinal)) {
 throw "Browser engine target mismatch: requested $Target, selected engine is $selectedEngineVersion."
}
if([string]::IsNullOrWhiteSpace($CandidateZip)) {
 $package=New-MIRNativeProbeTargetPackage -Context $resources -RepoRoot $repo -Target $targetKey -CandidatePrefix BROWSER
 $candidate=[string]$package.archive_path
 $validatedCandidate=Test-BrowserCandidate -Candidate $candidate -Line $Target -Identity $expectedIdentity -Repository $repo
}
$fixture=Join-Path $run 'mods/mir-browser-test_1.0.0'
New-Item -ItemType Directory -Force $fixture | Out-Null
$packageInput=[ordered]@{source_path=$candidate;file_name=[IO.Path]::GetFileName($candidate);expected_sha256=$validatedCandidate.sha256;role='mir-candidate';identity=@{target=$targetKey;source_version='4.2.1';distribution_version=[string]$expectedIdentity.distribution_version};provenance=@{kind='exact-source-checked-browser-candidate'};immutable=$true}
$lease=New-MIRImmutableInputLease -RunRoot $run -StageDirectory (Join-Path $run 'mods') -Inputs @($packageInput) -RequireHardLinks
Add-MIRNativeProbeImmutableLease -Context $resources -Lease $lease
@{name='mir-browser-test';version='1.0.0';title='MIR browser acceptance';author='MIR';factorio_version=$Target;dependencies=@('base','more-infinite-research')} | ConvertTo-Json | Set-Content (Join-Path $fixture 'info.json')
Copy-Item -LiteralPath (Join-Path $repo 'tests/runtime/browser_fixture_data.lua') -Destination (Join-Path $fixture 'data.lua')
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
[void]$lua.AppendLine('local check_browser_handler_regressions=(function()')
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/research_browser_handler_regressions.lua')))
[void]$lua.AppendLine('end)()')
[void]$lua.AppendLine('local check_browser_discovery_regressions=(function()')
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/research_browser_discovery_regressions.lua')))
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
$coreChecks='check_omissions(check); check_browser_core_regressions(browser_core,check); check_browser_handler_regressions(browser_host_test_source,check,browser_catalogue_test_source); check_browser_discovery_regressions(browser_core,browser_catalogue,check,browser_host_test_source); check_browser_native_discovery_regressions(browser_core,browser_catalogue,browser_native_discovery_source,browser_native_discovery_data_source,check); check(not pcall(check_browser_core_regressions,browser_core_positive_default_mutant,function(ok,message) assert(ok,message) end),"negative control detects positive-only default cap validation"); local force=game.forces.player'
[void]$lua.AppendLine($browserTestText.Replace('local force=game.forces.player',$coreChecks))
[IO.File]::WriteAllText((Join-Path $fixture 'control.lua'),$lua.ToString(),[Text.UTF8Encoding]::new($false))
@{mods=@(@{name='base';enabled=$true},@{name='space-age';enabled=$false},@{name='elevated-rails';enabled=$false},@{name='quality';enabled=$false},@{name='recycler';enabled=$false},@{name='more-infinite-research';enabled=$true},@{name='mir-browser-test';enabled=$true})} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $run 'mods/mod-list.json')
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
# This fixture exercises research/GUI state, not the player's blueprint library.
# Keep Steam from copying that library into each isolated acceptance directory.
"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($run.Replace('\','/'))/userdata`n[other]`ndisable-blueprint-storage=true`nenable-blueprint-storage-cloud-sync=false`n[graphics]`nfull-screen=false`ncache-sprite-atlas=false`n" | Set-Content (Join-Path $run 'config.ini')
$save=Join-Path $run 'probe.zip'
function Invoke-BrowserEngine([string[]]$Arguments) {
 $graphicsArguments=if($Arguments -contains '--benchmark-graphics') { @('--force-graphics-preset','low','--video-memory-usage','low','--single-thread-loading') } else { @() }
 $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $engine -TimeoutSeconds 120 `
  -Arguments (@('--config',(Join-Path $run 'config.ini'),'--mod-directory',(Join-Path $run 'mods'))+$graphicsArguments+$Arguments)
}
Invoke-BrowserEngine @('--create',$save)
if($Graphics) { Invoke-BrowserEngine @('--benchmark-graphics',$save,'--benchmark-ticks','720','--disable-audio','--window-size','1024x768') }
else { Invoke-BrowserEngine @('--benchmark',$save,'--benchmark-ticks','3','--benchmark-runs','1') }
$resultPath=Join-Path $run 'userdata/script-output/browser-test.json'
if(-not (Test-Path $resultPath)) { throw "No browser acceptance result: $run" }
$result=Get-Content -Raw $resultPath | ConvertFrom-Json
if($Graphics -and $result.native_players -lt 1) { throw "Graphics test did not exercise a native player: $run" }
if($Graphics -and ($result.native_discovery.status -cne 'passed-native-connected-player-translations-and-GUI' -or $result.native_discovery.native_players -lt 1)) { throw "Graphics test did not complete native localized discovery: $run" }
if($result.status -ne 'passed') { throw "Browser acceptance failed: $resultPath" }
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
Assert-MIR441CleanTrackedSource -RepoRoot $repo
if((Get-FileHash -LiteralPath $engine).Hash -cne $engineSha256 -or
   (& git -C $repo rev-parse HEAD).Trim() -cne $sourceCommit){throw '[mir-browser-input-drift] Engine or source changed during the native run.'}
$result | Add-Member source_commit $sourceCommit
$result | Add-Member source_tree $sourceTree
$result | Add-Member distribution_version $expectedIdentity.distribution_version
$result | Add-Member resource_policy @{declared_peak_memory_mib=$ExpectedPeakMemoryMiB;max_new_output_mib=$MaxNewOutputMiB;memory_enforcement='sampled-watchdog-not-hard-cap'}
$result | Add-Member resource_runs $resources.runs.ToArray()
$result | Add-Member factorio_driver_sha256 (Get-FileHash -LiteralPath (Join-Path $run 'factorio-driver.ps1')).Hash
$result | Add-Member resource_adapter_sha256 (Get-FileHash -LiteralPath (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')).Hash
$terminal=Complete-MIRImmutableInputLease -Lease $lease -Outcome passed
$lease=$null
$result | Add-Member input_lease $terminal
Write-MIRNativeProbeResult -Context $resources -Record $result
$result | ConvertTo-Json -Depth 30
Write-Output "Evidence: $run"
} catch {
 $failure=$_
 try { Write-MIRNativeProbeResult -Context $resources -Record ([ordered]@{status='failed';target=$Target;candidate=$candidate;error=$failure.Exception.Message;resource_runs=$resources.runs.ToArray()}) }
 catch { Write-Warning "Browser failure receipt exceeded its remaining budget; retained ledgers are in $run." }
 throw $failure
} finally {
 if($null -ne $lease -and -not $lease.closed){$null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed}
}
