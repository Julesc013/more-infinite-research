param(
  [ValidateSet("qualify", "seal", "check-seal")][string]$Action = "qualify",
  [string]$FactorioBin,
  [string]$CandidateZip,
  [string]$PriorZip,
  [switch]$StaticOnly,
  [switch]$RuntimeOnly,
  [switch]$UseExistingCandidate
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$profilePath = Join-Path $repo ".mir\target-reconstruction.json"
$profile = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json
$canonicalProfilePath = Join-Path $repo ".mir\targets.json"
$sourceLockPath = Join-Path $repo ".mir\backport-source-lock.json"
$canonicalFeatureModelPath = Join-Path $repo ".mir\canonical-lower-features.json"
$testCatalogPath = Join-Path $repo "validation\tests.yml"
$info = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($CandidateZip)) {
  $CandidateZip = Join-Path $repo "dist\$($info.name)_$($info.version).zip"
}
$summaryPath = Join-Path $repo ".mir\evidence\$($info.version)-qualification-summary.json"
$sealPath = Join-Path $repo ".mir\evidence\$($info.version)-candidate-seal.json"

function Get-MIRSha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-MIRStringSha256([string]$Value) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Value)
    return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "")
  } finally { $sha.Dispose() }
}

function Test-MIRTextPath([string]$RelativePath) {
  $extension = [IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
  return $extension -in @(".cfg", ".json", ".lua", ".md", ".txt") -or [IO.Path]::GetFileName($RelativePath) -eq "LICENSE"
}

function Get-MIRPackageFiles {
  $roots = @("changelog.txt", "control.lua", "data-final-fixes.lua", "data-updates.lua", "data.lua", "info.json", "LICENSE", "README.md", "settings.lua", "thumbnail.png", "locale", "migrations", "prototypes")
  $files = foreach ($relative in $roots) {
    $path = Join-Path $repo $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) { $relative.Replace("\", "/") }
    elseif (Test-Path -LiteralPath $path -PathType Container) {
      Get-ChildItem -LiteralPath $path -Recurse -File | ForEach-Object { [IO.Path]::GetRelativePath($repo, $_.FullName).Replace("\", "/") }
    }
  }
  return @($files | Sort-Object -Unique)
}

function Get-MIRPackageSourceFingerprint {
  $rows = foreach ($relative in Get-MIRPackageFiles) {
    $path = Join-Path $repo $relative
    if (Test-MIRTextPath $relative) {
      $text = [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
      $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
      $sha = [Security.Cryptography.SHA256]::Create()
      try { $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "") } finally { $sha.Dispose() }
      "$relative`t$($bytes.Length)`t$hash"
    } else {
      $item = Get-Item -LiteralPath $path
      "$relative`t$($item.Length)`t$(Get-MIRSha256 $path)"
    }
  }
  return Get-MIRStringSha256 ($rows -join "`n")
}

function Get-MIRZipContentFingerprint([string]$Path) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $rows = foreach ($entry in @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | Sort-Object FullName)) {
      $stream = $entry.Open()
      try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace("-", "") } finally { $sha.Dispose() }
      } finally { $stream.Dispose() }
      "$($entry.FullName)`t$($entry.Length)`t$hash"
    }
    return Get-MIRStringSha256 ($rows -join "`n")
  } finally { $zip.Dispose() }
}

function Get-MIRHarnessFingerprint {
  $rows = @(& git -C $repo ls-files -s -- scripts fixtures .mir | Where-Object { $_ -notmatch "\t\.mir/evidence/" } | Sort-Object)
  if ($LASTEXITCODE -ne 0) { throw "Cannot inventory the validation harness." }
  return Get-MIRStringSha256 ($rows -join "`n")
}

function Get-MIRRepositoryTextSha256([string]$Path) {
  $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
  return Get-MIRStringSha256 $text
}

function Get-MIRFixtureFingerprint {
  $rows = @(& git -C $repo ls-files -s -- fixtures | Sort-Object)
  if ($LASTEXITCODE -ne 0) { throw "Cannot inventory target fixtures." }
  return Get-MIRStringSha256 ($rows -join "`n")
}

function Assert-MIRSealableState {
  $status = @(& git -C $repo status --porcelain --untracked-files=all -- changelog.txt control.lua data-final-fixes.lua data-updates.lua data.lua info.json LICENSE README.md settings.lua thumbnail.png locale migrations prototypes scripts fixtures .mir |
    Where-Object { $_ -notmatch '[\\/]\.mir[\\/]evidence[\\/]' -and $_ -notmatch '\.mir/evidence/' })
  if ($status.Count) { throw "Package or validation harness is dirty; commit it before sealing: $($status -join '; ')" }
}

function Get-MIRSealValues {
  $candidate = (Resolve-Path -LiteralPath $CandidateZip).Path
  $binaryHash = $null
  if (-not [string]::IsNullOrWhiteSpace($FactorioBin)) {
    $binaryHash = Get-MIRSha256 (Resolve-Path -LiteralPath $FactorioBin).Path
    if ($binaryHash -ne $profile.factorio.binary_sha256) { throw "Factorio binary hash does not match target profile." }
  } else { $binaryHash = $profile.factorio.binary_sha256 }
  $sourceLock = Get-Content -Raw -LiteralPath $sourceLockPath | ConvertFrom-Json
  & git -C $repo merge-base --is-ancestor ([string]$sourceLock.canonical_dev_anchor) HEAD
  if ($LASTEXITCODE -ne 0) { throw "Canonical development anchor is not in target ancestry." }
  return [ordered]@{
    schema = 1
    kind = "mir-qualified-candidate-seal"
    branch = $profile.branch
    release = $profile.release
    mir_version = $profile.release
    target_factorio = $profile.factorio.line
    target = $profile.factorio.line
    source_commit = (& git -C $repo rev-parse HEAD).Trim()
    source_clean = $true
    canonical_dev_anchor = [string]$sourceLock.canonical_dev_anchor
    canonical_anchor_is_ancestor = $true
    backport_source_lock_sha256 = Get-MIRRepositoryTextSha256 $sourceLockPath
    canonical_feature_model_sha256 = Get-MIRRepositoryTextSha256 $canonicalFeatureModelPath
    candidate = [ordered]@{
      path = [IO.Path]::GetRelativePath($repo, $candidate).Replace("\", "/")
      sha256 = Get-MIRSha256 $candidate
      size_bytes = (Get-Item -LiteralPath $candidate).Length
      content_fingerprint = Get-MIRZipContentFingerprint $candidate
      package_source_fingerprint = Get-MIRPackageSourceFingerprint
    }
    target_profile_sha256 = [string]$sourceLock.target_profile_sha256
    target_reconstruction_profile_sha256 = Get-MIRRepositoryTextSha256 $profilePath
    canonical_target_catalog_sha256 = Get-MIRRepositoryTextSha256 $canonicalProfilePath
    test_catalog_sha256 = Get-MIRRepositoryTextSha256 $testCatalogPath
    fixtures_fingerprint = Get-MIRFixtureFingerprint
    validation_harness_fingerprint = Get-MIRHarnessFingerprint
    factorio_binary_sha256 = $binaryHash
    qualification_summary_sha256 = Get-MIRRepositoryTextSha256 $summaryPath
    release_actions = "not-run-maintainer-only"
  }
}

if ($Action -eq "qualify") {
  if (-not $RuntimeOnly) {
    if (-not $UseExistingCandidate) {
      & (Join-Path $PSScriptRoot "Build-MIRPackage.ps1") -OutputDir dist -CompressionLevel Optimal | Out-Host
    } elseif (-not (Test-Path -LiteralPath $CandidateZip -PathType Leaf)) {
      throw "UseExistingCandidate requires an existing exact candidate ZIP."
    }
    $CandidateZip = (Resolve-Path -LiteralPath $CandidateZip).Path
    & (Join-Path $PSScriptRoot "Test-MIRBackportCapabilities.ps1") | Out-Host
    & (Join-Path $PSScriptRoot "Test-MIRSettingsVisibility.ps1") | Out-Host
    & (Join-Path $PSScriptRoot "Test-MIRDeterministicPackage.ps1") -CandidateZip $CandidateZip | Out-Host
    & (Join-Path $PSScriptRoot "Invoke-MIRValidation.ps1") -StaticOnly -CandidateZip $CandidateZip | Out-Host
  } else {
    $CandidateZip = (Resolve-Path -LiteralPath $CandidateZip).Path
    $priorSummary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
    if ($priorSummary.status -ne "passed" -or $priorSummary.static_gate -ne "passed" -or
        $priorSummary.deterministic_rebuild -ne "passed" -or $priorSummary.candidate.sha256 -ne (Get-MIRSha256 $CandidateZip)) {
      throw "Runtime-only qualification requires the unchanged candidate to have passed the static and deterministic gates."
    }
  }

  $runtimeStatus = "not-run-static-only"
  $retentionStatus = "not-run-static-only"
  if (-not $StaticOnly) {
    if ([string]::IsNullOrWhiteSpace($FactorioBin)) { throw "-FactorioBin is required for release qualification." }
    if ((Get-MIRSha256 $FactorioBin) -ne $profile.factorio.binary_sha256) { throw "Factorio binary hash does not match target profile." }
    & (Join-Path $PSScriptRoot "Invoke-MIRValidation.ps1") -FactorioBin $FactorioBin -CandidateZip $CandidateZip | Out-Host
    $runtimeStatus = "passed"
    $retentionArgs = @{ FactorioBin=$FactorioBin; CandidateZip=$CandidateZip }
    if (-not [string]::IsNullOrWhiteSpace($PriorZip)) { $retentionArgs.PriorZip = $PriorZip }
    & (Join-Path $PSScriptRoot "Test-MIRCandidateRetention.ps1") @retentionArgs | Out-Host
    $retentionStatus = "passed"
  }

  $candidateHash = Get-MIRSha256 $CandidateZip
  $summary = [ordered]@{
    schema = 1
    status = "passed"
    branch = $profile.branch
    release = $profile.release
    target_factorio = $profile.factorio.line
    candidate = [ordered]@{ path=[IO.Path]::GetRelativePath($repo,$CandidateZip).Replace("\","/"); sha256=$candidateHash; size_bytes=(Get-Item $CandidateZip).Length }
    factorio = [ordered]@{ version=$profile.factorio.qualified_version; binary_sha256=$profile.factorio.binary_sha256 }
    capability_classification = "passed"
    deterministic_rebuild = "passed"
    static_gate = "passed"
    exact_candidate_runtime = $runtimeStatus
    fresh_create_reload_and_prior_retention = $retentionStatus
    runtime_scenario_baseline = $profile.factorio.baseline_runtime_scenarios
    ecosystem = "fixture-and-named-scenario evidence only; no broader public claim added"
    public_release = $false
    tag = "not-run"
  }
  $parent = Split-Path -Parent $summaryPath
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  [IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 10) + "`n", [Text.UTF8Encoding]::new($false))
  Write-Host "[ok] qualified exact candidate $candidateHash"
  exit 0
}

if ($Action -eq "seal") {
  Assert-MIRSealableState
  if (-not (Test-Path -LiteralPath $summaryPath)) { throw "Qualification summary is missing: $summaryPath" }
  $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
  if ($summary.status -ne "passed" -or $summary.exact_candidate_runtime -ne "passed" -or $summary.fresh_create_reload_and_prior_retention -ne "passed") {
    throw "Candidate is not fully runtime-qualified."
  }
  $seal = Get-MIRSealValues
  [IO.File]::WriteAllText($sealPath, ($seal | ConvertTo-Json -Depth 10) + "`n", [Text.UTF8Encoding]::new($false))
  Write-Host "[ok] sealed $($seal.candidate.sha256) at $sealPath"
  exit 0
}

$stored = Get-Content -Raw -LiteralPath $sealPath | ConvertFrom-Json
$current = Get-MIRSealValues
foreach ($field in @("branch", "release", "mir_version", "target_factorio", "target", "source_clean", "canonical_dev_anchor", "canonical_anchor_is_ancestor", "backport_source_lock_sha256", "canonical_feature_model_sha256", "target_profile_sha256", "target_reconstruction_profile_sha256", "canonical_target_catalog_sha256", "test_catalog_sha256", "fixtures_fingerprint", "validation_harness_fingerprint", "factorio_binary_sha256", "qualification_summary_sha256")) {
  if ([string]$stored.$field -ne [string]$current.$field) { throw "Seal mismatch: $field" }
}
foreach ($field in @("path", "sha256", "size_bytes", "content_fingerprint", "package_source_fingerprint")) {
  if ([string]$stored.candidate.$field -ne [string]$current.candidate.$field) { throw "Seal mismatch: candidate.$field" }
}
& git -C $repo merge-base --is-ancestor $stored.source_commit HEAD
if ($LASTEXITCODE -ne 0) { throw "Sealed source commit is not an ancestor of HEAD." }
Write-Host "[ok] candidate seal verified: $($stored.candidate.sha256)"
