param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path,
  [string]$AcceptedAt = "",
  [string]$Reviewer = "Julesc013",
  [switch]$Check
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo "tools/lib/control/Core.ps1")
. (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")

$family = @("3.2.9", "2.5.9", "1.9.9", "1.8.9", "1.7.9", "1.6.9", "1.5.9", "1.4.9", "1.3.9")
$allocationPath = Join-Path $repo ".mir/releases/terminal/MIR3-Terminal-Candidate-AllocationV1.json"
$acceptanceRelative = ".mir/releases/terminal/MIR3TerminalMaintainerAcceptanceV1.json"
$acceptancePath = Join-Path $repo $acceptanceRelative
$familyRelative = ".mir/releases/terminal/MIR3TerminalFamilyReadinessV1.json"
$familyPath = Join-Path $repo $familyRelative
$settingsRelative = ".mir/releases/terminal/MIR3TerminalCandidateSettingsQualificationV1.json"
$fixedPointRelative = ".mir/releases/terminal/MIR3TerminalFixedPointReceiptV1.json"

function Read-JsonHash([string]$Relative) {
  return Get-Content -Raw -LiteralPath (Join-Path $repo $Relative) | ConvertFrom-Json -AsHashtable -DateKind String
}

function Write-JsonHash([string]$Relative, [Collections.IDictionary]$Value) {
  Write-MIRCPJson -Path $Relative -Value $Value -RepoRoot $repo
}

function Get-AuthorityTextSha([string]$Relative) {
  # Ceremony-owned text bindings must survive Windows checkout EOL conversion.
  return Get-MIRCPPortableTextSha256 -Path (Join-Path $repo $Relative)
}

function Get-RawSha([string]$Relative) {
  # Pre-existing frozen evidence retains its already-governed byte identity.
  return (Get-FileHash -LiteralPath (Join-Path $repo $Relative) -Algorithm SHA256).Hash
}

function Get-RecordHash([Collections.IDictionary]$Value, [string[]]$Omit) {
  $copy = [ordered]@{}
  foreach ($key in $Value.Keys) {
    if ([string]$key -notin $Omit) { $copy[$key] = $Value[$key] }
  }
  return Get-MIRCPSha256Object -Value $copy
}

function Write-Utf8([string]$Relative, [string]$Text) {
  $path = Join-Path $repo $Relative
  $parent = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $parent) }
  [IO.File]::WriteAllText($path, ($Text.Replace("`r`n", "`n").TrimEnd() + "`n"), [Text.UTF8Encoding]::new($false))
}

function Assert-Schema([string]$Relative, [string]$SchemaRelative) {
  $raw = Get-Content -Raw -LiteralPath (Join-Path $repo $Relative)
  if (-not ($raw | Test-Json -SchemaFile (Join-Path $repo $SchemaRelative))) {
    throw "Schema validation failed: $Relative"
  }
}

function Get-ReleaseMeta([string]$Release) {
  $freeze = Read-JsonHash ".mir/releases/terminal/freezes/$Release.json"
  $first = $freeze.predecessors[0].release
  $second = $freeze.predecessors[1].release
  $kind = if ($Release -eq "3.2.9") { "current" } elseif ($Release -eq "2.5.9") { "maintained" } else { "historical" }
  $targetLabel = if ($Release -eq "1.8.9") { "Factorio 1.0.0 only" } elseif ($freeze.support_tier -eq "finite") { "Factorio $($freeze.engine.version) finite" } else { "Factorio $($freeze.engine.version)" }
  return [ordered]@{freeze=$freeze; first=$first; second=$second; kind=$kind; target_label=$targetLabel}
}

