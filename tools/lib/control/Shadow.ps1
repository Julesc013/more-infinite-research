function Get-MIRCPShadowAuthority {
  param([string]$RepoRoot = "")
  return Read-MIRCPJson -Path ".mir/control-plane/v4-v5-equivalence.json" -RepoRoot $RepoRoot
}

function Get-MIRCPShadowBaselinePath {
  param([Parameter(Mandatory)][string]$Release)
  if ($Release -eq "3.2.2") { return "validation/baselines/control/3.2.2-v4.json" }
  if ($Release -eq "2.5.0") { return "validation/baselines/control/2.5.0-p9-v4.json" }
  throw "No governed v4 shadow baseline for $Release."
}

function Test-MIRCPInheritedShadowCutoverContract {
  param(
    [Parameter(Mandatory)]$Authority,
    [Parameter(Mandatory)]$Cutover,
    [Parameter(Mandatory)]$CalibrationProof,
    [Parameter(Mandatory)]$ControlLock,
    [Parameter(Mandatory)]$Policy,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$ProofSha256,
    [Parameter(Mandatory)][bool]$ProofRevoked
  )
  $failures = [Collections.Generic.List[string]]::new()
  if ([string]$Authority.state -ne "accepted") { $failures.Add("global v4/v5 equivalence is not accepted") }
  if ([string]$Cutover.state -ne "accepted") { $failures.Add("target cutover is not accepted") }
  if ([string]$Cutover.calibration_release -notin @($Authority.calibration_candidates | ForEach-Object { [string]$_ })) { $failures.Add("target cutover does not name a calibration release") }
  if ([string]$CalibrationProof.authority -ne "mir-control-plane-v5-fresh-independent-calibration" -or [string]$CalibrationProof.status -ne "passed") { $failures.Add("fresh calibration proof is not passing") }
  if ([string]$CalibrationProof.release -ne [string]$Cutover.calibration_release) { $failures.Add("fresh calibration proof release differs from target cutover") }
  if ($ProofSha256 -ne [string]$Cutover.proof_sha256) { $failures.Add("fresh calibration proof digest differs from target cutover") }
  if ($ProofRevoked) { $failures.Add("fresh calibration proof is revoked") }
  if ([string]$CalibrationProof.control_plane_commit -ne [string]$Cutover.implementation_commit) { $failures.Add("fresh calibration implementation commit differs from target cutover") }
  if ($null -eq $CalibrationProof.component_abis -or $null -eq $Cutover.component_abis -or $null -eq $ControlLock.component_abis -or $null -eq $Policy.component_abis) {
    $failures.Add("component ABIs differ from the accepted calibration")
  } else {
    $proofAbis = Get-MIRCPSha256Object -Value $CalibrationProof.component_abis
    $cutoverAbis = Get-MIRCPSha256Object -Value $Cutover.component_abis
    $contextAbis = Get-MIRCPSha256Object -Value $ControlLock.component_abis
    $policyAbis = Get-MIRCPSha256Object -Value $Policy.component_abis
    if ($proofAbis -ne $cutoverAbis -or $proofAbis -ne $contextAbis -or $proofAbis -ne $policyAbis) { $failures.Add("component ABIs differ from the accepted calibration") }
  }
  return [pscustomobject][ordered]@{status=if($failures.Count -eq 0){"passed"}else{"failed"};target=$Target;calibration_release=[string]$Cutover.calibration_release;failures=@($failures)}
}

