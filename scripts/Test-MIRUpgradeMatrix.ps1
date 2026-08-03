param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$FromZip,
  [Parameter(Mandatory)][string]$ToZip,
  [Parameter(Mandatory)][string]$FromVersion,
  [Parameter(Mandatory)][string]$ToVersion,
  [string]$FixtureName = "assert-upgrade-3-2-1-to-3-2-2",
  [string]$OutputPath = ".work/artifacts/assurance/3.2.2-upgrade-proof.json"
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../validation/tests/runtime/Test-MIRUpgradeMatrix.ps1"
& $canonicalTest @PSBoundParameters