param(
  [Parameter(Mandatory)][ValidateCount(2, 16)][string[]]$ReceiptPath,
  [string]$ManifestPath = ".mir/backports/2.5.0.json",
  [string]$OutputPath = "",
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../validation/tests/release/Test-MIRBackportReconstruction.ps1"
& $canonicalTest @PSBoundParameters