param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"
$manifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\streams\generated_stream_manifest.json") | ConvertFrom-Json
$golden = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "fixtures\golden-plans\stable-technology-ids.json") | ConvertFrom-Json

if ($golden.schema -ne 1 -or $golden.baseline -ne "immutable-3.1.0") {
  throw "Stable technology golden plan has an unsupported schema or baseline."
}
$actual = @($manifest.streams.PSObject.Properties.Name | Sort-Object)
$expected = @($golden.technology_ids | ForEach-Object { [string]$_ } | Sort-Object)
if ($actual.Count -ne 70 -or $expected.Count -ne 70) {
  throw "Stable technology golden plan must preserve exactly 70 released identities."
}
if (($actual -join "`n") -ne ($expected -join "`n")) {
  throw "Generated technology identities differ from the immutable 3.1.0 golden plan."
}

Write-Host "[ok] MIR stable technology golden plan preserves 70 released identities."

