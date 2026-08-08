param(
  [Parameter(Mandatory)][string]$Release,
  [Parameter(Mandatory)][string]$FactorioBin,
  [string]$RepoRoot = "",
  [string]$OutputPath = "",
  [string]$WorkRoot = "",
  [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
if (-not $OutputPath) { $OutputPath = Join-Path $RepoRoot ".mir\evidence\terminal\baselines\$Release-engine-observation.json" }
if (-not $WorkRoot) { $WorkRoot = Join-Path $RepoRoot "build\terminal\engine-observations\$Release" }

. (Join-Path $RepoRoot "tools\lib\terminal\TerminalEngineObservation.ps1")
. (Join-Path $RepoRoot "tools\lib\assurance\Core.ps1")

function Write-MIRTerminalJson([string]$Path, $Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $json = (($Value | ConvertTo-Json -Depth 100) -replace "`r`n", "`n") + "`n"
  [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Write-MIRTerminalText([string]$Path, [string]$Value) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}

$wavePath = Join-Path $RepoRoot "docs\releases\archive\MIR-3.5-WAVE-INDEX.json"
$verificationPath = Join-Path $RepoRoot "docs\releases\archive\MIR-3.5-PUBLIC-ASSET-VERIFICATION.json"
$queuePath = Join-Path $RepoRoot ".mir\releases\terminal\MIR3-Terminal-Baseline-Capture-QueueV1.json"
$wave = Get-Content -Raw -LiteralPath $wavePath | ConvertFrom-Json -Depth 100
$verification = Get-Content -Raw -LiteralPath $verificationPath | ConvertFrom-Json -Depth 100
$queue = Get-Content -Raw -LiteralPath $queuePath | ConvertFrom-Json -Depth 100
$waveRows = @($wave.releases | Where-Object version -eq $Release)
$verifyRows = @($verification.releases | Where-Object version -eq $Release)
$queueRows = @($queue.rows | Where-Object baseline_release -eq $Release)
if ($waveRows.Count -ne 1 -or $verifyRows.Count -ne 1 -or $queueRows.Count -ne 1) {
  throw "Release is not one exact terminal .5 baseline: $Release"
}
$waveRow = $waveRows[0]
$verifyRow = $verifyRows[0]
$queueRow = $queueRows[0]
$zipPath = Join-Path $RepoRoot ([string]$waveRow.dist)
$zipSha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
if ($zipSha256 -ne [string]$waveRow.archive_sha256) { throw "Frozen public ZIP identity mismatch for $Release." }
$factorioPath = (Resolve-Path -LiteralPath $FactorioBin).Path
$factorioSha256 = (Get-FileHash -LiteralPath $factorioPath -Algorithm SHA256).Hash
if ($factorioSha256 -ne [string]$verifyRow.factorio_executable_sha256) { throw "Exact engine identity mismatch for $Release." }

$resolvedBuild = (Resolve-Path -LiteralPath (Join-Path $RepoRoot "build")).Path.TrimEnd('\') + '\'
if (Test-Path -LiteralPath $WorkRoot) {
  $resolvedWork = (Resolve-Path -LiteralPath $WorkRoot).Path
  if (-not $resolvedWork.StartsWith($resolvedBuild, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to replace engine-observation work outside build/."
  }
  Remove-Item -LiteralPath $resolvedWork -Recurse -Force
}
$userRoot = Join-Path $WorkRoot "user"
$modsRoot = Join-Path $userRoot "mods"
New-Item -ItemType Directory -Force -Path $modsRoot | Out-Null
Copy-Item -LiteralPath $zipPath -Destination (Join-Path $modsRoot ([IO.Path]::GetFileName($zipPath)))
$observerName = "mir-terminal-observer"
$observerRoot = Join-Path $modsRoot "$observerName`_1.0.0"
New-Item -ItemType Directory -Force -Path $observerRoot | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$publicZip = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
  $infoEntry = @($publicZip.Entries | Where-Object FullName -like "*/info.json")
  if ($infoEntry.Count -ne 1) { throw "Frozen public ZIP does not contain one info.json." }
  $reader = [IO.StreamReader]::new($infoEntry[0].Open(), [Text.UTF8Encoding]::new($false), $true)
  try { $publicInfo = $reader.ReadToEnd() | ConvertFrom-Json -Depth 20 } finally { $reader.Dispose() }
} finally { $publicZip.Dispose() }
$observerInfo = [ordered]@{name=$observerName;version="1.0.0";title="MIR terminal read-only observer";author="MIR release assurance";description="Package-excluded read-only terminal baseline observer.";dependencies=@("base", "more-infinite-research")}
if ($publicInfo.PSObject.Properties["factorio_version"]) { $observerInfo.factorio_version = [string]$publicInfo.factorio_version }
Write-MIRTerminalJson (Join-Path $observerRoot "info.json") $observerInfo
$declaredPath = Join-Path $RepoRoot ".mir\releases\terminal\baselines\$Release\declared\technologies.json"
$declared = Get-Content -Raw -LiteralPath $declaredPath | ConvertFrom-Json -Depth 100
$technologyNames = @($declared.items | ForEach-Object {
  $attribute = @($_.attributes | Where-Object name -eq "generated_technology")
  if ($attribute.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace([string]$attribute[0].value)) { [string]$attribute[0].value }
} | Sort-Object -Unique)
$nameRows = @($technologyNames | ForEach-Object { '  ["' + $_.Replace('"','\"') + '"] = true,' })
Write-MIRTerminalText (Join-Path $observerRoot "names.lua") ("return {`n" + ($nameRows -join "`n") + "`n}`n")
$observerLua = @'
local names = require("names")
local function field(value)
  if value == nil then return "<nil>" end
  local text = tostring(value)
  text = string.gsub(text, "\\", "\\\\")
  text = string.gsub(text, "\t", "\\t")
  text = string.gsub(text, "\r", "\\r")
  text = string.gsub(text, "\n", "\\n")
  return text
end
local function joined(values)
  local result = {}
  for _, value in ipairs(values or {}) do result[#result + 1] = field(value) end
  table.sort(result)
  return table.concat(result, string.char(31))
end
local function emit(...)
  local parts = {}
  for index = 1, select("#", ...) do parts[index] = field(select(index, ...)) end
  log(table.concat(parts, "\t"))
end
local observed = 0
local effects = 0
for name, _ in pairs(names) do
  local technology = data.raw.technology and data.raw.technology[name]
  if technology then
    local effect_rows = technology.effects or {}
    emit("MIR_TERMINAL_TECH", name, technology.enabled, technology.hidden, technology.upgrade, technology.max_level, joined(technology.prerequisites), serpent.line(technology.unit, {comment=false}), #effect_rows)
    observed = observed + 1
    for index, effect in ipairs(effect_rows) do
      emit("MIR_TERMINAL_EFFECT", name, index, effect.type, effect.technology or effect.recipe or effect.ammo_category or effect.turret_id or effect.modifier, serpent.line(effect, {comment=false}))
      effects = effects + 1
    end
  end
end
emit("MIR_TERMINAL_DATA_COMPLETE", observed, effects)
'@
Write-MIRTerminalText (Join-Path $observerRoot "data-final-fixes.lua") ($observerLua + "`n")
$settingsLua = @'
local function field(value)
  if value == nil then return "<nil>" end
  local text = tostring(value)
  text = string.gsub(text, "\\", "\\\\")
  text = string.gsub(text, "\t", "\\t")
  text = string.gsub(text, "\r", "\\r")
  text = string.gsub(text, "\n", "\\n")
  return text
end
local function joined(values)
  local result = {}
  for _, value in ipairs(values or {}) do result[#result + 1] = field(value) end
  return table.concat(result, string.char(31))
end
local function emit(...)
  local parts = {}
  for index = 1, select("#", ...) do parts[index] = field(select(index, ...)) end
  log(table.concat(parts, "\t"))
end
local observed = 0
for _, prototype_type in ipairs({"bool-setting", "double-setting", "int-setting", "string-setting"}) do
  local rows = data.raw[prototype_type] or {}
  local keys = {}
  for name, _ in pairs(rows) do if string.sub(name, 1, 4) == "mir-" then keys[#keys + 1] = name end end
  table.sort(keys)
  for _, name in ipairs(keys) do
    local setting = rows[name]
    emit("MIR_TERMINAL_SETTING", prototype_type, name, setting.setting_type, setting.default_value, setting.minimum_value, setting.maximum_value, joined(setting.allowed_values), setting.hidden, setting.order)
    observed = observed + 1
  end
end
emit("MIR_TERMINAL_SETTINGS_COMPLETE", observed)
'@
Write-MIRTerminalText (Join-Path $observerRoot "settings-final-fixes.lua") ($settingsLua + "`n")
$modList = [ordered]@{mods=@([ordered]@{name="base";enabled=$true},[ordered]@{name="more-infinite-research";enabled=$true},[ordered]@{name=$observerName;enabled=$true})}
Write-MIRTerminalJson (Join-Path $modsRoot "mod-list.json") $modList

$installation = Get-MIRAssuranceFactorioInstallationFingerprint -FactorioPath $factorioPath
$readData = Join-Path ([string]$installation.root) "data"
$configPath = Join-Path $WorkRoot "factorio-config.ini"
$config = "; Generated by MIR terminal exact-engine observation.`n[path]`nread-data=$($readData.Replace('\','/'))`nwrite-data=$($userRoot.Replace('\','/'))`n`n[general]`nlocale=auto`n`n[other]`nenable-steam-networking=false`ndisable-blueprint-storage=true`n"
[IO.File]::WriteAllText($configPath, $config, [Text.UTF8Encoding]::new($false))

$stdoutPath = Join-Path $WorkRoot "stdout.txt"
$stderrPath = Join-Path $WorkRoot "stderr.txt"
$processInfo = [Diagnostics.ProcessStartInfo]::new()
$processInfo.FileName = $factorioPath
$processInfo.UseShellExecute = $false
$processInfo.CreateNoWindow = $true
$processInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$savePath = Join-Path $WorkRoot "terminal-observation.zip"
foreach ($argument in @("--config", $configPath, "--no-log-rotation", "--mod-directory", $modsRoot, "--create", $savePath)) {
  [void]$processInfo.ArgumentList.Add($argument)
}
$process = [Diagnostics.Process]::Start($processInfo)
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
  try { $process.Kill($true) } catch { $process.Kill() }
  throw "Factorio observer load timed out after $TimeoutSeconds seconds for $Release."
}
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
[IO.File]::WriteAllText($stdoutPath, $stdout, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($stderrPath, $stderr, [Text.UTF8Encoding]::new($false))
if ($process.ExitCode -ne 0) { throw "Factorio observer load failed for $Release with exit code $($process.ExitCode): $stderr $stdout" }
if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) { throw "Factorio observer did not create the expected save for $Release." }
$logPath = Join-Path $userRoot "factorio-current.log"
if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { throw "Factorio observer did not produce a log for $Release." }
$evidenceRelative = [IO.Path]::GetRelativePath($RepoRoot, $OutputPath).Replace('\','/')
$logLines = @(Get-Content -LiteralPath $logPath)
$inventory = Get-MIRTerminalEngineInventoryFromLog -Lines $logLines -Release $Release -Target ([string]$queueRow.target) -EvidencePath $evidenceRelative
$semanticMaterial = [ordered]@{technologies=$inventory.technologies;effects_and_owners=$inventory.effects_and_owners;settings=$inventory.settings;data_complete=$inventory.data_complete;settings_complete=$inventory.settings_complete}
$semanticJson = ($semanticMaterial | ConvertTo-Json -Depth 100 -Compress)
$semanticSha256 = Get-MIRAssuranceTextHash -Text $semanticJson
$record = [ordered]@{
  schema=1; kind="MIR3TerminalEngineObservationV1"; release=$Release; target=[string]$queueRow.target;
  archive_sha256=$zipSha256; executable_sha256=$factorioSha256;
  official_data_file_count=[int]$installation.official_data.file_count;
  official_data_sha256=[string]$installation.official_data.sha256;
  installation_sha256=[string]$installation.installation_sha256;
  semantic_observation_sha256=$semanticSha256; mode="base-only-read-only-observer-after-data-final-fixes";
  technologies=@($inventory.technologies); effects_and_owners=@($inventory.effects_and_owners); settings=@($inventory.settings);
  capability_omissions=@(
    [ordered]@{field="runtime-save-state";reason="Data-stage dump cannot observe per-save runtime state."},
    $(if ($inventory.settings_complete) { $null } else { [ordered]@{field="setting-prototype-stage";reason="The exact target engine did not execute settings-final-fixes.lua; setting prototypes are an explicit engine-capability omission."} }),
    [ordered]@{field="optional-mod-compatibility-realization";reason="Base-only observation does not substitute for named ecosystem closures."}
  )
}
$record.capability_omissions = @($record.capability_omissions | Where-Object { $null -ne $_ })
Write-MIRTerminalJson $OutputPath $record
[pscustomobject][ordered]@{release=$Release;output=(Resolve-Path -LiteralPath $OutputPath).Path;technologies=@($inventory.technologies).Count;effects=@($inventory.effects_and_owners).Count;settings=@($inventory.settings).Count;archive_sha256=$zipSha256;engine_sha256=$factorioSha256;official_data_sha256=[string]$installation.official_data.sha256} | ConvertTo-Json -Depth 10
