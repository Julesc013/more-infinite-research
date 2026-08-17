param(
  [string]$RepoRoot = "",
  [switch]$Update,
  [switch]$BuildBundles
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $RepoRoot "tools\lib\validation\MIR4DistributionIdentity.ps1")
. (Join-Path $RepoRoot "tools\lib\mir4\BootstrapMaterialization.ps1")

function Read-Json([string]$RelativePath) {
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required MIR 4 R0 input is absent: $RelativePath" }
  return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String
}

function Get-Sha256Bytes([byte[]]$Bytes) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace("-", "") } finally { $sha.Dispose() }
}

function ConvertTo-CanonicalJsonBytes($Value) {
  $json = ($Value | ConvertTo-Json -Depth 100) -replace "`r`n", "`n"
  return [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
}

function Add-RecordSha256($Material) {
  $record = [ordered]@{}
  foreach ($property in $Material.Keys) { $record[$property] = $Material[$property] }
  $record.record_sha256 = Get-Sha256Bytes (ConvertTo-CanonicalJsonBytes $Material)
  return $record
}

function Write-Or-Check([string]$RelativePath, $Value) {
  $path = Join-Path $RepoRoot $RelativePath
  $bytes = ConvertTo-CanonicalJsonBytes $Value
  if ($Update) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllBytes($path, $bytes)
    return
  }
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Generated MIR 4 R0 view is absent: $RelativePath" }
  $actual = [IO.File]::ReadAllBytes($path)
  if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$actual, [byte[]]$bytes)) { throw "Generated MIR 4 R0 view is stale: $RelativePath" }
}

function Get-Binding([string]$RelativePath) {
  $path = Join-Path $RepoRoot $RelativePath
  $text = [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
  return [ordered]@{ path=$RelativePath; sha256=Get-Sha256Bytes $bytes }
}

function Assert-Schema([string]$RelativePath, [string]$SchemaPath) {
  $raw = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $RelativePath)
  if (-not ($raw | Test-Json -SchemaFile (Join-Path $RepoRoot $SchemaPath) -ErrorAction Stop)) {
    throw "Schema validation failed: $RelativePath"
  }
}

$captureScript = Join-Path $RepoRoot "tools\commands\release\New-MIR3Dot9TerminalBaselines.ps1"
$continuationScript = Join-Path $RepoRoot "tools\commands\release\New-MIR3PostTerminalHotfixBaselineContinuationV2.ps1"
$f200ContinuationScript = Join-Path $RepoRoot "tools\commands\release\New-MIR3Factorio20PostTerminalHotfixBaselineContinuationV2.ps1"
$importScript = Join-Path $RepoRoot "tools\commands\release\Import-MIR3TerminalBaselines.ps1"
$bootstrapRootSetScript = Join-Path $RepoRoot "tools\commands\release\New-MIR4BootstrapRootSet.ps1"
if ($Update) {
  $captureParams = @{ RepoRoot=$RepoRoot }
  if ($BuildBundles) { $captureParams.BuildBundles = $true }
  & $captureScript @captureParams
  & $continuationScript -RepoRoot $RepoRoot
  & $f200ContinuationScript -RepoRoot $RepoRoot
  & $importScript -RepoRoot $RepoRoot
} else {
  & $captureScript -RepoRoot $RepoRoot -Check
  & $continuationScript -RepoRoot $RepoRoot -Check
  & $f200ContinuationScript -RepoRoot $RepoRoot -Check
  & $importScript -RepoRoot $RepoRoot -Check
}
if ($Update) {
  & $bootstrapRootSetScript -RepoRoot $RepoRoot
} else {
  & $bootstrapRootSetScript -RepoRoot $RepoRoot -Check
}

