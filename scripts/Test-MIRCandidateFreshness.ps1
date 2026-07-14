param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
. (Join-Path $repo "scripts\validation\TargetProfiles.ps1")

function Get-MIRCandidateFields {
  param([Parameter(Mandatory)][string]$Text)

  $match = [regex]::Match(
    $Text,
    '(?ms)^candidate:\r?\n(?<body>(?:^  [^\r\n]*\r?\n?)*)'
  )
  if (-not $match.Success) {
    throw ".mir/convergence.yml must define a top-level candidate block."
  }

  $fields = @{}
  foreach ($line in $match.Groups["body"].Value -split "\r?\n") {
    if ($line -match '^  ([a-z0-9_]+):\s*(.*?)\s*$') {
      $fields[$matches[1]] = $matches[2].Trim().Trim('"')
    }
  }
  return $fields
}

function Get-MIRRequiredCandidateField {
  param(
    [Parameter(Mandatory)]$Fields,
    [Parameter(Mandatory)][string]$Name
  )

  if (-not $Fields.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace([string]$Fields[$Name])) {
    throw "Active release candidate is missing $Name."
  }
  return [string]$Fields[$Name]
}

function Get-MIRCandidateEvidenceJson {
  param(
    [Parameter(Mandatory)]$Fields,
    [Parameter(Mandatory)][string]$Field,
    [Parameter(Mandatory)][string]$Label
  )

  $relative = Get-MIRRequiredCandidateField -Fields $Fields -Name $Field
  $path = Join-Path $repo $relative
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "$Label evidence is missing: $relative"
  }
  try {
    return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  } catch {
    throw "$Label evidence is not valid JSON: $relative"
  }
}

function Assert-MIRCandidateBoundEvidence {
  param(
    [Parameter(Mandatory)]$Fields,
    [Parameter(Mandatory)][string]$PackageSourceCommit,
    [Parameter(Mandatory)][string]$ArchiveSha256,
    [Parameter(Mandatory)][string]$PackageContentSha256,
    [Parameter(Mandatory)][string]$PackageSourceSha256,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][ValidateSet("pending", "passed")][string]$InteractiveStatus
  )

  $upgrade = Get-MIRCandidateEvidenceJson -Fields $Fields -Field "upgrade_evidence_path" -Label "Upgrade"
  if ([int]$upgrade.schema -ne 1 -or [string]$upgrade.status -ne "passed") {
    throw "Upgrade evidence must be schema 1 with status passed."
  }
  if ([string]$upgrade.to.version -ne $Version -or [string]$upgrade.to.sha256 -ne $ArchiveSha256) {
    throw "Upgrade evidence is not bound to the active candidate version and archive."
  }
  $upgradeCommit = [string]$upgrade.git_commit
  if ($upgradeCommit -notmatch '^[0-9a-f]{40}$') {
    throw "Upgrade evidence must identify the full harness commit that produced it."
  }
  & git -C $repo cat-file -e "$upgradeCommit^{commit}" 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Upgrade evidence commit is unavailable: $upgradeCommit"
  }
  & git -C $repo merge-base --is-ancestor $PackageSourceCommit $upgradeCommit
  if ($LASTEXITCODE -ne 0) {
    throw "Upgrade evidence was produced before the active package source commit."
  }

  $campaign = Get-MIRCandidateEvidenceJson -Fields $Fields -Field "ecosystem_evidence_path" -Label "Ecosystem campaign"
  if ([int]$campaign.schema -ne 1 -or [string]$campaign.kind -ne "mir-modpack-campaign-evidence") {
    throw "Ecosystem campaign evidence must be schema 1 mir-modpack-campaign-evidence."
  }
  if ([string]$campaign.mir_archive.source_commit -ne $PackageSourceCommit -or [string]$campaign.mir_archive.sha256 -ne $ArchiveSha256) {
    throw "Ecosystem campaign evidence is not bound to the active candidate source and archive."
  }
  $failedCampaignRows = @($campaign.scenarios | Where-Object {
    [string]$_.result -ne "passed" -or [int]$_.dependency_failure_count -ne 0 -or
    [string]$_.claim_level -notin @("loads", "observed", "cooperates", "partial-family", "full-family")
  })
  if (@($campaign.scenarios).Count -eq 0 -or $failedCampaignRows.Count -gt 0) {
    throw "Ecosystem campaign evidence contains no scenarios or a non-passing/malformed scenario."
  }

  $interactive = Get-MIRCandidateEvidenceJson -Fields $Fields -Field "interactive_evidence_path" -Label "Interactive review"
  if ([int]$interactive.schema -ne 1 -or [string]$interactive.kind -ne "mir-interactive-review") {
    throw "Interactive review evidence must be schema 1 mir-interactive-review."
  }
  foreach ($binding in ([ordered]@{
    status = $InteractiveStatus
    version = $Version
    source_commit = $PackageSourceCommit
    archive_sha256 = $ArchiveSha256
    package_content_sha256 = $PackageContentSha256
    package_source_sha256 = $PackageSourceSha256
  }).GetEnumerator()) {
    if ([string]$interactive.($binding.Key) -ne [string]$binding.Value) {
      throw "Interactive review $($binding.Key) is stale: expected $($binding.Value), current $($interactive.($binding.Key))."
    }
  }
  if ($InteractiveStatus -eq "passed") {
    if ([string]::IsNullOrWhiteSpace([string]$interactive.reviewer) -or [string]::IsNullOrWhiteSpace([string]$interactive.reviewed_at)) {
      throw "Passed interactive review evidence must identify the reviewer and review time."
    }
    $captures = @($interactive.captures)
    if ($captures.Count -lt 3) {
      throw "Passed interactive review evidence requires at least three bound captures."
    }
    foreach ($capture in $captures) {
      $capturePath = Join-Path $repo ([string]$capture.path)
      if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) {
        throw "Interactive review capture is missing: $($capture.path)"
      }
      if ((Get-MIRFileSha256 -Path $capturePath) -ne [string]$capture.sha256) {
        throw "Interactive review capture hash is stale: $($capture.path)"
      }
    }
  }
}

