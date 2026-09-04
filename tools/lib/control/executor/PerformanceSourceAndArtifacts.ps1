function Assert-MIRCPPerformanceCampaignAuthority {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Descriptor,
    [Parameter(Mandatory)]$TargetProfile,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $campaign = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $Path) | ConvertFrom-Json
  $baseline = Get-MIRCPReleaseByVersion -Release ([string]$campaign.baseline.version) -RepoRoot $repo
  $currentRoles = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\releases\records\current.json") | ConvertFrom-Json
  $currentTargetRelease = if ([string]$Descriptor.target -eq "2.1") {
    [string]$currentRoles.roles.latest_tagged_factorio_2_1
  } elseif ([string]$Descriptor.target -eq "2.0") {
    [string]$currentRoles.roles.latest_tagged_factorio_2_0
  } else {
    ""
  }
  $historicalCampaign = -not [string]::IsNullOrWhiteSpace($currentTargetRelease) -and [string]$Descriptor.release -ne $currentTargetRelease
  $factorioVersionMatches = if ($historicalCampaign) {
    [string]$campaign.factorio_version -match ('^' + [regex]::Escape([string]$Descriptor.target) + '\.\d+$')
  } else {
    [string]$campaign.factorio_version -eq [string]$TargetProfile.qualification_factorio_version
  }
  $baselineMatchesProfile = $historicalCampaign -or [string]$campaign.baseline.version -eq [string]$TargetProfile.upgrade.from_version
  if ([int]$campaign.schema -ne 2 -or [string]$campaign.release -ne [string]$Descriptor.release -or
      [string]$campaign.factorio_line -ne [string]$Descriptor.target -or
      -not $factorioVersionMatches -or -not $baselineMatchesProfile -or
      [string]$campaign.baseline.version -ne [string]$baseline.release -or
      [string]$campaign.baseline.archive_sha256 -ne [string]$baseline.package.archive_sha256 -or
      [string]$campaign.baseline.package_content_sha256 -ne [string]$baseline.package.content_sha256 -or
      [string]$campaign.candidate.candidate_id -ne [string]$Descriptor.candidate_id -or
      [string]$campaign.candidate.version -ne [string]$Descriptor.release -or
      [string]$campaign.candidate.package_source_commit -ne [string]$Descriptor.source_commit -or
      [string]$campaign.candidate.package_source_sha256 -ne [string]$Descriptor.source_sha256 -or
      [string]$campaign.candidate.archive_sha256 -ne [string]$Descriptor.archive_sha256 -or
      [string]$campaign.candidate.package_content_sha256 -ne [string]$Descriptor.content_sha256) {
    throw "Performance campaign does not bind the immutable context candidate, baseline, target, and Factorio version."
  }
  return [pscustomobject][ordered]@{campaign=$campaign;sha256=(Get-MIRCPSha256File -Path (Resolve-Path -LiteralPath $Path).Path);historical=$historicalCampaign}
}

function Set-MIRCPCanonicalPerformanceProbeText {
  param([Parameter(Mandatory)][string]$OverlayRoot)
  $relativePath = "fixtures/performance-regression-probe/data-final-fixes.lua"
  $path = Join-Path $OverlayRoot $relativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Performance probe final-fixes source is absent: $path"
  }
  $text = [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
  if ([string]::IsNullOrWhiteSpace($text)) { throw "Performance probe final-fixes source is empty." }
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
  [IO.File]::WriteAllBytes($path, $bytes)
  if ($bytes -contains [byte]13) { throw "Canonical performance probe still contains carriage returns." }
  return [pscustomobject][ordered]@{
    path = $relativePath
    materialization = "utf8-no-bom-lf-v1"
    bytes = [int64]$bytes.Length
    line_feeds = @($bytes | Where-Object { $_ -eq 10 }).Count
    sha256 = Get-MIRCPSha256File -Path $path
  }
}

