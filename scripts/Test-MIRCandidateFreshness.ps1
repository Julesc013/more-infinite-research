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

$manifestPath = Join-Path $repo ".mir\convergence.yml"
$manifestText = Get-Content -Raw -LiteralPath $manifestPath
$candidate = Get-MIRCandidateFields -Text $manifestText
$status = Get-MIRRequiredCandidateField -Fields $candidate -Name "status"
$allowedStatuses = @(
  "rebuilding-after-package-visible-change",
  "release-candidate-awaiting-manual-review",
  "accepted-for-promotion",
  "published"
)
if ($status -notin $allowedStatuses) {
  throw "Unsupported MIR candidate status: $status"
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

if (Test-MIRPackageSourceGitDirty -RepoRoot $repo) {
  throw "Package-visible working-tree changes make the active release candidate stale."
}
if (Test-MIRRepositoryGitDirty -RepoRoot $repo) {
  throw "The entire repository working tree must be clean before candidate promotion."
}
$packageRoots = @(Get-MIRPackageSourceRoots)
$changedPackagePaths = @(& git -C $repo diff --name-only $sourceCommit HEAD -- @packageRoots)
if ($LASTEXITCODE -ne 0) {
  throw "Unable to compare active candidate source against HEAD."
}
if ($changedPackagePaths.Count -gt 0) {
  throw "Package-visible paths changed after the active candidate source commit: $($changedPackagePaths -join ', ')"
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

Write-Host "[ok] MIR release candidate evidence matches source, profile, package, and structured validation summary."
