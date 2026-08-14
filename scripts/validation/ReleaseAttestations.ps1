. (Join-Path $PSScriptRoot "PackageIdentity.ps1")

function Get-MIRReleaseSha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Get-MIRReleaseTextSha256 {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "") }
  finally { $sha.Dispose() }
}

function Get-MIRReleasePortableArtifactSha256 {
  param([Parameter(Mandatory)][string]$Path)
  $textExtensions = @(".csv", ".json", ".log", ".md", ".txt", ".yaml", ".yml")
  $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ($textExtensions -notcontains $extension) {
    return Get-MIRReleaseSha256 -Path $Path
  }
  $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
  $normalized = ($text -replace "`r`n", "`n") -replace "`r", "`n"
  return Get-MIRReleaseTextSha256 -Text $normalized
}

function ConvertTo-MIRReleaseOrderedMap {
  param([Parameter(Mandatory)]$Object)
  $map = [ordered]@{}
  foreach ($property in $Object.PSObject.Properties) { $map[$property.Name] = $property.Value }
  return $map
}

function Resolve-MIRReleasePath {
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$Path)
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  return [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function ConvertTo-MIRReleaseDateTimeOffset {
  param([Parameter(Mandatory)]$Value)
  if ($Value -is [DateTimeOffset]) { return [DateTimeOffset]$Value }
  if ($Value -is [DateTime]) { return [DateTimeOffset]::new([DateTime]$Value) }
  return [DateTimeOffset]::Parse(
    [string]$Value,
    [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::RoundtripKind
  )
}

function Resolve-MIRReleaseCommit {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)][string]$Label
  )
  if ($Commit -notmatch '^[0-9a-fA-F]{40}$') { throw "$Label must be a full Git commit." }
  $resolved = @(& git -C $RepoRoot rev-parse "$Commit^{commit}" 2>$null)
  if ($LASTEXITCODE -ne 0 -or $resolved.Count -ne 1 -or [string]$resolved[0] -notmatch '^[0-9a-f]{40}$') {
    throw "$Label is unavailable: $Commit"
  }
  return ([string]$resolved[0]).Trim().ToLowerInvariant()
}

function Get-MIRReleaseCandidateAuthority {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$CandidateInfo
  )
  $ledgerPath = Join-Path $RepoRoot '.mir\releases.json'
  $ledger = Get-Content -Raw -LiteralPath $ledgerPath | ConvertFrom-Json
  $targetKey = "factorio-$([string]$CandidateInfo.factorio_version)"
  $property = $ledger.development.PSObject.Properties[$targetKey]
  if ([int]$ledger.schema -ne 1 -or [string]$ledger.authority -ne 'canonical-release-ledger' -or $null -eq $property) {
    throw "Canonical release authority is absent for $targetKey."
  }
  $authority = $property.Value
  $canonicalMatches = [string]$authority.mir_version -eq [string]$CandidateInfo.version -and
      [string]$authority.package_source_commit -match '^[0-9a-f]{40}$' -and
      [long]$authority.archive_bytes -gt 0 -and [int]$authority.archive_entries -gt 0 -and
      [string]$authority.archive_sha256 -match '^[0-9A-F]{64}$' -and
      [string]$authority.package_content_sha256 -match '^[0-9A-F]{64}$'
  if ($canonicalMatches) { return $authority }

  $version = [string]$CandidateInfo.version
  $shadowRoot = Join-Path $RepoRoot ".mir\releases\terminal\shadows\$version"
  $contextPath = Join-Path $shadowRoot 'qualification-context.json'
  $manifestPath = Join-Path $shadowRoot 'package-manifest.json'
  $transitionPath = Join-Path $shadowRoot 'transition-plan.json'
  foreach ($requiredPath in @($contextPath, $manifestPath, $transitionPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
      throw 'Canonical release authority does not describe the candidate package.'
    }
  }
  $context = Get-Content -Raw -LiteralPath $contextPath | ConvertFrom-Json
  $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
  $transition = Get-Content -Raw -LiteralPath $transitionPath | ConvertFrom-Json
  $shadowAuthorities = @(
    $context.performance_transition.development_package,
    $manifest.source.performance_transition.development_package,
    $transition.immutable_inputs.performance_transition.development_package
  )
  if ([string]$context.release -ne $version -or [string]$context.target -ne [string]$CandidateInfo.factorio_version -or
      [string]$context.phase -ne 'shadow-convergence' -or $null -ne $context.candidate_id -or
      [string]$manifest.release -ne $version -or [string]$manifest.target -ne [string]$CandidateInfo.factorio_version -or
      [bool]$manifest.source_frozen -or $null -ne $manifest.candidate_id -or
      [string]$transition.release -ne $version -or [string]$transition.target -ne [string]$CandidateInfo.factorio_version -or
      [bool]$transition.source_frozen -or $null -ne $transition.candidate_id -or $shadowAuthorities.Count -ne 3) {
    throw 'Terminal shadow authority is not an unfrozen, candidate-unassigned convergence identity.'
  }
  $shadowAuthority = $shadowAuthorities[0]
  foreach ($candidateAuthority in $shadowAuthorities) {
    foreach ($field in @('version', 'package_source_commit', 'package_source_sha256', 'archive_bytes', 'archive_entries', 'archive_sha256', 'package_content_sha256')) {
      if ([string]$candidateAuthority.$field -ne [string]$shadowAuthority.$field) {
        throw "Terminal shadow package authority differs across generated records: $field"
      }
    }
  }
  if ([string]$shadowAuthority.version -ne $version -or
      [string]$shadowAuthority.package_source_commit -notmatch '^[0-9a-f]{40}$' -or
      [string]$shadowAuthority.package_source_sha256 -notmatch '^[0-9A-F]{64}$' -or
      [long]$shadowAuthority.archive_bytes -le 0 -or [int]$shadowAuthority.archive_entries -le 0 -or
      [string]$shadowAuthority.archive_sha256 -notmatch '^[0-9A-F]{64}$' -or
      [string]$shadowAuthority.package_content_sha256 -notmatch '^[0-9A-F]{64}$') {
    throw 'Terminal shadow package authority is incomplete.'
  }
  return $shadowAuthority
}

