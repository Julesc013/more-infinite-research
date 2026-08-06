param([string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context", "Shadow", "Executor", "Release")) {
  . (Join-Path $repo "tools/lib/control/$module.ps1")
}
$release = Get-MIRCPReleaseByVersion -Release "3.2.2" -RepoRoot $repo
$candidate = Join-Path $repo ([string]$release.package.archive)
if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { & (Join-Path $repo "tools/commands/package/Build-MIRPackage.ps1") | Out-Host }
$context = New-MIRCPVerificationContext -Mode calibrate-fresh -Target "2.1" -Release "3.2.2" -Stage release `
  -CandidatePath $candidate -OutputRoot "build/results/control-plane-v5-self-test/release-contexts" -RepoRoot $repo
$state = Get-MIRCPContextExecutionState -ContextPath $context.path
foreach ($required in @("qualification.full", "protected.qualification", "seal", "shadow.equivalence", "promotion", "shadow.structural")) {
  if (@($state.plan.tasks.id) -notcontains $required) { throw "Release-stage context omitted $required." }
}
if ([string]$state.plan.stage -ne "release" -or [string]$state.plan.mode -ne "calibrate-fresh") { throw "Release-stage context lost its stage or freshness mode." }

$invalidReleaseTaskRejected = $false
try { [void](Invoke-MIRCPReleaseTaskAdmission -ContextPath $context.path -TaskId "docs.schema" -RepoRoot $repo) } catch {
  if ($_.Exception.Message -match "not a release/publication admission task") { $invalidReleaseTaskRejected = $true } else { throw }
}
if (-not $invalidReleaseTaskRejected) { throw "Release command accepted a verification-stage TaskNode." }
$wrongTargetBackportRejected = $false
try { [void](Invoke-MIRCPBackportAdmission -ContextPath $context.path -RepoRoot $repo) } catch {
  if ($_.Exception.Message -match "only to Factorio 2.0") { $wrongTargetBackportRejected = $true } else { throw }
}
if (-not $wrongTargetBackportRejected) { throw "Backport command accepted a Factorio 2.1 context." }
$sealRejected = $false
try { [void](New-MIRCPReleaseSeal -ContextPath $context.path -EvidenceRoot "build/results/control-plane-v5-self-test/empty-release-evidence" -RepoRoot $repo) } catch {
  if ($_.Exception.Message -match "requires exactly one protected qualification.full") { $sealRejected = $true } else { throw }
}
if (-not $sealRejected) { throw "Seal command accepted a context without protected qualification." }
$promotionRejected = $false
try { [void](Invoke-MIRCPPromotionAdmission -ContextPath $context.path -EvidenceRoot "build/results/control-plane-v5-self-test/empty-release-evidence" -RepoRoot $repo) } catch {
  if ($_.Exception.Message -match "requires exactly one exact passing seal") { $promotionRejected = $true } else { throw }
}
if (-not $promotionRejected) { throw "Promotion command accepted a context without seal and shadow closure." }
Write-Host "[ok] release-stage contexts contain the complete acyclic proof chain; backport, seal, and promotion commands fail closed at exact missing evidence."
