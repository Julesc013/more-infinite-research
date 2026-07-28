param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$path = Join-Path $repo ".github/workflows/control-plane-v5.yml"
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Control Plane v5 workflow is missing." }
$workflow = Get-Content -Raw -LiteralPath $path
foreach ($token in @(
  "name: MIR Control Plane v5", "context:", "static:", "package:", "environments:", "transitions:", "ecosystem:", "performance:", "manual:",
  "verification-gate:", "name: MIR / verification-gate", "New-MIRVerificationContext.ps1",
  "-Operation record-context", "-Operation run-set", "-Operation environment", "-Operation upgrade",
  "-Operation ecosystem", "-Operation approved-delta", "-Operation performance", "-Operation aggregate",
  "-SourceRepoRoot source", "-Stage release", "-ExcludeTask shadow.equivalence", "-Kind manual", "-AggregateTaskId qualification.full",
  "proof.integration_commit", "Qualification-source commit mismatch",
  "Invoke-MIRControlPlane.ps1 backport", "Invoke-MIRControlPlane.ps1 seal", "-TaskId shadow.equivalence", "Invoke-MIRControlPlane.ps1 promotion",
  "MIR_PROTECTED_ENVIRONMENT: release-candidate", "MIR_TRUSTED_RUNNER: self-hosted-windows", "-TrustClass protected-release", "cancel-in-progress: false", "merge-multiple: true"
)) {
  if ($workflow -notmatch [regex]::Escape($token)) { throw "Control Plane v5 workflow omits required token: $token" }
}
if ($workflow -notmatch 'needs:\s*\[context,\s*static,\s*package,\s*environments,\s*transitions,\s*ecosystem,\s*performance,\s*manual\]') { throw "The final verification gate does not depend on every execution job." }
if ($workflow -notmatch 'runs-on:\s*\[self-hosted,\s*Windows\][\s\S]+?-Operation environment') { throw "Factorio environment workers are not bound to protected self-hosted Windows runners." }
if ($workflow -notmatch 'group:\s*mir-v5-performance-\$\{\{\s*inputs\.target\s*\}\}') { throw "Performance work lacks an exclusive target-scoped concurrency group." }
if ($workflow -notmatch '(?s)verification-gate:.+?runs-on:\s*\[self-hosted,\s*Windows\].+?environment:\s*release-candidate.+?-TrustClass protected-release') { throw "The aggregate execution manifest is not produced inside the protected runner environment." }
if ($workflow -notmatch '(?s)manual:.+?-Kind manual') { throw "The workflow does not fail closed on exact-candidate manual attestation." }
foreach ($operation in @("environment", "upgrade", "ecosystem", "approved-delta", "performance")) {
  if ($workflow -notmatch "(?s)-Operation $operation.+?-SourceRepoRoot source") { throw "Operation $operation is not bound to the immutable package-source checkout." }
}
if ($workflow -match '(?i)(--no-reuse|-NoReuse)') { throw "Workflow uses a global no-reuse switch instead of proposition freshness." }
$gateNames = @([regex]::Matches($workflow, '(?m)^\s+name:\s+MIR / verification-gate\s*$'))
if ($gateNames.Count -ne 1) { throw "Workflow must expose exactly one MIR / verification-gate status." }
Write-Host "[ok] v5 CI has one immutable context, exact-source native capture stages, a fail-closed manual boundary, exclusive performance, and one protected evidence-only aggregate gate."
