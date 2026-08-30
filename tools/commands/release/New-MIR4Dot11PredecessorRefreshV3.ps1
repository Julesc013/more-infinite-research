param(
  [string]$RepoRoot = "",
  [ValidateSet("All", "Core", "Private")]
  [string]$Phase = "All",
  [switch]$Check
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$authorityRoot = ".mir/releases/waves/mir4-r0"
$recordedAt = "2026-08-18T03:15:00+10:00"

function Read-Json([string]$RelativePath) {
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required authority is absent: $RelativePath" }
  return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String
}

function ConvertTo-CanonicalJsonBytes($Value) {
  $json = ($Value | ConvertTo-Json -Depth 100 -Compress) -replace "`r`n", "`n"
  return [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
}

function Get-Sha256Bytes([byte[]]$Bytes) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace("-", "") } finally { $sha.Dispose() }
}

function Get-TextIdentity([string]$RelativePath) {
  $path = Join-Path $RepoRoot $RelativePath
  $text = [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
  return [ordered]@{path=$RelativePath;file_sha256=(Get-Sha256Bytes $bytes)}
}

function Add-RecordSha256($Value) {
  $material = [ordered]@{}
  foreach ($property in $Value.PSObject.Properties) {
    if ($property.Name -ne "record_sha256") { $material[$property.Name] = $property.Value }
  }
  $canonical = ($material | ConvertTo-Json -Depth 100 -Compress) -replace "`r`n", "`n" -replace "`r", "`n"
  $material.record_sha256 = Get-Sha256Bytes ([Text.UTF8Encoding]::new($false).GetBytes($canonical))
  return [pscustomobject]$material
}

function Write-Or-Check([string]$RelativePath, $Value, [bool]$SelfHash = $false) {
  if ($SelfHash) { $Value = Add-RecordSha256 $Value }
  $bytes = ConvertTo-CanonicalJsonBytes $Value
  $path = Join-Path $RepoRoot $RelativePath
  if ($Check) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        -not [Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($path), [byte[]]$bytes)) {
      throw "Generated authority is stale: $RelativePath"
    }
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllBytes($path, $bytes)
  }
  return $Value
}

function New-Predecessor($Manifest, $Snapshot) {
  return [pscustomobject][ordered]@{
    release = [string]$Snapshot.release
    archive_path = [string]$Snapshot.distribution.path
    archive_sha256 = [string]$Snapshot.distribution.archive_sha256
    content_sha256 = [string]$Snapshot.distribution.content_sha256
    bytes = [long]$Snapshot.distribution.bytes
    entry_count = [int]$Snapshot.distribution.entries
    baseline_manifest = ".mir/releases/terminal/baselines/$($Snapshot.release)/baseline-manifest.json"
    baseline_record_sha256 = [string]$Manifest.record_sha256
    normalized_snapshot = ".mir/releases/terminal/baselines/$($Snapshot.release)/normalized-snapshot.json"
    snapshot_record_sha256 = [string]$Snapshot.record_sha256
  }
}

$manifest210 = Read-Json ".mir/releases/terminal/baselines/3.2.11/baseline-manifest.json"
$snapshot210 = Read-Json ".mir/releases/terminal/baselines/3.2.11/normalized-snapshot.json"
$record210 = Read-Json ".mir/releases/records/3.2.11.json"
$manifest200 = Read-Json ".mir/releases/terminal/baselines/2.5.11/baseline-manifest.json"
$snapshot200 = Read-Json ".mir/releases/terminal/baselines/2.5.11/normalized-snapshot.json"
$record200 = Read-Json ".mir/releases/records/2.5.11.json"