$manifestPath = Join-Path $repo ".mir\convergence.yml"
$manifestText = Get-Content -Raw -LiteralPath $manifestPath
$candidate = Get-MIRCandidateFields -Text $manifestText
$status = Get-MIRRequiredCandidateField -Fields $candidate -Name "status"
$allowedStatuses = @(
  "rebuilding-after-package-visible-change",
  "requalifying-after-validation-harness-change",
  "release-candidate-awaiting-manual-review",
  "release-candidate-accepted",
  "published"
)
if ($status -notin $allowedStatuses) {
  throw "Unsupported MIR release candidate status: $status"
}

if ($status -eq "rebuilding-after-package-visible-change") {
  if ((Get-MIRRequiredCandidateField -Fields $candidate -Name "source_commit") -ne "pending") {
    throw "A rebuilding candidate must use source_commit: pending."
  }
  if ((Get-MIRRequiredCandidateField -Fields $candidate -Name "automated_gate") -ne "pending") {
    throw "A rebuilding candidate must use automated_gate: pending."
  }
  $allowedRebuildingFields = @("artifact", "source_commit", "automated_gate", "manual_gate", "status")
  $staleFields = @($candidate.Keys | Where-Object { $_ -notin $allowedRebuildingFields })
  if ($staleFields.Count -gt 0) {
    throw "A rebuilding candidate must not retain obsolete pass/hash fields: $($staleFields -join ', ')."
  }
  Write-Host "[ok] MIR release evidence is explicitly rebuilding; stale candidate bytes cannot be promoted."
  exit 0
}