function New-MIRCPPerformanceSourceOverlay {
  param(
    [Parameter(Mandatory)]$State,
    [Parameter(Mandatory)]$Source,
    [Parameter(Mandatory)]$Descriptor,
    [Parameter(Mandatory)]$TargetProfile,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  . (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")
  $authorityRelativePath = Get-MIRCPPerformanceCampaignRelativePath -Descriptor $Descriptor -RepoRoot $repo
  $authorityPath = Join-Path $repo $authorityRelativePath
  $authority = Assert-MIRCPPerformanceCampaignAuthority -Path $authorityPath -Descriptor $Descriptor -TargetProfile $TargetProfile -RepoRoot $repo
  $root = Join-Path $repo "build/results/control-plane-v5/source-overlays/$([string]$State.context.context_id)"
  $destination = Join-Path $root "performance"
  if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
    [void](New-Item -ItemType Directory -Force -Path $root)
    $staging = Join-Path $root ("performance-staging-" + [guid]::NewGuid().ToString("N"))
    & git clone --local --no-hardlinks --no-checkout -- ([string]$Source.path) $staging 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Could not clone the immutable qualification source for the performance authority overlay." }
    & git -C $staging checkout --detach ([string]$Source.commit) 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Could not check out the immutable qualification source for the performance authority overlay." }
    Move-Item -LiteralPath $staging -Destination $destination
  }
  $head = ([string](& git -C $destination rev-parse HEAD)).Trim()
  if ($LASTEXITCODE -ne 0 -or $head -ne [string]$Source.commit) { throw "Performance authority overlay source commit differs from the immutable context source." }
  $overlayPath = Join-Path $destination ".mir/performance-campaign.json"
  [IO.File]::Copy($authorityPath, $overlayPath, $true)
  if ((Get-MIRCPSha256File -Path $overlayPath) -ne [string]$authority.sha256) { throw "Performance authority overlay changed the governed campaign bytes." }
  $controllerOverlayRelativePaths = @(
    "scripts/Invoke-MIRCompatAudit.ps1",
    "tools/commands/compatibility/Invoke-MIRCompatAudit.ps1",
    "tools/commands/compatibility/compat-audit/Configuration.ps1",
    "tools/commands/compatibility/compat-audit/InputDiscovery.ps1",
    "tools/commands/compatibility/compat-audit/ScenarioDefinitions.ps1",
    "tools/commands/compatibility/compat-audit/ScenarioResolution.ps1",
    "tools/commands/compatibility/compat-audit/ScenarioSelection.ps1",
    "tools/commands/compatibility/compat-audit/ResultCollation.ps1",
    "scripts/MIRCompatAudit/DependencyResolver.ps1",
    "scripts/MIRCompatAudit/DiagnosticsParser.ps1",
    "scripts/MIRCompatAudit/FactorioRunner.ps1",
    "scripts/MIRCompatAudit/ModPortal.ps1",
    "scripts/validation/PackageIdentity.ps1",
    "scripts/validation/PerformanceCampaign.ps1",
    "scripts/validation/ReleaseAttestations.ps1",
    "scripts/validation/SettingsOverrides.ps1",
    "tools/lib/compatibility/DependencyResolver.ps1",
    "tools/lib/compatibility/DiagnosticsParser.ps1",
    "tools/lib/compatibility/FactorioRunner.ps1",
    "tools/lib/compatibility/ModPortal.ps1",
    "tools/lib/validation/PackageIdentity.ps1",
    "tools/lib/validation/PerformanceCampaign.ps1",
    "tools/lib/validation/ReleaseAttestations.ps1",
    "tools/lib/validation/SettingsOverrides.ps1",
    "validation/adapters/portal-exclusions.json",
    "validation/scenarios/local-2.1.json",
    "validation/scenarios/manual.json"
  )
  $controllerOverlayRows = [Collections.Generic.List[object]]::new()
  foreach ($relativePath in $controllerOverlayRelativePaths) {
    $controllerPath = Join-Path $repo $relativePath
    if (-not (Test-Path -LiteralPath $controllerPath -PathType Leaf)) {
      throw "Performance controller overlay dependency is absent: $relativePath"
    }
    $overlayDependencyPath = Join-Path $destination $relativePath
    [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $overlayDependencyPath))
    [IO.File]::Copy($controllerPath, $overlayDependencyPath, $true)
    $sha256 = Get-MIRCPSha256File -Path $controllerPath
    if ((Get-MIRCPSha256File -Path $overlayDependencyPath) -ne $sha256) {
      throw "Performance controller overlay changed dependency bytes: $relativePath"
    }
    $controllerOverlayRows.Add([pscustomobject][ordered]@{
      path = $relativePath
      materialization = "controller-exact-bytes-v1"
      bytes = [int64](Get-Item -LiteralPath $overlayDependencyPath).Length
      sha256 = $sha256
    })
  }
  $probe = Set-MIRCPCanonicalPerformanceProbeText -OverlayRoot $destination
  $status = @(& git -C $destination status --porcelain --untracked-files=all)
  $allowedPaths = @(
    ".mir/performance-campaign.json"
    "fixtures/performance-regression-probe/data-final-fixes.lua"
    $controllerOverlayRelativePaths
  )
  $unexpected = @($status | Where-Object {
    $statusPath = ([string]$_).Substring(3).Replace("\", "/")
    $allowedPaths -notcontains $statusPath
  })
  if ($unexpected.Count -ne 0) { throw "Performance authority overlay contains changes outside its governed package-excluded files." }
  $canonicalPackageLayout = (
    (Test-Path -LiteralPath (Join-Path $destination 'src/mod/package-source.json') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $destination 'targets/package-authority.json') -PathType Leaf)
  )
  $packageSha256 = if ($canonicalPackageLayout) {
    Get-MIRPackageSourceFingerprint -RepoRoot $destination
  } else {
    Get-MIRLegacyRootPackageSourceFingerprint -RepoRoot $destination
  }
  if ($packageSha256 -ne [string]$Descriptor.source_sha256) { throw "Performance authority overlay changed package-visible source." }
  $harnessSha256 = & {
    param([string]$Root)
    . (Join-Path $Root "tools/lib/validation/PerformanceCampaign.ps1")
    Get-MIRPerformanceHarnessFingerprint -RepoRoot $Root
  } $destination
  $manifest = [pscustomobject][ordered]@{
    schema = 1
    kind = "mir-performance-source-overlay"
    source_commit = [string]$Source.commit
    files = @(
      [pscustomobject][ordered]@{path=".mir/performance-campaign.json";materialization="controller-exact-bytes-v1";bytes=[int64](Get-Item -LiteralPath $overlayPath).Length;sha256=[string]$authority.sha256},
      $probe
      foreach ($controllerOverlayRow in $controllerOverlayRows) { $controllerOverlayRow }
    )
    harness_sha256 = [string]$harnessSha256
    package_source_sha256 = $packageSha256
  }
  return [pscustomobject][ordered]@{
    path = $destination
    authority = $authority
    authority_sha256 = [string]$authority.sha256
    canonical_probe = $probe
    harness_sha256 = [string]$harnessSha256
    manifest = $manifest
    manifest_sha256 = Get-MIRCPSha256Object -Value $manifest
    package_source_sha256 = $packageSha256
  }
}

