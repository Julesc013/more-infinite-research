param(
  [string]$RepoRoot = "",
  [string]$PlanPath = ".mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV3.json",
  [ValidateSet("all", "f210", "f200", "f110", "f100")]
  [string]$Target = "f210",
  [ValidateSet('emergency', 'local-playtest-shadow')]
  [string]$Lane = 'emergency',
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

function Invoke-MIR4CapsuleChildProcess {
  param(
    [Parameter(Mandatory)][string]$PwshPath,
    [Parameter(Mandatory)][string]$RunnerPath,
    [Parameter(Mandatory)][string]$CapsulePath,
    [Parameter(Mandatory)][string]$EnvelopePath,
    [Parameter(Mandatory)][string]$PredecessorPath,
    [Parameter(Mandatory)][string]$ToolchainRoot,
    [Parameter(Mandatory)][string]$OutputPath
  )

  $processInfo = [Diagnostics.ProcessStartInfo]::new()
  $processInfo.FileName = $PwshPath
  $processInfo.UseShellExecute = $false
  $processInfo.CreateNoWindow = $true
  $processInfo.WorkingDirectory = (Split-Path -Parent $OutputPath)
  $processInfo.RedirectStandardOutput = $true
  $processInfo.RedirectStandardError = $true
  foreach ($argument in @(
    '-NoLogo', '-NoProfile', '-NonInteractive', '-File', $RunnerPath,
    '-CapsulePath', $CapsulePath,
    '-EnvelopePath', $EnvelopePath,
    '-PredecessorPath', $PredecessorPath,
    '-ToolchainRoot', $ToolchainRoot,
    '-OutputRoot', $OutputPath
  )) { $null = $processInfo.ArgumentList.Add([string]$argument) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $processInfo
  if (-not $process.Start()) { throw 'Unable to start the detached MIR 4 capsule reconstruction process.' }
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $process.WaitForExit()
  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()
  $exitCode = $process.ExitCode
  $process.Dispose()
  if ($exitCode -ne 0) { throw "Detached MIR 4 capsule reconstruction failed with exit code $exitCode`: $stderr" }
  $summaryLines = @($stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($summaryLines.Count -ne 1) { throw "Detached MIR 4 capsule reconstruction emitted an unexpected stdout protocol: $stdout" }
  $summary = $summaryLines[0] | ConvertFrom-Json -DateKind String
  if ([string]$summary.status -cne 'passed' -or [string]$summary.candidate_path -cne 'candidate.zip' -or
      [string]$summary.receipt_path -cne 'reconstruction.json') {
    throw 'Detached MIR 4 capsule reconstruction returned an invalid summary.'
  }
  return $summary
}

function Assert-MIR4PlanTarget {
  param(
    [Parameter(Mandatory)]$PlanTarget,
    [Parameter(Mandatory)]$TerminalImport,
    [Parameter(Mandatory)]$Registry,
    [Parameter(Mandatory)]$CodecRegistry,
    [Parameter(Mandatory)]$VersionAuthority,
    [Parameter(Mandatory)]$RootSet
  )

  $registryRow = @($Registry.payload.targets | Where-Object { $_.id -eq $PlanTarget.target_id })
  if ($registryRow.Count -ne 1) { throw "Current target registry does not contain exactly one $($PlanTarget.target_id) row." }
  Assert-Equal ([string]$registryRow[0].factorio) ([string]$PlanTarget.factorio_line) "$($PlanTarget.target_key) Factorio line"
  Assert-Equal ([string]$registryRow[0].distribution_target_code) ([string]$PlanTarget.distribution_target_code) "$($PlanTarget.target_key) distribution target code"
  Assert-Equal ([string]$registryRow[0].mir3_predecessor) ([string]$PlanTarget.predecessor.release) "$($PlanTarget.target_key) predecessor"

  $projection = Resolve-MIR4DistributionIdentity -TargetRegistry $CodecRegistry -VersionAuthority $VersionAuthority -TargetId ([string]$PlanTarget.target_id) -SourceMinor 0 -SourcePatch 0
  Assert-Equal ([string]$projection.distribution_target_code) ([string]$PlanTarget.distribution_target_code) "$($PlanTarget.target_key) projected code"
  Assert-Equal ([string]$projection.distribution_version) ([string]$PlanTarget.distribution_version) "$($PlanTarget.target_key) projected version"

  $terminalSource = if ($null -ne $PlanTarget.PSObject.Properties['predecessor_source']) {
    $PlanTarget.predecessor_source
  } else {
    $PlanTarget.source
  }
  $importRow = @($TerminalImport.releases | Where-Object { $_.release -eq $PlanTarget.predecessor.release })
  if ($importRow.Count -ne 1) { throw "Terminal import does not contain exactly one $($PlanTarget.predecessor.release) row." }
  $import = $importRow[0]
  Assert-Equal ([string]$import.target) ([string]$PlanTarget.factorio_line) "$($PlanTarget.target_key) terminal target"
  Assert-Equal ([string]$import.snapshot.source_identity.candidate_commit) ([string]$terminalSource.candidate_commit) "$($PlanTarget.target_key) predecessor candidate commit"
  Assert-Equal ([string]$import.snapshot.source_identity.source_tree) ([string]$terminalSource.source_tree) "$($PlanTarget.target_key) predecessor source tree"
  Assert-Equal ([string]$import.snapshot.source_identity.common_source_commit) ([string]$terminalSource.common_source_commit) "$($PlanTarget.target_key) predecessor common source"
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
  Assert-Equal ([string]$rootRow[0].source_identity.candidate_commit) ([string]$terminalSource.candidate_commit) "$($PlanTarget.target_key) root predecessor commit"
  Assert-Equal ([string]$rootRow[0].source_identity.candidate_tree) ([string]$terminalSource.source_tree) "$($PlanTarget.target_key) root predecessor tree"
  Assert-Equal ([string]$rootRow[0].source_identity.common_source_commit) ([string]$terminalSource.common_source_commit) "$($PlanTarget.target_key) root predecessor common source"
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

function Get-MIR4PlanCorrection {
  param([Parameter(Mandatory)]$PlanTarget)

  if ($null -eq $PlanTarget.PSObject.Properties['correction_authority']) { return $null }
  $relativePath = [string]$PlanTarget.correction_authority.path
  $path = Join-Path $RepoRoot $relativePath
  $text = Get-Content -Raw -LiteralPath $path
  $correction = $text | ConvertFrom-Json -Depth 100 -DateKind String
  $schemaName = if ([string]$correction.kind -ceq 'MIR4ApprovedBootstrapCorrectionDeltaV2') {
    'mir4-approved-bootstrap-correction-delta-v2.schema.json'
  } else {
    'mir4-approved-bootstrap-correction-delta.schema.json'
  }
  $schema = Join-Path $RepoRoot "spec/schemas/$schemaName"
  if (-not ($text | Test-Json -SchemaFile $schema)) { throw '[mir4-approved-delta] The correction authority fails its exact schema.' }
  if (-not (Test-MIR4BootstrapRecordHash -Record $correction) -or
      [string]$correction.record_sha256 -cne [string]$PlanTarget.correction_authority.record_sha256) {
    throw '[mir4-approved-delta] The correction authority record binding is stale.'
  }
  foreach ($binding in @(
    @($correction.base_source.commit, $PlanTarget.predecessor_source.candidate_commit, 'base commit'),
    @($correction.base_source.tree, $PlanTarget.predecessor_source.source_tree, 'base tree'),
    @($correction.integration_source.commit, $PlanTarget.source.candidate_commit, 'integration commit'),
    @($correction.integration_source.tree, $PlanTarget.source.source_tree, 'integration tree')
  )) { Assert-Equal ([string]$binding[0]) ([string]$binding[1]) "approved correction $($binding[2])" }
  Assert-Equal (Get-MIR4GitTree -RepoRoot $RepoRoot -Commit ([string]$correction.base_source.commit)) ([string]$correction.base_source.tree) 'approved correction base Git tree'
  if ($null -ne $correction.PSObject.Properties['correction_source']) {
    Assert-Equal (Get-MIR4GitTree -RepoRoot $RepoRoot -Commit ([string]$correction.correction_source.commit)) ([string]$correction.correction_source.tree) 'approved correction commit Git tree'
  } elseif ($null -ne $correction.PSObject.Properties['correction_commit']) {
    Assert-Equal ([string]$correction.correction_commit) ([string]$correction.integration_source.commit) 'approved composite correction commit'
  }
  Assert-Equal (Get-MIR4GitTree -RepoRoot $RepoRoot -Commit ([string]$correction.integration_source.commit)) ([string]$correction.integration_source.tree) 'approved correction integration Git tree'
  return $correction
}

function Get-MIR4LocalPlaytestAuthority {
  $relativePath = '.mir/releases/waves/mir4-r0/MIR4-Private-Lane-AuthorizationV3.json'
  $path = Join-Path $RepoRoot $relativePath
  $schema = Join-Path $RepoRoot 'spec/schemas/mir4-private-lane-authorization-v3.schema.json'
  $text = Get-Content -Raw -LiteralPath $path
  if (-not ($text | Test-Json -SchemaFile $schema)) { throw '[mir4-local-playtest-shadow] The lane authorization fails its exact schema.' }
  $authority = $text | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $authority) -or
      [string]$authority.authority_family -cne 'MIRLocalArtifactLaneAuthorizationV1' -or
      [bool]$authority.semantic_difference_authorized -ne $false -or
      [bool]$authority.release_admission_authorized -ne $false -or
      [bool]$authority.public_output_authorized -ne $false -or
      [bool]$authority.signing_or_sealing_authorized -ne $false -or
      [bool]$authority.publication_authorized -ne $false -or
      [bool]$authority.wildcard_targets_authorized -ne $false -or
      [bool]$authority.gate_waivers_authorized -ne $false) {
    throw '[mir4-local-playtest-shadow] The lane authorization crossed a construction-only boundary.'
  }
  foreach ($import in @($authority.imports.PSObject.Properties.Value)) {
    $importPath = Join-Path $RepoRoot ([string]$import.path)
    Assert-Equal (Get-MIR4BootstrapTextSha256 -Path $importPath) ([string]$import.file_sha256) "local lane canonical-text import $($import.path)"
    if ($null -ne $import.PSObject.Properties['record_sha256']) {
      $importRecord = Get-Content -Raw -LiteralPath $importPath | ConvertFrom-Json -Depth 100 -DateKind String
      Assert-Equal ([string]$importRecord.record_sha256) ([string]$import.record_sha256) "local lane record import $($import.path)"
    }
  }
  return $authority
}

function Compare-MIR4PlanCandidate {
  param(
    [Parameter(Mandatory)]$PlanTarget,
    [Parameter(Mandatory)][string]$CandidatePath,
    [Parameter(Mandatory)][string]$PredecessorPath
  )
  $common = @{
    CandidatePath = $CandidatePath
    PredecessorPath = $PredecessorPath
    ExpectedCandidateVersion = [string]$PlanTarget.distribution_version
    ExpectedPredecessorVersion = [string]$PlanTarget.predecessor.release
    ExpectedCandidateRoot = "more-infinite-research_$($PlanTarget.distribution_version)"
    ExpectedPredecessorRoot = "more-infinite-research_$($PlanTarget.predecessor.release)"
    ThrowOnDifference = $true
  }
  $correction = Get-MIR4PlanCorrection -PlanTarget $PlanTarget
  if ($null -ne $correction) {
    return Compare-MIR4BootstrapCorrectedCandidate @common -Correction $correction
  }
  return Compare-MIR4BootstrapCandidate @common
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
  $manifestSchemaRelative = if ($Lane -ceq 'emergency') {
    'spec/schemas/mir4-bootstrap-local-candidate-manifest.schema.json'
  } else {
    'spec/schemas/mir4-local-playtest-candidate-manifest.schema.json'
  }
  $manifestSchema = Join-Path $RepoRoot $manifestSchemaRelative
  if (-not ($manifestText | Test-Json -SchemaFile $manifestSchema)) { throw "Candidate manifest schema validation failed: $manifestPath" }
  $manifest = $manifestText | ConvertFrom-Json -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $manifest)) { throw "Candidate manifest self-hash mismatch: $manifestPath" }
  Assert-MIR4BootstrapCandidateArtifactLayout -Manifest $manifest
  Assert-Equal ([string]$manifest.target_key) ([string]$PlanTarget.target_key) "candidate target"
  Assert-Equal ([string]$manifest.factorio_line) ([string]$PlanTarget.factorio_line) "candidate Factorio line"
  Assert-Equal ([string]$manifest.distribution_version) ([string]$PlanTarget.distribution_version) "candidate version"
  Assert-Equal ([string]$manifest.admission) ([string]$PlanTarget.admission) "candidate admission"
  Assert-Equal ([string]$manifest.lane) $Lane 'candidate construction lane'
  Assert-Equal ([string]$manifest.identity_roots.semantic) ([string]$RootRow.roots.semantic.sha256) "candidate semantic root"
  $correction = Get-MIR4PlanCorrection -PlanTarget $PlanTarget
  if ($Lane -ceq 'emergency') {
    if ($null -ne $correction) {
      Assert-Equal ([string]$manifest.correction_authority.path) ([string]$PlanTarget.correction_authority.path) 'candidate correction path'
      Assert-Equal ([string]$manifest.correction_authority.kind) ([string]$correction.kind) 'candidate correction kind'
      Assert-Equal ([string]$manifest.correction_authority.finding) (@($correction.findings | Sort-Object) -join '+') 'candidate correction finding'
      Assert-Equal ([string]$manifest.correction_authority.record_sha256) ([string]$correction.record_sha256) 'candidate correction record'
    } elseif ($null -ne $manifest.PSObject.Properties['correction_authority']) {
      throw '[mir4-fixed-point] The f210 fixed-point candidate cannot retain a historical correction binding.'
    }
  } else {
    if ($null -ne $correction -or $null -ne $manifest.PSObject.Properties['correction_authority']) {
      throw '[mir4-local-playtest-shadow] A lower-target candidate cannot inherit the f210 correction authority.'
    }
    Assert-Equal (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.local_lane_authority) (ConvertTo-MIR4BootstrapCanonicalJson -Value $laneBinding) 'candidate local lane authority'
    if ([bool]$manifest.release_claim_permitted -ne $false -or
        [string]$manifest.transfer_policy -cne 'maintainer-controlled-private-machines-only') {
      throw '[mir4-local-playtest-shadow] Candidate transfer or release-claim policy crossed the private lane boundary.'
    }
  }

  $archivePath = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath ([string]$manifest.local_distribution.path)
  $inventory = Get-MIR4ArchiveInventory -Path $archivePath
  Assert-Equal ([string]$inventory.archive_sha256) ([string]$manifest.local_distribution.archive_sha256) "candidate archive hash"
  Assert-Equal ([string]$inventory.content_sha256) ([string]$manifest.local_distribution.content_sha256) "candidate content hash"
  Assert-Equal ([string]$inventory.bytes) ([string]$manifest.local_distribution.bytes) "candidate byte count"
  Assert-Equal ([string]$inventory.entry_count) ([string]$manifest.local_distribution.entry_count) "candidate entry count"

  $capsulePath = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath ([string]$manifest.source_capsule.path)
  $capsuleRecordPath = Join-Path (Split-Path -Parent $capsulePath) 'source-capsule.json'
  $capsuleRunnerPath = Join-Path (Split-Path -Parent $capsulePath) 'Invoke-MIR4BootstrapCapsule.ps1'
  $capsuleArtifact = Assert-MIR4BootstrapCapsuleArtifact `
    -CapsulePath $capsulePath `
    -EnvelopePath $capsuleRecordPath `
    -RunnerPath $capsuleRunnerPath `
    -SchemaRoot (Join-Path $RepoRoot 'spec/schemas')
  $capsuleInventory = $capsuleArtifact.inventory
  foreach ($field in @('archive_sha256', 'content_sha256', 'bytes', 'entry_count')) {
    Assert-Equal ([string]$capsuleInventory.$field) ([string]$manifest.source_capsule.$field) "source capsule $field"
  }
  $capsuleRecord = $capsuleArtifact.envelope
  Assert-Equal ([string]$capsuleRecord.record_sha256) ([string]$manifest.source_capsule_record_sha256) "source capsule record binding"
  Assert-Equal ([string]$capsuleRecord.lane) $Lane 'source capsule lane'
  Assert-Equal ([string]$capsuleRecord.target_key) ([string]$PlanTarget.target_key) "source capsule target"
  Assert-Equal ([string]$capsuleRecord.factorio_line) ([string]$PlanTarget.factorio_line) "source capsule Factorio line"
  Assert-Equal ([string]$capsuleRecord.source.candidate_commit) ([string]$PlanTarget.source.candidate_commit) "source capsule commit"
  Assert-Equal ([string]$capsuleRecord.source.source_tree) ([string]$PlanTarget.source.source_tree) "source capsule tree"
  Assert-Equal ([string]$capsuleRecord.source.common_source_commit) ([string]$PlanTarget.source.common_source_commit) "source capsule common source"
  Assert-Equal ([string]$capsuleRecord.predecessor.archive_sha256) ([string]$PlanTarget.predecessor.archive_sha256) "source capsule predecessor archive"
  if ($Lane -ceq 'emergency') {
    if ($null -ne $correction) {
      Assert-Equal (ConvertTo-MIR4BootstrapCanonicalJson -Value $capsuleRecord.correction_authority) (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.correction_authority) 'source capsule correction binding'
      Assert-Equal (ConvertTo-MIR4BootstrapCanonicalJson -Value $capsuleArtifact.manifest.target.correction_authority) (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.correction_authority) 'internal capsule correction binding'
    } elseif ($null -ne $capsuleRecord.PSObject.Properties['correction_authority'] -or
              $null -ne $capsuleArtifact.manifest.target.PSObject.Properties['correction_authority']) {
      throw '[mir4-fixed-point] The f210 fixed-point capsule retained a historical correction binding.'
    }
  } else {
    Assert-Equal (ConvertTo-MIR4BootstrapCanonicalJson -Value $capsuleRecord.local_lane_authority) (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.local_lane_authority) 'source capsule local lane binding'
    Assert-Equal (ConvertTo-MIR4BootstrapCanonicalJson -Value $capsuleArtifact.manifest.target.local_lane_authority) (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.local_lane_authority) 'internal capsule local lane binding'
  }
  Assert-Equal ([string]$capsuleRecord.capsule.archive_sha256) ([string]$capsuleInventory.archive_sha256) "source capsule record archive"
  Assert-Equal ([string]$capsuleRecord.capsule.content_sha256) ([string]$capsuleInventory.content_sha256) "source capsule record content"
  Assert-Equal ([string]$capsuleRecord.package_membership.authority_sha256) (Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')) "package membership tool hash"
  Assert-Equal ([string]$capsuleRecord.package_membership.capsule_tool_sha256) (Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')) "source capsule tool hash"
  foreach ($governedRelative in @(
    (Get-MIR4BootstrapCapsuleControllerPaths) +
    (Get-MIR4BootstrapCapsuleAuthorityPaths -Lane $Lane) +
    (Get-MIR4BootstrapCapsuleSchemaPaths -Lane $Lane)
  )) {
    $memberRows = @($capsuleArtifact.manifest.members | Where-Object { [string]$_.path -ceq [string]$governedRelative })
    if ($memberRows.Count -ne 1) { throw "Source capsule omits governed closure input: $governedRelative" }
    Assert-Equal ([string]$memberRows[0].sha256) (Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot $governedRelative)) "governed source capsule member $governedRelative"
  }
  foreach ($field in @('internal_manifest_record_sha256', 'payload_root_sha256', 'capsule_content_root_sha256', 'authority_closure_root_sha256', 'git_source_proof_record_sha256', 'toolchain_lock_record_sha256', 'canonical_builder_sha256', 'reconstruction_runner_sha256')) {
    Assert-Equal ([string]$manifest.capsule_closure.$field) ([string]$capsuleRecord.closure.$field) "candidate capsule closure $field"
  }
  if ([int]$manifest.capsule_closure.capture_count -ne 2 -or
      [bool]$manifest.capsule_closure.captures_identical -ne $true -or
      [bool]$manifest.capsule_closure.separate_processes -ne $true -or
      [bool]$manifest.capsule_closure.complete_ab_workspaces_deleted_before_c -ne $true -or
      [string]$manifest.capsule_closure.c_reconstruction_source -cne 'copied-canonical-capsule-no-checkout') {
    throw 'Candidate capsule construction claims do not describe the required A/B/delete/C sequence.'
  }

  $predecessorPath = Join-Path $RepoRoot ([string]$PlanTarget.predecessor.archive_path)
  $actualComparison = Compare-MIR4PlanCandidate -PlanTarget $PlanTarget -CandidatePath $archivePath -PredecessorPath $predecessorPath
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $actualComparison) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.equivalence)) {
    throw "Candidate equivalence record is stale or incomplete."
  }

  $rows = @($manifest.reconstructions)
  if ($rows.Count -ne 3 -or (@($rows.id) -join '|') -cne 'A|B|C') { throw "Candidate manifest must contain exact A/B/C reconstructions." }
  foreach ($row in $rows) {
    $rowPath = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath ([string]$row.path)
    $rowInventory = Get-MIR4ArchiveInventory -Path $rowPath
    foreach ($field in @('archive_sha256', 'content_sha256', 'bytes', 'entry_count')) {
      Assert-Equal ([string]$rowInventory.$field) ([string]$row.$field) "reconstruction $($row.id) $field"
    }
    $rowCapsulePath = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath ([string]$row.source_capsule_path)
    $rowCapsuleEnvelopePath = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath ([string]$row.source_capsule_envelope_path)
    $rowRunnerPath = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath ([string]$row.reconstruction_runner_path)
    $rowCapsuleArtifact = Assert-MIR4BootstrapCapsuleArtifact `
      -CapsulePath $rowCapsulePath `
      -EnvelopePath $rowCapsuleEnvelopePath `
      -RunnerPath $rowRunnerPath `
      -SchemaRoot (Join-Path $RepoRoot 'spec/schemas')
    $rowCapsuleInventory = $rowCapsuleArtifact.inventory
    Assert-Equal ([string]$rowCapsuleInventory.archive_sha256) ([string]$row.source_capsule_archive_sha256) "reconstruction $($row.id) capsule archive"
    $rowCapsuleRecord = $rowCapsuleArtifact.envelope
    Assert-Equal ([string]$rowCapsuleRecord.record_sha256) ([string]$row.source_capsule_record_sha256) "reconstruction $($row.id) capsule record"
    Assert-Equal ([string]$rowCapsuleRecord.capsule.archive_sha256) ([string]$rowCapsuleInventory.archive_sha256) "reconstruction $($row.id) capsule record archive"
    Assert-Equal ([string]$row.capsule_content_root_sha256) ([string]$rowCapsuleRecord.closure.capsule_content_root_sha256) "reconstruction $($row.id) capsule content root"
    Assert-Equal ([string]$row.toolchain_lock_record_sha256) ([string]$rowCapsuleArtifact.toolchain_lock.record_sha256) "reconstruction $($row.id) toolchain lock root"
    $receiptPath = Resolve-MIR4ArtifactPath -OutputRoot $OutputRoot -RelativePath ([string]$row.receipt_path)
    $receiptText = Get-Content -Raw -LiteralPath $receiptPath
    if (-not ($receiptText | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-bootstrap-reconstruction-receipt.schema.json'))) {
      throw "Reconstruction $($row.id) receipt schema validation failed."
    }
    $receipt = $receiptText | ConvertFrom-Json -Depth 100 -DateKind String
    if (-not (Test-MIR4BootstrapRecordHash -Record $receipt)) { throw "Reconstruction $($row.id) receipt self-hash mismatch." }
    foreach ($field in @('record_sha256', 'source_capsule_record_sha256', 'source_capsule_archive_sha256', 'capsule_content_root_sha256', 'toolchain_lock_record_sha256', 'package_manifest_sha256', 'equivalence_sha256', 'input_root_sha256', 'result_root_sha256')) {
      $rowField = if ($field -eq 'record_sha256') { 'reconstruction_record_sha256' } else { $field }
      Assert-Equal ([string]$receipt.$field) ([string]$row.$rowField) "reconstruction $($row.id) receipt $field"
    }
    if ([string]$receipt.mode -cne 'capsule-local-fresh-process' -or [bool]$receipt.capsule_only -ne $true -or
        [bool]$receipt.checkout_argument_supplied -ne $false -or [string]$row.mode -cne [string]$receipt.mode -or
        [bool]$row.capsule_only -ne $true -or [bool]$row.checkout_argument_supplied -ne $false) {
      throw "Reconstruction $($row.id) is not a capsule-only fresh child process."
    }
    foreach ($field in @('archive_sha256', 'content_sha256', 'bytes', 'entry_count')) {
      Assert-Equal ([string]$receipt.candidate.$field) ([string]$row.$field) "reconstruction $($row.id) receipt candidate $field"
      Assert-Equal ([string]$receipt.predecessor.$field) ([string]$PlanTarget.predecessor.$field) "reconstruction $($row.id) receipt predecessor $field"
    }
    Assert-Equal ([string]$receipt.target_key) ([string]$PlanTarget.target_key) "reconstruction $($row.id) receipt target"
    Assert-Equal ([string]$receipt.factorio_line) ([string]$PlanTarget.factorio_line) "reconstruction $($row.id) receipt Factorio line"
    Assert-Equal ([string]$receipt.distribution_version) ([string]$PlanTarget.distribution_version) "reconstruction $($row.id) receipt version"
    Assert-Equal ([string]$receipt.lane) $Lane "reconstruction $($row.id) lane"
    if ($Lane -ceq 'emergency') {
      if ($null -ne $correction) {
        Assert-Equal (ConvertTo-MIR4BootstrapCanonicalJson -Value $receipt.correction_authority) (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.correction_authority) "reconstruction $($row.id) correction binding"
      } elseif ($null -ne $receipt.PSObject.Properties['correction_authority']) {
        throw "[mir4-fixed-point] Reconstruction $($row.id) retained a historical correction binding."
      }
    } else {
      Assert-Equal (ConvertTo-MIR4BootstrapCanonicalJson -Value $receipt.local_lane_authority) (ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest.local_lane_authority) "reconstruction $($row.id) local lane binding"
    }
    $packageRows = @($rowInventory.entries | ForEach-Object { "$($_.path)|$($_.bytes)|$($_.raw_sha256)" })
    $expectedPackageManifest = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.package-manifest.v1' -Fields ([ordered]@{ entries = $packageRows })
    $expectedEquivalenceSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $receipt.equivalence)
    if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $receipt.equivalence) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $actualComparison)) {
      throw "Reconstruction $($row.id) receipt equivalence differs from the freshly verified candidate."
    }
    $inputFields = [ordered]@{
      capsule_content_root_sha256 = [string]$rowCapsuleRecord.closure.capsule_content_root_sha256
      envelope_record_sha256 = [string]$rowCapsuleRecord.record_sha256
      predecessor_archive_sha256 = [string]$PlanTarget.predecessor.archive_sha256
      toolchain_lock_record_sha256 = [string]$rowCapsuleArtifact.toolchain_lock.record_sha256
    }
    if ($null -ne $correction) {
      $inputFields.correction_record_sha256 = [string]$correction.record_sha256
    } elseif ($Lane -ceq 'local-playtest-shadow') {
      $inputFields.local_lane_authority_record_sha256 = [string]$laneAuthority.record_sha256
    }
    $expectedInputRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.reconstruction-input.v1' -Fields $inputFields
    $expectedResultRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.reconstruction-result.v1' -Fields ([ordered]@{
      candidate_archive_sha256 = [string]$rowInventory.archive_sha256
      candidate_content_sha256 = [string]$rowInventory.content_sha256
      package_manifest_sha256 = $expectedPackageManifest
      equivalence_sha256 = $expectedEquivalenceSha
    })
    Assert-Equal ([string]$receipt.package_manifest_sha256) $expectedPackageManifest "reconstruction $($row.id) package manifest root"
    Assert-Equal ([string]$receipt.equivalence_sha256) $expectedEquivalenceSha "reconstruction $($row.id) equivalence digest"
    Assert-Equal ([string]$receipt.input_root_sha256) $expectedInputRoot "reconstruction $($row.id) input root"
    Assert-Equal ([string]$receipt.result_root_sha256) $expectedResultRoot "reconstruction $($row.id) result root"
  }
  if (@($rows.archive_sha256 | Sort-Object -Unique).Count -ne 1 -or
      @($rows.content_sha256 | Sort-Object -Unique).Count -ne 1 -or
      @($rows.source_capsule_archive_sha256 | Sort-Object -Unique).Count -ne 1 -or
      @($rows.source_capsule_record_sha256 | Sort-Object -Unique).Count -ne 1 -or
      @($rows.reconstruction_record_sha256 | Sort-Object -Unique).Count -ne 1 -or
      @($rows.package_manifest_sha256 | Sort-Object -Unique).Count -ne 1 -or
      @($rows.equivalence_sha256 | Sort-Object -Unique).Count -ne 1) {
    throw "A/B/C candidate or source-capsule identities differ."
  }
  $authorityFields = [ordered]@{
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
    capsule_content_root_sha256 = [string]$manifest.capsule_closure.capsule_content_root_sha256
    candidate_archive_sha256 = [string]$inventory.archive_sha256
    candidate_content_sha256 = [string]$inventory.content_sha256
  }
  if ($null -ne $correction) {
    $authorityFields.correction_record_sha256 = [string]$correction.record_sha256
  } elseif ($Lane -ceq 'local-playtest-shadow') {
    $authorityFields.local_lane_authority_record_sha256 = [string]$laneAuthority.record_sha256
  }
  $expectedAuthorityRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.candidate.authority.v1' -Fields $authorityFields
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
  return $manifest
}