$authorityDirectory = ".mir/releases/waves/mir4-r0"
$executableKinds = @(
  "MIR4-ProgrammeV1",
  "MIR4-Entry-GateV1",
  "MIR4-Versioning-and-Distribution-Identity-ADRv2",
  "MIR4-Repository-Layout-TransitionV1",
  "MIR4-Target-RegistryV2",
  "MIR4-Terminal-Import-ContractV1",
  "MIR4-Equivalence-PolicyV1",
  "MIR4-Emergency-LaneV1",
  "MIR4-Offline-Release-AuthorityV1",
  "MIR3-to-MIR4-Governance-ReconciliationV1"
  "MIR4-Terminal-Predecessor-RefreshV1"
)
foreach ($kind in $executableKinds) {
  $path = "$authorityDirectory/$kind.json"
  $schemaPath = switch ($kind) {
    "MIR4-Target-RegistryV2" { "spec/schemas/mir4-target-registry-v2.schema.json"; break }
    "MIR4-Versioning-and-Distribution-Identity-ADRv2" { "spec/schemas/mir4-versioning-distribution-identity-v2.schema.json"; break }
    default { "spec/schemas/mir4-r0-authority.schema.json" }
  }
  Assert-Schema $path $schemaPath
  $authority = Read-Json $path
  if ([string]$authority.kind -ne $kind -or [bool]$authority.package_visible) { throw "MIR 4 R0 authority identity mismatch: $path" }
}

$eolHash = (Get-FileHash -LiteralPath (Join-Path $RepoRoot ".mir/releases/terminal/MIR3-Terminal-EOL-PolicyV1.json") -Algorithm SHA256).Hash.ToUpperInvariant()
$successorHash = (Get-FileHash -LiteralPath (Join-Path $RepoRoot ".mir/releases/terminal/MIR3TerminalSuccessorBootstrapPolicyV1.json") -Algorithm SHA256).Hash.ToUpperInvariant()
if ($eolHash -ne "778CA4835411E30CF5A1C2940D3FBF3FE659AA44994A7EDF3ABDA0677BFFAD5F" -or
    $successorHash -ne "E6192A56BBC4F418313D70C26E1CB4B796F63478DFCA5F944EEB0E0D2E23F968") {
  throw "Historical MIR 3 EOL or successor policy was rewritten instead of append-only reconciled."
}
$reconciliation = Read-Json "$authorityDirectory/MIR3-to-MIR4-Governance-ReconciliationV1.json"
$entry = Read-Json "$authorityDirectory/MIR4-Entry-GateV1.json"
if ([bool]$reconciliation.payload.public_4x_before_eol -or [bool]$entry.payload.public_version_4_before_eol -or
    (@($reconciliation.payload.ordered_gate) -join "|") -ne "local-4x-proof|terminal-custody-and-archive|mir3-final-index|mir3-eol-seal|public-4x-allocation-and-replication") {
  throw "MIR 3 EOL / MIR 4 entry graph is circular or publication permission was widened."
}

$identityValidation = Assert-MIR4R0DistributionIdentity -RepoRoot $RepoRoot
if ([string]$identityValidation.status -ne "passed" -or [bool]$identityValidation.historical_v1_executable) {
  throw "MIR 4 V2 distribution identity validation did not close."
}

