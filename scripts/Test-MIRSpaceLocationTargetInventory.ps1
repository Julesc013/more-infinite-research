param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../tests/compiler/Test-MIRSpaceLocationTargetInventory.ps1"
& $canonicalTest @PSBoundParameters