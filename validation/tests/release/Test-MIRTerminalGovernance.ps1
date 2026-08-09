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
  "MIR3-Terminal-EOL-PolicyV1",
  "MIR3TerminalFoundationAdmissionV1",
  "MIR3TerminalAcceleratedClosureDecisionV1"
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
foreach ($findingRecordPath in @($changeSet.finding_records)) {
  $finding = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ([string]$findingRecordPath)) | ConvertFrom-Json -Depth 100
  if ([string]$finding.kind -ne "MIR3TerminalFindingV1" -or [string]$finding.id -notmatch '^MIR3-TERM-[0-9]{4}$' -or
      [string]$finding.reproducer.status -ne "reproduced" -or @($finding.target_dispositions).Count -ne 9 -or
      (@($finding.target_dispositions.target) -join "|") -ne ($family -join "|") -or
      [string]$finding.admission.class -ne "NO_PACKAGE_CHANGE" -or [string]$finding.admission.status -ne "admitted" -or
      [bool]$finding.visibility.package -or [bool]$finding.visibility.gameplay -or -not [bool]$finding.visibility.assurance) {
    throw "Terminal finding is incomplete, not all-nine-disposed, or widens package authority: $findingRecordPath"
  }
}

$admission = $authorities["MIR3TerminalFoundationAdmissionV1"]
if ([string]$admission.status -ne "accepted" -or @($admission.stack).Count -ne 5 -or
    [string]$admission.foundation.commit -ne [string]$admission.stack[-1].merge_commit -or
    [string]$admission.dot5_identity_authority.verification -ne "archive-content-bytes-entries-passed-nine-of-nine" -or
    @($admission.dot5_identity_authority.releases).Count -ne 9 -or
    [bool]$admission.restack.history_rewritten -or [bool]$admission.restack.force_push_used -or
    -not [bool]$admission.restack.original_heads_retained_in_ancestry -or [bool]$admission.restack.cumulative_tree_changed -or
    [bool]$admission.package_boundary.published_zip_mutated -or [bool]$admission.package_boundary.candidate_assigned -or
    [bool]$admission.package_boundary.source_frozen_for_dot9) {
  throw "Terminal foundation admission receipt is incomplete or widens authority."
}
$foundationTree = (& git -C $RepoRoot rev-parse "$($admission.foundation.commit)^{tree}").Trim()
if ($LASTEXITCODE -ne 0 -or $foundationTree -ne [string]$admission.foundation.tree) { throw "Foundation commit/tree binding is invalid." }
$expectedFirstParent = [string]$admission.pre_foundation.commit
foreach ($row in @($admission.stack)) {
  & git -C $RepoRoot merge-base --is-ancestor ([string]$row.original_head) ([string]$row.corrected_head)
  if ($LASTEXITCODE -ne 0) { throw "Original PR head is not retained in corrected ancestry: #$($row.pr)" }
  $parts = @((& git -C $RepoRoot rev-list --parents -n 1 ([string]$row.merge_commit)).Trim() -split '\s+')
  if ($LASTEXITCODE -ne 0 -or $parts.Count -ne 3 -or $parts[1] -ne $expectedFirstParent -or $parts[2] -ne [string]$row.corrected_head -or
      [string]$row.checks -ne "passed" -or [long]$row.mir_run -le 0 -or [long]$row.branch_policy_run -le 0) {
    throw "Foundation merge/check binding is invalid: #$($row.pr)"
  }
  $expectedFirstParent = [string]$row.merge_commit
}
if ($expectedFirstParent -ne [string]$admission.foundation.commit) { throw "Foundation merge sequence does not terminate at the admitted commit." }
if ((Get-FileHash -LiteralPath (Join-Path $RepoRoot "docs\releases\archive\MIR-3.5-WAVE-INDEX.json") -Algorithm SHA256).Hash -ne [string]$admission.dot5_identity_authority.wave_index_sha256 -or
    (Get-FileHash -LiteralPath (Join-Path $RepoRoot ".mir\distributions.json") -Algorithm SHA256).Hash -ne [string]$admission.dot5_identity_authority.distribution_ledger_sha256) {
  throw "Foundation .5 authority files drifted after admission."
}
. (Join-Path $RepoRoot "tools\lib\validation\PackageIdentity.ps1")
Add-Type -AssemblyName System.IO.Compression.FileSystem
$wave = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\releases\archive\MIR-3.5-WAVE-INDEX.json") | ConvertFrom-Json -Depth 100
foreach ($identity in @($admission.dot5_identity_authority.releases)) {
  $row = @($wave.releases | Where-Object version -eq $identity.version)
  if ($row.Count -ne 1) { throw "Admitted .5 identity is absent from the wave index: $($identity.version)" }
  $archive = Join-Path $RepoRoot ([string]$row[0].dist)
  $zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
  try { $entryCount = $zip.Entries.Count } finally { $zip.Dispose() }
  if ([string]$identity.archive_sha256 -ne [string]$row[0].archive_sha256 -or [string]$identity.content_sha256 -ne [string]$row[0].content_sha256 -or
      [long]$identity.bytes -ne [long]$row[0].bytes -or [int]$identity.entries -ne [int]$row[0].entries -or
      (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne [string]$identity.archive_sha256 -or
      (Get-MIRZipContentFingerprint -Path $archive) -ne [string]$identity.content_sha256 -or
      (Get-Item -LiteralPath $archive).Length -ne [long]$identity.bytes -or $entryCount -ne [int]$identity.entries) {
    throw "Immutable .5 admission identity mismatch: $($identity.version)"
  }
}
if (Test-Path -LiteralPath (Join-Path $RepoRoot ".work")) { throw "Legacy .work directory exists after foundation admission." }

$programme = $authorities["MIR3-Terminal-ProgrammeV1"]
if (@(Compare-Object $family @($programme.family)).Count -ne 0 -or $programme.implementation_admitted -or $programme.source_frozen) {
  throw "Terminal programme must bind the exact unimplemented, unfrozen nine-release family."
}
$requiredOrder = @("baseline-capture", "bounded-change-admission", "implementation", "all-nine-shadow-materialization", "all-nine-fixed-point-sweeps", "source-freeze", "candidate-assignment", "all-nine-final-qualification-and-seals", "family-readiness-seal", "local-signed-annotated-tags", "controlled-publication")
if (($programme.execution_order -join "|") -ne ($requiredOrder -join "|")) { throw "Terminal execution order is not canonical." }

$baselineQueue = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\terminal\MIR3-Terminal-Baseline-Capture-QueueV1.json") | ConvertFrom-Json -Depth 100
if ([string]$baselineQueue.kind -ne "MIR3-Terminal-Baseline-Capture-QueueV1" -or @($baselineQueue.rows).Count -ne 9 -or
    (@($baselineQueue.rows.terminal_release) -join "|") -ne ($family -join "|") -or @($baselineQueue.required_semantic_inventory).Count -lt 15 -or
    [string]$baselineQueue.status -ne "complete-all-nine-realized-and-reconciled" -or
    @($baselineQueue.rows | Where-Object { $_.identity_status -ne "locked" -or $_.semantic_inventory_status -ne "complete" -or -not $_.baseline_manifest }).Count -ne 0) {
  throw "Terminal baseline queue must bind nine complete exact-engine captures."
}
foreach ($row in @($baselineQueue.rows)) {
  $baselineManifestPath = Join-Path $RepoRoot ([string]$row.baseline_manifest)
  $baselineManifest = Get-Content -Raw -LiteralPath $baselineManifestPath | ConvertFrom-Json -Depth 100
  if ([string]$baselineManifest.release -ne [string]$row.baseline_release -or [string]$baselineManifest.completion.state -ne "complete") {
    throw "Terminal baseline queue row does not bind its reconciled manifest: $($row.baseline_release)"
  }
}
$portalCustodyPath = Join-Path $RepoRoot ([string]$baselineQueue.source_authorities.mod_portal_custody)
$portalCustody = Get-Content -Raw -LiteralPath $portalCustodyPath | ConvertFrom-Json -Depth 100
$dot5Family = @($baselineQueue.rows.baseline_release)
$visiblePortalRows = @($portalCustody.observations | Where-Object state -eq "api-visible-sha1-matches-frozen-archive-redownload-pending")
$absentPortalRows = @($portalCustody.observations | Where-Object state -eq "not-uploaded-as-of-observation")
if ([string]$portalCustody.kind -ne "MIR3Dot5ModPortalCustodyV1" -or
    [string]$portalCustody.status -ne "partial-two-api-visible-redownload-pending-seven-not-uploaded" -or
    (@($portalCustody.observations.version) -join "|") -ne ($dot5Family -join "|") -or
    $visiblePortalRows.Count -ne 2 -or $absentPortalRows.Count -ne 7 -or
    @($visiblePortalRows | Where-Object { $_.portal_sha1 -ne $_.frozen_archive_sha1 -or $_.redownload_verification -notmatch '^pending-' }).Count -ne 0 -or
    [bool]$portalCustody.download_attempt.artifact_created -or [bool]$portalCustody.download_attempt.admitted_as_byte_evidence -or
    [bool]$portalCustody.identity_policy.published_package_mutation_permitted) {
  throw "The .5 Mod Portal custody authority must preserve the observed two-visible/seven-absent state without claiming byte verification."
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
$acceleratedClosure = $authorities["MIR3TerminalAcceleratedClosureDecisionV1"]
if ([string]$programme.authorities.accelerated_closure -ne ".mir/releases/terminal/MIR3TerminalAcceleratedClosureDecisionV1.json" -or
    [string]$acceleratedClosure.status -ne "active" -or
    [string]$acceleratedClosure.ordinary_terminal_intake.status -ne "closes-after-present-characterization-pass" -or
    @($acceleratedClosure.eligible_for_dot9).Count -ne 4 -or
    @($acceleratedClosure.not_eligible_after_freeze).Count -lt 5 -or
    [string]$acceleratedClosure.late_report_disposition.non_blocking -ne "MIR4-intake" -or
    [string]$acceleratedClosure.late_report_disposition.release_blocking_p0_or_p1 -ne "reopen-affected-dot9-targets-with-new-reproduced-finding" -or
    $acceleratedClosure.hard_boundaries.dot5_package_mutation_permitted -or
    $acceleratedClosure.hard_boundaries.dot9_product_implementation_admitted_by_this_decision -or
    $acceleratedClosure.hard_boundaries.source_freeze_permitted_by_this_decision -or
    $acceleratedClosure.hard_boundaries.candidate_assignment_permitted_by_this_decision -or
    $acceleratedClosure.hard_boundaries.mir4_implementation_permitted) {
  throw "Accelerated closure decision widens terminal scope or fails to close ordinary intake truthfully."
}
$fixedPoint = $authorities["MIR3-Terminal-FixedPointPolicyV1"]
if (($fixedPoint.participants -join "|") -ne ($family -join "|") -or @($fixedPoint.convergence).Count -ne 5 -or -not $fixedPoint.source_freeze_requires_accepted_receipt) {
  throw "Terminal fixed-point authority is incomplete."
}
$publication = $authorities["MIR3-Terminal-PublicationPolicyV1"]
if (@($publication.first_public_tag_requires).Count -lt 4 -or $publication.failure_policy.rollback_by_deletion -or -not $publication.failure_policy.same_byte_resume) {
  throw "Terminal family publication policy is incomplete."
}

$protection = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\terminal\MIR3-Terminal-Protection-HandoffV1.json") | ConvertFrom-Json -Depth 100
$dot5Tags = @("refs/tags/3.2.5", "refs/tags/2.5.5", "refs/tags/1.9.5", "refs/tags/1.8.5", "refs/tags/1.7.5", "refs/tags/1.6.5", "refs/tags/1.5.5", "refs/tags/1.4.5", "refs/tags/1.3.5")
$dot9Tags = @($family | ForEach-Object { "refs/tags/$_" })
$checkNames = @("branch-policy", "verification-gate")
if ([string]$protection.kind -ne "MIR3-Terminal-Protection-HandoffV1" -or
    [string]$protection.status -ne "corrected-ready-for-application-blocked-external-auth" -or
    [string]$protection.application_receipt.status -ne "not-applied" -or
    (@($protection.immutable_dot5_tags) -join "|") -ne ($dot5Tags -join "|") -or
    (@($protection.future_terminal_tags) -join "|") -ne ($dot9Tags -join "|") -or
    @($protection.observed_required_checks | Where-Object { $_.context -notin $checkNames -or [int]$_.integration_id -ne 15368 -or $_.conclusion -ne "success" }).Count -ne 0 -or
    @($protection.branches | Where-Object { $_.ref -in @("refs/heads/main", "refs/heads/legacy") -and $_.required_pull_request }).Count -ne 0) {
  throw "Terminal protection handoff is incomplete, overclaims application, or contradicts promotion topology."
}

$payloadRoot = Join-Path $RepoRoot ([string]$protection.payload_root)
$payloadNames = @("dev-integrity.json", "dev-workflow.json", "main-integrity.json", "main-promotion.json", "legacy-integrity.json", "legacy-promotion.json", "dot5-immutable.json", "dot9-immutable.json", "dot9-creation-gate.json", "canary-branch.json", "canary-tag.json")
$payloads = @{}
foreach ($name in $payloadNames) {
  $path = Join-Path $payloadRoot $name
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Terminal protection payload is missing: $name" }
  $payload = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ([string]$payload.enforcement -ne "active" -or @($payload.conditions.ref_name.include).Count -eq 0) { throw "Terminal protection payload is inactive or unscoped: $name" }
  $payloads[$name] = $payload
}
foreach ($name in @("dev-integrity.json", "main-integrity.json", "legacy-integrity.json")) {
  $payload = $payloads[$name]
  $statusRule = @($payload.rules | Where-Object type -eq "required_status_checks")
  if (@($payload.bypass_actors).Count -ne 0 -or $statusRule.Count -ne 1 -or
      (@($statusRule[0].parameters.required_status_checks.context) -join "|") -ne ($checkNames -join "|") -or
      @($statusRule[0].parameters.required_status_checks | Where-Object { [int]$_.integration_id -ne 15368 }).Count -ne 0 -or
      @($payload.rules | Where-Object type -eq "deletion").Count -ne 1 -or @($payload.rules | Where-Object type -eq "non_fast_forward").Count -ne 1) {
    throw "Terminal branch integrity checks are bypassable or incomplete: $name"
  }
}
foreach ($name in @("main-promotion.json", "legacy-promotion.json")) {
  $payload = $payloads[$name]
  if ((@($payload.rules.type) -join "|") -ne "update" -or @($payload.bypass_actors).Count -ne 1 -or
      [int]$payload.bypass_actors[0].actor_id -ne 30209022 -or [string]$payload.bypass_actors[0].bypass_mode -ne "always") {
    throw "Terminal promotion payload widens the exact actor/update exception: $name"
  }
}
if ((@($payloads["dot5-immutable.json"].conditions.ref_name.include) -join "|") -ne ($dot5Tags -join "|") -or
    (@($payloads["dot9-immutable.json"].conditions.ref_name.include) -join "|") -ne ($dot9Tags -join "|") -or
    @($payloads["dot5-immutable.json"].bypass_actors).Count -ne 0 -or @($payloads["dot9-immutable.json"].bypass_actors).Count -ne 0 -or
    (@($payloads["dot9-creation-gate.json"].rules.type) -join "|") -ne "creation") {
  throw "Published or future terminal tag lifecycle payloads are incomplete."
}
foreach ($name in @("canary-branch.json", "canary-tag.json")) {
  $includes = @($payloads[$name].conditions.ref_name.include)
  if ($includes.Count -ne 1 -or [string]$includes[0] -notmatch '^refs/(heads|tags)/canary/mir3-terminal-protection-\*$' -or
      @($includes | Where-Object { $_ -in @("refs/heads/dev", "refs/heads/main", "refs/heads/legacy") -or $_ -in $dot5Tags -or $_ -in $dot9Tags }).Count -ne 0) {
    throw "Terminal protection canary is not isolated from real refs: $name"
  }
}

$baselineSchemaNames = @("mir3-terminal-baseline-inventory-common", "mir3-terminal-baseline-identity", "mir3-terminal-baseline-engine-lock", "mir3-terminal-baseline-package-composition", "mir3-terminal-baseline-reconciliation", "mir3-terminal-baseline-feature-inventory", "mir3-terminal-baseline-technology-inventory", "mir3-terminal-baseline-setting-inventory", "mir3-terminal-baseline-locale-inventory", "mir3-terminal-baseline-ownership-inventory", "mir3-terminal-baseline-runtime-profile-inventory", "mir3-terminal-baseline-migration-inventory", "mir3-terminal-baseline-compatibility-inventory", "mir3-terminal-baseline-upgrade-inventory", "mir3-terminal-baseline-performance-inventory")
$schemaNames = @("mir3-terminal-package-manifest", "mir3-terminal-release-manifest", "mir3-terminal-publication-receipt", "mir3-terminal-engine-observation", "mir3-terminal-finding", "mir3-terminal-baseline-bundle-manifest", "mir3-terminal-dot5-semantic-matrix", "mir3-terminal-qualification-record", "mir3-terminal-target-seal", "mir3-terminal-fixed-point-receipt", "mir3-terminal-family-readiness", "mir3-final-index", "mir3-eol-record", "mir3-terminal-authority", "mir3-museum-index", "mir3-terminal-018-feasibility-gate") + $baselineSchemaNames
foreach ($name in $schemaNames) {
  $path = Join-Path $RepoRoot "spec\schemas\$name.schema.json"
  $schema = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ([string]$schema.'x-mir-canonical-path' -ne "spec/schemas/$name.schema.json") { throw "Terminal schema canonical path is invalid: $name" }
}
$findingSchema = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "spec\schemas\mir3-terminal-finding.schema.json") | ConvertFrom-Json -Depth 100
if ($findingSchema.additionalProperties -ne $false -or @($findingSchema.required).Count -lt 15 -or
    $findingSchema.properties.source_observation.additionalProperties -ne $false -or
    $findingSchema.properties.reproducer.additionalProperties -ne $false -or
    $findingSchema.properties.target_dispositions.minItems -ne 9 -or $findingSchema.properties.target_dispositions.maxItems -ne 9 -or
    $findingSchema.properties.target_dispositions.items.additionalProperties -ne $false -or
    $findingSchema.properties.admission.additionalProperties -ne $false -or $findingSchema.properties.closure.additionalProperties -ne $false) {
  throw "Terminal finding schema is not strict or all-nine complete."
}
$baselineCommon = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "spec\schemas\mir3-terminal-baseline-inventory-common.schema.json") | ConvertFrom-Json -Depth 100
if ($baselineCommon.additionalProperties -ne $false -or @($baselineCommon.required).Count -lt 11 -or
    $baselineCommon.'$defs'.item.additionalProperties -ne $false -or @($baselineCommon.'$defs'.item.required).Count -lt 9 -or
    $baselineCommon.'$defs'.omission.additionalProperties -ne $false) {
  throw "Terminal semantic baseline inventory schema is not strict or complete."
}
foreach ($name in @($baselineSchemaNames | Where-Object { $_ -match '-(feature|technology|setting|locale|ownership|runtime-profile|migration|compatibility|upgrade|performance)-inventory$' })) {
  $schema = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "spec\schemas\$name.schema.json") | ConvertFrom-Json -Depth 100
  if ([string]$schema.allOf[0].'$ref' -ne "mir3-terminal-baseline-inventory-common.schema.json" -or [string]$schema.allOf[1].properties.kind.const -notmatch '^MIR3TerminalBaseline.+InventoryV1$') {
    throw "Terminal semantic baseline child schema does not close over the strict common contract: $name"
  }
}
$digestSchemas = @("mir3-terminal-target-seal", "mir3-terminal-family-readiness", "mir3-final-index", "mir3-eol-record")
foreach ($name in $digestSchemas) {
  $schema = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "spec\schemas\$name.schema.json") | ConvertFrom-Json -Depth 100
  if ("seal_material_sha256" -notin @($schema.required) -or "record_sha256" -notin @($schema.required) -or "seal_sha256" -in @($schema.required) -or
      [string]$schema.properties.record_sha256.description -notmatch 'record_sha256 omitted') {
    throw "Terminal sealed-record digest contract is circular or incomplete: $name"
  }
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
    $current.roles.canonical -ne "3.2.5" -or $current.roles.backport_calibration -ne "2.5.5" -or
    $current.roles.planned_canonical -ne "3.2.9" -or $current.roles.planned_backport -ne "2.5.9" -or
    $current.active_programme.id -ne "MIR3-Terminal-ProgrammeV1" -or $current.active_programme.status -ne "active-planning-only") {
  throw "Current release roles do not distinguish published .5 from planned .9."
}

$wave = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\releases\archive\MIR-3.5-WAVE-INDEX.json") | ConvertFrom-Json
if ([string]$wave.mod_portal_custody.authority -ne [string]$baselineQueue.source_authorities.mod_portal_custody -or
    [string]$wave.mod_portal_custody.status -ne [string]$portalCustody.status -or
    @($wave.releases | Where-Object mod_portal -eq "api-visible-sha1-match-redownload-pending").Count -ne 2 -or
    @($wave.releases | Where-Object mod_portal -eq "not-uploaded-as-of-2026-08-09").Count -ne 7) {
  throw "The archived .5 wave index does not agree with the current Mod Portal custody authority."
}
foreach ($release in @($wave.releases)) {
  $zip = Join-Path $RepoRoot ([string]$release.dist)
  if ((Get-Item -LiteralPath $zip).Length -ne [long]$release.bytes -or (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne [string]$release.archive_sha256) {
    throw "Immutable .5 distribution changed: $($release.version)"
  }
}

Write-Host "[ok] all-nine terminal governance, schemas, allocation, fixed point, custody, and immutable .5 identities passed."
