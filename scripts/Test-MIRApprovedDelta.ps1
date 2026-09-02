param(
  [string]$Path = ".mir\releases\deltas\3.2.1-to-3.2.2.json",
  [string]$Candidate = "dist\more-infinite-research_3.2.2.zip",
  [string]$ExpectedSourceCommit = "",
  [switch]$ValidateStructureOnly
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../tests/release/Test-MIRApprovedDelta.ps1"
& $canonicalTest @PSBoundParameters
