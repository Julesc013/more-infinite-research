param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$CampaignPath = ".mir\performance-campaign.json",
  [string]$Candidate = "dist\more-infinite-research_3.2.0.zip",
  [string]$PriorRelease = "dist\more-infinite-research_3.1.9.zip",
  [string]$FactorioBin = $env:FACTORIO_BIN,
  [Parameter(Mandatory)][string]$ExpectedSourceCommit,
  [string]$LocalModZipDir = "C:\Projects\Factorio\testmods_2.1",
  [string]$OutputPath = ".mir\evidence\3.2.0-performance-regression.json",
  [string]$ArtifactRoot = "",
  [ValidateRange(1, 10)][int]$WarmupRuns = 1,
  [ValidateRange(5, 25)][int]$MeasuredRuns = 5,
  [switch]$ProbeSmokeOnly
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "validation\ReleaseAttestations.ps1")
. (Join-Path $PSScriptRoot "validation\PerformanceCampaign.ps1")

function Resolve-MIRCampaignPath {
  param([Parameter(Mandatory)][string]$Path)
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  return [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Get-MIRCampaignSafeName {
  param([Parameter(Mandatory)][string]$Value)
  return ($Value -replace '[^A-Za-z0-9_.-]', '-').Trim('-')
}

function Get-MIRCampaignTreeSha256 {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string[]]$RelativeRoots
  )
  $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
  $rows = @()
  foreach ($relativeRoot in @($RelativeRoots | Sort-Object -Unique)) {
    $path = Join-Path $resolvedRoot $relativeRoot
    if (-not (Test-Path -LiteralPath $path)) { throw "Performance authority is absent: $path" }
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $rows += ("{0}`t{1}" -f $relativeRoot.Replace("\", "/"), (Get-MIRFileSha256 -Path $path))
      continue
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $path -Recurse -File | Sort-Object FullName)) {
      $relative = [IO.Path]::GetRelativePath($resolvedRoot, $file.FullName).Replace("\", "/")
      $rows += ("{0}`t{1}`t{2}" -f $relative, $file.Length, (Get-MIRFileSha256 -Path $file.FullName))
    }
  }
  return Get-MIRStringSha256 -Value ($rows -join "`n")
}

function Get-MIRCampaignMachineSha256 {
  $parts = @(
    "os=$([Environment]::OSVersion.VersionString)",
    "arch=$([Runtime.InteropServices.RuntimeInformation]::OSArchitecture)",
    "process_arch=$([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture)",
    "logical_processors=$([Environment]::ProcessorCount)",
    "powershell=$($PSVersionTable.PSVersion)"
  )
  try {
    $cpu = @(Get-CimInstance Win32_Processor -ErrorAction Stop | Sort-Object DeviceID)
    foreach ($row in $cpu) {
      $parts += "cpu=$($row.Manufacturer)|$($row.Name)|$($row.NumberOfCores)|$($row.NumberOfLogicalProcessors)"
    }
    $system = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $parts += "memory=$([uint64]$system.TotalPhysicalMemory)"
  } catch {
    $parts += "hardware-query=unavailable"
  }
  return Get-MIRStringSha256 -Value ($parts -join "`n")
}

function Assert-MIRCampaignPackage {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Authority,
    [Parameter(Mandatory)][string]$Label
  )
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label archive is absent: $Path" }
  $info = Get-MIRReleasePackageInfo -Path $Path
  $archiveSha = Get-MIRReleaseSha256 -Path $Path
  $contentSha = Get-MIRReleaseArchiveContentSha256 -Path $Path
  if ([string]$info.version -ne [string]$Authority.version -or
      $archiveSha -ne [string]$Authority.archive_sha256 -or
      $contentSha -ne [string]$Authority.package_content_sha256) {
    throw "$Label archive does not match the governed performance-campaign authority."
  }
  return [pscustomobject][ordered]@{
    version = [string]$info.version
    archive_sha256 = $archiveSha
    package_content_sha256 = $contentSha
  }
}

