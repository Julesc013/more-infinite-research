# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [ValidateSet('2.0','2.1')]
  [string]$ExpectedFactorioLine='2.1',
  [string]$ExpectedEngineSha256='',
  [string]$OutputRoot='build/p/material-routes',
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB=0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 3 -MaxEntriesPerRoot 400 -MaxWorktrees 8 -MaxBranches 32 | Out-Host
$resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
$gitHeadAtStart=(& git -C $repo rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0){throw 'Unable to resolve the tested Git head.'}
$trackedStatusAtStart=@(& git -C $repo status --short --untracked-files=no)
if($LASTEXITCODE -ne 0){throw 'Unable to inspect tracked inputs before the material-route regression.'}
$run=$resources.root
$mod=Join-Path $run 'mods/mir-material-routes-test_1.0.0'
New-Item -ItemType Directory -Force -Path $mod,(Join-Path $run 'userdata') | Out-Null
$versionRun=Invoke-MIRNativeProbeProcess -Context $resources -FilePath $engine -Arguments @('--version') -TimeoutSeconds 30
$version=Get-Content -LiteralPath $versionRun.stdout -Raw
$engineSha256=(Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash
if($version -notmatch ('Version: '+[regex]::Escape($ExpectedFactorioLine)+'[.]')) { throw "This material-route regression requires a Factorio $ExpectedFactorioLine engine." }
if(-not [string]::IsNullOrWhiteSpace($ExpectedEngineSha256) -and $engineSha256 -cne $ExpectedEngineSha256) { throw "This material-route regression requires exact engine SHA-256 $ExpectedEngineSha256." }
$modules=[ordered]@{
 'prototypes.mir.capabilities.recipe_productivity.recipe_matching'='source/prototypes/mir/capabilities/recipe_productivity/recipe_matching.lua'
 'prototypes.mir.families.material_progression'='source/prototypes/mir/families/material_progression.lua'
 'prototypes.mir.families.operator_dsl'='source/prototypes/mir/families/operator_dsl.lua'
 'prototypes.mir.compatibility.policies.k2_science_phase'='source/prototypes/mir/compatibility/policies/k2_science_phase.lua'
 'prototypes.mir.index.recipe_risk_facts'='source/prototypes/mir/index/recipe_risk_facts.lua'
 'prototypes.mir.index.recipe_facts'='source/prototypes/mir/index/recipe_facts.lua'
 'prototypes.mir.domain.facts.recipe_semantics'='source/prototypes/mir/domain/facts/recipe_semantics.lua'
 'prototypes.mir.index.recycling'='source/prototypes/mir/index/recycling.lua'
 'prototypes.mir.policy.productivity_cap_scope'='source/prototypes/mir/policy/productivity_cap_scope.lua'
 'prototypes.mir.pipeline.prototype_limits'='source/prototypes/mir/pipeline/prototype_limits.lua'
 'prototypes.mir.settings.prototype_limits'='source/prototypes/mir/settings/prototype_limits.lua'
 'prototypes.mir.settings.order'='source/prototypes/mir/settings/order.lua'
 'fixtures.material_routes.target_profiles'='source/adapters/f210/prototypes/mir/platform/factorio/target_profiles.lua'
 'prototypes.mir.domain.facts.generated_technology_registry'='source/prototypes/mir/domain/facts/generated_technology_registry.lua'
 'prototypes.mir.report.diagnostics_sink'='source/prototypes/mir/report/diagnostics_sink.lua'
 'prototypes.mir.core.deepcopy'='source/prototypes/mir/core/deepcopy.lua'
 'prototypes.streams.productivity'='source/prototypes/streams/productivity.lua'
 'prototypes.mir.planner.stream_compiler.discover'='source/prototypes/mir/planner/stream_compiler/discover.lua'
 'prototypes.mir.domain.native_owner.contract'='source/prototypes/mir/domain/native_owner/contract.lua'
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
$testPath=Join-Path $repo 'tests/compiler/material_routes.lua'
[void]$lua.AppendLine([IO.File]::ReadAllText($testPath))
[void]$lua.AppendLine('end; run(env)')
[IO.File]::WriteAllText((Join-Path $mod 'data.lua'),$lua.ToString(),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $mod 'info.json'),('{"name":"mir-material-routes-test","version":"1.0.0","title":"MIR controlled material route regression","author":"MIR","factorio_version":"'+$ExpectedFactorioLine+'","dependencies":["base"]}'),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $run 'mods/mod-list.json'),'{"mods":[{"name":"base","enabled":true},{"name":"mir-material-routes-test","enabled":true}]}',[Text.UTF8Encoding]::new($false))
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
$config="[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($run.Replace('\','/'))/userdata`n"
[IO.File]::WriteAllText((Join-Path $run 'config.ini'),$config,[Text.UTF8Encoding]::new($false))
$engineRun=Invoke-MIRNativeProbeProcess -Context $resources -FilePath $engine -TimeoutSeconds 120 `
 -Arguments @('--config',(Join-Path $run 'config.ini'),'--no-log-rotation','--disable-audio','--mod-directory',(Join-Path $run 'mods'),'--create',(Join-Path $run 'probe.zip'))
$nativeLog=Join-Path $run 'userdata/factorio-current.log'
$log=Get-Content -Raw -LiteralPath $nativeLog
$completion=[regex]::Match($log,'MIR-MATERIAL-ROUTES-PASS ([0-9]+)')
if(-not $completion.Success) { throw "Material route regression failed: $nativeLog" }
$gitHeadAtEnd=(& git -C $repo rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0){throw 'Unable to resolve the tested Git head after the material-route regression.'}
$trackedStatusAtEnd=@(& git -C $repo status --short --untracked-files=no)
if($LASTEXITCODE -ne 0){throw 'Unable to inspect tracked inputs after the material-route regression.'}
$trackedInputsClean=($trackedStatusAtStart.Count -eq 0 -and $trackedStatusAtEnd.Count -eq 0 -and $gitHeadAtStart -ceq $gitHeadAtEnd)
$receipt=[ordered]@{status='passed';scope='controlled-material-process-guard-not-whole-ecosystem-proof';assertions=[int]$completion.Groups[1].Value;engine_line=$ExpectedFactorioLine;engine_version=$version.Trim();engine_sha256=$engineSha256;harness_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash;test_sha256=(Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash;modules=$identities;log_sha256=(Get-FileHash -LiteralPath $nativeLog -Algorithm SHA256).Hash;resource_runs=$resources.runs.ToArray();resource_policy=[ordered]@{declared_peak_memory_mib=$ExpectedPeakMemoryMiB;max_new_output_mib=$MaxNewOutputMiB;memory_enforcement='sampled-watchdog-not-hard-cap'};evidence_binding=[ordered]@{git_head=$gitHeadAtEnd;tracked_inputs_clean=$trackedInputsClean;reusable_for_exact_head=$trackedInputsClean}}
Write-MIRNativeProbeResult -Context $resources -Record $receipt
$receipt | ConvertTo-Json -Depth 6