$catalogPath = ".mir/releases/terminal/baselines/dot9-family-catalog.json"
$importPath = "$authorityDirectory/terminal-baseline-import.json"
$catalog = Read-Json $catalogPath
$import = Read-Json $importPath
if (@($catalog.releases).Count -ne 9 -or @($import.releases).Count -ne 9 -or [bool]$import.semantic_authority -or
    (@($import.releases.release) -join "|") -cne "3.2.11|2.5.11|1.9.9|1.8.9|1.7.9|1.6.9|1.5.9|1.4.9|1.3.9") {
  throw "All-nine terminal baseline import is incomplete or prematurely authoritative."
}
foreach ($row in @($catalog.releases)) {
  Assert-Schema ([string]$row.manifest) "spec/schemas/mir3-dot9-terminal-baseline-bundle-manifest.schema.json"
  Assert-Schema ([string]$row.normalized_snapshot) "spec/schemas/mir4-terminal-normalized-snapshot.schema.json"
  Assert-Schema ".mir/releases/terminal/closures/$($row.release).json" "spec/schemas/mir3-terminal-release-closure.schema.json"
}
Assert-Schema ".mir/releases/terminal/baselines/3.2.10/baseline-manifest.json" "spec/schemas/mir3-post-terminal-hotfix-baseline-continuation.schema.json"
Assert-Schema ".mir/releases/terminal/baselines/3.2.10/normalized-snapshot.json" "spec/schemas/mir4-terminal-normalized-snapshot.schema.json"
Assert-Schema ".mir/releases/terminal/closures/3.2.10.json" "spec/schemas/mir3-terminal-release-closure.schema.json"
Assert-Schema ".mir/releases/terminal/baselines/2.5.10/baseline-manifest.json" "spec/schemas/mir3-factorio-2-0-post-terminal-hotfix-baseline-continuation.schema.json"
Assert-Schema ".mir/releases/terminal/baselines/2.5.10/normalized-snapshot.json" "spec/schemas/mir4-terminal-normalized-snapshot.schema.json"
Assert-Schema ".mir/releases/terminal/closures/2.5.10.json" "spec/schemas/mir3-terminal-release-closure.schema.json"
Assert-Schema ".mir/releases/terminal/baselines/3.2.11/baseline-manifest.json" "spec/schemas/mir3-post-terminal-hotfix-baseline-continuation-v2.schema.json"
Assert-Schema ".mir/releases/terminal/baselines/3.2.11/normalized-snapshot.json" "spec/schemas/mir4-terminal-normalized-snapshot.schema.json"
Assert-Schema ".mir/releases/terminal/closures/3.2.11.json" "spec/schemas/mir3-terminal-release-closure.schema.json"
Assert-Schema ".mir/releases/terminal/baselines/2.5.11/baseline-manifest.json" "spec/schemas/mir3-factorio-2-0-post-terminal-hotfix-baseline-continuation-v2.schema.json"
Assert-Schema ".mir/releases/terminal/baselines/2.5.11/normalized-snapshot.json" "spec/schemas/mir4-terminal-normalized-snapshot.schema.json"
Assert-Schema ".mir/releases/terminal/closures/2.5.11.json" "spec/schemas/mir3-terminal-release-closure.schema.json"
Assert-Schema $importPath "spec/schemas/mir4-terminal-baseline-import.schema.json"

