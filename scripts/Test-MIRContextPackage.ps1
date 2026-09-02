param(
  [Parameter(Mandatory)][string]$ContextPath,
  [Parameter(Mandatory)][string]$SourceRepoRoot,
  [Parameter(Mandatory)][ValidateSet("identity", "composition", "determinism")][string]$Check,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../tests/package/Test-MIRContextPackage.ps1"
& $canonicalTest @PSBoundParameters