function New-MIRCampaignSettingsOverrideMod {
  param(
    [Parameter(Mandatory)][string]$ModsDir,
    [Parameter(Mandatory)]$Settings
  )
  $properties = @($Settings.PSObject.Properties | Sort-Object Name)
  if ($properties.Count -eq 0) { return $false }
  $modDir = Join-Path $ModsDir "mir-performance-settings-overrides"
  New-Item -ItemType Directory -Force -Path $modDir | Out-Null
  [ordered]@{
    name = "mir-performance-settings-overrides"
    version = "0.1.0"
    title = "MIR Performance Settings Overrides"
    author = "MIR performance harness"
    factorio_version = "2.1"
    dependencies = @("more-infinite-research")
  } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $modDir "info.json") -Encoding UTF8
  $lines = @(
    'local function override(name, value)',
    '  for _, prototype_type in ipairs({"bool-setting", "string-setting", "int-setting", "double-setting"}) do',
    '    local prototype = data.raw[prototype_type] and data.raw[prototype_type][name]',
    '    if prototype then prototype.default_value = value; return end',
    '  end',
    '  error("MIR performance override references missing startup setting " .. name)',
    'end'
  )
  foreach ($property in $properties) {
    $name = ([string]$property.Name).Replace("\", "\\").Replace('"', '\"')
    $value = if ($property.Value -is [bool]) {
      if ([bool]$property.Value) { "true" } else { "false" }
    } elseif ($property.Value -is [string]) {
      '"' + ([string]$property.Value).Replace("\", "\\").Replace('"', '\"') + '"'
    } elseif ($property.Value -is [ValueType]) {
      [Convert]::ToString($property.Value, [Globalization.CultureInfo]::InvariantCulture)
    } else {
      throw "Unsupported performance startup setting type for $name."
    }
    $lines += "override(`"$name`", $value)"
  }
  $lines | Set-Content -LiteralPath (Join-Path $modDir "settings-updates.lua") -Encoding UTF8
  return $true
}

function Copy-MIRCampaignProbe {
  param([Parameter(Mandatory)][string]$ModsDir)
  $source = Join-Path $RepoRoot "fixtures\performance-regression-probe"
  if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "Performance probe fixture is absent: $source"
  }
  $destination = Join-Path $ModsDir "mir-fixture-performance-regression-probe_0.1.0"
  Copy-Item -LiteralPath $source -Destination $destination -Recurse
}

function Get-MIRCampaignProbeFromLog {
  param([Parameter(Mandatory)][string]$LogPath)
  $marker = "[MIR_PERFORMANCE_PROBE]"
  $match = Select-String -LiteralPath $LogPath -Pattern $marker -SimpleMatch | Select-Object -Last 1
  if ($null -eq $match) { throw "Performance probe marker is absent from $LogPath" }
  $offset = $match.Line.IndexOf($marker) + $marker.Length
  $probe = $match.Line.Substring($offset).Trim() | ConvertFrom-Json
  if ([int]$probe.schema -ne 1 -or [string]$probe.kind -ne "mir-performance-regression-probe") {
    throw "Performance probe contract is invalid in $LogPath"
  }
  $phaseRows = [ordered]@{}
  foreach ($phase in @("snapshot", "graph", "planning", "postconditions")) {
    $phaseRows[$phase] = [ordered]@{runs=0; seconds=0.0}
  }
  $starts = @{}
  foreach ($line in Get-Content -LiteralPath $LogPath) {
    $phaseMatch = [regex]::Match($line, '^\s*(?<timestamp>\d+(?:\.\d+)?)\s+.*\[MIR_PERFORMANCE_PHASE\]\s+(?<event>start|end)\s+(?<phase>snapshot|graph|planning|postconditions)\s+(?<sequence>\d+)\s*$')
    if (-not $phaseMatch.Success) { continue }
    $phase = $phaseMatch.Groups['phase'].Value
    $key = "$phase/$($phaseMatch.Groups['sequence'].Value)"
    $timestamp = [double]::Parse($phaseMatch.Groups['timestamp'].Value, [Globalization.CultureInfo]::InvariantCulture)
    if ($phaseMatch.Groups['event'].Value -eq 'start') {
      if ($starts.ContainsKey($key)) { throw "Duplicate performance phase start marker '$key' in $LogPath" }
      $starts[$key] = $timestamp
    } else {
      if (-not $starts.ContainsKey($key)) { throw "Unpaired performance phase end marker '$key' in $LogPath" }
      $phaseRows[$phase].runs++
      $phaseRows[$phase].seconds += [Math]::Max([double]0, $timestamp - [double]$starts[$key])
      $starts.Remove($key)
    }
  }
  if ($starts.Count -ne 0) { throw "Performance phase markers are incomplete in $LogPath" }
  foreach ($phase in @("snapshot", "graph", "planning", "postconditions")) {
    $probe.phases.$phase.runs = [int]$phaseRows[$phase].runs
    $probe.phases.$phase.seconds = [Math]::Round([double]$phaseRows[$phase].seconds, 6)
    if ([int]$probe.phases.$phase.runs -lt 1 -or [double]$probe.phases.$phase.seconds -lt 0) {
      throw "Performance probe phase '$phase' is absent or invalid in $LogPath"
    }
  }
  if ($null -ne $probe.telemetry) {
    $telemetryJson = $probe.telemetry | ConvertTo-Json -Depth 100 -Compress
    $probe.telemetry | Add-Member -NotePropertyName evidence_sha256 -NotePropertyValue (Get-MIRStringSha256 -Value $telemetryJson)
  }
  return $probe
}

function Invoke-MIRExactPackagePerformanceRun {
  param(
    [Parameter(Mandatory)]$Lane,
    [Parameter(Mandatory)][string]$PackagePath,
    [Parameter(Mandatory)][string]$RunRoot
  )
  $modsDir = Join-Path $RunRoot "mods"
  $savesDir = Join-Path $RunRoot "saves"
  New-Item -ItemType Directory -Force -Path $modsDir, $savesDir | Out-Null
  Copy-Item -LiteralPath $PackagePath -Destination (Join-Path $modsDir (Split-Path -Leaf $PackagePath)) -Force
  Copy-MIRCampaignProbe -ModsDir $modsDir
  $hasOverride = New-MIRCampaignSettingsOverrideMod -ModsDir $modsDir -Settings $Lane.settings

  $knownOfficial = @("elevated-rails", "quality", "recycler", "space-age")
  $enabledOfficial = @($Lane.official_mods | ForEach-Object { [string]$_ })
  $mods = @([ordered]@{name="base"; enabled=$true})
  foreach ($name in $knownOfficial) {
    $mods += [ordered]@{name=$name; enabled=($enabledOfficial -contains $name)}
  }
  $mods += [ordered]@{name="more-infinite-research"; enabled=$true}
  $mods += [ordered]@{name="mir-fixture-performance-regression-probe"; enabled=$true}
  if ($hasOverride) { $mods += [ordered]@{name="mir-performance-settings-overrides"; enabled=$true} }
  [ordered]@{mods=$mods} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $modsDir "mod-list.json") -Encoding UTF8

  $factorioRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $script:FactorioPath))
  $readData = Join-Path $factorioRoot "data"
  $configPath = Join-Path $RunRoot "config.ini"
  @"
; Generated by the MIR paired performance harness.
[path]
read-data=$readData
write-data=$RunRoot

[general]
locale=en

[other]
enable-steam-networking=false
disable-blueprint-storage=true
"@ | Set-Content -LiteralPath $configPath -Encoding UTF8

  $savePath = Join-Path $savesDir "performance.zip"
  $stdoutPath = Join-Path $RunRoot "factorio.log"
  $stderrPath = Join-Path $RunRoot "factorio.err.log"
  $arguments = @(
    "--config", $configPath,
    "--no-log-rotation",
    "--disable-audio",
    "--mod-directory", $modsDir,
    "--create", $savePath
  )
  $timer = [Diagnostics.Stopwatch]::StartNew()
  $process = Start-Process -FilePath $script:FactorioPath -ArgumentList $arguments -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
  if (-not $process.WaitForExit(900000)) {
    try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}
    throw "Performance run timed out: $($Lane.id)"
  }
  $timer.Stop()
  if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $savePath -PathType Leaf)) {
    $tail = if (Test-Path -LiteralPath $stdoutPath) { (Get-Content -LiteralPath $stdoutPath -Tail 30) -join "`n" } else { "log absent" }
    throw "Performance run failed for $($Lane.id), exit $($process.ExitCode).`n$tail"
  }
  $logText = Get-Content -Raw -LiteralPath $stdoutPath
  if ($logText.Contains("------------- Error -------------") -or $logText.Contains("Error Util.cpp")) {
    throw "Performance run log contains a fatal Factorio marker: $($Lane.id)"
  }
  $settings = ConvertTo-MIRPerformanceSettingsMap -Value $Lane.settings
  if ($settings.Contains("mir-debug-generation-report")) {
    $reportPresent = $logText.Contains("[more-infinite-research] Generation report start")
    if ([bool]$settings["mir-debug-generation-report"] -ne $reportPresent) {
      throw "Performance diagnostics setting was not effective for $($Lane.id)."
    }
  }
  $probe = Get-MIRCampaignProbeFromLog -LogPath $stdoutPath
  return [pscustomobject][ordered]@{
    seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 6)
    closure_rows = @()
    official_mods = $enabledOfficial
    probe = $probe
  }
}

