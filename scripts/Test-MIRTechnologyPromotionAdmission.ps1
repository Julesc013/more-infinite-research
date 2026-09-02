param(
  [Parameter(Mandatory)][string]$CatalogPath,
  [Parameter(Mandatory)][string]$AssessmentPath,
  [Parameter(Mandatory)][string]$ApprovalPath,
  [Parameter(Mandatory)][string]$PromotionPath,
  [Parameter(Mandatory)][string]$ProfilePath,
  [string]$MigrationPath,
  [Parameter(Mandatory)][string]$OutputPath
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../tests/compiler/Test-MIRTechnologyPromotionAdmission.ps1"
& $canonicalTest @PSBoundParameters