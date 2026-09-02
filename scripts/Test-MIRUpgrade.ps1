param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$FromZip,
  [Parameter(Mandatory)][string]$ToZip,
  [string]$FromVersion = "3.0.5",
  [string]$ToVersion = "3.1.0",
  [string]$FixtureName = "assert-upgrade-3-0-5-to-3-1-0",
  [ValidateSet("", "base-default", "space-age-native-owner", "automatic-family-creation", "base-continuations", "mod-set-configuration-change", "affected-planet-discovery")]
  [string]$Archetype = "",
  [string[]]$SourceOnlyFixtureNames = @(),
  [string]$OutputPath = ""
)

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$canonicalTest = Join-Path $PSScriptRoot "../tests/runtime/Test-MIRUpgrade.ps1"
& $canonicalTest @PSBoundParameters