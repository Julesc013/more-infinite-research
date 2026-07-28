param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}
$first = New-MIRCPVerificationContext -Mode calibrate-fresh -Target "2.1" -Release "3.2.2" -OutputRoot "out/control-plane-v5-self-test/contexts" -RepoRoot $repo
$second = New-MIRCPVerificationContext -Mode calibrate-fresh -Target "2.1" -Release "3.2.2" -OutputRoot "out/control-plane-v5-self-test/contexts" -RepoRoot $repo
if ([string]$first.context_id -ne [string]$second.context_id -or [int]$first.members -lt 10) { throw "Verification context materialization is not deterministic or complete." }
$manifest = Get-Content -Raw -LiteralPath (Join-Path $first.path "context-manifest.json") | ConvertFrom-Json
$memberNames = @($manifest.members.path | ForEach-Object { [string]$_ })
foreach ($required in @("plan.json", "candidate-descriptor.json", "release-transition.json", "expanded-tasks.json", "expanded-scenarios.json", "domain-manifest.json", "target-profile.json", "environment-locks.json", "control-plane-lock.json", "candidate.zip")) {
  if ($memberNames -notcontains $required) { throw "Verification context omits $required." }
}
Write-Host "[ok] immutable verification context $($first.context_id) contains $($first.members) digest-checked members and exact C24 candidate bytes."