$bootstrapRootSetPath = "$authorityDirectory/bootstrap-root-set.json"
Assert-Schema $bootstrapRootSetPath "spec/schemas/mir4-bootstrap-root-set.schema.json"
$bootstrapRootSet = Read-Json $bootstrapRootSetPath
$expectedBootstrapTargets = "f210|f200|f110|f100"
if ([string]$bootstrapRootSet.kind -ne "MIR4BootstrapRootSetV1" -or
    [string]$bootstrapRootSet.status -ne "current-pre-eol-package-excluded" -or
    [bool]$bootstrapRootSet.package_visible -or
    [bool]$bootstrapRootSet.semantic_authority -or
    [string]$bootstrapRootSet.derived_from.record_sha256 -ne [string]$import.record_sha256 -or
    (@($bootstrapRootSet.targets.target_id) -join "|") -cne $expectedBootstrapTargets -or
    @($bootstrapRootSet.targets.roots.semantic.domain | Where-Object { $_ -cne "mir4.bootstrap.semantic.v1" }).Count -ne 0 -or
    @($bootstrapRootSet.targets.roots.authority.domain | Where-Object { $_ -cne "mir4.bootstrap.authority.v1" }).Count -ne 0 -or
    @($bootstrapRootSet.targets.roots.qualification.domain | Where-Object { $_ -cne "mir4.bootstrap.qualification.v1" }).Count -ne 0) {
  throw "MIR 4 bootstrap root set is not the exact four-target domain-separated derivation."
}
$historicalBootstrapCandidatePlanPath = "$authorityDirectory/MIR4-Bootstrap-Local-Candidate-PlanV1.json"
Assert-Schema $historicalBootstrapCandidatePlanPath "spec/schemas/mir4-bootstrap-local-candidate-plan.schema.json"
$historicalBootstrapCandidatePlanV2Path = "$authorityDirectory/MIR4-Bootstrap-Local-Candidate-PlanV2.json"
Assert-Schema $historicalBootstrapCandidatePlanV2Path "spec/schemas/mir4-bootstrap-local-candidate-plan-v2.schema.json"
$bootstrapCandidatePlanPath = "$authorityDirectory/MIR4-Bootstrap-Local-Candidate-PlanV3.json"
Assert-Schema $bootstrapCandidatePlanPath "spec/schemas/mir4-bootstrap-local-candidate-plan-v3.schema.json"
$bootstrapCandidatePlan = Read-Json $bootstrapCandidatePlanPath
$f210Plan = @($bootstrapCandidatePlan.targets | Where-Object target_key -eq "f210")
$f200Plan = @($bootstrapCandidatePlan.targets | Where-Object target_key -eq "f200")
if ([string]$bootstrapCandidatePlan.kind -cne 'MIR4BootstrapLocalCandidatePlanV3' -or
    $f210Plan.Count -ne 1 -or [string]$f210Plan[0].predecessor.release -cne "3.2.11" -or
    [string]$f210Plan[0].engine_lock.version -cne "2.1.14" -or
    [string]$f210Plan[0].engine_lock.executable_sha256 -cne "E396BD25C068DD4C5EF45E93E6A87DBA0E12EEA964B6A5B73163041CC4A6143F" -or
    [string]$f210Plan[0].source.candidate_commit -cne '0a32864d1f1d1fdea090369bc1a22fbd511e290a' -or
    $null -ne $f210Plan[0].PSObject.Properties['correction_authority'] -or
    $f200Plan.Count -ne 1 -or [string]$f200Plan[0].predecessor.release -cne '2.5.11' -or
    [string]$f200Plan[0].source.candidate_commit -cne '57324642e7423d784d7f22b9be4a2b6b350bf012' -or
    -not (Test-MIR4BootstrapRecordHash -Record $bootstrapCandidatePlan)) {
  throw "The local MIR 4 Plan V3 does not bind the current 3.2.11 / 2.5.11 predecessors."
}
$privateLanePath = "$authorityDirectory/MIR4-Private-Lane-AuthorizationV3.json"
Assert-Schema $privateLanePath "spec/schemas/mir4-private-lane-authorization-v3.schema.json"
$privateLane = Read-Json $privateLanePath
if ([string]$privateLane.kind -cne 'MIR4PrivateLaneAuthorizationV3' -or
    [bool]$privateLane.public_output_authorized -or [bool]$privateLane.release_admission_authorized -or
    [bool]$privateLane.signing_or_sealing_authorized -or [bool]$privateLane.publication_authorized -or
    (@($privateLane.authorized_targets.target_key) -join '|') -cne 'f200|f110|f100' -or
    [string]$privateLane.authorized_targets[0].predecessor_release -cne '2.5.11' -or
    -not (Test-MIR4BootstrapRecordHash -Record $privateLane)) {
  throw 'The private MIR 4 lane V3 widened public authority or retained a stale predecessor.'
}