function Test-MIRReleasePackageRootsEqual {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ReferenceCommit,
    [Parameter(Mandatory)][string]$DifferenceCommit
  )
  $roots = @(Get-MIRPackageSourceRoots)
  & git -C $RepoRoot diff --quiet $ReferenceCommit $DifferenceCommit -- @roots
  return $LASTEXITCODE -eq 0
}

function Assert-MIRReleaseEvidenceSourceAuthority {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$CandidateInfo,
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][string]$ExpectedQualificationCommit,
    [Parameter(Mandatory)][string]$RecordedEvidenceCommit,
    [switch]$RequirePackageSourceEvidenceCommit
  )
  $authority = Get-MIRReleaseCandidateAuthority -RepoRoot $RepoRoot -CandidateInfo $CandidateInfo
  $packageCommit = Resolve-MIRReleaseCommit -RepoRoot $RepoRoot -Commit ([string]$authority.package_source_commit) -Label 'Package-source commit'
  $qualificationCommit = Resolve-MIRReleaseCommit -RepoRoot $RepoRoot -Commit $ExpectedQualificationCommit -Label 'Qualification-source commit'
  $evidenceCommit = Resolve-MIRReleaseCommit -RepoRoot $RepoRoot -Commit $RecordedEvidenceCommit -Label 'Evidence-producing commit'
  if ($RequirePackageSourceEvidenceCommit -and $evidenceCommit -ne $packageCommit) {
    throw 'Manual review evidence must bind the immutable package-source commit.'
  }
  & git -C $RepoRoot merge-base --is-ancestor $packageCommit $evidenceCommit
  if ($LASTEXITCODE -ne 0) { throw 'Package-source commit is not an ancestor of the evidence-producing commit.' }
  & git -C $RepoRoot merge-base --is-ancestor $evidenceCommit $qualificationCommit
  if ($LASTEXITCODE -ne 0) { throw 'Evidence-producing commit is not an ancestor of the qualification-source commit.' }
  if (-not (Test-MIRReleasePackageRootsEqual -RepoRoot $RepoRoot -ReferenceCommit $packageCommit -DifferenceCommit $evidenceCommit) -or
      -not (Test-MIRReleasePackageRootsEqual -RepoRoot $RepoRoot -ReferenceCommit $packageCommit -DifferenceCommit $qualificationCommit)) {
    throw 'Package-visible roots differ across package, evidence, and qualification source authorities.'
  }
  $candidateSha = Get-MIRReleaseSha256 -Path $CandidatePath
  $candidateContentSha = Get-MIRReleaseArchiveContentSha256 -Path $CandidatePath
  if ($candidateSha -ne [string]$authority.archive_sha256 -or
      $candidateContentSha -ne [string]$authority.package_content_sha256 -or
      (Get-Item -LiteralPath $CandidatePath).Length -ne [long]$authority.archive_bytes -or
      (Get-MIRReleaseArchiveEntryCount -Path $CandidatePath) -ne [int]$authority.archive_entries) {
    throw 'Candidate bytes do not match canonical release authority.'
  }
  return [pscustomobject][ordered]@{
    package_source_commit = $packageCommit
    evidence_source_commit = $evidenceCommit
    qualification_source_commit = $qualificationCommit
  }
}