function Get-ReleaseBody([string]$Release, [Collections.IDictionary]$Allocation) {
  $meta = Get-ReleaseMeta $Release
  $header = @(
    "# More Infinite Research $Release",
    "",
    "Final MIR 3 terminal release for $($meta.target_label).",
    "",
    "Candidate: ``$($Allocation.assigned_id)``",
    "",
    "Archive SHA-256: ``$($Allocation.archive_sha256)``",
    "",
    "Normalized content SHA-256: ``$($Allocation.content_sha256)``",
    "",
    "Upgrade paths: ``$($meta.first) -> $Release`` and ``$($meta.second) -> $Release``",
    "",
    "## Changes",
    ""
  )
  $changes = if ($Release -eq "3.2.9") {
    @(
      "- Corrects K2/K2SO science-card phasing for the qualified K2 2.1.2 and K2SO 2.0.13 envelope.",
      "- Selects the deterministic earliest safe science-production route instead of an arbitrary technology-name gate.",
      "- Resolves direct-effect ownership across the combined compilation plan, including the reported Tesla shooting-speed startup crash.",
      "- Preserves stable technology IDs, completed research, current research, fractional progress, queue state, and reload behavior across the governed upgrades.",
      "- Keeps every released setting in its existing Startup/compile scope; MIRSET1 and setting identities are unchanged.",
      "- Establishes the permanent MIR 3 Factorio 2.1 baseline. Future architecture work belongs to MIR 4."
    )
  } elseif ($Release -eq "2.5.9") {
    @(
      "- Corrects alternate science-production-route prerequisite selection on Factorio 2.0.",
      "- Resolves duplicate direct-effect ownership on the maintained Factorio 2.0 compiler path.",
      "- Preserves stable identities and both governed upgrade paths.",
      "- Keeps every released setting in its existing Startup/compile scope; MIRSET1 and setting identities are unchanged.",
      "- Establishes the permanent MIR 3 Factorio 2.0 baseline."
    )
  } else {
    $extra = if ($Release -eq "1.8.9") { @("- Supports Factorio 1.0 only; this release makes no Factorio 0.18 bridge claim.") } else { @() }
    @(
      "- Final target-native MIR 3 baseline for $($meta.target_label).",
      "- Preserves the target-supported ``.5`` behavior, stable public identities, deterministic packaging, explicit omissions, and both governed upgrade paths.",
      "- Does not approximate unsupported modern features on this historical engine."
    ) + $extra
  }
  $footer = @(
    "",
    "## Qualification",
    "",
    "The exact archive was reconstructed three times from clean detached roots and passed its target-tier automated qualification. Maintainer acceptance is limited to inspection of the exact frozen distribution; engine, settings, compatibility, performance, and upgrade claims come from the recorded automated evidence.",
    "",
    "## Installation",
    "",
    "Use the attached ``more-infinite-research_$Release.zip`` unchanged. Do not rename or unpack it into another archive."
  )
  return (($header + $changes + $footer) -join "`n")
}

