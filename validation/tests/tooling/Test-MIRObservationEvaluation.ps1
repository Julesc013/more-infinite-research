param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo "tools/lib/control/Core.ps1")
. (Join-Path $repo "tools/lib/control/Scenario.ps1")
. (Join-Path $repo "tools/lib/control/Observation.ps1")

$candidate = "A" * 64
$environment = "B" * 64
$observation = New-MIRCPObservation -Kind environment-capture -EnvironmentSignature $environment -Target "test" -CandidateSha256 $candidate -Facts ([pscustomobject][ordered]@{status="passed"; value=7}) -Source ([pscustomobject][ordered]@{test="identity-split"})
$sameObservation = New-MIRCPObservation -Kind environment-capture -EnvironmentSignature $environment -Target "test" -CandidateSha256 $candidate -Facts ([pscustomobject][ordered]@{status="passed"; value=7}) -Source ([pscustomobject][ordered]@{test="identity-split"})
if ((Get-MIRCPSha256Object -Value $observation) -ne (Get-MIRCPSha256Object -Value $sameObservation)) { throw "Canonical observations are nondeterministic." }
$passing = [pscustomobject][ordered]@{schema=1; id="assertion/test/value-seven"; version=1; type="field-equals"; reads=@("facts.value"); field="facts.value"; proposition="Captured value is seven."; expected=7}
$failing = [pscustomobject][ordered]@{schema=1; id="assertion/test/value-eight"; version=1; type="field-equals"; reads=@("facts.value"); field="facts.value"; proposition="Captured value is eight."; expected=8}
$passEvaluation = Invoke-MIRCPEvaluation -Observation $observation -Assertion $passing
$failEvaluation = Invoke-MIRCPEvaluation -Observation $observation -Assertion $failing
if ([string]$passEvaluation.status -ne "passed" -or [string]$failEvaluation.status -ne "failed") { throw "Pure evaluation did not distinguish passing and failing assertions." }
if ([string]$passEvaluation.observation_sha256 -ne [string]$failEvaluation.observation_sha256 -or [string]$passEvaluation.evaluation_key -eq [string]$failEvaluation.evaluation_key) {
  throw "Observation and evaluation identities are not independent."
}
$missing = [pscustomobject][ordered]@{schema=1; id="assertion/test/missing"; version=1; type="captured-proposition"; reads=@("facts.absent.status"); proposition="Missing fact stays invalid."; expected="passed"}
if ([string](Invoke-MIRCPEvaluation -Observation $observation -Assertion $missing).status -ne "invalid") { throw "Missing captured facts did not fail closed." }
$replay = Update-MIRCPV4ReplayReport -RepoRoot $repo -Check
if ([string]$replay.verdict -ne "passed" -or [int]$replay.metrics.source_evidence -ne 130 -or [int]$replay.metrics.observations -ne 130) { throw "Historical v4 replay is incomplete." }
Write-Host "[ok] capture and evaluation identities are independent, missing facts fail closed, and all $($replay.metrics.source_evidence) historical v4 rows replay offline."