function Get-MIRReleasePackageInfo {
  param([Parameter(Mandatory)][string]$Path)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entry = @($archive.Entries | Where-Object { $_.FullName -match '(^|/)info\.json$' })[0]
    if ($null -eq $entry) { throw "Package lacks info.json: $Path" }
    $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8, $true)
    try { return ($reader.ReadToEnd() | ConvertFrom-Json) }
    finally { $reader.Dispose() }
  } finally { $archive.Dispose() }
}

function Get-MIRReleaseArchiveContentSha256 {
  param([Parameter(Mandatory)][string]$Path)
  return Get-MIRZipContentFingerprint -Path $Path
}

function Get-MIRReleaseArchiveEntryCount {
  param([Parameter(Mandatory)][string]$Path)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try { return @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }).Count }
  finally { $archive.Dispose() }
}

function Get-MIRReleasePercentile {
  param([Parameter(Mandatory)][double[]]$Values, [Parameter(Mandatory)][double]$Percentile)
  $sorted = @($Values | Sort-Object)
  if ($sorted.Count -eq 0) { throw "Cannot calculate a percentile from an empty run set." }
  $index = [Math]::Max(0, [Math]::Ceiling($Percentile * $sorted.Count) - 1)
  return [double]$sorted[$index]
}

function Get-MIRReleaseRunStatistics {
  param([Parameter(Mandatory)][double[]]$Values)
  $sorted = @($Values | Sort-Object)
  if ($sorted.Count -eq 0) { throw "Performance lane has no measured runs." }
  $middle = [Math]::Floor($sorted.Count / 2)
  $median = if (($sorted.Count % 2) -eq 0) {
    ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2
  } else {
    [double]$sorted[$middle]
  }
  return [ordered]@{
    median_seconds = [Math]::Round($median, 6)
    p90_seconds = [Math]::Round((Get-MIRReleasePercentile -Values $sorted -Percentile 0.9), 6)
    minimum_seconds = [Math]::Round([double]$sorted[0], 6)
    maximum_seconds = [Math]::Round([double]$sorted[-1], 6)
  }
}

function Assert-MIRReleaseStatistic {
  param([Parameter(Mandatory)]$Recorded, [Parameter(Mandatory)]$Expected, [Parameter(Mandatory)][string]$Label)
  foreach ($field in @("median_seconds", "p90_seconds", "minimum_seconds", "maximum_seconds")) {
    if ([Math]::Abs([double]$Recorded.$field - [double]$Expected[$field]) -gt 0.000001) {
      throw "Performance evidence has an incorrect $Label $field."
    }
  }
}

