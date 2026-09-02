param(
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$CandidateZip,
  [string]$PriorZip,
  [string]$OutputRoot,
  [int]$TimeoutSeconds = 180
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../tests/package/Test-MIRCandidateRetention.ps1"
& $canonicalTest @PSBoundParameters