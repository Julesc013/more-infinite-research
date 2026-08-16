param(
  [string]$RepoRoot = "",
  [string]$ManifestPath = ".mir/releases/backports/2.5.0.json",
  [switch]$AllowPendingTags
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../validation/tests/release/Test-MIRBackportManifest.ps1"
& $canonicalTest @PSBoundParameters