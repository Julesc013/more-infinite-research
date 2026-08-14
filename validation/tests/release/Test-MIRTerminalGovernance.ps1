param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path }

& (Join-Path $RepoRoot "validation/tests/release/Test-MIRTerminalShadowProjection.ps1") -RepoRoot $RepoRoot
if ($LASTEXITCODE -ne 0) { throw "MIR terminal shadow projection validation failed." }
& (Join-Path $RepoRoot "validation/tests/release/Test-MIRGitHubAdministration.ps1") -RepoRoot $RepoRoot
if ($LASTEXITCODE -ne 0) { throw "MIR GitHub administration preflight validation failed." }

$family = @("3.2.9", "2.5.9", "1.9.9", "1.8.9", "1.7.9", "1.6.9", "1.5.9", "1.4.9", "1.3.9")
$authorityNames = @(
  "MIR3-Terminal-ProgrammeV1",
  "MIR3-Terminal-ScopeFirewallV1",
  "MIR3-Terminal-Target-MatrixV1",
  "MIR3-Terminal-Candidate-AllocationV1",
  "MIR3-Terminal-FixedPointPolicyV1",
  "MIR3TerminalFixedPointReceiptV1",
  "MIR3TerminalSourceFreezeV1",
  "MIR3-Terminal-PublicationPolicyV1",
  "MIR3-Terminal-EOL-PolicyV1",
  "MIR3TerminalFoundationAdmissionV1",
  "MIR3TerminalAssuranceCalibrationReceiptV1",
  "MIR3TerminalAcceleratedClosureDecisionV1",
  "MIR3TerminalSuccessorBootstrapPolicyV1",
  "MIR3-Settings-Scope-AuditV1",
  "MIR3-ModPortal-Compatibility-CensusV1",
  "MIR3-ModPortal-Discussion-ReconciliationV1",
  "MIR3-Mod-Interaction-MatrixV1",
  "MIR3-Compatibility-ClaimsV1",
  "MIR3-Effective-Mutation-Owner-ReportV1",
  "MIR3-FINAL-DEFECT-INDEX",
  "MIR3-Engine-Gap-AuditV1",
  "MIR3TerminalProductAdmissionBundleV1"
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
$findingRecords = @{}
foreach ($findingRecordPath in @($changeSet.finding_records)) {
  $finding = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ([string]$findingRecordPath)) | ConvertFrom-Json -Depth 100
  if ([string]$finding.kind -ne "MIR3TerminalFindingV1" -or [string]$finding.id -notmatch '^MIR3-TERM-[0-9]{4}$' -or
      [string]$finding.reproducer.status -ne "reproduced" -or @($finding.target_dispositions).Count -ne 9 -or
      (@($finding.target_dispositions.target) -join "|") -ne ($family -join "|") -or [string]$finding.admission.status -ne "admitted") {
    throw "Terminal finding is incomplete, not all-nine-disposed, or not admitted: $findingRecordPath"
  }
  if ([string]$finding.admission.class -eq "NO_PACKAGE_CHANGE" -and
      ([bool]$finding.visibility.package -or [bool]$finding.visibility.gameplay -or -not [bool]$finding.visibility.assurance)) {
    throw "Package-excluded assurance finding widens package authority: $findingRecordPath"
  }
  if ([string]$finding.admission.class -eq "DOT9_REQUIRED" -and
      (-not [bool]$finding.visibility.package -or -not [bool]$finding.visibility.gameplay -or [bool]$finding.visibility.assurance)) {
    throw "Required product finding does not declare its package/gameplay boundary: $findingRecordPath"
  }
  $findingRecords[[string]$finding.id] = $finding
}

$foundationPath = Join-Path $RepoRoot ".mir\releases\terminal\MIR3TerminalFoundationAdmissionV1.json"
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

