[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$RepoRoot = "",
  [ValidateRange(0, 3650)]
  [int]$OlderThanDays = 7,
  [switch]$AllWorktrees,
  [switch]$Apply,
  [switch]$PassThru,
  [Parameter(DontShow)]
  [switch]$SkipActiveProcessCheck
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/workspace/Remove-MIRStaleArtifacts.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE