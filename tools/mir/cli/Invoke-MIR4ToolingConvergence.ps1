param(
  [Parameter(Mandatory)][ValidateSet('inventory','inventory-check','test-authority','test-authority-check','tests','tests-check','workflows','workflows-check')][string]$Command,
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/tooling/CommandInventory.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/tooling/ExecutableTestAuthority.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/tooling/TestWorkflowCatalogues.ps1')
$result = switch ($Command) {
  'inventory' { Update-MIR4CommandInventoryV1 -RepoRoot $RepoRoot }
  'inventory-check' { Update-MIR4CommandInventoryV1 -RepoRoot $RepoRoot -Check }
  'test-authority' { Update-MIR4ExecutableTestAuthorityProjectionsV1 -RepoRoot $RepoRoot }
  'test-authority-check' { Update-MIR4ExecutableTestAuthorityProjectionsV1 -RepoRoot $RepoRoot -Check }
  'tests' { Update-MIR4ToolingCatalogueV1 -RepoRoot $RepoRoot -Catalogue tests }
  'tests-check' { Update-MIR4ToolingCatalogueV1 -RepoRoot $RepoRoot -Catalogue tests -Check }
  'workflows' { Update-MIR4ToolingCatalogueV1 -RepoRoot $RepoRoot -Catalogue workflows }
  'workflows-check' { Update-MIR4ToolingCatalogueV1 -RepoRoot $RepoRoot -Catalogue workflows -Check }
}
$result | ConvertTo-Json -Depth 20