function Get-MIRCampaignClosureRows {
  param([Parameter(Mandatory)]$CampaignEvidence, [Parameter(Mandatory)][string]$LaneId)
  $scenarios = @($CampaignEvidence.scenarios)
  if ($scenarios.Count -ne 1 -or [string]$scenarios[0].result -ne "passed" -or
      [string]$scenarios[0].process_result -ne "passed" -or [bool]$scenarios[0].timed_out) {
    throw "Compatibility performance run did not produce one passing scenario for $LaneId."
  }
  return @(
    foreach ($entry in @($scenarios[0].dependency_closure | Sort-Object name, version)) {
      if ([string]$entry.sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "Compatibility performance closure lacks a SHA-256 for $($entry.name)."
      }
      "{0}`t{1}`t{2}" -f ([string]$entry.name), ([string]$entry.version), ([string]$entry.sha256).ToUpperInvariant()
    }
  )
}

function Invoke-MIRCompatPerformanceRun {
  param(
    [Parameter(Mandatory)]$Lane,
    [Parameter(Mandatory)][string]$PackagePath,
    [Parameter(Mandatory)][string]$PackageLabel,
    [Parameter(Mandatory)][string]$RunRoot
  )
  $compatScript = Join-Path $RepoRoot "scripts\Invoke-MIRCompatAudit.ps1"
  $outputDir = Join-Path $RunRoot "compat"
  $logPath = Join-Path $RunRoot "compat-audit.log"
  $parameters = @{
    FactorioBin = $script:FactorioPath
    FactorioLine = "2.1"
    FactorioVersions = @("2.1")
    OutputDir = $outputDir
    MaxCandidates = 0
    CatalogPages = 0
    LocalModZipDirs = @($script:LocalLibraryPath)
    LocalModLibraryDirs = @($script:LocalLibraryPath)
    ModUnderTestZip = $PackagePath
    RunLoadTests = $true
    RunManualScenarios = $true
    Offline = $true
    FailFast = $true
    LinkMode = "Hardlink"
    ScenarioNames = @([string]$Lane.scenario)
    ManualScenariosPath = $script:ManualScenariosPath
  }
  if ($PackageLabel -eq "candidate") { $parameters.ModUnderTestSourceCommit = $ExpectedSourceCommit }
  $harnessTimer = [Diagnostics.Stopwatch]::StartNew()
  try {
    & $compatScript @parameters *> $logPath
  } catch {
    $harnessTimer.Stop()
    $tail = if (Test-Path -LiteralPath $logPath) { (Get-Content -LiteralPath $logPath -Tail 40) -join "`n" } else { "log absent" }
    throw "Compatibility performance run failed for $($Lane.id).`n$tail`n$($_.Exception.Message)"
  }
  $harnessTimer.Stop()
  $campaignEvidencePath = Join-Path $outputDir "campaign-evidence.json"
  if (-not (Test-Path -LiteralPath $campaignEvidencePath -PathType Leaf)) {
    throw "Compatibility performance run lacks campaign evidence for $($Lane.id)."
  }
  $campaignEvidence = Get-Content -Raw -LiteralPath $campaignEvidencePath | ConvertFrom-Json
  $closureRows = @(Get-MIRCampaignClosureRows -CampaignEvidence $campaignEvidence -LaneId ([string]$Lane.id))
  $factorioSeconds = [double]$campaignEvidence.scenarios[0].duration_seconds
  if ($factorioSeconds -le 0) {
    throw "Compatibility performance run lacks a positive Factorio process duration for $($Lane.id)."
  }
  return [pscustomobject][ordered]@{
    seconds = [Math]::Round($factorioSeconds, 6)
    harness_seconds = [Math]::Round($harnessTimer.Elapsed.TotalSeconds, 6)
    closure_rows = $closureRows
    official_mods = @($campaignEvidence.scenarios[0].official_mods)
    probe = $null
  }
}

function Invoke-MIRCampaignLaneRun {
  param(
    [Parameter(Mandatory)]$Lane,
    [Parameter(Mandatory)][ValidateSet("baseline", "candidate")][string]$PackageLabel,
    [Parameter(Mandatory)][string]$Phase,
    [Parameter(Mandatory)][int]$Index
  )
  $packagePath = if ($PackageLabel -eq "baseline") { $script:PriorPath } else { $script:CandidatePath }
  $laneSafe = Get-MIRCampaignSafeName -Value ([string]$Lane.id)
  $runRoot = Join-Path $script:RunRoot ("{0}\{1}-{2:D2}-{3}" -f $laneSafe, $Phase, $Index, $PackageLabel)
  New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
  Write-Host ("[performance] lane={0} phase={1} index={2} package={3} starting" -f $Lane.id, $Phase, $Index, $PackageLabel)
  $result = switch ([string]$Lane.runner) {
    "exact-package-load" { Invoke-MIRExactPackagePerformanceRun -Lane $Lane -PackagePath $packagePath -RunRoot $runRoot }
    "compat-audit" { Invoke-MIRCompatPerformanceRun -Lane $Lane -PackagePath $packagePath -PackageLabel $PackageLabel -RunRoot $runRoot }
    default { throw "Unknown performance runner '$($Lane.runner)' for $($Lane.id)." }
  }
  $capsule = [ordered]@{
    schema = 1
    lane = [string]$Lane.id
    scenario = [string]$Lane.scenario
    phase = $Phase
    index = $Index
    package = $PackageLabel
    package_sha256 = Get-MIRReleaseSha256 -Path $packagePath
    seconds = [double]$result.seconds
    closure_rows_sha256 = Get-MIRStringSha256 -Value (@($result.closure_rows) -join "`n")
    status = "passed"
  }
  if ($null -ne $result.probe) {
    $capsule.probe = $result.probe
  }
  $capsule | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot "run.json") -Encoding UTF8
  Write-Host ("[performance] lane={0} phase={1} index={2} package={3} seconds={4:N3} passed" -f $Lane.id, $Phase, $Index, $PackageLabel, $result.seconds)
  return $result
}

function New-MIRCampaignStatistics {
  param([Parameter(Mandatory)][double[]]$Values)
  $statistics = Get-MIRReleaseRunStatistics -Values $Values
  return [ordered]@{
    runs_seconds = @($Values | ForEach-Object { [Math]::Round([double]$_, 6) })
    median_seconds = [double]$statistics.median_seconds
    p90_seconds = [double]$statistics.p90_seconds
    minimum_seconds = [double]$statistics.minimum_seconds
    maximum_seconds = [double]$statistics.maximum_seconds
  }
}

$campaignFile = Resolve-MIRCampaignPath -Path $CampaignPath
$script:CandidatePath = Resolve-MIRCampaignPath -Path $Candidate
$script:PriorPath = Resolve-MIRCampaignPath -Path $PriorRelease
$script:FactorioPath = Resolve-MIRCampaignPath -Path $FactorioBin
$script:LocalLibraryPath = Resolve-MIRCampaignPath -Path $LocalModZipDir
$outputFile = Resolve-MIRCampaignPath -Path $OutputPath
if (-not (Test-Path -LiteralPath $campaignFile -PathType Leaf)) { throw "Performance campaign manifest is absent: $campaignFile" }
if (-not (Test-Path -LiteralPath $script:FactorioPath -PathType Leaf)) { throw "Factorio binary is absent: $script:FactorioPath" }
if (-not (Test-Path -LiteralPath $script:LocalLibraryPath -PathType Container)) { throw "Local Factorio 2.1 mod library is absent: $script:LocalLibraryPath" }
if ($ExpectedSourceCommit -notmatch '^[0-9A-Fa-f]{40}$') { throw "ExpectedSourceCommit must be a full Git commit." }

$campaign = Get-Content -Raw -LiteralPath $campaignFile | ConvertFrom-Json
if ([int]$campaign.schema -ne 2 -or [string]$campaign.release -ne "3.2.0" -or [string]$campaign.factorio_line -ne "2.1") {
  throw "Performance campaign manifest is not the governed MIR 3.2.0 Factorio 2.1 campaign."
}
$lanes = @($campaign.lanes)
$phaseLanes = @($campaign.phase_lanes)
$budgets = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\performance-budgets.json") | ConvertFrom-Json
$expectedLaneIds = @($budgets.regression_lanes.id | Sort-Object)
if (($expectedLaneIds -join "`n") -ne (@($lanes.id + $phaseLanes.id | Sort-Object) -join "`n")) {
  throw "Performance campaign lane set does not match the regression budget manifest."
}
if ($WarmupRuns -lt [int]$campaign.run_policy.warmup_runs -or $MeasuredRuns -lt [int]$campaign.run_policy.minimum_measured_runs_per_package) {
  throw "Requested performance run counts are below the governed minimum."
}

$candidateIdentity = Assert-MIRCampaignPackage -Path $script:CandidatePath -Authority $campaign.candidate -Label "Candidate"
$baselineIdentity = Assert-MIRCampaignPackage -Path $script:PriorPath -Authority $campaign.baseline -Label "Baseline"
$factorioVersion = Get-MIRFactorioBinaryVersion -Path $script:FactorioPath
if (-not $factorioVersion.StartsWith([string]$campaign.factorio_version)) {
  throw "Performance campaign requires Factorio $($campaign.factorio_version), found $factorioVersion."
}
$sourceExists = (& git -C $RepoRoot cat-file -t $ExpectedSourceCommit 2>$null) -eq "commit"
if (-not $sourceExists) { throw "Package source commit is unavailable: $ExpectedSourceCommit" }
& git -C $RepoRoot merge-base --is-ancestor $ExpectedSourceCommit HEAD
if ($LASTEXITCODE -ne 0) { throw "Package source commit is not an ancestor of the current branch." }
$packageRoots = @(Get-MIRPackageSourceRoots)
$packageChanges = @(& git -C $RepoRoot diff --name-only "$ExpectedSourceCommit..HEAD" -- @packageRoots)
if ($LASTEXITCODE -ne 0 -or $packageChanges.Count -gt 0 -or (Test-MIRPackageSourceGitDirty -RepoRoot $RepoRoot)) {
  throw "Package-visible files differ from the exact candidate source authority."
}

$manualScenariosRelative = [string]$campaign.manual_scenarios
$script:ManualScenariosPath = Resolve-MIRCampaignPath -Path $manualScenariosRelative
if (-not (Test-Path -LiteralPath $script:ManualScenariosPath -PathType Leaf)) { throw "Manual scenario authority is absent." }
if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) {
  $ArtifactRoot = "artifacts\performance\3.1.9-to-3.2.0-$((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))"
}
$script:RunRoot = Resolve-MIRCampaignPath -Path $ArtifactRoot
New-Item -ItemType Directory -Force -Path $script:RunRoot | Out-Null

if ($ProbeSmokeOnly) {
  $lane = @($lanes | Where-Object id -eq $campaign.phase_source_lane)[0]
  if ($null -eq $lane) { throw "Performance campaign phase-source lane is absent." }
  $baselineProbe = Invoke-MIRCampaignLaneRun -Lane $lane -PackageLabel baseline -Phase "probe-smoke" -Index 1
  $candidateProbe = Invoke-MIRCampaignLaneRun -Lane $lane -PackageLabel candidate -Phase "probe-smoke" -Index 1
  if ($null -eq $baselineProbe.probe -or $null -eq $candidateProbe.probe -or
      $null -eq $candidateProbe.probe.telemetry -or
      [string]$candidateProbe.probe.telemetry.evidence_sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
    throw "Exact-archive performance probe smoke did not capture candidate telemetry."
  }
  $smoke = [ordered]@{
    schema = 1
    kind = "mir-performance-probe-smoke"
    status = "passed"
    candidate_sha256 = $candidateIdentity.archive_sha256
    baseline_sha256 = $baselineIdentity.archive_sha256
    factorio_version = $factorioVersion
    baseline = $baselineProbe.probe
    candidate = $candidateProbe.probe
  }
  $smoke | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $script:RunRoot "probe-smoke.json") -Encoding UTF8
  Write-Host "[ok] exact-archive performance probe smoke passed: $($script:RunRoot)"
  exit 0
}

$factorioRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $script:FactorioPath))
$officialRoots = @("data\core", "data\base", "data\elevated-rails", "data\quality", "data\recycler", "data\space-age")
$machineSha = Get-MIRCampaignMachineSha256
$officialModsSha = Get-MIRCampaignTreeSha256 -Root $factorioRoot -RelativeRoots $officialRoots
$settingsSha = Get-MIRPerformanceSettingsFingerprint -Campaign $campaign
$scenariosSha = Get-MIRFileSha256 -Path $campaignFile
$harnessSha = Get-MIRPerformanceHarnessFingerprint -RepoRoot $RepoRoot
$factorioSha = Get-MIRFileSha256 -Path $script:FactorioPath

$raw = [ordered]@{
  schema = 1
  kind = "mir-runtime-performance-campaign-raw"
  status = "running"
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  candidate_sha256 = $candidateIdentity.archive_sha256
  baseline_sha256 = $baselineIdentity.archive_sha256
  factorio_sha256 = $factorioSha
  campaign_sha256 = $scenariosSha
  harness_sha256 = $harnessSha
  warmup_runs = $WarmupRuns
  measured_runs = $MeasuredRuns
  lanes = @()
}
$rawPath = Join-Path $script:RunRoot "campaign-result.json"
$raw | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $rawPath -Encoding UTF8

$runOrder = @()
for ($pair = 1; $pair -le $MeasuredRuns; $pair++) {
  if (($pair % 2) -eq 1) { $runOrder += @("baseline", "candidate") }
  else { $runOrder += @("candidate", "baseline") }
}

$laneResults = @()
$allClosureRows = @()
$phaseSamples = [ordered]@{baseline=[ordered]@{}; candidate=[ordered]@{}}
foreach ($packageLabel in @("baseline", "candidate")) {
  foreach ($phase in @($phaseLanes.probe_phase)) { $phaseSamples[$packageLabel][$phase] = @() }
}
$volumeSamples = [ordered]@{"diagnostics-off"=@(); "diagnostics-on"=@()}
foreach ($lane in $lanes) {
  $laneClosureSha = ""
  for ($warmup = 1; $warmup -le $WarmupRuns; $warmup++) {
    foreach ($packageLabel in @("baseline", "candidate")) {
      $warmupResult = Invoke-MIRCampaignLaneRun -Lane $lane -PackageLabel $packageLabel -Phase "warmup" -Index $warmup
      $closureSha = Get-MIRStringSha256 -Value (@($warmupResult.closure_rows) -join "`n")
      if ([string]::IsNullOrWhiteSpace($laneClosureSha)) { $laneClosureSha = $closureSha }
      elseif ($closureSha -ne $laneClosureSha) { throw "Third-party closure drifted during warm-up for $($lane.id)." }
      $allClosureRows += @($warmupResult.closure_rows | ForEach-Object { "$($lane.id)`t$_" })
    }
  }
  $baselineRuns = @()
  $candidateRuns = @()
  for ($orderIndex = 0; $orderIndex -lt $runOrder.Count; $orderIndex++) {
    $packageLabel = $runOrder[$orderIndex]
    $pairIndex = [Math]::Floor($orderIndex / 2) + 1
    $result = Invoke-MIRCampaignLaneRun -Lane $lane -PackageLabel $packageLabel -Phase "measured" -Index $pairIndex
    $closureSha = Get-MIRStringSha256 -Value (@($result.closure_rows) -join "`n")
    if ([string]::IsNullOrWhiteSpace($laneClosureSha)) { $laneClosureSha = $closureSha }
    elseif ($closureSha -ne $laneClosureSha) { throw "Third-party closure drifted during measured runs for $($lane.id)." }
    $allClosureRows += @($result.closure_rows | ForEach-Object { "$($lane.id)`t$_" })
    if ($packageLabel -eq "baseline") { $baselineRuns += [double]$result.seconds }
    else { $candidateRuns += [double]$result.seconds }
    if ([string]$lane.id -eq [string]$campaign.phase_source_lane) {
      if ($null -eq $result.probe) { throw "Phase-source run lacks the exact-archive performance probe." }
      foreach ($phase in @($phaseLanes.probe_phase)) {
        $phaseSamples[$packageLabel][$phase] += [double]$result.probe.phases.$phase.seconds
      }
    }
    if ($packageLabel -eq "candidate") {
      $surface = switch ([string]$lane.id) {
        "diagnostics-off.factorio-total" { "diagnostics-off" }
        "diagnostics-on.factorio-total" { "diagnostics-on" }
        default { $null }
      }
      if ($null -ne $surface) {
        if ($null -eq $result.probe.telemetry -or [string]$result.probe.telemetry.evidence_sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
          throw "Candidate artifact-volume run lacks published compiler telemetry: $surface"
        }
        $volumeSamples[$surface] += $result.probe.telemetry
      }
    }
  }
  $baselineStatistics = New-MIRCampaignStatistics -Values $baselineRuns
  $candidateStatistics = New-MIRCampaignStatistics -Values $candidateRuns
  $delta = [Math]::Round([double]$candidateStatistics.median_seconds - [double]$baselineStatistics.median_seconds, 6)
  $percentage = if ([double]$baselineStatistics.median_seconds -eq 0) { $null }
    else { [Math]::Round(($delta / [double]$baselineStatistics.median_seconds) * 100, 6) }
  $policy = @($budgets.regression_lanes | Where-Object id -eq $lane.id)[0]
  $withinRegression = ($null -ne $percentage -and [double]$percentage -le [double]$policy.maximum_regression_percent) -or
    $delta -le [double]$policy.absolute_noise_allowance_seconds
  $withinAbsolute = $null -eq $policy.max_candidate_seconds -or
    [double]$candidateStatistics.median_seconds -le [double]$policy.max_candidate_seconds
  $laneStatus = if ($withinRegression -and $withinAbsolute) { "passed" } else { "failed" }
  $laneResults += [ordered]@{
    id = [string]$lane.id
    baseline = $baselineStatistics
    candidate = $candidateStatistics
    absolute_delta_seconds = $delta
    percentage_delta = $percentage
    status = $laneStatus
  }
  Write-Host ("[performance] lane={0} baseline_median={1:N3}s candidate_median={2:N3}s delta={3:N3}s percent={4} status={5}" -f
    $lane.id, $baselineStatistics.median_seconds, $candidateStatistics.median_seconds, $delta,
    $(if ($null -eq $percentage) { "n/a" } else { "$percentage%" }), $laneStatus)
}

