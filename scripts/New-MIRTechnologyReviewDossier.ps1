param(
  [Parameter(Mandatory)][string]$CatalogPath,
  [Parameter(Mandatory)][string]$CandidateId,
  [string]$AssessmentPath,
  [Parameter(Mandatory)][string]$OutputPath
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/technology/New-MIRTechnologyReviewDossier.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE