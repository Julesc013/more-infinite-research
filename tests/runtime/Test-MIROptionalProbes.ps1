# MIR4-CANONICAL-EXECUTABLE-TEST
param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
 [ValidateSet('2.0','2.1')][string]$Target='2.1'
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path $RepoRoot).Path
$engine=(Resolve-Path $FactorioBin).Path
$version=(& $engine --version | Out-String).Trim()
if($version -notmatch ('Version: '+[regex]::Escape($Target)+'[.]')) { throw 'Engine line does not match requested target.' }
$run=Join-Path $repo ('build/optional-probes/'+[guid]::NewGuid().ToString('N').Substring(0,8))
$fixture=Join-Path $run 'mods/mir-optional-test_1.0.0'
New-Item -ItemType Directory -Force $fixture | Out-Null
@{name='mir-optional-test';version='1.0.0';title='MIR package-excluded optional probes';author='MIR';factorio_version=$Target;dependencies=@('base')} | ConvertTo-Json | Set-Content (Join-Path $fixture 'info.json')
Copy-Item -LiteralPath (Join-Path $repo 'tests/runtime/optional_runtime_services.lua') -Destination $fixture
Copy-Item -LiteralPath (Join-Path $repo 'tests/runtime/optional_runtime_probe.lua') -Destination (Join-Path $fixture 'control.lua')
@{mods=@(@{name='base';enabled=$true},@{name='space-age';enabled=$false},@{name='elevated-rails';enabled=$false},@{name='quality';enabled=$false},@{name='recycler';enabled=$false},@{name='mir-optional-test';enabled=$true})} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $run 'mods/mod-list.json')
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($run.Replace('\','/'))/userdata`n" | Set-Content (Join-Path $run 'config.ini')
$save=Join-Path $run 'probe.zip'
function Invoke-BrowserEngine([string[]]$Arguments) {
 $start=[Diagnostics.ProcessStartInfo]::new($engine)
 $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
 $start.Environment["SteamAppId"]="427520"; $start.Environment["SteamGameId"]="427520"
 $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
 foreach($arg in @('--config',(Join-Path $run 'config.ini'),'--mod-directory',(Join-Path $run 'mods'))+$Arguments) { $start.ArgumentList.Add($arg) }
 $process=[Diagnostics.Process]::Start($start)
 $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
 try {
  if(-not $process.WaitForExit(120000)) { $process.Kill($true); throw "Browser test timeout: $run" }
  $result=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
  $result | Set-Content (Join-Path $run ('engine-'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.log'))
  if($process.ExitCode -ne 0) { throw "Browser engine failed: $run`n$($result.Substring([Math]::Max(0,$result.Length-2500)))" }
 } finally { $process.Dispose() }
}
Invoke-BrowserEngine @('--create',$save)
Invoke-BrowserEngine @('--benchmark',$save,'--benchmark-ticks','242','--benchmark-runs','1')
$resultPath=Join-Path $run 'userdata/script-output/optional-probe.json'
if(-not (Test-Path $resultPath)) { throw "No optional probe result: $run" }
$result=Get-Content -Raw $resultPath | ConvertFrom-Json
if($result.status -ne 'passed') { throw "Optional probe failed: $run" }
$result | Add-Member engine_sha256 (Get-FileHash $engine).Hash
$result | Add-Member prototype_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/optional_runtime_services.lua')).Hash
$result | Add-Member test_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/optional_runtime_probe.lua')).Hash
$result | Add-Member harness_sha256 (Get-FileHash $PSCommandPath).Hash
$result | Add-Member target $Target
$result | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $run 'result.json')
$result | ConvertTo-Json -Depth 6
Write-Output "Evidence: $run"