if ($Phase -in @("All", "Core")) {
  $refresh = [pscustomobject][ordered]@{
    schema = 1
    kind = "MIR4-Terminal-Predecessor-RefreshV3"
    status = "accepted-current-pre-eol-package-excluded"
    recorded_at = $recordedAt
    package_visible = $false
    authority_id = "MIR4-terminal-predecessor-refresh-v3"
    imports = @(
      "$authorityRoot/MIR4-Terminal-Predecessor-RefreshV2.json",
      ".mir/releases/records/3.2.11.json",
      ".mir/evidence/terminal-publication/2026-08-18/github/3.2.11.json",
      ".mir/releases/records/2.5.11.json",
      ".mir/evidence/terminal-publication/2026-08-18/github/2.5.11.json"
    )
    semantic_reads = @("immutable-dot10-baselines", "public-dot11-corrections", "exact-2.1.14-and-2.0.77-qualification", "mir4-terminal-predecessor-refresh-v2")
    semantic_writes = @("mir4-factorio-2.1-predecessor", "mir4-factorio-2.0-predecessor", "m4-003-corrected-predecessor-binding")
    target_dispositions = [pscustomobject][ordered]@{
      "factorio-2.1" = "advance-predecessor-to-3.2.11"
      "factorio-2.0" = "advance-predecessor-to-2.5.11"
      "factorio-1.x" = "retain-existing-dot9-predecessors"
      historical = "retain-all-dot9-and-dot10-baseline-snapshots"
    }
    digest_classes = [pscustomobject][ordered]@{semantic="dot11-maximum-level-contract-v2";authority="append-only-emergency-predecessor-refresh-v3";qualification="exact-engine-and-public-byte-verification"}
    migration = [pscustomobject][ordered]@{from="3.2.10-and-2.5.10-predecessors";to="3.2.11-and-2.5.11-predecessors";state="accepted-before-m4-003-resumption"}
    rollback = [pscustomobject][ordered]@{strategy="retain-all-immutable-baselines-and-block-materialization-on-binding-mismatch";permitted_until="mir4-semantic-authority-cutover"}
    parity_test = @("exact-public-dot11-bytes", "lossless-maximum-level-contract", "transactional-owner-replacement", "exact-engine-locks")
    sunset_condition = "superseded-by-sealed-mir4-terminal-import-and-qualified-m4-003-completion"
    payload = [pscustomobject][ordered]@{
      factorio_2_1 = [pscustomobject][ordered]@{predecessor_release="3.2.11";archive_sha256=[string]$snapshot210.distribution.archive_sha256;content_sha256=[string]$snapshot210.distribution.content_sha256;package_source_commit=[string]$record210.package.source_commit;package_source_tree=[string]$record210.package.source_tree;engine=[pscustomobject][ordered]@{version=[string]$snapshot210.engine.version;executable_sha256=[string]$snapshot210.engine.executable_sha256}}
      factorio_2_0 = [pscustomobject][ordered]@{predecessor_release="2.5.11";archive_sha256=[string]$snapshot200.distribution.archive_sha256;content_sha256=[string]$snapshot200.distribution.content_sha256;package_source_commit=[string]$record200.package.source_commit;package_source_tree=[string]$record200.package.source_tree;engine=[pscustomobject][ordered]@{version=[string]$snapshot200.engine.version;executable_sha256=[string]$snapshot200.engine.executable_sha256}}
      mir4_semantic_authority = $false
      public_4x_authorized = $false
    }
  }
  $null = Write-Or-Check "$authorityRoot/MIR4-Terminal-Predecessor-RefreshV3.json" $refresh

  $composite = [pscustomobject][ordered]@{
    schema = 1
    kind = "MIR4-Terminal-Import-CompositeV3"
    status = "accepted-package-excluded-corrected-predecessor-composite"
    recorded_at = $recordedAt
    package_visible = $false
    authority_id = "MIR4-terminal-import-composite-v3"
    imports = @("$authorityRoot/MIR4-Terminal-Predecessor-RefreshV3.json", ".mir/releases/terminal/baselines/3.2.11/baseline-manifest.json", ".mir/releases/terminal/baselines/2.5.11/baseline-manifest.json", ".mir/releases/emergency/MIR3PostTerminalEmergencyHotfixChangeSetV2.json")
    semantic_reads = @("dot11-terminal-snapshots", "closed-MIR3-TERM-0033", "closed-MIR3-TERM-0034")
    semantic_writes = @("normalized-terminal-import-root", "mir4-upgrade-predecessor-root")
    target_dispositions = [pscustomobject][ordered]@{"f210"="import-3.2.11";"f200"="import-2.5.11";"f110-and-f100"="unchanged"}
    digest_classes = [pscustomobject][ordered]@{semantic="corrected-dot11-predecessor-pair";authority="bound-terminal-baseline-continuations";qualification="reuse-terminal-release-proof-only-not-mir4-candidate-proof"}
    migration = [pscustomobject][ordered]@{from="terminal-import-v2";to="terminal-import-composite-v3";state="ready-for-private-candidate-reconstruction"}
    rollback = [pscustomobject][ordered]@{strategy="keep-v1-v2-authorities-historical-and-fail-closed";permitted_until="m4-003-candidate-proof-complete"}
    parity_test = @("f210-predecessor-is-3.2.11", "f200-predecessor-is-2.5.11", "f110-and-f100-identities-unchanged")
    sunset_condition = "superseded-by-qualified-m4-003-terminal-import"
    payload = [pscustomobject][ordered]@{findings=@("MIR3-TERM-0033","MIR3-TERM-0034");f210=[pscustomobject][ordered]@{release="3.2.11";baseline_record_sha256=[string]$manifest210.record_sha256;snapshot_record_sha256=[string]$snapshot210.record_sha256};f200=[pscustomobject][ordered]@{release="2.5.11";baseline_record_sha256=[string]$manifest200.record_sha256;snapshot_record_sha256=[string]$snapshot200.record_sha256};semantic_authority=$false;public_4x_authorized=$false}
  }
  $null = Write-Or-Check "$authorityRoot/MIR4-Terminal-Import-CompositeV3.json" $composite

  $registry = Read-Json "$authorityRoot/MIR4-Target-RegistryV3.json"
  $registry.schema = 4
  $registry.kind = "MIR4-Target-RegistryV4"
  $registry.recorded_at = $recordedAt
  $registry.authority_id = "MIR4-target-registry-v4"
  $registry.imports = @(".mir/targets.json", "$authorityRoot/MIR4-Target-RegistryV3.json", "$authorityRoot/MIR4-Terminal-Predecessor-RefreshV3.json", "$authorityRoot/MIR4-Terminal-Import-CompositeV3.json")
  $registry.semantic_reads = @("historical-v3-target-registry", "append-only-terminal-predecessor-refresh-v3", "target-capabilities")
  $registry.migration = [pscustomobject][ordered]@{from="v3-dot10-predecessor-bindings";to="v4-dot11-predecessor-bindings";state="accepted-pre-publication-current"}
  $registry.payload | Add-Member -NotePropertyName v3_disposition -NotePropertyValue "historical-dot10-predecessor-registry-non-executable" -Force
  @($registry.payload.targets | Where-Object id -ceq "factorio-2.1")[0].mir3_predecessor = "3.2.11"
  @($registry.payload.targets | Where-Object id -ceq "factorio-2.0")[0].mir3_predecessor = "2.5.11"
  $null = Write-Or-Check "$authorityRoot/MIR4-Target-RegistryV4.json" $registry

  $planV2 = Read-Json "$authorityRoot/MIR4-Bootstrap-Local-Candidate-PlanV2.json"
  $planV2.schema = 3
  $planV2.kind = "MIR4BootstrapLocalCandidatePlanV3"
  $planV2.supersedes = [pscustomobject][ordered]@{path="$authorityRoot/MIR4-Bootstrap-Local-Candidate-PlanV2.json";record_sha256=[string](Read-Json "$authorityRoot/MIR4-Bootstrap-Local-Candidate-PlanV2.json").record_sha256;disposition="historical-dot10-predecessor-plan"}
  $planV2.imports = @("$authorityRoot/MIR4-Entry-GateV1.json", "$authorityRoot/MIR4-Emergency-LaneV1.json", "$authorityRoot/MIR4-Equivalence-PolicyV1.json", "$authorityRoot/MIR4-Terminal-Import-CompositeV3.json", "$authorityRoot/MIR4-Target-RegistryV4.json", "$authorityRoot/MIR4-Versioning-and-Distribution-Identity-ADRv2.json", "$authorityRoot/MIR4-Terminal-Predecessor-RefreshV3.json", "$authorityRoot/MIR4-Terminal-Import-ContractV2.json", "$authorityRoot/terminal-baseline-import.json", "$authorityRoot/bootstrap-root-set.json")
  $f210 = @($planV2.targets | Where-Object target_key -ceq "f210")[0]
  $f210.PSObject.Properties.Remove("predecessor_source")
  $f210.PSObject.Properties.Remove("correction_authority")
  $f210.source = [pscustomobject][ordered]@{candidate_commit=[string]$record210.package.source_commit;source_tree=[string]$record210.package.source_tree;common_source_commit=[string]$snapshot210.source_identity.common_source_commit}
  $f210.predecessor = New-Predecessor $manifest210 $snapshot210
  $f210.dispositions.semantic_change = "none-bootstrap-fixed-point"
  $f210.dispositions.package = "metadata-only-version-and-root-difference"
  $f210.dispositions.capability_omissions = ".mir/releases/terminal/baselines/3.2.11/normalized-snapshot.json#/capability_omissions"
  $f200 = @($planV2.targets | Where-Object target_key -ceq "f200")[0]
  $f200.source = [pscustomobject][ordered]@{candidate_commit=[string]$record200.package.source_commit;source_tree=[string]$record200.package.source_tree;common_source_commit=[string]$snapshot200.source_identity.common_source_commit}
  $f200.predecessor = New-Predecessor $manifest200 $snapshot200
  $f200.dispositions.capability_omissions = ".mir/releases/terminal/baselines/2.5.11/normalized-snapshot.json#/capability_omissions"
  $planV2.hard_boundary = "This V3 plan reconstructs private MIR 4 candidates only from the exact 3.2.11 and 2.5.11 terminal predecessors. It grants no MIR 4 semantic authority, public identity, tag, dist write, signing, sealing, upload, or publication authority."
  $null = Write-Or-Check "$authorityRoot/MIR4-Bootstrap-Local-Candidate-PlanV3.json" $planV2 $true
}

