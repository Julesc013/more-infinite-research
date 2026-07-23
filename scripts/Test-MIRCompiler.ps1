param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

& (Join-Path $repo "scripts\Test-MIRCompilerSchemaDrift.ps1") -RepoRoot $repo
& (Join-Path $repo "scripts\Test-MIRCompilerContractCoverage.ps1") -RepoRoot $repo
& (Join-Path $repo "scripts\Test-MIRModuleDependencies.ps1") -RepoRoot $repo

Write-Host "[ok] MIR compiler schema, authority, contract coverage, dependencies, and mutation sentinels passed."
