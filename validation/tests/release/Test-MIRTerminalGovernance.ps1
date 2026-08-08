param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path }

$family = @("3.2.9", "2.5.9", "1.9.9", "1.8.9", "1.7.9", "1.6.9", "1.5.9", "1.4.9", "1.3.9")
$authorityNames = @(
  "MIR3-Terminal-ProgrammeV1",
  "MIR3-Terminal-ScopeFirewallV1",
  "MIR3-Terminal-Target-MatrixV1",
  "MIR3-Terminal-Candidate-AllocationV1",
  "MIR3-Terminal-FixedPointPolicyV1",
  "MIR3-Terminal-PublicationPolicyV1",
  "MIR3-Terminal-EOL-PolicyV1"
)
$authorities = @{}
foreach ($name in $authorityNames) {
  $path = Join-Path $RepoRoot ".mir\releases\terminal\$name.json"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Terminal authority is missing: $name" }
  $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ([int]$record.schema -ne 1 -or [string]$record.kind -ne $name) { throw "Terminal authority identity is invalid: $name" }
  $authorities[$name] = $record
}
$changeSet = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\waves\MIR3-Terminal-ChangeSet.json") | ConvertFrom-Json -Depth 100
if ([string]$changeSet.kind -ne "MIR3-Terminal-ChangeSetV1") { throw "Terminal change-set authority is invalid." }

$programme = $authorities["MIR3-Terminal-ProgrammeV1"]
if (@(Compare-Object $family @($programme.family)).Count -ne 0 -or $programme.implementation_admitted -or $programme.source_frozen) {
  throw "Terminal programme must bind the exact unimplemented, unfrozen nine-release family."
}
$requiredOrder = @("baseline-capture", "bounded-change-admission", "implementation", "all-nine-shadow-materialization", "all-nine-fixed-point-sweeps", "source-freeze", "candidate-assignment", "all-nine-final-qualification-and-seals", "family-readiness-seal", "local-signed-annotated-tags", "controlled-publication")
if (($programme.execution_order -join "|") -ne ($requiredOrder -join "|")) { throw "Terminal execution order is not canonical." }

$baselineQueue = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\terminal\MIR3-Terminal-Baseline-Capture-QueueV1.json") | ConvertFrom-Json -Depth 100
if ([string]$baselineQueue.kind -ne "MIR3-Terminal-Baseline-Capture-QueueV1" -or @($baselineQueue.rows).Count -ne 9 -or
    (@($baselineQueue.rows.terminal_release) -join "|") -ne ($family -join "|") -or @($baselineQueue.required_semantic_inventory).Count -lt 15 -or
    @($baselineQueue.rows | Where-Object { $_.identity_status -ne "locked" -or $_.semantic_inventory_status -ne "pending-capture" }).Count -ne 0) {
  throw "Terminal baseline queue must lock nine identities and truthfully retain semantic capture work."
}
$incidentReconciliation = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\terminal\MIR3-Terminal-Incident-ReconciliationV1.json") | ConvertFrom-Json -Depth 100
if ([string]$incidentReconciliation.kind -ne "MIR3-Terminal-Incident-ReconciliationV1" -or $incidentReconciliation.rules.history_mutation_permitted -or
    $incidentReconciliation.rules.dot5_package_mutation_permitted -or @($incidentReconciliation.items | Where-Object terminal_state -eq "retained-assurance-debt").Count -lt 2) {
  throw "Terminal incident reconciliation must preserve history, .5 bytes, and assurance debt."
}

$allocation = $authorities["MIR3-Terminal-Candidate-AllocationV1"]
if (@($allocation.allocations).Count -ne 9 -or @($allocation.allocations | Where-Object { $null -ne $_.assigned_id }).Count -ne 0) {
  throw "Every terminal candidate allocation must remain unassigned."
}
foreach ($release in $family) {
  $row = @($allocation.allocations | Where-Object release -eq $release)
  $record = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\records\$release.json") | ConvertFrom-Json
  if ($row.Count -ne 1 -or [string]$record.state -ne "planned" -or [string]$record.candidate_id -ne "not-assigned" -or $null -ne $record.candidate_allocation.assigned_id -or
      [string]$record.candidate_allocation.namespace -ne [string]$row[0].namespace -or [int]$record.candidate_allocation.minimum_next_ordinal -ne [int]$row[0].minimum_next_ordinal) {
    throw "Terminal release/candidate authority disagrees for $release."
  }
}

$matrix = $authorities["MIR3-Terminal-Target-MatrixV1"]
if (@($matrix.targets).Count -ne 9 -or (@($matrix.targets.release) -join "|") -ne ($family -join "|")) { throw "Terminal target matrix is not exact or ordered." }
foreach ($row in @($matrix.targets)) {
  foreach ($field in @("release", "target", "support_tier", "immutable_dot5_predecessor", "pre_dot5_public_predecessor", "engine_lock_rule", "upgrade_rows", "proof_depth", "mir4_successor_target")) {
    if ($null -eq $row.PSObject.Properties[$field]) { throw "Target $($row.release) omits $field." }
  }
  if (@($row.upgrade_rows).Count -lt 2) { throw "Target $($row.release) must bind direct .5 and pre-.5 upgrade rows." }
}

