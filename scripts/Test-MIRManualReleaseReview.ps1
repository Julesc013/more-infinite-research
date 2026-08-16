param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$Path = "",
  [Parameter(Mandatory)][string]$Candidate,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ExpectedSourceCommit,
  [Parameter(Mandatory)][string]$ExpectedFactorioVersion
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../validation/tests/release/Test-MIRManualReleaseReview.ps1"
& $canonicalTest @PSBoundParameters