[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SourceArchive,

  [Parameter(Mandatory = $true)]
  [string]$OutputArchive,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^\d+\.\d+$')]
  [string]$ExpectedSourceFactorioVersion,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^\d+\.\d+$')]
  [string]$TargetFactorioVersion,

  [string]$ManifestPath
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/compatibility/New-MIRFactorioLineTestAdapter.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE