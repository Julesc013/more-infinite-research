function Get-MIRPerformanceHarnessFiles {
  param(
    [Parameter(Mandatory)][Alias("RepoRoot")][string]$ExecutionRoot,
    [string]$TargetAuthorityRoot = "",
    [string]$ManualScenariosRelativePath = ""
  )

  $execution = (Resolve-Path -LiteralPath $ExecutionRoot).Path
  if ([string]::IsNullOrWhiteSpace($TargetAuthorityRoot)) { $TargetAuthorityRoot = $execution }
  if ([string]::IsNullOrWhiteSpace($ManualScenariosRelativePath)) {
    $campaignPath = Join-Path $TargetAuthorityRoot ".mir\performance-campaign.json"
    if (-not (Test-Path -LiteralPath $campaignPath -PathType Leaf)) { throw "Performance harness campaign authority is absent." }
    $ManualScenariosRelativePath = [string]((Get-Content -Raw -LiteralPath $campaignPath | ConvertFrom-Json).manual_scenarios)
  }
  $target = (Resolve-Path -LiteralPath $TargetAuthorityRoot).Path
  $scenarioAuthority = $ManualScenariosRelativePath.Replace("\", "/")
  if ([IO.Path]::IsPathRooted($ManualScenariosRelativePath) -or
      $scenarioAuthority -notmatch '^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*\.json$') {
    throw "Performance harness requires a repository-relative scenario authority path."
  }
  $executionAuthorities = @(
    ".mir/performance-campaign.json",
    "fixtures/performance-regression-probe",
    "scripts/Invoke-MIRCompatAudit.ps1",
    "tools/commands/compatibility/Invoke-MIRCompatAudit.ps1",
    "scripts/Measure-MIRPerformanceRegression.ps1",
    "tools/lib/compatibility",
    "tools/lib/validation/PackageIdentity.ps1",
    "tools/lib/validation/PerformanceCampaign.ps1",
    "tools/lib/validation/ReleaseAttestations.ps1",
    "tools/lib/validation/SettingsOverrides.ps1"
  )
  $files = @()
  foreach ($relative in $executionAuthorities) {
    $path = Join-Path $execution $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $files += [pscustomobject]@{ scope="execution"; relative=$relative.Replace("\", "/"); path=$path }
      continue
    }
    if (Test-Path -LiteralPath $path -PathType Container) {
      $files += @(
        Get-ChildItem -LiteralPath $path -Recurse -File |
          ForEach-Object {
            [pscustomobject]@{
              scope="execution"
              relative=[IO.Path]::GetRelativePath($execution, $_.FullName).Replace("\", "/")
              path=$_.FullName
            }
          }
      )
      continue
    }
    throw "Performance execution-toolchain authority is absent: $relative"
  }
  foreach ($relative in @(".mir/performance-budgets.json", ".mir/sanitation-budgets.json", $scenarioAuthority)) {
    $path = Join-Path $target $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Performance target authority is absent: $relative"
    }
    $files += [pscustomobject]@{ scope="target"; relative=$relative.Replace("\", "/"); path=$path }
  }
  return @($files | Sort-Object scope, relative -Unique)
}

function Get-MIRPerformanceHarnessFingerprint {
  param(
    [Parameter(Mandatory)][Alias("RepoRoot")][string]$ExecutionRoot,
    [string]$TargetAuthorityRoot = "",
    [string]$ManualScenariosRelativePath = ""
  )

  $rows = foreach ($entry in Get-MIRPerformanceHarnessFiles -ExecutionRoot $ExecutionRoot -TargetAuthorityRoot $TargetAuthorityRoot -ManualScenariosRelativePath $ManualScenariosRelativePath) {
    $qualifiedPath = "$($entry.scope)/$($entry.relative)"
    $identity = Get-MIRFileContentIdentity -Path $entry.path -RelativePath $qualifiedPath
    "{0}`t{1}`t{2}" -f $qualifiedPath, $identity.Length, $identity.Sha256
  }
  return Get-MIRStringSha256 -Value ($rows -join "`n")
}

function ConvertTo-MIRPerformanceSettingsMap {
  param($Value)

  $map = [ordered]@{}
  if ($null -eq $Value) { return $map }
  foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
    $map[[string]$property.Name] = $property.Value
  }
  return $map
}

function Get-MIRPerformanceSettingsFingerprint {
  param([Parameter(Mandatory)]$Campaign)

  $rows = @(
    foreach ($lane in @($Campaign.lanes | Sort-Object id)) {
      $settingsJson = (ConvertTo-MIRPerformanceSettingsMap -Value $lane.settings) | ConvertTo-Json -Depth 10 -Compress
      "$($lane.id)`t$settingsJson"
    }
  )
  return Get-MIRStringSha256 -Value ($rows -join "`n")
}

function Get-MIRPerformanceRawSha256 {
  param([Parameter(Mandatory)][string]$Path)

  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-MIRPerformanceTextSha256 {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

  $sha256 = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Value)
    return ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace("-", "")
  } finally {
    $sha256.Dispose()
  }
}

function Get-MIRPerformancePathBudgetProjection {
  param(
    [Parameter(Mandatory)]$Campaign,
    [Parameter(Mandatory)][string]$ScratchRoot
  )

  $root = [IO.Path]::GetFullPath($ScratchRoot)
  $maximumLength = 0
  $maximumPath = ""
  $paths = [Collections.Generic.List[string]]::new()
  foreach ($lane in @($Campaign.lanes)) {
    $laneId = [string]$lane.id
    $laneSafe = ($laneId -replace '[^A-Za-z0-9_.-]', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($laneSafe)) { throw "Performance staging lane has no safe path component: $laneId" }
    $relativePaths = if ([string]$lane.runner -eq "compat-audit") {
      @(
        "$laneSafe\measured-25-candidate\compat\runs\u-0123456789ab\mods\mir-validation-settings-overrides\settings-updates.lua",
        "$laneSafe\measured-25-candidate\compat\runs\u-0123456789ab\temp-extraction\locale\en\mir-performance-regression-deep-path.cfg"
      )
    } else {
      @(
        "$laneSafe\measured-25-candidate\mods\mir-fixture-performance-regression-probe_0.1.0\data-final-fixes.lua",
        "$laneSafe\measured-25-candidate\temp-extraction\mods\mir-fixture-performance-regression-probe_0.1.0\locale\en\mir-performance-regression-deep-path.cfg"
      )
    }
    foreach ($relativePath in $relativePaths) {
      $probe = Join-Path $root $relativePath
      $paths.Add($probe)
      if ($probe.Length -gt $maximumLength) {
        $maximumLength = $probe.Length
        $maximumPath = $probe
      }
    }
  }
  if ($paths.Count -eq 0) { throw "Performance staging campaign has no lanes to project." }
  return [pscustomobject][ordered]@{
    conservative_path_budget = 240
    maximum_path_length = $maximumLength
    maximum_path = $maximumPath
    projected_paths = @($paths)
  }
}

function New-MIRPerformanceStagingRoot {
  param(
    [Parameter(Mandatory)]$Campaign,
    [Parameter(Mandatory)][string]$TargetCode,
    [Parameter(Mandatory)][string]$TestId,
    [Parameter(Mandatory)][string]$PlanFingerprint,
    [Parameter(Mandatory)][string]$CandidateSha256,
    [Parameter(Mandatory)][string]$BaselineSha256,
    [Parameter(Mandatory)][string]$FactorioBinarySha256,
    [Parameter(Mandatory)][string]$DurableDestination,
    [ValidateRange(1, 9999)][int]$AttemptOrdinal = 1,
    [string[]]$ScratchRootCandidates = @("C:\mir-tmp", "C:\tmp", [IO.Path]::GetTempPath())
  )

  foreach ($field in @(
    @{name="PlanFingerprint";value=$PlanFingerprint},
    @{name="CandidateSha256";value=$CandidateSha256},
    @{name="BaselineSha256";value=$BaselineSha256},
    @{name="FactorioBinarySha256";value=$FactorioBinarySha256}
  )) {
    if ([string]$field.value -notmatch '^[0-9A-Fa-f]{64}$') { throw "$($field.name) must be an exact SHA-256 digest." }
  }
  if ($TargetCode -notmatch '^[A-Za-z0-9_-]{2,12}$' -or [string]::IsNullOrWhiteSpace($TestId)) {
    throw "Performance staging requires a short target code and non-empty test identity."
  }
  if ([string]::IsNullOrWhiteSpace($DurableDestination) -or [IO.Path]::IsPathRooted($DurableDestination)) {
    throw "Performance staging provenance requires a repository-relative durable destination."
  }
  $contextDigest = $PlanFingerprint.ToUpperInvariant()
  $attemptName = "{0:D2}" -f $AttemptOrdinal
  $rejections = [Collections.Generic.List[string]]::new()
  foreach ($candidateRoot in @($ScratchRootCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    try { $parent = [IO.Path]::GetFullPath([string]$candidateRoot) }
    catch { $rejections.Add("invalid-root:$candidateRoot"); continue }
    $root = Join-Path $parent (Join-Path $TargetCode (Join-Path $contextDigest.Substring(0, 8) $attemptName))
    $projection = Get-MIRPerformancePathBudgetProjection -Campaign $Campaign -ScratchRoot $root
    if ([int]$projection.maximum_path_length -gt [int]$projection.conservative_path_budget) {
      $rejections.Add("path-budget:$root=$($projection.maximum_path_length)")
      continue
    }
    if (Test-Path -LiteralPath $root) {
      $rejections.Add("occupied:$root")
      continue
    }
    try {
      [void](New-Item -ItemType Directory -Force -Path $root)
    } catch {
      $rejections.Add("unavailable:$root")
      continue
    }
    $markerPath = Join-Path $root "mir-staging-provenance.json"
    $marker = [ordered]@{
      schema = 1
      kind = "mir-performance-staging-provenance"
      target = $TargetCode
      test_id = $TestId
      plan_fingerprint = $contextDigest
      candidate_sha256 = $CandidateSha256.ToUpperInvariant()
      baseline_sha256 = $BaselineSha256.ToUpperInvariant()
      factorio_binary_sha256 = $FactorioBinarySha256.ToUpperInvariant()
      attempt_ordinal = $AttemptOrdinal
      scratch_root = $root
      durable_destination = $DurableDestination.Replace("\\", "/")
      conservative_path_budget = [int]$projection.conservative_path_budget
      maximum_projected_path_length = [int]$projection.maximum_path_length
      maximum_projected_path = [string]$projection.maximum_path
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
    $marker | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $markerPath -Encoding UTF8
    return [pscustomobject][ordered]@{
      path = $root
      marker_path = $markerPath
      strategy = "compact-context-scratch-v2"
      target = $TargetCode
      attempt_ordinal = $AttemptOrdinal
      plan_fingerprint = $contextDigest
      conservative_path_budget = [int]$projection.conservative_path_budget
      maximum_projected_path_length = [int]$projection.maximum_path_length
      maximum_projected_path = [string]$projection.maximum_path
      durable_destination = $marker.durable_destination
    }
  }
  throw "assurance-infrastructure-path-budget: no compact scratch root can satisfy the conservative 240-character budget before Factorio launch. Rejections: $($rejections -join '; ')"
}

function Copy-MIRPerformanceArtifactsVerified {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$DestinationRoot
  )

  $source = (Resolve-Path -LiteralPath $SourceRoot).Path
  if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Performance artifact source is absent: $SourceRoot" }
  $destination = [IO.Path]::GetFullPath($DestinationRoot)
  if (Test-Path -LiteralPath $destination) { throw "Performance artifact destination already exists and will not be merged: $destination" }
  $sourceInfo = Get-Item -LiteralPath $source -Force
  if (($sourceInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Performance artifact source must not be a reparse point." }
  foreach ($directory in @(Get-ChildItem -LiteralPath $source -Recurse -Force -Directory)) {
    if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Performance artifact tree contains a reparse-point directory: $($directory.FullName)"
    }
  }
  $files = @(Get-ChildItem -LiteralPath $source -Recurse -Force -File)
  $seenCase = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $seenUnicode = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($file in $files) {
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Performance artifact tree contains a reparse-point file: $($file.FullName)" }
    $relative = [IO.Path]::GetRelativePath($source, $file.FullName)
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or $relative -match ':') {
      throw "Performance artifact tree contains an unsafe relative path: $relative"
    }
    $normalized = $relative.Normalize([Text.NormalizationForm]::FormC)
    if (-not $seenCase.Add($relative) -or -not $seenUnicode.Add($normalized)) {
      throw "Performance artifact tree contains a case or Unicode-normalization collision: $relative"
    }
    $rows.Add([pscustomobject][ordered]@{relative_path=$relative.Replace("\\", "/"); source_path=$file.FullName; sha256=(Get-MIRPerformanceRawSha256 -Path $file.FullName); bytes=[int64]$file.Length})
  }
  $parent = Split-Path -Parent $destination
  [void](New-Item -ItemType Directory -Force -Path $parent)
  $temporary = "$destination.staging-$([guid]::NewGuid().ToString('N'))"
  [void](New-Item -ItemType Directory -Path $temporary)
  foreach ($row in $rows) {
    $target = Join-Path $temporary ($row.relative_path.Replace("/", [IO.Path]::DirectorySeparatorChar))
    [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target))
    [IO.File]::Copy([string]$row.source_path, $target, $false)
    $destinationSha256 = Get-MIRPerformanceRawSha256 -Path $target
    if ($destinationSha256 -ne [string]$row.sha256) {
      throw "Performance artifact relocation changed bytes for $($row.relative_path); preserved partial staging root: $temporary"
    }
  }
  [IO.Directory]::Move($temporary, $destination)
  $manifestRows = @($rows | ForEach-Object { "$($_.relative_path)`t$($_.bytes)`t$($_.sha256)" })
  return [pscustomobject][ordered]@{
    source_root = $source
    destination_root = $destination
    file_count = $rows.Count
    bytes = [int64](($rows | Measure-Object -Property bytes -Sum).Sum)
    artifact_tree_sha256 = Get-MIRPerformanceTextSha256 -Value ($manifestRows -join "`n")
    artifacts = @($rows | ForEach-Object { [pscustomobject][ordered]@{path=$_.relative_path;bytes=$_.bytes;sha256=$_.sha256} })
  }
}

function Get-MIRPerformanceCounterValue {
  param(
    [Parameter(Mandatory)]$Counters,
    [Parameter(Mandatory)][string]$Name
  )

  if ($Counters -is [Collections.IDictionary]) {
    if (-not $Counters.Contains($Name)) {
      return [pscustomobject]@{found=$false; value=[long]0}
    }
    return [pscustomobject]@{found=$true; value=[long]$Counters[$Name]}
  }

  $property = $Counters.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return [pscustomobject]@{found=$false; value=[long]0}
  }
  return [pscustomobject]@{found=$true; value=[long]$property.Value}
}
