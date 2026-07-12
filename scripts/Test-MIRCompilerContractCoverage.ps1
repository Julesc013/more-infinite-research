param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")))
$ErrorActionPreference = "Stop"
$manifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\compiler-contract-coverage.yml") | ConvertFrom-Json
if ($manifest.schema -ne 1 -or -not $manifest.positive_negative_required) { throw "Compiler contract coverage manifest is invalid." }
foreach ($field in @("generation_plan_gates", "actions", "family_strategies", "compatibility_pack_fields", "automatic_modes", "mutation_sentinels")) {
  if (@($manifest.$field).Count -eq 0) { throw "Compiler contract coverage omits $field." }
}
$expectedModes = @("off", "report", "safe-attach", "safe-generate", "exact-pack")
if (@(Compare-Object $expectedModes @($manifest.automatic_modes)).Count -ne 0) { throw "Automatic mode contract coverage is incomplete." }
$fixture = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $manifest.runtime_fixture)
foreach ($sentinel in @("hard-safety sentinel", "duplicate materialized effect", "missing prerequisite sentinel", "numeric effect value")) {
  if (-not $fixture.Contains($sentinel)) { throw "Compiler contract fixture is missing mutation sentinel: $sentinel" }
}
Write-Host "[ok] MIR compiler contract coverage and mutation sentinels are declared."
