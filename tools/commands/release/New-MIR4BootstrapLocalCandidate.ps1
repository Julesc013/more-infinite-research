param(
  [string]$RepoRoot = "",
  [string]$PlanPath = ".mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV1.json",
  [ValidateSet("all", "f210", "f200", "f110", "f100")]
  [string]$Target = "f210",
  [string]$OutputRoot = "build/mir4/emergency-lane",
  [ValidateRange(3, 3)]
  [int]$Repetitions = 3,
  [switch]$Check
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}
if (-not [IO.Path]::IsPathRooted($PlanPath)) { $PlanPath = Join-Path $RepoRoot $PlanPath }
if (-not [IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot = Join-Path $RepoRoot $OutputRoot }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)

. (Join-Path $RepoRoot "tools/lib/mir4/BootstrapMaterialization.ps1")
. (Join-Path $RepoRoot "tools/lib/validation/MIR4DistributionIdentity.ps1")

$allowedOutputRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build/mir4'))
$OutputRoot = Assert-MIR4DescendantPath -Root $allowedOutputRoot -Path $OutputRoot
$null = Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path $OutputRoot

function Assert-Equal([string]$Actual, [string]$Expected, [string]$Context) {
  if ($Actual -cne $Expected) { throw "$Context mismatch: expected '$Expected', got '$Actual'." }
}

function Assert-MIR4PlanTarget {
  param(
    [Parameter(Mandatory)]$PlanTarget,
    [Parameter(Mandatory)]$TerminalImport,
    [Parameter(Mandatory)]$Registry,
    [Parameter(Mandatory)]$VersionAuthority,
    [Parameter(Mandatory)]$RootSet
  )

  $registryRow = @($Registry.payload.targets | Where-Object { $_.id -eq $PlanTarget.target_id })
  if ($registryRow.Count -ne 1) { throw "V2 target registry does not contain exactly one $($PlanTarget.target_id) row." }
  Assert-Equal ([string]$registryRow[0].factorio) ([string]$PlanTarget.factorio_line) "$($PlanTarget.target_key) Factorio line"
  Assert-Equal ([string]$registryRow[0].distribution_target_code) ([string]$PlanTarget.distribution_target_code) "$($PlanTarget.target_key) distribution target code"
  Assert-Equal ([string]$registryRow[0].mir3_predecessor) ([string]$PlanTarget.predecessor.release) "$($PlanTarget.target_key) predecessor"

  $projection = Resolve-MIR4DistributionIdentity -TargetRegistry $Registry -VersionAuthority $VersionAuthority -TargetId ([string]$PlanTarget.target_id) -SourceMinor 0 -SourcePatch 0
  Assert-Equal ([string]$projection.distribution_target_code) ([string]$PlanTarget.distribution_target_code) "$($PlanTarget.target_key) projected code"
  Assert-Equal ([string]$projection.distribution_version) ([string]$PlanTarget.distribution_version) "$($PlanTarget.target_key) projected version"

  $importRow = @($TerminalImport.releases | Where-Object { $_.release -eq $PlanTarget.predecessor.release })
  if ($importRow.Count -ne 1) { throw "Terminal import does not contain exactly one $($PlanTarget.predecessor.release) row." }
  $import = $importRow[0]
  Assert-Equal ([string]$import.target) ([string]$PlanTarget.factorio_line) "$($PlanTarget.target_key) terminal target"
  Assert-Equal ([string]$import.snapshot.source_identity.candidate_commit) ([string]$PlanTarget.source.candidate_commit) "$($PlanTarget.target_key) candidate commit"
  Assert-Equal ([string]$import.snapshot.source_identity.source_tree) ([string]$PlanTarget.source.source_tree) "$($PlanTarget.target_key) source tree"
  Assert-Equal ([string]$import.snapshot.source_identity.common_source_commit) ([string]$PlanTarget.source.common_source_commit) "$($PlanTarget.target_key) common source"
  Assert-Equal ([string]$import.distribution.archive_sha256) ([string]$PlanTarget.predecessor.archive_sha256) "$($PlanTarget.target_key) predecessor archive"
  Assert-Equal ([string]$import.distribution.content_sha256) ([string]$PlanTarget.predecessor.content_sha256) "$($PlanTarget.target_key) predecessor content"
  Assert-Equal ([string]$import.distribution.bytes) ([string]$PlanTarget.predecessor.bytes) "$($PlanTarget.target_key) predecessor bytes"
  Assert-Equal ([string]$import.distribution.entries) ([string]$PlanTarget.predecessor.entry_count) "$($PlanTarget.target_key) predecessor entries"
  Assert-Equal ([string]$import.baseline_manifest.record_sha256) ([string]$PlanTarget.predecessor.baseline_record_sha256) "$($PlanTarget.target_key) baseline record"
  Assert-Equal ([string]$import.normalized_snapshot.record_sha256) ([string]$PlanTarget.predecessor.snapshot_record_sha256) "$($PlanTarget.target_key) snapshot record"
  Assert-Equal ([string]$import.snapshot.engine.version) ([string]$PlanTarget.engine_lock.version) "$($PlanTarget.target_key) engine version"
  Assert-Equal ([string]$import.snapshot.engine.executable_sha256) ([string]$PlanTarget.engine_lock.executable_sha256) "$($PlanTarget.target_key) engine hash"

  $rootRow = @($RootSet.targets | Where-Object { $_.target_id -eq $PlanTarget.target_key })
  if ($rootRow.Count -ne 1) { throw "Bootstrap root set does not contain exactly one $($PlanTarget.target_key) row." }
  Assert-Equal ([string]$rootRow[0].predecessor_release) ([string]$PlanTarget.predecessor.release) "$($PlanTarget.target_key) root predecessor"
  Assert-Equal ([string]$rootRow[0].factorio_line) ([string]$PlanTarget.factorio_line) "$($PlanTarget.target_key) root Factorio line"
  Assert-Equal ([string]$rootRow[0].source_identity.candidate_commit) ([string]$PlanTarget.source.candidate_commit) "$($PlanTarget.target_key) root candidate commit"
  Assert-Equal ([string]$rootRow[0].source_identity.candidate_tree) ([string]$PlanTarget.source.source_tree) "$($PlanTarget.target_key) root source tree"
  Assert-Equal ([string]$rootRow[0].source_identity.common_source_commit) ([string]$PlanTarget.source.common_source_commit) "$($PlanTarget.target_key) root common source"
  Assert-Equal ([string]$rootRow[0].terminal_distribution.archive_sha256) ([string]$PlanTarget.predecessor.archive_sha256) "$($PlanTarget.target_key) root archive"
  Assert-Equal ([string]$rootRow[0].terminal_distribution.content_sha256) ([string]$PlanTarget.predecessor.content_sha256) "$($PlanTarget.target_key) root content"
  Assert-Equal ([string]$rootRow[0].baseline_identity.path) ([string]$PlanTarget.predecessor.baseline_manifest) "$($PlanTarget.target_key) root baseline path"
  Assert-Equal ([string]$rootRow[0].baseline_identity.record_sha256) ([string]$PlanTarget.predecessor.baseline_record_sha256) "$($PlanTarget.target_key) root baseline hash"
  Assert-Equal ([string]$rootRow[0].snapshot_identity.path) ([string]$PlanTarget.predecessor.normalized_snapshot) "$($PlanTarget.target_key) root snapshot path"
  Assert-Equal ([string]$rootRow[0].snapshot_identity.record_sha256) ([string]$PlanTarget.predecessor.snapshot_record_sha256) "$($PlanTarget.target_key) root snapshot hash"
  Assert-Equal ([string]$rootRow[0].exact_engine.version) ([string]$PlanTarget.engine_lock.version) "$($PlanTarget.target_key) root engine version"
  Assert-Equal ([string]$rootRow[0].exact_engine.executable_sha256) ([string]$PlanTarget.engine_lock.executable_sha256) "$($PlanTarget.target_key) root engine hash"
  return $rootRow[0]
}