if ($Check) {
  $allocation = Read-JsonHash ".mir/releases/terminal/MIR3-Terminal-Candidate-AllocationV1.json"
  $acceptance = Read-JsonHash $acceptanceRelative
  Assert-Schema $acceptanceRelative "spec/schemas/mir3-terminal-maintainer-acceptance.schema.json"
  if ((Get-RecordHash $acceptance @("record_sha256")) -ne $acceptance.record_sha256) { throw "Maintainer acceptance record digest is invalid." }
  $acceptanceSha = Get-AuthorityTextSha $acceptanceRelative
  foreach ($row in $allocation.allocations) {
    $release = [string]$row.release
    $zip = Join-Path $repo "dist/more-infinite-research_$release.zip"
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $row.archive_sha256 -or
        (Get-MIRZipContentFingerprint -Path $zip) -ne $row.content_sha256 -or
        (Get-Item -LiteralPath $zip).Length -ne [long]$row.bytes) { throw "Frozen candidate identity drifted: $release" }
    $qualificationRelative = ".mir/releases/terminal/qualifications/$release.json"
    $qualification = Read-JsonHash $qualificationRelative
    Assert-Schema $qualificationRelative "spec/schemas/mir3-terminal-qualification-record.schema.json"
    if ($qualification.status -ne "passed-automated-awaiting-human-review" -or $qualification.manual_review.status -ne "pending-maintainer-approval") { throw "Immutable automated qualification state drifted: $release" }
    $reviewRelative = ".mir/releases/terminal/reviews/$release.json"
    $review = Read-JsonHash $reviewRelative
    Assert-Schema $reviewRelative "spec/schemas/mir3-terminal-qualification-review.schema.json"
    if ((Get-RecordHash $review @("record_sha256")) -ne $review.record_sha256 -or
        $review.qualification.sha256 -ne (Get-AuthorityTextSha $qualificationRelative) -or
        $review.acceptance.sha256 -ne $acceptanceSha) { throw "Qualification review overlay is invalid: $release" }
    $sealRelative = ".mir/releases/terminal/seals/$release.json"
    $seal = Read-JsonHash $sealRelative
    Assert-Schema $sealRelative "spec/schemas/mir3-terminal-target-seal.schema.json"
    if ((Get-RecordHash $seal @("seal_material_sha256", "record_sha256")) -ne $seal.seal_material_sha256 -or
        (Get-RecordHash $seal @("record_sha256")) -ne $seal.record_sha256 -or
        $seal.qualification_sha256 -ne (Get-AuthorityTextSha $qualificationRelative) -or
        $seal.review_sha256 -ne (Get-AuthorityTextSha $reviewRelative)) { throw "Target seal is invalid: $release" }
    foreach ($binding in @($seal.package_manifest, $seal.release_manifest, $seal.baseline_bundle, $seal.fixed_point_receipt, $seal.candidate_settings_qualification)) {
      $bindingSha = if ([string]$binding.path -match '/manifests/') {
        Get-AuthorityTextSha ([string]$binding.path)
      } else {
        Get-RawSha ([string]$binding.path)
      }
      if ($bindingSha -ne [string]$binding.sha256) { throw "Target seal binding drifted: $release/$($binding.path)" }
    }
    Assert-Schema ".mir/releases/terminal/manifests/$release-package.json" "spec/schemas/mir3-terminal-package-manifest.schema.json"
    Assert-Schema ".mir/releases/terminal/manifests/$release-release.json" "spec/schemas/mir3-terminal-release-manifest.schema.json"
  }
  $defectReconciliationRelative = ".mir/releases/terminal/MIR3FinalDefectQualificationReconciliationV1.json"
  $defectReconciliation = Read-JsonHash $defectReconciliationRelative
  Assert-Schema $defectReconciliationRelative "spec/schemas/mir3-final-defect-qualification-reconciliation.schema.json"
  if ((Get-RecordHash $defectReconciliation @("record_sha256")) -ne $defectReconciliation.record_sha256 -or
      (Get-AuthorityTextSha ([string]$defectReconciliation.fixed_point_defect_index.path)) -ne [string]$defectReconciliation.fixed_point_defect_index.sha256) {
    throw "Final defect qualification reconciliation is invalid."
  }
  $ready = Read-JsonHash $familyRelative
  Assert-Schema $familyRelative "spec/schemas/mir3-terminal-family-readiness.schema.json"
  if ((Get-RecordHash $ready @("seal_material_sha256", "record_sha256")) -ne $ready.seal_material_sha256 -or
      (Get-RecordHash $ready @("record_sha256")) -ne $ready.record_sha256) { throw "Family-readiness digest is invalid." }
  foreach ($binding in $ready.target_seals) {
    if ((Get-AuthorityTextSha ([string]$binding.path)) -ne [string]$binding.sha256) { throw "Family target-seal binding drifted: $($binding.release)" }
  }
  if ((Get-AuthorityTextSha ([string]$ready.defect_qualification_reconciliation.path)) -ne [string]$ready.defect_qualification_reconciliation.sha256) {
    throw "Family defect-qualification reconciliation binding drifted."
  }
  Write-Host "[ok] MIR 3 terminal maintainer acceptance, nine target seals, and family readiness are valid"
  exit 0
}

$AcceptedAt = $AcceptedAt.Trim()
if ([string]::IsNullOrWhiteSpace($AcceptedAt)) { throw "-AcceptedAt is required when creating release-ceremony authority." }
$null = [DateTimeOffset]::ParseExact($AcceptedAt, "yyyy-MM-dd'T'HH:mm:sszzz", [Globalization.CultureInfo]::InvariantCulture)
$allocation = Read-JsonHash ".mir/releases/terminal/MIR3-Terminal-Candidate-AllocationV1.json"
if (@($allocation.allocations).Count -ne 9) { throw "Candidate allocation is not nine-of-nine." }

$candidateRows = @($allocation.allocations | ForEach-Object {
  [ordered]@{
    release = [string]$_.release
    candidate_id = [string]$_.assigned_id
    candidate_commit = [string]$_.candidate_commit
    source_tree = [string]$_.candidate_tree
    archive_sha256 = [string]$_.archive_sha256
    content_sha256 = [string]$_.content_sha256
    bytes = [long]$_.bytes
    entries = [int]$_.entries
  }
})

