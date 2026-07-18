param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")))

$ErrorActionPreference = "Stop"
$tempPath = Join-Path ([IO.Path]::GetTempPath()) ("mir-mod-interaction-" + [guid]::NewGuid().ToString("N") + ".json")
try {
  & (Join-Path $RepoRoot "scripts\New-MIRModInteractionGraph.ps1") -OutputPath $tempPath
  $generated = Get-Content -Raw -LiteralPath $tempPath | ConvertFrom-Json
  $canonicalPath = Join-Path $RepoRoot ".mir\mod-interaction-graph.json"
  $canonical = Get-Content -Raw -LiteralPath $canonicalPath | ConvertFrom-Json
  if ($generated.graph_sha256 -ne $canonical.graph_sha256) { throw "Committed mod interaction graph is stale." }
  if ($generated.summary.node_count -ne 4 -or $generated.summary.pair_count -ne 6 `
      -or $generated.summary.overlapping_pair_count -ne 2 -or $generated.summary.blocked_pair_count -ne 0) {
    throw "Mod interaction graph summary differs from the reviewed four-capsule campaign."
  }

  $campaigns = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\combination-campaigns.json") | ConvertFrom-Json
  $scenarioManifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures\compat-matrix\expected-scenarios.json")
  foreach ($campaign in @($campaigns.campaigns)) {
    $pairId = @($campaign.capsules | ForEach-Object {[string]$_} | Sort-Object) -join "+x+"
    $pair = @($generated.pairs | Where-Object {$_.pair_id -eq $pairId})
    if ($pair.Count -ne 1 -or $pair[0].classification -ne $campaign.classification) {
      throw "Combination campaign classification does not match graph: $($campaign.campaign_id)"
    }
    if (-not $scenarioManifest.Contains(('"name": "' + [string]$campaign.scenario + '"'))) {
      throw "Combination campaign scenario is not declared: $($campaign.scenario)"
    }
    if ($campaign.classification -like "targeted-*") {
      if ([string]::IsNullOrWhiteSpace([string]$campaign.delta_policy) -or $pair[0].delta_policy -ne $campaign.delta_policy) {
        throw "Overlapping combination campaign lacks its narrow delta policy: $($campaign.campaign_id)"
      }
    }
  }
} finally {
  if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
}

Write-Host "[ok] MIR semantic mod interactions, narrow deltas, and combination campaigns are complete."
