# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$contextSource = Get-Content -Raw -LiteralPath (Join-Path $repo "tools/lib/control/Context.ps1")
$controllerProfileBinding = '$targetProfilePath = Join-Path $repo "validation/profiles/factorio-$Target.json"'
if (-not $contextSource.Contains($controllerProfileBinding)) {
  throw "Verification context must take the mutable target profile from the controller repository, not the frozen package source."
}
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context")) {
  . (Join-Path $repo "tools/lib/control/$module.ps1")
}
$first = New-MIRCPVerificationContext -Mode calibrate-fresh -Target "2.1" -Release "3.2.2" -OutputRoot "build/results/control-plane-v5-self-test/contexts" -RepoRoot $repo
$second = New-MIRCPVerificationContext -Mode calibrate-fresh -Target "2.1" -Release "3.2.2" -OutputRoot "build/results/control-plane-v5-self-test/contexts" -RepoRoot $repo
if ([string]$first.context_id -ne [string]$second.context_id -or [int]$first.members -lt 10) { throw "Verification context materialization is not deterministic or complete." }
$manifest = Get-Content -Raw -LiteralPath (Join-Path $first.path "context-manifest.json") | ConvertFrom-Json
$memberNames = @($manifest.members.path | ForEach-Object { [string]$_ })
foreach ($required in @("plan.json", "candidate-descriptor.json", "release-transition.json", "expanded-tasks.json", "expanded-scenarios.json", "domain-manifest.json", "target-profile.json", "environment-locks.json", "control-plane-lock.json", "candidate.zip")) {
  if ($memberNames -notcontains $required) { throw "Verification context omits $required." }
}
$environmentLocks = Get-Content -Raw -LiteralPath (Join-Path $first.path "environment-locks.json") | ConvertFrom-Json
$controlLock = Get-Content -Raw -LiteralPath (Join-Path $first.path "control-plane-lock.json") | ConvertFrom-Json
if ([int]$manifest.context_abi -ne 3 -or @($environmentLocks.factorio).Count -lt 1 -or
    @($controlLock.files | Where-Object path -eq ".mir/performance-campaigns/3.2.2-C24.json").Count -ne 1 -or
    @($controlLock.files | Where-Object path -eq ".mir/control-plane/v4-v5-equivalence.json").Count -ne 1) {
  throw "Executable verification context does not bind ABI 3, a Factorio installation, its exact versioned performance campaign, and shadow cutover authority."
}
$stagedProfilePath = Join-Path $first.path "target-profile.json"
if ([string]$environmentLocks.target_profile.sha256 -ne (Get-MIRCPSha256File -Path $stagedProfilePath)) {
  throw "Environment lock does not bind the exact projected target profile."
}
$c30Release = Get-MIRCPReleaseByVersion -Release "3.2.3" -RepoRoot $repo
$baseProfile = Get-Content -Raw -LiteralPath (Join-Path $repo "validation/profiles/factorio-2.1.json") | ConvertFrom-Json
$c30Profile = Resolve-MIRCPTargetProfileForRelease -BaseProfile $baseProfile -ReleaseRecord $c30Release -RepoRoot $repo
if ([string]$c30Profile.upgrade.from_version -ne "3.2.2" -or [string]$c30Profile.upgrade.to_version -ne "3.2.3" -or
    [string]$c30Profile.upgrade.fixture -ne "assert-upgrade-3-2-2-to-3-2-3") {
  throw "C30 target-profile projection does not bind the exact governed save transition."
}
$c31Release = Get-MIRCPReleaseByVersion -Release "3.2.4" -RepoRoot $repo
$c31Profile = Resolve-MIRCPTargetProfileForRelease -BaseProfile $baseProfile -ReleaseRecord $c31Release -RepoRoot $repo
if ([string]$c31Profile.upgrade.from_version -ne "3.2.3" -or [string]$c31Profile.upgrade.to_version -ne "3.2.4" -or
    [string]$c31Profile.upgrade.fixture -ne "assert-upgrade-3-2-3-to-3-2-4") {
  throw "C31 target-profile projection does not bind the exact governed save transition."
}
$candidateRelease = Get-MIRCPReleaseByVersion -Release "3.2.5" -RepoRoot $repo
$candidateProfile = Resolve-MIRCPTargetProfileForRelease -BaseProfile $baseProfile -ReleaseRecord $candidateRelease -RepoRoot $repo
if ([string]$candidateRelease.state -notin @("candidate-qualified", "automated-qualified-awaiting-human-review", "manually-accepted", "protected-qualified", "sealed", "promoted", "tagged", "published", "publicly-verified") -or
    [string]$candidateRelease.candidate_id -ne "C32" -or
    [string]$candidateProfile.upgrade.from_version -ne "3.2.3" -or [string]$candidateProfile.upgrade.to_version -ne "3.2.5" -or
    [string]$candidateProfile.upgrade.fixture -ne "assert-upgrade-3-2-3-to-3-2-5") {
  throw "C32 target-profile projection does not bind the governed public upgrade."
}
Write-Host "[ok] immutable ABI-3 verification context $($first.context_id) contains $($first.members) digest-checked members, exact C24 bytes, historical C30/C31 projections, and the C32 public upgrade."
