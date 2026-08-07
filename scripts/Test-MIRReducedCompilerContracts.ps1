param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")))

$ErrorActionPreference = "Stop"
$info = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "info.json") | ConvertFrom-Json
if ([string]$info.factorio_version -notin @("0.16", "0.17", "0.18", "1.0", "1.1")) {
  throw "Reduced compiler contracts apply only to the maintained Factorio 0.16-1.1 lines."
}

$manifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\streams\generated_stream_manifest.json") | ConvertFrom-Json
$streamRows = @($manifest.streams.PSObject.Properties)
if ([int]$manifest.schema -ne 1 -or $streamRows.Count -lt 1) {
  throw "Reduced compiler requires a non-empty schema-1 stable stream manifest."
}
foreach ($row in $streamRows) {
  if (-not [bool]$row.Value.stable -or [string]::IsNullOrWhiteSpace([string]$row.Value.stream_key)) {
    throw "Stable stream manifest row is incomplete: $($row.Name)"
  }
}

$contracts = @(
  @{Path="prototypes\mir\planner\stream_compiler.lua"; Markers=@("research_cost_classification.anchor_level", "costs.model_for", "cost_model.count_formula")},
  @{Path="prototypes\mir\planner\costs.lua"; Markers=@("research_cost_model.new", "function M.model_for")},
  @{Path="prototypes\mir\emit\base_extensions.lua"; Markers=@("research_cost_model.new", "count_formula = cost_model.count_formula")},
  @{Path="prototypes\mir\settings\cost_contract.lua"; Markers=@('M.formula_abi = "mir-research-cost-v1"', "linear_increment", "growth_factor")},
  @{Path="prototypes\mir\domain\research_cost\formula.lua"; Markers=@('"fixed"', '"linear"', '"exponential"', '"hybrid"')}
)
foreach ($contract in $contracts) {
  $text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $contract.Path)
  foreach ($marker in $contract.Markers) {
    if (-not $text.Contains($marker)) { throw "$($contract.Path) is missing reduced compiler contract marker: $marker" }
  }
}

Write-Host "[ok] MIR reduced compiler stable IDs and unified research-cost integration passed for Factorio $($info.factorio_version)."
