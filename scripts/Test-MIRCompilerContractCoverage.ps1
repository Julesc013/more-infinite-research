param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")))
$ErrorActionPreference = "Stop"
$manifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\compiler-contract-coverage.yml") | ConvertFrom-Json
if ($manifest.schema -ne 1 -or -not $manifest.positive_negative_required) { throw "Compiler contract coverage manifest is invalid." }
foreach ($field in @("generation_plan_gates", "actions", "family_strategies", "compatibility_pack_fields", "automatic_actions", "automatic_generation_controls", "legacy_automatic_modes", "mutation_sentinels")) {
  if (@($manifest.$field).Count -eq 0) { throw "Compiler contract coverage omits $field." }
}
$expectedActions = @("disabled", "preview", "apply")
if (@(Compare-Object $expectedActions @($manifest.automatic_actions)).Count -ne 0) { throw "Automatic action contract coverage is incomplete." }
if (($expectedActions -join "|") -ne (@($manifest.automatic_actions) -join "|")) { throw "Automatic actions must stay ordered from no changes to applied changes." }
$contract = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "prototypes\mir\settings\automatic_compiler_contract.lua")
foreach ($snippet in @(
  'M.actions = {"disabled", "preview", "apply"}',
  'M.legacy_modes = {"off", "report", "safe-attach", "exact-pack", "safe-generate"}',
  'create_research = "mir-automatic-create-research"',
  'require_reviewed_data = "mir-automatic-require-reviewed-data"'
)) {
  if (-not $contract.Contains($snippet)) { throw "Automatic compiler contract is missing: $snippet" }
}
$fixture = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $manifest.runtime_fixture)
foreach ($sentinel in @("hard-safety sentinel", "duplicate materialized effect", "missing prerequisite sentinel", "numeric effect value")) {
  if (-not $fixture.Contains($sentinel)) { throw "Compiler contract fixture is missing mutation sentinel: $sentinel" }
}
Write-Host "[ok] MIR compiler contract coverage and mutation sentinels are declared."
