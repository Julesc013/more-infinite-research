param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$Path = "",
  [Parameter(Mandatory)][string]$Candidate,
  [Parameter(Mandatory)][string]$PriorRelease,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ExpectedSourceCommit,
  [Parameter(Mandatory)][string]$ExpectedBaselineVersion,
  [Parameter(Mandatory)][string]$ExpectedFactorioVersion,
  [string]$CampaignPath = ""
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../tests/release/Test-MIRPerformanceRegression.ps1"
& $canonicalTest @PSBoundParameters