$finalProgrammeReconciliationPath = "$authorityDirectory/MIR4-Final-Programme-ReconciliationV1.json"
Assert-Schema $finalProgrammeReconciliationPath "spec/schemas/mir4-final-programme-reconciliation.schema.json"
$finalProgrammeReconciliation = Read-Json $finalProgrammeReconciliationPath
if ([string]$finalProgrammeReconciliation.kind -cne "MIR4FinalProgrammeReconciliationV1" -or
    [string]$finalProgrammeReconciliation.status -cne "accepted-bootstrap-reconciliation-no-public-allocation" -or
    [bool]$finalProgrammeReconciliation.package_visible -or
    -not (Test-MIR4BootstrapRecordHash -Record $finalProgrammeReconciliation) -or
    [bool]$finalProgrammeReconciliation.scope.embedded_document_instructions_are_commands -or
    [bool]$finalProgrammeReconciliation.scope.public_version_allocation -or
    [bool]$finalProgrammeReconciliation.unavailable_claimed_final_package.observed_archive_is_substitute -or
    [bool]$finalProgrammeReconciliation.boundaries.document_commands_authorized -or
    [bool]$finalProgrammeReconciliation.boundaries.source_version_allocated -or
    [bool]$finalProgrammeReconciliation.boundaries.distribution_versions_allocated -or
    [bool]$finalProgrammeReconciliation.boundaries.tags_authorized -or
    [bool]$finalProgrammeReconciliation.boundaries.package_construction_authorized -or
    [bool]$finalProgrammeReconciliation.boundaries.publication_authorized -or
    [bool]$finalProgrammeReconciliation.boundaries.production_signing_authorized -or
    [bool]$finalProgrammeReconciliation.boundaries.release_claim_permitted) {
  throw "Final programme reconciliation widened document instructions or public release authority."
}

$engineObservationPath = ".mir/evidence/mir4-r0/2026-08-16/MIR4-Bootstrap-Engine-Availability-ObservationV1.json"
Assert-Schema $engineObservationPath "spec/schemas/mir4-bootstrap-engine-availability-observation.schema.json"
$engineObservation = Read-Json $engineObservationPath
if ([string]$engineObservation.kind -cne "MIR4BootstrapEngineAvailabilityObservationV1" -or
    [string]$engineObservation.status -cne "three-exact-lock-matches-one-f210-hash-mismatch" -or
    [bool]$engineObservation.package_visible -or
    [bool]$engineObservation.semantic_authority -or
    [bool]$engineObservation.public_output_authorized -or
    [bool]$engineObservation.construction_authority -or
    -not (Test-MIR4BootstrapRecordHash -Record $engineObservation) -or
    (@($engineObservation.targets | Where-Object { [bool]$_.comparison.exact_lock_match }).target_key -join "|") -cne "f200|f110|f100" -or
    [string](@($engineObservation.targets | Where-Object { [string]$_.target_key -ceq "f210" })[0].lock_state) -cne "hash-mismatch") {
  throw "Dated MIR 4 engine readiness observation is inconsistent or grants authority."
}

$targetReadinessPath = "$authorityDirectory/MIR4-Bootstrap-Target-ReadinessV1.json"
Assert-Schema $targetReadinessPath "spec/schemas/mir4-bootstrap-target-readiness.schema.json"
$targetReadiness = Read-Json $targetReadinessPath
if ([string]$targetReadiness.kind -cne "MIR4BootstrapTargetReadinessV1" -or
    [string]$targetReadiness.status -cne "pre-eol-non-emitting-readiness-only" -or
    [bool]$targetReadiness.package_visible -or
    [bool]$targetReadiness.semantic_authority -or
    [bool]$targetReadiness.public_output_authorized -or
    [bool]$targetReadiness.construction_authority -or
    -not (Test-MIR4BootstrapRecordHash -Record $targetReadiness) -or
    (@($targetReadiness.entry_state.construction_admitted_targets) -join "|") -cne "f210" -or
    (@($targetReadiness.entry_state.blocked_targets) -join "|") -cne "f200|f110|f100" -or
    (@($targetReadiness.targets | Where-Object { [bool]$_.local_construction_admitted }).target_key -join "|") -cne "f210" -or
    @($targetReadiness.targets | Where-Object { [bool]$_.public_output_authorized }).Count -ne 0) {
  throw "MIR 4 target readiness record emitted or admitted a blocked target."
}

