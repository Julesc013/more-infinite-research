param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$Release = "3.2.0",
  [int64]$MaximumTrackedTextBytes = 524288
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../tests/release/Test-MIREvidenceHygiene.ps1"
& $canonicalTest @PSBoundParameters