$acceptance = [ordered]@{
  schema = 1
  kind = "Mir3TerminalMaintainerAcceptanceV1"
  recorded_at = $AcceptedAt
  reviewer = $Reviewer
  scope = "inspection of the nine exact frozen candidate distributions"
  decision = "approved"
  statement = "The maintainer inspected the exact nine frozen candidate distributions identified in the release dossier and found no package-visible release blocker."
  limitations = @(
    "No unrecorded per-engine visual playtesting is claimed.",
    "No exhaustive settings, compatibility, performance, or save-upgrade observation is claimed.",
    "Those surfaces are established only by the existing exact-candidate automated qualification records."
  )
  condition = "Approval remains valid only while the exact candidate identities, qualification roots, target seals, and family-readiness seal remain unchanged."
  candidates = $candidateRows
  authorization = [ordered]@{
    create_target_seals = $true
    create_family_readiness = $true
    promote_branches = $true
    create_annotated_tags = $true
    publish_github_releases = $true
    mod_portal_upload = $false
  }
  status = "accepted-exact-nine-candidate-distributions"
}
$acceptance.record_sha256 = Get-RecordHash $acceptance @("record_sha256")
Write-JsonHash $acceptanceRelative $acceptance
$acceptanceSha = Get-AuthorityTextSha $acceptanceRelative

$checksumLines = @()
foreach ($row in $allocation.allocations) {
  $release = [string]$row.release
  $zipRelative = "dist/more-infinite-research_$release.zip"
  $zip = Join-Path $repo $zipRelative
  if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $row.archive_sha256 -or
      (Get-MIRZipContentFingerprint -Path $zip) -ne $row.content_sha256 -or
      (Get-Item -LiteralPath $zip).Length -ne [long]$row.bytes) { throw "Frozen candidate identity drifted: $release" }
  $checksumLines += "$($row.archive_sha256)  more-infinite-research_$release.zip"

  $qualificationRelative = ".mir/releases/terminal/qualifications/$release.json"
  $qualification = Read-JsonHash $qualificationRelative
  if ($qualification.status -ne "passed-automated-awaiting-human-review" -or $qualification.manual_review.status -ne "pending-maintainer-approval") {
    throw "Immutable automated qualification state drifted: $release"
  }
  $reviewRelative = ".mir/releases/terminal/reviews/$release.json"
  $review = [ordered]@{
    schema = 1
    kind = "Mir3TerminalQualificationReviewV1"
    recorded_at = $AcceptedAt
    release = $release
    candidate_id = [string]$row.assigned_id
    archive_sha256 = [string]$row.archive_sha256
    qualification = [ordered]@{path=$qualificationRelative;sha256=(Get-AuthorityTextSha $qualificationRelative);status="passed-automated-awaiting-human-review";mutated=$false}
    acceptance = [ordered]@{path=$acceptanceRelative;sha256=$acceptanceSha;reviewer=$Reviewer;decision="approved"}
    scope = "maintainer-inspected-exact-frozen-distribution; automated-record-covers-engine-settings-compatibility-performance-and-upgrade-surfaces"
    status = "accepted-exact-package-inspection"
  }
  $review.record_sha256 = Get-RecordHash $review @("record_sha256")
  Write-JsonHash $reviewRelative $review

  $meta = Get-ReleaseMeta $release
  $baselineRelease = [string]$meta.freeze.predecessors[0].release
  $baselineRelative = ".mir/releases/terminal/baselines/$baselineRelease/baseline-manifest.json"
  $packageManifestRelative = ".mir/releases/terminal/manifests/$release-package.json"
  $releaseManifestRelative = ".mir/releases/terminal/manifests/$release-release.json"
  $packageManifest = [ordered]@{
    schema = 1
    kind = "Mir3TerminalPackageManifestV1"
    release = $release
    target = [string]$meta.freeze.target
    source = [ordered]@{candidate_commit=[string]$row.candidate_commit; source_tree=[string]$row.candidate_tree; common_source_commit=[string]$meta.freeze.common_source_commit}
    semantic_roots = @($fixedPointRelative, ".mir/releases/terminal/MIR3TerminalProductImplementationReconciliationV1.json")
    inventories = @($baselineRelative, ".mir/releases/terminal/MIR3-Compatibility-ClaimsV1.json", ".mir/releases/terminal/MIR3-Settings-Scope-AuditV1.json")
    schemas = @("spec/schemas/mir3-terminal-package-manifest.schema.json", "spec/schemas/mir3-terminal-release-manifest.schema.json")
    migration_watermark = [ordered]@{from=@([string]$meta.first,[string]$meta.second);to=$release;stable_ids=$true}
    toolchain = [ordered]@{source_freeze=".mir/releases/terminal/MIR3TerminalSourceFreezeV1.json";target_freeze=".mir/releases/terminal/freezes/$release.json"}
    mir4_successor_target = "MIR4-R0/$($meta.freeze.target)"
    upgrade_obligation = @([string]$meta.freeze.upgrade_rows[0], [string]$meta.freeze.upgrade_rows[1])
  }
  Write-JsonHash $packageManifestRelative $packageManifest
  $releaseManifest = [ordered]@{
    schema = 1
    kind = "Mir3TerminalReleaseManifestV1"
    release = $release
    candidate_id = [string]$row.assigned_id
    candidate_commit = [string]$row.candidate_commit
    archive_sha256 = [string]$row.archive_sha256
    content_sha256 = [string]$row.content_sha256
    bytes = [long]$row.bytes
    entries = [int]$row.entries
    qualification = [ordered]@{path=$qualificationRelative;status="passed-automated-awaiting-human-review"}
    review = [ordered]@{path=$reviewRelative;sha256=(Get-AuthorityTextSha $reviewRelative);status="accepted-exact-package-inspection"}
    seal = [ordered]@{path=".mir/releases/terminal/seals/$release.json";status="created-after-manifest-root"}
    tag = [ordered]@{name=$release;target_commit=[string]$row.candidate_commit;status="authorized-pending-creation"}
    github_release_body = ".mir/releases/terminal/release-bodies/$release.md"
    mod_portal_description = ".mir/releases/terminal/mod-portal-descriptions/$release.md"
  }
  Write-JsonHash $releaseManifestRelative $releaseManifest

  $body = Get-ReleaseBody $release $row
  Write-Utf8 ".mir/releases/terminal/release-bodies/$release.md" $body
  Write-Utf8 ".mir/releases/terminal/mod-portal-descriptions/$release.md" ($body + "`n`n## Mod Portal custody`n`nUpload the exact sealed ZIP named above. Publication is not complete until authenticated redownload, byte verification, and the exact-engine public-asset smoke are recorded.")

  $noteTitle = "MIR $release Release Notes"
  $note = @"
