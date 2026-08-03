param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$schemaRoot = Join-Path $RepoRoot "spec\schemas"
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
  "change-record.schema.json" = @("schema", "id", "title", "kind", "package_visible", "domains_read", "domains_written", "affected_targets", "test_obligations", "state")
  "candidate-closure.schema.json" = @("schema", "id", "release", "candidate_id", "disposition", "reason", "successor", "package", "remaining_obligations_disposition", "evidence_policy", "closed_at")
  "incident-record.schema.json" = @("schema", "id", "title", "state", "failing_environment", "root_cause", "regression_propositions", "candidate_binding", "closure")
  "release-record.schema.json" = @("schema", "release", "candidate_id", "target", "branch", "state", "package", "proofs", "updated_at")
  "release-transition.schema.json" = @("schema", "id", "release", "from", "to", "admission", "proofs", "recorded_at")
  "task-node.schema.json" = @("schema", "id", "owner", "kind", "layer", "depends_on", "reads", "writes", "effective_inputs", "outputs", "resource_class", "freshness", "side_effect", "retry", "completion_proof", "state")
  "observation.schema.json" = @("schema", "kind", "observation_abi", "canonicalization_abi", "capture_key", "environment_signature", "target", "candidate_sha256", "facts", "diagnostics", "artifacts")
  "assertion.schema.json" = @("schema", "id", "version", "type", "reads", "proposition", "expected")
  "evaluation.schema.json" = @("schema", "evaluation_abi", "evaluation_key", "observation_sha256", "assertion", "status", "actual", "expected", "proposition", "evidence_digest")
  "execution-registry.schema.json" = @("schema", "authority", "target", "observation_abi", "source", "metrics", "scenarios", "batches")
  "verification-context.schema.json" = @("schema", "authority", "context_abi", "context_id", "mode", "target", "release", "candidate_id", "plan_id", "members")
  "evidence-object.schema.json" = @("schema", "kind", "object_abi", "context_digest", "identity_key", "subject", "producer", "payload", "links")
  "evidence-manifest.schema.json" = @("schema", "authority", "context_digest", "plan_id", "producer", "objects", "task_results", "status")
  "evidence-revocation.schema.json" = @("schema", "authority", "default_disposition", "rules")
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
  if ([string]$schema.'x-mir-canonical-path' -ne "spec/schemas/$($entry.Key)") {
    throw "Verification schema lacks its canonical repository path: $($entry.Key)"
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
$core = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\Core.ps1")
if ($core -notmatch 'schema=4') {
  throw "Assurance plan schema differs from plan.schema.json."
}
$evidence = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\Evidence.ps1")
if ($evidence -notmatch 'schema="mir-test-result-v1"' -or $evidence -notmatch 'schema=2') {
  throw "Assurance result or bundle schema differs from the governed JSON schemas."
}
$release = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\Release.ps1")
if ($release -notmatch 'schema=4') {
  throw "Assurance seal schema differs from seal.schema.json."
}

Write-Host "[ok] strict verification JSON schemas and implementation schema constants agree."
