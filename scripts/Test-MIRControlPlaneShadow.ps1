param(
  [string]$ContextPath = "",
  [string]$SourceRepoRoot = "",
  [string]$EvidenceRoot = "build/results/evidence",
  [switch]$ContractOnly,
  [switch]$StructuralOnly,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../validation/tests/tooling/Test-MIRControlPlaneShadow.ps1"
& $canonicalTest @PSBoundParameters