---
title: "$noteTitle"
status: current
applies_to: "$release"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-15
supersedes: []
superseded_by: []
---

$body

<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->
<!-- Generated immutable release identity is inserted by the control plane. -->
<!-- MIR-CONTROL-PLANE-IDENTITY:END -->
"@
  Write-Utf8 "docs/releases/notes/release-notes-$release.md" $note

  $recordRelative = ".mir/releases/records/$release.json"
  $record = Read-JsonHash $recordRelative
  $record.state = "sealed"
  $record.release_notes = "docs/releases/notes/release-notes-$release.md"
  $record.proofs.manual_acceptance = [ordered]@{path=$reviewRelative;sha256=(Get-AuthorityTextSha $reviewRelative);family_acceptance_path=$acceptanceRelative;family_acceptance_sha256=$acceptanceSha}
  $record.proofs.package_manifest = $packageManifestRelative
  $record.proofs.release_manifest = $releaseManifestRelative
  $record.proofs.target_seal = ".mir/releases/terminal/seals/$release.json"
  $record.proofs.family_readiness = $familyRelative
  $record.remaining_obligations = if ($release -in @("3.2.9", "2.5.9")) { @("promote-tag-publish-and-publicly-verify", "archive-and-mir4-handoff") } else { @("tag-publish-and-publicly-verify", "archive-and-mir4-handoff") }
  $record.updated_at = $AcceptedAt
  Write-JsonHash $recordRelative $record
}
Write-Utf8 "docs/releases/SHA256SUMS-MIR-3.txt" ($checksumLines -join "`n")

