param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$schemaRoot = Join-Path $RepoRoot "verification\schema"
$contracts = [ordered]@{
  "test.schema.json" = @("id", "kind", "layer", "requires_factorio")
  "plan.schema.json" = @("schema", "policy_id", "target", "profile", "expected_test_ids", "plan_material_sha256", "tests")
  "result.schema.json" = @("schema", "test_id", "status", "exit_code", "assertions", "artifacts")
  "capsule.schema.json" = @("schema", "test_id", "status", "fingerprint_sha256", "producer", "result", "result_digest")
  "bundle.schema.json" = @("schema", "policy_id", "status", "plan_material_sha256", "capsule_set_sha256", "bundle_sha256")
  "seal.schema.json" = @("schema", "state", "mir_version", "target", "candidate_id", "package_source_commit", "package_source_sha256", "package_source_material", "qualification_source_commit", "qualification_source_tree", "candidate_sha256", "plan_material_sha256", "capsule_set_sha256", "seal_sha256")
  "runtime-performance-evidence.schema.json" = @("schema", "kind", "status", "candidate", "baseline", "factorio", "comparability", "run_policy", "run_order", "lanes", "artifact_volume")
  "manual-release-attestation.schema.json" = @("schema", "kind", "candidate_sha256", "candidate_content_sha256", "source_commit", "checklist_version", "items", "status", "attestation_sha256")
  "playtest-report.schema.json" = @("schema", "kind", "created_at", "candidate", "factorio", "environment", "observation", "compiler", "attachments")
  "upgrade-matrix.schema.json" = @("schema", "kind", "status", "source_commit", "factorio", "baseline", "candidate", "required_archetypes", "rows")
}

foreach ($entry in $contracts.GetEnumerator()) {
  $path = Join-Path $schemaRoot $entry.Key
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Verification schema is missing: $($entry.Key)"
  }
  $schema = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if ([string]$schema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema") {
    throw "Verification schema does not use JSON Schema 2020-12: $($entry.Key)"
  }
  if ([string]::IsNullOrWhiteSpace([string]$schema.'$id') -or [string]$schema.type -ne "object") {
    throw "Verification schema lacks an object identity: $($entry.Key)"
  }
  $required = @($schema.required | ForEach-Object { [string]$_ })
  $propertyNames = @($schema.properties.PSObject.Properties.Name)
  foreach ($field in $entry.Value) {
    if ($required -notcontains $field -or $propertyNames -notcontains $field) {
      throw "Verification schema $($entry.Key) does not require and define '$field'."
    }
  }
  if ($schema.additionalProperties -ne $false) {
    throw "Verification schema permits unknown top-level properties: $($entry.Key)"
  }
}

$assuranceEntry = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\Invoke-MIRAssurance.ps1")
if ($assuranceEntry -notmatch '\$evidenceSchema\s*=\s*4') {
  throw "Assurance evidence schema differs from capsule.schema.json."
}
$core = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\MIRAssurance\Core.ps1")
if ($core -notmatch 'schema=4') {
  throw "Assurance plan schema differs from plan.schema.json."
}
$evidence = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\MIRAssurance\Evidence.ps1")
if ($evidence -notmatch 'schema="mir-test-result-v1"' -or $evidence -notmatch 'schema=2') {
  throw "Assurance result or bundle schema differs from the governed JSON schemas."
}
$release = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\MIRAssurance\Release.ps1")
if ($release -notmatch 'schema=4') {
  throw "Assurance seal schema differs from seal.schema.json."
}

Write-Host "[ok] strict verification JSON schemas and implementation schema constants agree."