function Test-MIRRuntimePerformanceEvidence {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$Path = "",
    [Parameter(Mandatory)][string]$Candidate,
    [Parameter(Mandatory)][string]$PriorRelease,
    [Parameter(Mandatory)][string]$FactorioBin,
    [Parameter(Mandatory)][string]$ExpectedSourceCommit,
    [Parameter(Mandatory)][string]$ExpectedBaselineVersion,
    [Parameter(Mandatory)][string]$ExpectedFactorioVersion,
    [string]$CampaignPath = ".mir\performance-campaign.json"
  )
  $candidatePath = Resolve-MIRReleasePath -RepoRoot $RepoRoot -Path $Candidate
  $priorPath = Resolve-MIRReleasePath -RepoRoot $RepoRoot -Path $PriorRelease
  if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { throw "Runtime performance candidate is absent: $candidatePath" }
  if (-not (Test-Path -LiteralPath $priorPath -PathType Leaf)) { throw "Runtime performance baseline is absent: $priorPath" }
  if (-not (Test-Path -LiteralPath $FactorioBin -PathType Leaf)) { throw "Runtime performance Factorio binary is absent: $FactorioBin" }
  $candidateInfo = Get-MIRReleasePackageInfo -Path $candidatePath
  $priorInfo = Get-MIRReleasePackageInfo -Path $priorPath
  if ([string]::IsNullOrWhiteSpace($Path)) { $Path = ".mir/evidence/$($candidateInfo.version)-performance-regression.json" }
  $evidencePath = Resolve-MIRReleasePath -RepoRoot $RepoRoot -Path $Path
  if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) { throw "Runtime performance evidence is absent: $evidencePath" }
  $evidence = Get-Content -Raw -LiteralPath $evidencePath | ConvertFrom-Json
  if ([int]$evidence.schema -ne 3 -or [string]$evidence.kind -ne "mir-runtime-performance-regression") {
    throw "Runtime performance evidence must use mir-runtime-performance-regression schema 3."
  }
  if ([string]$evidence.status -ne "passed") { throw "Runtime performance evidence is not passed." }
  $campaignPath = if ([IO.Path]::IsPathRooted($CampaignPath)) {
    [IO.Path]::GetFullPath($CampaignPath)
  } else {
    [IO.Path]::GetFullPath((Join-Path $RepoRoot $CampaignPath))
  }
  if (-not (Test-Path -LiteralPath $campaignPath -PathType Leaf)) { throw "Runtime performance campaign authority is absent." }
  $campaign = Get-Content -Raw -LiteralPath $campaignPath | ConvertFrom-Json
  if ([int]$campaign.schema -ne 2 -or [string]$campaign.release -ne [string]$evidence.candidate.version -or
      [string]$campaign.factorio_version -notlike "$ExpectedFactorioVersion*") {
    throw "Runtime performance evidence does not bind a coherent governed target-era campaign."
  }
  $candidateSha = Get-MIRReleaseSha256 -Path $candidatePath
  $candidateContentSha = Get-MIRReleaseArchiveContentSha256 -Path $candidatePath
  if ([string]$evidence.candidate.archive_sha256 -ne $candidateSha -or
      [string]$evidence.candidate.package_content_sha256 -ne $candidateContentSha) {
    throw "Runtime performance evidence does not bind the exact candidate."
  }
  $null = Assert-MIRReleaseEvidenceSourceAuthority `
    -RepoRoot $RepoRoot `
    -CandidateInfo $candidateInfo `
    -CandidatePath $candidatePath `
    -ExpectedQualificationCommit $ExpectedSourceCommit `
    -RecordedEvidenceCommit ([string]$evidence.candidate.source_commit)
  $baselineSha = Get-MIRReleaseSha256 -Path $priorPath
  if ([string]$priorInfo.version -ne $ExpectedBaselineVersion -or
      [string]$evidence.baseline.version -ne $ExpectedBaselineVersion -or
      [string]$evidence.baseline.archive_sha256 -ne $baselineSha -or
      [string]$evidence.baseline.package_content_sha256 -ne (Get-MIRReleaseArchiveContentSha256 -Path $priorPath)) {
    throw "Runtime performance evidence does not bind the exact prior-release baseline."
  }
  if ([string]$priorInfo.version -eq "3.1.9" -and
      $baselineSha -ne "D77B3A78DA40CD4FDD4C829A01B5030E59FB593F3387124EF5C438F6A9E8DFCD") {
    throw "Runtime performance evidence did not use the sealed 3.1.9 baseline archive."
  }
  $factorioSha = Get-MIRReleaseSha256 -Path $FactorioBin
  $factorioVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($FactorioBin).FileVersion
  if ([string]$evidence.factorio.binary_sha256 -ne $factorioSha -or
      -not ([string]$evidence.factorio.version).StartsWith($ExpectedFactorioVersion) -or
      -not ([string]$factorioVersion).StartsWith($ExpectedFactorioVersion)) {
    throw "Runtime performance evidence is not bound to the exact qualified Factorio $ExpectedFactorioVersion binary."
  }
  foreach ($field in @("machine_sha256", "official_mods_sha256", "third_party_closure_sha256", "settings_sha256", "scenarios_sha256", "harness_sha256")) {
    if ([string]$evidence.comparability.$field -notmatch '^[0-9A-Fa-f]{64}$') {
      throw "Runtime performance evidence lacks comparable-run authority: $field"
    }
  }
  $minimumRuns = [int]$evidence.run_policy.minimum_measured_runs_per_package
  if ($minimumRuns -lt 5 -or [int]$evidence.run_policy.warmup_runs -lt 1 -or
      [string]$evidence.run_policy.order -ne "paired-balanced") {
    throw "Runtime performance evidence does not use the governed warm-up and paired-run policy."
  }
  $runOrder = @($evidence.run_order | ForEach-Object { [string]$_ })
  if (@($runOrder | Where-Object { $_ -eq "baseline" }).Count -lt $minimumRuns -or
      @($runOrder | Where-Object { $_ -eq "candidate" }).Count -lt $minimumRuns -or
      ($runOrder.Count % 2) -ne 0) {
    throw "Runtime performance run order does not contain the required measured pairs."
  }
  for ($index = 0; $index -lt $runOrder.Count; $index += 2) {
    $pair = (@($runOrder[$index], $runOrder[$index + 1]) | Sort-Object) -join ","
    if ($pair -ne "baseline,candidate") {
      throw "Runtime performance run order is not balanced within each measured pair."
    }
  }

  $targetManifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.mir\targets.json') | ConvertFrom-Json
  $targetLine = [string]$candidateInfo.factorio_version
  $targetProfile = $targetManifest.profiles.PSObject.Properties[$targetLine].Value
  $volumeMeasurements = @($evidence.artifact_volume.measurements)
  $artifactVolumeOmitted = $targetProfile.prototype_shapes.mod_data -eq $false
  if ($artifactVolumeOmitted) {
    if ([int]$evidence.artifact_volume.telemetry_schema -ne 0 -or
        [string]$evidence.artifact_volume.aggregation -ne 'omitted-by-capability' -or
        [string]$evidence.artifact_volume.capability -ne 'mod_data' -or $volumeMeasurements.Count -ne 0) {
      throw "Runtime performance evidence does not truthfully record the target's mod-data capability omission."
    }
  } elseif ([int]$evidence.artifact_volume.telemetry_schema -ne 1 -or
            [string]$evidence.artifact_volume.aggregation -ne "maximum-observed") {
    throw "Runtime performance evidence lacks the governed artifact-volume aggregation."
  }
  $volumeSurfaces = @($volumeMeasurements | ForEach-Object { [string]$_.surface })
  $actualVolumeSurfaces = (@($volumeSurfaces | Sort-Object) -join "`n")
  $expectedVolumeSurfaces = (@("diagnostics-off", "diagnostics-on") | Sort-Object) -join "`n"
  if (-not $artifactVolumeOmitted -and ($actualVolumeSurfaces -ne $expectedVolumeSurfaces -or
      @($volumeSurfaces | Group-Object | Where-Object Count -gt 1).Count -gt 0)) {
    throw "Runtime performance evidence must contain exactly diagnostics-off and diagnostics-on artifact-volume measurements."
  }
  $performancePolicy = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\performance.yml")
  $counterBlock = [regex]::Match($performancePolicy, '(?ms)required_counters:\s*(?<block>.*?)\s+required_phases:')
  if (-not $counterBlock.Success) { throw "Performance policy does not expose its required telemetry counter block." }
  $requiredVolumeCounters = @([regex]::Matches($counterBlock.Groups['block'].Value, '(?m)^\s*-\s+(?<name>[a-z0-9_-]+)\s*$') | ForEach-Object { $_.Groups['name'].Value })
  foreach ($measurement in $volumeMeasurements) {
    $fingerprints = @($measurement.telemetry_fingerprints | ForEach-Object { [string]$_ })
    if ([int]$measurement.measured_runs -lt $minimumRuns -or $fingerprints.Count -ne [int]$measurement.measured_runs -or
        @($fingerprints | Where-Object { $_ -notmatch '^[0-9A-Fa-f]{64}$' }).Count -gt 0) {
      throw "Artifact-volume measurement '$($measurement.surface)' does not bind every measured candidate run."
    }
    $counterNames = @($measurement.counters.PSObject.Properties.Name)
    foreach ($counterName in $requiredVolumeCounters) {
      if ($counterNames -notcontains $counterName -or [long]$measurement.counters.$counterName -lt 0) {
        throw "Artifact-volume measurement '$($measurement.surface)' lacks governed counter '$counterName'."
      }
    }
  }

  $budgetPath = Join-Path $RepoRoot ".mir\performance-budgets.json"
  $budgetManifest = Get-Content -Raw -LiteralPath $budgetPath | ConvertFrom-Json
  if ([int]$budgetManifest.schema -ne 2) { throw "Performance budget manifest must use schema 2." }
  foreach ($measurement in $volumeMeasurements) {
    foreach ($bound in @($budgetManifest.compiler_counter_bounds)) {
      $counter = [string]$bound.counter
      $property = $measurement.counters.PSObject.Properties[$counter]
      if ($null -eq $property -or [long]$property.Value -gt [long]$bound.maximum) {
        throw "Artifact-volume measurement '$($measurement.surface)' exceeds or omits compiler budget '$counter'."
      }
    }
  }
  $expectedLanes = @($budgetManifest.regression_lanes)
  $actualLanes = @($evidence.lanes)
  $actualIds = @($actualLanes | ForEach-Object { [string]$_.id })
  if (@($actualIds | Group-Object | Where-Object Count -gt 1).Count -gt 0) { throw "Runtime performance evidence has duplicate lane IDs." }
  if ((@($expectedLanes.id | Sort-Object) -join "`n") -ne (@($actualIds | Sort-Object) -join "`n")) {
    throw "Runtime performance evidence does not contain the exact governed lane set."
  }
  foreach ($policy in $expectedLanes) {
    $lane = @($actualLanes | Where-Object id -eq $policy.id)[0]
    $baselineRuns = @($lane.baseline.runs_seconds | ForEach-Object { [double]$_ })
    $candidateRuns = @($lane.candidate.runs_seconds | ForEach-Object { [double]$_ })
    if ($baselineRuns.Count -lt $minimumRuns -or $candidateRuns.Count -lt $minimumRuns -or
        @($baselineRuns + $candidateRuns | Where-Object { $_ -lt 0 }).Count -gt 0) {
      throw "Runtime performance lane '$($policy.id)' lacks non-negative measured runs."
    }
    $baselineStats = Get-MIRReleaseRunStatistics -Values $baselineRuns
    $candidateStats = Get-MIRReleaseRunStatistics -Values $candidateRuns
    Assert-MIRReleaseStatistic -Recorded $lane.baseline -Expected $baselineStats -Label "$($policy.id) baseline"
    Assert-MIRReleaseStatistic -Recorded $lane.candidate -Expected $candidateStats -Label "$($policy.id) candidate"
    $absoluteDelta = [Math]::Round([double]$candidateStats.median_seconds - [double]$baselineStats.median_seconds, 6)
    $percentDelta = if ([double]$baselineStats.median_seconds -eq 0) {
      if ($absoluteDelta -le 0) { 0 } else { [double]::PositiveInfinity }
    } else {
      [Math]::Round(($absoluteDelta / [double]$baselineStats.median_seconds) * 100, 6)
    }
    $withinRegression = $percentDelta -le [double]$policy.maximum_regression_percent -or
      $absoluteDelta -le [double]$policy.absolute_noise_allowance_seconds
    $withinAbsolute = $null -eq $policy.max_candidate_seconds -or
      [double]$candidateStats.median_seconds -le [double]$policy.max_candidate_seconds
    if (-not $withinRegression -or -not $withinAbsolute -or [string]$lane.status -ne "passed" -or
        [Math]::Abs([double]$lane.absolute_delta_seconds - $absoluteDelta) -gt 0.000001 -or
        ([double]::IsFinite($percentDelta) -and [Math]::Abs([double]$lane.percentage_delta - $percentDelta) -gt 0.000001)) {
      throw "Runtime performance lane failed or has incorrect deltas: $($policy.id)"
    }
  }
  return [pscustomobject][ordered]@{
    path = $evidencePath
    sha256 = Get-MIRReleaseSha256 -Path $evidencePath
    status = "passed"
    evidence = $evidence
  }
}

