param(
  [Parameter(Mandatory)]
  [ValidateSet('api-check', 'api-conformance', 'sdk-generate', 'sdk-check')]
  [string]$Command,
  [string]$RepoRoot = ''
)

& (Join-Path $PSScriptRoot '../../mir/cli/Invoke-MIR4ExperimentalApi.ps1') @PSBoundParameters