if ($status -eq "requalifying-after-validation-harness-change") {
  if ((Get-MIRRequiredCandidateField -Fields $candidate -Name "source_commit") -ne "pending") {
    throw "A harness-requalifying candidate must use source_commit: pending."
  }
  $packageSourceCommit = Get-MIRRequiredCandidateField -Fields $candidate -Name "package_source_commit"
  if ($packageSourceCommit -notmatch '^[0-9a-f]{40}$') {
    throw "A harness-requalifying candidate must retain a full package_source_commit."
  }
  & git -C $repo cat-file -e "$packageSourceCommit^{commit}" 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Harness-requalifying package source commit is unavailable: $packageSourceCommit"
  }
  if ((Get-MIRRequiredCandidateField -Fields $candidate -Name "automated_gate") -ne "pending-requalification") {
    throw "A harness-requalifying candidate must use automated_gate: pending-requalification."
  }
  $allowedFields = @("artifact", "source_commit", "package_source_commit", "automated_gate", "manual_gate", "status")
  $staleFields = @($candidate.Keys | Where-Object { $_ -notin $allowedFields })
  if ($staleFields.Count -gt 0) {
    throw "A harness-requalifying candidate must not retain obsolete pass/hash fields: $($staleFields -join ', ')."
  }
  if (Test-MIRPackageSourceGitDirty -RepoRoot $repo) {
    throw "Package-visible working-tree changes are not allowed during harness-only requalification."
  }
  Write-Host "[ok] MIR release evidence is explicitly requalifying after a validation-harness change; stale evidence cannot be promoted."
  exit 0
}

$info = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json
$profile = Get-MIRTargetProfile -RepoRoot $repo -FactorioVersion ([string]$info.factorio_version)
$requiredGroups = @($profile.required_validation_groups | ForEach-Object { [string]$_ } | Sort-Object -Unique)

$sourceCommit = Get-MIRRequiredCandidateField -Fields $candidate -Name "source_commit"
if ($sourceCommit -notmatch '^[0-9a-f]{40}$') {
  throw "Active release candidate source_commit must be a full lowercase Git object ID."
}
& git -C $repo cat-file -e "$sourceCommit^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
  throw "Active release candidate source commit is not available locally: $sourceCommit"
}
$packageSourceCommit = Get-MIRRequiredCandidateField -Fields $candidate -Name "package_source_commit"
if ($packageSourceCommit -notmatch '^[0-9a-f]{40}$') {
  throw "Active release candidate package_source_commit must be a full lowercase Git object ID."
}
& git -C $repo cat-file -e "$packageSourceCommit^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
  throw "Active release candidate package source commit is not available locally: $packageSourceCommit"
}

if (Test-MIRPackageSourceGitDirty -RepoRoot $repo) {
  throw "Package-visible working-tree changes make the active release candidate stale."
}
if (Test-MIRRepositoryGitDirty -RepoRoot $repo) {
  throw "The entire repository working tree must be clean before candidate promotion."
}

