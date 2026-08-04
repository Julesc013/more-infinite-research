param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path,
  [switch]$AllPackageLocks
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context", "Shadow", "Executor", "Release", "Calibration")) {
  . (Join-Path $repo "tools/lib/control/$module.ps1")
}

$records = Assert-MIRCPRecords -RepoRoot $repo
$freeze = Assert-MIRCPPackageFreeze -RepoRoot $repo -AllLocks:$AllPackageLocks
foreach ($command in @("Invoke-MIRCPFreshCalibration", "New-MIRCPFreshCalibrationProof", "Get-MIRCPCalibrationProofState", "Resolve-MIRCPManifestTaskResult")) {
  if ($null -eq (Get-Command $command -CommandType Function -ErrorAction SilentlyContinue)) { throw "Control-plane calibration command is unavailable: $command" }
}
$closureContext = "D" * 64
$closureIdentity = "C" * 64
$selectedClosureDigest = "A" * 64
$unselectedDuplicateDigest = "B" * 64
$closureManifestRows = @([pscustomobject][ordered]@{
  task_id = "static.full"
  status = "passed"
  object_digest = $selectedClosureDigest
})
$closureEvidenceRows = @(
  [pscustomobject][ordered]@{digest=$selectedClosureDigest;kind="task-result";task_id="static.full";status="passed";context_digest=$closureContext;identity_key=$closureIdentity;trust_class="ci";revoked=$false},
  [pscustomobject][ordered]@{digest=$unselectedDuplicateDigest;kind="task-result";task_id="static.full";status="passed";context_digest=$closureContext;identity_key=$closureIdentity;trust_class="ci";revoked=$false}
)
$selectedClosureRow = Resolve-MIRCPManifestTaskResult -ManifestTaskResults $closureManifestRows -EvidenceObjects $closureEvidenceRows `
  -TaskId "static.full" -IdentityKey $closureIdentity -ContextDigest $closureContext -TrustClass "ci"
$duplicateClosureRejected = $false
try {
  [void](Resolve-MIRCPManifestTaskResult -ManifestTaskResults @($closureManifestRows + $closureManifestRows) -EvidenceObjects $closureEvidenceRows `
    -TaskId "static.full" -IdentityKey $closureIdentity -ContextDigest $closureContext -TrustClass "ci")
} catch {
  if ($_.Exception.Message -match "requires one exact TaskNode result") { $duplicateClosureRejected = $true } else { throw }
}
$mismatchedClosureRejected = $false
try {
  $mismatchedEvidenceRows = @([pscustomobject][ordered]@{
    digest=$selectedClosureDigest;kind="task-result";task_id="static.full";status="passed";context_digest=$closureContext;
    identity_key=("E" * 64);trust_class="ci";revoked=$false
  })
  [void](Resolve-MIRCPManifestTaskResult -ManifestTaskResults $closureManifestRows -EvidenceObjects $mismatchedEvidenceRows `
    -TaskId "static.full" -IdentityKey $closureIdentity -ContextDigest $closureContext -TrustClass "ci")
} catch {
  if ($_.Exception.Message -match "does not resolve to one exact current evidence object") { $mismatchedClosureRejected = $true } else { throw }
}
if ([string]$selectedClosureRow.digest -ne $selectedClosureDigest -or -not $duplicateClosureRejected -or -not $mismatchedClosureRejected) {
  throw "Fresh-calibration proof selection is not compact-manifest-bound, object-identity-strict, and ambiguity-rejecting."
}

foreach ($schemaName in @("change-record.schema.json", "candidate-closure.schema.json", "incident-record.schema.json", "release-record.schema.json", "release-transition.schema.json", "task-node.schema.json", "observation.schema.json", "assertion.schema.json", "evaluation.schema.json", "execution-registry.schema.json", "verification-context.schema.json", "evidence-object.schema.json", "evidence-manifest.schema.json", "evidence-revocation.schema.json")) {
  $schema = Read-MIRCPJson -Path "spec/schemas/$schemaName" -RepoRoot $repo
  if ([string]$schema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema" -or [string]$schema.type -ne "object" -or $schema.additionalProperties -ne $false) {
    throw "Control-plane schema is not strict JSON Schema 2020-12: $schemaName"
  }
}

$portableDigestRoot = Join-Path ([IO.Path]::GetTempPath()) ("mir-control-plane-portable-digest-" + [guid]::NewGuid().ToString("N"))
try {
  [void](New-Item -ItemType Directory -Path $portableDigestRoot)
  $lfPath = Join-Path $portableDigestRoot "lf.txt"
  $crlfPath = Join-Path $portableDigestRoot "crlf.txt"
  [IO.File]::WriteAllText($lfPath, "one`ntwo`n", [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($crlfPath, "one`r`ntwo`r`n", [Text.UTF8Encoding]::new($false))
  if ((Get-MIRCPPortableTextSha256 -Path $lfPath) -ne (Get-MIRCPPortableTextSha256 -Path $crlfPath)) {
    throw "Portable control-plane text digests differ across LF and CRLF checkouts."
  }
} finally {
  if (Test-Path -LiteralPath $portableDigestRoot -PathType Container) {
    Remove-Item -LiteralPath $portableDigestRoot -Recurse -Force
  }
}

$views = Update-MIRCPViews -RepoRoot $repo -Check
if ([string]$views.status -ne "current") { throw "Control-plane generated views are not current." }
$calibration = Assert-MIRCPMutationCalibration -RepoRoot $repo
if ([int]$calibration.false_negative_budget -ne 0) { throw "Impact mutation calibration permits false negatives." }
$planA = New-MIRCPPlan -Mode changed -ChangedPath @("tools/lib/control/Planner.ps1") -RepoRoot $repo
$planB = New-MIRCPPlan -Mode changed -ChangedPath @("tools/lib/control/Planner.ps1") -RepoRoot $repo
if ([string]$planA.plan_id -ne [string]$planB.plan_id -or [bool]$planA.plan.impact.governance_failure) { throw "Semantic planner is nondeterministic or failed to own its own implementation." }
$releaseForInputs = Get-MIRCPReleaseByVersion -Release "3.2.2" -RepoRoot $repo
$docsInput = Get-MIRCPEffectiveInputManifest -Task ((Get-MIRCPTaskMap -RepoRoot $repo)["docs.schema"]) -ReleaseRecord $releaseForInputs -Target "2.1" -SourceRepoRoot $repo -RepoRoot $repo
$docsManifestRow = @($docsInput.rows | Where-Object input -eq "source:.mir/docs.yml")
$docsFileRow = @($docsManifestRow.matches | Where-Object path -eq ".mir/docs.yml")
if ($docsManifestRow.Count -ne 1 -or [string]$docsManifestRow[0].scope -ne "source" -or [string]$docsManifestRow[0].source_commit -ne ([string](& git -C $repo rev-parse HEAD)).Trim() -or
    $docsFileRow.Count -ne 1 -or [string]$docsFileRow[0].sha256 -ne (Get-MIRCPSha256Text -Value ([IO.File]::ReadAllText((Join-Path $repo ".mir/docs.yml")).Replace("`r`n", "`n").Replace("`r", "`n")))) {
  throw "Effective-input manifest is not bound to canonical repository file content."
}
$freshPlan = New-MIRCPPlan -Mode calibrate-fresh -ChangedPath @("tools/lib/control/Planner.ps1") -RepoRoot $repo
$verificationTaskCount = @(Get-MIRCPTaskRecords -RepoRoot $repo | Where-Object {
  ($null -eq $_.PSObject.Properties["activation"] -or [string]$_.activation -eq "verification") -and
  ($null -eq $_.PSObject.Properties["targets"] -or @($_.targets | ForEach-Object { [string]$_ }) -contains "2.1")
}).Count
if ([int]$freshPlan.plan.task_count -ne $verificationTaskCount -or [string]$freshPlan.plan.stage -ne "verification" -or -not [bool]$freshPlan.plan.aggregate_is_result_only) { throw "Fresh calibration does not select the complete verification-stage TaskNode graph or treats aggregates as executable." }
$aggregateRows = @($freshPlan.plan.tasks | Where-Object kind -eq "aggregate")
if ($aggregateRows.Count -ne 2 -or @($aggregateRows | Where-Object action -ne "AGGREGATE").Count -ne 0) { throw "Result-only aggregates were scheduled as executable work." }
$publicationPlan = New-MIRCPPlan -Mode calibrate-fresh -ChangedPath @("tools/lib/control/Planner.ps1") -Target "2.0" -Release "2.5.0" -Stage publication -SelectionOnly -RepoRoot $repo
foreach ($requiredPublicationNode in @("tag", "publication", "public-byte-verification", "promotion", "seal", "protected.qualification", "qualification.full", "backport.reconstruction")) {
  if (@($publicationPlan.plan.tasks.id) -notcontains $requiredPublicationNode) { throw "Publication plan omitted prerequisite $requiredPublicationNode." }
}
$registry = Update-MIRCPExecutionRegistry -Target "2.1" -RepoRoot $repo -Check
$registryResult = Assert-MIRCPExecutionRegistry -Registry $registry -RepoRoot $repo
$replay = Update-MIRCPV4ReplayReport -RepoRoot $repo -Check
if ([string]$replay.verdict -ne "passed" -or [int]$replay.metrics.source_evidence -ne 130) { throw "Historical v4 evidence replay is incomplete." }
$shadowContract = Assert-MIRCPShadowContract -RepoRoot $repo
$policy = Get-MIRCPPolicy -RepoRoot $repo
$proofSha256 = "A" * 64
$implementationCommit = "b" * 40
$syntheticProof = [pscustomobject][ordered]@{authority="mir-control-plane-v5-fresh-independent-calibration";status="passed";release="3.2.2";control_plane_commit=$implementationCommit;component_abis=$policy.component_abis}
$syntheticLock = [pscustomobject][ordered]@{component_abis=$policy.component_abis}
$pendingAuthority = [pscustomobject][ordered]@{state="pending";calibration_candidates=@("3.2.2","2.5.0")}
$pendingCutover = [pscustomobject][ordered]@{state="pending";calibration_release="3.2.2";proof_sha256="";implementation_commit="";component_abis=$null}
$pendingInheritance = Test-MIRCPInheritedShadowCutoverContract -Authority $pendingAuthority `
  -Cutover $pendingCutover -CalibrationProof $syntheticProof `
  -ControlLock $syntheticLock -Policy $policy -Target "2.1" -ProofSha256 $proofSha256 -ProofRevoked $false
if ([string]$pendingInheritance.status -ne "failed" -or @($pendingInheritance.failures) -notcontains "global v4/v5 equivalence is not accepted") {
  throw "C30 inherited shadow admission did not fail closed while global equivalence is pending."
}
$acceptedAuthority = [pscustomobject][ordered]@{state="accepted";calibration_candidates=@("3.2.2","2.5.0")}
$acceptedCutover = [pscustomobject][ordered]@{state="accepted";calibration_release="3.2.2";proof_sha256=$proofSha256;implementation_commit=$implementationCommit;component_abis=$policy.component_abis}
$acceptedInheritance = Test-MIRCPInheritedShadowCutoverContract -Authority $acceptedAuthority -Cutover $acceptedCutover `
  -CalibrationProof $syntheticProof -ControlLock $syntheticLock -Policy $policy -Target "2.1" -ProofSha256 $proofSha256 -ProofRevoked $false
if ([string]$acceptedInheritance.status -ne "passed" -or @($acceptedInheritance.failures).Count -ne 0) { throw "Exact accepted C24 cutover did not admit later Factorio 2.1 release inheritance." }
$revokedInheritance = Test-MIRCPInheritedShadowCutoverContract -Authority $acceptedAuthority -Cutover $acceptedCutover `
  -CalibrationProof $syntheticProof -ControlLock $syntheticLock -Policy $policy -Target "2.1" -ProofSha256 $proofSha256 -ProofRevoked $true
if ([string]$revokedInheritance.status -ne "failed" -or @($revokedInheritance.failures) -notcontains "fresh calibration proof is revoked") { throw "Inherited shadow admission accepted a revoked calibration proof." }
$p9InheritanceRejected = $false
try { [void](Assert-MIRCPInheritedShadowCutover -ReleaseRecord (Get-MIRCPReleaseByVersion -Release "2.5.0" -RepoRoot $repo) -ContextPath "missing" -SourceRepoRoot "missing" -RepoRoot $repo) } catch {
  if ($_.Exception.Message -match "Calibration candidates cannot use inherited") { $p9InheritanceRejected = $true } else { throw }
}
if (-not $p9InheritanceRejected) { throw "P9 was permitted to inherit C24 shadow admission instead of requiring target-local operational proof." }
$shadow = Read-MIRCPJson -Path ".mir/control-plane/shadow-analysis.json" -RepoRoot $repo
$expectedShadowCounts = @{
  "3.2.2" = @{ v4 = 113; v5 = 116 }
  "2.5.0" = @{ v4 = 109; v5 = 112 }
}
foreach ($candidate in @($shadow.candidates)) {
  $version = [string]$candidate.release
  if (-not $expectedShadowCounts.ContainsKey($version)) { throw "Shadow analysis contains an unexpected candidate: $version" }
  foreach ($dimension in @("candidate-identity", "required-proof-obligations", "scenario-identities", "environment-identities")) {
    if ([string]$candidate.dimensions.$dimension.status -ne "passed") {
      throw "Shadow analysis has not proven $version structural dimension $dimension."
    }
  }
  if ([int]$candidate.dimensions.'scenario-identities'.v4 -ne [int]$expectedShadowCounts[$version].v4 -or
      [int]$candidate.dimensions.'scenario-identities'.v5 -ne [int]$expectedShadowCounts[$version].v5) {
    throw "Shadow scenario counts changed for $version."
  }
  if ([int]$candidate.dimensions.'environment-identities'.mapped -ne [int]$expectedShadowCounts[$version].v4 -or
      [string]$candidate.dimensions.'environment-identities'.mapping_sha256 -notmatch '^[0-9A-F]{64}$' -or
      @($candidate.dimensions.'environment-identities'.mappings).Count -ne [int]$expectedShadowCounts[$version].v4) {
    throw "Shadow environment identity mapping is incomplete for $version."
  }
}
if ([string]$shadow.status -ne "passed" -or @($shadow.pending_dimensions).Count -ne 0 -or [int]$shadowContract.pending.Count -ne 0) {
  throw "Toolchain-admission shadow analysis must prove exact structural and pending-verdict parity for both candidates."
}
$p9Shadow = @($shadow.candidates | Where-Object release -eq "2.5.0")
if ($p9Shadow.Count -ne 1 -or [string]$p9Shadow[0].comparison_mode -ne "toolchain-admission") {
  throw "Committed P9 shadow analysis is not explicitly scoped to toolchain admission."
}
foreach ($dimension in @("approved-delta", "upgrade-result", "performance-result", "manual-result", "aggregate-verdict", "seal-inputs")) {
  if ([string]$p9Shadow[0].dimensions.$dimension.status -ne "passed" -or [string]$p9Shadow[0].dimensions.$dimension.reason -notmatch "v4=pending and v5=pending") {
    throw "P9 admission parity is not explicit for $dimension."
  }
}

$backport = Read-MIRCPJson -Path "path:releases.backports/2.5.0.json" -RepoRoot $repo
if ([string]$backport.source.release -ne "3.2.3" -or
    [string]$backport.source.tag -ne "3.2.3" -or
    [string]$backport.source.tag_state -ne "immutable" -or
    [string]$backport.source.tag_commit -ne "1abe07573cde814c3cacf6153b5ae64dee4038ba" -or
    [string]$backport.source.candidate_id -ne "C30" -or
    [string]$backport.expected_target.candidate_id -ne "2.5-P11") {
  throw "P11 backport authority is not bound to immutable MIR 3.2.3 candidate C30."
}

$docManifest = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir/docs.yml")
if ($docManifest -notmatch [regex]::Escape("docs/architecture/control-plane-v5.md")) {
  throw "Control Plane v5 architecture document is not registered."
}
$modules = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir/modules.yml")
foreach ($token in @("control_plane_policy", "control_plane_entrypoint", "control_plane_gate")) {
  if ($modules -notmatch $token) { throw "Module manifest is missing $token." }
}

Write-Host "[ok] MIR Control Plane v5 records ($($records.changes) changes, $($records.incidents) incidents, $($records.releases) releases, $($records.tasks) tasks), package freeze $($freeze.lock_id), $($registryResult.scenarios) exact-environment scenarios, 130 replayed observations, and $($calibration.cases) zero-false-negative impact mutations are valid."