function Test-MIR4ExistingCandidate {
  param(
    [Parameter(Mandatory)]$PlanTarget,
    [Parameter(Mandatory)]$RootRow
  )

  $manifestPath = Join-Path $OutputRoot "manifests\$($PlanTarget.target_key).json"
  $null = Assert-MIR4NoReparseAncestors -Root $OutputRoot -Path $manifestPath
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Candidate manifest is missing: $manifestPath" }
  $manifestText = Get-Content -Raw -LiteralPath $manifestPath
  $manifestSchema = Join-Path $RepoRoot 'spec/schemas/mir4-bootstrap-local-candidate-manifest.schema.json'
  if (-not ($manifestText | Test-Json -SchemaFile $manifestSchema)) { throw "Candidate manifest schema validation failed: $manifestPath" }
  $manifest = $manifestText | ConvertFrom-Json
  if (-not (Test-MIR4BootstrapRecordHash -Record $manifest)) { throw "Candidate manifest self-hash mismatch: $manifestPath" }
  Assert-MIR4BootstrapCandidateArtifactLayout -Manifest $manifest
  Assert-Equal ([string]$manifest.target_key) ([string]$PlanTarget.target_key) "candidate target"
  Assert-Equal ([string]$manifest.factorio_line) ([string]$PlanTarget.factorio_line) "candidate Factorio line"
  Assert-Equal ([string]$manifest.distribution_version) ([string]$PlanTarget.distribution_version) "candidate version"
  Assert-Equal ([string]$manifest.admission) ([string]$PlanTarget.admission) "candidate admission"
  Assert-Equal ([string]$manifest.identity_roots.semantic) ([string]$RootRow.roots.semantic.sha256) "candidate semantic root"

  $archivePath = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath ([string]$manifest.local_distribution.path)
  $inventory = Get-MIR4ArchiveInventory -Path $archivePath
  Assert-Equal ([string]$inventory.archive_sha256) ([string]$manifest.local_distribution.archive_sha256) "candidate archive hash"
  Assert-Equal ([string]$inventory.content_sha256) ([string]$manifest.local_distribution.content_sha256) "candidate content hash"
  Assert-Equal ([string]$inventory.bytes) ([string]$manifest.local_distribution.bytes) "candidate byte count"
  Assert-Equal ([string]$inventory.entry_count) ([string]$manifest.local_distribution.entry_count) "candidate entry count"

  $capsulePath = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath ([string]$manifest.source_capsule.path)
  $capsuleInventory = Get-MIR4ArchiveInventory -Path $capsulePath
  Assert-Equal ([string]$capsuleInventory.root) 'source' "source capsule root"
  foreach ($field in @('archive_sha256', 'content_sha256', 'bytes', 'entry_count')) {
    Assert-Equal ([string]$capsuleInventory.$field) ([string]$manifest.source_capsule.$field) "source capsule $field"
  }
  $capsuleRecordPath = Join-Path (Split-Path -Parent $capsulePath) 'source-capsule.json'
  $capsuleRecordText = Get-Content -Raw -LiteralPath $capsuleRecordPath
  if (-not ($capsuleRecordText | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-bootstrap-source-capsule.schema.json'))) {
    throw "Source capsule record schema validation failed: $capsuleRecordPath"
  }
  $capsuleRecord = $capsuleRecordText | ConvertFrom-Json
  if (-not (Test-MIR4BootstrapRecordHash -Record $capsuleRecord)) { throw "Source capsule record self-hash mismatch: $capsuleRecordPath" }
  Assert-Equal ([string]$capsuleRecord.record_sha256) ([string]$manifest.source_capsule_record_sha256) "source capsule record binding"
  Assert-Equal ([string]$capsuleRecord.target_key) ([string]$PlanTarget.target_key) "source capsule target"
  Assert-Equal ([string]$capsuleRecord.factorio_line) ([string]$PlanTarget.factorio_line) "source capsule Factorio line"
  Assert-Equal ([string]$capsuleRecord.source.candidate_commit) ([string]$PlanTarget.source.candidate_commit) "source capsule commit"
  Assert-Equal ([string]$capsuleRecord.source.source_tree) ([string]$PlanTarget.source.source_tree) "source capsule tree"
  Assert-Equal ([string]$capsuleRecord.source.common_source_commit) ([string]$PlanTarget.source.common_source_commit) "source capsule common source"
  Assert-Equal ([string]$capsuleRecord.predecessor.archive_sha256) ([string]$PlanTarget.predecessor.archive_sha256) "source capsule predecessor archive"
  Assert-Equal ([string]$capsuleRecord.capsule.archive_sha256) ([string]$capsuleInventory.archive_sha256) "source capsule record archive"
  Assert-Equal ([string]$capsuleRecord.capsule.content_sha256) ([string]$capsuleInventory.content_sha256) "source capsule record content"
  Assert-Equal ([string]$capsuleRecord.package_membership.authority_sha256) (Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')) "package membership tool hash"
  Assert-Equal ([string]$capsuleRecord.package_membership.capsule_tool_sha256) (Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')) "source capsule tool hash"

  $rows = @($manifest.reconstructions)
  if ($rows.Count -ne 3 -or (@($rows.id) -join '|') -cne 'A|B|C') { throw "Candidate manifest must contain exact A/B/C reconstructions." }
  foreach ($row in $rows) {
    $rowPath = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath ([string]$row.path)
    $rowInventory = Get-MIR4ArchiveInventory -Path $rowPath
    foreach ($field in @('archive_sha256', 'content_sha256', 'bytes', 'entry_count')) {
      Assert-Equal ([string]$rowInventory.$field) ([string]$row.$field) "reconstruction $($row.id) $field"
    }
    $rowCapsulePath = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath ([string]$row.source_capsule_path)
    $rowCapsuleInventory = Get-MIR4ArchiveInventory -Path $rowCapsulePath
    Assert-Equal ([string]$rowCapsuleInventory.root) 'source' "reconstruction $($row.id) capsule root"
    Assert-Equal ([string]$rowCapsuleInventory.archive_sha256) ([string]$row.source_capsule_archive_sha256) "reconstruction $($row.id) capsule archive"
    $rowCapsuleRecordPath = Join-Path (Split-Path -Parent $rowCapsulePath) 'source-capsule.json'
    $rowCapsuleRecordText = Get-Content -Raw -LiteralPath $rowCapsuleRecordPath
    if (-not ($rowCapsuleRecordText | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-bootstrap-source-capsule.schema.json'))) {
      throw "Reconstruction $($row.id) source capsule schema validation failed."
    }
    $rowCapsuleRecord = $rowCapsuleRecordText | ConvertFrom-Json
    if (-not (Test-MIR4BootstrapRecordHash -Record $rowCapsuleRecord)) { throw "Reconstruction $($row.id) source capsule record self-hash mismatch." }
    Assert-Equal ([string]$rowCapsuleRecord.record_sha256) ([string]$row.source_capsule_record_sha256) "reconstruction $($row.id) capsule record"
    Assert-Equal ([string]$rowCapsuleRecord.capsule.archive_sha256) ([string]$rowCapsuleInventory.archive_sha256) "reconstruction $($row.id) capsule record archive"
  }
  if (@($rows.archive_sha256 | Sort-Object -Unique).Count -ne 1 -or
      @($rows.content_sha256 | Sort-Object -Unique).Count -ne 1 -or
      @($rows.source_capsule_archive_sha256 | Sort-Object -Unique).Count -ne 1 -or
      @($rows.source_capsule_record_sha256 | Sort-Object -Unique).Count -ne 1) {
    throw "A/B/C candidate or source-capsule identities differ."
  }
  $expectedAuthorityRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.candidate.authority.v1' -Fields ([ordered]@{
    terminal_authority_root = [string]$RootRow.roots.authority.sha256
    root_set_record_sha256 = [string]$rootSet.record_sha256
    plan_record_sha256 = [string]$plan.record_sha256
    plan_import_closure_root = [string]$planImportClosureRoot
    target_key = [string]$PlanTarget.target_key
    distribution_target_code = [string]$PlanTarget.distribution_target_code
    distribution_version = [string]$PlanTarget.distribution_version
    source_capsule_record_sha256 = [string]$manifest.source_capsule_record_sha256
    source_capsule_archive_sha256 = [string]$manifest.source_capsule.archive_sha256
    source_capsule_content_sha256 = [string]$manifest.source_capsule.content_sha256
    candidate_archive_sha256 = [string]$inventory.archive_sha256
    candidate_content_sha256 = [string]$inventory.content_sha256
  })
  Assert-Equal ([string]$manifest.identity_roots.candidate_authority) $expectedAuthorityRoot "candidate authority root"
  $expectedQualificationRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.candidate.qualification-input.v1' -Fields ([ordered]@{
    candidate_authority_root = $expectedAuthorityRoot
    terminal_qualification_root = [string]$RootRow.roots.qualification.sha256
    engine_version = [string]$PlanTarget.engine_lock.version
    engine_sha256 = [string]$PlanTarget.engine_lock.executable_sha256
  })
  Assert-Equal ([string]$manifest.identity_roots.qualification_input) $expectedQualificationRoot "candidate qualification input root"
  Assert-Equal ([string]$manifest.qualification.status) 'blocked-exact-engine-not-provided' "candidate qualification status"
  Assert-Equal ([string]$manifest.qualification.required_engine_version) ([string]$PlanTarget.engine_lock.version) "candidate required engine version"
  Assert-Equal ([string]$manifest.qualification.required_engine_sha256) ([string]$PlanTarget.engine_lock.executable_sha256) "candidate required engine hash"
  if ([bool]$manifest.qualification.runtime_claim_permitted -ne $false -or
      [bool]$manifest.qualification.release_claim_permitted -ne $false) {
    throw "Candidate qualification must not permit runtime or release claims."
  }
  $predecessorPath = Join-Path $RepoRoot ([string]$PlanTarget.predecessor.archive_path)
  $actualComparison = Compare-MIR4BootstrapCandidate `
    -CandidatePath $archivePath `
    -PredecessorPath $predecessorPath `
    -ExpectedCandidateVersion $PlanTarget.distribution_version `
    -ExpectedPredecessorVersion $PlanTarget.predecessor.release `
    -ExpectedCandidateRoot "more-infinite-research_$($PlanTarget.distribution_version)" `
    -ExpectedPredecessorRoot "more-infinite-research_$($PlanTarget.predecessor.release)" `
    -ThrowOnDifference
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $actualComparison) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.equivalence)) {
    throw "Candidate equivalence record is stale or incomplete."
  }
  return $manifest
}

$plan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json
if ($plan.kind -ne 'MIR4BootstrapLocalCandidatePlanV1' -or $plan.public_output_authorized -ne $false) {
  throw "The input is not a publication-forbidden MIR4 bootstrap local candidate plan."
}
if (-not (Test-MIR4BootstrapRecordHash -Record $plan)) { throw "MIR4 local candidate plan self-hash mismatch." }

$schemaPath = Join-Path $RepoRoot 'spec/schemas/mir4-bootstrap-local-candidate-plan.schema.json'
if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) { throw "Test-Json is required for fail-closed MIR 4 materialization." }
if (-not ((Get-Content -Raw -LiteralPath $PlanPath) | Test-Json -SchemaFile $schemaPath)) {
  throw "MIR4 local candidate plan does not satisfy its schema."
}
$governedOutputRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot ([string]$plan.package_policy.output_root)))
$outputComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
if (-not [string]::Equals($OutputRoot, $governedOutputRoot, $outputComparison)) {
  throw "[mir4-output-root] MIR4BootstrapLocalCandidateV1 must write beneath the governed emergency-lane root: $governedOutputRoot"
}
$expectedImports = @(
  '.mir/releases/waves/mir4-r0/MIR4-Entry-GateV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-Emergency-LaneV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-Equivalence-PolicyV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV2.json',
  '.mir/releases/waves/mir4-r0/MIR4-Versioning-and-Distribution-Identity-ADRv2.json',
  '.mir/releases/waves/mir4-r0/terminal-baseline-import.json',
  '.mir/releases/waves/mir4-r0/bootstrap-root-set.json'
)
if ((@($plan.imports) -join '|') -cne ($expectedImports -join '|')) { throw "MIR 4 local candidate plan import closure is not exact." }
foreach ($import in $expectedImports) {
  if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $import) -PathType Leaf)) { throw "MIR 4 plan import is absent: $import" }
}
$planImportBindings = [ordered]@{}
foreach ($import in $expectedImports) {
  $planImportBindings[$import] = Get-MIR4Sha256File -Path (Join-Path $RepoRoot $import)
}
$planImportClosureRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.plan-import-closure.v1' -Fields $planImportBindings

$registryPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV2.json'
$versionAuthorityPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Versioning-and-Distribution-Identity-ADRv2.json'
$entryGatePath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Entry-GateV1.json'
$emergencyLanePath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Emergency-LaneV1.json'
$equivalencePolicyPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Equivalence-PolicyV1.json'
$importPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/terminal-baseline-import.json'
$rootSetPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/bootstrap-root-set.json'
$registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json
$versionAuthority = Get-Content -Raw -LiteralPath $versionAuthorityPath | ConvertFrom-Json
$entryGateText = Get-Content -Raw -LiteralPath $entryGatePath
if (-not ($entryGateText | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-r0-authority.schema.json'))) {
  throw '[mir4-entry-gate] The MIR 4 entry gate does not satisfy the governed R0 authority schema.'
}
$entryGate = $entryGateText | ConvertFrom-Json
$emergencyLaneText = Get-Content -Raw -LiteralPath $emergencyLanePath
$equivalencePolicyText = Get-Content -Raw -LiteralPath $equivalencePolicyPath
foreach ($authorityText in @($emergencyLaneText, $equivalencePolicyText)) {
  if (-not ($authorityText | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-r0-authority.schema.json'))) {
    throw '[mir4-r0-authority] An imported emergency-lane or equivalence authority fails its governed schema.'
  }
}
$emergencyLane = $emergencyLaneText | ConvertFrom-Json
$equivalencePolicy = $equivalencePolicyText | ConvertFrom-Json
$terminalImport = Get-Content -Raw -LiteralPath $importPath | ConvertFrom-Json
$rootSet = Get-Content -Raw -LiteralPath $rootSetPath | ConvertFrom-Json
$null = Assert-MIR4R0DistributionIdentity -RepoRoot $RepoRoot
& (Join-Path $RepoRoot 'tools/commands/release/New-MIR4BootstrapRootSet.ps1') -RepoRoot $RepoRoot -Check
Assert-Equal ([string]$rootSet.derived_from.path) '.mir/releases/waves/mir4-r0/terminal-baseline-import.json' 'root-set derivation path'
Assert-Equal ([string]$rootSet.derived_from.record_sha256) ([string]$terminalImport.record_sha256) 'root-set derivation record'

$f210LocalConstructionAdmissions = @($entryGate.payload.before_mir3_eol | Where-Object {
  [string]$_ -ceq 'generate-local-behavior-equivalent-factorio-2.1-distribution'
})
if ([int]$entryGate.schema -ne 1 -or
    [string]$entryGate.kind -cne 'MIR4-Entry-GateV1' -or
    [string]$entryGate.status -cne 'pre-eol-local-proof-authorized-publication-forbidden' -or
    [bool]$entryGate.package_visible -ne $false -or
    [bool]$entryGate.payload.public_version_4_before_eol -ne $false -or
    [string]$entryGate.target_dispositions.'factorio-2.1' -cne 'local-emergency-proof-first' -or
    [string]$entryGate.target_dispositions.'other-active-targets' -cne 'blocked-until-r1-and-eol' -or
    $f210LocalConstructionAdmissions.Count -ne 1) {
  throw '[mir4-entry-gate] The exact pre-EOL, publication-forbidden f210 emergency-lane authority is absent or has drifted.'
}
$emergencyAllowedDifferences = @($emergencyLane.payload.allowed_differences)
$emergencyParity = @($emergencyLane.parity_test)
if ([int]$emergencyLane.schema -ne 1 -or
    [string]$emergencyLane.kind -cne 'MIR4-Emergency-LaneV1' -or
    [string]$emergencyLane.status -cne 'admitted-not-yet-proven' -or
    [bool]$emergencyLane.package_visible -ne $false -or
    [string]$emergencyLane.target_dispositions.'factorio-2.1' -cne 'first-local-proof' -or
    [string]$emergencyLane.target_dispositions.'other-active-targets' -cne 'not-in-r1' -or
    [string]$emergencyLane.payload.input_release -cne '3.2.9' -or
    [string]$emergencyLane.payload.target -cne 'factorio-2.1' -or
    [string]$emergencyLane.payload.output_root -cne 'build/mir4/emergency-lane' -or
    [bool]$emergencyLane.payload.public_output_authorized -ne $false -or
    @($emergencyAllowedDifferences | Where-Object { $_ -ceq 'version-and-distribution-metadata' }).Count -ne 1 -or
    @($emergencyAllowedDifferences | Where-Object { $_ -ceq 'generated-root-name' }).Count -ne 1 -or
    @($emergencyParity | Where-Object { $_ -ceq 'deterministic-double-build' }).Count -ne 1) {
  throw '[mir4-emergency-lane] The exact admitted, unpublished f210 emergency-lane authority is absent or has drifted.'
}
$permittedDifferences = @($equivalencePolicy.payload.permitted_differences)
if ([int]$equivalencePolicy.schema -ne 1 -or
    [string]$equivalencePolicy.kind -cne 'MIR4-Equivalence-PolicyV1' -or
    [string]$equivalencePolicy.status -cne 'accepted-shadow-policy' -or
    [bool]$equivalencePolicy.package_visible -ne $false -or
    [string]$equivalencePolicy.target_dispositions.'active-nine' -cne 'exact-target-local-equivalence' -or
    @($permittedDifferences | Where-Object { $_ -ceq 'version-and-distribution-metadata' }).Count -ne 1 -or
    @($permittedDifferences | Where-Object { $_ -ceq 'expected-generated-package-root-and-version-name' }).Count -ne 1 -or
    @($equivalencePolicy.payload.hard_failures | Where-Object { $_ -ceq 'package-visible-difference-outside-permitted-set' }).Count -ne 1) {
  throw '[mir4-equivalence-policy] The current target-local shadow equivalence authority is absent or has drifted.'
}

$targets = if ($Target -eq 'all') { @($plan.targets) } else { @($plan.targets | Where-Object { $_.target_key -eq $Target }) }
if ($targets.Count -eq 0) { throw "No target selected." }
$blockedTargets = @($targets | Where-Object {
  [string]$_.target_key -cne 'f210' -or
  [string]$_.admission -cne 'admitted-local-emergency-lane'
})
if ($blockedTargets.Count -gt 0) {
  throw "[mir4-entry-gate] MIR4BootstrapLocalCandidateV1 admits only the local f210 emergency-lane plan row; blocked: $(@($blockedTargets.target_key) -join ', ')."
}
if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) { New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null }

$manifests = @()
foreach ($targetPlan in $targets) {
  $rootRow = Assert-MIR4PlanTarget -PlanTarget $targetPlan -TerminalImport $terminalImport -Registry $registry -VersionAuthority $versionAuthority -RootSet $rootSet
  $predecessorPath = Join-Path $RepoRoot ([string]$targetPlan.predecessor.archive_path)
  $predecessor = Get-MIR4ArchiveInventory -Path $predecessorPath
  Assert-Equal ([string]$predecessor.archive_sha256) ([string]$targetPlan.predecessor.archive_sha256) "$($targetPlan.target_key) predecessor archive on disk"
  Assert-Equal ([string]$predecessor.content_sha256) ([string]$targetPlan.predecessor.content_sha256) "$($targetPlan.target_key) predecessor content on disk"

  if ($Check) {
    $manifests += Test-MIR4ExistingCandidate -PlanTarget $targetPlan -RootRow $rootRow
    continue
  }

  $capsuleTargetRoot = Join-Path $OutputRoot "capsules\$($targetPlan.target_key)"
  Remove-MIR4BuildTree -OutputRoot $OutputRoot -Path $capsuleTargetRoot
  $candidateRoot = Join-Path $OutputRoot "candidates\$($targetPlan.target_key)"
  Remove-MIR4BuildTree -OutputRoot $OutputRoot -Path $candidateRoot
  New-Item -ItemType Directory -Force -Path $candidateRoot | Out-Null
  $reconstructions = @()
  $candidatePaths = @()
  $capsules = @()

  for ($index = 0; $index -lt $Repetitions; $index++) {
    $id = [char]([int][char]'A' + $index)
    $capsule = New-MIR4BootstrapSourceCapsule -RepoRoot $RepoRoot -Target $targetPlan -OutputRoot $OutputRoot -CapsuleId ([string]$id)
    $capsuleInventory = Get-MIR4ArchiveInventory -Path $capsule.archive_path
    $capsules += [pscustomobject][ordered]@{ result = $capsule; inventory = $capsuleInventory }
    $runRoot = Join-Path $candidateRoot ([string]$id)
    $extractRoot = Join-Path $runRoot 'reconstruction'
    New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
    Expand-MIR4SafeArchive -ArchivePath $capsule.archive_path -Destination $extractRoot -OutputRoot $OutputRoot
    $sourceRoot = Join-Path $extractRoot 'source'
    $infoPath = Join-Path $sourceRoot 'info.json'
    $sourceInfo = Get-Content -Raw -LiteralPath $infoPath | ConvertFrom-Json
    Assert-Equal ([string]$sourceInfo.version) ([string]$targetPlan.predecessor.release) "$($targetPlan.target_key) capsule predecessor version"
    Assert-Equal ([string]$sourceInfo.factorio_version) ([string]$targetPlan.factorio_line) "$($targetPlan.target_key) capsule Factorio line"
    Set-MIR4InfoVersion -InfoPath $infoPath -Version ([string]$targetPlan.distribution_version)

    $packageName = "more-infinite-research_$($targetPlan.distribution_version)"
    $candidatePath = Join-Path $runRoot "$packageName.zip"
    Write-MIR4DeterministicArchive -SourceRoot $sourceRoot -EntryRoot $packageName -OutputPath $candidatePath -ContainmentRoot $OutputRoot
    $inventory = Get-MIR4ArchiveInventory -Path $candidatePath
    $null = Compare-MIR4BootstrapCandidate `
      -CandidatePath $candidatePath `
      -PredecessorPath $predecessorPath `
      -ExpectedCandidateVersion $targetPlan.distribution_version `
      -ExpectedPredecessorVersion $targetPlan.predecessor.release `
      -ExpectedCandidateRoot $packageName `
      -ExpectedPredecessorRoot "more-infinite-research_$($targetPlan.predecessor.release)" `
      -ThrowOnDifference
    $reconstructions += [pscustomobject][ordered]@{
      id = [string]$id
      path = Get-MIR4PortablePath -Root $OutputRoot -Path $candidatePath
      source_capsule_path = Get-MIR4PortablePath -Root $OutputRoot -Path $capsule.archive_path
      source_capsule_archive_sha256 = $capsuleInventory.archive_sha256
      source_capsule_record_sha256 = [string]$capsule.record.record_sha256
      archive_sha256 = $inventory.archive_sha256
      content_sha256 = $inventory.content_sha256
      bytes = $inventory.bytes
      entry_count = $inventory.entry_count
    }
    $candidatePaths += $candidatePath
    Remove-MIR4BuildTree -OutputRoot $OutputRoot -Path $extractRoot
  }

  $archiveHashes = @($reconstructions.archive_sha256 | Sort-Object -Unique)
  $contentHashes = @($reconstructions.content_sha256 | Sort-Object -Unique)
  $capsuleArchiveHashes = @($reconstructions.source_capsule_archive_sha256 | Sort-Object -Unique)
  $capsuleRecordHashes = @($reconstructions.source_capsule_record_sha256 | Sort-Object -Unique)
  if ($archiveHashes.Count -ne 1 -or $contentHashes.Count -ne 1 -or
      $capsuleArchiveHashes.Count -ne 1 -or $capsuleRecordHashes.Count -ne 1) {
    throw "Independent source capture or A/B/C reconstruction differs for $($targetPlan.target_key)."
  }

  $capsule = $capsules[0].result
  $capsuleInventory = $capsules[0].inventory

  $distributionRoot = Join-Path $OutputRoot 'distributions'
  $null = Assert-MIR4NoReparseAncestors -Root $OutputRoot -Path $distributionRoot
  New-Item -ItemType Directory -Force -Path $distributionRoot | Out-Null
  $distributionPath = Join-Path $distributionRoot ([IO.Path]::GetFileName($candidatePaths[0]))
  if (Test-Path -LiteralPath $distributionPath) {
    Remove-MIR4BuildTree -OutputRoot $OutputRoot -Path $distributionPath
  }
  Copy-Item -LiteralPath $candidatePaths[0] -Destination $distributionPath
  $distribution = Get-MIR4ArchiveInventory -Path $distributionPath
  $equivalence = Compare-MIR4BootstrapCandidate `
    -CandidatePath $distributionPath `
    -PredecessorPath $predecessorPath `
    -ExpectedCandidateVersion $targetPlan.distribution_version `
    -ExpectedPredecessorVersion $targetPlan.predecessor.release `
    -ExpectedCandidateRoot "more-infinite-research_$($targetPlan.distribution_version)" `
    -ExpectedPredecessorRoot "more-infinite-research_$($targetPlan.predecessor.release)" `
    -ThrowOnDifference
  $authorityRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.candidate.authority.v1' -Fields ([ordered]@{
    terminal_authority_root = [string]$rootRow.roots.authority.sha256
    root_set_record_sha256 = [string]$rootSet.record_sha256
    plan_record_sha256 = [string]$plan.record_sha256
    plan_import_closure_root = [string]$planImportClosureRoot
    target_key = [string]$targetPlan.target_key
    distribution_target_code = [string]$targetPlan.distribution_target_code
    distribution_version = [string]$targetPlan.distribution_version
    source_capsule_record_sha256 = [string]$capsule.record.record_sha256
    source_capsule_archive_sha256 = [string]$capsuleInventory.archive_sha256
    source_capsule_content_sha256 = [string]$capsuleInventory.content_sha256
    candidate_archive_sha256 = [string]$distribution.archive_sha256
    candidate_content_sha256 = [string]$distribution.content_sha256
  })
  $qualificationInputRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.candidate.qualification-input.v1' -Fields ([ordered]@{
    candidate_authority_root = $authorityRoot
    terminal_qualification_root = [string]$rootRow.roots.qualification.sha256
    engine_version = [string]$targetPlan.engine_lock.version
    engine_sha256 = [string]$targetPlan.engine_lock.executable_sha256
  })

  $manifest = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4BootstrapLocalCandidateManifestV1'
    status = 'built-unqualified-local-package-candidate'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    target_key = [string]$targetPlan.target_key
    factorio_line = [string]$targetPlan.factorio_line
    distribution_version = [string]$targetPlan.distribution_version
    admission = [string]$targetPlan.admission
    public_output_authorized = $false
    source_capsule = [pscustomobject][ordered]@{
      path = Get-MIR4PortablePath -Root $OutputRoot -Path $capsule.archive_path
      archive_sha256 = $capsuleInventory.archive_sha256
      content_sha256 = $capsuleInventory.content_sha256
      bytes = $capsuleInventory.bytes
      entry_count = $capsuleInventory.entry_count
    }
    source_capsule_record_sha256 = [string]$capsule.record.record_sha256
    identity_roots = [pscustomobject][ordered]@{
      semantic = [string]$rootRow.roots.semantic.sha256
      candidate_authority = $authorityRoot
      qualification_input = $qualificationInputRoot
    }
    reconstructions = $reconstructions
    equivalence = $equivalence
    local_distribution = [pscustomobject][ordered]@{
      path = Get-MIR4PortablePath -Root $OutputRoot -Path $distributionPath
      archive_sha256 = $distribution.archive_sha256
      content_sha256 = $distribution.content_sha256
      bytes = $distribution.bytes
      entry_count = $distribution.entry_count
    }
    qualification = [pscustomobject][ordered]@{
      status = 'blocked-exact-engine-not-provided'
      required_engine_version = [string]$targetPlan.engine_lock.version
      required_engine_sha256 = [string]$targetPlan.engine_lock.executable_sha256
      runtime_claim_permitted = $false
      release_claim_permitted = $false
    }
    record_sha256 = ''
  }
  Assert-MIR4BootstrapCandidateArtifactLayout -Manifest $manifest
  $manifestPath = Join-Path $OutputRoot "manifests\$($targetPlan.target_key).json"
  $null = Assert-MIR4NoReparseAncestors -Root $OutputRoot -Path $manifestPath
  if (Test-Path -LiteralPath $manifestPath) {
    Remove-MIR4BuildTree -OutputRoot $OutputRoot -Path $manifestPath
  }
  $null = Write-MIR4BootstrapRecord -Record $manifest -Path $manifestPath
  $manifestText = Get-Content -Raw -LiteralPath $manifestPath
  if (-not ($manifestText | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-bootstrap-local-candidate-manifest.schema.json'))) {
    throw "Generated MIR 4 local candidate manifest failed schema validation for $($targetPlan.target_key)."
  }
  $manifests += $manifest
}

$summary = [pscustomobject][ordered]@{
  schema = 1
  kind = 'MIR4BootstrapLocalCandidateSetV1'
  status = 'built-unqualified-local-package-candidates'
  public_output_authorized = $false
  target_count = $manifests.Count
  candidates = @($manifests | ForEach-Object {
    [pscustomobject][ordered]@{
      target_key = $_.target_key
      version = $_.distribution_version
      status = $_.status
      archive_sha256 = $_.local_distribution.archive_sha256
      path = $_.local_distribution.path
    }
  })
}
$summary | ConvertTo-Json -Depth 8