$plan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json -DateKind String
if ($plan.kind -ne 'MIR4BootstrapLocalCandidatePlanV3' -or $plan.public_output_authorized -ne $false -or $plan.semantic_authority -ne $false) {
  throw "The input is not a publication-forbidden MIR4 bootstrap local candidate plan."
}
if (-not (Test-MIR4BootstrapRecordHash -Record $plan)) { throw "MIR4 local candidate plan self-hash mismatch." }

$schemaPath = Join-Path $RepoRoot 'spec/schemas/mir4-bootstrap-local-candidate-plan-v3.schema.json'
if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) { throw "Test-Json is required for fail-closed MIR 4 materialization." }
if (-not ((Get-Content -Raw -LiteralPath $PlanPath) | Test-Json -SchemaFile $schemaPath)) {
  throw "MIR4 local candidate plan does not satisfy its schema."
}
$laneAuthority = if ($Lane -ceq 'local-playtest-shadow') { Get-MIR4LocalPlaytestAuthority } else { $null }
$laneBinding = if ($null -ne $laneAuthority) {
  [pscustomobject][ordered]@{
    path = '.mir/releases/waves/mir4-r0/MIR4-Private-Lane-AuthorizationV3.json'
    kind = [string]$laneAuthority.kind
    authority_family = [string]$laneAuthority.authority_family
    record_sha256 = [string]$laneAuthority.record_sha256
  }
} else { $null }
$governedOutputRelative = if ($Lane -ceq 'emergency') { [string]$plan.package_policy.output_root } else { [string]$laneAuthority.output_root }
$governedOutputRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot $governedOutputRelative))
$outputComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
if (-not [string]::Equals($OutputRoot, $governedOutputRoot, $outputComparison)) {
  throw "[mir4-output-root] MIR4 bootstrap materialization must use the exact governed '$Lane' output root: $governedOutputRoot"
}
$expectedImports = @(
  '.mir/releases/waves/mir4-r0/MIR4-Entry-GateV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-Emergency-LaneV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-Equivalence-PolicyV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-Terminal-Import-CompositeV3.json',
  '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV4.json',
  '.mir/releases/waves/mir4-r0/MIR4-Versioning-and-Distribution-Identity-ADRv2.json',
  '.mir/releases/waves/mir4-r0/MIR4-Terminal-Predecessor-RefreshV3.json',
  '.mir/releases/waves/mir4-r0/MIR4-Terminal-Import-ContractV2.json',
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

$registryPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV4.json'
$codecRegistryPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV2.json'
$versionAuthorityPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Versioning-and-Distribution-Identity-ADRv2.json'
$entryGatePath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Entry-GateV1.json'
$emergencyLanePath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Emergency-LaneV1.json'
$equivalencePolicyPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Equivalence-PolicyV1.json'
$importPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/terminal-baseline-import.json'
$rootSetPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/bootstrap-root-set.json'
$registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json -DateKind String
$codecRegistry = Get-Content -Raw -LiteralPath $codecRegistryPath | ConvertFrom-Json -DateKind String
$versionAuthority = Get-Content -Raw -LiteralPath $versionAuthorityPath | ConvertFrom-Json -DateKind String
$entryGateText = Get-Content -Raw -LiteralPath $entryGatePath
if (-not ($entryGateText | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-r0-authority.schema.json'))) {
  throw '[mir4-entry-gate] The MIR 4 entry gate does not satisfy the governed R0 authority schema.'
}
$entryGate = $entryGateText | ConvertFrom-Json -DateKind String
$emergencyLaneText = Get-Content -Raw -LiteralPath $emergencyLanePath
$equivalencePolicyText = Get-Content -Raw -LiteralPath $equivalencePolicyPath
foreach ($authorityText in @($emergencyLaneText, $equivalencePolicyText)) {
  if (-not ($authorityText | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-r0-authority.schema.json'))) {
    throw '[mir4-r0-authority] An imported emergency-lane or equivalence authority fails its governed schema.'
  }
}
$emergencyLane = $emergencyLaneText | ConvertFrom-Json -DateKind String
$equivalencePolicy = $equivalencePolicyText | ConvertFrom-Json -DateKind String
$terminalImport = Get-Content -Raw -LiteralPath $importPath | ConvertFrom-Json -DateKind String
$rootSet = Get-Content -Raw -LiteralPath $rootSetPath | ConvertFrom-Json -DateKind String
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
    [string]$emergencyLane.payload.input_release -cne '3.2.10' -or
    [string]$emergencyLane.payload.target -cne 'factorio-2.1' -or
    [string]$emergencyLane.payload.output_root -cne 'build/mir4/emergency-lane' -or
    [bool]$emergencyLane.payload.public_output_authorized -ne $false -or
    @($emergencyAllowedDifferences | Where-Object { $_ -ceq 'version-and-distribution-metadata' }).Count -ne 1 -or
    @($emergencyAllowedDifferences | Where-Object { $_ -ceq 'generated-root-name' }).Count -ne 1 -or
    @($emergencyParity | Where-Object { $_ -ceq 'deterministic-double-build' }).Count -ne 1 -or
    @($emergencyParity | Where-Object { $_ -ceq 'mir3-term-0033-transactional-owner-rollback' }).Count -ne 1 -or
    [string]$emergencyLane.payload.required_finding -cne 'MIR3-TERM-0033') {
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

$laneTargets = if ($Lane -ceq 'emergency') {
  @($plan.targets | Where-Object { [string]$_.target_key -ceq 'f210' })
} else {
  @($plan.targets | Where-Object { [string]$_.target_key -cin @('f200', 'f110', 'f100') })
}
$targets = if ($Target -eq 'all') { $laneTargets } else { @($laneTargets | Where-Object { $_.target_key -eq $Target }) }
if ($targets.Count -eq 0) { throw "No target selected." }
$blockedTargets = @($targets | Where-Object {
  if ($Lane -ceq 'emergency') {
    [string]$_.target_key -cne 'f210' -or [string]$_.admission -cne 'admitted-local-emergency-lane'
  } else {
    [string]$_.target_key -cnotin @('f200', 'f110', 'f100') -or [string]$_.admission -cne 'non-authoritative-shadow-blocked-by-eol'
  }
})
if ($blockedTargets.Count -gt 0) {
  throw "[mir4-entry-gate] Lane '$Lane' does not admit: $(@($blockedTargets.target_key) -join ', ')."
}
$currentRegistryPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV4.json'
$currentRegistrySchemaPath = Join-Path $RepoRoot 'spec/schemas/mir4-target-registry-v4.schema.json'
$currentRegistryText = Get-Content -Raw -LiteralPath $currentRegistryPath
if (-not ($currentRegistryText | Test-Json -SchemaFile $currentRegistrySchemaPath)) {
  throw '[mir4-current-registry] Target Registry V4 does not satisfy its governed schema.'
}
$currentRegistry = $currentRegistryText | ConvertFrom-Json -DateKind String
foreach ($targetPlan in $targets) {
  $currentRows = @($currentRegistry.payload.targets | Where-Object { [string]$_.id -ceq [string]$targetPlan.target_id })
  if ($currentRows.Count -ne 1 -or
      [string]$currentRows[0].mir3_predecessor -cne [string]$targetPlan.predecessor.release) {
    throw "[mir4-stale-predecessor-plan] $($targetPlan.target_key) still binds $($targetPlan.predecessor.release); the current registry requires $($currentRows[0].mir3_predecessor). Create a new append-only candidate plan and lane authorization before materialization."
  }
}
if ($Lane -ceq 'local-playtest-shadow') {
  foreach ($targetPlan in $targets) {
    $authorizedRows = @($laneAuthority.authorized_targets | Where-Object { [string]$_.target_key -ceq [string]$targetPlan.target_key })
    if ($authorizedRows.Count -ne 1 -or
        [string]$authorizedRows[0].source_commit -cne [string]$targetPlan.source.candidate_commit -or
        [string]$authorizedRows[0].source_tree -cne [string]$targetPlan.source.source_tree -or
        [string]$authorizedRows[0].predecessor_archive_sha256 -cne [string]$targetPlan.predecessor.archive_sha256 -or
        [string]$authorizedRows[0].engine_sha256 -cne [string]$targetPlan.engine_lock.executable_sha256) {
      throw "[mir4-local-playtest-shadow] The private lane does not exactly bind $($targetPlan.target_key)."
    }
  }
}
if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) { New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null }

$manifests = @()
foreach ($targetPlan in $targets) {
  $rootRow = Assert-MIR4PlanTarget -PlanTarget $targetPlan -TerminalImport $terminalImport -Registry $registry -CodecRegistry $codecRegistry -VersionAuthority $versionAuthority -RootSet $rootSet
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
  $receiptRoot = Join-Path $OutputRoot "receipts\$($targetPlan.target_key)"
  Remove-MIR4BuildTree -OutputRoot $OutputRoot -Path $receiptRoot
  New-Item -ItemType Directory -Force -Path $receiptRoot | Out-Null
  $reconstructions = @()
  $candidatePaths = @()
  $capsules = [ordered]@{}
  foreach ($id in @('A', 'B')) {
    $capture = New-MIR4BootstrapSourceCapsule -RepoRoot $RepoRoot -Target $targetPlan -OutputRoot $OutputRoot -CapsuleId $id -Lane $Lane
    $artifact = Assert-MIR4BootstrapCapsuleArtifact `
      -CapsulePath $capture.archive_path `
      -EnvelopePath $capture.record_path `
      -RunnerPath $capture.runner_path `
      -SchemaRoot (Join-Path $RepoRoot 'spec/schemas')
    $capsules[$id] = [pscustomobject][ordered]@{ result = $capture; artifact = $artifact }
  }
  foreach ($field in @('archive_sha256', 'content_sha256')) {
    Assert-Equal ([string]$capsules.A.artifact.inventory.$field) ([string]$capsules.B.artifact.inventory.$field) "independent capsule capture $field"
  }
  Assert-Equal ([string]$capsules.A.result.record.record_sha256) ([string]$capsules.B.result.record.record_sha256) 'independent capsule envelope'
  Assert-Equal ([string]$capsules.A.result.record.closure.capsule_content_root_sha256) ([string]$capsules.B.result.record.closure.capsule_content_root_sha256) 'independent capsule content root'

  $capsuleCRoot = Join-Path $capsuleTargetRoot 'C'
  New-Item -ItemType Directory -Force -Path $capsuleCRoot | Out-Null
  $capsuleCPath = Join-Path $capsuleCRoot 'source-capsule.zip'
  $envelopeCPath = Join-Path $capsuleCRoot 'source-capsule.json'
  $runnerCPath = Join-Path $capsuleCRoot 'Invoke-MIR4BootstrapCapsule.ps1'
  Copy-Item -LiteralPath $capsules.A.result.archive_path -Destination $capsuleCPath
  Copy-Item -LiteralPath $capsules.A.result.record_path -Destination $envelopeCPath
  Copy-Item -LiteralPath $capsules.A.result.runner_path -Destination $runnerCPath
  $capsules.C = [pscustomobject][ordered]@{
    result = [pscustomobject][ordered]@{
      archive_path = $capsuleCPath
      record_path = $envelopeCPath
      runner_path = $runnerCPath
      record = (Get-Content -Raw -LiteralPath $envelopeCPath | ConvertFrom-Json -Depth 100 -DateKind String)
    }
    artifact = Assert-MIR4BootstrapCapsuleArtifact `
      -CapsulePath $capsuleCPath `
      -EnvelopePath $envelopeCPath `
      -RunnerPath $runnerCPath `
      -SchemaRoot (Join-Path $RepoRoot 'spec/schemas')
  }

  $tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $constructionTaskRoot = Join-Path $tempParent ("mir4-bootstrap-" + [guid]::NewGuid().ToString('N'))
  $null = Assert-MIR4DescendantPath -Root $tempParent -Path $constructionTaskRoot
  New-Item -ItemType Directory -Path $constructionTaskRoot | Out-Null
  $pwshPath = (Get-Process -Id $PID).Path
  $toolchainRoot = Split-Path -Parent $pwshPath
  $packageName = "more-infinite-research_$($targetPlan.distribution_version)"
  try {
    foreach ($id in @('A', 'B')) {
      $runRoot = Join-Path $constructionTaskRoot $id
      $inputRoot = Join-Path $runRoot 'input'
      $childOutput = Join-Path $runRoot 'output'
      New-Item -ItemType Directory -Force -Path $inputRoot | Out-Null
      $inputCapsule = Join-Path $inputRoot 'source-capsule.zip'
      $inputEnvelope = Join-Path $inputRoot 'source-capsule.json'
      $inputRunner = Join-Path $inputRoot 'Invoke-MIR4BootstrapCapsule.ps1'
      $inputPredecessor = Join-Path $inputRoot ([IO.Path]::GetFileName($predecessorPath))
      Copy-Item -LiteralPath $capsules[$id].result.archive_path -Destination $inputCapsule
      Copy-Item -LiteralPath $capsules[$id].result.record_path -Destination $inputEnvelope
      Copy-Item -LiteralPath $capsules[$id].result.runner_path -Destination $inputRunner
      Copy-Item -LiteralPath $predecessorPath -Destination $inputPredecessor
      $null = Invoke-MIR4CapsuleChildProcess `
        -PwshPath $pwshPath `
        -RunnerPath $inputRunner `
        -CapsulePath $inputCapsule `
        -EnvelopePath $inputEnvelope `
        -PredecessorPath $inputPredecessor `
        -ToolchainRoot $toolchainRoot `
        -OutputPath $childOutput
      $candidateDir = Join-Path $candidateRoot $id
      $receiptDir = Join-Path $receiptRoot $id
      New-Item -ItemType Directory -Force -Path $candidateDir, $receiptDir | Out-Null
      $candidatePath = Join-Path $candidateDir "$packageName.zip"
      $receiptPath = Join-Path $receiptDir 'reconstruction.json'
      Copy-Item -LiteralPath (Join-Path $childOutput 'candidate.zip') -Destination $candidatePath
      Copy-Item -LiteralPath (Join-Path $childOutput 'reconstruction.json') -Destination $receiptPath
    }

    foreach ($id in @('A', 'B')) {
      $runRoot = Join-Path $constructionTaskRoot $id
      Remove-MIR4BuildTree -OutputRoot $constructionTaskRoot -Path $runRoot
      if (Test-Path -LiteralPath $runRoot) { throw "Construction workspace $id survived its required deletion." }
    }

    $id = 'C'
    $runRoot = Join-Path $constructionTaskRoot $id
    $inputRoot = Join-Path $runRoot 'input'
    $childOutput = Join-Path $runRoot 'output'
    New-Item -ItemType Directory -Force -Path $inputRoot | Out-Null
    $inputCapsule = Join-Path $inputRoot 'source-capsule.zip'
    $inputEnvelope = Join-Path $inputRoot 'source-capsule.json'
    $inputRunner = Join-Path $inputRoot 'Invoke-MIR4BootstrapCapsule.ps1'
    $inputPredecessor = Join-Path $inputRoot ([IO.Path]::GetFileName($predecessorPath))
    Copy-Item -LiteralPath $capsules.C.result.archive_path -Destination $inputCapsule
    Copy-Item -LiteralPath $capsules.C.result.record_path -Destination $inputEnvelope
    Copy-Item -LiteralPath $capsules.C.result.runner_path -Destination $inputRunner
    Copy-Item -LiteralPath $predecessorPath -Destination $inputPredecessor
    $null = Invoke-MIR4CapsuleChildProcess `
      -PwshPath $pwshPath `
      -RunnerPath $inputRunner `
      -CapsulePath $inputCapsule `
      -EnvelopePath $inputEnvelope `
      -PredecessorPath $inputPredecessor `
      -ToolchainRoot $toolchainRoot `
      -OutputPath $childOutput
    $candidateDir = Join-Path $candidateRoot $id
    $receiptDir = Join-Path $receiptRoot $id
    New-Item -ItemType Directory -Force -Path $candidateDir, $receiptDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $childOutput 'candidate.zip') -Destination (Join-Path $candidateDir "$packageName.zip")
    Copy-Item -LiteralPath (Join-Path $childOutput 'reconstruction.json') -Destination (Join-Path $receiptDir 'reconstruction.json')
  } finally {
    if (Test-Path -LiteralPath $constructionTaskRoot) { Remove-MIR4BuildTree -OutputRoot $tempParent -Path $constructionTaskRoot }
  }

  foreach ($id in @('A', 'B', 'C')) {
    $capsule = $capsules[$id].result
    $capsuleInventory = $capsules[$id].artifact.inventory
    $candidatePath = Join-Path $candidateRoot "$id\$packageName.zip"
    $receiptPath = Join-Path $receiptRoot "$id\reconstruction.json"
    $inventory = Get-MIR4ArchiveInventory -Path $candidatePath
    $receiptText = Get-Content -Raw -LiteralPath $receiptPath
    if (-not ($receiptText | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-bootstrap-reconstruction-receipt.schema.json'))) {
      throw "Generated reconstruction receipt failed schema validation for $id."
    }
    $receipt = $receiptText | ConvertFrom-Json -Depth 100 -DateKind String
    if (-not (Test-MIR4BootstrapRecordHash -Record $receipt)) { throw "Generated reconstruction receipt self-hash mismatch for $id." }
    $reconstructions += [pscustomobject][ordered]@{
      id = $id
      path = Get-MIR4PortablePath -Root $OutputRoot -Path $candidatePath
      source_capsule_path = Get-MIR4PortablePath -Root $OutputRoot -Path $capsule.archive_path
      source_capsule_envelope_path = Get-MIR4PortablePath -Root $OutputRoot -Path $capsule.record_path
      reconstruction_runner_path = Get-MIR4PortablePath -Root $OutputRoot -Path $capsule.runner_path
      receipt_path = Get-MIR4PortablePath -Root $OutputRoot -Path $receiptPath
      source_capture = if ($id -eq 'C') { 'copied-canonical-capsule-a' } else { 'independent-git-object-capture' }
      mode = 'capsule-local-fresh-process'
      capsule_only = $true
      checkout_argument_supplied = $false
      source_capsule_archive_sha256 = [string]$capsuleInventory.archive_sha256
      source_capsule_record_sha256 = [string]$capsule.record.record_sha256
      capsule_content_root_sha256 = [string]$capsule.record.closure.capsule_content_root_sha256
      toolchain_lock_record_sha256 = [string]$receipt.toolchain_lock_record_sha256
      reconstruction_record_sha256 = [string]$receipt.record_sha256
      package_manifest_sha256 = [string]$receipt.package_manifest_sha256
      equivalence_sha256 = [string]$receipt.equivalence_sha256
      input_root_sha256 = [string]$receipt.input_root_sha256
      result_root_sha256 = [string]$receipt.result_root_sha256
      archive_sha256 = [string]$inventory.archive_sha256
      content_sha256 = [string]$inventory.content_sha256
      bytes = [long]$inventory.bytes
      entry_count = [int]$inventory.entry_count
    }
    $candidatePaths += $candidatePath
  }

  $archiveHashes = @($reconstructions.archive_sha256 | Sort-Object -Unique)
  $contentHashes = @($reconstructions.content_sha256 | Sort-Object -Unique)
  $capsuleArchiveHashes = @($reconstructions.source_capsule_archive_sha256 | Sort-Object -Unique)
  $capsuleRecordHashes = @($reconstructions.source_capsule_record_sha256 | Sort-Object -Unique)
  if ($archiveHashes.Count -ne 1 -or $contentHashes.Count -ne 1 -or
      $capsuleArchiveHashes.Count -ne 1 -or $capsuleRecordHashes.Count -ne 1) {
    throw "Independent source capture or A/B/C reconstruction differs for $($targetPlan.target_key)."
  }

  $receiptHashes = @($reconstructions.reconstruction_record_sha256 | Sort-Object -Unique)
  if ($receiptHashes.Count -ne 1) { throw "A/B/C capsule reconstruction receipts differ for $($targetPlan.target_key)." }

  $capsule = $capsules.A.result
  $capsuleInventory = $capsules.A.artifact.inventory

  $distributionRoot = Join-Path $OutputRoot 'distributions'
  $null = Assert-MIR4NoReparseAncestors -Root $OutputRoot -Path $distributionRoot
  New-Item -ItemType Directory -Force -Path $distributionRoot | Out-Null
  $distributionPath = Join-Path $distributionRoot ([IO.Path]::GetFileName($candidatePaths[2]))
  if (Test-Path -LiteralPath $distributionPath) {
    Remove-MIR4BuildTree -OutputRoot $OutputRoot -Path $distributionPath
  }
  Copy-Item -LiteralPath $candidatePaths[2] -Destination $distributionPath
  $distribution = Get-MIR4ArchiveInventory -Path $distributionPath
  $equivalence = Compare-MIR4PlanCandidate -PlanTarget $targetPlan -CandidatePath $distributionPath -PredecessorPath $predecessorPath
  $authorityFields = [ordered]@{
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
    capsule_content_root_sha256 = [string]$capsule.record.closure.capsule_content_root_sha256
    candidate_archive_sha256 = [string]$distribution.archive_sha256
    candidate_content_sha256 = [string]$distribution.content_sha256
  }
  if ($null -ne $correction) {
    $authorityFields.correction_record_sha256 = [string]$targetPlan.correction_authority.record_sha256
  } elseif ($Lane -ceq 'local-playtest-shadow') {
    $authorityFields.local_lane_authority_record_sha256 = [string]$laneAuthority.record_sha256
  }
  $authorityRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.candidate.authority.v1' -Fields $authorityFields
  $qualificationInputRoot = Get-MIR4DomainSha256 -Domain 'mir4.bootstrap.candidate.qualification-input.v1' -Fields ([ordered]@{
    candidate_authority_root = $authorityRoot
    terminal_qualification_root = [string]$rootRow.roots.qualification.sha256
    engine_version = [string]$targetPlan.engine_lock.version
    engine_sha256 = [string]$targetPlan.engine_lock.executable_sha256
  })

  $manifestFields = [ordered]@{
    schema = 1
    kind = if ($Lane -ceq 'emergency') { 'MIR4BootstrapLocalCandidateManifestV1' } else { 'MIR4LocalPlaytestCandidateManifestV1' }
    status = if ($Lane -ceq 'emergency') { 'built-unqualified-local-package-candidate' } else { 'built-unqualified-local-playtest-candidate' }
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    lane = $Lane
    target_key = [string]$targetPlan.target_key
    factorio_line = [string]$targetPlan.factorio_line
    distribution_version = [string]$targetPlan.distribution_version
    admission = [string]$targetPlan.admission
    public_output_authorized = $false
  }
  if ($null -ne $correction) {
    $manifestFields.correction_authority = [pscustomobject][ordered]@{
      path = [string]$targetPlan.correction_authority.path
      kind = [string]$capsule.record.correction_authority.kind
      finding = [string]$capsule.record.correction_authority.finding
      record_sha256 = [string]$targetPlan.correction_authority.record_sha256
    }
  } elseif ($Lane -ceq 'local-playtest-shadow') {
    $manifestFields.release_claim_permitted = $false
    $manifestFields.local_lane_authority = $laneBinding
    $manifestFields.transfer_policy = 'maintainer-controlled-private-machines-only'
  }
  $manifestFields.source_capsule = [pscustomobject][ordered]@{
      path = Get-MIR4PortablePath -Root $OutputRoot -Path $capsule.archive_path
      archive_sha256 = $capsuleInventory.archive_sha256
      content_sha256 = $capsuleInventory.content_sha256
      bytes = $capsuleInventory.bytes
      entry_count = $capsuleInventory.entry_count
  }
  $manifestFields.source_capsule_record_sha256 = [string]$capsule.record.record_sha256
  $manifestFields.capsule_closure = [pscustomobject][ordered]@{
      internal_manifest_record_sha256 = [string]$capsule.record.closure.internal_manifest_record_sha256
      payload_root_sha256 = [string]$capsule.record.closure.payload_root_sha256
      capsule_content_root_sha256 = [string]$capsule.record.closure.capsule_content_root_sha256
      authority_closure_root_sha256 = [string]$capsule.record.closure.authority_closure_root_sha256
      git_source_proof_record_sha256 = [string]$capsule.record.closure.git_source_proof_record_sha256
      toolchain_lock_record_sha256 = [string]$capsule.record.closure.toolchain_lock_record_sha256
      canonical_builder_sha256 = [string]$capsule.record.closure.canonical_builder_sha256
      reconstruction_runner_sha256 = [string]$capsule.record.closure.reconstruction_runner_sha256
      capture_count = 2
      captures_identical = $true
      separate_processes = $true
      complete_ab_workspaces_deleted_before_c = $true
      c_reconstruction_source = 'copied-canonical-capsule-no-checkout'
  }
  $manifestFields.identity_roots = [pscustomobject][ordered]@{
      semantic = [string]$rootRow.roots.semantic.sha256
      candidate_authority = $authorityRoot
      qualification_input = $qualificationInputRoot
  }
  $manifestFields.reconstructions = $reconstructions
  $manifestFields.equivalence = $equivalence
  $manifestFields.local_distribution = [pscustomobject][ordered]@{
      path = Get-MIR4PortablePath -Root $OutputRoot -Path $distributionPath
      archive_sha256 = $distribution.archive_sha256
      content_sha256 = $distribution.content_sha256
      bytes = $distribution.bytes
      entry_count = $distribution.entry_count
  }
  $manifestFields.qualification = [pscustomobject][ordered]@{
      status = 'blocked-exact-engine-not-provided'
      required_engine_version = [string]$targetPlan.engine_lock.version
      required_engine_sha256 = [string]$targetPlan.engine_lock.executable_sha256
      runtime_claim_permitted = $false
      release_claim_permitted = $false
  }
  $manifestFields.record_sha256 = ''
  $manifest = [pscustomobject]$manifestFields
  Assert-MIR4BootstrapCandidateArtifactLayout -Manifest $manifest
  $manifestPath = Join-Path $OutputRoot "manifests\$($targetPlan.target_key).json"
  $null = Assert-MIR4NoReparseAncestors -Root $OutputRoot -Path $manifestPath
  if (Test-Path -LiteralPath $manifestPath) {
    Remove-MIR4BuildTree -OutputRoot $OutputRoot -Path $manifestPath
  }
  $null = Write-MIR4BootstrapRecord -Record $manifest -Path $manifestPath
  $manifestText = Get-Content -Raw -LiteralPath $manifestPath
  $manifestSchemaRelative = if ($Lane -ceq 'emergency') {
    'spec/schemas/mir4-bootstrap-local-candidate-manifest.schema.json'
  } else {
    'spec/schemas/mir4-local-playtest-candidate-manifest.schema.json'
  }
  if (-not ($manifestText | Test-Json -SchemaFile (Join-Path $RepoRoot $manifestSchemaRelative))) {
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