$calibrationReceiptPath = Join-Path $RepoRoot ".mir\releases\terminal\MIR3TerminalAssuranceCalibrationReceiptV1.json"
$calibrationReceiptSchemaPath = Join-Path $RepoRoot "spec\schemas\mir3-terminal-assurance-calibration-receipt.schema.json"
$calibration = Get-Content -Raw -LiteralPath $calibrationReceiptPath | ConvertFrom-Json -Depth 100 -DateKind String
$calibrationSchema = Get-Content -Raw -LiteralPath $calibrationReceiptSchemaPath | ConvertFrom-Json -Depth 100
if ("entries" -notin @($calibrationSchema.'$defs'.packageIdentity.required)) {
  throw "Terminal calibration package identity schema must require entry counts."
}
function Test-MIRRfc3339Timestamp {
  param([Parameter(Mandatory)][string]$Value)

  $rfc3339Pattern = '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$'
  if ($Value -notmatch $rfc3339Pattern) { return $false }

  $parsed = [DateTimeOffset]::MinValue
  return [DateTimeOffset]::TryParse(
    $Value,
    [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::RoundtripKind,
    [ref]$parsed
  )
}
if (Test-MIRRfc3339Timestamp -Value "08/11/2026 00:57:44") {
  throw "Culture-dependent terminal calibration timestamps must be rejected."
}
if (-not ((Get-Content -Raw -LiteralPath $calibrationReceiptPath) | Test-Json -SchemaFile $calibrationReceiptSchemaPath) -or
    [string]$calibration.status -ne "accepted" -or [string]$calibration.scope -ne "package-excluded-terminal-assurance-calibration" -or
    [string]$calibration.assurance_freeze.status -ne "frozen" -or [int]$calibration.closure.unresolved_release_blocking_assurance_findings -ne 0 -or
    [bool]$calibration.closure.package_bytes_changed -or [bool]$calibration.closure.candidate_assigned -or [bool]$calibration.closure.source_frozen) {
  throw "Terminal assurance calibration receipt is invalid, incomplete, or widens release authority."
}
$currentAssuranceTree = (& git -C $RepoRoot rev-parse "$($calibration.source_authorities.current.commit)^{tree}").Trim()
if ($LASTEXITCODE -ne 0 -or $currentAssuranceTree -ne [string]$calibration.source_authorities.current.tree -or
    [string]$calibration.source_authorities.current.commit -ne "838d67a21364da6f669411ae64b360de67febaa5" -or
    [string]$calibration.source_authorities.historical_projection.commit -ne "bc9d63c3b665145abd7f1ccccff8a3a908e8bd0d" -or
    [string]$calibration.source_authorities.historical_projection.tree -ne "2ec5ff49f9cfb7efb4301f768f8bb203e6731eb2") {
  throw "Terminal assurance calibration source commit/tree binding is invalid."
}
$expectedCalibrationPrs = @(83, 84, 85)
$hostedChecks = @($calibration.source_authorities.hosted_exact_head_checks)
if (($hostedChecks.pr -join "|") -ne ($expectedCalibrationPrs -join "|") -or @($hostedChecks | Where-Object {
      [string]$_.status -ne "passed" -or [long]$_.mir_run -le 0 -or [long]$_.branch_policy_run -le 0
    }).Count -ne 0) {
  throw "Terminal assurance calibration does not bind the exact hosted implementation heads."
}
$calibrationTargets = @($calibration.calibration_targets)
if (($calibrationTargets.release -join "|") -ne "3.2.5|2.5.5" -or
    (@($calibrationTargets[0].rerun_test_ids).Count -ne 137) -or (@($calibrationTargets[1].rerun_test_ids).Count -ne 104)) {
  throw "Terminal assurance calibration does not bind the exact two target catalogs."
}
$totalRerunRows = 0
foreach ($targetCalibration in $calibrationTargets) {
  $rerunIds = @($targetCalibration.rerun_test_ids)
  if (@($rerunIds | Sort-Object -Unique).Count -ne $rerunIds.Count -or
      "runtime.ecosystem" -notin $rerunIds -or "runtime.performance-regression" -notin $rerunIds -or "manual.release-review" -notin $rerunIds -or
      (@($targetCalibration.campaigns).role -join "|") -ne "convergence|independent-confirmation") {
    throw "Terminal assurance calibration rerun inventory is incomplete: $($targetCalibration.release)"
  }
  $planMaterials = @($targetCalibration.campaigns.plan_material_sha256 | Sort-Object -Unique)
  $testSets = @($targetCalibration.campaigns.required_test_set_sha256 | Sort-Object -Unique)
  $capsuleSets = @($targetCalibration.campaigns.capsule_set_sha256 | Sort-Object -Unique)
  $bundles = @($targetCalibration.campaigns.bundle_sha256 | Sort-Object -Unique)
  $performanceTrees = @($targetCalibration.campaigns.performance_custody.artifact_tree_sha256 | Sort-Object -Unique)
  if ($planMaterials.Count -ne 1 -or $testSets.Count -ne 1 -or $capsuleSets.Count -ne 2 -or $bundles.Count -ne 2 -or $performanceTrees.Count -ne 2) {
    throw "Convergence and independent confirmation are not a stable-plan, distinct-evidence pair: $($targetCalibration.release)"
  }
  foreach ($campaign in @($targetCalibration.campaigns)) {
    if (-not (Test-MIRRfc3339Timestamp -Value ([string]$campaign.generated_at)) -or
        -not (Test-MIRRfc3339Timestamp -Value ([string]$campaign.completed_at)) -or
        [DateTimeOffset]::Parse([string]$campaign.completed_at, [Globalization.CultureInfo]::InvariantCulture) -lt
          [DateTimeOffset]::Parse([string]$campaign.generated_at, [Globalization.CultureInfo]::InvariantCulture) -or
        [int]$campaign.counts.planned -ne $rerunIds.Count -or [int]$campaign.counts.executed -ne $rerunIds.Count -or
        [int]$campaign.counts.checkpoint_adopted -ne 0 -or [int]$campaign.counts.ordinary_reused -ne 0 -or
        [int]$campaign.counts.failed -ne 0 -or [int]$campaign.counts.incomplete -ne 0 -or [int]$campaign.counts.unexpected -ne 0 -or
        [string]$campaign.counts.rerun_scope -ne "all-planned-rows") {
      throw "Terminal assurance campaign execution ledger is not exact and fresh: $($targetCalibration.release)/$($campaign.role)"
    }
    $totalRerunRows += [int]$campaign.counts.executed
  }
}
if ($totalRerunRows -ne 482 -or [int]$calibration.resumability.final_campaign_rows_rerun -ne 482 -or
    [int]$calibration.resumability.final_campaign_checkpoint_adoptions -ne 0 -or [string]$calibration.resumability.status -ne "passed") {
  throw "Terminal resumability calibration row accounting is invalid."
}
$attestationPath = Join-Path $RepoRoot ([string]$calibration.historical_manual_review.path)
$attestationObjectPath = Join-Path $RepoRoot ([string]$calibration.historical_manual_review.content_addressed_object)
if ((Get-FileHash -LiteralPath $attestationPath -Algorithm SHA256).Hash -ne [string]$calibration.historical_manual_review.raw_sha256 -or
    (Get-FileHash -LiteralPath $attestationObjectPath -Algorithm SHA256).Hash -ne [string]$calibration.historical_manual_review.raw_sha256) {
  throw "Historical manual-review attestation lost its byte-identical custody binding."
}
if ((Get-FileHash -LiteralPath $foundationPath -Algorithm SHA256).Hash -ne [string]$calibration.all_nine_dot5_identity.authority_sha256 -or
    @($calibration.all_nine_dot5_identity.releases).Count -ne 9) {
  throw "Terminal calibration lost the admitted all-nine immutable .5 identity authority."
}
foreach ($identity in @($calibration.all_nine_dot5_identity.releases)) {
  $admittedIdentity = @($admission.dot5_identity_authority.releases | Where-Object version -eq $identity.version)
  if ($admittedIdentity.Count -ne 1 -or [string]$identity.archive_sha256 -ne [string]$admittedIdentity[0].archive_sha256 -or
      [string]$identity.content_sha256 -ne [string]$admittedIdentity[0].content_sha256 -or [long]$identity.bytes -ne [long]$admittedIdentity[0].bytes -or
      [int]$identity.entries -ne [int]$admittedIdentity[0].entries) {
    throw "Terminal calibration .5 identity differs from foundation admission: $($identity.version)"
  }
}
$calibrationFindingIds = @($calibration.finding_closures.id)
foreach ($finding in @($findingRecords.Values | Where-Object severity -eq "assurance")) {
  if ([string]$finding.closure.status -ne "closed") { throw "Release-blocking assurance finding remains unresolved: $($finding.id)" }
  if ([string]$finding.id -in @("MIR3-TERM-0012", "MIR3-TERM-0015", "MIR3-TERM-0016", "MIR3-TERM-0017", "MIR3-TERM-0018", "MIR3-TERM-0019", "MIR3-TERM-0020", "MIR3-TERM-0021", "MIR3-TERM-0022", "MIR3-TERM-0023", "MIR3-TERM-0024", "MIR3-TERM-0025", "MIR3-TERM-0026", "MIR3-TERM-0029", "MIR3-TERM-0030") -and
      ([string]$finding.id -notin $calibrationFindingIds -or [string]$finding.closure.evidence -ne ".mir/releases/terminal/MIR3TerminalAssuranceCalibrationReceiptV1.json")) {
    throw "Assurance finding closure is not bound to the calibration receipt: $($finding.id)"
  }
}
$legacyCalibrationItem = @($changeSet.items | Where-Object id -eq "MIR3-TERM-0003")
if ($legacyCalibrationItem.Count -ne 1 -or [string]$legacyCalibrationItem[0].closure.status -ne "closed" -or
    [string]$legacyCalibrationItem[0].closure.evidence -ne ".mir/releases/terminal/MIR3TerminalAssuranceCalibrationReceiptV1.json") {
  throw "Legacy terminal calibration debt remains unresolved."
}
if (Test-Path -LiteralPath (Join-Path $RepoRoot ".work")) { throw "Legacy .work directory exists after foundation admission." }

$programme = $authorities["MIR3-Terminal-ProgrammeV1"]
if (@(Compare-Object $family @($programme.family)).Count -ne 0 -or -not $programme.implementation_admitted -or -not $programme.source_frozen -or
    [string]$programme.status -ne "source-frozen-ready-for-candidate-allocation") {
  throw "Terminal programme must bind the exact fixed-point-accepted, source-frozen nine-release family."
}
$requiredOrder = @("baseline-capture", "bounded-change-admission", "implementation", "all-nine-shadow-materialization", "all-nine-fixed-point-sweeps", "source-freeze", "candidate-assignment", "all-nine-final-qualification-and-seals", "family-readiness-seal", "local-signed-annotated-tags", "controlled-publication")
if (($programme.execution_order -join "|") -ne ($requiredOrder -join "|")) { throw "Terminal execution order is not canonical." }

$productIntakeSchemaByKind = @{
  "MIR3TerminalSuccessorBootstrapPolicyV1" = "mir3-terminal-successor-bootstrap-policy"
  "MIR3-Settings-Scope-AuditV1" = "mir3-settings-scope-audit"
  "MIR3-ModPortal-Compatibility-CensusV1" = "mir3-mod-portal-compatibility-census"
  "MIR3-ModPortal-Discussion-ReconciliationV1" = "mir3-mod-portal-discussion-reconciliation"
  "MIR3-Mod-Interaction-MatrixV1" = "mir3-mod-interaction-matrix"
  "MIR3-Compatibility-ClaimsV1" = "mir3-compatibility-claims"
  "MIR3-Effective-Mutation-Owner-ReportV1" = "mir3-effective-mutation-owner-report"
  "MIR3-FINAL-DEFECT-INDEX" = "mir3-final-defect-index"
  "MIR3-Engine-Gap-AuditV1" = "mir3-engine-gap-audit"
  "MIR3TerminalProductAdmissionBundleV1" = "mir3-terminal-product-admission-bundle"
  "MIR3TerminalFixedPointReceiptV1" = "mir3-terminal-fixed-point-receipt"
}
foreach ($kind in @($productIntakeSchemaByKind.Keys)) {
  $authorityPath = Join-Path $RepoRoot ".mir\releases\terminal\$kind.json"
  $schemaPath = Join-Path $RepoRoot "spec\schemas\$($productIntakeSchemaByKind[$kind]).schema.json"
  if (-not ((Get-Content -Raw -LiteralPath $authorityPath) | Test-Json -SchemaFile $schemaPath)) {
    throw "Terminal product-intake authority does not match its strict schema: $kind"
  }
}

$successorBootstrap = $authorities["MIR3TerminalSuccessorBootstrapPolicyV1"]
if ([string]$programme.authorities.successor_bootstrap -ne ".mir/releases/terminal/MIR3TerminalSuccessorBootstrapPolicyV1.json" -or
    [string]$successorBootstrap.status -ne "active-package-excluded" -or
    [bool]$successorBootstrap.production_plane.release_bytes_may_be_changed_by_successor_work -or
    [bool]$successorBootstrap.production_plane.cutover_before_mir3_eol -or
    [bool]$successorBootstrap.successor_plane.may_publish_version_4 -or
    [bool]$successorBootstrap.cutover_gate.mir4_shadow_completion_blocks_dot9 -or
    @($successorBootstrap.terminal_import_authorities).Count -ne 4) {
  throw "Successor bootstrap policy widens pre-EOL authority or package visibility."
}

$settingsAudit = $authorities["MIR3-Settings-Scope-AuditV1"]
if ([string]$programme.authorities.settings_scope_audit -ne ".mir/releases/terminal/MIR3-Settings-Scope-AuditV1.json" -or
    @($settingsAudit.setting_families).Count -ne 7 -or
    @($settingsAudit.setting_families | Where-Object { $_.scope -ne "startup" -or -not $_.restart_required -or $_.profile_namespace -ne "compile" }).Count -ne 0 -or
    [int]$settingsAudit.stage_read_validation.runtime_global_settings_registered -ne 0 -or
    [int]$settingsAudit.stage_read_validation.runtime_per_user_settings_registered -ne 0 -or
    [int]$settingsAudit.stage_read_validation.released_setting_type_changes -ne 0 -or
    [bool]$settingsAudit.stage_read_validation.new_dot9_runtime_setting_admitted -or
    [string]$settingsAudit.profile_contract.current_codec -ne "MIRSET1" -or [bool]$settingsAudit.profile_contract.schema_change_admitted) {
  throw "Terminal settings-scope audit changes a released scope, admits an unjustified runtime control, or loses MIRSET1."
}

$census = $authorities["MIR3-ModPortal-Compatibility-CensusV1"]
$expectedTierA = @("Krastorio2", "Krastorio2-spaced-out", "cubium", "productivity-through-science", "ProductivityResearchForEveryone", "ProductivityResearchForEveryoneFG", "ExpandedProductivityResearch", "crafting-efficiency-2", "remove-productivity-cap", "modified-productivity-cap", "UnlimitedProductivityFork", "fair-unlimited-productivity", "science-not-invited", "ScienceCostTweakerM", "productivity-technology-limit", "finite_prod_techs")
if ([string]$programme.authorities.mod_portal_compatibility_census -ne ".mir/releases/terminal/MIR3-ModPortal-Compatibility-CensusV1.json" -or
    (@($census.tier_a.name) -join "|") -ne ($expectedTierA -join "|") -or @($census.tier_a.releases).Count -ne 28 -or
    [int]$census.api.rows_scanned.'2.1' -ne 3367 -or [int]$census.api.rows_scanned.'2.0' -ne 9338 -or
    @($census.supplemental_exact_archive_locks).Count -ne 3 -or [bool]$census.archive_policy.authenticated_download_completed_for_current_census -or
    [bool]$census.archive_policy.'local_exact_sha1_match_is_runtime-proof' -or [bool]$census.archive_policy.modified_or_shim_archive_may_support_public_claim) {
  throw "Terminal Mod Portal census is incomplete, unbounded, or promotes local/static evidence into a runtime claim."
}
foreach ($release in @($census.tier_a.releases | Where-Object { $null -ne $_.local_sha256 })) {
  if ([string]$release.archive_state -notmatch '^local-exact-portal-sha1-match') {
    throw "A local Tier A archive digest is not explicitly bound as an exact portal SHA-1 match: $($release.version)"
  }
}

$discussionReconciliation = $authorities["MIR3-ModPortal-Discussion-ReconciliationV1"]
$expectedDiscussionIds = @(
  "68f8e983f3937755388bce07", "68fa30a0e3359475cfbc8e3b", "690240a9a8da210ba60a6655", "6a1fbbdca2b1de38bd581fdd",
  "6a4364f99578b6446a283279", "6a43666bf41b7876460c7a67", "6a4a3d24d67098d68c57f90c", "6a4e8c6884594f98390cc27e",
  "6a5029a0fc2d087349d7b27b", "6a53de8c425eced196e68c24", "6a53f0cd425eced196e68c32", "6a55009eaccd254ecaa02683",
  "6a55d1e51aacedd553f17d69", "6a58dc5e15625739f8897041", "6a5908b2e0bb1eb64fa996f6", "6a594aefe0bb1eb64fa99702",
  "6a5bb7abae192b42f00bc4a4", "6a64fba3954cdc5ccdc7127d", "6a6a3195bf84e2fe914c920c", "6a6a328023ef8e8966de505b",
  "6a6b723800cdd256f60059c3", "6a6c270932c3548953769590", "6a79147520108b995a72702a", "6a7cc4ed6d4d8ec344e3cc66"
)
if ([string]$programme.authorities.mod_portal_discussion_reconciliation -ne ".mir/releases/terminal/MIR3-ModPortal-Discussion-ReconciliationV1.json" -or
    [string]$discussionReconciliation.public_index.url -ne "https://mods.factorio.com/mod/more-infinite-research/discussion" -or
    [int]$discussionReconciliation.public_index.http_status -ne 200 -or [int]$discussionReconciliation.public_index.thread_count -ne 24 -or
    (@($discussionReconciliation.public_index.thread_ids) -join "|") -ne ($expectedDiscussionIds -join "|") -or
    (@($discussionReconciliation.threads.id) -join "|") -ne ($expectedDiscussionIds -join "|") -or
    @($discussionReconciliation.threads | Group-Object id | Where-Object Count -ne 1).Count -ne 0 -or
    @($discussionReconciliation.threads | Where-Object { @($_.linked_authorities).Count -eq 0 -or @($_.evidence).Count -eq 0 -or -not $_.rationale }).Count -ne 0 -or
    @($discussionReconciliation.threads | Where-Object release_blocking).id -join "|" -ne "6a4e8c6884594f98390cc27e|6a58dc5e15625739f8897041|6a79147520108b995a72702a|6a7cc4ed6d4d8ec344e3cc66" -or
    [int]$discussionReconciliation.summary.unclassified -ne 0 -or [int]$discussionReconciliation.summary.additional_product_findings_admitted -ne 0 -or
    -not [bool]$discussionReconciliation.boundaries.ordinary_intake_closed -or [bool]$discussionReconciliation.boundaries.source_frozen -or
    [bool]$discussionReconciliation.boundaries.candidate_assigned -or [bool]$discussionReconciliation.boundaries.dot5_package_mutation_permitted -or
    [bool]$discussionReconciliation.boundaries.broad_support_inferred_from_thread -or [bool]$discussionReconciliation.boundaries.portal_status_substitutes_for_regression_evidence) {
  throw "Terminal Mod Portal discussion reconciliation is incomplete, unclassified, or widens product and compatibility authority."
}

$claims = $authorities["MIR3-Compatibility-ClaimsV1"]
$claimLevels = @($claims.levels)
$claimDimensions = @($claims.dimensions)
$publicClaims = @($claims.claims | Where-Object public_claim_allowed)
$k2Claims = @($claims.claims | Where-Object id -eq "tier-a-k2-k2so-2.1-finding-envelope")
$cubium21Claims = @($claims.claims | Where-Object id -eq "tier-a-cubium-2.1")
if ([string]$programme.authorities.compatibility_claims -ne ".mir/releases/terminal/MIR3-Compatibility-ClaimsV1.json" -or
    @($claims.claims).Count -lt 16 -or @($claims.claims | Where-Object { $_.level -notin $claimLevels }).Count -ne 0 -or
    @($claims.claims | Where-Object { @($_.dimension_status.PSObject.Properties.Name).Count -ne $claimDimensions.Count }).Count -ne 0 -or
    $publicClaims.Count -ne 1 -or [string]$publicClaims[0].id -ne "tier-a-finite-prod-techs-0.1.1-narrow" -or
    $k2Claims.Count -ne 1 -or [string]$k2Claims[0].level -ne "KNOWN_CONFLICT" -or
    $cubium21Claims.Count -ne 1 -or [string]$cubium21Claims[0].level -ne "UPSTREAM_BLOCKED") {
  throw "Terminal compatibility claim classification is dimensionless, overbroad, or promotes unqualified evidence."
}

$interactionMatrix = $authorities["MIR3-Mod-Interaction-MatrixV1"]
if ([string]$programme.authorities.mod_interaction_matrix -ne ".mir/releases/terminal/MIR3-Mod-Interaction-MatrixV1.json" -or
    @($interactionMatrix.rows).Count -ne 16 -or @($interactionMatrix.rows | Where-Object { @($_.shared_surfaces).Count -eq 0 -or -not $_.required_campaign }).Count -ne 0) {
  throw "Terminal Mod Portal interaction matrix omits an overlap classification or qualification campaign."
}

$ownerReport = $authorities["MIR3-Effective-Mutation-Owner-ReportV1"]
$ownerActions = @("preserve", "apply", "skip", "conflict", "report")
$ownerScannerPath = Join-Path $RepoRoot ([string]$ownerReport.scanner)
if ([string]$programme.authorities.effective_mutation_owner_report -ne ".mir/releases/terminal/MIR3-Effective-Mutation-Owner-ReportV1.json" -or
    @($ownerReport.surfaces).Count -ne 9 -or @($ownerReport.surfaces | Where-Object { $_.mir_action -notin $ownerActions }).Count -ne 0 -or
    -not (Test-Path -LiteralPath $ownerScannerPath -PathType Leaf) -or
    (Get-Content -Raw -LiteralPath $ownerScannerPath) -notmatch 'compatibility_claim\s*=\s*"none"') {
  throw "Terminal effective mutation-owner report is incomplete or its scanner overclaims compatibility."
}

$defectIndex = $authorities["MIR3-FINAL-DEFECT-INDEX"]
$expectedFindingIds = @(1..31 | ForEach-Object { "MIR3-TERM-{0:D4}" -f $_ })
$expectedIncidentIds = @(35..60 | ForEach-Object { "INC-2026-{0:D4}" -f $_ })
$expectedIssueIds = @("GH-3", "GH-4", "GH-5", "GH-24", "GH-35")
$expectedPortalImplementedIds = @("6a4e8c6884594f98390cc27e", "6a58dc5e15625739f8897041", "6a79147520108b995a72702a", "6a7cc4ed6d4d8ec344e3cc66")
$indexedFindingIds = @($defectIndex.dispositions | Where-Object source_kind -eq "terminal-finding" | ForEach-Object source_id)
$indexedIncidentIds = @($defectIndex.dispositions | Where-Object source_kind -eq "lifecycle-incident" | ForEach-Object source_id)
$indexedIssueIds = @($defectIndex.dispositions | Where-Object source_kind -eq "github-issue" | ForEach-Object source_id)
$indexedDiscussionIds = @($defectIndex.dispositions | Where-Object source_kind -eq "mod-portal-discussion" | ForEach-Object source_id)
if ([string]$programme.authorities.final_defect_index -ne ".mir/releases/terminal/MIR3-FINAL-DEFECT-INDEX.json" -or
    @($defectIndex.dispositions).Count -ne 86 -or (@(Compare-Object $expectedFindingIds $indexedFindingIds)).Count -ne 0 -or
    (@(Compare-Object $expectedIncidentIds $indexedIncidentIds)).Count -ne 0 -or (@(Compare-Object $expectedIssueIds $indexedIssueIds)).Count -ne 0 -or
    (@(Compare-Object $expectedDiscussionIds $indexedDiscussionIds)).Count -ne 0 -or
    @($defectIndex.dispositions | Group-Object source_id | Where-Object Count -ne 1).Count -ne 0 -or
    @($defectIndex.dispositions | Where-Object completion -eq "admitted-pending-implementation").Count -ne 0 -or
    (@($defectIndex.dispositions | Where-Object { $_.source_kind -eq "terminal-finding" -and $_.completion -eq "implemented-fixed-point-accepted-awaiting-final-candidate-qualification" }).source_id -join "|") -ne "MIR3-TERM-0027|MIR3-TERM-0028|MIR3-TERM-0031" -or
    (@(Compare-Object $expectedPortalImplementedIds @($defectIndex.dispositions | Where-Object { $_.source_kind -eq "mod-portal-discussion" -and $_.completion -eq "implemented-fixed-point-accepted-awaiting-final-candidate-qualification" } | ForEach-Object source_id))).Count -ne 0 -or
    [int]$defectIndex.summary.unclassified -ne 0 -or -not [bool]$defectIndex.hard_boundaries.ordinary_intake_closed -or
    [bool]$defectIndex.hard_boundaries.source_frozen -or [bool]$defectIndex.hard_boundaries.candidate_assigned) {
  throw "Final defect index loses a repository issue, lifecycle incident, terminal finding, Mod Portal discussion, or pre-freeze boundary."
}

$engineGapAudit = $authorities["MIR3-Engine-Gap-AuditV1"]
$expectedEngineGapIds = @("general-item-research-ingredients", "recipe-category-sets", "probability-and-catalyst-semantics", "quality-aware-products", "recycling-safety-versus-throughput", "multi-level-trigger-prohibition", "late-mutation-detection")
if ([string]$programme.authorities.engine_gap_audit -ne ".mir/releases/terminal/MIR3-Engine-Gap-AuditV1.json" -or
    (@($engineGapAudit.surfaces.id) -join "|") -ne ($expectedEngineGapIds -join "|") -or
    @($engineGapAudit.surfaces | Where-Object { $_.classification -ne "covered-no-reproduced-dot9-defect" -or $_.dot9_admission -ne "none" -or @($_.evidence).Count -lt 2 }).Count -ne 0 -or
    [int]$engineGapAudit.summary.additional_reproduced_dot9_defects -ne 0) {
  throw "Bounded engine-gap audit is incomplete or invents an unreproduced MIR 3 defect."
}

$productAdmission = $authorities["MIR3TerminalProductAdmissionBundleV1"]
$acceptedFindingIds = @($productAdmission.accepted_findings.id)
if ([string]$programme.authorities.product_admission -ne ".mir/releases/terminal/MIR3TerminalProductAdmissionBundleV1.json" -or
    ($acceptedFindingIds -join "|") -ne "MIR3-TERM-0027|MIR3-TERM-0028|MIR3-TERM-0031" -or @($productAdmission.all_nine_dispositions).Count -ne 9 -or
    (@($productAdmission.all_nine_dispositions.release) -join "|") -ne ($family -join "|") -or
    -not [bool]$productAdmission.ordinary_intake.closed -or -not [bool]$productAdmission.boundaries.implementation_admitted -or
    [bool]$productAdmission.boundaries.source_frozen -or [bool]$productAdmission.boundaries.candidate_assigned -or
    [bool]$productAdmission.boundaries.dot5_package_mutation_permitted -or [bool]$productAdmission.boundaries.assurance_reopened -or
    [bool]$productAdmission.boundaries.mir4_package_visible_implementation_permitted -or [bool]$productAdmission.boundaries.tagging_or_publication_permitted) {
  throw "Terminal product admission is broad, unclassified, or crosses a freeze/publication boundary."
}

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
$portalRecheckPath = Join-Path $RepoRoot ([string]$programme.authorities.dot5_mod_portal_custody_recheck)
$portalRecheckSchemaPath = Join-Path $RepoRoot "spec\schemas\mir3-dot5-mod-portal-custody-recheck.schema.json"
$portalRecheck = Get-Content -Raw -LiteralPath $portalRecheckPath | ConvertFrom-Json -Depth 100
if (-not ((Get-Content -Raw -LiteralPath $portalRecheckPath) | Test-Json -SchemaFile $portalRecheckSchemaPath) -or
    [string]$portalRecheck.prior_authority -ne [string]$baselineQueue.source_authorities.mod_portal_custody -or
    (@($portalRecheck.observations.version) -join "|") -ne ($dot5Family -join "|") -or
    @($portalRecheck.observations | Where-Object portal_state -eq "api-visible").Count -ne 6 -or
    @($portalRecheck.observations | Where-Object portal_state -eq "not-uploaded").Count -ne 3 -or
    @($portalRecheck.observations | Where-Object { $_.portal_state -eq "api-visible" -and $_.portal_sha1 -ne $_.frozen_archive_sha1 }).Count -ne 0 -or
    [int]$portalRecheck.summary.authenticated_redownloads_complete -ne 0 -or [bool]$portalRecheck.summary.package_bytes_changed) {
  throw "The append-only .5 Mod Portal custody recheck overclaims bytes, loses the historical record, or disagrees with the live six/three observation."
}
foreach ($identity in @($admission.dot5_identity_authority.releases)) {
  $recheckIdentity = @($portalRecheck.observations | Where-Object version -eq $identity.version)
  if ($recheckIdentity.Count -ne 1 -or [string]$recheckIdentity[0].frozen_archive_sha256 -ne [string]$identity.archive_sha256 -or
      [long]$recheckIdentity[0].bytes -ne [long]$identity.bytes -or [int]$recheckIdentity[0].entries -ne [int]$identity.entries) {
    throw "Mod Portal custody recheck differs from the immutable foundation identity: $($identity.version)"
  }
}
$incidentReconciliation = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\terminal\MIR3-Terminal-Incident-ReconciliationV1.json") | ConvertFrom-Json -Depth 100
if ([string]$incidentReconciliation.kind -ne "MIR3-Terminal-Incident-ReconciliationV1" -or $incidentReconciliation.rules.history_mutation_permitted -or
    $incidentReconciliation.rules.dot5_package_mutation_permitted -or @($incidentReconciliation.items).Count -ne 15 -or
    @($incidentReconciliation.items | Where-Object terminal_state -ne "closed").Count -ne 0) {
  throw "Terminal incident reconciliation must preserve history and .5 bytes while closing calibrated assurance debt."
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
if (-not $changeSet.implementation_admitted -or [string]$changeSet.status -ne "product-set-admitted-ordinary-intake-closed-fixed-point-accepted-ready-for-source-freeze" -or
    (@($changeSet.product_intake.id) -join "|") -ne "MIR3-TERM-0027|MIR3-TERM-0028|MIR3-TERM-0031" -or
    @($changeSet.product_intake | Where-Object { $_.closure.status -ne "implemented-fixed-point-accepted-awaiting-final-candidate-qualification" }).Count -ne 0) {
  throw "Terminal change set must preserve the sealed intake and accepted fixed-point boundary without crossing source freeze."
}

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
$fixedPointReceipt = $authorities["MIR3TerminalFixedPointReceiptV1"]
if ([string]$programme.authorities.fixed_point_receipt -ne ".mir/releases/terminal/MIR3TerminalFixedPointReceiptV1.json" -or
    [string]$fixedPointReceipt.status -ne "accepted" -or
    (@($fixedPointReceipt.participants) -join "|") -ne ($family -join "|") -or
    (@($fixedPointReceipt.shadow_trees.release) -join "|") -ne ($family -join "|") -or
    @($fixedPointReceipt.shadow_trees).Count -ne 9 -or @($fixedPointReceipt.shadow_trees.upgrades).Count -ne 18 -or
    @($fixedPointReceipt.shadow_trees | Where-Object { [string]$_.convergence.status -ne "passed" -or [int]$_.convergence.failed -ne 0 -or [string]$_.confirmation.status -ne "passed" -or [int]$_.confirmation.failed -ne 0 }).Count -ne 0 -or
    @($fixedPointReceipt.shadow_trees.upgrades | Where-Object status -ne "passed").Count -ne 0 -or
    [int]$fixedPointReceipt.findings.new_portable_return_findings -ne 0 -or
    [int]$fixedPointReceipt.findings.unresolved_release_blocking_findings -ne 0 -or
    -not [bool]$fixedPointReceipt.findings.ordinary_product_intake_closed -or
    @($fixedPointReceipt.convergence_checks.PSObject.Properties | Where-Object { -not [bool]$_.Value }).Count -ne 0 -or
    -not [bool]$fixedPointReceipt.evidence_reuse_boundary.all_confirmation_campaigns_independent -or
    [bool]$fixedPointReceipt.evidence_reuse_boundary.mutable_job_status_used_as_evidence -or
    [string]$fixedPointReceipt.acceptance.fixed_point -ne "accepted" -or
    [bool]$fixedPointReceipt.acceptance.source_freeze_performed -or [bool]$fixedPointReceipt.acceptance.candidates_assigned -or
    [bool]$fixedPointReceipt.acceptance.final_qualification_performed -or [bool]$fixedPointReceipt.acceptance.tagging_or_publication_permitted -or
    [bool]$fixedPointReceipt.immutable_boundaries.dot5_package_bytes_changed -or [bool]$fixedPointReceipt.immutable_boundaries.history_rewritten -or
    [bool]$fixedPointReceipt.immutable_boundaries.force_push_used -or [bool]$fixedPointReceipt.immutable_boundaries.source_frozen -or
    [bool]$fixedPointReceipt.immutable_boundaries.candidate_assigned -or [bool]$fixedPointReceipt.immutable_boundaries.terminal_tag_created) {
  throw "Terminal fixed-point receipt is incomplete, non-converged, or crosses a later release boundary."
}
$fixedPointInputTree = (& git -C $RepoRoot rev-parse "$($fixedPointReceipt.dev_input_authority.commit)^{tree}").Trim()
if ($LASTEXITCODE -ne 0 -or $fixedPointInputTree -ne [string]$fixedPointReceipt.dev_input_authority.tree) {
  throw "Terminal fixed-point receipt lost its pre-receipt dev commit/tree binding."
}
$sourceFreeze = $authorities["MIR3TerminalSourceFreezeV1"]
$sourceFreezePath = Join-Path $RepoRoot ".mir\releases\terminal\MIR3TerminalSourceFreezeV1.json"
$sourceFreezeSchemaPath = Join-Path $RepoRoot "spec\schemas\mir3-terminal-source-freeze.schema.json"
$targetFreezeSchemaPath = Join-Path $RepoRoot "spec\schemas\mir3-terminal-target-source-freeze.schema.json"
if (-not ((Get-Content -Raw -LiteralPath $sourceFreezePath) | Test-Json -SchemaFile $sourceFreezeSchemaPath) -or
    [string]$programme.authorities.source_freeze -ne ".mir/releases/terminal/MIR3TerminalSourceFreezeV1.json" -or
    [string]$sourceFreeze.status -ne "source-frozen-candidates-unassigned" -or
    (@($sourceFreeze.family) -join "|") -ne ($family -join "|") -or @($sourceFreeze.targets).Count -ne 9 -or
    [bool]$sourceFreeze.boundaries.candidate_ids_assigned -or [bool]$sourceFreeze.boundaries.candidate_packages_built -or
    [bool]$sourceFreeze.boundaries.final_qualification_complete -or [bool]$sourceFreeze.boundaries.manual_review_complete -or
    [bool]$sourceFreeze.boundaries.tags_created -or [bool]$sourceFreeze.boundaries.publication_permitted -or
    [bool]$sourceFreeze.boundaries.dot5_package_bytes_changed) {
  throw "Terminal family source-freeze authority is invalid or crosses a later gate."
}
foreach ($binding in @($sourceFreeze.fixed_point, $sourceFreeze.repository_protection) + @($sourceFreeze.authority_roots)) {
  $bindingPath = Join-Path $RepoRoot ([string]$binding.path)
  if (-not (Test-Path -LiteralPath $bindingPath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $bindingPath -Algorithm SHA256).Hash -ne [string]$binding.sha256) {
    throw "Terminal source-freeze authority root drifted: $($binding.path)"
  }
}
$commonTree = (& git -C $RepoRoot rev-parse "$($sourceFreeze.common_source.commit)^{tree}").Trim()
if ($LASTEXITCODE -ne 0 -or $commonTree -ne [string]$sourceFreeze.common_source.tree -or
    [string]$sourceFreeze.common_source.package_source_sha256 -ne "FE68D37CCDB0685120579AF04AA62ABA7DD41F1F4AF01A02B72015A907794B25" -or
    [int]$sourceFreeze.common_source.package_file_count -ne 303) {
  throw "Terminal common source freeze lost its commit, tree, or package-material binding."
}
foreach ($release in $family) {
  $targetPath = Join-Path $RepoRoot ".mir\releases\terminal\freezes\$release.json"
  if (-not ((Get-Content -Raw -LiteralPath $targetPath) | Test-Json -SchemaFile $targetFreezeSchemaPath)) {
    throw "Terminal target source-freeze packet does not match its strict schema: $release"
  }
  $targetFreeze = Get-Content -Raw -LiteralPath $targetPath | ConvertFrom-Json -Depth 100 -DateKind String
  $fixedRow = @($fixedPointReceipt.shadow_trees | Where-Object release -eq $release)
  $profileRow = @((Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\terminal\MIR3-Terminal-Shadow-ProjectionProfilesV1.json") | ConvertFrom-Json -Depth 100).targets | Where-Object release -eq $release)
  if ($fixedRow.Count -ne 1 -or $profileRow.Count -ne 1 -or [string]$targetFreeze.status -ne "source-frozen-candidate-unassigned" -or
      $null -ne $targetFreeze.candidate_id -or [string]$targetFreeze.common_source_commit -ne [string]$sourceFreeze.common_source.commit -or
      [string]$targetFreeze.shadow_source.commit -ne [string]$fixedRow[0].source.commit -or [string]$targetFreeze.shadow_source.tree -ne [string]$fixedRow[0].source.tree -or
      [string]$targetFreeze.package.archive_sha256 -ne [string]$fixedRow[0].package.archive_sha256 -or
      [string]$targetFreeze.package.content_sha256 -ne [string]$fixedRow[0].package.content_sha256 -or
      [long]$targetFreeze.package.bytes -ne [long]$fixedRow[0].package.bytes -or [int]$targetFreeze.package.entries -ne [int]$fixedRow[0].package.entries -or
      [string]$targetFreeze.engine.version -ne [string]$profileRow[0].exact_engine -or [string]$targetFreeze.engine.binary_sha256 -ne [string]$profileRow[0].exact_engine_sha256 -or
      [string]$targetFreeze.profile -ne [string]$profileRow[0].target_profile -or [string]$targetFreeze.adapter -ne [string]$profileRow[0].target_adapter -or
      (@($targetFreeze.upgrade_rows) -join "|") -ne (@($profileRow[0].upgrade_rows) -join "|") -or
      [bool]$targetFreeze.boundaries.candidate_assigned -or [bool]$targetFreeze.boundaries.candidate_built -or
      [bool]$targetFreeze.boundaries.manual_review_complete -or [bool]$targetFreeze.boundaries.sealed -or
      [bool]$targetFreeze.boundaries.tagged -or [bool]$targetFreeze.boundaries.published) {
    throw "Terminal target source-freeze packet disagrees with fixed-point/profile authority: $release"
  }
  if ((& git -C $RepoRoot rev-parse "$($targetFreeze.shadow_source.commit)^{tree}").Trim() -ne [string]$targetFreeze.shadow_source.tree) {
    throw "Terminal target source-freeze commit/tree binding is invalid: $release"
  }
  foreach ($predecessor in @($targetFreeze.predecessors)) {
    if ((& git -C $RepoRoot rev-parse "$($predecessor.tag)^{commit}").Trim() -ne [string]$predecessor.commit) {
      throw "Terminal target source-freeze predecessor tag moved: $release/$($predecessor.role)"
    }
  }
}
foreach ($root in @($fixedPointReceipt.authority_roots)) {
  $rootPath = Join-Path $RepoRoot ([string]$root.path)
  if (-not (Test-Path -LiteralPath $rootPath -PathType Leaf)) {
    throw "Terminal fixed-point receipt authority root drifted: $($root.path)"
  }
  $rootText = [IO.File]::ReadAllText($rootPath).Replace("`r`n", "`n").Replace("`r", "`n")
  $rootHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($rootText)))
  if ($rootHash -ne [string]$root.canonical_text_sha256) { throw "Terminal fixed-point receipt authority root drifted: $($root.path)" }
}
$expectedFixedPointPackages = @{
  "3.2.9" = "0E833FCDDA3017641CA99D0EBD2FA226938A1CEE91D2EBB4007E94B29787AE20"
  "2.5.9" = "B5EF300A12F1DE7F130ADAE8A2D368CD879D56FE7141879A807698F9B0EBBF35"
  "1.9.9" = "E250F85BE20DE647112F7D2F96209CEA00774AEE7DCADE262291F1123B2F6843"
  "1.8.9" = "F9A7C245A12763362FB4A838FD9560C3AFE29FE0166E7E575617A26CB7F8B51A"
  "1.7.9" = "B6BDCD54C5952F986155ED4D78D92E109E90AD38D2CA9EC609034A848152CA2C"
  "1.6.9" = "928916C96C500AD1441455563F0559EF330A4814DD6C9630ADA9E9B698248B84"
  "1.5.9" = "85255CB5E8F8B482387454C92A16660276009E0A5D301FBDE38BF8944F72E24E"
  "1.4.9" = "1E3651E59656CE5258EC4F5FEFEA05883D577151E0BC8465342547D92CBAC872"
  "1.3.9" = "CF540E5ED6902BC0B97F0AC98D17875001B286183647C604CB065A8078B1AD5A"
}
$projectionProfiles = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\terminal\MIR3-Terminal-Shadow-ProjectionProfilesV1.json") | ConvertFrom-Json -Depth 100
foreach ($target in @($fixedPointReceipt.shadow_trees)) {
  $profile = @($projectionProfiles.targets | Where-Object release -eq ([string]$target.release))
  if ($profile.Count -ne 1 -or [string]$target.engine.version -ne [string]$profile[0].exact_engine -or
      [string]$target.engine.sha256 -ne [string]$profile[0].exact_engine_sha256 -or
      [string]$target.package.archive_sha256 -ne [string]$expectedFixedPointPackages[[string]$target.release] -or
      -not [bool]$target.source.remote_exact) {
    throw "Terminal fixed-point target authority is inconsistent: $($target.release)"
  }
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
    [string]$protection.status -ne "applied-and-verified" -or
    [string]$protection.application_receipt.status -ne "applied-and-verified" -or
    @($protection.application_receipt.canary_ruleset_ids).Count -ne 2 -or
    @($protection.application_receipt.production_ruleset_ids).Count -ne 9 -or
    @($protection.application_receipt.production_ruleset_ids | Sort-Object -Unique).Count -ne 9 -or
    [string]$protection.application_receipt.applied_by.login -ne "Julesc013" -or
    [int]$protection.application_receipt.applied_by.actor_id -ne 30209022 -or
    @($protection.application_receipt.negative_tests).Count -lt 8 -or
    (@($protection.immutable_dot5_tags) -join "|") -ne ($dot5Tags -join "|") -or
    (@($protection.future_terminal_tags) -join "|") -ne ($dot9Tags -join "|") -or
    @($protection.observed_required_checks | Where-Object { $_.context -notin $checkNames -or [int]$_.integration_id -ne 15368 -or $_.conclusion -ne "success" }).Count -ne 0 -or
    @($protection.branches | Where-Object { $_.ref -in @("refs/heads/main", "refs/heads/legacy") -and $_.required_pull_request }).Count -ne 0) {
  throw "Terminal protection handoff is incomplete, overclaims application, or contradicts promotion topology."
}
foreach ($field in @("applied_at", "verified_at")) {
  try { $null = [DateTimeOffset]::Parse([string]$protection.application_receipt.$field, [Globalization.CultureInfo]::InvariantCulture) }
  catch { throw "Terminal protection application receipt has a noncanonical $field timestamp." }
}
$protectionReceiptRelative = ([string]$protection.application_receipt.path).Replace("\", "/")
$protectionManifestRelative = ([string]$protection.application_receipt.evidence_manifest_path).Replace("\", "/")
foreach ($relative in @($protectionReceiptRelative, $protectionManifestRelative)) {
  if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains("..") -or $relative.Contains(":")) {
    throw "Terminal protection evidence path is not portable: $relative"
  }
}
$protectionReceiptPath = Join-Path $RepoRoot $protectionReceiptRelative
$protectionManifestPath = Join-Path $RepoRoot $protectionManifestRelative
if (-not (Test-Path -LiteralPath $protectionReceiptPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $protectionManifestPath -PathType Leaf) -or
    (Get-FileHash -LiteralPath $protectionReceiptPath -Algorithm SHA256).Hash -ne [string]$protection.application_receipt.sha256 -or
    (Get-FileHash -LiteralPath $protectionManifestPath -Algorithm SHA256).Hash -ne [string]$protection.application_receipt.evidence_manifest_sha256) {
  throw "Terminal protection application receipt or evidence manifest is absent or stale."
}
$protectionApplication = Get-Content -Raw -LiteralPath $protectionReceiptPath | ConvertFrom-Json -Depth 100
$protectionEvidence = Get-Content -Raw -LiteralPath $protectionManifestPath | ConvertFrom-Json -Depth 100
if ([string]$protectionApplication.kind -ne "MIR3TerminalProtectionApplicationReceiptV1" -or
    [string]$protectionApplication.status -ne "applied-and-verified" -or
    [string]$protectionApplication.repository -ne [string]$protection.repository -or
    @($protectionApplication.production_rulesets).Count -ne 9 -or
    @($protectionApplication.production_rulesets | Where-Object enforcement -ne "active").Count -ne 0 -or
    (@($protectionApplication.production_rulesets.id) -join "|") -ne (@($protection.application_receipt.production_ruleset_ids) -join "|") -or
    @($protectionApplication.required_checks | Where-Object { $_.context -notin $checkNames -or [int]$_.integration_id -ne 15368 }).Count -ne 0 -or
    -not [bool]$protectionApplication.canary.rulesets_removed -or -not [bool]$protectionApplication.canary.refs_removed -or
    @($protectionApplication.canary.negative_tests | Where-Object result -ne "rejected-http-422").Count -ne 0 -or
    [string]$protectionEvidence.kind -ne "MIR3TerminalProtectionEvidenceManifestV1" -or
    @($protectionEvidence.artifacts).Count -lt 20) {
  throw "Terminal protection application evidence does not bind the exact live applied state."
}
foreach ($artifact in @($protectionEvidence.artifacts)) {
  $relative = ([string]$artifact.path).Replace("\", "/")
  if ([IO.Path]::IsPathRooted($relative) -or $relative.Contains("..") -or $relative.Contains(":")) {
    throw "Terminal protection artifact path is not portable: $relative"
  }
  $artifactPath = Join-Path $RepoRoot $relative
  if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash -ne [string]$artifact.sha256 -or
      (Get-Item -LiteralPath $artifactPath).Length -ne [long]$artifact.bytes) {
    throw "Terminal protection artifact is absent or stale: $relative"
  }
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
$schemaNames = @("mir3-terminal-package-manifest", "mir3-terminal-release-manifest", "mir3-terminal-shadow-projection-profiles", "mir3-terminal-publication-receipt", "mir3-terminal-engine-observation", "mir3-terminal-finding", "mir3-terminal-experiment-receipt", "mir3-terminal-assurance-calibration-receipt", "mir3-terminal-baseline-bundle-manifest", "mir3-terminal-dot5-semantic-matrix", "mir3-terminal-qualification-record", "mir3-terminal-target-seal", "mir3-terminal-fixed-point-receipt", "mir3-terminal-family-readiness", "mir3-final-index", "mir3-eol-record", "mir3-terminal-authority", "mir3-museum-index", "mir3-terminal-018-feasibility-gate", "mir3-terminal-successor-bootstrap-policy", "mir3-settings-scope-audit", "mir3-mod-portal-compatibility-census", "mir3-mod-portal-discussion-reconciliation", "mir3-mod-interaction-matrix", "mir3-compatibility-claims", "mir3-effective-mutation-owner-report", "mir3-dot5-mod-portal-custody-recheck", "mir3-final-defect-index", "mir3-engine-gap-audit", "mir3-terminal-product-admission-bundle") + $baselineSchemaNames
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
$experimentReceiptPath = Join-Path $RepoRoot ".mir\releases\terminal\experiments\MIR3-TERM-0012-a1ceee06.json"
$experimentReceipt = Get-Content -Raw -LiteralPath $experimentReceiptPath | ConvertFrom-Json -Depth 100
if ([string]$programme.authorities.experiments -ne ".mir/releases/terminal/experiments" -or
    [int]$experimentReceipt.schema -ne 1 -or [string]$experimentReceipt.kind -ne "MIR3TerminalExperimentReceiptV1" -or
    [string]$experimentReceipt.finding -ne "MIR3-TERM-0012" -or [string]$experimentReceipt.authority_class -ne "reproduced-experiment" -or
    [string]$experimentReceipt.experiment.commit -ne "a1ceee060c4f0abd0a9fdd203564df4e9f081d98" -or
    [string]$experimentReceipt.experiment.merge_base -ne "1abe07573cde814c3cacf6153b5ae64dee4038ba" -or
    [int]$experimentReceipt.experiment.dev_ahead -ne 181 -or [int]$experimentReceipt.experiment.experiment_ahead -ne 351 -or
    $experimentReceipt.integration.merge_allowed -or $experimentReceipt.integration.cherry_pick_allowed -or -not $experimentReceipt.canonical_port.required -or
    [string]$experimentReceipt.canonical_port.final_evidence_status -ne "diagnostic-only-until-repeated-under-current-canonical-implementation" -or
    @($experimentReceipt.evidence.archived_artifacts).Count -ne 2) {
  throw "The divergent 2.5.5 calibration experiment is not correctly bounded as diagnostic-only non-integrable evidence."
}
foreach ($artifact in @($experimentReceipt.evidence.archived_artifacts)) {
  $artifactPath = Join-Path $RepoRoot ([string]$artifact.path)
  if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash -ne [string]$artifact.sha256) {
    throw "Terminal experiment artifact is absent or differs from its archived diagnostic identity: $($artifact.path)"
  }
}
$attributes = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".gitattributes")
if ($attributes -notmatch '(?m)^\.mir/evidence/archive/mir3-term-experiments/\*\*/\*\.json -text\r?$') {
  throw "Terminal experiment artifacts must retain exact checkout bytes for their raw archived SHA-256 identities."
}
$historicalReviewCustodyPath = Join-Path $RepoRoot ".mir\evidence\2.5.5-manual-review-custody.json"
$historicalReviewCustody = Get-Content -Raw -LiteralPath $historicalReviewCustodyPath | ConvertFrom-Json -Depth 100
$historicalReviewPath = Join-Path $RepoRoot ([string]$historicalReviewCustody.attestation.path)
$historicalReviewObjectPath = Join-Path $RepoRoot ([string]$historicalReviewCustody.object.path)
if ($attributes -notmatch '(?m)^\.mir/evidence/2\.5\.5-manual-review-attestation\.json -text\r?$' -or
    (Get-FileHash -LiteralPath $historicalReviewPath -Algorithm SHA256).Hash -ne [string]$historicalReviewCustody.attestation.sha256 -or
    (Get-FileHash -LiteralPath $historicalReviewObjectPath -Algorithm SHA256).Hash -ne [string]$historicalReviewCustody.object.sha256) {
  throw "Historical 2.5.5 manual-review custody must retain the exact attestation and content-addressed object bytes."
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
if (($current.planned_releases -join "|") -ne ($family -join "|") -or -not $current.implementation_admitted -or -not $current.source_frozen -or
    $current.roles.latest_published_factorio_2_1 -ne "3.2.5" -or $current.roles.latest_published_factorio_2_0 -ne "2.5.5" -or
    $current.roles.canonical -ne "3.2.9" -or $current.roles.backport_calibration -ne "2.5.5" -or
    $current.roles.planned_canonical -ne "3.2.9" -or $current.roles.planned_backport -ne "2.5.9" -or
    $current.active_programme.id -ne "MIR3-Terminal-ProgrammeV1" -or $current.active_programme.status -ne "source-frozen-ready-for-candidate-allocation") {
  throw "Current release roles do not distinguish published .5 from source-frozen, candidate-unassigned .9."
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
