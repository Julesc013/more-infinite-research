# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$OutputRoot='build/tests/technology-design-characterization'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$buildRoot=(Join-Path $repo 'build')+[IO.Path]::DirectorySeparatorChar
if(-not$output.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)) {
  throw 'Test outputs must be under build.'
}
$os=Get-CimInstance Win32_OperatingSystem
$availableBytes=[int64]$os.FreePhysicalMemory*1KB
if($availableBytes-lt4GB) {
  throw ('TechnologyDesign engine characterization requires at least 4 GiB free RAM; observed {0:N2} GiB.' -f ($availableBytes/1GB))
}
$run=Join-Path $output ([guid]::NewGuid().ToString('N'))
$mod=Join-Path $run 'mods/mir-technology-design-characterization_1.0.0'
New-Item -ItemType Directory -Force -Path $mod,(Join-Path $run 'userdata')|Out-Null
$version=(& $engine --version|Out-String)
if($LASTEXITCODE-ne0-or$version-notmatch'Version: 2[.]1[.]') {
  throw 'TechnologyDesign characterization requires an exact Factorio 2.1 engine.'
}
$modules=[ordered]@{
  'prototypes.mir.core.deepcopy'='source/prototypes/mir/core/deepcopy.lua'
  'prototypes.mir.core.fingerprint'='source/prototypes/mir/core/fingerprint.lua'
  'prototypes.mir.core.trusted_record'='source/prototypes/mir/core/trusted_record.lua'
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
[void]$lua.AppendLine('end; run(env)')
[IO.File]::WriteAllText((Join-Path $mod 'data.lua'),$lua.ToString(),[Text.UTF8Encoding]::new($false))
$info='{"name":"mir-technology-design-characterization","version":"1.0.0","title":"MIR TechnologyDesign characterization","author":"MIR","factorio_version":"2.1","dependencies":["base"]}'
[IO.File]::WriteAllText((Join-Path $mod 'info.json'),$info,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $run 'mods/mod-list.json'),'{"mods":[{"name":"base","enabled":true},{"name":"mir-technology-design-characterization","enabled":true}]}',[Text.UTF8Encoding]::new($false))
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
$config="[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($run.Replace('\','/'))/userdata`n"
[IO.File]::WriteAllText((Join-Path $run 'config.ini'),$config,[Text.UTF8Encoding]::new($false))
$start=[Diagnostics.ProcessStartInfo]::new($engine)
$start.UseShellExecute=$false
$start.CreateNoWindow=$true
$start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
foreach($argument in @('--config',(Join-Path $run 'config.ini'),'--mod-directory',(Join-Path $run 'mods'),'--create',(Join-Path $run 'probe.zip'))) {
  $start.ArgumentList.Add($argument)
}
$process=[Diagnostics.Process]::Start($start)
try {
  if(-not$process.WaitForExit(60000)) {
    $process.Kill($true)
    throw "TechnologyDesign characterization timed out: $run"
  }
  $exitCode=$process.ExitCode
} finally {
  $process.Dispose()
}
$nativeLog=Join-Path $run 'userdata/factorio-current.log'
$log=Get-Content -Raw -LiteralPath $nativeLog
[IO.File]::WriteAllText((Join-Path $run 'stdout.txt'),$log,[Text.UTF8Encoding]::new($false))
if($exitCode-ne0-or$log-notmatch'MIR-TECHNOLOGY-DESIGN-CHARACTERIZATION-PASS ([0-9]+)') {
  throw "TechnologyDesign characterization failed: $nativeLog"
}
$assertionCount=[int]$Matches[1]
if($assertionCount-ne42) {
  throw "TechnologyDesign characterization expected 42 assertions, observed $assertionCount`: $nativeLog"
}
$receipt=[ordered]@{
  status='passed'
  scope='technology-design-characterization-not-release-qualification'
  assertions=$assertionCount
  engine_version=$version.Trim()
  engine_sha256=(Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash
  test_sha256=(Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash
  modules=$identities
  log_sha256=(Get-FileHash -LiteralPath (Join-Path $run 'stdout.txt') -Algorithm SHA256).Hash
}
$receipt|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
$receipt|ConvertTo-Json -Depth 6
