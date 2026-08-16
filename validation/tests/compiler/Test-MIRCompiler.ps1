param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../.."))
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

& (Join-Path $repo "validation\tests\compiler\Test-MIRCompilerSchemaDrift.ps1") -RepoRoot $repo
& (Join-Path $repo "validation\tests\compiler\Test-MIRCompilerContractCoverage.ps1") -RepoRoot $repo
& (Join-Path $repo "validation\tests\architecture\Test-MIRModuleDependencies.ps1") -RepoRoot $repo

Write-Host "[ok] MIR compiler schema, authority, contract coverage, dependencies, and mutation sentinels passed."
