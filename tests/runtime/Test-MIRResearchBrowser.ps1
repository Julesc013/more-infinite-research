# MIR4-CANONICAL-EXECUTABLE-TEST
param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
 [string]$CandidateZip='',
 [ValidateSet('2.0','2.1')][string]$Target='2.1',
 [switch]$Graphics
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path $RepoRoot).Path
$engine=(Resolve-Path $FactorioBin).Path
if([string]::IsNullOrWhiteSpace($CandidateZip)) {
 . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
 $targetKey=if($Target -eq '2.0') {'f200'} else {'f210'}
 $version=if($Target -eq '2.0') {'4.2.20000'} else {'4.2.21000'}
 $package=New-MIR4TargetPackage -RepoRoot $repo -Target $targetKey -CandidateId ('BROWSER-'+[guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()) -SourceVersion '4.2.0' -DistributionVersion $version -OutputRoot 'build/browser-packages'
 $candidate=[string]$package.archive_path
} else { $candidate=(Resolve-Path (Join-Path $repo $CandidateZip)).Path }
$archive=[IO.Compression.ZipFile]::OpenRead($candidate)
try {
 $entry=@($archive.Entries | Where-Object FullName -Like '*/prototypes/mir/runtime/research_browser_model.lua')
 if($entry.Count -ne 1) { throw 'Candidate must contain exactly one browser model.' }
 $stream=$entry[0].Open()
 try { $modelHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) } finally { $stream.Dispose() }
 if($modelHash -cne (Get-FileHash (Join-Path $repo 'src/mod/families/modern/prototypes/mir/runtime/research_browser_model.lua')).Hash) { throw 'Candidate model differs from the controlled model under test.' }
} finally { $archive.Dispose() }
$run=Join-Path $repo ('build/browser-tests/'+[guid]::NewGuid().ToString('N').Substring(0,8))
$fixture=Join-Path $run 'mods/mir-browser-test_1.0.0'
New-Item -ItemType Directory -Force $fixture | Out-Null
Copy-Item -LiteralPath $candidate -Destination (Join-Path $run 'mods')
@{name='mir-browser-test';version='1.0.0';title='MIR browser acceptance';author='MIR';factorio_version=$Target;dependencies=@('base','more-infinite-research')} | ConvertTo-Json | Set-Content (Join-Path $fixture 'info.json')
Copy-Item -LiteralPath (Join-Path $repo 'tests/runtime/browser_fixture_data.lua') -Destination (Join-Path $fixture 'data.lua')
$lua=[Text.StringBuilder]::new()
[void]$lua.AppendLine('local browser_model=(function()')
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo 'src/mod/families/modern/prototypes/mir/runtime/research_browser_model.lua')))
[void]$lua.AppendLine('end)()')
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/research_browser.lua')))
[IO.File]::WriteAllText((Join-Path $fixture 'control.lua'),$lua.ToString(),[Text.UTF8Encoding]::new($false))
@{mods=@(@{name='base';enabled=$true},@{name='space-age';enabled=$false},@{name='elevated-rails';enabled=$false},@{name='quality';enabled=$false},@{name='recycler';enabled=$false},@{name='more-infinite-research';enabled=$true},@{name='mir-browser-test';enabled=$true})} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $run 'mods/mod-list.json')
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
if($Graphics) { Invoke-BrowserEngine @('--benchmark-graphics',$save,'--benchmark-ticks','120','--disable-audio','--window-size','1024x768') }
else { Invoke-BrowserEngine @('--benchmark',$save,'--benchmark-ticks','3','--benchmark-runs','1') }
$resultPath=Join-Path $run 'userdata/script-output/browser-test.json'
if(-not (Test-Path $resultPath)) { throw "No browser acceptance result: $run" }
$result=Get-Content -Raw $resultPath | ConvertFrom-Json
if($Graphics -and $result.native_players -lt 1) { throw "Graphics test did not exercise a native player: $run" }
if($result.status -ne 'passed') { throw "Browser acceptance failed: $resultPath" }
$result | Add-Member package_sha256 (Get-FileHash $candidate).Hash
$result | Add-Member engine_sha256 (Get-FileHash $engine).Hash
$result | Add-Member model_sha256 (Get-FileHash (Join-Path $repo 'src/mod/families/modern/prototypes/mir/runtime/research_browser_model.lua')).Hash
$result | Add-Member harness_sha256 (Get-FileHash $PSCommandPath).Hash
$result | Add-Member fixture_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/browser_fixture_data.lua')).Hash
$result | Add-Member test_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/research_browser.lua')).Hash
if($Graphics) {
 $saved=Join-Path $run 'userdata/saves/_autosave-mir-browser-acceptance.zip'
 if(-not (Test-Path $saved)) { throw "Native browser save capture missing: $saved" }
 Invoke-BrowserEngine @('--benchmark-graphics',$saved,'--benchmark-ticks','120','--disable-audio','--window-size','1024x768')
 $reloaded=Join-Path $run 'userdata/script-output/browser-reload.json'
 if(-not(Test-Path $reloaded)) { throw "Native browser reload result missing: $run" }
 $reload=Get-Content -Raw $reloaded | ConvertFrom-Json
 if($reload.status -ne 'passed') { throw 'Browser reload failed.' }
 $result | Add-Member reload $reload
 $result | Add-Member save_sha256 (Get-FileHash $saved).Hash
}
$result | Add-Member target $Target
$result | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $run 'result.json')
$result | ConvertTo-Json -Depth 6
Write-Output "Evidence: $run"
