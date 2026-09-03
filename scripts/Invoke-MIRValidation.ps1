param(
  [string]$FactorioBin = $env:FACTORIO_BIN,
  [string]$FactorioLog = $env:FACTORIO_LOG,
  [string]$UserDataDir = $env:FACTORIO_USERDATA,
  [string]$CandidateZip = "",
  [switch]$DocsOnly,
  [switch]$ManifestsOnly,
  [switch]$ArchitectureOnly,
  [switch]$StaticOnly,
  [switch]$ScenarioWorker,
  [string[]]$Scenario = @(),
  [string[]]$Group = @(),
  [string[]]$Tag = @(),
  [ValidateSet("", "pure", "static", "smoke", "impacted", "full")]
  [string]$Tier = "",
  [string]$ChangedSince = "",
  [ValidateSet("", "space-age-native-owner-settings-default", "space-age-vanilla-family-mixed-owner")]
  [string]$StartAtScenario = "",
  [ValidateRange(1, 4)][int]$MaxParallel = 1,
  [switch]$List,
  [string]$ValidationSummaryPath = $env:MIR_VALIDATION_SUMMARY
)

. (Join-Path $PSScriptRoot "../tools/lib/validation/runner/Invoke-MIRValidationRunner.ps1")