$changeFields = @("source_observation", "reproduction", "severity", "visibility", "stable_id_and_migration_impact", "affected_targets", "target_dispositions", "admission_destination", "regression_obligations", "fixed_point_restart_scope", "closure")
foreach ($item in @($changeSet.items)) {
  foreach ($field in $changeFields) { if ($null -eq $item.PSObject.Properties[$field]) { throw "Terminal change $($item.id) omits $field." } }
  if (@($item.target_dispositions).Count -eq 0) { throw "Terminal change $($item.id) has no target disposition." }
}
if ($changeSet.implementation_admitted) { throw "A topic inventory must not admit terminal product implementation." }

$firewall = $authorities["MIR3-Terminal-ScopeFirewallV1"]
if ($firewall.rules.package_visible_change_without_change_id -or $firewall.rules.source_freeze_without_fixed_point_receipt -or $firewall.rules.public_tag_without_family_readiness_seal -or
    @($firewall.forbidden | Where-Object { $_ -in @("release-.6", "release-.7", "release-.8", "release-.10") }).Count -ne 4) {
  throw "Terminal scope firewall does not enforce release and admission hard stops."
}
$fixedPoint = $authorities["MIR3-Terminal-FixedPointPolicyV1"]
if (($fixedPoint.participants -join "|") -ne ($family -join "|") -or @($fixedPoint.convergence).Count -ne 5 -or -not $fixedPoint.source_freeze_requires_accepted_receipt) {
  throw "Terminal fixed-point authority is incomplete."
}
$publication = $authorities["MIR3-Terminal-PublicationPolicyV1"]
if (@($publication.first_public_tag_requires).Count -lt 4 -or $publication.failure_policy.rollback_by_deletion -or -not $publication.failure_policy.same_byte_resume) {
  throw "Terminal family publication policy is incomplete."
}

$schemaNames = @("mir3-terminal-package-manifest", "mir3-terminal-release-manifest", "mir3-terminal-publication-receipt", "mir3-terminal-baseline-bundle-manifest", "mir3-terminal-qualification-record", "mir3-terminal-target-seal", "mir3-terminal-fixed-point-receipt", "mir3-terminal-family-readiness", "mir3-eol-record", "mir3-terminal-authority", "mir3-museum-index", "mir3-terminal-018-feasibility-gate")
foreach ($name in $schemaNames) {
  $path = Join-Path $RepoRoot "spec\schemas\$name.schema.json"
  $schema = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ([string]$schema.'x-mir-canonical-path' -ne "spec/schemas/$name.schema.json") { throw "Terminal schema canonical path is invalid: $name" }
}
$packageSchemaText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "spec\schemas\mir3-terminal-package-manifest.schema.json")
$releaseSchemaText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "spec\schemas\mir3-terminal-release-manifest.schema.json")
if ($packageSchemaText -notmatch 'archive_sha256' -or $releaseSchemaText -notmatch 'publication_receipts') { throw "Terminal package/release self-reference firewall is absent." }

$gate = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\terminal\MIR3-Terminal-018-FeasibilityGateV1.json") | ConvertFrom-Json
$museum = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\terminal\MIR-3-MUSEUM-INDEX.json") | ConvertFrom-Json
if ($gate.default_1_8_9_target -ne "Factorio 1.0.0 only" -or $gate.blocks_terminal_family -or $gate.may_create_0_18_dot9_package -or
    $museum.artificial_dot9_versions_permitted -or @($museum.targets).Count -ne 7) { throw "0.18 or museum custody policy is invalid." }

$current = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\records\current.json") | ConvertFrom-Json
if (($current.planned_releases -join "|") -ne ($family -join "|") -or $current.implementation_admitted -or $current.source_frozen -or
    $current.roles.latest_published_factorio_2_1 -ne "3.2.5" -or $current.roles.latest_published_factorio_2_0 -ne "2.5.5" -or
    $current.active_programme.id -ne "MIR3-Terminal-ProgrammeV1" -or $current.active_programme.status -ne "active-planning-only") {
  throw "Current release roles do not distinguish published .5 from planned .9."
}

$wave = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\releases\archive\MIR-3.5-WAVE-INDEX.json") | ConvertFrom-Json
foreach ($release in @($wave.releases)) {
  $zip = Join-Path $RepoRoot ([string]$release.dist)
  if ((Get-Item -LiteralPath $zip).Length -ne [long]$release.bytes -or (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne [string]$release.archive_sha256) {
    throw "Immutable .5 distribution changed: $($release.version)"
  }
}

Write-Host "[ok] all-nine terminal governance, schemas, allocation, fixed point, custody, and immutable .5 identities passed."
