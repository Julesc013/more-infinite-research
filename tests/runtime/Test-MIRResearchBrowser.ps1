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
} else {
 $candidateInput=if([IO.Path]::IsPathRooted($CandidateZip)) { $CandidateZip } else { Join-Path $repo $CandidateZip }
 $candidate=(Resolve-Path -LiteralPath $candidateInput).Path
}
$archive=[IO.Compression.ZipFile]::OpenRead($candidate)
try {
 $infoEntries=@($archive.Entries | Where-Object FullName -Like '*/info.json')
 if($infoEntries.Count -ne 1) { throw 'Browser candidate requires one mod identity.' }
 $infoReader=[IO.StreamReader]::new($infoEntries[0].Open())
 try { $info=$infoReader.ReadToEnd() | ConvertFrom-Json } finally { $infoReader.Dispose() }
 if([string]$info.name -cne 'more-infinite-research' -or [string]$info.factorio_version -cne $Target) {
  throw "Browser candidate target mismatch: requested $Target, archive declares $($info.factorio_version)."
 }
 foreach($name in @('research_browser.lua','research_browser_core.lua','research_browser_factorio_catalogue.lua','research_browser_mir_provider.lua','research_browser_actions.lua')) {
  $entry=@($archive.Entries | Where-Object FullName -Like "*/prototypes/mir/runtime/$name")
  if($entry.Count -ne 1) { throw "Candidate must contain exactly one $name." }
  $stream=$entry[0].Open()
  try { $moduleHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) } finally { $stream.Dispose() }
  if($moduleHash -cne (Get-FileHash (Join-Path $repo "source/prototypes/mir/runtime/$name")).Hash) { throw "Candidate $name differs from the controlled source under test." }
 }
} finally { $archive.Dispose() }
$versionStart=[Diagnostics.ProcessStartInfo]::new($engine)
$versionStart.UseShellExecute=$false; $versionStart.CreateNoWindow=$true; $versionStart.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
$versionStart.RedirectStandardOutput=$true; $versionStart.RedirectStandardError=$true
$versionStart.Environment['SteamAppId']='427520'; $versionStart.Environment['SteamGameId']='427520'
$versionStart.ArgumentList.Add('--version')
$versionProcess=[Diagnostics.Process]::Start($versionStart)
try {
 $versionOutput=$versionProcess.StandardOutput.ReadToEndAsync(); $versionError=$versionProcess.StandardError.ReadToEndAsync()
 if(-not $versionProcess.WaitForExit(10000)) { $versionProcess.Kill($true); $versionProcess.WaitForExit(); throw 'Browser engine version query timed out.' }
 $engineVersionText=$versionOutput.GetAwaiter().GetResult()
 $versionError.GetAwaiter().GetResult() | Out-Null
 $versionExitCode=$versionProcess.ExitCode
} finally { $versionProcess.Dispose() }
if($versionExitCode -ne 0 -or $engineVersionText -notmatch '(?m)^Version:\s*(?<version>[0-9]+\.[0-9]+\.[0-9]+)') {
 throw 'Browser test cannot identify the selected engine version.'
}
$selectedEngineVersion=[string]$Matches.version
if(-not $selectedEngineVersion.StartsWith($Target + '.', [StringComparison]::Ordinal)) {
 throw "Browser engine target mismatch: requested $Target, selected engine is $selectedEngineVersion."
}
$run=Join-Path $repo ('build/browser-tests/'+[guid]::NewGuid().ToString('N').Substring(0,8))
$fixture=Join-Path $run 'mods/mir-browser-test_1.0.0'
New-Item -ItemType Directory -Force $fixture | Out-Null
Copy-Item -LiteralPath $candidate -Destination (Join-Path $run 'mods')
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
$browserTestText=[IO.File]::ReadAllText((Join-Path $repo 'tests/runtime/research_browser.lua'))
if(([regex]::Matches($browserTestText,[regex]::Escape('local force=game.forces.player'))).Count -ne 1) { throw 'Browser omission checks require one unambiguous controlled force entry.' }
[void]$lua.AppendLine($browserTestText.Replace('local force=game.forces.player', 'check_omissions(check); local force=game.forces.player'))
[IO.File]::WriteAllText((Join-Path $fixture 'control.lua'),$lua.ToString(),[Text.UTF8Encoding]::new($false))
@{mods=@(@{name='base';enabled=$true},@{name='space-age';enabled=$false},@{name='elevated-rails';enabled=$false},@{name='quality';enabled=$false},@{name='recycler';enabled=$false},@{name='more-infinite-research';enabled=$true},@{name='mir-browser-test';enabled=$true})} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $run 'mods/mod-list.json')
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent) -Parent) -Parent
# This fixture exercises research/GUI state, not the player's blueprint library.
# Keep Steam from copying that library into each isolated acceptance directory.
"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($run.Replace('\','/'))/userdata`n[other]`ndisable-blueprint-storage=true`nenable-blueprint-storage-cloud-sync=false`n[graphics]`nfull-screen=false`ncache-sprite-atlas=false`n" | Set-Content (Join-Path $run 'config.ini')
$save=Join-Path $run 'probe.zip'
function Invoke-BrowserEngine([string[]]$Arguments) {
 $start=[Diagnostics.ProcessStartInfo]::new($engine)
 $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
 $start.Environment["SteamAppId"]="427520"; $start.Environment["SteamGameId"]="427520"
 $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
 $graphicsArguments=if($Arguments -contains '--benchmark-graphics') { @('--force-graphics-preset','low','--video-memory-usage','low','--single-thread-loading') } else { @() }
 foreach($arg in @('--config',(Join-Path $run 'config.ini'),'--mod-directory',(Join-Path $run 'mods'))+$graphicsArguments+$Arguments) { $start.ArgumentList.Add($arg) }
 $process=[Diagnostics.Process]::Start($start)
 $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
 try {
  if(-not $process.WaitForExit(120000)) { $process.Kill($true); throw "Browser test timeout: $run" }
  $result=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
  $engineLog=Join-Path $run ('engine-'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.log')
  $result | Set-Content $engineLog
  $exitCode=$process.ExitCode
  if($exitCode -ne 0) { throw "Browser engine failed: phase=$($Arguments[0]); exit_code=$exitCode; log=$engineLog`n$($result.Substring([Math]::Max(0,$result.Length-2500)))" }
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
if([string]$result.engine -cne $selectedEngineVersion) { throw 'Browser native result does not match the selected engine.' }
$result | Add-Member package_sha256 (Get-FileHash $candidate).Hash
$result | Add-Member engine_sha256 (Get-FileHash $engine).Hash
$result | Add-Member core_sha256 (Get-FileHash (Join-Path $repo 'source/prototypes/mir/runtime/research_browser_core.lua')).Hash
$result | Add-Member host_sha256 (Get-FileHash (Join-Path $repo 'source/prototypes/mir/runtime/research_browser.lua')).Hash
$result | Add-Member provider_sha256 (Get-FileHash (Join-Path $repo 'source/prototypes/mir/runtime/research_browser_mir_provider.lua')).Hash
$result | Add-Member catalogue_adapter_sha256 (Get-FileHash (Join-Path $repo 'source/prototypes/mir/runtime/research_browser_factorio_catalogue.lua')).Hash
$result | Add-Member action_predicate_sha256 (Get-FileHash (Join-Path $repo 'source/prototypes/mir/runtime/research_browser_actions.lua')).Hash
$result | Add-Member harness_sha256 (Get-FileHash $PSCommandPath).Hash
$result | Add-Member fixture_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/browser_fixture_data.lua')).Hash
$result | Add-Member test_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/research_browser.lua')).Hash
$result | Add-Member omission_test_sha256 (Get-FileHash (Join-Path $repo 'tests/runtime/research_browser_omissions.lua')).Hash
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
