param(
  [ValidateSet('f210','f200','f110','f100')][string]$Target = 'f210',
  [ValidatePattern('^[A-Z0-9][A-Z0-9.-]*$')][string]$CandidateId = 'MIR4-ORDINARY-BUILD',
  [string]$SourceVersion,
  [string]$DistributionVersion,
  [string]$OutputDir = 'build/packages/ordinary',
  [ValidateSet('Optimal')][string]$CompressionLevel = 'Optimal'
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/package/Build-MIRPackage.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE
