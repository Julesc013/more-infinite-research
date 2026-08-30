param(
  [Parameter(Mandatory)][ValidateSet('init','validate','explain','test','package','migrate','doctor','lock','diff','ci-init','discover')][string]$Command,
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$ExtensionPath='',
  [string]$OutputRoot='build/mir4/extension-builder',
  [string]$ExtensionId='org.example.extension',
  [ValidateSet('minimal','all-fragments','unavailable')][string]$Template='minimal',
  [string]$BasePath='',
  [string]$CandidatePath='',
  [string]$DiscoveryPath='',
  [ValidatePattern('^f[0-9]{3}$')][string]$Target=''
)

& (Join-Path $PSScriptRoot '../../mir/cli/Invoke-MIR4Extension.ps1') @PSBoundParameters
