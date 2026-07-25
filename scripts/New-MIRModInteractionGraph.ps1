param(
  [string]$PolicyPath = ".mir\mod-interaction-policy.json",
  [string]$OutputPath = ".mir\mod-interaction-graph.json"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Resolve-MIRPath {
  param([string]$Path)
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  return [IO.Path]::GetFullPath((Join-Path $repo $Path))
}

function Get-MIRTextSha256 {
  param([string]$Text)
  $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "") }
  finally { $sha.Dispose() }
}

$policyFile = Resolve-MIRPath $PolicyPath
$policy = Get-Content -Raw -LiteralPath $policyFile | ConvertFrom-Json
if ($policy.schema -ne 1 -or $policy.kind -ne "mir-mod-interaction-policy") {
  throw "Mod interaction policy must be schema 1."
}
$capsulesFile = Resolve-MIRPath ([string]$policy.capsules)
$deltaFile = Resolve-MIRPath ([string]$policy.delta_policies)
$capsules = Get-Content -Raw -LiteralPath $capsulesFile | ConvertFrom-Json
$deltas = Get-Content -Raw -LiteralPath $deltaFile | ConvertFrom-Json
if ($capsules.schema -ne 1 -or $deltas.schema -ne 1) { throw "Mod interaction inputs must be schema 1." }

$dimensions = @($policy.footprint_dimensions | ForEach-Object { [string]$_ } | Sort-Object -Unique)
$nodes = @($capsules.capsules | Sort-Object id)
$ids = @{}
foreach ($node in $nodes) {
  $id = [string]$node.id
  if ([string]::IsNullOrWhiteSpace($id) -or $ids.ContainsKey($id)) { throw "Support capsule id is missing or duplicated: $id" }
  $ids[$id] = $true
  foreach ($dimension in $dimensions) {
    if ($null -eq $node.footprints.PSObject.Properties[$dimension]) { throw "Support capsule $id omits footprint dimension $dimension." }
  }
}

$deltaByPair = @{}
foreach ($delta in @($deltas.policies)) {
  $pair = @($delta.capsules | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  if ($pair.Count -ne 2 -or $delta.copies_full_capsule_policy -ne $false) {
    throw "Interaction delta policy must bind exactly two capsules and remain narrow: $($delta.policy_id)"
  }
  $pairId = $pair -join "+x+"
  if ($deltaByPair.ContainsKey($pairId)) { throw "Duplicate interaction delta policy pair: $pairId" }
  $deltaByPair[$pairId] = $delta
}

$pairs = @()
for ($leftIndex = 0; $leftIndex -lt $nodes.Count; $leftIndex++) {
  for ($rightIndex = $leftIndex + 1; $rightIndex -lt $nodes.Count; $rightIndex++) {
    $left, $right = $nodes[$leftIndex], $nodes[$rightIndex]
    $pairId = @([string]$left.id, [string]$right.id) -join "+x+"
    $shared = @()
    foreach ($dimension in $dimensions) {
      $leftValues = @($left.footprints.$dimension | ForEach-Object { [string]$_ })
      $rightValues = @($right.footprints.$dimension | ForEach-Object { [string]$_ })
      foreach ($value in @($leftValues | Where-Object { $_ -in $rightValues } | Sort-Object -Unique)) {
        $shared += "$dimension`:$value"
      }
    }
    $overlap = $shared.Count -gt 0
    $delta = if ($deltaByPair.ContainsKey($pairId)) { $deltaByPair[$pairId] } else { $null }
    $classification = if (-not $overlap) {
      "independent-composition-smoke"
    } elseif ($delta) {
      "targeted-interaction-campaign-with-narrow-delta"
    } else {
      "BLOCKED_MISSING_DELTA_POLICY"
    }
    if ($delta) {
      $declaredShared = @($delta.shared_footprints | ForEach-Object { [string]$_ } | Sort-Object -Unique)
      if (@(Compare-Object @($shared | Sort-Object -Unique) $declaredShared).Count -ne 0) {
        throw "Interaction delta policy shared footprint drift: $($delta.policy_id)"
      }
    }
    $pairs += [ordered]@{
      pair_id = $pairId
      capsules = @([string]$left.id, [string]$right.id)
      overlap = $overlap
      shared_footprints = @($shared | Sort-Object -Unique)
      classification = $classification
      delta_policy = if ($delta) { [string]$delta.policy_id } else { $null }
    }
  }
}

$graph = [ordered]@{
  schema = 1
  kind = "mir-semantic-mod-interaction-graph"
  nodes = @($nodes | ForEach-Object {
    [ordered]@{id=[string]$_.id; exact_mods=@($_.exact_mods); evidence=@($_.evidence); footprints=$_.footprints}
  })
  pairs = $pairs
  summary = [ordered]@{
    node_count = $nodes.Count
    pair_count = $pairs.Count
    overlapping_pair_count = @($pairs | Where-Object {$_.overlap}).Count
    independent_pair_count = @($pairs | Where-Object {-not $_.overlap}).Count
    blocked_pair_count = @($pairs | Where-Object {$_.classification -eq "BLOCKED_MISSING_DELTA_POLICY"}).Count
  }
  input_hash_basis = "canonical-json"
  policy_sha256 = Get-MIRTextSha256 (($policy | ConvertTo-Json -Depth 100 -Compress))
  capsules_sha256 = Get-MIRTextSha256 (($capsules | ConvertTo-Json -Depth 100 -Compress))
  delta_policies_sha256 = Get-MIRTextSha256 (($deltas | ConvertTo-Json -Depth 100 -Compress))
}
$graph.graph_sha256 = Get-MIRTextSha256 (($graph | ConvertTo-Json -Depth 100 -Compress))
$destination = Resolve-MIRPath $OutputPath
$parent = Split-Path -Parent $destination
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$graph | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $destination -Encoding UTF8
Write-Host "[ok] wrote MIR interaction graph $destination nodes=$($nodes.Count) overlap=$($graph.summary.overlapping_pair_count) blocked=$($graph.summary.blocked_pair_count)"
