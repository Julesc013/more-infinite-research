param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [string]$OutputRoot = "",
  [switch]$CheckThresholds,
  [int]$MaxMirLegacyActiveModules = 0,
  [int]$MaxRequiresMirLegacy = 0,
  [int]$MaxCompatActiveModules = 0,
  [int]$MaxRequiresCompat = 0,
  [int]$MaxLibActiveModules = 0,
  [int]$MaxRequiresLib = 0,
  [int]$MaxRequiresConfig = 0,
  [int]$MaxRequiresUtil = 0,
  [int]$MaxRequiresDiagnostics = 0,
  [int]$MaxShimDirectoriesPresent = 0,
  [int]$MaxOldRootHelperFilesPresent = 0,
  [int]$MaxRuntimeControlLuaFiles = 0,
  [int]$MaxDataExtendOutsideAllowed = 0,
  [int]$MaxDataRawOutsidePlatform = 0,
  [int]$MaxGeneratedStreamsWithoutManifest = 0
)

# MIR-L5-LEGACY-COMMAND-WRAPPER: retained for historical command compatibility only.
$canonicalCommand = Join-Path $PSScriptRoot "../tools/commands/workspace/Get-MIRLegacyInventory.ps1"
& $canonicalCommand @PSBoundParameters
exit $LASTEXITCODE