if ($status -eq "published") {
  if ((Get-MIRRequiredCandidateField -Fields $candidate -Name "automated_gate") -ne "passed") {
    throw "A published candidate must retain automated_gate: passed."
  }
  if ((Get-MIRRequiredCandidateField -Fields $candidate -Name "manual_gate") -ne "accepted-for-publication") {
    throw "A published candidate must record manual_gate: accepted-for-publication."
  }

  $artifactRelative = Get-MIRRequiredCandidateField -Fields $candidate -Name "artifact"
  $artifactPath = Join-Path $repo $artifactRelative
  if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
    throw "Published release artifact is missing: $artifactRelative"
  }
  foreach ($field in @("sha256", "package_content_sha256")) {
    $actual = if ($field -eq "sha256") {
      Get-MIRFileSha256 -Path $artifactPath
    } else {
      Get-MIRZipContentFingerprint -Path $artifactPath
    }
    $expected = Get-MIRRequiredCandidateField -Fields $candidate -Name $field
    if ($actual -ne $expected) {
      throw "Published release artifact $field changed: expected $expected, current $actual."
    }
  }
  Assert-MIRCandidateBoundEvidence `
    -Fields $candidate `
    -PackageSourceCommit $packageSourceCommit `
    -ArchiveSha256 (Get-MIRRequiredCandidateField -Fields $candidate -Name "sha256") `
    -PackageContentSha256 (Get-MIRRequiredCandidateField -Fields $candidate -Name "package_content_sha256") `
    -PackageSourceSha256 (Get-MIRRequiredCandidateField -Fields $candidate -Name "package_source_sha256") `
    -Version ([string]$info.version) `
    -InteractiveStatus "passed"

  $summaryRelative = Get-MIRRequiredCandidateField -Fields $candidate -Name "structured_summary_path"
  $summaryPath = Join-Path $repo $summaryRelative
  if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
    throw "Published candidate structured summary is missing: $summaryRelative"
  }
  $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
  $publishedSummaryExpectations = [ordered]@{
    schema = 2
    status = "passed"
    run_id = Get-MIRRequiredCandidateField -Fields $candidate -Name "structured_summary_run_id"
    git_commit = $sourceCommit
    target_profile_sha256 = Get-MIRRequiredCandidateField -Fields $candidate -Name "target_profile_sha256"
    required_groups_sha256 = Get-MIRRequiredCandidateField -Fields $candidate -Name "required_groups_sha256"
    package_source_sha256 = Get-MIRRequiredCandidateField -Fields $candidate -Name "package_source_sha256"
    validation_package_sha256 = Get-MIRRequiredCandidateField -Fields $candidate -Name "validation_package_sha256"
    validation_package_content_sha256 = Get-MIRRequiredCandidateField -Fields $candidate -Name "validation_package_content_sha256"
    validation_harness_sha256 = Get-MIRRequiredCandidateField -Fields $candidate -Name "validation_harness_sha256"
    expected_scenarios_sha256 = Get-MIRRequiredCandidateField -Fields $candidate -Name "expected_scenarios_sha256"
  }
  foreach ($field in $publishedSummaryExpectations.Keys) {
    if ([string]$summary.$field -ne [string]$publishedSummaryExpectations[$field]) {
      throw "Published structured summary $field does not match recorded candidate evidence."
    }
  }
  if ([bool]$summary.package_source_git_dirty -or [bool]$summary.validation_harness_git_dirty) {
    throw "Published structured summary must come from clean package-source and validation-harness state."
  }
  $failedRequiredGroups = @($summary.groups | Where-Object { [bool]$_.required -and $_.status -ne "passed" })
  if ($failedRequiredGroups.Count -gt 0) {
    throw "Published structured summary contains a required group that did not pass."
  }

  $releaseCommit = Get-MIRRequiredCandidateField -Fields $candidate -Name "release_commit"
  $releaseTag = Get-MIRRequiredCandidateField -Fields $candidate -Name "release_tag"
  & git -C $repo cat-file -e "$releaseCommit^{commit}" 2>$null
  if ($LASTEXITCODE -ne 0) { throw "Published release commit is not available locally: $releaseCommit" }
  $tagCommit = (& git -C $repo rev-parse "$releaseTag^{commit}" 2>$null)
  if ($LASTEXITCODE -ne 0 -or ([string]$tagCommit).Trim() -ne $releaseCommit) {
    throw "Published release tag $releaseTag does not resolve to $releaseCommit."
  }
  & git -C $repo merge-base --is-ancestor $sourceCommit $releaseCommit
  if ($LASTEXITCODE -ne 0) {
    throw "Published release commit does not contain the validated source commit."
  }
  & git -C $repo merge-base --is-ancestor $packageSourceCommit $releaseCommit
  if ($LASTEXITCODE -ne 0) {
    throw "Published release commit does not contain the package source commit."
  }

  Write-Host "[ok] MIR published release archive, tag, and recorded validation evidence are immutable and consistent."
  exit 0
}

$packageRoots = @(Get-MIRPackageSourceRoots)
$changedPackagePaths = @(& git -C $repo diff --name-only $packageSourceCommit HEAD -- @packageRoots)
if ($LASTEXITCODE -ne 0) {
  throw "Unable to compare active candidate source against HEAD."
}
if ($changedPackagePaths.Count -gt 0) {
  throw "Package-visible paths changed after the active candidate package source commit: $($changedPackagePaths -join ', ')"
}

$artifactRelative = Get-MIRRequiredCandidateField -Fields $candidate -Name "artifact"
$artifactPath = Join-Path $repo $artifactRelative
if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
  throw "Active release candidate artifact is missing: $artifactRelative"
}

$checks = [ordered]@{
  sha256 = Get-MIRFileSha256 -Path $artifactPath
  package_content_sha256 = Get-MIRZipContentFingerprint -Path $artifactPath
  package_source_sha256 = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  target_profile_sha256 = Get-MIRTargetProfileFingerprint -Profile $profile
  required_groups_sha256 = Get-MIRRequiredGroupsFingerprint -RequiredGroups $requiredGroups
  validation_harness_sha256 = Get-MIRValidationHarnessFingerprint -RepoRoot $repo
  expected_scenarios_sha256 = Get-MIRFileContentSha256 `
    -Path (Join-Path $repo "fixtures\compat-matrix\expected-scenarios.json") `
    -RelativePath "fixtures/compat-matrix/expected-scenarios.json"
}
foreach ($field in $checks.Keys) {
  $expected = Get-MIRRequiredCandidateField -Fields $candidate -Name $field
  if ($expected -ne $checks[$field]) {
    throw "Active release candidate $field is stale: expected $expected, current $($checks[$field])."
  }
}

$expectedManualGate = if ($status -eq "release-candidate-accepted") { "accepted-for-publication" } else { "pending" }
if ((Get-MIRRequiredCandidateField -Fields $candidate -Name "automated_gate") -ne "passed") {
  throw "An active release candidate must record automated_gate: passed."
}
if ((Get-MIRRequiredCandidateField -Fields $candidate -Name "manual_gate") -ne $expectedManualGate) {
  throw "Candidate status $status requires manual_gate: $expectedManualGate."
}
Assert-MIRCandidateBoundEvidence `
  -Fields $candidate `
  -PackageSourceCommit $packageSourceCommit `
  -ArchiveSha256 $checks.sha256 `
  -PackageContentSha256 $checks.package_content_sha256 `
  -PackageSourceSha256 $checks.package_source_sha256 `
  -Version ([string]$info.version) `
  -InteractiveStatus $(if ($status -eq "release-candidate-accepted") { "passed" } else { "pending" })

