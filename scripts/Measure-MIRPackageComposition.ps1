param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$ArchivePath,
  [string]$BaselinePath,
  [string]$OutputPath,
  [int]$TopEntryCount = 20,
  [double]$GrowthReviewPercent = 20.0,
  [double]$RootGrowthReviewPercent = 30.0,
  [string]$Explanation,
  [switch]$RequireReviewedExplanation
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/package/Measure-MIRPackageComposition.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE