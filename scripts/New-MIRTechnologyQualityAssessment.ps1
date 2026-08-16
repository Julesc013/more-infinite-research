param(
  [Parameter(Mandatory)][string]$CatalogPath,
  [Parameter(Mandatory)][string]$CandidateId,
  [Parameter(Mandatory)][string]$ProfilePath,
  [Parameter(Mandatory)][string]$ProfileId,
  [string]$MetricsPath,
  [Parameter(Mandatory)][string]$OutputPath
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/technology/New-MIRTechnologyQualityAssessment.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE