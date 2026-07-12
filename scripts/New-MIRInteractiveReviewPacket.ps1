param(
  [string]$CandidateZip = "build\validation-dist\more-infinite-research_3.1.0.zip",
  [string]$SourceCommit = "",
  [string]$OutputDir = "artifacts\interactive-review-current"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")

$info = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json
$candidatePath = if ([System.IO.Path]::IsPathRooted($CandidateZip)) {
  (Resolve-Path -LiteralPath $CandidateZip).Path
} else {
  (Resolve-Path -LiteralPath (Join-Path $repo $CandidateZip)).Path
}
if ([string]::IsNullOrWhiteSpace($SourceCommit)) {
  $SourceCommit = ([string](& git -C $repo rev-parse HEAD)).Trim()
}
if ($SourceCommit -notmatch '^[0-9a-f]{40}$') {
  throw "SourceCommit must be a full lowercase Git commit ID."
}
& git -C $repo cat-file -e "$SourceCommit^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) { throw "Source commit is not available locally: $SourceCommit" }

$changedPackagePaths = @(& git -C $repo diff --name-only $SourceCommit HEAD -- @(Get-MIRPackageSourceRoots))
if ($LASTEXITCODE -ne 0 -or $changedPackagePaths.Count -gt 0) {
  throw "Package-visible source differs from the requested source commit: $($changedPackagePaths -join ', ')"
}
if (Test-MIRPackageSourceGitDirty -RepoRoot $repo) {
  throw "Package-visible working-tree changes must be committed before creating an interactive review packet."
}

$outputRoot = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $repo $OutputDir }
$modsDir = Join-Path $outputRoot "mods"
New-Item -ItemType Directory -Force -Path $modsDir | Out-Null
$copiedArchive = Join-Path $modsDir (Split-Path -Leaf $candidatePath)
Copy-Item -LiteralPath $candidatePath -Destination $copiedArchive -Force

$relativeEvidenceRoot = [System.IO.Path]::GetRelativePath($repo, $outputRoot).Replace("\", "/")
$packet = [ordered]@{
  schema = 1
  kind = "mir-interactive-review"
  status = "pending"
  version = [string]$info.version
  factorio_version = [string]$info.factorio_version
  source_commit = $SourceCommit
  archive_path = [System.IO.Path]::GetRelativePath($repo, $candidatePath).Replace("\", "/")
  archive_sha256 = Get-MIRFileSha256 -Path $candidatePath
  package_content_sha256 = Get-MIRZipContentFingerprint -Path $candidatePath
  package_source_sha256 = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  required_checks = @(
    "isolated-normal-mod-directory-load",
    "base-and-space-age-save-load",
    "startup-settings-and-automatic-compiler-modes",
    "locale-and-help-text",
    "technology-visibility-icons-costs-and-effects",
    "science-and-prerequisite-reachability",
    "default-safe-attach-boundary",
    "opt-in-safe-generate-assembler-and-lab-boundary",
    "balance-review"
  )
  reviewer = $null
  reviewed_at = $null
  captures = @()
  notes = @(
    "This pending packet is identity-bound preparation, not evidence that GUI review passed.",
    "Record at least settings, technology-tree, and loaded-save captures before acceptance."
  )
}
$packetPath = Join-Path $outputRoot "interactive-review.json"
$packet | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $packetPath -Encoding utf8

$checklist = @(
  "# MIR $($info.version) Interactive Review",
  "",
  "Candidate source: ``$SourceCommit``",
  "Candidate archive SHA-256: ``$($packet.archive_sha256)``",
  "",
  "Use the isolated ``$relativeEvidenceRoot/mods`` directory. Complete every required check in ``interactive-review.json``, capture the settings page, technology tree, and loaded save, then record reviewer identity, review time, capture paths/hashes, notes, and ``status: passed``. Do not reuse screenshots from an earlier candidate."
)
$checklist | Set-Content -LiteralPath (Join-Path $outputRoot "README.md") -Encoding utf8

Write-Host "[ok] prepared identity-bound interactive review packet $packetPath"
