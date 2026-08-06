param(
  [Parameter(Mandatory)][ValidateSet("manual", "protected", "seal", "backport", "promotion", "tag", "publication", "public-byte")][string]$Obligation,
  [Parameter(Mandatory)][string]$ContextPath,
  [string]$EvidenceRoot = "build/results/evidence",
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../validation/tests/release/Test-MIRReleaseObligation.ps1"
& $canonicalTest @PSBoundParameters