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

function Read-Json([string]$RelativePath) {
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required MIR 4 R0 input is absent: $RelativePath" }
  return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
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
  return [ordered]@{ path=$RelativePath; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant() }
}

function Assert-Schema([string]$RelativePath, [string]$SchemaPath) {
  $raw = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $RelativePath)
  if (-not ($raw | Test-Json -SchemaFile (Join-Path $RepoRoot $SchemaPath) -ErrorAction Stop)) {
    throw "Schema validation failed: $RelativePath"
  }
}

$captureScript = Join-Path $RepoRoot "tools\commands\release\New-MIR3Dot9TerminalBaselines.ps1"
$importScript = Join-Path $RepoRoot "tools\commands\release\Import-MIR3TerminalBaselines.ps1"
if ($Update) {
  $captureParams = @{ RepoRoot=$RepoRoot }
  if ($BuildBundles) { $captureParams.BuildBundles = $true }
  & $captureScript @captureParams
  & $importScript -RepoRoot $RepoRoot
} else {
  & $captureScript -RepoRoot $RepoRoot -Check
  & $importScript -RepoRoot $RepoRoot -Check
}

$authorityDirectory = ".mir/releases/waves/mir4-r0"
$requiredKinds = @(
  "MIR4-ProgrammeV1",
  "MIR4-Entry-GateV1",
  "MIR4-Versioning-and-Distribution-Identity-ADRv1",
  "MIR4-Repository-Layout-TransitionV1",
  "MIR4-Target-RegistryV1",
  "MIR4-Terminal-Import-ContractV1",
  "MIR4-Equivalence-PolicyV1",
  "MIR4-Emergency-LaneV1",
  "MIR4-Offline-Release-AuthorityV1",
  "MIR3-to-MIR4-Governance-ReconciliationV1"
)
foreach ($kind in $requiredKinds) {
  $path = "$authorityDirectory/$kind.json"
  Assert-Schema $path "spec/schemas/mir4-r0-authority.schema.json"
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

$registry = Read-Json "$authorityDirectory/MIR4-Target-RegistryV1.json"
$targets = @($registry.payload.targets)
if (@($targets | Group-Object id | Where-Object Count -ne 1).Count -ne 0 -or
    @($targets | Group-Object portal_target_id | Where-Object Count -ne 1).Count -ne 0 -or
    @($targets | Where-Object state -eq "active").Count -ne 9) {
  throw "MIR 4 target registry identity is not unique or does not contain exactly nine active targets."
}
$expectedPredecessors = @{
  "factorio-2.1"="3.2.9"; "factorio-2.0"="2.5.9"; "factorio-1.1"="1.9.9"; "factorio-1.0"="1.8.9";
  "factorio-0.17"="1.7.9"; "factorio-0.16"="1.6.9"; "factorio-0.15"="1.5.9"; "factorio-0.14"="1.4.9"; "factorio-0.13"="1.3.9"
}
foreach ($row in @($targets | Where-Object state -eq "active")) {
  if ([string]$row.mir3_predecessor -ne [string]$expectedPredecessors[[string]$row.id]) { throw "MIR 3 predecessor drift for $($row.id)." }
  foreach ($sourcePatch in @(0, 1, 8, 99)) {
    $encoded = ([int]$row.portal_target_id * 100) + $sourcePatch
    if ($encoded -gt 65535 -or [Math]::Floor($encoded / 100) -ne [int]$row.portal_target_id -or ($encoded % 100) -ne $sourcePatch) {
      throw "MIR 4 distribution version projection is not bounded and reversible for $($row.id)."
    }
  }
}
$versionAuthority = Read-Json "$authorityDirectory/MIR4-Versioning-and-Distribution-Identity-ADRv1.json"
if ([int]$versionAuthority.payload.source_patch_range.maximum -ne 99 -or [int]$versionAuthority.payload.component_maximum -ne 65535 -or
    [string]$versionAuthority.payload.public_allocation -ne "blocked-until-mir3-eol") {
  throw "MIR 4 version allocation boundary was weakened."
}

$catalogPath = ".mir/releases/terminal/baselines/dot9-family-catalog.json"
$importPath = "$authorityDirectory/terminal-baseline-import.json"
$catalog = Read-Json $catalogPath
$import = Read-Json $importPath
if (@($catalog.releases).Count -ne 9 -or @($import.releases).Count -ne 9 -or [bool]$import.semantic_authority) {
  throw "All-nine terminal baseline import is incomplete or prematurely authoritative."
}
foreach ($row in @($catalog.releases)) {
  Assert-Schema ([string]$row.manifest) "spec/schemas/mir3-dot9-terminal-baseline-bundle-manifest.schema.json"
  Assert-Schema ([string]$row.normalized_snapshot) "spec/schemas/mir4-terminal-normalized-snapshot.schema.json"
  Assert-Schema ".mir/releases/terminal/closures/$($row.release).json" "spec/schemas/mir3-terminal-release-closure.schema.json"
}
Assert-Schema $importPath "spec/schemas/mir4-terminal-baseline-import.schema.json"

if (Test-Path -LiteralPath (Join-Path $RepoRoot ".work")) { throw ".work must remain absent during MIR 4 R0 bootstrap." }

$generatedSources = @($requiredKinds | ForEach-Object { Get-Binding "$authorityDirectory/$_.json" })
$generatedSources += Get-Binding $catalogPath
$generatedSources += Get-Binding $importPath
$generatedSources += Get-Binding ".mir/releases/terminal/MIR3-Terminal-ProgrammeV1.json"
$generatedSources += Get-Binding ".mir/evidence/terminal-publication/2026-08-16/mod-portal/MIR3-Dot9-ModPortal-CustodyObservationV1.json"
$generatedSources = @($generatedSources | Sort-Object path)

$dashboard = Add-RecordSha256 ([ordered]@{
  schema = 1
  kind = "MIR4R0DashboardV1"
  status = "READY_FOR_MIR4_R0_IMPLEMENTATION"
  package_visible = $false
  generated_from = $generatedSources
  payload = [ordered]@{
    mir3 = [ordered]@{ product_development="closed"; github_publication="complete"; mod_portal_custody="partial-two-visible-seven-not-uploaded"; terminal_dot9_baselines="capture-ready-custody-pending"; final_index="pending"; museum_and_restore="pending"; eol="pending" }
    mir4 = [ordered]@{ r0="active-package-excluded"; semantic_authority=$false; public_4x="forbidden-until-mir3-eol"; emergency_lane="admitted-not-yet-proven" }
    package_delta = 0
    next_executable_task = "M4-003-local-offline-emergency-lane"
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
      [ordered]@{id="M4-000";scope="entry-gate-and-post-publication-reconciliation";state="ready-at-bootstrap-head";blocked_by=@()},
      [ordered]@{id="M4-001";scope="dot9-baseline-capture-and-import";state="ready-at-bootstrap-head-public-custody-pending";blocked_by=@("manual-mod-portal-custody-for-final-seal")},
      [ordered]@{id="M4-002";scope="programme-version-target-equivalence-layout-offline-authorities";state="ready-at-bootstrap-head";blocked_by=@()},
      [ordered]@{id="M4-003";scope="local-offline-emergency-lane";state="ready";blocked_by=@()},
      [ordered]@{id="M4-004";scope="museum-final-index-archive-and-restore";state="pending";blocked_by=@("M4-003")},
      [ordered]@{id="M4-005";scope="mod-portal-custody-and-mir3-eol";state="blocked-external-and-local";blocked_by=@("seven-mod-portal-uploads", "nine-authenticated-redownloads", "M4-003", "M4-004")}
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
Write-Host "[ok] next executable task: M4-003-local-offline-emergency-lane"
