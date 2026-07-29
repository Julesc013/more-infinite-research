function Invoke-MIRCPFreshCalibration {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$FactorioBin,
    [Parameter(Mandatory)][string]$PriorRelease,
    [Parameter(Mandatory)][string]$LocalModDir,
    [Parameter(Mandatory)][string]$SourceRepoRoot,
    [string]$LocalModZipDir = "",
    [ValidateSet("ci")][string]$TrustClass = "ci",
    [string]$EvidenceRoot = "artifacts/evidence",
    [switch]$Resume,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath -RepoRoot $repo
  if ([string]$state.manifest.mode -ne "calibrate-fresh" -or [string]$state.manifest.release -ne "3.2.2") {
    throw "Toolchain admission calibration requires a fresh C24 verification context."
  }
  [void](Resolve-Path -LiteralPath $FactorioBin)
  [void](Resolve-Path -LiteralPath $PriorRelease)
  [void](Resolve-Path -LiteralPath $LocalModDir)
  [void](Resolve-Path -LiteralPath $SourceRepoRoot)
  if ([string]::IsNullOrWhiteSpace($LocalModZipDir)) { $LocalModZipDir = $LocalModDir }
  [void](Resolve-Path -LiteralPath $LocalModZipDir)

  $indexResult = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $EvidenceRoot
  if ([int]$indexResult.invalid -ne 0) { throw "Calibration evidence store contains invalid objects." }
  $existingObjects = @($indexResult.index.objects)
  function Test-MIRCPCalibrationResultExists {
    param([Parameter(Mandatory)][string]$TaskId, [Parameter(Mandatory)][string]$IdentityKey)
    $matches = @($existingObjects | Where-Object {
      [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq $TaskId -and
      [string]$_.context_digest -eq [string]$state.context.context_id -and
      [string]$_.identity_key -eq $IdentityKey -and [string]$_.status -eq "passed" -and
      [string]$_.trust_class -eq $TrustClass -and -not [bool]$_.revoked
    })
    if ($matches.Count -gt 1) { throw "Calibration evidence is ambiguous for $TaskId." }
    if ($matches.Count -eq 1 -and -not $Resume) {
      throw "Calibration evidence already exists for $TaskId; use -Resume to adopt it without duplication."
    }
    return $matches.Count -eq 1
  }
  function Invoke-MIRCPCalibrationPlanTask {
    param([Parameter(Mandatory)][string]$TaskId)
    $row = @($state.plan.tasks | Where-Object id -eq $TaskId)
    if ($row.Count -ne 1) { throw "Calibration plan does not contain $TaskId exactly once." }
    if (Test-MIRCPCalibrationResultExists -TaskId $TaskId -IdentityKey ([string]$row[0].effective_input_sha256)) {
      Write-Host "[calibration] resume $TaskId"
      return
    }
    Write-Host "[calibration] run $TaskId"
    [void](Invoke-MIRCPTaskCommand -ContextPath $state.context.path -TaskId $TaskId -TrustClass $TrustClass `
      -EvidenceRoot $EvidenceRoot -SourceRepoRoot $SourceRepoRoot -RepoRoot $repo)
  }
  function Complete-MIRCPCalibrationAggregate {
    param([Parameter(Mandatory)][string]$TaskId)
    $row = @($state.plan.tasks | Where-Object id -eq $TaskId)
    if ($row.Count -ne 1 -or [string]$row[0].kind -ne "aggregate") { throw "Calibration aggregate is missing: $TaskId" }
    if (Test-MIRCPCalibrationResultExists -TaskId $TaskId -IdentityKey ([string]$row[0].effective_input_sha256)) {
      Write-Host "[calibration] resume $TaskId"
      return $null
    }
    Write-Host "[calibration] aggregate $TaskId"
    return Complete-MIRCPAggregateGate -ContextPath $state.context.path -AggregateTaskId $TaskId `
      -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
  }

  $contextRow = @($state.plan.tasks | Where-Object id -eq "verification.context")
  if ($contextRow.Count -ne 1) { throw "Fresh calibration plan omits verification.context." }
  if (-not (Test-MIRCPCalibrationResultExists -TaskId "verification.context" -IdentityKey ([string]$contextRow[0].effective_input_sha256))) {
    Write-Host "[calibration] record verification.context"
    [void](Write-MIRCPContextCompletionEvidence -ContextPath $state.context.path -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo)
  }

  foreach ($row in @($state.plan.tasks | Where-Object {
    [string]$_.id -ne "verification.context" -and [string]$_.kind -in @("static", "package", "evaluation")
  })) {
    Invoke-MIRCPCalibrationPlanTask -TaskId ([string]$row.id)
  }
  [void](Complete-MIRCPCalibrationAggregate -TaskId "static.full")

  $registry = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "expanded-scenarios.json") | ConvertFrom-Json
  $batches = @($registry.batches | Where-Object process_required)
  $batchNumber = 0
  foreach ($batch in $batches) {
    $batchNumber++
    $batchIdentity = Get-MIRCPSha256Object -Value ([pscustomobject][ordered]@{context=[string]$state.context.context_id;batch=$batch})
    if (Test-MIRCPCalibrationResultExists -TaskId ([string]$batch.id) -IdentityKey $batchIdentity) {
      Write-Host "[calibration] resume environment $batchNumber/$($batches.Count) $($batch.id)"
      continue
    }
    Write-Host "[calibration] run environment $batchNumber/$($batches.Count) $($batch.id)"
    [void](Invoke-MIRCPEnvironmentBatch -ContextPath $state.context.path -BatchId ([string]$batch.id) `
      -FactorioBin $FactorioBin -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot `
      -SourceRepoRoot $SourceRepoRoot -RepoRoot $repo)
  }

  foreach ($special in @("upgrade.measurement", "ecosystem.measurement", "approved-delta.measurement", "performance.measurement")) {
    $row = @($state.plan.tasks | Where-Object id -eq $special)
    if ($row.Count -ne 1) { throw "Fresh calibration plan omits $special." }
    if (Test-MIRCPCalibrationResultExists -TaskId $special -IdentityKey ([string]$row[0].effective_input_sha256)) {
      Write-Host "[calibration] resume $special"
      continue
    }
    Write-Host "[calibration] run $special"
    switch ($special) {
      "upgrade.measurement" {
        [void](Invoke-MIRCPUpgradeMeasurement -ContextPath $state.context.path -FactorioBin $FactorioBin `
          -PriorRelease $PriorRelease -SourceRepoRoot $SourceRepoRoot -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo)
      }
      "ecosystem.measurement" {
        [void](Invoke-MIRCPEcosystemMeasurement -ContextPath $state.context.path -FactorioBin $FactorioBin `
          -LocalModDir $LocalModDir -SourceRepoRoot $SourceRepoRoot -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo)
      }
      "approved-delta.measurement" {
        [void](Invoke-MIRCPApprovedDeltaMeasurement -ContextPath $state.context.path -FactorioBin $FactorioBin `
          -PriorRelease $PriorRelease -SourceRepoRoot $SourceRepoRoot -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo)
      }
      "performance.measurement" {
        [void](Invoke-MIRCPPerformanceMeasurement -ContextPath $state.context.path -FactorioBin $FactorioBin `
          -PriorRelease $PriorRelease -LocalModZipDir $LocalModZipDir -SourceRepoRoot $SourceRepoRoot `
          -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo)
      }
    }
  }
  Invoke-MIRCPCalibrationPlanTask -TaskId "manual.acceptance"
  $qualification = Complete-MIRCPCalibrationAggregate -TaskId "qualification.full"
  $finalIndex = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $EvidenceRoot
  if ([int]$finalIndex.invalid -ne 0) { throw "Completed calibration evidence store contains invalid objects." }
  return [pscustomobject][ordered]@{
    status = "passed"
    context_id = [string]$state.context.context_id
    plan_id = [string]$state.plan_envelope.plan_id
    planned_tasks = @($state.plan.tasks).Count
    environment_batches = $batches.Count
    evidence_objects = [int]$finalIndex.objects
    qualification_manifest = if ($null -eq $qualification) { "resumed" } else { [string]$qualification.manifest_object }
  }
}

function New-MIRCPFreshCalibrationProof {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [string]$EvidenceRoot = "artifacts/evidence",
    [string]$Output = ".mir/control-plane/fresh-calibration.json",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath -RepoRoot $repo
  if ([string]$state.manifest.mode -ne "calibrate-fresh" -or [string]$state.manifest.release -ne "3.2.2") {
    throw "Fresh calibration proof requires a calibrate-fresh C24 context."
  }
  $indexResult = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $EvidenceRoot
  if ([int]$indexResult.invalid -ne 0) { throw "Calibration proof cannot use an invalid evidence store." }
  $objects = @($indexResult.index.objects)
  $taskRows = [Collections.Generic.List[object]]::new()
  foreach ($row in @($state.plan.tasks)) {
    $matches = @($objects | Where-Object {
      [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq [string]$row.id -and
      [string]$_.context_digest -eq [string]$state.context.context_id -and
      [string]$_.identity_key -eq [string]$row.effective_input_sha256 -and
      [string]$_.status -eq "passed" -and [string]$_.trust_class -eq "ci" -and -not [bool]$_.revoked
    })
    if ($matches.Count -ne 1) { throw "Fresh calibration proof requires one exact TaskNode result for $($row.id); found $($matches.Count)." }
    $taskRows.Add([pscustomobject][ordered]@{task_id=[string]$row.id;digest=[string]$matches[0].digest})
  }
  $registry = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "expanded-scenarios.json") | ConvertFrom-Json
  $environmentRows = [Collections.Generic.List[object]]::new()
  foreach ($batch in @($registry.batches | Where-Object process_required)) {
    $identity = Get-MIRCPSha256Object -Value ([pscustomobject][ordered]@{context=[string]$state.context.context_id;batch=$batch})
    $matches = @($objects | Where-Object {
      [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq [string]$batch.id -and
      [string]$_.context_digest -eq [string]$state.context.context_id -and [string]$_.identity_key -eq $identity -and
      [string]$_.status -eq "passed" -and [string]$_.trust_class -eq "ci" -and -not [bool]$_.revoked
    })
    if ($matches.Count -ne 1) { throw "Fresh calibration proof requires one exact environment result for $($batch.id); found $($matches.Count)." }
    $environmentRows.Add([pscustomobject][ordered]@{batch_id=[string]$batch.id;digest=[string]$matches[0].digest})
  }
  $qualificationManifests = [Collections.Generic.List[object]]::new()
  foreach ($row in @($objects | Where-Object {
    [string]$_.kind -eq "execution-manifest" -and [string]$_.context_digest -eq [string]$state.context.context_id -and
    [string]$_.status -eq "passed" -and [string]$_.trust_class -eq "ci" -and -not [bool]$_.revoked
  })) {
    $record = (Read-MIRCPEvidenceObject -Digest ([string]$row.digest) -RepoRoot $repo -Root $EvidenceRoot).object
    if (@($record.payload.task_results | Where-Object task_id -eq "qualification.full").Count -eq 1) {
      $qualificationManifests.Add([pscustomobject][ordered]@{digest=[string]$row.digest;record=$record})
    }
  }
  if ($qualificationManifests.Count -ne 1) { throw "Fresh calibration proof requires one complete qualification execution manifest." }
  $mutation = Assert-MIRCPMutationCalibration -RepoRoot $repo
  if ([int]$mutation.false_negative_budget -ne 0) { throw "Fresh calibration mutation false-negative budget is not zero." }
  $shadow = Assert-MIRCPShadowContract -RepoRoot $repo
  if ([string]$shadow.analysis_status -ne "passed" -or @($shadow.pending).Count -ne 0) { throw "Fresh calibration proof requires passing toolchain-admission shadow analysis." }
  [void](Assert-MIRCPPackageFreeze -RepoRoot $repo)
  $descriptor = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "candidate-descriptor.json") | ConvertFrom-Json
  $controlLock = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "control-plane-lock.json") | ConvertFrom-Json
  if (-not [bool]$controlLock.qualification_source_clean) { throw "Fresh calibration proof requires a clean committed control-plane checkout." }
  $environmentLocks = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "environment-locks.json") | ConvertFrom-Json
  $body = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-control-plane-v5-fresh-independent-calibration"
    status = "passed"
    disposition = "independent-local-calibration-not-release-seal"
    release = "3.2.2"
    candidate_id = [string]$descriptor.candidate_id
    candidate_archive_sha256 = [string]$descriptor.archive_sha256
    candidate_content_sha256 = [string]$descriptor.content_sha256
    package_source_commit = [string]$descriptor.source_commit
    context_id = [string]$state.context.context_id
    plan_id = [string]$state.plan_envelope.plan_id
    control_plane_commit = [string]$controlLock.qualification_source_commit
    control_plane_worktree_sha256 = [string]$controlLock.qualification_source_worktree_sha256
    component_abis = $controlLock.component_abis
    factorio_locks = @($environmentLocks.factorio)
    task_results = [pscustomobject][ordered]@{count=$taskRows.Count;sha256=(Get-MIRCPSha256Object -Value @($taskRows))}
    environment_results = [pscustomobject][ordered]@{count=$environmentRows.Count;sha256=(Get-MIRCPSha256Object -Value @($environmentRows))}
    qualification_manifest = [string]$qualificationManifests[0].digest
    evidence_index_sha256 = Get-MIRCPSha256File -Path $indexResult.path
    shadow_analysis_sha256 = Get-MIRCPSha256File -Path (Join-Path $repo ".mir/control-plane/shadow-analysis.json")
    mutation_calibration = [pscustomobject][ordered]@{cases=[int]$mutation.cases;false_negative_budget=[int]$mutation.false_negative_budget}
    completed_at = [string]$qualificationManifests[0].record.producer.produced_at
  }
  $record = [ordered]@{}
  foreach ($property in $body.PSObject.Properties) { $record[$property.Name] = $property.Value }
  $record.calibration_sha256 = Get-MIRCPSha256Object -Value $body
  Write-MIRCPJson -Path $Output -Value ([pscustomobject]$record) -RepoRoot $repo
  return [pscustomobject]$record
}
