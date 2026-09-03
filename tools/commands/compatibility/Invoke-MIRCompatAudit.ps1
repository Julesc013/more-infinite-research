param(
  [string]$FactorioBin = $env:FACTORIO_BIN,
  [ValidateSet("2.0", "2.1")]
  [string]$FactorioLine = "",
  [string]$ModPortalUsername = $env:FACTORIO_USERNAME,
  [string]$ModPortalToken = $env:FACTORIO_TOKEN,
  [int]$MinDownloads = 10000,
  [string[]]$FactorioVersions = @("2.0", "2.1"),
  [switch]$IncludeSpaceAge,
  [switch]$UseCachedDownloads,
  [string]$ModCacheDir = (Join-Path $PSScriptRoot "..\..\..\build\compat-mod-cache"),
  [string]$OutputDir = (Join-Path $PSScriptRoot "..\..\..\build\results\compat-audit"),
  [string]$RuntimeRoot = $env:MIR_COMPAT_RUNTIME_ROOT,
  [int]$MaxCandidates = 50,
  [int]$CatalogPages = 0,
  [string]$FromLockfile,
  [int]$StartIndex = 0,
  [int]$Count = 0,
  [string[]]$CandidateNames = @(),
  [string[]]$LocalModZipDirs = @(),
  [string[]]$LocalModZips = @(),
  [string[]]$LocalModLibraryDirs = @(),
  [string[]]$LocalModLibraryZips = @(),
  [string[]]$LocalModNames = @(),
  [string]$ModUnderTestZip = "",
  [string]$ModUnderTestSourceCommit = "",
  [switch]$DownloadMods,
  [switch]$RunLoadTests,
  [switch]$RunManualScenarios,
  [switch]$RunLocalModZips,
  [switch]$RunGeneratedLocalScenarios,
  [switch]$GenerateLocalMegaScenario,
  [switch]$GenerateLocalClusterScenarios,
  [switch]$GenerateLocalPairwiseScenarios,
  [int]$GeneratedLocalPairwiseLimit = 40,
  [switch]$IncludeRecommendedDependencies,
  [ValidateSet("Copy", "Hardlink", "Symlink")]
  [string]$LinkMode = "Copy",
  [switch]$Offline,
  [string[]]$ScenarioNames = @(),
  [int]$ScenarioTimeoutSeconds = 900,
  [switch]$ContinueOnDependencyFailure,
  [switch]$FailFast,
  [Alias("ManualScenarios")]
  [string]$ManualScenariosPath = (Join-Path $PSScriptRoot "..\..\..\validation\scenarios\manual.json"),
  [string]$SanitationBudgetPath = (Join-Path $PSScriptRoot "..\..\..\.mir\sanitation-budgets.json"),
  [string]$KnownExclusions = (Join-Path $PSScriptRoot "..\..\..\validation\adapters\portal-exclusions.json")
)

$compatAuditCommandRoot = $PSScriptRoot
. (Join-Path $compatAuditCommandRoot 'compat-audit/Configuration.ps1')
. (Join-Path $compatAuditCommandRoot 'compat-audit/InputDiscovery.ps1')
. (Join-Path $compatAuditCommandRoot 'compat-audit/ScenarioDefinitions.ps1')
. (Join-Path $compatAuditCommandRoot 'compat-audit/ScenarioResolution.ps1')
. (Join-Path $compatAuditCommandRoot 'compat-audit/ScenarioSelection.ps1')
. (Join-Path $compatAuditCommandRoot 'compat-audit/ResultCollation.ps1')