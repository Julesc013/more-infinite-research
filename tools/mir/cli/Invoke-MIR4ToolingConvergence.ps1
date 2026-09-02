param(
  [Parameter(Mandatory)][ValidateSet('inventory','inventory-check')][string]$Command,
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/tooling/CommandInventory.ps1')
$result = Update-MIR4CommandInventoryV1 -RepoRoot $RepoRoot -Check:($Command -ceq 'inventory-check')
$result | ConvertTo-Json -Depth 20