$summaryRelative = Get-MIRRequiredCandidateField -Fields $candidate -Name "structured_summary_path"
$summaryPath = Join-Path $repo $summaryRelative
if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
  throw "Active release candidate structured summary is missing: $summaryRelative"
}
$summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
$summaryExpectations = [ordered]@{
  schema = 2
  status = "passed"
  run_id = Get-MIRRequiredCandidateField -Fields $candidate -Name "structured_summary_run_id"
  mir_version = [string]$info.version
  factorio_version = [string]$info.factorio_version
  git_commit = $sourceCommit
  target_profile_sha256 = $checks.target_profile_sha256
  required_groups_sha256 = $checks.required_groups_sha256
  package_source_sha256 = $checks.package_source_sha256
  validation_package_sha256 = Get-MIRRequiredCandidateField -Fields $candidate -Name "validation_package_sha256"
  validation_package_content_sha256 = $checks.package_content_sha256
  validation_harness_sha256 = $checks.validation_harness_sha256
  expected_scenarios_sha256 = $checks.expected_scenarios_sha256
}
foreach ($field in $summaryExpectations.Keys) {
  if ([string]$summary.$field -ne [string]$summaryExpectations[$field]) {
    throw "Structured summary $field does not match active candidate evidence."
  }
}
if ([bool]$summary.package_source_git_dirty) {
  throw "Structured summary was produced from a package-visible dirty tree."
}
if ([bool]$summary.validation_harness_git_dirty) {
  throw "Structured summary was produced from a dirty validation harness."
}

$summaryRequired = @($summary.required_groups | ForEach-Object { [string]$_ } | Sort-Object -Unique)
if (@(Compare-Object -ReferenceObject $requiredGroups -DifferenceObject $summaryRequired).Count -gt 0) {
  throw "Structured summary required-group snapshot differs from the current target profile."
}
foreach ($requiredGroup in $requiredGroups) {
  $group = @($summary.groups | Where-Object { $_.name -eq $requiredGroup })
  if ($group.Count -ne 1 -or $group[0].status -ne "passed" -or -not [bool]$group[0].required) {
    throw "Structured summary does not prove required group $requiredGroup."
  }
}

Write-Host "[ok] MIR release candidate evidence matches source, package, validation, upgrade, ecosystem, and interactive-review state."
