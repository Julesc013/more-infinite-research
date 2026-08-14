function Get-MIRPerformanceHarnessFiles {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authorities = @(
    ".mir/performance-budgets.json",
    ".mir/performance-campaign.json",
    ".mir/sanitation-budgets.json",
    "fixtures/compat-matrix/local-library-scenarios.json",
    "fixtures/performance-regression-probe",
    "scripts/Invoke-MIRCompatAudit.ps1",
    "scripts/Measure-MIRPerformanceRegression.ps1",
    "scripts/MIRCompatAudit",
    "scripts/validation/PackageIdentity.ps1",
    "scripts/validation/PerformanceCampaign.ps1",
    "scripts/validation/ReleaseAttestations.ps1",
    "scripts/validation/SettingsOverrides.ps1"
  )
  $files = @()
  foreach ($relative in $authorities) {
    $path = Join-Path $repo $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $files += $relative.Replace("\", "/")
      continue
    }
    if (Test-Path -LiteralPath $path -PathType Container) {
      $files += @(
        Get-ChildItem -LiteralPath $path -Recurse -File |
          ForEach-Object { [IO.Path]::GetRelativePath($repo, $_.FullName).Replace("\", "/") }
      )
      continue
    }
    throw "Performance harness authority is absent: $relative"
  }
  return @($files | Sort-Object -Unique)
}

function Get-MIRPerformanceHarnessFingerprint {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $rows = foreach ($relative in Get-MIRPerformanceHarnessFiles -RepoRoot $repo) {
    $identity = Get-MIRFileContentIdentity -Path (Join-Path $repo $relative) -RelativePath $relative
    "{0}`t{1}`t{2}" -f $relative, $identity.Length, $identity.Sha256
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
  return Get-MIRPerformanceTextSha256 -Value ($rows -join "`n")
}

function Get-MIRPerformanceRunDirectoryName {
  param(
    [Parameter(Mandatory)][string]$LaneId,
    [Parameter(Mandatory)][ValidateSet("warmup", "measured", "compat-smoke", "probe-smoke")][string]$Phase,
    [Parameter(Mandatory)][ValidateRange(1, 99)][int]$Index,
    [Parameter(Mandatory)][ValidateSet("baseline", "candidate")][string]$PackageLabel
  )

  if ([string]::IsNullOrWhiteSpace($LaneId)) {
    throw "Performance run directory requires a non-empty lane ID."
  }
  $hasher = [Security.Cryptography.SHA256]::Create()
  try {
    $laneHash = [Convert]::ToHexString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($LaneId))).Substring(0, 16).ToLowerInvariant()
  } finally {
    $hasher.Dispose()
  }
  $phaseToken = @{
    "warmup" = "w"
    "measured" = "m"
    "compat-smoke" = "s"
    "probe-smoke" = "p"
  }[$Phase]
  $packageToken = if ($PackageLabel -eq "baseline") { "b" } else { "c" }
  return "l-$laneHash-$phaseToken$($Index.ToString('D2'))-$packageToken"
}

function Get-MIRPerformanceRunPathBudget {
  param(
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RunDirectoryName
  )

  $userDataPath = Join-Path $RunRoot (Join-Path $RunDirectoryName "c\runs\u-000000000000")
  $tempPath = Join-Path $userDataPath "temp\currently-playing\locale\ar\freeplay.cfg"
  return [pscustomobject]@{
    maximum_path_length = 240
    projected_user_data_path = $userDataPath
    projected_user_data_path_length = $userDataPath.Length
    projected_temp_path = $tempPath
    projected_temp_path_length = $tempPath.Length
  }
}

function Assert-MIRPerformanceRunPathBudget {
  param(
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RunDirectoryName
  )

  $budget = Get-MIRPerformanceRunPathBudget -RunRoot $RunRoot -RunDirectoryName $RunDirectoryName
  if ($budget.projected_temp_path_length -gt $budget.maximum_path_length) {
    throw "Performance run path exceeds the Factorio temporary-path budget ($($budget.projected_temp_path_length) > $($budget.maximum_path_length)): $($budget.projected_temp_path)"
  }
  return $budget
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
      durable_destination = $DurableDestination.Replace("\", "/")
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
    [Parameter(Mandatory)][string]$DestinationRoot,
    [switch]$ContentAddressedChild
  )

  $source = (Resolve-Path -LiteralPath $SourceRoot).Path
  if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Performance artifact source is absent: $SourceRoot" }
  $destinationNamespace = [IO.Path]::GetFullPath($DestinationRoot)
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
    $rows.Add([pscustomobject][ordered]@{
      relative_path=$relative.Replace("\", "/")
      source_path=$file.FullName
      sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
      bytes=[int64]$file.Length
    })
  }
  $rows = @($rows | Sort-Object -Property relative_path)
  $manifestRows = @($rows | ForEach-Object { "$($_.relative_path)`t$($_.bytes)`t$($_.sha256)" })
  $artifactTreeSha256 = Get-MIRPerformanceTextSha256 -Value ($manifestRows -join "`n")
  $destination = if ($ContentAddressedChild) { Join-Path $destinationNamespace $artifactTreeSha256 } else { $destinationNamespace }
  if (Test-Path -LiteralPath $destination) {
    if (-not $ContentAddressedChild) { throw "Performance artifact destination already exists and will not be merged: $destination" }
    $destinationInfo = Get-Item -LiteralPath $destination -Force
    if (-not $destinationInfo.PSIsContainer -or ($destinationInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Content-addressed performance artifact destination is not a safe directory: $destination"
    }
    $existingFiles = @(Get-ChildItem -LiteralPath $destination -Recurse -Force -File)
    if ($existingFiles.Count -ne $rows.Count) { throw "Content-addressed performance artifact destination does not match its tree identity: $destination" }
    foreach ($row in $rows) {
      $existingPath = Join-Path $destination ($row.relative_path.Replace("/", [IO.Path]::DirectorySeparatorChar))
      if (-not (Test-Path -LiteralPath $existingPath -PathType Leaf)) {
        throw "Content-addressed performance artifact destination is missing $($row.relative_path): $destination"
      }
      $existingInfo = Get-Item -LiteralPath $existingPath -Force
      if (($existingInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
          [int64]$existingInfo.Length -ne [int64]$row.bytes -or
          (Get-FileHash -LiteralPath $existingPath -Algorithm SHA256).Hash.ToUpperInvariant() -ne [string]$row.sha256) {
        throw "Content-addressed performance artifact destination changed bytes for $($row.relative_path): $destination"
      }
    }
    return [pscustomobject][ordered]@{
      source_root=$source; destination_root=$destination; destination_namespace=$destinationNamespace
      disposition="existing-verified"; file_count=$rows.Count
      bytes=[int64](($rows | Measure-Object -Property bytes -Sum).Sum)
      artifact_tree_sha256=$artifactTreeSha256
    }
  }
  [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination))
  $temporary = "$destination.staging-$([guid]::NewGuid().ToString('N'))"
  [void](New-Item -ItemType Directory -Path $temporary)
  foreach ($row in $rows) {
    $target = Join-Path $temporary ($row.relative_path.Replace("/", [IO.Path]::DirectorySeparatorChar))
    [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target))
    [IO.File]::Copy([string]$row.source_path, $target, $false)
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToUpperInvariant() -ne [string]$row.sha256) {
      throw "Performance artifact relocation changed bytes for $($row.relative_path); preserved partial staging root: $temporary"
    }
  }
  [IO.Directory]::Move($temporary, $destination)
  return [pscustomobject][ordered]@{
    source_root=$source; destination_root=$destination; destination_namespace=$destinationNamespace
    disposition="copied"; file_count=$rows.Count
    bytes=[int64](($rows | Measure-Object -Property bytes -Sum).Sum)
    artifact_tree_sha256=$artifactTreeSha256
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
