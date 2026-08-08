param(
  [string]$RepoRoot = "",
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
if (-not $OutputPath) { $OutputPath = Join-Path $RepoRoot ".mir\releases\terminal\MIR3-Dot5-Semantic-MatrixV1.json" }

function ConvertTo-CanonicalJsonBytes($Value) {
  $json = ($Value | ConvertTo-Json -Depth 100) -replace "`r`n", "`n"
  return [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
}

function Get-Sha256Bytes([byte[]]$Bytes) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-", "") } finally { $sha.Dispose() }
}

function Write-CanonicalJson([string]$Path, $Value) {
  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  [IO.File]::WriteAllBytes($Path, (ConvertTo-CanonicalJsonBytes $Value))
}

$releaseOrder = @("3.2.5", "2.5.5", "1.9.5", "1.8.5", "1.7.5", "1.6.5", "1.5.5", "1.4.5", "1.3.5")
$baselineRoot = Join-Path $RepoRoot ".mir\releases\terminal\baselines"
$inventoryDefinitions = [ordered]@{
  features = "declared\features.json"
  technologies = "declared\technologies.json"
  settings = "declared\settings.json"
  migrations = "declared\migrations.json"
  compatibility_claims = "declared\compatibility-claims.json"
}

$releaseRecords = @()
$inventories = @{}
$unresolved = @()
foreach ($release in $releaseOrder) {
  $root = Join-Path $baselineRoot $release
  $manifestPath = Join-Path $root "baseline-manifest.json"
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Missing terminal baseline manifest: $release" }
  $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100
  $identity = Get-Content -Raw -LiteralPath (Join-Path $root "identity.json") | ConvertFrom-Json -Depth 100
  $findingRecord = Get-Content -Raw -LiteralPath (Join-Path $root "reconciliation\unresolved-findings.json") | ConvertFrom-Json -Depth 100
  $unresolved += @($findingRecord.unresolved_findings | ForEach-Object { [string]$_ })
  $counts = [ordered]@{}
  $inventories[$release] = @{}
  foreach ($definition in $inventoryDefinitions.GetEnumerator()) {
    $path = Join-Path $root $definition.Value
    $inventory = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
    $inventories[$release][$definition.Key] = $inventory
    $counts[$definition.Key] = @($inventory.items).Count
  }
  $releaseRecords += [ordered]@{
    release = $release
    target = [string]$manifest.target
    archive_sha256 = [string]$identity.archive_sha256
    content_sha256 = [string]$identity.content_sha256
    baseline_root_sha256 = [string]$manifest.baseline_root_sha256
    manifest_record_sha256 = [string]$manifest.record_sha256
    completion_state = [string]$manifest.completion.state
    inventory_counts = $counts
  }
}

$matrices = [ordered]@{}
foreach ($definition in $inventoryDefinitions.GetEnumerator()) {
  $ids = @($releaseOrder | ForEach-Object { @($inventories[$_][$definition.Key].items.stable_id) } | Sort-Object -Unique)
  $rows = foreach ($id in $ids) {
    $cells = foreach ($release in $releaseOrder) {
      $inventory = $inventories[$release][$definition.Key]
      $items = @($inventory.items | Where-Object stable_id -eq $id)
      if ($items.Count -gt 1) { throw "Duplicate $($definition.Key) stable ID in ${release}: $id" }
      if ($items.Count -eq 1) {
        $item = $items[0]
        [ordered]@{
          release = $release
          target = [string]$item.target
          state = [string]$item.state
          origin = [string]$item.origin
          target_disposition = [string]$item.target_disposition
          mir4_transition_rule = [string]$item.mir4_transition_rule
          source_evidence = @($item.source_evidence | ForEach-Object { [string]$_ } | Sort-Object -Unique)
          omissions = @()
        }
      } elseif (@($inventory.fields_unavailable).Count -gt 0) {
        [ordered]@{
          release = $release
          target = [string]$inventory.target
          state = "authority-or-field-unavailable"
          origin = "explicit-baseline-omission"
          target_disposition = "explicit-capability-omission"
          mir4_transition_rule = "re-evaluate-from-terminal-authority-before-claim"
          source_evidence = @($inventory.source_evidence | ForEach-Object { [string]$_ } | Sort-Object -Unique)
          omissions = @($inventory.fields_unavailable)
        }
      } else {
        [ordered]@{
          release = $release
          target = [string]$inventory.target
          state = "not-declared-in-baseline"
          origin = "exact-declared-inventory"
          target_disposition = "not-present-in-declared-baseline"
          mir4_transition_rule = "preserve-absence-unless-new-authority-admits-change"
          source_evidence = @($inventory.source_evidence | ForEach-Object { [string]$_ } | Sort-Object -Unique)
          omissions = @()
        }
      }
    }
    [ordered]@{ stable_id = [string]$id; cells = @($cells) }
  }
  $matrices[$definition.Key] = @($rows)
}

if (@($releaseRecords | Where-Object completion_state -ne "complete").Count -ne 0 -or @($unresolved).Count -ne 0) {
  throw "The all-nine semantic matrix cannot complete while a baseline or finding remains open."
}

$material = [ordered]@{
  schema = 1
  kind = "MIR3Dot5SemanticMatrixV1"
  status = "complete"
  generated_by = [ordered]@{
    path = "scripts/Export-MIRTerminalBaselineMatrix.ps1"
    version = "2"
    sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
  }
  release_order = $releaseOrder
  releases = @($releaseRecords)
  matrices = $matrices
  unresolved_findings = @($unresolved | Sort-Object -Unique)
  completion = [ordered]@{
    all_nine_static_inventories_present = $true
    all_nine_realized_engine_inventories_complete = $true
    contradictions_classified = $true
    queue_completion_permitted = $true
  }
}
$recordSha = Get-Sha256Bytes (ConvertTo-CanonicalJsonBytes $material)
$record = [ordered]@{}
foreach ($key in $material.Keys) { $record[$key] = $material[$key] }
$record.record_sha256 = $recordSha
Write-CanonicalJson $OutputPath $record
Write-Host "[ok] wrote terminal .5 semantic matrix $OutputPath record=$recordSha status=$($record.status)"