function Test-MIRManualReleaseAttestation {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$Path = "",
    [Parameter(Mandatory)][string]$Candidate,
    [Parameter(Mandatory)][string]$FactorioBin,
    [Parameter(Mandatory)][string]$ExpectedSourceCommit,
    [Parameter(Mandatory)][string]$ExpectedFactorioVersion
  )
  $candidatePath = Resolve-MIRReleasePath -RepoRoot $RepoRoot -Path $Candidate
  if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { throw "Manual review candidate is absent: $candidatePath" }
  if (-not (Test-Path -LiteralPath $FactorioBin -PathType Leaf)) { throw "Manual review Factorio binary is absent: $FactorioBin" }
  $candidateInfo = Get-MIRReleasePackageInfo -Path $candidatePath
  if ([string]::IsNullOrWhiteSpace($Path)) { $Path = ".mir/evidence/$($candidateInfo.version)-manual-review-attestation.json" }
  $attestationPath = Resolve-MIRReleasePath -RepoRoot $RepoRoot -Path $Path
  if (-not (Test-Path -LiteralPath $attestationPath -PathType Leaf)) { throw "Manual release attestation is absent: $attestationPath" }
  $attestation = Get-Content -Raw -LiteralPath $attestationPath | ConvertFrom-Json
  if ([int]$attestation.schema -ne 2 -or [string]$attestation.kind -ne "mir-manual-release-review" -or
      [string]$attestation.status -ne "passed" -or [string]$attestation.checklist_version -ne "mir-manual-release-review-v1") {
    throw "Manual release attestation is not a passing schema-2 package review."
  }
  if ([string]$attestation.candidate_sha256 -ne (Get-MIRReleaseSha256 -Path $candidatePath) -or
      [string]$attestation.candidate_content_sha256 -ne (Get-MIRReleaseArchiveContentSha256 -Path $candidatePath)) {
    throw "Manual release attestation does not bind the exact candidate."
  }
  $null = Assert-MIRReleaseEvidenceSourceAuthority `
    -RepoRoot $RepoRoot `
    -CandidateInfo $candidateInfo `
    -CandidatePath $candidatePath `
    -ExpectedQualificationCommit $ExpectedSourceCommit `
    -RecordedEvidenceCommit ([string]$attestation.source_commit) `
    -RequirePackageSourceEvidenceCommit
  $factorioVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($FactorioBin).FileVersion
  if (-not ([string]$attestation.factorio_version).StartsWith($ExpectedFactorioVersion) -or
      -not ([string]$factorioVersion).StartsWith($ExpectedFactorioVersion) -or
      [string]$attestation.factorio_binary_sha256 -ne (Get-MIRReleaseSha256 -Path $FactorioBin)) {
    throw "Manual release attestation is not bound to the exact qualified Factorio $ExpectedFactorioVersion binary."
  }
  if ([string]::IsNullOrWhiteSpace([string]$attestation.reviewer) -or
      [string]::IsNullOrWhiteSpace([string]$attestation.reviewed_at)) {
    throw "Manual release attestation lacks reviewer identity or review time."
  }
  $null = ConvertTo-MIRReleaseDateTimeOffset -Value $attestation.reviewed_at
  $expectedItems = @(
    "technology-tree-visual", "icon-visual", "locale-fit-and-truncation",
    "settings-ux", "save-ui", "human-balance", "configuration-change-give-item-safety"
  )
  $items = @($attestation.items)
  if ((@($items.id | Sort-Object) -join "`n") -ne (@($expectedItems | Sort-Object) -join "`n")) {
    throw "Manual release attestation does not contain the exact pre-seal package checklist."
  }
  foreach ($item in $items) {
    if ([string]$item.status -ne "passed" -or [string]::IsNullOrWhiteSpace([string]$item.notes) -or
        @($item.artifacts).Count -eq 0) {
      throw "Manual release checklist item is incomplete: $($item.id)"
    }
    foreach ($artifact in @($item.artifacts)) {
      $relative = ([string]$artifact.path).Replace("\", "/")
      if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains("..") -or $relative.Contains(":")) {
        throw "Manual review artifact path is not portable: $relative"
      }
      $artifactPath = Resolve-MIRReleasePath -RepoRoot $RepoRoot -Path $relative
      if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf) -or
          [string]$artifact.sha256 -ne (Get-MIRReleasePortableArtifactSha256 -Path $artifactPath)) {
        throw "Manual review artifact is absent or has the wrong hash: $relative"
      }
    }
  }
  $material = ConvertTo-MIRReleaseOrderedMap -Object $attestation
  $material.Remove("attestation_sha256")
  $expectedAttestationSha = Get-MIRReleaseTextSha256 -Text ($material | ConvertTo-Json -Depth 40 -Compress)
  if ([string]$attestation.attestation_sha256 -ne $expectedAttestationSha) {
    throw "Manual release attestation self-hash is invalid."
  }
  return [pscustomobject][ordered]@{
    path = $attestationPath
    sha256 = Get-MIRReleaseSha256 -Path $attestationPath
    status = "passed"
    evidence = $attestation
  }
}
