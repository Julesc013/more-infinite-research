# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$OutputRoot='build/tests/recipe-source-epoch'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/F210QualificationPolicy.ps1')
# This maintainer-authorized controlled diagnostic uses the exact pre-freeze engine lock;
# its receipt does not grant public ecosystem/API qualification.
# The governed resolver owns the exact Steam path, branch, manifest, build,
# file-version and 2.1.18+ floor checks. Do not replace it with a loose version
# regex: this test may launch only the exact selected current F210 engine.
$engineResolution=Get-MIR4F210EngineResolutionV2 -RepoRoot $repo -FactorioBin $FactorioBin
$engine=(Resolve-Path -LiteralPath ([string]$engineResolution.engine.path)).Path
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
if(-not $output.StartsWith((Join-Path $repo 'build')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Test outputs must be under build.' }
$run=Join-Path $output ([guid]::NewGuid().ToString('N'))
$mod=Join-Path $run 'mods/mir-recipe-source-epoch-test_1.0.0'
New-Item -ItemType Directory -Force -Path $mod,(Join-Path $run 'userdata') | Out-Null
$modules=[ordered]@{
  'prototypes.mir.core.deepcopy'='source/prototypes/mir/core/deepcopy.lua'
  'prototypes.mir.core.fingerprint'='source/prototypes/mir/core/fingerprint.lua'
  'prototypes.mir.domain.compiler.execution_mode'='source/prototypes/mir/domain/compiler/execution_mode.lua'
  'prototypes.mir.domain.facts.recipe_semantics'='source/prototypes/mir/domain/facts/recipe_semantics.lua'
  'prototypes.mir.platform.factorio.data_raw'='source/prototypes/mir/platform/factorio/data_raw.lua'
  'prototypes.mir.pipeline.compiler_context'='source/prototypes/mir/pipeline/compiler_context.lua'
  'prototypes.mir.report.compiler_telemetry'='source/prototypes/mir/report/compiler_telemetry.lua'
  'prototypes.mir.graph.snapshot'='source/prototypes/mir/graph/snapshot.lua'
  'prototypes.mir.graph.scc'='source/prototypes/mir/graph/scc.lua'
  'prototypes.mir.graph.condensation'='source/prototypes/mir/graph/condensation.lua'
  'prototypes.mir.graph.researchability_index'='source/prototypes/mir/graph/researchability_index.lua'
  'prototypes.mir.index.recipe_facts'='source/prototypes/mir/index/recipe_facts.lua'
  'prototypes.mir.index.recipe_unlocks'='source/prototypes/mir/index/recipe_unlocks.lua'
  'prototypes.mir.capabilities.science_integration.pack_registry'='source/prototypes/mir/capabilities/science_integration/pack_registry.lua'
  'prototypes.mir.capabilities.science_integration.science_selection_policy'='source/prototypes/mir/capabilities/science_integration/science_selection_policy.lua'
  'prototypes.mir.capabilities.science_integration.recipe_unlock_facts'='source/prototypes/mir/capabilities/science_integration/recipe_unlock_facts.lua'
  'prototypes.mir.capabilities.science_integration.production_route_policy'='source/prototypes/mir/capabilities/science_integration/production_route_policy.lua'
  'prototypes.mir.capabilities.science_integration.recipe_route_feasibility'='source/prototypes/mir/capabilities/science_integration/recipe_route_feasibility.lua'
  'prototypes.mir.capabilities.science_integration.pack_production_reachability'='source/prototypes/mir/capabilities/science_integration/pack_production_reachability.lua'
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
[void]$lua.AppendLine('local function run(_ENV)')
$testPath=Join-Path $repo 'tests/compiler/recipe_source_epoch.lua'
[void]$lua.AppendLine([IO.File]::ReadAllText($testPath))
[void]$lua.AppendLine('end; run(env)')
[IO.File]::WriteAllText((Join-Path $mod 'data.lua'),$lua.ToString(),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $mod 'info.json'),'{"name":"mir-recipe-source-epoch-test","version":"1.0.0","title":"MIR recipe source epoch regression","author":"MIR","factorio_version":"2.1","dependencies":["base"]}',[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $run 'mods/mod-list.json'),'{"mods":[{"name":"base","enabled":true},{"name":"mir-recipe-source-epoch-test","enabled":true}]}',[Text.UTF8Encoding]::new($false))
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
$config="[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($run.Replace('\','/'))/userdata`n"
[IO.File]::WriteAllText((Join-Path $run 'config.ini'),$config,[Text.UTF8Encoding]::new($false))
$start=[Diagnostics.ProcessStartInfo]::new($engine)
$start.UseShellExecute=$false
$start.CreateNoWindow=$true
$start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
foreach($argument in @('--config',(Join-Path $run 'config.ini'),'--mod-directory',(Join-Path $run 'mods'),'--create',(Join-Path $run 'probe.zip'))) { $start.ArgumentList.Add($argument) }
$process=[Diagnostics.Process]::Start($start)
try {
  if(-not $process.WaitForExit(60000)) { $process.Kill($true); throw "Recipe source epoch regression timed out: $run" }
  $exitCode=$process.ExitCode
} finally { $process.Dispose() }
$nativeLog=Join-Path $run 'userdata/factorio-current.log'
$log=Get-Content -Raw -LiteralPath $nativeLog
[IO.File]::WriteAllText((Join-Path $run 'stdout.txt'),$log,[Text.UTF8Encoding]::new($false))
if($exitCode -ne 0 -or $log -notmatch 'MIR-RECIPE-SOURCE-EPOCH-PASS ([0-9]+)') { throw "Recipe source epoch regression failed: $nativeLog" }
$receipt=[ordered]@{status='passed';scope='controlled-real-context-recipe-source-epoch-not-ecosystem-qualification';assertions=[int]$Matches[1];engine_version=[string]$engineResolution.engine.version;engine_sha256=[string]$engineResolution.engine.sha256;engine_resolution_record_sha256=[string]$engineResolution.record_sha256;test_sha256=(Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash;modules=$identities;log_sha256=(Get-FileHash -LiteralPath (Join-Path $run 'stdout.txt') -Algorithm SHA256).Hash}
$receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
$receipt | ConvertTo-Json -Depth 6
