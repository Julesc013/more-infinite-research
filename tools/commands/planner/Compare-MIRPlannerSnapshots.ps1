param(
  [Parameter(Mandatory)][string]$Before,
  [Parameter(Mandatory)][string]$After,
  [string]$OutputPath = "",
  [switch]$RequireDifferentTargets
)

$ErrorActionPreference = "Stop"

function Get-MIRRowKey {
  param($Row)
  return (@("kind", "key", "subject", "recipe", "capability", "rule", "target_stream") | ForEach-Object {
    [string]$Row.PSObject.Properties[$_].Value
  }) -join "|"
}

function Get-MIRRowMap {
  param([object[]]$Rows)
  $map = @{}
  foreach ($row in $Rows) { $map[(Get-MIRRowKey $row)] = $row }
  return $map
}

$beforeSnapshot = Get-Content -Raw -LiteralPath $Before | ConvertFrom-Json
$afterSnapshot = Get-Content -Raw -LiteralPath $After | ConvertFrom-Json
if ($beforeSnapshot.kind -ne "mir-planner-snapshot" -or $afterSnapshot.kind -ne "mir-planner-snapshot") {
  throw "Both inputs must be MIR planner snapshots."
}
if ($RequireDifferentTargets -and $beforeSnapshot.target_profile -eq $afterSnapshot.target_profile) {
  throw "Target-plan diff requires different target_profile values."
}

$beforeMap = Get-MIRRowMap -Rows @($beforeSnapshot.plan_rows)
$afterMap = Get-MIRRowMap -Rows @($afterSnapshot.plan_rows)
$added = @($afterMap.Keys | Where-Object { -not $beforeMap.ContainsKey($_) } | Sort-Object)
$removed = @($beforeMap.Keys | Where-Object { -not $afterMap.ContainsKey($_) } | Sort-Object)
$changed = @($beforeMap.Keys | Where-Object {
  $afterMap.ContainsKey($_) -and
  (($beforeMap[$_] | ConvertTo-Json -Depth 20 -Compress) -ne ($afterMap[$_] | ConvertTo-Json -Depth 20 -Compress))
} | Sort-Object)

$report = [ordered]@{
  schema = 1
  kind = "mir-planner-snapshot-diff"
  before_target = [string]$beforeSnapshot.target_profile
  after_target = [string]$afterSnapshot.target_profile
  before_fingerprint = [string]$beforeSnapshot.fingerprint_sha256
  after_fingerprint = [string]$afterSnapshot.fingerprint_sha256
  added_count = $added.Count
  removed_count = $removed.Count
  changed_count = $changed.Count
  added_keys = $added
  removed_keys = $removed
  changed_keys = $changed
}
if ($OutputPath) { $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 }
$report | ConvertTo-Json -Depth 20
