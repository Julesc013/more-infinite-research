# MIR4-CANONICAL-EXECUTABLE-TEST
param(
 [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
 [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
 [string]$EvidenceRoot='build/results/mir42-overnight'
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path $RepoRoot).Path
$engine=(Resolve-Path $FactorioBin).Path
$fixtureSource=Join-Path $repo 'fixtures/portable-research-surface-no-mir'
$coreSource=Join-Path $repo 'src/mod/families/modern/prototypes/mir/runtime/research_browser_core.lua'
$adapterSource=Join-Path $repo 'src/mod/families/modern/prototypes/mir/runtime/research_browser_factorio_catalogue.lua'
foreach($path in @($fixtureSource,$coreSource,$adapterSource)) { if(-not(Test-Path -LiteralPath $path)){throw "Missing portable no-MIR input: $path"} }
$fixtureInfo=Get-Content -Raw (Join-Path $fixtureSource 'info.json')|ConvertFrom-Json
if(@($fixtureInfo.dependencies|Where-Object{[string]$_ -match 'more-infinite-research'}).Count){throw 'No-MIR fixture declares MIR.'}
$coreRaw=Get-Content -Raw $coreSource
if($coreRaw -match '(?i)\b(game|script|defines|prototypes|gui|research_queue|runtime_state|require)\b'){throw 'Portable core imports a Factorio host surface.'}
$adapterRaw=Get-Content -Raw $adapterSource
if($adapterRaw -match '(?i)(require\(|runtime_state|prototypes\.mod_data|more-infinite-research)'){throw 'Generic Factorio adapter imports MIR/private state.'}
$run=Join-Path $repo ($EvidenceRoot+'/portable-research-surface-no-mir/'+[guid]::NewGuid().ToString('N').Substring(0,8))
$fixture=Join-Path $run 'mods/portable-research-surface-no-mir_1.0.0'
New-Item -ItemType Directory -Force (Split-Path $fixture -Parent) | Out-Null
Copy-Item -LiteralPath $fixtureSource -Destination $fixture -Recurse
$lua=[Text.StringBuilder]::new()
foreach($module in @(@{name='portable_core';path=$coreSource},@{name='portable_factorio_catalogue';path=$adapterSource})) {
 [void]$lua.AppendLine("local $($module.name)=(function()")
 [void]$lua.AppendLine([IO.File]::ReadAllText($module.path))
 [void]$lua.AppendLine('end)()')
}
[void]$lua.AppendLine([IO.File]::ReadAllText((Join-Path $fixtureSource 'control.lua')))
[IO.File]::WriteAllText((Join-Path $fixture 'control.lua'),$lua.ToString(),[Text.UTF8Encoding]::new($false))
@{mods=@(@{name='base';enabled=$true},@{name='space-age';enabled=$false},@{name='elevated-rails';enabled=$false},@{name='quality';enabled=$false},@{name='recycler';enabled=$false},@{name='portable-research-surface-no-mir';enabled=$true})}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $run 'mods/mod-list.json')
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($run.Replace('\','/'))/userdata`n"|Set-Content (Join-Path $run 'config.ini')
function Invoke-PortableEngine([string[]]$Arguments) {
 $start=[Diagnostics.ProcessStartInfo]::new($engine)
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
 $start.Environment['SteamAppId']='427520';$start.Environment['SteamGameId']='427520'
 $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 foreach($argument in @('--config',(Join-Path $run 'config.ini'),'--mod-directory',(Join-Path $run 'mods'))+$Arguments){$start.ArgumentList.Add($argument)}
 $process=[Diagnostics.Process]::Start($start)
 $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
 try {
  if(-not$process.WaitForExit(120000)){$process.Kill($true);throw "Portable no-MIR test timeout: $run"}
  $output=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
  $output|Set-Content (Join-Path $run ('engine-'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.log'))
  if($process.ExitCode -ne 0){throw "Portable no-MIR engine failed: $run`n$($output.Substring([Math]::Max(0,$output.Length-2500)))"}
 } finally {$process.Dispose()}
}
$save=Join-Path $run 'probe.zip'
Invoke-PortableEngine @('--create',$save)
Invoke-PortableEngine @('--benchmark',$save,'--benchmark-ticks','3','--benchmark-runs','1')
$resultPath=Join-Path $run 'userdata/script-output/portable-research-surface-no-mir.json'
if(-not(Test-Path $resultPath)){throw "No portable no-MIR result: $run"}
$result=Get-Content -Raw $resultPath|ConvertFrom-Json
if($result.status -ne 'passed'){throw "Portable no-MIR acceptance failed: $resultPath"}
if([string]$result.engine -cne '2.1.17'){throw "Portable no-MIR fixture requires Steam F210 2.1.17, received $($result.engine)."}
$result|Add-Member core_sha256 (Get-FileHash $coreSource).Hash
$result|Add-Member factorio_catalogue_adapter_sha256 (Get-FileHash $adapterSource).Hash
$result|Add-Member fixture_control_sha256 (Get-FileHash (Join-Path $fixtureSource 'control.lua')).Hash
$result|Add-Member fixture_data_sha256 (Get-FileHash (Join-Path $fixtureSource 'data.lua')).Hash
$result|Add-Member harness_sha256 (Get-FileHash $PSCommandPath).Hash
$result|Add-Member engine_sha256 (Get-FileHash $engine).Hash
$result|Add-Member package_excluded $true
$result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $run 'result.json')
$result|ConvertTo-Json -Depth 6
Write-Output "Evidence: $run"
