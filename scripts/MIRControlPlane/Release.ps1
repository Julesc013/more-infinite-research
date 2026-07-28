function Assert-MIRCPProtectedEvidenceProducer {
  param([Parameter(Mandatory)]$Producer, [Parameter(Mandatory)]$State, [string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $policy = Read-MIRCPJson -Path "validation/trust.json" -RepoRoot $repo
  $class = $policy.classes.'protected-release'
  if ([string]$Producer.trust_class -ne "protected-release") { throw "Evidence producer is not protected-release." }
  foreach ($binding in @(
    @{field="repository"; policy="repositories"}, @{field="workflow"; policy="workflows"},
    @{field="event"; policy="events"}, @{field="ref"; policy="refs"}
  )) {
    if (@($class.($binding.policy) | ForEach-Object { [string]$_ }) -notcontains [string]$Producer.($binding.field)) {
      throw "Evidence producer has untrusted $($binding.field)."
    }
  }
  foreach ($field in @("environment", "runner_identity", "runner_environment")) {
    if ([string]$Producer.$field -ne [string]$class.$field) { throw "Evidence producer has untrusted $field." }
  }
  $controlLock = Get-Content -Raw -LiteralPath (Join-Path $State.context.path "control-plane-lock.json") | ConvertFrom-Json
  if ([string]$Producer.commit -ne [string]$controlLock.qualification_source_commit) { throw "Evidence producer commit differs from the immutable context control-plane lock." }
  if ([string]$Producer.trust_policy_sha256 -ne (Get-MIRCPSha256File -Path (Join-Path $repo "validation/trust.json"))) { throw "Evidence producer trust policy digest is stale." }
  foreach ($field in @("run_id", "run_attempt", "job", "runner")) {
    if ([string]::IsNullOrWhiteSpace([string]$Producer.$field)) { throw "Evidence producer is missing $field." }
  }
  return $true
}

function Test-MIRCPProducerExecutionIdentity {
  param([Parameter(Mandatory)]$Actual, [Parameter(Mandatory)]$Expected)
  foreach ($field in @(
    "trust_class", "repository", "workflow", "event", "ref", "environment", "runner_identity", "runner_environment",
    "commit", "trust_policy_sha256", "run_id", "run_attempt", "job", "runner"
  )) {
    if ([string]$Actual.$field -ne [string]$Expected.$field) { return $false }
  }
  return $true
}

function Get-MIRCPExactTaskEvidenceObject {
  param(
    [Parameter(Mandatory)]$State,
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$IndexObjects,
    $Producer = $null,
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $row = @($State.plan.tasks | Where-Object id -eq $TaskId)
  if ($row.Count -ne 1) { throw "Context plan does not contain TaskNode $TaskId exactly once." }
  $matches = @($IndexObjects | Where-Object {
    [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq $TaskId -and
    [string]$_.context_digest -eq [string]$State.context.context_id -and
    [string]$_.identity_key -eq [string]$row[0].effective_input_sha256 -and
    [string]$_.status -eq "passed" -and -not [bool]$_.revoked
  })
  if ($null -ne $Producer -and $matches.Count -gt 0) {
    $current = [Collections.Generic.List[object]]::new()
    foreach ($match in $matches) {
      $evidence = Read-MIRCPEvidenceObject -Digest ([string]$match.digest) -RepoRoot $RepoRoot -Root $EvidenceRoot
      if (Test-MIRCPProducerExecutionIdentity -Actual $evidence.object.producer -Expected $Producer) { $current.Add($match) }
    }
    $matches = @($current)
  }
  if ($matches.Count -ne 1) { throw "Release command requires exactly one exact passing $TaskId evidence object." }
  return Read-MIRCPEvidenceObject -Digest ([string]$matches[0].digest) -RepoRoot $RepoRoot -Root $EvidenceRoot
}

function Complete-MIRCPQualification {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [string]$EvidenceRoot = "",
    [switch]$RequireFresh,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  if ([string]$state.plan.stage -notin @("release", "publication", "all")) { throw "Qualification requires a release-stage immutable context." }
  if ($RequireFresh -and [string]$state.plan.mode -ne "calibrate-fresh") { throw "Independent qualification requires a calibrate-fresh context." }
  $result = Complete-MIRCPAggregateGate -ContextPath $ContextPath -AggregateTaskId "qualification.full" -TrustClass "protected-release" -EvidenceRoot $EvidenceRoot -RepoRoot $repo
  $manifest = Read-MIRCPEvidenceObject -Digest ([string]$result.manifest_object) -RepoRoot $repo -Root $EvidenceRoot
  [void](Assert-MIRCPProtectedEvidenceProducer -Producer $manifest.object.producer -State $state -RepoRoot $repo)
  return [pscustomobject][ordered]@{schema=1;status="passed";operation="qualification";release=[string]$state.plan.release;context_digest=[string]$state.context.context_id;plan_id=[string]$state.plan_envelope.plan_id;fresh=([string]$state.plan.mode -eq "calibrate-fresh");qualification_manifest=[string]$result.manifest_object;task_results=[int]$result.task_results}
}

function Invoke-MIRCPBackportAdmission {
  param([Parameter(Mandatory)][string]$ContextPath, [string]$EvidenceRoot = "", [string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  if ([string]$state.plan.target -ne "2.0") { throw "Backport admission applies only to Factorio 2.0 contexts." }
  return Invoke-MIRCPTaskCommand -ContextPath $ContextPath -TaskId "backport.reconstruction" -TrustClass "protected-release" -EvidenceRoot $EvidenceRoot -RepoRoot $repo
}

function New-MIRCPReleaseSeal {
  param([Parameter(Mandatory)][string]$ContextPath, [string]$EvidenceRoot = "", [string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  if ([string]$state.plan.stage -notin @("release", "publication", "all")) { throw "Seal creation requires a release-stage immutable context." }
  $indexResult = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $EvidenceRoot
  if ([int]$indexResult.invalid -ne 0) { throw "Evidence store contains invalid objects." }
  $manifests = @($indexResult.index.objects | Where-Object {
    [string]$_.kind -eq "execution-manifest" -and [string]$_.context_digest -eq [string]$state.context.context_id -and
    [string]$_.status -eq "passed" -and [string]$_.trust_class -eq "protected-release" -and -not [bool]$_.revoked
  })
  $qualifiedCandidates = [Collections.Generic.List[object]]::new()
  foreach ($row in $manifests) {
    $object = (Read-MIRCPEvidenceObject -Digest ([string]$row.digest) -RepoRoot $repo -Root $EvidenceRoot).object
    if (@($object.payload.task_results | Where-Object task_id -eq "qualification.full").Count -eq 1) { $qualifiedCandidates.Add([pscustomobject][ordered]@{digest=[string]$row.digest;record=$object}) }
  }
  if ($qualifiedCandidates.Count -eq 0) { throw "Seal creation requires exactly one protected qualification.full execution manifest." }
  $currentProducer = New-MIRCPExecutorProducer -TrustClass "protected-release" -RepoRoot $repo
  $qualified = @($qualifiedCandidates | Where-Object { Test-MIRCPProducerExecutionIdentity -Actual $_.record.producer -Expected $currentProducer })
  if ($qualified.Count -ne 1) { throw "Seal creation requires exactly one current protected qualification.full execution manifest." }
  [void](Assert-MIRCPProtectedEvidenceProducer -Producer $qualified[0].record.producer -State $state -RepoRoot $repo)
  $objects = @($indexResult.index.objects)
  if ([string]$state.plan.target -eq "2.0") { [void](Get-MIRCPExactTaskEvidenceObject -State $state -TaskId "backport.reconstruction" -IndexObjects $objects -Producer $currentProducer -EvidenceRoot $EvidenceRoot -RepoRoot $repo) }
  $qualification = Get-MIRCPExactTaskEvidenceObject -State $state -TaskId "qualification.full" -IndexObjects $objects -Producer $currentProducer -EvidenceRoot $EvidenceRoot -RepoRoot $repo
  $protectedRow = @($state.plan.tasks | Where-Object id -eq "protected.qualification")
  if ($protectedRow.Count -ne 1) { throw "Context plan omits protected.qualification." }
  $protectedMarker = Write-MIRCPTaskResultEvidence -State $state -PlanRow $protectedRow[0] -Status passed `
    -Payload ([pscustomobject][ordered]@{qualification_manifest=[string]$qualified[0].digest;qualification_task_object=[string]$qualification.digest}) `
    -TrustClass "protected-release" -EvidenceRoot $EvidenceRoot -RepoRoot $repo

  $descriptor = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "candidate-descriptor.json") | ConvertFrom-Json
  $controlLock = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "control-plane-lock.json") | ConvertFrom-Json
  $sealMaterial = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-control-plane-v5-release-seal"
    release = [string]$descriptor.release
    candidate_id = [string]$descriptor.candidate_id
    archive_sha256 = [string]$descriptor.archive_sha256
    content_sha256 = [string]$descriptor.content_sha256
    package_source_commit = [string]$descriptor.source_commit
    context_digest = [string]$state.context.context_id
    plan_id = [string]$state.plan_envelope.plan_id
    control_plane_commit = [string]$controlLock.qualification_source_commit
    component_abis = $controlLock.component_abis
    qualification_manifest = [string]$qualified[0].digest
  }
  $producer = $currentProducer
  $sealObject = New-MIRCPEvidenceObject -Kind seal -ContextDigest ([string]$state.context.context_id) -IdentityKey (Get-MIRCPSha256Object -Value $sealMaterial) `
    -Subject ([pscustomobject][ordered]@{release=[string]$descriptor.release;candidate_id=[string]$descriptor.candidate_id;archive_sha256=[string]$descriptor.archive_sha256}) `
    -Producer $producer -Payload ([pscustomobject][ordered]@{status="passed";material=$sealMaterial;sealed_at=[DateTimeOffset]::UtcNow.ToString("o")}) `
    -Links @([string]$qualified[0].digest, [string]$protectedMarker.object_digest)
  $stored = Write-MIRCPEvidenceObject -Object $sealObject -RepoRoot $repo -Root $EvidenceRoot
  $sealRow = @($state.plan.tasks | Where-Object id -eq "seal")
  if ($sealRow.Count -ne 1) { throw "Context plan omits seal." }
  $sealMarker = Write-MIRCPTaskResultEvidence -State $state -PlanRow $sealRow[0] -Status passed `
    -Payload ([pscustomobject][ordered]@{seal_object=[string]$stored.digest;qualification_manifest=[string]$qualified[0].digest}) `
    -TrustClass "protected-release" -EvidenceRoot $EvidenceRoot -RepoRoot $repo
  return [pscustomobject][ordered]@{schema=1;status="passed";operation="seal";release=[string]$descriptor.release;candidate_sha256=[string]$descriptor.archive_sha256;context_digest=[string]$state.context.context_id;seal_object=[string]$stored.digest;task_object=[string]$sealMarker.object_digest}
}

function Invoke-MIRCPReleaseTaskAdmission {
  param([Parameter(Mandatory)][string]$ContextPath, [Parameter(Mandatory)][string]$TaskId, [string]$SourceRepoRoot = "", [string]$TrustClass = "ci", [string]$EvidenceRoot = "", [string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $task = (Get-MIRCPTaskMap -RepoRoot $repo)[$TaskId]
  if ($null -eq $task -or [string]$task.activation -notin @("release", "publication")) { throw "TaskNode $TaskId is not a release/publication admission task." }
  return Invoke-MIRCPTaskCommand -ContextPath $ContextPath -TaskId $TaskId -SourceRepoRoot $SourceRepoRoot -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
}

function Invoke-MIRCPPromotionAdmission {
  param([Parameter(Mandatory)][string]$ContextPath, [string]$EvidenceRoot = "", [string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath
  $index = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $EvidenceRoot
  $objects = @($index.index.objects)
  foreach ($required in @("seal", "shadow.equivalence")) {
    $row = @($state.plan.tasks | Where-Object id -eq $required)
    $available = @($objects | Where-Object { [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq $required -and [string]$_.context_digest -eq [string]$state.context.context_id -and [string]$_.identity_key -eq [string]$row[0].effective_input_sha256 -and [string]$_.status -eq "passed" -and -not [bool]$_.revoked })
    if ($available.Count -eq 0) { throw "Release command requires exactly one exact passing $required evidence object." }
  }
  $currentProducer = New-MIRCPExecutorProducer -TrustClass "protected-release" -RepoRoot $repo
  foreach ($required in @("seal", "shadow.equivalence")) { [void](Get-MIRCPExactTaskEvidenceObject -State $state -TaskId $required -IndexObjects $objects -Producer $currentProducer -EvidenceRoot $EvidenceRoot -RepoRoot $repo) }
  if ([string]$state.plan.target -eq "2.0") {
    $release = Get-MIRCPReleaseByVersion -Release ([string]$state.plan.release) -RepoRoot $repo
    $proof = Get-Content -Raw -LiteralPath (Join-Path $repo ([string]$release.proofs.backport_reconstruction[0].path)) | ConvertFrom-Json
    & git -C $repo merge-base --is-ancestor ([string]$release.baseline_release.tag_commit) ([string]$proof.integration_commit)
    if ($LASTEXITCODE -ne 0) { throw "Promotion commit lost the target-line baseline ancestry." }
  }
  $row = @($state.plan.tasks | Where-Object id -eq "promotion")
  if ($row.Count -ne 1) { throw "Context plan omits promotion." }
  return Write-MIRCPTaskResultEvidence -State $state -PlanRow $row[0] -Status passed -Payload ([pscustomobject][ordered]@{admission="proof-closure"}) -TrustClass "protected-release" -EvidenceRoot $EvidenceRoot -RepoRoot $repo
}