if ($Phase -in @("All", "Private")) {
  $plan = Read-Json "$authorityRoot/MIR4-Bootstrap-Local-Candidate-PlanV3.json"
  $laneV2 = Read-Json "$authorityRoot/MIR4-Private-Lane-AuthorizationV2.json"
  $laneV2.schema = 3
  $laneV2.kind = "MIR4PrivateLaneAuthorizationV3"
  $laneV2.approved_by = "explicit-maintainer-bounded-authorization-2026-08-18"
  $laneV2.supersedes = [pscustomobject][ordered]@{path="$authorityRoot/MIR4-Private-Lane-AuthorizationV2.json";record_sha256=[string](Read-Json "$authorityRoot/MIR4-Private-Lane-AuthorizationV2.json").record_sha256;disposition="historical-dot10-predecessor-authorization"}
  $planIdentity = Get-TextIdentity "$authorityRoot/MIR4-Bootstrap-Local-Candidate-PlanV3.json"
  $planIdentity.record_sha256 = [string]$plan.record_sha256
  $refreshIdentity = Get-TextIdentity "$authorityRoot/MIR4-Terminal-Predecessor-RefreshV3.json"
  $importIdentity = Get-TextIdentity "$authorityRoot/terminal-baseline-import.json"
  $importIdentity.record_sha256 = [string](Read-Json "$authorityRoot/terminal-baseline-import.json").record_sha256
  $rootIdentity = Get-TextIdentity "$authorityRoot/bootstrap-root-set.json"
  $rootIdentity.record_sha256 = [string](Read-Json "$authorityRoot/bootstrap-root-set.json").record_sha256
  $compositeIdentity = Get-TextIdentity "$authorityRoot/MIR4-Terminal-Import-CompositeV3.json"
  $laneV2.imports = [pscustomobject][ordered]@{
    candidate_plan = [pscustomobject]$planIdentity
    target_profiles = [pscustomobject](Get-TextIdentity ".mir/targets.json")
    terminal_predecessor_refresh = [pscustomobject]$refreshIdentity
    terminal_import_contract = [pscustomobject](Get-TextIdentity "$authorityRoot/MIR4-Terminal-Import-ContractV2.json")
    terminal_import = [pscustomobject]$importIdentity
    bootstrap_root_set = [pscustomobject]$rootIdentity
    terminal_import_composite = [pscustomobject]$compositeIdentity
  }
  $f200Plan = @($plan.targets | Where-Object target_key -ceq "f200")[0]
  $f200Lane = @($laneV2.authorized_targets | Where-Object target_key -ceq "f200")[0]
  $f200Lane.source_commit = [string]$f200Plan.source.candidate_commit
  $f200Lane.source_tree = [string]$f200Plan.source.source_tree
  $f200Lane.predecessor_release = [string]$f200Plan.predecessor.release
  $f200Lane.predecessor_archive_sha256 = [string]$f200Plan.predecessor.archive_sha256
  $f200Lane.predecessor_content_sha256 = [string]$f200Plan.predecessor.content_sha256
  $laneV2.hard_boundary = "This V3 private lane binds f200 to immutable 2.5.11 while f110 and f100 remain unchanged. It authorizes no public output, release identity, tag, dist write, signing, sealing, upload, or publication."
  $null = Write-Or-Check "$authorityRoot/MIR4-Private-Lane-AuthorizationV3.json" $laneV2 $true
}

Write-Host "[ok] MIR 4 .11 predecessor refresh V3 ($Phase)"
