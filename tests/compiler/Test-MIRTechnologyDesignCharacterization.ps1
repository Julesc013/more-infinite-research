# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$OutputRoot='build/tmp/technology-design-characterization',
  [ValidateRange(0,2048)][int]$ExpectedPeakMemoryMiB=0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/ResourceGovernor.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
$outputPath=if([IO.Path]::IsPathRooted($OutputRoot)){$OutputRoot}else{Join-Path $repo $OutputRoot}
$output=Resolve-MIR441RecoveryScratchPath -Path $outputPath
if($ExpectedPeakMemoryMiB-le0){throw '[mir441-resource-peak-budget-required] Declare the characterization peak memory budget.'}
$policy=[pscustomobject]@{minimum_free_ram_gib=4}
$peakBytes=[int64]$ExpectedPeakMemoryMiB*1MB
$writeBytes=[int64]$MaxNewOutputMiB*1MB
# Refuse before staging or even a version probe allocates process/output state.
$null=Assert-MIR441ResourceAdmission -Policy $policy -WorkRoot $output -EstimatedPeakBytes $writeBytes -ExpectedPeakMemoryBytes $peakBytes
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/Common.ps1')
. (Join-Path $repo 'tools/lib/compatibility/FactorioRunner.ps1')
$run=Join-Path $output ([guid]::NewGuid().ToString('N'))
# The only non-builtin mod is a single generated fixture ZIP in this run's
# checkout-contained flat library.  Source assembly stays outside the library;
# Factorio sees no extracted mod directory or copied dependency payload.
$fixtureSource=Join-Path $run 'fixture-source'
$library=Join-Path $run 'fixture-library'
New-Item -ItemType Directory -Force -Path $fixtureSource,$library,(Join-Path $run 'userdata')|Out-Null
$ledger=Join-Path $run 'resource-ledger.jsonl'
$versionRun=Invoke-MIR441MonitoredProcess -FilePath $engine -Arguments @('--version') -WorkRoot $run -LedgerPath $ledger -Policy $policy -EstimatedPeakBytes $writeBytes -ExpectedPeakMemoryBytes $peakBytes -TimeoutSeconds 15 -StdoutPath (Join-Path $run 'version.stdout.txt') -StderrPath (Join-Path $run 'version.stderr.txt') -AllowNonZeroExit
$version=[IO.File]::ReadAllText((Join-Path $run 'version.stdout.txt'))
if(-not$versionRun.passed-or$version-notmatch'Version: 2[.]1[.]') {
  throw 'TechnologyDesign characterization requires an exact Factorio 2.1 engine.'
}
$modules=[ordered]@{
  'prototypes.mir.core.deepcopy'='source/prototypes/mir/core/deepcopy.lua'
  'prototypes.mir.core.fingerprint'='source/prototypes/mir/core/fingerprint.lua'
  'prototypes.mir.core.trusted_record'='source/prototypes/mir/core/trusted_record.lua'
  'prototypes.mir.domain.compiler.compilation_snapshot'='source/prototypes/mir/domain/compiler/compilation_snapshot.lua'
  'prototypes.mir.domain.compiler.execution_mode'='source/prototypes/mir/domain/compiler/execution_mode.lua'
  'prototypes.mir.pipeline.compiler_context'='source/prototypes/mir/pipeline/compiler_context.lua'
  'prototypes.mir.index.recipe_facts'='source/prototypes/mir/index/recipe_facts.lua'
  'prototypes.mir.graph.snapshot'='source/prototypes/mir/graph/snapshot.lua'
  'prototypes.mir.pipeline.compilation_snapshot_adapter'='source/prototypes/mir/pipeline/compilation_snapshot_adapter.lua'
  'prototypes.mir.pipeline.compiler_orchestrator.publication'='source/prototypes/mir/pipeline/compiler_orchestrator/publication.lua'
  'prototypes.mir.domain.effects.metadata'='source/prototypes/mir/domain/effects/metadata.lua'
  'prototypes.mir.domain.effects.generated_target_contracts'='source/prototypes/mir/domain/effects/generated_target_contracts.lua'
  'prototypes.mir.integrity.effect_contracts'='source/prototypes/mir/integrity/effect_contracts.lua'
  'prototypes.mir.domain.technology.gate'='source/prototypes/mir/domain/technology/gate.lua'
  'prototypes.mir.domain.technology.technology_design'='source/prototypes/mir/domain/technology/technology_design.lua'
}
$lua=[Text.StringBuilder]::new()
[void]$lua.AppendLine('local host_log=log; local loaders={}; local env=setmetatable({package={loaded={}}},{__index=_G}); env._G=env; env.print=function(s) host_log(s) end')
[void]$lua.AppendLine('env.require=function(name) local value=env.package.loaded[name]; if value~=nil then return value end; assert(loaders[name], "Unbound module: "..name); value=loaders[name](env); env.package.loaded[name]=value; return value end')
$identities=@()
foreach($entry in $modules.GetEnumerator()) {
  $path=Join-Path $repo $entry.Value
  [void]$lua.AppendLine(('loaders["{0}"]=function(_ENV)'-f$entry.Key))
  [void]$lua.AppendLine([IO.File]::ReadAllText($path))
  [void]$lua.AppendLine('end')
  $identities+=@{path=$entry.Value;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
}
[void]$lua.AppendLine('local function run(_ENV)')
$testPath=Join-Path $repo 'tests/compiler/technology_design_characterization.lua'
[void]$lua.AppendLine([IO.File]::ReadAllText($testPath))
$publicationTestPath=Join-Path $repo 'tests/compiler/publication_measurement.lua'
[void]$lua.AppendLine([IO.File]::ReadAllText($publicationTestPath))
[void]$lua.AppendLine('end; run(env)')
$fixtureName='mir-technology-design-characterization'
$fixtureVersion='1.0.0'
[IO.File]::WriteAllText((Join-Path $fixtureSource 'data.lua'),$lua.ToString(),[Text.UTF8Encoding]::new($false))
$info='{"name":"mir-technology-design-characterization","version":"1.0.0","title":"MIR TechnologyDesign characterization","author":"MIR","factorio_version":"2.1","dependencies":["base"]}'
[IO.File]::WriteAllText((Join-Path $fixtureSource 'info.json'),$info,[Text.UTF8Encoding]::new($false))
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
$engineData=Join-Path $engineRoot 'data'
$baseInfo=Get-Content -Raw -LiteralPath (Join-Path $engineData 'base/info.json')|ConvertFrom-Json
$fixtureArchive=Publish-MIRModDirectoryArchive -Source $fixtureSource -Name $fixtureName -Version $fixtureVersion -ModsDir $library
Assert-MIRLibraryFixtureArchive -Archive $fixtureArchive -SourceDirectory $fixtureSource
$profile=Join-Path $run 'selection.json'
@{mods=@(
  @{name='base';version=[string]$baseInfo.version;enabled=$true},
  @{name=$fixtureName;version=$fixtureVersion;enabled=$true}
)}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $profile -Encoding utf8NoBOM
$archiveHashes=@{([IO.Path]::GetFileName($fixtureArchive))=(Get-FileHash -LiteralPath $fixtureArchive -Algorithm SHA256).Hash}
$config="[path]`nread-data=$($engineData.Replace('\','/'))`nwrite-data=$($run.Replace('\','/'))/userdata`n[other]`nenable-new-mods=false`n"
[IO.File]::WriteAllText((Join-Path $run 'config.ini'),$config,[Text.UTF8Encoding]::new($false))
$arguments=@('--config',(Join-Path $run 'config.ini'),'--mod-directory',$library,'--create',(Join-Path $run 'probe.zip'))
$activation=$null;$libraryRestoration=$null
try{
  $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $engineData -ProfilePath $profile -ArchiveHashes $archiveHashes -SettingsMode Defaults
  $process=Invoke-MIRCompatFactorioProcess -FactorioBin $engine -ArgumentList $arguments -StdoutPath (Join-Path $run 'stdout.txt') -StderrPath (Join-Path $run 'stderr.txt') -TimeoutSeconds 60 -EstimatedPeakBytes $writeBytes -ExpectedPeakMemoryBytes $peakBytes -LibraryActivation $activation
  $nativeLog=Join-Path $run 'userdata/factorio-current.log'
  $log=Get-Content -Raw -LiteralPath $nativeLog
  if($process.exit_code-ne0-or$log-notmatch'MIR-TECHNOLOGY-DESIGN-CHARACTERIZATION-PASS ([0-9]+)') {
    throw "TechnologyDesign characterization failed: $nativeLog"
  }
  $assertionCount=[int]$Matches[1]
  if($assertionCount-ne636) {
    throw "TechnologyDesign characterization expected 636 assertions, observed $assertionCount`: $nativeLog"
  }
  if($log-notmatch'MIR-PUBLICATION-MEASUREMENT-PASS ([0-9]+)') {
    throw "Publication measurement characterization failed: $nativeLog"
  }
  $publicationAssertionCount=[int]$Matches[1]
  if($publicationAssertionCount-ne11) {
    throw "Publication measurement characterization expected 11 assertions, observed $publicationAssertionCount`: $nativeLog"
  }
  $null=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $nativeLog -LatestInvocation
}finally{
  if($null-ne$activation-and-not$activation.closed){$libraryRestoration=Complete-MIRLibraryActivation -Activation $activation}
}
$receipt=[ordered]@{
  status='passed'
  scope='technology-design-characterization-not-release-qualification'
  assertions=$assertionCount
  engine_version=$version.Trim()
  engine_sha256=(Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash
  test_sha256=(Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash
  publication_test_sha256=(Get-FileHash -LiteralPath $publicationTestPath -Algorithm SHA256).Hash
  publication_assertions=$publicationAssertionCount
  modules=$identities
  log_sha256=(Get-FileHash -LiteralPath $nativeLog -Algorithm SHA256).Hash
  fixture_library=@{path=$library;archive=$fixtureArchive;sha256=$archiveHashes[[IO.Path]::GetFileName($fixtureArchive)];flat_archive_count=@(Get-ChildItem -LiteralPath $library -File -Filter '*.zip').Count}
  library_control_restoration=$libraryRestoration
  dependency_payload_bytes_copied=0
  archive_links_created=0
  archive_extractions=0
  populated_profiles_created=0
  version_process=$versionRun
  characterization_process=$process
  memory_enforcement='sampled-watchdog-not-hard-cap'
  expected_peak_memory_bytes=$peakBytes
  maximum_additional_output_bytes=$writeBytes
}
$receipt|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
$receipt|ConvertTo-Json -Depth 6
