param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Evidence", "Views")) {
  . (Join-Path $repo "scripts/MIRControlPlane/$module.ps1")
}

$root = ".work/output/control-plane-v5-self-test/evidence/$([guid]::NewGuid().ToString('N'))"
$contextDigest = "C" * 64
$identityKey = "D" * 64
$producer = [pscustomobject][ordered]@{component="self-test"; abi=1; trust_class="self-test"}
$evidence = New-MIRCPEvidenceObject -Kind task-result -ContextDigest $contextDigest -IdentityKey $identityKey `
  -Subject ([pscustomobject][ordered]@{task_id="self-test"; target="2.1"}) -Producer $producer `
  -Payload ([pscustomobject][ordered]@{status="passed"; canonicalization_abi=1})
$first = Write-MIRCPEvidenceObject -Object $evidence -RepoRoot $repo -Root $root
$second = Write-MIRCPEvidenceObject -Object $evidence -RepoRoot $repo -Root $root
if ([string]$first.digest -ne [string]$second.digest) { throw "Evidence object writes are not idempotent." }
$read = Read-MIRCPEvidenceObject -Digest $first.digest -RepoRoot $repo -Root $root
if ([string]$read.object.identity_key -ne $identityKey -or [bool]$read.revocation.revoked) { throw "Evidence object did not round-trip exactly." }

$revocations = [pscustomobject][ordered]@{
  schema=1; authority="mir-control-plane-v5-evidence-revocations"; default_disposition="allow"
  rules=@([pscustomobject][ordered]@{id="TEST-PRODUCER-ABI"; type="producer-abi"; active=$true; reason="self-test"; abi=1})
}
$revoked = Test-MIRCPEvidenceRevocation -Object $read.object -Digest $first.digest -Authority $revocations -RepoRoot $repo
if (-not [bool]$revoked.revoked -or [string]$revoked.rule_id -ne "TEST-PRODUCER-ABI") { throw "Producer ABI revocation did not invalidate the object." }

$index = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $root
if ([int]$index.objects -ne 1 -or [int]$index.invalid -ne 0) { throw "Evidence index rebuild did not find the exact object set." }
$runtimeTask = [pscustomobject][ordered]@{id="self-test";freshness="content-eternal";effective_inputs=@("factorio-installation")}
$runtimeDecision = Resolve-MIRCPTaskEvidenceAction -Task $runtimeTask -EffectiveInputSha256 $identityKey -Mode changed -EvidenceIndex $index.path -TrustClass "self-test" -RepoRoot $repo
if ([string]$runtimeDecision.action -ne "RUN" -or [string]$runtimeDecision.reason -notmatch "worker-resolved") { throw "Worker-resolved runtime evidence was reused from an unresolved base identity." }
$lease1 = Acquire-MIRCPEvidenceLease -IdentityKey $identityKey -Scope process -TtlMinutes 30 -RepoRoot $repo -Root $root
$lease2 = Acquire-MIRCPEvidenceLease -IdentityKey $identityKey -Scope process -TtlMinutes 30 -RepoRoot $repo -Root $root
if ([string]$lease1.disposition -ne "ACQUIRE" -or [string]$lease2.disposition -ne "ADOPT") { throw "Matching in-progress evidence work was not adopted." }

$basePlan = New-MIRCPPlan -Mode changed -ChangedPath @("verification/schema/observation.schema.json") -Target "2.1" -Release "3.2.2" -RepoRoot $repo
$taskRow = @($basePlan.plan.tasks | Where-Object id -eq "harness.schemas")
if ($taskRow.Count -ne 1) { throw "Evidence reuse self-test could not select harness.schemas." }
$taskEvidence = New-MIRCPEvidenceObject -Kind task-result -ContextDigest $contextDigest -IdentityKey ([string]$taskRow[0].effective_input_sha256) `
  -Subject ([pscustomobject][ordered]@{task_id="harness.schemas"; target="2.1"}) -Producer $producer `
  -Payload ([pscustomobject][ordered]@{status="passed"; canonicalization_abi=1})
$taskEvidenceResult = Write-MIRCPEvidenceObject -Object $taskEvidence -RepoRoot $repo -Root $root
$index = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $root
$reusePlan = New-MIRCPPlan -Mode changed -ChangedPath @("verification/schema/observation.schema.json") -Target "2.1" -Release "3.2.2" -EvidenceIndex $index.path -TrustClass "self-test" -RepoRoot $repo
$reuseRow = @($reusePlan.plan.tasks | Where-Object id -eq "harness.schemas")
if ([string]$reuseRow[0].action -ne "REUSE") { throw "Exact unrevoked evidence was not reused." }
$freshPlan = New-MIRCPPlan -Mode calibrate-fresh -ChangedPath @("verification/schema/observation.schema.json") -Target "2.1" -Release "3.2.2" -EvidenceIndex $index.path -TrustClass "self-test" -RepoRoot $repo
$freshRow = @($freshPlan.plan.tasks | Where-Object id -eq "harness.schemas")
if ([string]$freshRow[0].action -ne "RUN") { throw "Independent calibration reused content-eternal evidence." }

$manifest = New-MIRCPExecutionManifest -ContextDigest $contextDigest -PlanId ([string]$reusePlan.plan_id) -Producer $producer `
  -TaskResults @([pscustomobject][ordered]@{task_id="harness.schemas"; status="passed"; object_digest=[string]$taskEvidenceResult.digest}) -Status passed
$manifestObject = New-MIRCPEvidenceObject -Kind execution-manifest -ContextDigest $contextDigest -IdentityKey (Get-MIRCPSha256Object -Value $manifest) `
  -Subject ([pscustomobject][ordered]@{plan_id=[string]$reusePlan.plan_id; target="2.1"}) -Producer $producer -Payload $manifest
[void](Write-MIRCPEvidenceObject -Object $manifestObject -RepoRoot $repo -Root $root)

$store = Get-MIRCPEvidenceRoot -RepoRoot $repo -Root $root
$badDigest = "F" * 64
$badDir = Join-Path $store "objects/sha256/FF"
if (-not (Test-Path -LiteralPath $badDir -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $badDir) }
[IO.File]::WriteAllText((Join-Path $badDir "$badDigest.json"), "not-json`n", [Text.UTF8Encoding]::new($false))
$quarantined = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $root -QuarantineInvalid
if ([int]$quarantined.invalid -ne 1 -or @(Get-ChildItem -LiteralPath (Join-Path $store "quarantine") -File).Count -ne 1) { throw "Invalid evidence was not quarantined explicitly." }

Write-Host "[ok] content-addressed evidence round-trips, indexes rebuild, exact evidence reuses, runtime inputs and fresh calibration rerun, matching leases adopt, revocation invalidates, and corrupt objects quarantine."
