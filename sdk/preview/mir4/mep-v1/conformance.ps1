param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/ExtensionDeveloperExperience.ps1')
$value=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'sdk/preview/mir4/mep-v1/examples/positive/extension.json')|ConvertFrom-Json -Depth 100
Test-MIR4MepV1Envelope -Envelope $value -RepoRoot $RepoRoot|Out-Null
$closure=Resolve-MIR4ExtensionClosureV1 -RepoRoot $RepoRoot -Extensions @($value) -Target f210
$doctor=Get-MIR4ExtensionDoctorV1 -RepoRoot $RepoRoot -Envelope $value
$lock=New-MIR4ExtensionLockV1 -RepoRoot $RepoRoot -Envelope $value -Target f210
$diff=New-MIR4ExtensionDiffV1 -RepoRoot $RepoRoot -Base $value -Candidate $value
$plan=New-MIR4ExtensionShadowPlanV1 -RepoRoot $RepoRoot -Envelope $value -Target f210
if([string]$doctor.status-cne'passed'-or-not[bool]$closure.complete-or[string]$diff.status-cne'identical'-or[string]$plan.result-cne'shadow-complete'){throw '[mir4-mep-v1-conformance]'}
[pscustomobject]@{
  status='passed';maturity='developer-preview';commands=11;offline=$true
  lock_status=[string]$lock.status;player_mutation_authorized=$false;prototype_write_authorized=$false
  production_consumer='BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER'
}|ConvertTo-Json