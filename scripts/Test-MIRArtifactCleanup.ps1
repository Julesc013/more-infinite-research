param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$fixtureRoot = Join-Path $tempRoot ("mir-artifact-cleanup-{0}" -f [guid]::NewGuid().ToString("N"))
$cleanupScript = Join-Path $RepoRoot "scripts\Remove-MIRStaleArtifacts.ps1"

try {
  New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
  & git -C $fixtureRoot init --quiet
  if ($LASTEXITCODE -ne 0) { throw "Unable to initialize artifact-cleanup fixture repository." }
  "/artifacts/" | Set-Content -LiteralPath (Join-Path $fixtureRoot ".gitignore") -Encoding UTF8

  $artifactRoot = Join-Path $fixtureRoot "artifacts"
  $protectedAssurance = Join-Path $artifactRoot "assurance"
  $protectedValidation = Join-Path $artifactRoot "validation"
  $staleRun = Join-Path $artifactRoot "stale-run"
  $recentRun = Join-Path $artifactRoot "recent-run"
  foreach ($path in @($protectedAssurance, $protectedValidation, $staleRun, $recentRun)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    "fixture" | Set-Content -LiteralPath (Join-Path $path "result.txt") -Encoding UTF8
  }

  $staleTimestamp = [DateTime]::UtcNow.AddDays(-10)
  Get-ChildItem -LiteralPath $staleRun -Force -Recurse | ForEach-Object { $_.LastWriteTimeUtc = $staleTimestamp }
  (Get-Item -LiteralPath $staleRun).LastWriteTimeUtc = $staleTimestamp
  foreach ($protectedPath in @($protectedAssurance, $protectedValidation)) {
    Get-ChildItem -LiteralPath $protectedPath -Force -Recurse | ForEach-Object { $_.LastWriteTimeUtc = $staleTimestamp }
    (Get-Item -LiteralPath $protectedPath).LastWriteTimeUtc = $staleTimestamp
  }

  $preview = @(& $cleanupScript -RepoRoot $fixtureRoot -OlderThanDays 7 -PassThru)
  if (-not (Test-Path -LiteralPath $staleRun)) { throw "Dry-run cleanup removed a stale artifact." }
  if (@($preview | Where-Object { $_.item -eq "stale-run" -and $_.status -eq "eligible" }).Count -ne 1) {
    throw "Dry-run cleanup did not identify the stale artifact exactly once."
  }
  foreach ($protectedName in @("assurance", "validation")) {
    if (@($preview | Where-Object { $_.item -eq $protectedName -and $_.status -eq "protected" }).Count -ne 1) {
      throw "Cleanup did not protect artifacts/$protectedName."
    }
  }

  $applied = @(& $cleanupScript -RepoRoot $fixtureRoot -OlderThanDays 7 -Apply -PassThru -SkipActiveProcessCheck -Confirm:$false)
  if (Test-Path -LiteralPath $staleRun) { throw "Applied cleanup retained the stale artifact." }
  if (-not (Test-Path -LiteralPath $recentRun)) { throw "Applied cleanup removed a recent artifact." }
  if (-not (Test-Path -LiteralPath $protectedAssurance) -or -not (Test-Path -LiteralPath $protectedValidation)) {
    throw "Applied cleanup removed a protected artifact root."
  }
  if (@($applied | Where-Object { $_.item -eq "stale-run" -and $_.status -eq "deleted" }).Count -ne 1) {
    throw "Applied cleanup did not report the stale artifact as deleted."
  }
} finally {
  if (Test-Path -LiteralPath $fixtureRoot) {
    $resolvedFixture = [System.IO.Path]::GetFullPath($fixtureRoot)
    $tempPrefix = $tempRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedFixture.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Artifact-cleanup fixture escaped the system temp directory: $resolvedFixture"
    }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
  }
}

Write-Host "[ok] artifact cleanup is dry-run-first, age-aware, Git-ignored-only, and protects assurance and validation roots."