$portalVisibilityPath = ".mir/evidence/terminal-publication/2026-08-16/mod-portal/MIR3-Dot9-ModPortal-VisibilityRecheckV1.json"
Assert-Schema $portalVisibilityPath "spec/schemas/mir3-dot9-mod-portal-visibility-recheck.schema.json"
$portalVisibility = Read-Json $portalVisibilityPath
if ([string]$portalVisibility.kind -cne "MIR3Dot9ModPortalVisibilityRecheckV1" -or
    [string]$portalVisibility.status -cne "api-and-rendered-table-two-visible-sha1-matched-redownloads-pending" -or
    [bool]$portalVisibility.package_visible -or
    -not (Test-MIR4BootstrapRecordHash -Record $portalVisibility) -or
    @($portalVisibility.releases | Where-Object { -not [bool]$_.api_visible -or -not [bool]$_.rendered_table_visible -or -not [bool]$_.sha1_matches_sealed }).Count -ne 0 -or
    [int]$portalVisibility.custody_state.authenticated_redownloads_complete -ne 0 -or
    -not [bool]$portalVisibility.custody_state.mir3_eol_blocked -or
    @($portalVisibility.authority.psobject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
  throw "Dated MIR 3 portal visibility record is inconsistent or grants authority."
}

if (Test-Path -LiteralPath (Join-Path $RepoRoot ".work")) { throw ".work must remain absent during MIR 4 R0 bootstrap." }

$generatedSources = @($executableKinds | ForEach-Object { Get-Binding "$authorityDirectory/$_.json" })
$generatedSources += Get-Binding "$authorityDirectory/MIR4-Distribution-Version-Codec-VectorsV2.json"
$generatedSources += Get-Binding $catalogPath
$generatedSources += Get-Binding $importPath
$generatedSources += Get-Binding $bootstrapRootSetPath
$generatedSources += Get-Binding $historicalBootstrapCandidatePlanPath
$generatedSources += Get-Binding $historicalBootstrapCandidatePlanV2Path
$generatedSources += Get-Binding $bootstrapCandidatePlanPath
$generatedSources += Get-Binding $privateLanePath
$generatedSources += Get-Binding $finalProgrammeReconciliationPath
$generatedSources += Get-Binding $targetReadinessPath
$generatedSources += Get-Binding $engineObservationPath
$generatedSources += Get-Binding ".mir/releases/terminal/MIR3-Terminal-ProgrammeV1.json"
$generatedSources += Get-Binding ".mir/evidence/terminal-publication/2026-08-16/mod-portal/MIR3-Dot9-ModPortal-CustodyObservationV1.json"
$generatedSources += Get-Binding $portalVisibilityPath
$generatedSources += Get-Binding "$authorityDirectory/MIR4-Terminal-Predecessor-RefreshV1.json"
$generatedSources += Get-Binding "$authorityDirectory/MIR4-Terminal-Predecessor-RefreshV2.json"
$generatedSources += Get-Binding "$authorityDirectory/MIR4-Terminal-Predecessor-RefreshV3.json"
$generatedSources += Get-Binding "$authorityDirectory/MIR4-Terminal-Import-CompositeV3.json"
$generatedSources += Get-Binding "$authorityDirectory/MIR4-Terminal-Import-ContractV2.json"
$generatedSources += Get-Binding "$authorityDirectory/MIR4-Target-RegistryV4.json"
$generatedSources += Get-Binding "$authorityDirectory/MIR4-Approved-Bootstrap-Correction-CompositeV2.json"
$generatedSources += Get-Binding ".mir/releases/records/2.5.10.json"
$generatedSources += Get-Binding ".mir/evidence/terminal-publication/2026-08-17/github/2.5.10.json"
$generatedSources += Get-Binding ".mir/releases/terminal/baselines/3.2.10/baseline-manifest.json"
$generatedSources += Get-Binding ".mir/releases/records/3.2.11.json"
$generatedSources += Get-Binding ".mir/evidence/terminal-publication/2026-08-18/github/3.2.11.json"
$generatedSources += Get-Binding ".mir/releases/terminal/baselines/3.2.11/baseline-manifest.json"
$generatedSources += Get-Binding ".mir/releases/records/2.5.11.json"
$generatedSources += Get-Binding ".mir/evidence/terminal-publication/2026-08-18/github/2.5.11.json"
$generatedSources += Get-Binding ".mir/releases/terminal/baselines/2.5.11/baseline-manifest.json"
$generatedSources = @($generatedSources | Sort-Object path)

$dashboard = Add-RecordSha256 ([ordered]@{
  schema = 1
  kind = "MIR4R0DashboardV1"
  status = "READY_FOR_MIR4_R0_IMPLEMENTATION"
  package_visible = $false
  generated_from = $generatedSources
  payload = [ordered]@{
    mir3 = [ordered]@{ product_development="closed-except-immutable-post-terminal-hotfixes"; github_publication="3.2.11-latest-and-2.5.11-published-verified"; mod_portal_custody="maintainer-upload-not-independently-redownload-verified"; terminal_dot9_baselines="retained-immutable"; terminal_2_1_continuation="3.2.11-captured-and-imported"; terminal_2_0_continuation="2.5.11-public-release-bound-refresh-v3"; final_index="pending"; museum_and_restore="pending"; eol="pending" }
    mir4 = [ordered]@{ r0="active-package-excluded"; semantic_authority=$false; identity_authority="v4-predecessors-with-unchanged-v2-distribution-codec"; historical_v1_v2_v3_registries_executable=$false; programme_reconciliation="accepted-no-public-allocation"; target_readiness="f210-3.2.11-and-f200-2.5.11-predecessors-bound"; materialization="authorized-private-plan-v3-f210-emergency-and-f200-shadow"; public_4x="forbidden-until-mir3-eol"; emergency_lane="plan-v3-current-reproof-pending" }
    package_delta = 0
    next_executable_task = "M4-003-f210-and-f200-materialization-and-reproof"
  }
})
$queue = Add-RecordSha256 ([ordered]@{
  schema = 1
  kind = "MIR4R0ExecutableQueueV1"
  status = "next-task-ready"
  package_visible = $false
  generated_from = $generatedSources
  payload = [ordered]@{
    tasks = @(
      [ordered]@{id="M4-000";scope="entry-gate-and-post-publication-reconciliation";state="completed-live-r0-entry";blocked_by=@()},
      [ordered]@{id="M4-001";scope="dot9-baseline-capture-plus-post-terminal-continuations";state="completed-current-predecessors-imported";blocked_by=@()},
      [ordered]@{id="M4-002";scope="programme-version-target-equivalence-layout-offline-authorities";state="identity-authority-corrected";blocked_by=@()},
      [ordered]@{id="M4-003";scope="local-offline-emergency-lane-from-corrected-dot11-predecessors";state="plan-v3-ready-f210-and-f200-reproof-pending";blocked_by=@("candidate-bound-f210-and-f200-reproof")},
      [ordered]@{id="M4-004A";scope="portal-custody-final-index-archive-rights-and-restore-records";state="parallel-external-custody-open";blocked_by=@("seven-mod-portal-uploads", "nine-authenticated-redownloads")},
      [ordered]@{id="M4-004B";scope="seal-mir3-eol-and-admit-public-mir4-authority";state="blocked-external-and-local";blocked_by=@("M4-003", "M4-004A")},
      [ordered]@{id="M4-005";scope="accept-and-allocate-public-mir4-source-and-target-identities";state="blocked-by-mir3-eol";blocked_by=@("M4-004B")}
    )
  }
})
Write-Or-Check "$authorityDirectory/dashboard.json" $dashboard
Write-Or-Check "$authorityDirectory/queue.json" $queue
if (-not $Update) {
  Assert-Schema "$authorityDirectory/dashboard.json" "spec/schemas/mir4-r0-status.schema.json"
  Assert-Schema "$authorityDirectory/queue.json" "spec/schemas/mir4-r0-status.schema.json"
}

Write-Host "[ok] MIR 4 R0 bootstrap status: READY_FOR_MIR4_R0_IMPLEMENTATION"
Write-Host "[ok] next executable task: materialize and re-prove f210 and f200 under Plan V3"
