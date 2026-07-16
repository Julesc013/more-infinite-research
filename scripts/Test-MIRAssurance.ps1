param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }

& (Join-Path $RepoRoot "scripts\Invoke-MIRAssurance.ps1") self-test
if ($LASTEXITCODE -ne 0) { throw "MIR assurance self-test failed." }
& (Join-Path $RepoRoot "scripts\Test-MIRVerificationSchemas.ps1") -RepoRoot $RepoRoot
if ($LASTEXITCODE -ne 0) { throw "MIR verification schema validation failed." }

$config = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\assurance.json") | ConvertFrom-Json
$catalog = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\tests.yml") | ConvertFrom-Json
$domains = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\domains.yml") | ConvertFrom-Json
$trust = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\trust.json") | ConvertFrom-Json
if ([int]$config.schema -ne 1 -or [int]$catalog.schema -ne 2 -or [int]$domains.schema -ne 1 -or [int]$trust.schema -ne 1) {
  throw "Unsupported assurance manifest schema."
}

$ids = @($catalog.tests | ForEach-Object { [string]$_.id })
$duplicates = @($ids | Group-Object | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw "Duplicate assurance test IDs: $($duplicates.Name -join ', ')" }

foreach ($required in @("tooling.self-test", "static.full", "performance.static", "runtime.full", "runtime.upgrade", "runtime.exact-zip", "runtime.ecosystem", "seal.verify")) {
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
foreach ($requiredSealField in @(
  "mir_version",
  "target",
  "canonical_dev_anchor",
  "candidate_descriptor_sha256",
  "plan_material_sha256",
  "required_test_set_sha256",
  "evidence_bundle_sha256",
  "capsule_set_sha256",
  "verifier_release_sha256",
  "producer_attestation"
)) {
  if ($releaseAssurance -notmatch ("(?m)^\s+" + [regex]::Escape($requiredSealField) + "=")) {
    throw "Candidate seal schema omits the backport source-lock field: $requiredSealField"
  }
}
if ($releaseAssurance -match 'Get-MIRAssuranceOption\s+-Name\s+"--evidence"') {
  throw "Candidate sealing still accepts an arbitrary evidence summary."
}

$workflow = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".github\workflows\assurance-full.yml")
foreach ($requiredWorkflowSnippet in @(
  "MIR_TRUST_CLASS: protected-release",
  "f0:",
  "needs: [plan, f0]",
  "needs: [plan, f1]",
  "needs: [plan, f2]",
  "needs: [plan, f3]",
  "needs: [plan, f0, f1, f2, f3, f4]",
  "assurance seal"
)) {
  if (-not $workflow.Contains($requiredWorkflowSnippet)) {
    throw "Full assurance workflow does not enforce the required protected F0-F4 chain: $requiredWorkflowSnippet"
  }
}

Write-Host "[ok] MIR assurance manifests, domain policy, target profiles, and stable test catalog passed."