function New-MIRCPCompactPerformanceArtifactRoot {
  param(
    [Parameter(Mandatory)]$State,
    [Parameter(Mandatory)]$Campaign
  )
  $contextId = [string]$State.context.context_id
  if ($contextId -notmatch '^[0-9A-F]{64}$') {
    throw "Compact performance staging requires an exact context digest."
  }
  $scratchParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $path = Join-Path $scratchParent ("mircp-p-" + $contextId.Substring(0, 24))
  if (Test-Path -LiteralPath $path) {
    throw "Compact performance staging already exists and will not be overwritten: $path"
  }
  $maximumPathLength = 0
  $maximumPath = ""
  foreach ($lane in @($Campaign.lanes | Where-Object { [string]$_.runner -eq "exact-package-load" })) {
    $laneSafe = ([string]$lane.id -replace '[^A-Za-z0-9_.-]', '-').Trim('-')
    $probePath = Join-Path $path ("{0}\measured-25-candidate\mods\mir-fixture-performance-regression-probe_0.1.0\data-final-fixes.lua" -f $laneSafe)
    if ($probePath.Length -gt $maximumPathLength) {
      $maximumPathLength = $probePath.Length
      $maximumPath = $probePath
    }
  }
  foreach ($lane in @($Campaign.lanes | Where-Object { [string]$_.runner -eq "compat-audit" })) {
    $laneSafe = ([string]$lane.id -replace '[^A-Za-z0-9_.-]', '-').Trim('-')
    $compatPath = Join-Path $path ("{0}\measured-25-candidate\compat\runs\u-0123456789ab\mods\mir-validation-settings-overrides\settings-updates.lua" -f $laneSafe)
    if ($compatPath.Length -gt $maximumPathLength) {
      $maximumPathLength = $compatPath.Length
      $maximumPath = $compatPath
    }
  }
  $pathBudget = 240
  if ($maximumPathLength -gt $pathBudget) {
    throw "Compact performance staging exceeds the conservative Factorio path budget ($maximumPathLength > $pathBudget): $maximumPath"
  }
  [void](New-Item -ItemType Directory -Path $path)
  $marker = [pscustomobject][ordered]@{
    schema = 1
    kind = "mir-control-plane-performance-execution-root"
    context_id = $contextId
    strategy = "compact-context-scratch-v1"
    conservative_path_budget = $pathBudget
    maximum_factorio_path_length = $maximumPathLength
  }
  $markerPath = Join-Path $path "control-plane-execution-root.json"
  $marker | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $markerPath -Encoding UTF8
  return [pscustomobject][ordered]@{
    path = $path
    marker_path = $markerPath
    context_id = $contextId
    strategy = [string]$marker.strategy
    conservative_path_budget = $pathBudget
    maximum_factorio_path_length = $maximumPathLength
  }
}

