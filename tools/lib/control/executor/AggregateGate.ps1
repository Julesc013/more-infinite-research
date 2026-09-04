function Complete-MIRCPAggregateGate {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [string]$TrustClass = "protected-release",
    [string]$AggregateTaskId = "",
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath -RepoRoot $repo
  $indexResult = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $EvidenceRoot
  if ([int]$indexResult.invalid -ne 0) { throw "Evidence store contains invalid objects." }
  $objects = @($indexResult.index.objects)
  $selectedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  if ([string]::IsNullOrWhiteSpace($AggregateTaskId)) {
    foreach ($row in @($state.plan.tasks)) { [void]$selectedIds.Add([string]$row.id) }
  } else {
    $aggregateTarget = @($state.plan.tasks | Where-Object { [string]$_.id -eq $AggregateTaskId -and [string]$_.kind -eq "aggregate" })
    if ($aggregateTarget.Count -ne 1) { throw "Context plan does not contain aggregate TaskNode $AggregateTaskId exactly once." }
    [void]$selectedIds.Add($AggregateTaskId)
    $changed = $true
    while ($changed) {
      $changed = $false
      foreach ($row in @($state.plan.tasks | Where-Object { $selectedIds.Contains([string]$_.id) })) {
        foreach ($dependency in @($row.depends_on)) { if ($selectedIds.Add([string]$dependency)) { $changed = $true } }
      }
    }
  }
  $taskResults = [Collections.Generic.List[object]]::new()
  $taskMap = Get-MIRCPTaskMap -RepoRoot $repo
  foreach ($row in @($state.plan.tasks | Where-Object { [string]$_.kind -ne "aggregate" -and $selectedIds.Contains([string]$_.id) })) {
    $matches = @($objects | Where-Object { [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq [string]$row.id -and [string]$_.identity_key -eq [string]$row.effective_input_sha256 -and [string]$_.status -eq "passed" -and -not [bool]$_.revoked })
    if ([string]$row.action -ne "REUSE") { $matches = @($matches | Where-Object { [string]$_.context_digest -eq [string]$state.context.context_id }) }
    if ($TrustClass -eq "protected-release") {
      $task = $taskMap[[string]$row.id]
      if ([string]$task.kind -eq "manual") { $matches = @($matches | Where-Object trust_class -eq "ci") }
      elseif ([string]$task.freshness -in @("protected-release-fresh", "always-fresh")) { $matches = @($matches | Where-Object trust_class -eq "protected-release") }
    }
    if ($matches.Count -eq 0) { throw "Aggregate gate lacks exact passing evidence for TaskNode $($row.id)." }
    if ($matches.Count -gt 1) { throw "Aggregate gate found ambiguous evidence for TaskNode $($row.id)." }
    $taskResults.Add([pscustomobject][ordered]@{task_id=[string]$row.id;status="passed";object_digest=[string]$matches[0].digest})
  }
  $registry = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "expanded-scenarios.json") | ConvertFrom-Json
  $requiresEnvironmentBatches = $selectedIds.Contains("ecosystem.measurement")
  foreach ($batch in @($registry.batches | Where-Object { $requiresEnvironmentBatches -and [bool]$_.process_required })) {
    $matches = @($objects | Where-Object { [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq [string]$batch.id -and [string]$_.context_digest -eq [string]$state.context.context_id -and [string]$_.status -eq "passed" -and -not [bool]$_.revoked })
    if ($TrustClass -eq "protected-release") { $matches = @($matches | Where-Object trust_class -eq "protected-release") }
    if ($matches.Count -eq 1) { $taskResults.Add([pscustomobject][ordered]@{task_id=[string]$batch.id;status="passed";object_digest=[string]$matches[0].digest}) }
    elseif ($matches.Count -eq 0) { throw "Aggregate gate lacks exact passing evidence for environment batch $($batch.id)." }
    else { throw "Aggregate gate found ambiguous evidence for environment batch $($batch.id)." }
  }
  foreach ($row in @($state.plan.tasks | Where-Object { [string]$_.kind -eq "aggregate" -and $selectedIds.Contains([string]$_.id) })) {
    $selectedMembers = @($row.depends_on | ForEach-Object { [string]$_ })
    $missingMembers = @($selectedMembers | Where-Object { $member = $_; @($taskResults | Where-Object task_id -eq $member).Count -ne 1 })
    if ($missingMembers.Count -gt 0) { throw "Aggregate TaskNode $($row.id) lacks exact member results: $($missingMembers -join ', ')." }
    $memberResults = @($taskResults | Where-Object { [string]$_.task_id -in $selectedMembers } | Sort-Object task_id)
    $memberPayload = @($memberResults | ForEach-Object { [pscustomobject][ordered]@{task_id=[string]$_.task_id;object_digest=[string]$_.object_digest} })
    $aggregateMatches = @($objects | Where-Object {
      [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq [string]$row.id -and
      [string]$_.context_digest -eq [string]$state.context.context_id -and
      [string]$_.identity_key -eq [string]$row.effective_input_sha256 -and
      [string]$_.status -eq "passed" -and [string]$_.trust_class -eq $TrustClass -and -not [bool]$_.revoked
    })
    if ($aggregateMatches.Count -gt 1) { throw "Aggregate gate found ambiguous evidence for aggregate TaskNode $($row.id)." }
    if ($aggregateMatches.Count -eq 1) {
      $existingAggregate = (Read-MIRCPEvidenceObject -Digest ([string]$aggregateMatches[0].digest) -RepoRoot $repo -Root $EvidenceRoot).object
      if (-not [bool]$existingAggregate.payload.aggregate -or
          (Get-MIRCPSha256Object -Value @($existingAggregate.payload.members)) -ne (Get-MIRCPSha256Object -Value $memberPayload)) {
        throw "Existing aggregate TaskNode $($row.id) does not bind the exact selected member closure."
      }
      $aggregateMarker = [pscustomobject][ordered]@{
        schema = 1
        task_id = [string]$row.id
        status = "passed"
        context_digest = [string]$state.context.context_id
        identity_key = [string]$row.effective_input_sha256
        object_digest = [string]$aggregateMatches[0].digest
      }
    } else {
      $aggregateMarker = Write-MIRCPTaskResultEvidence -State $state -PlanRow $row -Status passed `
        -Payload ([pscustomobject][ordered]@{aggregate=$true;members=$memberPayload}) `
        -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
    }
    $taskResults.Add($aggregateMarker)
  }
  $producer = New-MIRCPExecutorProducer -TrustClass $TrustClass -RepoRoot $repo
  $manifest = New-MIRCPExecutionManifest -ContextDigest ([string]$state.context.context_id) -PlanId ([string]$state.plan_envelope.plan_id) -Producer $producer -TaskResults @($taskResults) -Status passed
  $manifestObject = New-MIRCPEvidenceObject -Kind execution-manifest -ContextDigest ([string]$state.context.context_id) -IdentityKey (Get-MIRCPSha256Object -Value $manifest) `
    -Subject ([pscustomobject][ordered]@{plan_id=[string]$state.plan_envelope.plan_id;target=[string]$state.plan.target}) -Producer $producer -Payload $manifest -Links @($taskResults.object_digest)
  $stored = Write-MIRCPEvidenceObject -Object $manifestObject -RepoRoot $repo -Root $EvidenceRoot
  return [pscustomobject][ordered]@{status="passed";context_digest=[string]$state.context.context_id;plan_id=[string]$state.plan_envelope.plan_id;aggregate_task=if([string]::IsNullOrWhiteSpace($AggregateTaskId)){"all"}else{$AggregateTaskId};task_results=$taskResults.Count;manifest_object=[string]$stored.digest}
}
