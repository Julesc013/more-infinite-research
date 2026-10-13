# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$OutputRoot='build/tmp/researchability-planning',
  [ValidateRange(1,2048)][int]$ExpectedPeakMemoryMiB=512,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=64
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/compatibility/LibraryActivation.ps1')
. (Join-Path $repo 'tools/mir/application/release/F210QualificationPolicy.ps1')

# This controlled compiler fixture has its own process/output budget and uses
# one private, flat archive library. It must not extract a mod, copy a
# dependency, or replace a player's selected-library controls.
$context=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
$run=$context.root
$engineResolution=Get-MIR4F210EngineResolutionV2 -RepoRoot $repo -FactorioBin $FactorioBin
$engine=(Resolve-Path -LiteralPath ([string]$engineResolution.engine.path)).Path
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
$engineData=Join-Path $engineRoot 'data'
$fixtureSource=Join-Path $run 'fixture-source'
$library=Join-Path $run 'fixture-library'
$userdata=Join-Path $run 'userdata'
New-Item -ItemType Directory -Force -Path $fixtureSource,$library,$userdata|Out-Null

$modules=[ordered]@{
  'prototypes.mir.core.deepcopy'='source/prototypes/mir/core/deepcopy.lua'
  'prototypes.mir.core.fingerprint'='source/prototypes/mir/core/fingerprint.lua'
  'prototypes.mir.domain.compiler.execution_mode'='source/prototypes/mir/domain/compiler/execution_mode.lua'
  'prototypes.mir.pipeline.compiler_context'='source/prototypes/mir/pipeline/compiler_context.lua'
  'prototypes.mir.platform.factorio.prototype_lookup'='source/prototypes/mir/platform/factorio/prototype_lookup.lua'
  'prototypes.mir.platform.factorio.mods'='source/prototypes/mir/platform/factorio/mods.lua'
  'prototypes.mir.index.item_prototype_facts'='source/prototypes/mir/index/item_prototype_facts.lua'
  'prototypes.mir.report.compiler_telemetry'='source/prototypes/mir/report/compiler_telemetry.lua'
  'prototypes.mir.platform.factorio.data_raw'='source/prototypes/mir/platform/factorio/data_raw.lua'
  'prototypes.mir.platform.factorio.target_profiles'='source/adapters/f210/prototypes/mir/platform/factorio/target_profiles.lua'
  'prototypes.mir.domain.facts.recipe_semantics'='source/prototypes/mir/domain/facts/recipe_semantics.lua'
  'prototypes.mir.index.recipe_facts'='source/prototypes/mir/index/recipe_facts.lua'
  'prototypes.mir.graph.snapshot'='source/prototypes/mir/graph/snapshot.lua'
  'prototypes.mir.graph.scc'='source/prototypes/mir/graph/scc.lua'
  'prototypes.mir.graph.condensation'='source/prototypes/mir/graph/condensation.lua'
  'prototypes.mir.graph.researchability_index'='source/prototypes/mir/graph/researchability_index.lua'
  'prototypes.mir.index.recipe_unlocks'='source/prototypes/mir/index/recipe_unlocks.lua'
  'prototypes.mir.capabilities.science_integration.pack_registry'='source/prototypes/mir/capabilities/science_integration/pack_registry.lua'
  'prototypes.mir.capabilities.science_integration.lab_compatibility'='source/prototypes/mir/capabilities/science_integration/lab_compatibility.lua'
  'prototypes.mir.capabilities.science_integration.recipe_unlock_facts'='source/prototypes/mir/capabilities/science_integration/recipe_unlock_facts.lua'
  'prototypes.mir.capabilities.science_integration.recipe_route_feasibility'='source/prototypes/mir/capabilities/science_integration/recipe_route_feasibility.lua'
  'prototypes.mir.capabilities.science_integration.production_route_policy'='source/prototypes/mir/capabilities/science_integration/production_route_policy.lua'
  'prototypes.mir.capabilities.science_integration.technology_researchability'='source/prototypes/mir/capabilities/science_integration/technology_researchability.lua'
  'prototypes.mir.capabilities.science_integration.pack_production_reachability'='source/prototypes/mir/capabilities/science_integration/pack_production_reachability.lua'
  'prototypes.mir.capabilities.science_integration.science_selection_policy'='source/prototypes/mir/capabilities/science_integration/science_selection_policy.lua'
  'prototypes.mir.capabilities.science_integration.science_packs'='source/prototypes/mir/capabilities/science_integration/science_packs.lua'
  'prototypes.mir.capabilities.science_integration.science_selector'='source/prototypes/mir/capabilities/science_integration/science_selector.lua'
  'prototypes.mir.platform.factorio.target_line'='source/prototypes/mir/platform/factorio/target_line.lua'
  'prototypes.streams.direct-effects'='source/prototypes/streams/direct-effects.lua'
  'prototypes.mir.presentation.icon_builder'='source/prototypes/mir/presentation/icon_builder.lua'
  'fixtures.f200.base_continuations.qualify'='source/adapters/f200/prototypes/mir/planner/base_continuations/qualify.lua'
}
$lua=[Text.StringBuilder]::new()
[void]$lua.AppendLine('local host_log=log; local loaders={}; local env=setmetatable({package={loaded={}}},{__index=_G}); env._G=env; env.print=function(s) host_log(s) end')
[void]$lua.AppendLine('env.require=function(name) local value=env.package.loaded[name]; if value~=nil then return value end; assert(loaders[name], "Unbound module: "..name); value=loaders[name](env); env.package.loaded[name]=value; return value end')
$identities=@()
foreach($entry in $modules.GetEnumerator()) {
  $path=Join-Path $repo $entry.Value
  [void]$lua.AppendLine(('loaders["{0}"]=function(_ENV)' -f $entry.Key))
  [void]$lua.AppendLine([IO.File]::ReadAllText($path))
  [void]$lua.AppendLine('end')
  $identities+=@{path=$entry.Value;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
}
$testPath=Join-Path $repo 'tests/compiler/researchability_planning.lua'
$labTestPath=Join-Path $repo 'tests/compiler/lab_reachability.lua'
[void]$lua.AppendLine('local function run(_ENV)')
[void]$lua.AppendLine([IO.File]::ReadAllText($testPath))
[void]$lua.AppendLine('end; run(env)')
[void]$lua.AppendLine('env.package.loaded={}; local function run_labs(_ENV)')
[void]$lua.AppendLine([IO.File]::ReadAllText($labTestPath))
[void]$lua.AppendLine('end; run_labs(env)')

$fixtureName='mir-researchability-planning-test'
$fixtureVersion='1.0.0'
[IO.File]::WriteAllText((Join-Path $fixtureSource 'data.lua'),$lua.ToString(),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $fixtureSource 'info.json'),
  '{"name":"mir-researchability-planning-test","version":"1.0.0","title":"MIR controlled researchability regression","author":"MIR","factorio_version":"2.1","dependencies":["base"]}',
  [Text.UTF8Encoding]::new($false))