foreach ($phaseLane in $phaseLanes) {
  $phase = [string]$phaseLane.probe_phase
  $baselineStatistics = New-MIRCampaignStatistics -Values @($phaseSamples.baseline[$phase])
  $candidateStatistics = New-MIRCampaignStatistics -Values @($phaseSamples.candidate[$phase])
  $delta = [Math]::Round([double]$candidateStatistics.median_seconds - [double]$baselineStatistics.median_seconds, 6)
  $percentage = if ([double]$baselineStatistics.median_seconds -eq 0) { $null }
    else { [Math]::Round(($delta / [double]$baselineStatistics.median_seconds) * 100, 6) }
  $policy = @($budgets.regression_lanes | Where-Object id -eq $phaseLane.id)[0]
  $withinRegression = ($null -ne $percentage -and [double]$percentage -le [double]$policy.maximum_regression_percent) -or
    $delta -le [double]$policy.absolute_noise_allowance_seconds
  $laneResults += [ordered]@{
    id = [string]$phaseLane.id
    baseline = $baselineStatistics
    candidate = $candidateStatistics
    absolute_delta_seconds = $delta
    percentage_delta = $percentage
    status = if ($withinRegression) { "passed" } else { "failed" }
  }
}

$volumeMeasurements = @()
foreach ($surface in @("diagnostics-off", "diagnostics-on")) {
  $samples = @($volumeSamples[$surface])
  if ($samples.Count -ne $MeasuredRuns) { throw "Artifact-volume surface '$surface' lacks measured candidate runs." }
  $counterNames = @($samples[0].counters.PSObject.Properties.Name | Sort-Object)
  $counters = [ordered]@{}
  foreach ($name in $counterNames) {
    $counters[$name] = [long](($samples | ForEach-Object { [long]$_.counters.$name } | Measure-Object -Maximum).Maximum)
  }
  $volumeMeasurements += [ordered]@{
    surface = $surface
    measured_runs = $samples.Count
    telemetry_fingerprints = @($samples | ForEach-Object { ([string]$_.evidence_sha256).ToUpperInvariant() })
    counters = $counters
  }
}

$closureRows = @($allClosureRows | Sort-Object -Unique)
$thirdPartyClosureSha = Get-MIRStringSha256 -Value ($closureRows -join "`n")
$failedLanes = @($laneResults | Where-Object status -ne "passed")
$raw.status = if ($failedLanes.Count -eq 0) { "passed" } else { "failed" }
$raw.lanes = $laneResults
$raw.third_party_closure_sha256 = $thirdPartyClosureSha
$raw.completed_at = (Get-Date).ToUniversalTime().ToString("o")
$raw | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $rawPath -Encoding UTF8

if ($failedLanes.Count -gt 0) {
  throw "Performance campaign failed lanes: $(@($failedLanes.id) -join ', '). Raw result: $rawPath"
}

$evidence = [ordered]@{
  schema = 3
  kind = "mir-runtime-performance-regression"
  status = "passed"
  candidate = [ordered]@{
    version = $candidateIdentity.version
    archive_sha256 = $candidateIdentity.archive_sha256
    package_content_sha256 = $candidateIdentity.package_content_sha256
    source_commit = $ExpectedSourceCommit.ToLowerInvariant()
  }
  baseline = $baselineIdentity
  factorio = [ordered]@{
    version = $factorioVersion
    binary_sha256 = $factorioSha
  }
  comparability = [ordered]@{
    machine_sha256 = $machineSha
    official_mods_sha256 = $officialModsSha
    third_party_closure_sha256 = $thirdPartyClosureSha
    settings_sha256 = $settingsSha
    scenarios_sha256 = $scenariosSha
    harness_sha256 = $harnessSha
  }
  run_policy = [ordered]@{
    warmup_runs = $WarmupRuns
    minimum_measured_runs_per_package = $MeasuredRuns
    order = "paired-balanced"
  }
  run_order = $runOrder
  lanes = $laneResults
  artifact_volume = [ordered]@{
    telemetry_schema = 1
    aggregation = "maximum-observed"
    measurements = $volumeMeasurements
  }
}
$outputParent = Split-Path -Parent $outputFile
if (-not (Test-Path -LiteralPath $outputParent)) { New-Item -ItemType Directory -Force -Path $outputParent | Out-Null }
$evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $outputFile -Encoding UTF8
Write-Host "[ok] paired MIR performance evidence: $outputFile"
Write-Host "[ok] raw performance campaign: $rawPath"
