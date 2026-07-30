param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"
$manifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\streams\generated_stream_manifest.json") | ConvertFrom-Json
$golden = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures\golden-plans\stable-technology-ids.json") | ConvertFrom-Json
$automatic = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures\golden-plans\automatic-family-technology-ids.json") | ConvertFrom-Json
$release320 = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures\golden-plans\3.2.0-technology-ids.json") | ConvertFrom-Json

if ($golden.schema -ne 1 -or $golden.baseline -ne "immutable-3.0.5") {
  throw "Stable technology golden plan has an unsupported schema or baseline."
}
$actual = @($manifest.streams.PSObject.Properties.Name | Sort-Object)
$expected = @($golden.technology_ids | ForEach-Object { [string]$_ } | Sort-Object)
if ($expected.Count -ne 71) {
  throw "Stable technology golden plan must preserve the 70 prior identities plus the registered 3.2.3 Platform Productivity identity."
}
foreach ($stableId in $expected) {
  if ($stableId -notin $actual) {
    throw "Generated technology identities dropped immutable 3.0.5 id $stableId."
  }
}
if ($automatic.schema -ne 1 -or $automatic.release -ne "3.1.0") {
  throw "Automatic family technology golden plan has an unsupported schema or release."
}
$automaticIds = @($automatic.technology_ids | ForEach-Object { [string]$_ } | Sort-Object)
if ($release320.schema -ne 1 -or $release320.release -ne "3.2.0" `
    -or $release320.identity_state -ne "stable-unreleased") {
  throw "3.2.0 technology golden plan has an unsupported schema, release, or identity state."
}
$release320Ids = @($release320.technology_ids | ForEach-Object { [string]$_ } | Sort-Object)
if ($release320Ids.Count -ne 3 -or
    "recipe-prod-research_capture_robot_rockets-1" -notin $release320Ids -or
    "recipe-prod-research_nutrients-1" -notin $release320Ids -or
    "recipe-prod-research_steel-1" -notin $release320Ids) {
  throw "3.2.0 technology golden plan must reserve exactly Steel, Nutrients, and Capture bot rocket productivity."
}
$combined = @($expected + $automaticIds + $release320Ids | Sort-Object -Unique)
if ($actual.Count -ne $combined.Count -or ($actual -join "`n") -ne ($combined -join "`n")) {
  throw "Generated technology identities differ from the immutable plus release-scoped golden plans."
}

Write-Host "[ok] MIR golden plans preserve 70 baseline, $($automaticIds.Count) predeclared 3.1 automatic-family, and $($release320Ids.Count) 3.2 identities."