function Assert-MIRCPInheritedShadowCutover {
  param(
    [Parameter(Mandatory)]$ReleaseRecord,
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$SourceRepoRoot,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $authority = Get-MIRCPShadowAuthority -RepoRoot $repo
  if ([string]$ReleaseRecord.release -in @($authority.calibration_candidates | ForEach-Object { [string]$_ })) { throw "Calibration candidates cannot use inherited shadow admission." }
  $cutoverProperty = $authority.target_cutovers.PSObject.Properties[[string]$ReleaseRecord.target]
  if ($null -eq $cutoverProperty) { throw "No governed shadow cutover exists for target $($ReleaseRecord.target)." }
  $cutover = $cutoverProperty.Value
  if ([string]::IsNullOrWhiteSpace([string]$cutover.proof_path)) { throw "Target shadow cutover has no calibration proof path." }
  $proofPath = Join-Path $repo ([string]$cutover.proof_path)
  if (-not (Test-Path -LiteralPath $proofPath -PathType Leaf)) { throw "Accepted target shadow calibration proof is missing." }
  $proof = Get-Content -Raw -LiteralPath $proofPath | ConvertFrom-Json
  $proofSha256 = Get-MIRCPSha256File -Path $proofPath
  $proofBody = [ordered]@{}
  foreach ($property in $proof.PSObject.Properties | Where-Object Name -ne "calibration_sha256") { $proofBody[$property.Name] = $property.Value }
  if ([string]$proof.calibration_sha256 -ne (Get-MIRCPSha256Object -Value ([pscustomobject]$proofBody))) { throw "Fresh calibration proof self-digest is invalid." }
  $calibrationRelease = Get-MIRCPReleaseByVersion -Release ([string]$cutover.calibration_release) -RepoRoot $repo
  if ([string]$proof.candidate_archive_sha256 -ne [string]$calibrationRelease.package.archive_sha256 -or
      [string]$proof.candidate_content_sha256 -ne [string]$calibrationRelease.package.content_sha256 -or
      [string]$proof.package_source_commit -ne [string]$calibrationRelease.package.source_commit) {
    throw "Fresh calibration proof is not exact-candidate bound to its calibration release."
  }
  $revocations = Get-MIRCPEvidenceRevocationAuthority -RepoRoot $repo
  $revocableDigests = @($proofSha256, [string]$proof.qualification_manifest)
  $proofRevoked = @($revocations.rules | Where-Object {
    [bool]$_.active -and [string]$_.type -eq "object-digest-set" -and
    @($_.digests | ForEach-Object { [string]$_ } | Where-Object { $_ -in $revocableDigests }).Count -ne 0
  }).Count -ne 0
  $context = Assert-MIRCPVerificationContext -Path $ContextPath
  $manifest = Get-Content -Raw -LiteralPath (Join-Path $context.path "context-manifest.json") | ConvertFrom-Json
  $controlLock = Get-Content -Raw -LiteralPath (Join-Path $context.path "control-plane-lock.json") | ConvertFrom-Json
  if ([string]$manifest.release -ne [string]$ReleaseRecord.release) { throw "Inherited shadow context release mismatch." }
  $source = (Resolve-Path -LiteralPath $SourceRepoRoot).Path
  $sourceCommit = ([string](& git -C $source rev-parse HEAD)).Trim()
  $sourceTree = ([string](& git -C $source rev-parse "HEAD^{tree}")).Trim()
  $sourceWorktree = Get-MIRCPTrackedWorktreeSha256 -SourceRepoRoot $source
  if ($LASTEXITCODE -ne 0 -or $sourceCommit -ne [string]$controlLock.scenario_source_commit -or
      $sourceTree -ne [string]$controlLock.scenario_source_tree -or $sourceWorktree -ne [string]$controlLock.scenario_source_worktree_sha256) {
    throw "Inherited shadow source does not match its immutable context qualification-source lock."
  }
  foreach ($lockedPath in @(".mir/control-plane/v4-v5-equivalence.json", [string]$cutover.proof_path)) {
    $matches = @($controlLock.files | Where-Object path -eq $lockedPath)
    if ($matches.Count -ne 1 -or [string]$matches[0].sha256 -ne (Get-MIRCPSha256File -Path (Join-Path $repo $lockedPath))) { throw "Inherited shadow context does not lock exact authority $lockedPath." }
  }
  $result = Test-MIRCPInheritedShadowCutoverContract -Authority $authority -Cutover $cutover -CalibrationProof $proof `
    -ControlLock $controlLock -Policy (Get-MIRCPPolicy -RepoRoot $repo) -Target ([string]$ReleaseRecord.target) `
    -ProofSha256 $proofSha256 -ProofRevoked $proofRevoked
  if ([string]$result.status -ne "passed") { throw "Inherited shadow cutover rejected $($ReleaseRecord.release): $(@($result.failures) -join '; ')." }
  & git -C $repo merge-base --is-ancestor ([string]$cutover.implementation_commit) ([string]$controlLock.qualification_source_commit)
  if ($LASTEXITCODE -ne 0) { throw "Context control-plane commit does not descend from the accepted cutover implementation." }
  return $result
}

function Assert-MIRCPInheritedReleaseProofClosure {
  param(
    [Parameter(Mandatory)]$ReleaseRecord,
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$EvidenceRoot,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $context = Assert-MIRCPVerificationContext -Path $ContextPath
  $plan = Get-Content -Raw -LiteralPath (Join-Path $context.path "plan.json") | ConvertFrom-Json
  $index = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $EvidenceRoot
  if ([int]$index.invalid -ne 0) { throw "Inherited shadow evidence store contains invalid objects." }
  foreach ($binding in @(@{task="qualification.full";trust="protected-release"}, @{task="seal";trust="protected-release"})) {
    $row = @($plan.plan.tasks | Where-Object id -eq $binding.task)
    $matches = @($index.index.objects | Where-Object {
      [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq $binding.task -and
      [string]$_.context_digest -eq [string]$context.context_id -and
      [string]$_.identity_key -eq [string]$row[0].effective_input_sha256 -and
      [string]$_.status -eq "passed" -and [string]$_.trust_class -eq $binding.trust -and -not [bool]$_.revoked
    })
    if ($row.Count -ne 1 -or $matches.Count -ne 1) { throw "Inherited shadow admission requires one exact unrevoked $($binding.task) result." }
    if ($binding.task -eq "seal") {
      $taskObject = (Read-MIRCPEvidenceObject -Digest ([string]$matches[0].digest) -RepoRoot $repo -Root $EvidenceRoot).object
      $seal = (Read-MIRCPEvidenceObject -Digest ([string]$taskObject.payload.seal_object) -RepoRoot $repo -Root $EvidenceRoot).object
      if ([string]$seal.kind -ne "seal" -or [string]$seal.payload.status -ne "passed" -or
          [string]$seal.subject.archive_sha256 -ne [string]$ReleaseRecord.package.archive_sha256) { throw "Inherited shadow seal is not exact-candidate bound." }
    }
  }
  return [pscustomobject][ordered]@{status="passed";release=[string]$ReleaseRecord.release;context_id=[string]$context.context_id}
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
  $out["seal-inputs"] = New-MIRCPShadowOutcome -Status "passed" `
    -Reason "v4 and v5 agree that C24 had no protected seal; this historical equivalence is never admissible as a future release seal"
  return [pscustomobject]$out
}

function Get-MIRCPShadowP9Outcomes {
  param(
    [Parameter(Mandatory)]$ReleaseRecord,
    [string]$ObservedProofRoot = "",
    [string]$ContextPath = "",
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $hasContext = -not [string]::IsNullOrWhiteSpace($ContextPath)
  $hasEvidence = -not [string]::IsNullOrWhiteSpace($EvidenceRoot)
  if ($hasContext -ne $hasEvidence) { throw "Operational P9 shadow comparison requires both ContextPath and EvidenceRoot." }
  $operationalCutover = $hasContext -and $hasEvidence
  $out = [ordered]@{}
  foreach ($dimension in @("approved-delta", "upgrade-result", "performance-result", "manual-result", "aggregate-verdict", "seal-inputs")) {
    $out[$dimension] = if ($operationalCutover) {
      New-MIRCPShadowOutcome -Status pending -Reason "no admitted exact-P9 operational proof"
    } else {
      New-MIRCPShadowOutcome -Status passed -Reason "admission parity: v4=pending and v5=pending; release-specific proof remains required for operational cutover"
    }
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
        $out[$row.dimension] = New-MIRCPShadowOutcome -Status $(if ($operationalCutover) { "observed-unadmitted" } else { "passed" }) `
          -Reason $(if ($operationalCutover) { "exact-candidate focused proof exists outside the governed v5 branch and is not admitted as qualification evidence" } else { "admission parity remains v4=pending and v5=pending; an external focused observation exists but is not admitted" }) `
          -Path $row.file -Sha256 (Get-MIRCPSha256File -Path $path)
      }
    }
  }
  if ($operationalCutover) {
    $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
    $context = Assert-MIRCPVerificationContext -Path $ContextPath
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $context.path "context-manifest.json") | ConvertFrom-Json
    $planEnvelope = Get-Content -Raw -LiteralPath (Join-Path $context.path "plan.json") | ConvertFrom-Json
    if ([string]$manifest.release -ne [string]$ReleaseRecord.release) { throw "P9 shadow evidence context release mismatch." }
    $index = Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $EvidenceRoot
    if ([int]$index.invalid -ne 0) { throw "P9 shadow evidence store contains invalid objects." }
    foreach ($binding in @(
      @{dimension="approved-delta";task="approved-delta.measurement";trust="protected-release"},
      @{dimension="upgrade-result";task="upgrade.measurement";trust="protected-release"},
      @{dimension="performance-result";task="performance.measurement";trust="protected-release"},
      @{dimension="manual-result";task="manual.acceptance";trust="ci"},
      @{dimension="aggregate-verdict";task="qualification.full";trust="protected-release"},
      @{dimension="seal-inputs";task="seal";trust="protected-release"}
    )) {
      $planRow = @($planEnvelope.plan.tasks | Where-Object id -eq $binding.task)
      if ($planRow.Count -ne 1) { continue }
      $matches = @($index.index.objects | Where-Object {
        [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq $binding.task -and
        [string]$_.context_digest -eq [string]$context.context_id -and
        [string]$_.identity_key -eq [string]$planRow[0].effective_input_sha256 -and
        [string]$_.status -eq "passed" -and [string]$_.trust_class -eq $binding.trust -and -not [bool]$_.revoked
      })
      if ($matches.Count -ne 1) { continue }
      $object = (Read-MIRCPEvidenceObject -Digest ([string]$matches[0].digest) -RepoRoot $repo -Root $EvidenceRoot).object
      if ($binding.task -eq "seal") {
        $sealDigest = [string]$object.payload.seal_object
        if ($sealDigest -notmatch '^[0-9A-F]{64}$') { continue }
        $sealObject = (Read-MIRCPEvidenceObject -Digest $sealDigest -RepoRoot $repo -Root $EvidenceRoot).object
        if ([string]$sealObject.kind -ne "seal" -or [string]$sealObject.payload.status -ne "passed" -or
            [string]$sealObject.subject.archive_sha256 -ne [string]$ReleaseRecord.package.archive_sha256) { continue }
      }
      $out[$binding.dimension] = New-MIRCPShadowOutcome -Status "passed" `
        -Reason "exact unrevoked context-bound v5 evidence admitted" -Path "evidence:$([string]$matches[0].digest)" -Sha256 ([string]$matches[0].digest)
    }
  }
  return [pscustomobject]$out
}

function New-MIRCPShadowCandidateAnalysis {
  param(
    [Parameter(Mandatory)][string]$Release,
    [Parameter(Mandatory)][string]$SourceRepoRoot,
    [string]$ContextPath = "",
    [string]$ObservedProofRoot = "",
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $source = (Resolve-Path -LiteralPath $SourceRepoRoot).Path
  $authority = Get-MIRCPShadowAuthority -RepoRoot $repo
  if ($Release -notin @($authority.calibration_candidates | ForEach-Object { [string]$_ })) { throw "Release $Release is not a governed shadow calibration candidate." }
  $baselinePath = Get-MIRCPShadowBaselinePath -Release $Release
  $baseline = Read-MIRCPJson -Path $baselinePath -RepoRoot $repo
  $releaseRecord = Get-MIRCPReleaseByVersion -Release $Release -RepoRoot $repo
  $sourceCommit = ([string](& git -C $source rev-parse HEAD)).Trim()
  if ([string]::IsNullOrWhiteSpace($ContextPath)) {
    if ($LASTEXITCODE -ne 0 -or $sourceCommit -ne [string]$releaseRecord.package.source_commit) {
      throw "Shadow baseline source for $Release is not its exact package-source commit."
    }
  } else {
    $context = Assert-MIRCPVerificationContext -Path $ContextPath
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $context.path "context-manifest.json") | ConvertFrom-Json
    if ([string]$manifest.release -ne $Release) { throw "Shadow context release differs from requested analysis release." }
    $controlLock = Get-Content -Raw -LiteralPath (Join-Path $context.path "control-plane-lock.json") | ConvertFrom-Json
    $sourceTree = ([string](& git -C $source rev-parse "HEAD^{tree}")).Trim()
    $worktreeSha256 = Get-MIRCPTrackedWorktreeSha256 -SourceRepoRoot $source
    if ($LASTEXITCODE -ne 0 -or $sourceCommit -ne [string]$controlLock.scenario_source_commit -or
        $sourceTree -ne [string]$controlLock.scenario_source_tree -or
        $worktreeSha256 -ne [string]$controlLock.scenario_source_worktree_sha256) {
      throw "Shadow source for $Release does not match its immutable context qualification-source lock."
    }
  }
  $registry = if ([string]::IsNullOrWhiteSpace($ContextPath)) {
    New-MIRCPExecutionRegistry -Target ([string]$releaseRecord.target) -RepoRoot $source
  } else {
    Get-Content -Raw -LiteralPath (Join-Path $context.path "expanded-scenarios.json") | ConvertFrom-Json
  }
  [void](Assert-MIRCPExecutionRegistry -Registry $registry -RepoRoot $source)
  $plan = New-MIRCPPlan -Mode calibrate-fresh -ChangedPath @("tools/lib/control/Shadow.ps1") `
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
  $environmentMappings = [Collections.Generic.List[object]]::new()
  $baselineEnvironments = @($baseline.environments)
  $baselineEnvironmentIds = @($baselineEnvironments.test_id | ForEach-Object { [string]$_ } | Sort-Object)
  if (($baselineEnvironmentIds -join "`n") -cne ($baselineScenarios -join "`n")) {
    $environmentFailures.Add("baseline environment rows do not exactly cover baseline scenario identities")
  }
  foreach ($scenarioId in $baselineScenarios) {
    $v4 = @($baselineEnvironments | Where-Object test_id -eq $scenarioId)
    $scenario = @($registry.scenarios | Where-Object id -eq $scenarioId)
    $batch = @($registry.batches | Where-Object { @($_.scenario_ids | ForEach-Object { [string]$_ }) -contains $scenarioId })
    if ($v4.Count -ne 1 -or $scenario.Count -ne 1 -or $batch.Count -ne 1) {
      $environmentFailures.Add("$scenarioId does not resolve to exactly one v4 row, v5 scenario, and v5 batch")
      continue
    }
    $v4Hashes = @([string]$v4[0].definition_sha256, [string]$v4[0].scenario_sha256, [string]$v4[0].input_key)
    $v5Signature = [string]$scenario[0].environment.signature_sha256
    $batchSignature = [string]$batch[0].environment_signature
    if (@($v4Hashes | Where-Object { $_ -notmatch '^[0-9A-F]{64}$' }).Count -ne 0 -or
        $v5Signature -notmatch '^[0-9A-F]{64}$' -or $batchSignature -ne $v5Signature -or
        -not [bool]$batch[0].process_required -or @($batch[0].scenario_ids).Count -ne 1 -or
        [string]$batch[0].scenario_ids[0] -ne $scenarioId) {
      $environmentFailures.Add("$scenarioId has a non-exact identity or non-isolated process batch")
      continue
    }
    $environmentMappings.Add([pscustomobject][ordered]@{
      scenario_id = $scenarioId
      v4_definition_sha256 = [string]$v4[0].definition_sha256
      v4_scenario_sha256 = [string]$v4[0].scenario_sha256
      v4_input_key = [string]$v4[0].input_key
      v5_environment_signature = $v5Signature
      v5_batch_id = [string]$batch[0].id
      v5_authority_sha256 = Get-MIRCPSha256Object -Value $scenario[0].authority
    })
  }
  if (@($baselineEnvironments.input_key | Sort-Object -Unique).Count -ne $baselineScenarios.Count) {
    $environmentFailures.Add("v4 baseline input identities are not unique")
  }
  if (@($environmentMappings.v5_environment_signature | Sort-Object -Unique).Count -ne $baselineScenarios.Count -or
      @($environmentMappings.v5_batch_id | Sort-Object -Unique).Count -ne $baselineScenarios.Count) {
    $environmentFailures.Add("v5 environment signatures or process batches are not one-to-one")
  }
  $environmentsPassed = $environmentFailures.Count -eq 0 -and $environmentMappings.Count -eq $baselineScenarios.Count
  $outcomes = if ($Release -eq "3.2.2") { Get-MIRCPShadowC24Outcomes -ReleaseRecord $releaseRecord -RepoRoot $repo } else { Get-MIRCPShadowP9Outcomes -ReleaseRecord $releaseRecord -ObservedProofRoot $ObservedProofRoot -ContextPath $ContextPath -EvidenceRoot $EvidenceRoot -RepoRoot $repo }
  $dimensions = [ordered]@{
    "candidate-identity" = [pscustomobject][ordered]@{status=if($candidatePassed){"passed"}else{"failed"};baseline_archive_sha256=[string]$baseline.candidate.archive_sha256;v5_archive_sha256=[string]$releaseRecord.package.archive_sha256}
    "required-proof-obligations" = [pscustomobject][ordered]@{status=if($obligationsPassed){"passed"}else{"failed"};v4_obligations=@($baseline.obligations).Count;unmapped=@($unmapped);missing_v5_tasks=@($missingTasks | Sort-Object -Unique)}
    "scenario-identities" = [pscustomobject][ordered]@{status=if($scenariosPassed){"passed"}else{"failed"};v4=$baselineScenarios.Count;v5=$v5Scenarios.Count;missing=$missingScenarios;added=$addedScenarioIds}
    "environment-identities" = [pscustomobject][ordered]@{status=if($environmentsPassed){"passed"}else{"failed"};mapped=$environmentMappings.Count;mapping_sha256=Get-MIRCPSha256Object -Value @($environmentMappings);failures=@($environmentFailures);mappings=@($environmentMappings)}
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
    comparison_mode = if ([string]::IsNullOrWhiteSpace($ContextPath)) { "toolchain-admission" } else { "operational-cutover" }
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
  foreach ($target in @("2.1", "2.0")) {
    $cutover = $authority.target_cutovers.PSObject.Properties[$target]
    if ($null -eq $cutover -or [string]$cutover.Value.state -notin @("pending", "accepted") -or
        [string]$cutover.Value.calibration_release -notin @($authority.calibration_candidates | ForEach-Object { [string]$_ })) {
      throw "Shadow authority has no valid target cutover for $target."
    }
  }
  if ([string]$authority.state -eq "accepted" -and [string]$authority.target_cutovers.'2.1'.state -ne "accepted") { throw "Global shadow acceptance requires accepted Factorio 2.1 C24 cutover." }
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
