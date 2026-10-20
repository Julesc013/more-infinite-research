# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$ExpectedEngineSha256='',
  [string]$OutputRoot='build/tests/k2-imersite-continuation'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$k2StateRows = @(
  [ordered]@{name='mir-k2-imersite-staged-state-1';stream_key='__migration_state/k2_imersite_staged_v1';source='compatibility-migration-state:k2-imersite-staged'},
  [ordered]@{name='mir-k2-imersite-continuation-state-4';stream_key='__migration_state/k2_imersite_continuation_v1';source='compatibility-migration-state:k2-imersite-continuation'}
)
function Assert-MIRK2StagedStateManifest {
  param([string]$Repository)
  $streamsPath=Join-Path $Repository '.mir/streams.yml'
  $manifestPath=Join-Path $Repository 'source/prototypes/mir/streams/generated_stream_manifest.json'
  $streams=[IO.File]::ReadAllText($streamsPath)
  $manifest=Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
  foreach($expected in $k2StateRows) {
    $name=[regex]::Escape($expected.name)
    $rowMatch=[regex]::Match($streams,"(?ms)^    $name`:`r?`n(?<row>.*?)(?=^    [A-Za-z0-9_][^:`r`n]*:|`z)")
    if(-not $rowMatch.Success) { throw "K2 staged-state stream row missing: $($expected.name)" }
    $required=@(
      "canonical_row: prototypes/mir/streams/generated_stream_manifest.json#streams.$($expected.name)",
      'introduced_in: "4.7.0"',
      "source: $($expected.source)",
      'policy: retain-hidden-alias',
      'identity_state: stable-unreleased',
      "generated_technology: $($expected.name)",
      "stream_key: $($expected.stream_key)",
      'migration_policy: stable'
    )
    foreach($line in $required) {
      if($rowMatch.Groups['row'].Value -notmatch ('(?m)^      '+[regex]::Escape($line)+'\r?$')) {
        throw "K2 staged-state stream row lacks exact '$line': $($expected.name)"
      }
    }
    $entry=$manifest.streams.PSObject.Properties[$expected.name].Value
    if($null -eq $entry) { throw "K2 staged-state generated manifest row missing: $($expected.name)" }
    foreach($property in @('introduced_in','source','policy','identity_state','generated_technology','stream_key','migration_policy','stable')) {
      if($null -eq $entry.PSObject.Properties[$property]) { throw "K2 staged-state manifest property missing: $($expected.name).$property" }
    }
    if($entry.introduced_in -cne '4.7.0' -or $entry.source -cne $expected.source -or $entry.policy -cne 'retain-hidden-alias' -or
        $entry.identity_state -cne 'stable-unreleased' -or $entry.generated_technology -cne $expected.name -or
        $entry.stream_key -cne $expected.stream_key -or $entry.migration_policy -cne 'stable' -or $entry.stable -ne $true) {
      throw "K2 staged-state generated manifest row differs from the exact retained-alias contract: $($expected.name)"
    }
  }
}
Assert-MIRK2StagedStateManifest -Repository $repo
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
if(-not $output.StartsWith((Join-Path $repo 'build')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
  throw 'Test outputs must be under build.'
}
$version=(& $engine --version | Out-String)
$engineSha256=(Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash
if($LASTEXITCODE -ne 0 -or $version -notmatch 'Version:\s*2[.]1[.]22(?:\s|$)') {
  throw 'The K2 Imersite continuation compiler regression requires Factorio 2.1.22.'
}
if(-not [string]::IsNullOrWhiteSpace($ExpectedEngineSha256) -and $engineSha256 -cne $ExpectedEngineSha256) {
  throw "This regression requires exact engine SHA-256 $ExpectedEngineSha256."
}

$run=Join-Path $output ([guid]::NewGuid().ToString('N'))
$mod=Join-Path $run 'mods/mir-k2-imersite-continuation-test_1.0.0'
New-Item -ItemType Directory -Force -Path $mod,(Join-Path $run 'userdata') | Out-Null

$modules=[ordered]@{
  'prototypes.mir.core.deepcopy'='source/prototypes/mir/core/deepcopy.lua'
  'prototypes.mir.core.fingerprint'='source/prototypes/mir/core/fingerprint.lua'
  'prototypes.mir.capabilities.science_integration.science_selection_policy'='source/prototypes/mir/capabilities/science_integration/science_selection_policy.lua'
  'prototypes.mir.compatibility.policies.k2_science_phase'='source/prototypes/mir/compatibility/policies/k2_science_phase.lua'
  'prototypes.mir.families.material_progression'='source/prototypes/mir/families/material_progression.lua'
  'prototypes.mir.planner.requirements'='source/prototypes/mir/planner/requirements.lua'
  'prototypes.mir.domain.streams.descriptor'='source/prototypes/mir/domain/streams/descriptor.lua'
  'prototypes.mir.domain.effects.metadata'='source/prototypes/mir/domain/effects/metadata.lua'
  'prototypes.mir.domain.technology.technology_risk'='source/prototypes/mir/domain/technology/technology_risk.lua'
  'prototypes.mir.platform.factorio.target_line'='source/prototypes/mir/platform/factorio/target_line.lua'
  'prototypes.mir.platform.factorio.data_raw'='source/prototypes/mir/platform/factorio/data_raw.lua'
  'prototypes.mir.platform.factorio.prototype_lookup'='source/prototypes/mir/platform/factorio/prototype_lookup.lua'
  'prototypes.mir.capabilities.science_integration.science_packs'='source/prototypes/mir/capabilities/science_integration/science_packs.lua'
  'prototypes.mir.planner.costs'='source/prototypes/mir/planner/costs.lua'
  'prototypes.mir.domain.research_cost.model'='source/prototypes/mir/domain/research_cost/model.lua'
  'prototypes.mir.planner.stream_compiler.diagnostics'='source/prototypes/mir/planner/stream_compiler/diagnostics.lua'
  'prototypes.mir.report.diagnostics_sink'='source/prototypes/mir/report/diagnostics_sink.lua'
  'fixtures.material_progression.target_profiles'='source/adapters/f210/prototypes/mir/platform/factorio/target_profiles.lua'
  'prototypes.mir.domain.technology.maximum_level_binding'='source/prototypes/mir/domain/technology/maximum_level_binding.lua'
  'prototypes.mir.domain.research.k2_imersite_staged_state'='source/prototypes/mir/domain/research/k2_imersite_staged_state.lua'
  'prototypes.mir.planner.stream_compiler.k2_imersite_migration_alias'='source/prototypes/mir/planner/stream_compiler/k2_imersite_migration_alias.lua'
  'prototypes.mir.runtime.k2_imersite_staged_state_migration'='source/prototypes/mir/runtime/k2_imersite_staged_state_migration.lua'
  'prototypes.mir.runtime.maximum_level_control'='source/prototypes/mir/runtime/maximum_level_control.lua'
  'prototypes.mir.planner.stream_compiler.material_continuation'='source/prototypes/mir/planner/stream_compiler/material_continuation.lua'
  'prototypes.mir.policy.max_level'='source/prototypes/mir/policy/max_level.lua'
  'prototypes.streams.productivity'='source/prototypes/streams/productivity.lua'
}
$tests=[ordered]@{
  progression='tests/compiler/material_progression.lua'
  continuation='tests/compiler/material_continuation.lua'
  k2_staged_state='tests/runtime/k2_imersite_staged_state_controls.lua'
  worker_robot_speed_cap='tests/runtime/worker_robot_speed_cap.lua'
}

$lua=[Text.StringBuilder]::new()
[void]$lua.AppendLine('local host_log=log; local loaders={}')
[void]$lua.AppendLine('local function new_env() local env=setmetatable({package={loaded={}}},{__index=_G}); env._G=env; env.print=function(s) host_log(s) end; env.require=function(name) local value=env.package.loaded[name]; if value~=nil then return value end; assert(loaders[name], "Unbound module: "..name); value=loaders[name](env); env.package.loaded[name]=value; return value end; return env end')
$identities=@()
foreach($entry in $modules.GetEnumerator()) {
  $path=Join-Path $repo $entry.Value
  [void]$lua.AppendLine(('loaders["{0}"]=function(_ENV)' -f $entry.Key))
  [void]$lua.AppendLine([IO.File]::ReadAllText($path))
  [void]$lua.AppendLine('end')
  $identities+=@{path=$entry.Value;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
}
foreach($entry in $tests.GetEnumerator()) {
  $path=Join-Path $repo $entry.Value
  [void]$lua.AppendLine('do local _ENV=new_env()')
  [void]$lua.AppendLine([IO.File]::ReadAllText($path))
  [void]$lua.AppendLine('end')
  $identities+=@{path=$entry.Value;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
}

[IO.File]::WriteAllText((Join-Path $mod 'data.lua'),$lua.ToString(),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $mod 'info.json'),'{"name":"mir-k2-imersite-continuation-test","version":"1.0.0","title":"MIR controlled material continuation regression","author":"MIR","factorio_version":"2.1","dependencies":["base"]}',[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $run 'mods/mod-list.json'),'{"mods":[{"name":"base","enabled":true},{"name":"mir-k2-imersite-continuation-test","enabled":true}]}',[Text.UTF8Encoding]::new($false))
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
$config="[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($run.Replace('\','/'))/userdata`n"
[IO.File]::WriteAllText((Join-Path $run 'config.ini'),$config,[Text.UTF8Encoding]::new($false))

$start=[Diagnostics.ProcessStartInfo]::new($engine)
$start.UseShellExecute=$false
$start.CreateNoWindow=$true
$start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
foreach($argument in @('--config',(Join-Path $run 'config.ini'),'--mod-directory',(Join-Path $run 'mods'),'--create',(Join-Path $run 'probe.zip'))) {
  [void]$start.ArgumentList.Add($argument)
}
$process=[Diagnostics.Process]::Start($start)
try {
  if(-not $process.WaitForExit(60000)) {
    $process.Kill($true)
    throw "K2 Imersite continuation compiler regression timed out: $run"
  }
  $exitCode=$process.ExitCode
} finally {
  $process.Dispose()
}
$nativeLog=Join-Path $run 'userdata/factorio-current.log'
$log=Get-Content -Raw -LiteralPath $nativeLog
[IO.File]::WriteAllText((Join-Path $run 'stdout.txt'),$log,[Text.UTF8Encoding]::new($false))
$progressionMatch=[regex]::Match($log,'MIR-MATERIAL-PROGRESSION-PASS ([0-9]+)')
$continuationMatch=[regex]::Match($log,'MIR-MATERIAL-CONTINUATION-PASS ([0-9]+)')
$workerRobotSpeedCapMatch=[regex]::Match($log,'MIR-WORKER-ROBOT-SPEED-CAP-PASS')
$k2StagedStateMatch=[regex]::Match($log,'MIR-K2-STAGED-STATE-PASS ([0-9]+)')
if($exitCode -ne 0 -or -not $progressionMatch.Success -or -not $continuationMatch.Success -or -not $k2StagedStateMatch.Success -or -not $workerRobotSpeedCapMatch.Success) {
  throw "K2 Imersite continuation compiler regression failed: $nativeLog"
}
$receipt=[ordered]@{
  status='passed'
  scope='controlled-material-declarations-and-continuation-planner-not-K2-profile-qualification'
  assertions=[ordered]@{progression=[int]$progressionMatch.Groups[1].Value;continuation=[int]$continuationMatch.Groups[1].Value;k2_staged_state=[int]$k2StagedStateMatch.Groups[1].Value;worker_robot_speed_cap=$true}
  engine_version=$version.Trim()
  engine_sha256=$engineSha256
  harness_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
  inputs=$identities
  log_sha256=(Get-FileHash -LiteralPath (Join-Path $run 'stdout.txt') -Algorithm SHA256).Hash
}
$receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
$receipt | ConvertTo-Json -Depth 6
