param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

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
  "Build-MIRPackage.ps1 -RepoRoot source -Target `$targetKey -CandidateId MIR4-CONTROL-PLANE -OutputDir build/packages/control-plane", "steps.package-build.outputs.archive",
  "Isolate nested source checkout from controller status", 'git rev-parse --git-path info/exclude', '-Value "/source/"',
  "Invoke-MIRControlPlane.ps1 backport", "Invoke-MIRControlPlane.ps1 seal", "-TaskId shadow.equivalence", "Invoke-MIRControlPlane.ps1 promotion",
  "MIR_PROTECTED_ENVIRONMENT: release-candidate", "MIR_TRUSTED_RUNNER: self-hosted-windows", "-TrustClass protected-release", "cancel-in-progress: false",
  "Download isolated immutable worker objects", "Import content-addressed worker objects deterministically", "-Operation import-workers",
  "-WorkerRoot build/results/control-plane-worker-evidence", "Tee-Object -FilePath build/results/control-plane-v5/worker-import.json"
)) {
  if ($workflow -notmatch [regex]::Escape($token)) { throw "Control Plane v5 workflow omits required token: $token" }
}
if ($workflow -match 'merge-multiple:\s*true') { throw "Control Plane v5 must not overlay worker artifacts into one shared tree." }
$contextDownloads = @([regex]::Matches($workflow, '(?m)^\s+name:\s+mir-v5-context\r?\n\s+path:\s+build/results\s*$'))
if ($contextDownloads.Count -ne 8) {
  throw "Every Control Plane v5 consumer must restore the context artifact beneath build/results."
}
$sourceIsolations = @([regex]::Matches($workflow, '(?m)^\s+- name:\s+Isolate nested source checkout from controller status\s*$'))
if ($sourceIsolations.Count -ne 8) {
  throw "Every Control Plane v5 nested source checkout must be excluded from controller status."
}
if ($workflow -match '(?m)^\s*run:\s*\./source/tools/commands/package/Build-MIRPackage\.ps1\s*$') {
  throw "Control Plane v5 must not create an untracked candidate archive inside the immutable source checkout."
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
$registeredPath = Join-Path $repo ".github/workflows/assurance-full.yml"
if (-not (Test-Path -LiteralPath $registeredPath -PathType Leaf)) { throw "Registered protected-workflow dispatcher is missing." }
$registered = Get-Content -Raw -LiteralPath $registeredPath
foreach ($token in @(
  "name: Assurance Full Qualification", "workflow_dispatch:", "uses: ./.github/workflows/control-plane-v5.yml",
  "source_ref: `${{ inputs.source_ref }}", "release: `${{ inputs.release }}", "target: `${{ inputs.target }}",
  "mode: `${{ inputs.mode }}", "prior_release: `${{ inputs.prior_release }}",
  "local_mod_zip_dir: `${{ inputs.local_mod_zip_dir }}", "secrets: inherit"
)) {
  if ($registered -notmatch [regex]::Escape($token)) { throw "Registered protected-workflow dispatcher omits required token: $token" }
}
if ($workflow -notmatch '(?m)^  workflow_call:\s*$' -or $workflow -notmatch '(?s)workflow_call:.+?secrets:.+?FACTORIO_BIN:.+?required:\s*true') {
  throw "Canonical Control Plane v5 workflow is not reusable through the registered dispatcher."
}
Write-Host "[ok] v5 CI has one registered reusable entry point, one immutable context, exact-source native capture stages, a fail-closed manual boundary, exclusive performance, and one protected evidence-only aggregate gate."
