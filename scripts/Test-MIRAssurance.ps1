param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }

& (Join-Path $RepoRoot "scripts\Invoke-MIRAssurance.ps1") self-test
if ($LASTEXITCODE -ne 0) { throw "MIR assurance self-test failed." }

$config = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\assurance.json") | ConvertFrom-Json
$catalog = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\test-catalog.json") | ConvertFrom-Json
if ([int]$config.schema -ne 1 -or [int]$catalog.schema -ne 1) { throw "Unsupported assurance manifest schema." }

$ids = @($catalog.tests | ForEach-Object { [string]$_.id })
$duplicates = @($ids | Group-Object | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw "Duplicate assurance test IDs: $($duplicates.Name -join ', ')" }

foreach ($required in @("static.full", "runtime.full", "runtime.upgrade", "runtime.exact-zip", "seal.verify")) {
  if ($ids -notcontains $required) { throw "Missing release-blocking assurance test ID: $required" }
}

$governanceClass = @($config.classes | Where-Object { [string]$_.id -eq "release-governance" })
if ($governanceClass.Count -ne 1) { throw "Assurance config must declare one release-governance class." }
foreach ($path in @(
  ".mir/backport-source-lock.json", ".mir/branches.yml", ".mir/convergence.yml",
  ".mir/docs.yml", ".mir/fixtures.yml", ".mir/release-wave.yml",
  ".mir/evidence/lower-wave/1.7.5-feature-classification.json"
)) {
  if (-not @($governanceClass[0].patterns | Where-Object { $path -match [string]$_ })) {
    throw "Known release-governance path is unclassified: $path"
  }
}
$docsClass = @($config.classes | Where-Object { [string]$_.id -eq "repository-docs" })
if ($docsClass.Count -ne 1 -or @($docsClass[0].tests) -contains "seal.verify") {
  throw "Repository docs must not select the promotion-only seal check before a seal exists."
}
$evidenceClass = @($config.classes | Where-Object { [string]$_.id -eq "release-evidence" })
if ($evidenceClass.Count -ne 1 -or @($evidenceClass[0].tests) -notcontains "seal.verify") {
  throw "Release evidence must retain the seal verification gate."
}
if (@($evidenceClass[0].patterns | Where-Object { ".mir/evidence/lower-wave/1.7.5-feature-classification.json" -match [string]$_ })) {
  throw "Pre-seal feature classification must not select seal verification."
}
if (-not @($evidenceClass[0].patterns | Where-Object { ".mir/evidence/candidate-seals/example.json" -match [string]$_ })) {
  throw "Candidate-seal evidence must select seal verification."
}

$releaseAssurance = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\MIRAssurance\Release.ps1")
foreach ($requiredSealField in @("mir_version", "target", "canonical_dev_anchor")) {
  if ($releaseAssurance -notmatch ("(?m)^\s+" + [regex]::Escape($requiredSealField) + "=")) {
    throw "Candidate seal schema omits the backport source-lock field: $requiredSealField"
  }
}

Write-Host "[ok] MIR assurance manifests and stable test catalog passed."