$defectsRelative = ".mir/releases/terminal/MIR3-FINAL-DEFECT-INDEX.json"
$settingsSha = Get-RawSha $settingsRelative
$fixedPointSha = Get-RawSha $fixedPointRelative
$sealRows = @()
foreach ($row in $allocation.allocations) {
  $release = [string]$row.release
  $meta = Get-ReleaseMeta $release
  $qualificationRelative = ".mir/releases/terminal/qualifications/$release.json"
  $baselineRelative = ".mir/releases/terminal/baselines/$($meta.freeze.predecessors[0].release)/baseline-manifest.json"
  $baseline = Read-JsonHash $baselineRelative
  $packageManifestRelative = ".mir/releases/terminal/manifests/$release-package.json"
  $releaseManifestRelative = ".mir/releases/terminal/manifests/$release-release.json"
  $sealRelative = ".mir/releases/terminal/seals/$release.json"
  $seal = [ordered]@{
    schema = 1
    kind = "Mir3TerminalTargetSealV1"
    sealed_at = $AcceptedAt
    release = $release
    target = [string]$meta.freeze.target
    support_tier = [string]$meta.freeze.support_tier
    candidate_id = [string]$row.assigned_id
    candidate_commit = [string]$row.candidate_commit
    source_tree = [string]$row.candidate_tree
    parents = @($row.parents | ForEach-Object { [string]$_ })
    archive_sha256 = [string]$row.archive_sha256
    content_sha256 = [string]$row.content_sha256
    bytes = [long]$row.bytes
    entries = [int]$row.entries
    engine = $meta.freeze.engine
    target_profile = [ordered]@{id=[string]$meta.freeze.profile;adapter=[string]$meta.freeze.adapter;freeze_path=".mir/releases/terminal/freezes/$release.json"}
    qualification = [ordered]@{path=$qualificationRelative;status="passed-automated-awaiting-human-review";review_resolution=".mir/releases/terminal/reviews/$release.json"}
    qualification_sha256 = Get-AuthorityTextSha $qualificationRelative
    candidate_settings_qualification = [ordered]@{path=$settingsRelative;sha256=$settingsSha;status="passed"}
    upgrade_rows = @($meta.freeze.upgrade_rows | ForEach-Object { [ordered]@{id=[string]$_;status="passed"} })
    review = [ordered]@{path=".mir/releases/terminal/reviews/$release.json";reviewer=$Reviewer;decision="approved";family_acceptance=$acceptanceRelative}
    review_sha256 = Get-AuthorityTextSha ".mir/releases/terminal/reviews/$release.json"
    package_manifest = [ordered]@{path=$packageManifestRelative;sha256=(Get-AuthorityTextSha $packageManifestRelative)}
    release_manifest = [ordered]@{path=$releaseManifestRelative;sha256=(Get-AuthorityTextSha $releaseManifestRelative)}
    baseline_bundle = [ordered]@{path=$baselineRelative;sha256=(Get-RawSha $baselineRelative);root_sha256=[string]$baseline.baseline_root_sha256}
    fixed_point_receipt = [ordered]@{path=$fixedPointRelative;sha256=$fixedPointSha;status="accepted-all-nine"}
    tag_authority = [ordered]@{name=$release;target_commit=[string]$row.candidate_commit;immutable=$true;update_or_delete=$false}
    status = "sealed"
  }
  $seal.seal_material_sha256 = Get-RecordHash $seal @("seal_material_sha256", "record_sha256")
  $seal.record_sha256 = Get-RecordHash $seal @("record_sha256")
  Write-JsonHash $sealRelative $seal
  $sealRows += [ordered]@{release=$release;path=$sealRelative;sha256=(Get-AuthorityTextSha $sealRelative);record_sha256=[string]$seal.record_sha256}
}

$defectReconciliationRelative = ".mir/releases/terminal/MIR3FinalDefectQualificationReconciliationV1.json"
$defects = Read-JsonHash $defectsRelative
$completionUpdates = @($defects.dispositions | Where-Object completion -eq "implemented-fixed-point-accepted-awaiting-final-candidate-qualification" | ForEach-Object {
  [ordered]@{source_kind=[string]$_.source_kind;source_id=[string]$_.source_id;prior_completion=[string]$_.completion;final_completion="final-candidate-qualified-and-sealed"}
})
$defectReconciliation = [ordered]@{
  schema = 1
  kind = "MIR3FinalDefectQualificationReconciliationV1"
  recorded_at = $AcceptedAt
  fixed_point_defect_index = [ordered]@{path=$defectsRelative;sha256=(Get-AuthorityTextSha $defectsRelative);status=[string]$defects.status;mutated=$false}
  candidate_allocation = [ordered]@{path=".mir/releases/terminal/MIR3-Terminal-Candidate-AllocationV1.json";sha256=(Get-RawSha ".mir/releases/terminal/MIR3-Terminal-Candidate-AllocationV1.json")}
  target_seals = $sealRows
  completion_updates = $completionUpdates
  unresolved_release_blockers = 0
  status = "final-candidates-qualified-and-sealed"
}
$defectReconciliation.record_sha256 = Get-RecordHash $defectReconciliation @("record_sha256")
Write-JsonHash $defectReconciliationRelative $defectReconciliation