function Move-MIRCPPerformanceArtifacts {
  param(
    [Parameter(Mandatory)]$ExecutionRoot,
    [Parameter(Mandatory)][string]$Destination
  )
  if (-not (Test-Path -LiteralPath ([string]$ExecutionRoot.path) -PathType Container)) {
    throw "Compact performance execution root is absent: $($ExecutionRoot.path)"
  }
  if (Test-Path -LiteralPath $Destination) {
    throw "Performance artifact destination already exists and will not be merged: $Destination"
  }
  $verified = Copy-MIRPerformanceArtifactsVerified -SourceRoot ([string]$ExecutionRoot.path) -DestinationRoot $Destination
  Remove-Item -LiteralPath ([string]$ExecutionRoot.path) -Recurse -Force
  if (Test-Path -LiteralPath ([string]$ExecutionRoot.path)) { throw "Compact performance execution root still exists after verified artifact relocation." }
  $markerPath = Join-Path $Destination "control-plane-execution-root.json"
  if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
    throw "Relocated performance artifacts lack their execution-root binding marker."
  }
  $marker = Get-Content -Raw -LiteralPath $markerPath | ConvertFrom-Json
  if ([string]$marker.context_id -ne [string]$ExecutionRoot.context_id -or
      [string]$marker.strategy -ne [string]$ExecutionRoot.strategy) {
    throw "Relocated performance artifacts do not bind the expected context and staging strategy."
  }
  return [pscustomobject][ordered]@{
    path = $Destination
    strategy = [string]$marker.strategy
    context_id = [string]$marker.context_id
    conservative_path_budget = [int]$marker.conservative_path_budget
    maximum_factorio_path_length = [int]$marker.maximum_factorio_path_length
    file_count = [int]$verified.file_count
    bytes = [int64]$verified.bytes
    artifact_tree_sha256 = [string]$verified.artifact_tree_sha256
    artifacts = @($verified.artifacts)
  }
}
