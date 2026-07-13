param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"
$manifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\streams\generated_stream_manifest.json") | ConvertFrom-Json
$golden = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures\golden-plans\stable-technology-ids.json") | ConvertFrom-Json
$automatic = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures\golden-plans\automatic-family-technology-ids.json") | ConvertFrom-Json

if ($golden.schema -ne 1 -or $golden.baseline -ne "immutable-3.0.5") {
  throw "Stable technology golden plan has an unsupported schema or baseline."
}
$actual = @($manifest.streams.PSObject.Properties.Name | Sort-Object)
$expected = @($golden.technology_ids | ForEach-Object { [string]$_ } | Sort-Object)
if ($expected.Count -ne 70) {
  throw "Stable technology golden plan must preserve exactly 70 released identities."
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
$combined = @($expected + $automaticIds | Sort-Object -Unique)
if ($actual.Count -ne $combined.Count -or ($actual -join "`n") -ne ($combined -join "`n")) {
  throw "Generated technology identities differ from the immutable plus predeclared automatic-family golden plans."
}

Write-Host "[ok] MIR golden plans preserve 70 baseline and $($automaticIds.Count) predeclared 3.1 automatic-family identities."
