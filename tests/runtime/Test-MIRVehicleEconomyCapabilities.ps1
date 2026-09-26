# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path,
  [ValidateSet('2.0','2.1')][string]$Target = '2.1',
  [string]$FactorioBin = '',
  [ValidateRange(30,180)][int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
if ([string]::IsNullOrWhiteSpace($FactorioBin)) {
  $FactorioBin = if ($Target -ceq '2.0') { 'D:\Programs\Factorio\2.0\bin\x64\factorio.exe' } else { 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' }
}
$engine = (Resolve-Path -LiteralPath $FactorioBin).Path
$engineVersion = (& $engine --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $engineVersion -notmatch ('Version: ' + [regex]::Escape($Target) + '[.]')) { throw "Engine line does not match requested target: $engineVersion" }

$fixtureSource = Join-Path $repo 'tests/runtime/vehicle_economy_capabilities.lua'
$carControlSource = Join-Path $repo 'tests/runtime/optional_runtime_services.lua'
foreach ($path in @($fixtureSource, $carControlSource)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required controlled input missing: $path" } }
$fixtureHashBefore = (Get-FileHash -LiteralPath $fixtureSource -Algorithm SHA256).Hash
$carControlHashBefore = (Get-FileHash -LiteralPath $carControlSource -Algorithm SHA256).Hash
$harnessHashBefore = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
$engineHashBefore = (Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash

$apiPath = if ($Target -ceq '2.0') { 'D:\Programs\Factorio\2.0\doc-html\runtime-api.json' } else { 'C:\Program Files\Steam\steamapps\common\Factorio\doc-html\runtime-api.json' }
$apiHashBefore = (Get-FileHash -LiteralPath $apiPath -Algorithm SHA256).Hash
$api = Get-Content -Raw -LiteralPath $apiPath | ConvertFrom-Json -Depth 100
$entityClass = @($api.classes | Where-Object { $_.name -ceq 'LuaEntity' })
if ($entityClass.Count -ne 1) { throw 'Installed runtime API has no unique LuaEntity record.' }
$controlClass = @($api.classes | Where-Object { $_.name -ceq 'LuaControl' })
if ($controlClass.Count -ne 1 -or [string]$entityClass[0].parent -cne 'LuaControl') { throw 'Installed runtime API does not establish LuaEntity as a LuaControl.' }
$ridingState = @($controlClass[0].attributes | Where-Object { $_.name -ceq 'riding_state' })
if ($ridingState.Count -ne 1 -or [string]$ridingState[0].write_type -cne 'RidingState') { throw 'Installed runtime API does not expose writable LuaControl.riding_state.' }
$apiAttributes = [ordered]@{}
foreach ($name in @('consumption_modifier','effectivity_modifier','burner','speed','train')) {
  $attribute = @($entityClass[0].attributes | Where-Object { $_.name -ceq $name })
  if ($attribute.Count -ne 1) { throw "Installed runtime API has no unique LuaEntity.$name record." }
  $apiAttributes[$name] = [ordered]@{ read_type = $attribute[0].read_type; write_type = $attribute[0].write_type; optional = [bool]$attribute[0].optional }
}
foreach ($name in @('consumption_modifier','effectivity_modifier')) {
  if ([string]$apiAttributes[$name].write_type -ne 'float') { throw "Installed runtime API does not expose writable LuaEntity.$name." }
}
$apiMethods = [ordered]@{}
foreach ($name in @('set_driver','get_driver','get_fuel_inventory')) {
  $method = @($entityClass[0].methods | Where-Object { $_.name -ceq $name })
  if ($method.Count -ne 1) { throw "Installed runtime API has no unique LuaEntity.$name method." }
  $apiMethods[$name] = [ordered]@{ present = $true; parameters = @($method[0].parameters) }
}
$apiControl = [ordered]@{ lua_entity_parent = [string]$entityClass[0].parent; riding_state = [ordered]@{ read_type = $ridingState[0].read_type; write_type = $ridingState[0].write_type }; entity_methods = $apiMethods }
$checkoutHeadContext = (& git -C $repo rev-parse HEAD).Trim()

$run = Join-Path $repo ('build/tmp/mir42-vehicle-economy/' + [guid]::NewGuid().ToString('N').Substring(0, 12))
$mods = Join-Path $run 'mods'
$fixture = Join-Path $mods 'mir-vehicle-economy-capability_1.0.0'
New-Item -ItemType Directory -Force -Path $fixture | Out-Null
[ordered]@{ name = 'mir-vehicle-economy-capability'; version = '1.0.0'; title = 'MIR private vehicle economy capability'; author = 'MIR'; factorio_version = $Target; dependencies = @('base') } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixture 'info.json') -Encoding utf8
Copy-Item -LiteralPath $fixtureSource -Destination (Join-Path $fixture 'control.lua')
Copy-Item -LiteralPath $carControlSource -Destination (Join-Path $fixture 'optional_runtime_services.lua')
$official = @('base','elevated-rails','quality','recycler','space-age')
[ordered]@{ mods = @($official | ForEach-Object { [ordered]@{ name = $_; enabled = ($_ -ceq 'base') } }) + @([ordered]@{ name = 'mir-vehicle-economy-capability'; enabled = $true }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $mods 'mod-list.json') -Encoding utf8
$engineRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $engine))
@('[path]', "read-data=$($engineRoot.Replace('\','/'))/data", "write-data=$($run.Replace('\','/'))/userdata", '[other]', 'disable-blueprint-storage=true', 'enable-blueprint-storage-cloud-sync=false', 'check-updates=false') | Set-Content -LiteralPath (Join-Path $run 'config.ini') -Encoding utf8

function Invoke-VehicleCapabilityEngine([string]$Phase, [string[]]$Arguments) {
  $start = [Diagnostics.ProcessStartInfo]::new($engine)
  $start.UseShellExecute = $false; $start.CreateNoWindow = $true; $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
  $start.Environment['SteamAppId'] = '427520'; $start.Environment['SteamGameId'] = '427520'
  foreach ($argument in @('--config', (Join-Path $run 'config.ini'), '--mod-directory', $mods, '--disable-audio') + $Arguments) { [void]$start.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::Start($start)
  $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
  try {
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
      try { $process.Kill($true) } catch { $process.Kill() }
      [void]$process.WaitForExit(10000)
    }
    $text = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
    [IO.File]::WriteAllText((Join-Path $run ($Phase + '.log')), $text, [Text.UTF8Encoding]::new($false))
    if ($timedOut) { throw "VEH-02 $Phase timed out after $TimeoutSeconds seconds; drained output is retained: $run" }
    if ($process.ExitCode -ne 0 -or $text -match 'non-recoverable error|Exception at tick|Error while running event|Failed to load mods') { throw "VEH-02 $Phase failed: $run`n$($text.Substring([Math]::Max(0, $text.Length - 3000)))" }
  } finally { $process.Dispose() }
}

$save = Join-Path $run 'vehicle-capability.zip'
Invoke-VehicleCapabilityEngine 'create' @('--create', $save)
Invoke-VehicleCapabilityEngine 'probe' @('--benchmark', $save, '--benchmark-ticks', '360', '--benchmark-runs', '1')
$resultPath = Join-Path $run 'userdata/script-output/vehicle-economy-capabilities.json'
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { throw "VEH-02 produced no result: $run" }
$result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json -Depth 100
if ($result.status -cne 'passed') { throw "VEH-02 fixture did not pass: $run" }
if ($null -eq $result.vehicles.car -or -not [bool]$result.vehicles.car.engine_native_mapping) { throw "VEH-02 Car positive control did not establish its controlled native mapping: $run" }
foreach ($name in @('spider-vehicle','locomotive')) {
  if ($null -eq $result.vehicles.$name -or [string]$result.vehicles.$name.decision -notin @('measured-native-mapping','not-admitted-by-this-probe')) { throw "VEH-02 has no explicit $name disposition: $run" }
}
$engineHashAfter = (Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash
$apiHashAfter = (Get-FileHash -LiteralPath $apiPath -Algorithm SHA256).Hash
if ((Get-FileHash -LiteralPath $fixtureSource -Algorithm SHA256).Hash -cne $fixtureHashBefore -or (Get-FileHash -LiteralPath $carControlSource -Algorithm SHA256).Hash -cne $carControlHashBefore -or (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash -cne $harnessHashBefore) { throw 'Controlled VEH-02 inputs changed during execution.' }
if ($engineHashAfter -cne $engineHashBefore -or $apiHashAfter -cne $apiHashBefore) { throw 'Installed Factorio engine or API record changed during VEH-02 execution.' }
$result | Add-Member -NotePropertyName target -NotePropertyValue $Target
$result | Add-Member -NotePropertyName engine -NotePropertyValue $engineVersion
$result | Add-Member -NotePropertyName engine_sha256 -NotePropertyValue ([ordered]@{ before = $engineHashBefore; after = $engineHashAfter })
$result | Add-Member -NotePropertyName runtime_api -NotePropertyValue ([ordered]@{ path = $apiPath; sha256_before = $apiHashBefore; sha256_after = $apiHashAfter; application_version = $api.application_version; api_version = $api.api_version; lua_entity = $apiAttributes; normal_driving = $apiControl })
$result | Add-Member -NotePropertyName fixture_sha256 -NotePropertyValue $fixtureHashBefore
$result | Add-Member -NotePropertyName car_control_sha256 -NotePropertyValue $carControlHashBefore
$result | Add-Member -NotePropertyName harness_sha256 -NotePropertyValue $harnessHashBefore
$result | Add-Member -NotePropertyName execution_context -NotePropertyValue ([ordered]@{ checkout_head_context = $checkoutHeadContext; controlled_harness_state = 'uncommitted-snapshot-explicitly-hash-bound'; candidate_or_player_package = $false })
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
$result | ConvertTo-Json -Depth 20
Write-Output "Evidence: $run"
