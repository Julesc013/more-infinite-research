param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }

& (Join-Path $RepoRoot "scripts\Invoke-MIRAssurance.ps1") self-test
if ($LASTEXITCODE -ne 0) { throw "MIR assurance self-test failed." }

$config = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\assurance.json") | ConvertFrom-Json
$catalog = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\tests.yml") | ConvertFrom-Json
$domains = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\domains.yml") | ConvertFrom-Json
if ([int]$config.schema -ne 1 -or [int]$catalog.schema -ne 2 -or [int]$domains.schema -ne 1) { throw "Unsupported assurance manifest schema." }

$ids = @($catalog.tests | ForEach-Object { [string]$_.id })
$duplicates = @($ids | Group-Object | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw "Duplicate assurance test IDs: $($duplicates.Name -join ', ')" }

foreach ($required in @("static.full", "runtime.full", "runtime.upgrade", "runtime.exact-zip", "seal.verify")) {
  if ($ids -notcontains $required) { throw "Missing release-blocking assurance test ID: $required" }
}

foreach ($target in @("2.0", "2.1")) {
  $profilePath = Join-Path $RepoRoot "validation\profiles\factorio-$target.json"
  $profile = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json
  if ([int]$profile.schema -ne 1 -or [string]$profile.target -ne $target -or [string]$profile.policy_id -ne [string]$domains.policy_id) {
    throw "Verification profile is not bound to the canonical domain policy: $profilePath"
  }
}

$releaseAssurance = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\MIRAssurance\Release.ps1")
foreach ($requiredSealField in @("mir_version", "target", "canonical_dev_anchor")) {
  if ($releaseAssurance -notmatch ("(?m)^\s+" + [regex]::Escape($requiredSealField) + "=")) {
    throw "Candidate seal schema omits the backport source-lock field: $requiredSealField"
  }
}

Write-Host "[ok] MIR assurance manifests, domain policy, target profiles, and stable test catalog passed."