$fixtureArchive=Publish-MIRModDirectoryArchive -Source $fixtureSource -Name $fixtureName -Version $fixtureVersion -ModsDir $library
Assert-MIRLibraryFixtureArchive -Archive $fixtureArchive -SourceDirectory $fixtureSource
$baseInfo=Get-Content -Raw -LiteralPath (Join-Path $engineData 'base/info.json')|ConvertFrom-Json
$profile=Join-Path $run 'selection.json'
@{mods=@(
  @{name='base';version=[string]$baseInfo.version;enabled=$true},
  @{name=$fixtureName;version=$fixtureVersion;enabled=$true}
)}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $profile -Encoding utf8NoBOM
$archiveHashes=@{([IO.Path]::GetFileName($fixtureArchive))=(Get-FileHash -LiteralPath $fixtureArchive -Algorithm SHA256).Hash}
$config=[string]::Join([Environment]::NewLine,@('[path]',('read-data='+$engineData.Replace('\','/')),('write-data='+$userdata.Replace('\','/')),'[other]','enable-new-mods=false',''))
[IO.File]::WriteAllText((Join-Path $run 'config.ini'),$config,[Text.UTF8Encoding]::new($false))
$arguments=@('--config',(Join-Path $run 'config.ini'),'--mod-directory',$library,'--create',(Join-Path $run 'probe.zip'))
$activation=$null;$libraryRestoration=$null;$nativeRun=$null;$observerLog=$null
$researchabilityAssertions=$null;$labAssertions=$null;$failure=$null;$receipt=$null
try {
  $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $engineData -ProfilePath $profile -ArchiveHashes $archiveHashes -SettingsMode Defaults
  Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments $arguments
  $nativeRun=Invoke-MIRNativeProbeFactorioProcess -Context $context -FilePath $engine -Arguments $arguments -TimeoutSeconds 90
  $nativeLog=Join-Path $userdata 'factorio-current.log'
  if(-not(Test-Path -LiteralPath $nativeLog -PathType Leaf)){throw "Researchability planning produced no Factorio observer log: $nativeLog"}
  $observerLog=Join-Path $run 'factorio-observer.log'
  $log=Get-Content -Raw -LiteralPath $nativeLog
  [IO.File]::WriteAllText($observerLog,$log,[Text.UTF8Encoding]::new($false))
  if($nativeRun.result.exit_code -ne 0-or$log -notmatch'MIR-RESEARCHABILITY-PLANNING-PASS ([0-9]+)') {
    throw "Researchability planning regression failed: $observerLog"
  }
  $researchabilityAssertions=[int]$Matches[1]
  if($log -notmatch'MIR-LAB-REACHABILITY-PASS ([0-9]+)') {
    throw "Lab acquisition regression failed: $observerLog"
  }
  $labAssertions=[int]$Matches[1]
  $null=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $nativeLog -LatestInvocation
  $receipt=[ordered]@{
    status='passed'
    scope='controlled-modules-not-real-ecosystem-qualification'
    assertions=$researchabilityAssertions
    lab_acquisition_assertions=$labAssertions
    engine_version=[string]$engineResolution.engine.version
    engine_sha256=[string]$engineResolution.engine.sha256
    engine_resolution_record_sha256=[string]$engineResolution.record_sha256
    test_sha256=(Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash
    lab_test_sha256=(Get-FileHash -LiteralPath $labTestPath -Algorithm SHA256).Hash
    modules=$identities
    observer_log_sha256=(Get-FileHash -LiteralPath $observerLog -Algorithm SHA256).Hash
    fixture_library=@{path=$library;archive=$fixtureArchive;sha256=$archiveHashes[[IO.Path]::GetFileName($fixtureArchive)];flat_archive_count=@(Get-ChildItem -LiteralPath $library -File -Filter '*.zip').Count}
    dependency_payload_bytes_copied=0
    archive_links_created=0
    archive_extractions=0
    populated_profiles_created=0
    native_process=$nativeRun
    memory_enforcement='sampled-watchdog-not-hard-cap'
    expected_peak_memory_bytes=$context.peak_memory_bytes
    maximum_additional_output_bytes=$context.max_new_output_bytes
  }
} catch {
  $failure=$_
} finally {
  if($null -ne $activation -and -not $activation.closed){
    try {$libraryRestoration=Complete-MIRLibraryActivation -Activation $activation}
    catch {$libraryRestoration=[ordered]@{status='recovery-required';library=$activation.library;error=$_.Exception.Message;activation_closed=[bool]$activation.closed}}
  }
  if($null -ne $receipt){$receipt.library_control_restoration=$libraryRestoration}
  if($null -ne $failure){
    $failureReceipt=[ordered]@{
      status='failed'
      scope='controlled-modules-not-real-ecosystem-qualification'
      error=$failure.Exception.Message
      engine_version=[string]$engineResolution.engine.version
      engine_sha256=[string]$engineResolution.engine.sha256
      engine_resolution_record_sha256=[string]$engineResolution.record_sha256
      test_sha256=(Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash
      lab_test_sha256=(Get-FileHash -LiteralPath $labTestPath -Algorithm SHA256).Hash
      modules=$identities
      observer_log_sha256=$(if($observerLog -and (Test-Path -LiteralPath $observerLog -PathType Leaf)){(Get-FileHash -LiteralPath $observerLog -Algorithm SHA256).Hash}else{$null})
      fixture_library=@{path=$library;archive=$fixtureArchive;sha256=$archiveHashes[[IO.Path]::GetFileName($fixtureArchive)];flat_archive_count=@(Get-ChildItem -LiteralPath $library -File -Filter '*.zip').Count}
      library_control_restoration=$libraryRestoration
      dependency_payload_bytes_copied=0
      archive_links_created=0
      archive_extractions=0
      populated_profiles_created=0
      native_process=$nativeRun
      memory_enforcement='sampled-watchdog-not-hard-cap'
      expected_peak_memory_bytes=$context.peak_memory_bytes
      maximum_additional_output_bytes=$context.max_new_output_bytes
    }
    try {Write-MIRNativeProbeResult -Context $context -Record $failureReceipt}
    catch {Write-Warning "Researchability planning failure receipt exceeded its remaining budget; retained ledgers are in $run."}
  }
}
if($null -ne $failure){throw $failure}
Write-MIRNativeProbeResult -Context $context -Record $receipt
$receipt|ConvertTo-Json -Depth 12