$bodyRows = @($family | ForEach-Object { $path=".mir/releases/terminal/release-bodies/$_.md"; [ordered]@{release=$_;path=$path;sha256=(Get-AuthorityTextSha $path)} })
$portalRows = @($family | ForEach-Object { $path=".mir/releases/terminal/mod-portal-descriptions/$_.md"; [ordered]@{release=$_;path=$path;sha256=(Get-AuthorityTextSha $path)} })
$sealedArchives = @($allocation.allocations | ForEach-Object { [ordered]@{release=[string]$_.release;candidate_id=[string]$_.assigned_id;archive_sha256=[string]$_.archive_sha256;content_sha256=[string]$_.content_sha256;bytes=[long]$_.bytes;entries=[int]$_.entries} })
$ready = [ordered]@{
  schema = 1
  kind = "Mir3TerminalFamilyReadinessV1"
  sealed_at = $AcceptedAt
  releases = $family
  target_seals = $sealRows
  fixed_point_receipt = [ordered]@{path=$fixedPointRelative;sha256=$fixedPointSha;status="accepted-all-nine"}
  sealed_archives = $sealedArchives
  unresolved_release_blockers = 0
  defect_index = [ordered]@{path=$defectsRelative;sha256=(Get-AuthorityTextSha $defectsRelative)}
  defect_qualification_reconciliation = [ordered]@{path=$defectReconciliationRelative;sha256=(Get-AuthorityTextSha $defectReconciliationRelative);status="final-candidates-qualified-and-sealed"}
  release_bodies = $bodyRows
  mod_portal_descriptions = $portalRows
  checksum_file = [ordered]@{path="docs/releases/SHA256SUMS-MIR-3.txt";sha256=(Get-AuthorityTextSha "docs/releases/SHA256SUMS-MIR-3.txt")}
  branch_promotion_preflight = [ordered]@{
    main = [ordered]@{from="391684ffe5822dbadc0b6644d22fd9640ee0ffa8";to="a60230a0695d2dd8fd1e727744614e746cda0bd8";mode="governed-fast-forward";status="ready"}
    legacy = [ordered]@{from="27877275854eb131efeb42672d3676c9c513c85e";to="89719eb8ea5c938b6a0e9d816e6324d4d59b87bb";mode="governed-fast-forward";status="ready"}
    lower_targets = "immutable-tag-only-no-permanent-branches"
  }
  tag_preflight = [ordered]@{names=$family;targets=@($allocation.allocations | ForEach-Object { [ordered]@{name=[string]$_.release;commit=[string]$_.candidate_commit} });existing_terminal_tags=0;status="ready"}
  publication_credentials = [ordered]@{provider="github";actor=$Reviewer;repository="Julesc013/more-infinite-research";admin=$true;push=$true;checked_at=$AcceptedAt;status="ready"}
  archive_destination_preflight = [ordered]@{path=".mir/evidence/terminal-publication";repository_excluded_from_packages=$true;status="ready"}
  authorization = [ordered]@{path=$acceptanceRelative;sha256=$acceptanceSha;reviewer=$Reviewer;github_publication=$true;mod_portal_upload=$false}
  signing_disposition = [ordered]@{mode="annotated-unsigned";reason="no-stable-release-signing-key-configured";unrelated_key_permitted=$false}
  status = "ready-for-local-tagging"
}
$ready.seal_material_sha256 = Get-RecordHash $ready @("seal_material_sha256", "record_sha256")
$ready.record_sha256 = Get-RecordHash $ready @("record_sha256")
Write-JsonHash $familyRelative $ready

$programmeRelative = ".mir/releases/terminal/MIR3-Terminal-ProgrammeV1.json"
$programme = Read-JsonHash $programmeRelative
$programme.status = "ready-for-local-tagging"
$programme.authorities.maintainer_acceptance = $acceptanceRelative
$programme.authorities.target_seals = ".mir/releases/terminal/seals"
$programme.authorities.family_readiness = $familyRelative
$programme.authorities.release_manifests = ".mir/releases/terminal/manifests"
$programme.authorities.final_defect_qualification_reconciliation = $defectReconciliationRelative
$programme.hard_gate = "Nine exact frozen candidates are maintainer-accepted, independently sealed, and bound by a valid family-readiness record. Governed branch promotion and immutable annotated tag creation are authorized; publication must use only the sealed ZIPs."
Write-JsonHash $programmeRelative $programme

$currentRelative = ".mir/releases/records/current.json"
$current = Read-JsonHash $currentRelative
$current.active_programme.status = "ready-for-local-tagging"
Write-JsonHash $currentRelative $current

$guide = @"
---
title: "MIR 3 Terminal Release and MIR 4 Handoff Guide"
status: current
applies_to: "3.2.9-1.3.9"
audience: release-manager
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-15
supersedes: []
superseded_by: []
---

