function Get-MIRCPShadowAuthority {
  param([string]$RepoRoot = "")
  return Read-MIRCPJson -Path ".mir/control-plane/v4-v5-equivalence.json" -RepoRoot $RepoRoot
}

function Get-MIRCPShadowBaselinePath {
  param([Parameter(Mandatory)][string]$Release)
  if ($Release -eq "3.2.2") { return ".mir/control-plane/baselines/3.2.2-v4.json" }
  if ($Release -eq "2.5.0") { return ".mir/control-plane/baselines/2.5.0-p9-v4.json" }
  throw "No governed v4 shadow baseline for $Release."
}

function New-MIRCPShadowOutcome {
  param(
    [Parameter(Mandatory)][string]$Status,
    [Parameter(Mandatory)][string]$Reason,
    [string]$Path = "",
    [string]$Sha256 = ""
  )
  return [pscustomobject][ordered]@{status=$Status;reason=$Reason;path=$Path;sha256=$Sha256}
}

function Get-MIRCPShadowC24Outcomes {
  param([Parameter(Mandatory)]$ReleaseRecord, [string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $candidateSha = [string]$ReleaseRecord.package.archive_sha256
  $paths = [ordered]@{
    "approved-delta" = "approved-delta/3.2.1-to-3.2.2.json"
    "upgrade-result" = ".mir/evidence/3.2.2-upgrade-proof.json"
    "performance-result" = ".mir/evidence/3.2.2-performance-regression.json"
    "manual-result" = ".mir/evidence/3.2.2-manual-review-attestation.json"
    "aggregate-verdict" = ".mir/evidence/3.2.2-local-automated-qualification.json"
  }
  $out = [ordered]@{}
  foreach ($entry in $paths.GetEnumerator()) {
    $path = Join-Path $repo $entry.Value
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      $out[$entry.Key] = New-MIRCPShadowOutcome -Status pending -Reason "governed proof file is missing" -Path $entry.Value
      continue
    }
    $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    $recordStatus = if ($entry.Key -eq "approved-delta") { [string]$record.status } else { [string]$record.status }
    $recordCandidate = switch ($entry.Key) {
      "approved-delta" { [string]$record.current.archive_sha256 }
      "manual-result" { [string]$record.candidate_sha256 }
      "aggregate-verdict" { [string]$record.candidate_descriptor.sha256 }
      default { [string]$record.candidate.archive_sha256 }
    }
    $passedStatus = if ($entry.Key -eq "approved-delta") { $recordStatus -eq "approved" } else { $recordStatus -eq "passed" }
    $status = if ($passedStatus -and $recordCandidate -eq $candidateSha) { "passed" } else { "failed" }
    $reason = if ($status -eq "passed") { "committed proof is passing and exact-candidate bound" } else { "committed proof status or candidate binding differs" }
    $out[$entry.Key] = New-MIRCPShadowOutcome -Status $status -Reason $reason -Path $entry.Value -Sha256 (Get-MIRCPSha256File -Path $path)
  }
  $out["seal-inputs"] = New-MIRCPShadowOutcome -Status "exception-not-admissible" `
    -Reason "C24 was tagged without a protected capsule or schema-4 seal; its calibration-only exception cannot satisfy a future release gate"
  return [pscustomobject]$out
}

function Get-MIRCPShadowP9Outcomes {
  param(
    [Parameter(Mandatory)]$ReleaseRecord,
    [string]$ObservedProofRoot = ""
  )
  $out = [ordered]@{}
  foreach ($dimension in @("approved-delta", "upgrade-result", "performance-result", "manual-result", "aggregate-verdict", "seal-inputs")) {
    $out[$dimension] = New-MIRCPShadowOutcome -Status pending -Reason "no committed admissible exact-P9 proof"
  }
  if (-not [string]::IsNullOrWhiteSpace($ObservedProofRoot) -and (Test-Path -LiteralPath $ObservedProofRoot -PathType Container)) {
    foreach ($row in @(
      @{dimension="upgrade-result";file="2.5.0-upgrade-proof.json"},
      @{dimension="performance-result";file="2.5.0-performance-regression.json"}
    )) {
      $path = Join-Path $ObservedProofRoot $row.file
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
      $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
      if ([string]$record.status -eq "passed" -and [string]$record.candidate.archive_sha256 -eq [string]$ReleaseRecord.package.archive_sha256) {
        $out[$row.dimension] = New-MIRCPShadowOutcome -Status "observed-unadmitted" `
          -Reason "exact-candidate focused proof exists outside the governed v5 branch and is not admitted as qualification evidence" `
          -Path $row.file -Sha256 (Get-MIRCPSha256File -Path $path)
      }
    }
  }
  return [pscustomobject]$out
}

function New-MIRCPShadowCandidateAnalysis {
  param(
    [Parameter(Mandatory)][ValidateSet("3.2.2", "2.5.0")][string]$Release,
    [Parameter(Mandatory)][string]$SourceRepoRoot,
    [string]$ContextPath = "",
    [string]$ObservedProofRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $source = (Resolve-Path -LiteralPath $SourceRepoRoot).Path
  $authority = Get-MIRCPShadowAuthority -RepoRoot $repo
  $baselinePath = Get-MIRCPShadowBaselinePath -Release $Release
  $baseline = Read-MIRCPJson -Path $baselinePath -RepoRoot $repo
  $releaseRecord = Get-MIRCPReleaseByVersion -Release $Release -RepoRoot $repo
  $sourceCommit = ([string](& git -C $source rev-parse HEAD)).Trim()
  if ($LASTEXITCODE -ne 0 -or $sourceCommit -ne [string]$releaseRecord.package.source_commit) { throw "Shadow source for $Release is not its exact package-source commit." }
  $registry = if ([string]::IsNullOrWhiteSpace($ContextPath)) {
    New-MIRCPExecutionRegistry -Target ([string]$releaseRecord.target) -RepoRoot $source
  } else {
    $context = Assert-MIRCPVerificationContext -Path $ContextPath
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $context.path "context-manifest.json") | ConvertFrom-Json
    if ([string]$manifest.release -ne $Release) { throw "Shadow context release differs from requested analysis release." }
    Get-Content -Raw -LiteralPath (Join-Path $context.path "expanded-scenarios.json") | ConvertFrom-Json
  }
  [void](Assert-MIRCPExecutionRegistry -Registry $registry -RepoRoot $source)
  $plan = New-MIRCPPlan -Mode calibrate-fresh -ChangedPath @("scripts/MIRControlPlane/Shadow.ps1") `
    -Target ([string]$releaseRecord.target) -Release $Release -SourceRepoRoot $source -RepoRoot $repo
  $candidatePassed = [string]$baseline.candidate.archive_sha256 -eq [string]$releaseRecord.package.archive_sha256 -and
    [string]$baseline.candidate.content_sha256 -eq [string]$releaseRecord.package.content_sha256 -and
    [string]$baseline.candidate.governed_package_source_commit -eq [string]$releaseRecord.package.source_commit

  $unmapped = [Collections.Generic.List[string]]::new()
  $missingTasks = [Collections.Generic.List[string]]::new()
  foreach ($obligation in @($baseline.obligations)) {
    $mapping = $authority.obligation_mapping.PSObject.Properties[[string]$obligation.id]
    if ($null -eq $mapping) { $unmapped.Add([string]$obligation.id); continue }
    foreach ($taskId in @($mapping.Value)) {
      if (@($plan.plan.tasks.id | ForEach-Object { [string]$_ }) -notcontains [string]$taskId) { $missingTasks.Add([string]$taskId) }
    }
  }
  foreach ($taskId in @($authority.additional_v5_obligations)) {
    if (@($plan.plan.tasks.id | ForEach-Object { [string]$_ }) -notcontains [string]$taskId) { $missingTasks.Add([string]$taskId) }
  }
  $obligationsPassed = $unmapped.Count -eq 0 -and $missingTasks.Count -eq 0 -and @($baseline.obligations).Count -eq @($authority.obligation_mapping.PSObject.Properties).Count

  $baselineScenarios = @($baseline.scenarios | ForEach-Object { [string]$_ } | Sort-Object)
  $v5Scenarios = @($registry.scenarios.id | ForEach-Object { [string]$_ } | Sort-Object)
  $missingScenarios = @($baselineScenarios | Where-Object { $v5Scenarios -notcontains $_ })
  $addedScenarioIds = @($v5Scenarios | Where-Object { $baselineScenarios -notcontains $_ })
  $addedNames = @($addedScenarioIds | ForEach-Object { ($_ -split '/', 3)[2] } | Sort-Object)
  $expectedAdditions = @($authority.allowed_v5_scenario_additions | ForEach-Object { [string]$_ } | Sort-Object)
  $scenariosPassed = $missingScenarios.Count -eq 0 -and (($addedNames -join "`n") -ceq ($expectedAdditions -join "`n"))

  $environmentFailures = [Collections.Generic.List[string]]::new()
  foreach ($scenarioId in $baselineScenarios) {
    $scenario = @($registry.scenarios | Where-Object id -eq $scenarioId)
    $batch = @($registry.batches | Where-Object { @($_.scenario_ids | ForEach-Object { [string]$_ }) -contains $scenarioId })
    if ($scenario.Count -ne 1 -or $batch.Count -ne 1 -or -not [bool]$batch[0].process_required) { $environmentFailures.Add($scenarioId) }
  }
  $environmentsPassed = $environmentFailures.Count -eq 0
  $outcomes = if ($Release -eq "3.2.2") { Get-MIRCPShadowC24Outcomes -ReleaseRecord $releaseRecord -RepoRoot $repo } else { Get-MIRCPShadowP9Outcomes -ReleaseRecord $releaseRecord -ObservedProofRoot $ObservedProofRoot }
  $dimensions = [ordered]@{
    "candidate-identity" = [pscustomobject][ordered]@{status=if($candidatePassed){"passed"}else{"failed"};baseline_archive_sha256=[string]$baseline.candidate.archive_sha256;v5_archive_sha256=[string]$releaseRecord.package.archive_sha256}
    "required-proof-obligations" = [pscustomobject][ordered]@{status=if($obligationsPassed){"passed"}else{"failed"};v4_obligations=@($baseline.obligations).Count;unmapped=@($unmapped);missing_v5_tasks=@($missingTasks | Sort-Object -Unique)}
    "scenario-identities" = [pscustomobject][ordered]@{status=if($scenariosPassed){"passed"}else{"failed"};v4=$baselineScenarios.Count;v5=$v5Scenarios.Count;missing=$missingScenarios;added=$addedScenarioIds}
    "environment-identities" = [pscustomobject][ordered]@{status=if($environmentsPassed){"passed"}else{"failed"};mapped=$baselineScenarios.Count;failures=@($environmentFailures)}
  }
  foreach ($dimension in @("approved-delta", "upgrade-result", "performance-result", "manual-result", "aggregate-verdict", "seal-inputs")) { $dimensions[$dimension] = $outcomes.$dimension }
  $pending = @($dimensions.GetEnumerator() | Where-Object { [string]$_.Value.status -ne "passed" } | ForEach-Object { [string]$_.Key })
  $structuralPlan = [pscustomobject][ordered]@{
    schema = 1
    release = $Release
    target = [string]$releaseRecord.target
    stage = [string]$plan.plan.stage
    aggregate_is_result_only = [bool]$plan.plan.aggregate_is_result_only
    tasks = @($plan.plan.tasks | Sort-Object id | ForEach-Object {
      [pscustomobject][ordered]@{
        id = [string]$_.id
        kind = [string]$_.kind
        layer = [string]$_.layer
        action = [string]$_.action
        depends_on = @($_.depends_on | ForEach-Object { [string]$_ } | Sort-Object)
      }
    })
  }
  return [pscustomobject][ordered]@{
    release = $Release
    candidate_id = [string]$releaseRecord.candidate_id
    target = [string]$releaseRecord.target
    source_commit = $sourceCommit
    baseline_sha256 = [string]$baseline.baseline_sha256
    v5_structural_plan_sha256 = Get-MIRCPSha256Object -Value $structuralPlan
    v5_registry_sha256 = Get-MIRCPSha256Object -Value $registry
    status = if ($pending.Count -eq 0) { "passed" } else { "pending" }
    pending_dimensions = $pending
    dimensions = [pscustomobject]$dimensions
  }
}

function Get-MIRCPShadowStatus {
  param([string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $authority = Get-MIRCPShadowAuthority -RepoRoot $repo
  $analysisPath = Join-Path $repo ".mir/control-plane/shadow-analysis.json"
  $analysis = if (Test-Path -LiteralPath $analysisPath -PathType Leaf) { Get-Content -Raw -LiteralPath $analysisPath | ConvertFrom-Json } else { $null }
  return [pscustomobject][ordered]@{state=[string]$authority.state;analysis_status=if($null-eq$analysis){"missing"}else{[string]$analysis.status};candidates=if($null-eq$analysis){@()}else{@($analysis.candidates)}}
}

function Assert-MIRCPShadowContract {
  param([string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $authority = Get-MIRCPShadowAuthority -RepoRoot $repo
  $required = @("candidate-identity", "required-proof-obligations", "scenario-identities", "environment-identities", "approved-delta", "upgrade-result", "performance-result", "manual-result", "aggregate-verdict", "seal-inputs")
  if ([int]$authority.schema -ne 1 -or [string]$authority.authority -ne "mir-control-plane-v5-shadow-equivalence") { throw "Shadow equivalence authority is invalid." }
  foreach ($dimension in $required) { if (@($authority.dimensions) -notcontains $dimension) { throw "Shadow authority omits dimension $dimension." } }
  if (-not [bool]$authority.acceptance.exact_plan_obligation_equivalence -or -not [bool]$authority.acceptance.exact_verdict_equivalence -or -not [bool]$authority.acceptance.fresh_independent_calibration_required) { throw "Shadow acceptance weakened a required condition." }
  $taskMap = Get-MIRCPTaskMap -RepoRoot $repo
  $baselineObligations = @((Read-MIRCPJson -Path (Get-MIRCPShadowBaselinePath -Release "3.2.2") -RepoRoot $repo).obligations.id | ForEach-Object { [string]$_ } | Sort-Object)
  $mappingKeys = @($authority.obligation_mapping.PSObject.Properties.Name | Sort-Object)
  if (($baselineObligations -join "`n") -cne ($mappingKeys -join "`n")) { throw "Shadow obligation mapping does not exactly cover the v4 baseline." }
  foreach ($property in @($authority.obligation_mapping.PSObject.Properties)) {
    foreach ($taskId in @($property.Value)) { if (-not $taskMap.ContainsKey([string]$taskId)) { throw "Shadow mapping references unknown TaskNode $taskId." } }
  }
  foreach ($proof in @($authority.proofs)) {
    $path = Join-Path $repo ([string]$proof.path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Shadow proof is missing: $($proof.path)" }
  }
  $analysis = Read-MIRCPJson -Path ".mir/control-plane/shadow-analysis.json" -RepoRoot $repo
  $body = [ordered]@{}
  foreach ($property in $analysis.PSObject.Properties | Where-Object Name -ne "analysis_sha256") { $body[$property.Name] = $property.Value }
  if ([string]$analysis.analysis_sha256 -ne (Get-MIRCPSha256Object -Value ([pscustomobject]$body))) { throw "Shadow analysis self-digest is stale." }
  if ([string]$authority.state -eq "accepted" -and ([string]$analysis.status -ne "passed" -or @($analysis.pending_dimensions).Count -ne 0)) { throw "Shadow authority claims acceptance without complete proof." }
  return [pscustomobject][ordered]@{state=[string]$authority.state;dimensions=@($authority.dimensions).Count;candidates=@($authority.calibration_candidates).Count;proofs=@($authority.proofs).Count;analysis_status=[string]$analysis.status;pending=@($analysis.pending_dimensions)}
}