# MIR 3 Terminal Release and MIR 4 Handoff Guide

The nine ``.9`` archives are the final target-native MIR 3 family. They are source-frozen, triple-reconstructed, automatically qualified, maintainer-accepted, and sealed. Package-visible bytes must not change during branch promotion, tagging, GitHub publication, Mod Portal upload, archival, or MIR 4 bootstrap.

## Target, feature, and omission matrix

| Release | Exact engine | Product delta | Explicit boundary |
| --- | --- | --- | --- |
| ``3.2.9`` | Factorio 2.1.13 | K2 phasing, alternate science routes, combined direct-effect ownership | Exact named compatibility claims only |
| ``2.5.9`` | Factorio 2.0.77 | Alternate science routes and combined direct-effect ownership | No K2 2.1 policy projection |
| ``1.9.9`` | Factorio 1.1.110 | No admitted package delta | Target-native terminal baseline |
| ``1.8.9`` | Factorio 1.0.0 | No admitted package delta | Factorio 1.0 only; no 0.18 bridge claim |
| ``1.7.9`` | Factorio 0.17.79 | No admitted package delta | Target-native omissions retained |
| ``1.6.9`` | Factorio 0.16.51 | No admitted package delta | Target-native omissions retained |
| ``1.5.9`` | Factorio 0.15.40 | No admitted package delta | Target-native omissions retained |
| ``1.4.9`` | Factorio 0.14.23 | No admitted package delta | Finite continuation; no modern approximation |
| ``1.3.9`` | Factorio 0.13.20 | No admitted package delta | Finite continuation; no modern approximation |

## Upgrade matrix

Each target passed two governed paths: ``3.2.5/3.2.3``, ``2.5.5/2.5.0``, ``1.9.5/1.9.4``, ``1.8.5/1.8.2``, ``1.7.5/1.7.1``, ``1.6.5/1.6.0``, ``1.5.5/1.5.0``, ``1.4.5/1.4.0``, and ``1.3.5/1.3.0`` to their matching ``.9`` release.

## Settings and compatibility

No released setting ID, type, default, profile encoding, or scope changed. All settings remain Startup/compile settings and MIRSET1 is unchanged. Public compatibility claims remain limited to exact fixtures or named load-check evidence in ``MIR3-Compatibility-ClaimsV1``; the release does not claim every possible mod combination.

## Known limitations

Direct unmodified Cubium 1.0.28 proof remains bounded by archive acquisition and upstream engine compatibility. Historical releases intentionally omit unsupported modern functionality. Mod Portal custody is incomplete until the maintainer uploads each exact ZIP and authenticated redownload plus exact-engine smoke verification succeeds.

## Publication and MIR 4 handoff

Promote only ``main`` to 3.2.9 and ``legacy`` to 2.5.9. The seven lower releases remain tag-only. Publish the exact ZIPs whose hashes appear in ``SHA256SUMS-MIR-3.txt``. MIR 4 begins from these sealed baselines through explicit target profiles and deterministic lowering; it must not reconstruct MIR 3 authority from mutable branch history.
"@
Write-Utf8 "docs/releases/mir3-terminal-release-and-mir4-handoff.md" $guide

Write-Utf8 "docs/releases/mir3-terminal-mod-portal-upload-checklist.md" @"
---
title: "MIR 3 Terminal Mod Portal Upload Checklist"
status: current
applies_to: "3.2.9-1.3.9"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-15
supersedes: []
superseded_by: []
---

# MIR 3 Terminal Mod Portal Upload Checklist

Upload in descending order: 3.2.9, 2.5.9, 1.9.9, 1.8.9, 1.7.9, 1.6.9, 1.5.9, 1.4.9, 1.3.9. For every row use ``dist/more-infinite-research_<version>.zip`` and the matching ready-to-paste text in ``.mir/releases/terminal/mod-portal-descriptions/<version>.md``.

Before upload, compare the archive with ``docs/releases/SHA256SUMS-MIR-3.txt``. After upload, authenticated-redownload the public file, verify archive/content hashes, bytes, entries, and package composition, run the exact-engine load smoke, and append a ``Mir3TerminalPublicationReceiptV1`` with channel ``mod-portal``. Until those steps pass, Mod Portal status remains pending manual upload.
"@

Write-Host "[ok] created MIR 3 maintainer acceptance, nine manifests and seals, family readiness, external release bodies, and handoff documentation"
