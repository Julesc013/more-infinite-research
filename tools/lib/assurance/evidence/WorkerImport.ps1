function Write-MIRAssuranceWorkerReceipt {
  param(
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Capsule
  )

  $paths = Get-MIRAssuranceEvidencePaths -TestId ([string]$Test.id) -InputKey ([string]$Test.fingerprint.input_key)
  $capsulePath = Resolve-MIRAssurancePath -Path ([string]$Capsule.attempt_path)
  if (-not (Test-Path -LiteralPath $capsulePath -PathType Leaf)) {
    throw "Cannot write a worker receipt without the immutable evidence capsule for '$([string]$Test.id)'."
  }
  $planMaterialSha256 = [string]$Plan.plan_material_sha256
  if ($planMaterialSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
    throw "Cannot write a worker receipt without an exact plan-material digest for '$([string]$Test.id)'."
  }
  if ($null -eq $Plan.producer) {
    throw "Cannot write a worker receipt without the plan's coordination producer for '$([string]$Test.id)'."
  }
  $receiptProducer = Get-MIRAssuranceProducer
  $receiptProducerSha256 = Get-MIRAssuranceJsonHash -Value $receiptProducer
  $evidenceProducerSha256 = Get-MIRAssuranceJsonHash -Value $Capsule.producer
  $evidenceDisposition = if ($receiptProducerSha256 -eq $evidenceProducerSha256) {
    "produced-by-worker"
  } else {
    "adopted-exact-trusted-capsule"
  }
  $receipt = [ordered]@{
    schema="mir-assurance-worker-receipt-v3"
    plan=[ordered]@{
      material_sha256=$planMaterialSha256
      required_test_set_sha256=[string]$Plan.required_test_set_sha256
      generated_at=(ConvertTo-MIRAssuranceTimestampText -Value $Plan.generated_at)
      source_commit=[string]$Plan.source_commit
      source_tree=[string]$Plan.source_tree
      target=[string]$Plan.target
      profile=[string]$Plan.profile
      producer=$Plan.producer
    }
    work=[ordered]@{
      test_id=[string]$Test.id
      safe_test_id=[string]$Test.safe_test_id
      input_key=[string]$Test.fingerprint.input_key
      fingerprint_sha256=[string]$Test.fingerprint.fingerprint_sha256
      definition_sha256=[string]$Test.fingerprint.definition_sha256
      force_fresh=[bool]$Test.force_fresh
    }
    result=[ordered]@{
      conclusion=[string]$Capsule.conclusion
      result_digest=[string]$Capsule.result_digest
      capsule_path=[string]$Capsule.attempt_path
      capsule_sha256=(Get-MIRAssuranceSha256 -Path $capsulePath)
    }
    producer=$receiptProducer
    evidence_producer=$Capsule.producer
    evidence_disposition=$evidenceDisposition
    completed_at=(ConvertTo-MIRAssuranceTimestampText -Value $Capsule.completed_at)
  }
  $receiptPath = Join-Path $paths.root "worker-receipts\$planMaterialSha256.json"
  Write-MIRAssuranceAtomicJson -Value $receipt -Path $receiptPath
  return $receipt
}

function Read-MIRAssuranceWorkerObject {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Context
  )

  $fingerprint = $Test.fingerprint
  $paths = Get-MIRAssuranceEvidencePaths -TestId ([string]$Test.id) -InputKey ([string]$fingerprint.input_key)
  $planMaterialSha256 = [string]$Plan.plan_material_sha256
  if ($planMaterialSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
    throw "Worker import for '$([string]$Test.id)' has no exact plan-material digest."
  }
  $receiptPath = Join-Path $SourceRoot "worker-receipts\$planMaterialSha256.json"
  if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
    throw "Worker artifact for '$([string]$Test.id)' has no immutable worker receipt."
  }
  try { $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json }
  catch { throw "Worker artifact for '$([string]$Test.id)' has an invalid worker receipt." }
  $expectedSafeId = ([string]$Test.id) -replace '[^A-Za-z0-9._-]', '_'
  $receiptMismatches = [Collections.Generic.List[string]]::new()
  if ([string]$receipt.schema -ne "mir-assurance-worker-receipt-v3") { $receiptMismatches.Add("schema") }
  if ([string]$receipt.plan.material_sha256 -ne [string]$Plan.plan_material_sha256) { $receiptMismatches.Add("plan-material") }
  if ([string]$receipt.plan.required_test_set_sha256 -ne [string]$Plan.required_test_set_sha256) { $receiptMismatches.Add("required-test-set") }
  $receiptGeneratedAt = ConvertTo-MIRAssuranceDateTimeOffset -Value $receipt.plan.generated_at
  $planGeneratedAt = ConvertTo-MIRAssuranceDateTimeOffset -Value $Plan.generated_at
  if ($receiptGeneratedAt.UtcDateTime.Ticks -ne $planGeneratedAt.UtcDateTime.Ticks) { $receiptMismatches.Add("plan-generated-at") }
  if ([string]$receipt.plan.source_commit -ne [string]$Plan.source_commit) { $receiptMismatches.Add("source-commit") }
  if ([string]$receipt.plan.source_tree -ne [string]$Plan.source_tree) { $receiptMismatches.Add("source-tree") }
  if ([string]$receipt.plan.target -ne [string]$Plan.target) { $receiptMismatches.Add("target") }
  if ([string]$receipt.plan.profile -ne [string]$Plan.profile) { $receiptMismatches.Add("profile") }
  if ((Get-MIRAssuranceJsonHash -Value $receipt.plan.producer) -ne (Get-MIRAssuranceJsonHash -Value $Plan.producer)) { $receiptMismatches.Add("plan-producer") }
  if ([string]$receipt.work.test_id -ne [string]$Test.id) { $receiptMismatches.Add("test-id") }
  if ([string]$receipt.work.safe_test_id -ne $expectedSafeId) { $receiptMismatches.Add("safe-test-id") }
  if ([string]$receipt.work.input_key -ne [string]$fingerprint.input_key) { $receiptMismatches.Add("input-key") }
  if ([string]$receipt.work.fingerprint_sha256 -ne [string]$fingerprint.fingerprint_sha256) { $receiptMismatches.Add("fingerprint") }
  if ([string]$receipt.work.definition_sha256 -ne [string]$fingerprint.definition_sha256) { $receiptMismatches.Add("definition") }
  if ([bool]$receipt.work.force_fresh -ne [bool]$Test.force_fresh) { $receiptMismatches.Add("freshness") }
  if ([string]$receipt.result.conclusion -notin @("passed", "failed")) { $receiptMismatches.Add("conclusion") }
  if ([string]$receipt.result.result_digest -notmatch '^[A-Fa-f0-9]{64}$') { $receiptMismatches.Add("result-digest") }
  if ([string]::IsNullOrWhiteSpace([string]$receipt.result.capsule_path)) { $receiptMismatches.Add("capsule-path") }
  if ([string]$receipt.result.capsule_sha256 -notmatch '^[A-Fa-f0-9]{64}$') { $receiptMismatches.Add("capsule-digest") }
  if (-not (Test-MIRAssuranceTrustedProducer -Producer $receipt.producer -Context $Context)) { $receiptMismatches.Add("receipt-trust-context") }
  if (-not (Test-MIRAssuranceTrustedProducer -Producer $receipt.evidence_producer -Context $Context)) { $receiptMismatches.Add("evidence-trust-context") }
  $receiptProducerSha256 = Get-MIRAssuranceJsonHash -Value $receipt.producer
  $evidenceProducerSha256 = Get-MIRAssuranceJsonHash -Value $receipt.evidence_producer
  $expectedEvidenceDisposition = if ($receiptProducerSha256 -eq $evidenceProducerSha256) {
    "produced-by-worker"
  } else {
    "adopted-exact-trusted-capsule"
  }
  if ([string]$receipt.evidence_disposition -ne $expectedEvidenceDisposition) { $receiptMismatches.Add("evidence-disposition") }
  foreach ($field in @("repository", "workflow", "run_id", "run_attempt", "job", "commit", "ref", "event", "trust_class")) {
    if ([string]::IsNullOrWhiteSpace([string]$receipt.producer.$field)) { $receiptMismatches.Add("receipt-producer-$field") }
  }
  if (-not (Test-MIRAssurancePlanContinuationProducer -Producer $receipt.plan.producer -Context $Context -SourceCommit ([string]$Plan.source_commit))) {
    $receiptMismatches.Add("plan-continuation-authority")
  }
  if ($receiptMismatches.Count -gt 0) {
    throw "Worker artifact for '$([string]$Test.id)' receipt does not match the active plan, work row, or trust context: $($receiptMismatches -join ', ')."
  }
  $capsulePath = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $SourceRoot -DestinationRoot $paths.root -RepoRelativePath ([string]$receipt.result.capsule_path)
  if (-not (Test-Path -LiteralPath $capsulePath -PathType Leaf) -or
      (Get-MIRAssuranceSha256 -Path $capsulePath) -ne [string]$receipt.result.capsule_sha256) {
    throw "Worker artifact for '$([string]$Test.id)' has a missing or digest-mismatched capsule."
  }
  try { $capsule = Get-Content -Raw -LiteralPath $capsulePath | ConvertFrom-Json }
  catch { throw "Worker artifact for '$([string]$Test.id)' has an invalid evidence capsule." }
  $outcome = [string]$receipt.result.conclusion
  if ([string]$capsule.attempt_path -ne [string]$receipt.result.capsule_path -or
      [int]$capsule.schema -ne $evidenceSchema -or
      [string]$capsule.test_id -ne [string]$Test.id -or
      [string]$capsule.input_key -ne [string]$fingerprint.input_key -or
      [string]$capsule.fingerprint_sha256 -ne [string]$fingerprint.fingerprint_sha256 -or
      [string]$capsule.definition_sha256 -ne [string]$fingerprint.definition_sha256 -or
      [string]$capsule.target -ne [string]$fingerprint.target -or
      [string]$capsule.status -ne $outcome -or
      [string]$capsule.conclusion -ne $outcome -or
      ($outcome -eq "passed" -and [int]$capsule.exit_code -ne 0) -or
      ($outcome -eq "failed" -and [int]$capsule.exit_code -eq 0)) {
    throw "Worker artifact for '$([string]$Test.id)' does not match its planned test, target, or fingerprint."
  }
  if ([string]$receipt.result.result_digest -ne [string]$capsule.result_digest -or
      (Get-MIRAssuranceJsonHash -Value $receipt.evidence_producer) -ne (Get-MIRAssuranceJsonHash -Value $capsule.producer) -or
      (ConvertTo-MIRAssuranceDateTimeOffset -Value $receipt.completed_at).UtcDateTime.Ticks -ne
        (ConvertTo-MIRAssuranceDateTimeOffset -Value $capsule.completed_at).UtcDateTime.Ticks) {
    throw "Worker artifact for '$([string]$Test.id)' receipt differs from its selected immutable capsule."
  }
  if (-not (Test-MIRAssuranceTrustedProducer -Producer $capsule.producer -Context $Context)) {
    throw "Worker artifact for '$([string]$Test.id)' was produced outside the active trust context."
  }
  if ([bool]$Test.force_fresh) {
    if (-not (Test-MIRAssuranceFreshCampaignEvidence -Capsule $capsule -Test $Test -Plan $Plan)) {
      throw "Worker artifact for '$([string]$Test.id)' does not satisfy the plan-owned freshness binding."
    }
  }

  $resultPath = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $SourceRoot -DestinationRoot $paths.root -RepoRelativePath ([string]$capsule.result.path)
  if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "Worker artifact for '$([string]$Test.id)' is missing its structured result."
  }
  $resultItem = Get-Item -LiteralPath $resultPath
  if ($resultItem.Length -ne [long]$capsule.result.bytes -or
      (Get-MIRAssuranceSha256 -Path $resultPath) -ne [string]$capsule.result.sha256) {
    throw "Worker artifact for '$([string]$Test.id)' has a digest-mismatched structured result."
  }
  try { $structuredResult = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json }
  catch { throw "Worker artifact for '$([string]$Test.id)' has invalid structured-result JSON." }
  if ([string]$structuredResult.schema -ne "mir-test-result-v1" -or
      [string]$structuredResult.test_id -ne [string]$Test.id -or
      [string]$structuredResult.status -ne $outcome -or
      [int]$structuredResult.exit_code -ne [int]$capsule.exit_code -or
      (Get-MIRAssuranceJsonHash -Value @($structuredResult.assertions)) -ne (Get-MIRAssuranceJsonHash -Value @($capsule.assertions)) -or
      (Get-MIRAssuranceJsonHash -Value @($structuredResult.artifacts)) -ne (Get-MIRAssuranceJsonHash -Value @($capsule.artifacts))) {
    throw "Worker artifact for '$([string]$Test.id)' has structured content that differs from its capsule."
  }

  $objectFiles = [Collections.Generic.List[string]]::new()
  $objectFiles.Add([string]$receipt.result.capsule_path)
  $objectFiles.Add([string]$capsule.result.path)
  foreach ($artifact in @($capsule.artifacts)) {
    $artifactPath = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $SourceRoot -DestinationRoot $paths.root -RepoRelativePath ([string]$artifact.path)
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
      throw "Worker artifact for '$([string]$Test.id)' is missing a declared evidence artifact."
    }
    $artifactItem = Get-Item -LiteralPath $artifactPath
    if ($artifactItem.Length -ne [long]$artifact.bytes -or
        (Get-MIRAssuranceSha256 -Path $artifactPath) -ne [string]$artifact.sha256) {
      throw "Worker artifact for '$([string]$Test.id)' has a digest-mismatched declared artifact."
    }
    $objectFiles.Add([string]$artifact.path)
  }

  $normalizedResultPath = ([string]$capsule.result.path).Replace("\", "/")
  $resultDirectory = $normalizedResultPath.Substring(0, $normalizedResultPath.LastIndexOf("/"))
  $stdoutRelative = "$resultDirectory/stdout.txt"
  $stderrRelative = "$resultDirectory/stderr.txt"
  $stdoutPath = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $SourceRoot -DestinationRoot $paths.root -RepoRelativePath $stdoutRelative
  $stderrPath = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $SourceRoot -DestinationRoot $paths.root -RepoRelativePath $stderrRelative
  if (-not (Test-Path -LiteralPath $stdoutPath -PathType Leaf) -or
      -not (Test-Path -LiteralPath $stderrPath -PathType Leaf) -or
      (Get-MIRAssuranceSha256 -Path $stdoutPath) -ne [string]$capsule.stdout_sha256 -or
      (Get-MIRAssuranceSha256 -Path $stderrPath) -ne [string]$capsule.stderr_sha256 -or
      (Get-MIRAssuranceTextHash -Text ((Get-Content -Raw -LiteralPath $stdoutPath) + "`n" + (Get-Content -Raw -LiteralPath $stderrPath))) -ne [string]$capsule.log_digest) {
    throw "Worker artifact for '$([string]$Test.id)' has missing or digest-mismatched executor logs."
  }
  $objectFiles.Add($stdoutRelative)
  $objectFiles.Add($stderrRelative)
  if ((Get-MIRAssuranceCapsuleDigest -Capsule $capsule) -ne [string]$capsule.result_digest) {
    throw "Worker artifact for '$([string]$Test.id)' has a digest-mismatched evidence capsule."
  }
  $verifiedKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($relativePath in @($objectFiles)) {
    $canonical = Get-MIRAssuranceWorkerCanonicalPath -Path $relativePath
    [void]$verifiedKeys.Add([string]$canonical.key)
  }
  foreach ($assertion in @($capsule.assertions)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$assertion.evidence)) {
      $canonicalEvidence = Get-MIRAssuranceWorkerCanonicalPath -Path ([string]$assertion.evidence)
      if (-not $verifiedKeys.Contains([string]$canonicalEvidence.key)) {
        throw "Worker artifact for '$([string]$Test.id)' has assertion evidence that is not digest-bound by its result, logs, or declared artifacts."
      }
    }
  }
  $receiptDestination = Join-Path $paths.root "worker-receipts\$planMaterialSha256.json"
  $receiptRelative = Get-MIRAssuranceRepoRelativePath -Path $receiptDestination
  $objectFiles.Add($receiptRelative)
  $canonicalFiles = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
  foreach ($relativePath in @($objectFiles)) {
    $canonical = Get-MIRAssuranceWorkerCanonicalPath -Path $relativePath
    if ($canonicalFiles.ContainsKey([string]$canonical.key)) {
      throw "Worker artifact for '$([string]$Test.id)' contains duplicate canonical object paths."
    }
    $canonicalFiles[[string]$canonical.key] = [string]$canonical.path
    $null = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $SourceRoot -DestinationRoot $paths.root -RepoRelativePath $relativePath
  }
  $pointer = [ordered]@{
    schema=1
    test_id=[string]$Test.id
    input_key=[string]$fingerprint.input_key
    conclusion=$outcome
    capsule_path=[string]$receipt.result.capsule_path
    capsule_sha256=[string]$receipt.result.capsule_sha256
  }
  $suppliedPointerName = if ($outcome -eq "passed") { "passed.json" } else { "blocked.json" }
  $suppliedPointerPath = Join-Path $SourceRoot $suppliedPointerName
  $suppliedPointerStatus = "missing"
  if (Test-Path -LiteralPath $suppliedPointerPath -PathType Leaf) {
    try {
      $suppliedPointer = Get-Content -Raw -LiteralPath $suppliedPointerPath | ConvertFrom-Json
      $suppliedPointerStatus = if ((Get-MIRAssuranceJsonHash -Value $suppliedPointer) -eq (Get-MIRAssuranceJsonHash -Value $pointer)) { "validated" } else { "stale-ignored" }
    } catch {
      $suppliedPointerStatus = "invalid-ignored"
    }
  }
  return [ordered]@{
    receipt=$receipt
    receipt_sha256=(Get-MIRAssuranceSha256 -Path $receiptPath)
    pointer=$pointer
    pointer_status=$suppliedPointerStatus
    outcome=$outcome
    capsule=$capsule
    destination_paths=$paths
    files=@($canonicalFiles.Values | Sort-Object)
  }
}

function Import-MIRAssuranceWorkerEvidence {
  param(
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][string]$WorkerRoot,
    [Parameter(Mandatory)][string]$ArtifactPrefix
  )

  if ($ArtifactPrefix -notmatch '^[A-Za-z0-9._-]+$') {
    throw "Worker artifact prefix contains unsafe characters: $ArtifactPrefix"
  }
  $resolvedWorkerRoot = Resolve-MIRAssurancePath -Path $WorkerRoot
  $repoBoundary = [IO.Path]::GetFullPath($repo).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
  if (-not ([IO.Path]::GetFullPath($resolvedWorkerRoot).StartsWith($repoBoundary, [StringComparison]::OrdinalIgnoreCase))) {
    throw "Worker evidence root must stay inside the repository workspace: $resolvedWorkerRoot"
  }
  $work = @($Plan.work | Sort-Object test_id)
  if ($work.Count -eq 0) {
    return [ordered]@{schema=2;status="passed";worker_root=(Get-MIRAssuranceRepoRelativePath -Path $resolvedWorkerRoot);imported=@();failed=@();missing=@();rejected=@();duplicates=@();ignored=@()}
  }
  if (-not (Test-Path -LiteralPath $resolvedWorkerRoot -PathType Container)) {
    return [ordered]@{
      schema=2
      status="failed"
      worker_root=(Get-MIRAssuranceRepoRelativePath -Path $resolvedWorkerRoot)
      imported=@()
      failed=@()
      missing=@($work | ForEach-Object { [string]$_.test_id })
      rejected=@()
      duplicates=@()
      ignored=@()
    }
  }

  $limits = $Context.config.worker_import
  if ([int]$limits.max_artifacts -le 0) { throw "Worker-import limit 'max_artifacts' must be positive." }
  $artifactDirectories = @(Get-ChildItem -LiteralPath $resolvedWorkerRoot -Directory -Force | Sort-Object Name)
  if ($artifactDirectories.Count -gt [int]$limits.max_artifacts) {
    throw "Worker evidence root exceeds the artifact-count limit."
  }
  $artifactNameKeys = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
  foreach ($directory in $artifactDirectories) {
    if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Worker evidence root contains a symlink or reparse-point artifact: $($directory.Name)"
    }
    $canonicalName = Get-MIRAssuranceWorkerCanonicalPath -Path $directory.Name
    if ($artifactNameKeys.ContainsKey([string]$canonicalName.key)) {
      throw "Worker evidence root contains a case-fold or Unicode-normalization artifact collision."
    }
    $artifactNameKeys[[string]$canonicalName.key] = [string]$directory.Name
  }
  $safeIdGroups = @($work | Group-Object safe_test_id | Where-Object Count -gt 1)
  if ($safeIdGroups.Count -gt 0) {
    throw "Verification plan contains ambiguous worker safe IDs: $($safeIdGroups.Name -join ', ')"
  }

  $expectedRows = @{}
  $candidates = @{}
  $preRejected = @{}
  foreach ($row in $work) {
    $expectedRows[[string]$row.test_id] = $row
    $candidates[[string]$row.test_id] = [Collections.Generic.List[object]]::new()
    $preRejected[[string]$row.test_id] = [Collections.Generic.List[string]]::new()
  }
  $ignored = [Collections.Generic.List[object]]::new()
  foreach ($directory in $artifactDirectories) {
    if (-not $directory.Name.StartsWith($ArtifactPrefix, [StringComparison]::Ordinal)) {
      $ignored.Add([ordered]@{artifact=$directory.Name;reason="prefix-mismatch"})
      continue
    }
    $receiptPath = Join-Path $directory.FullName "worker-receipts\$([string]$Plan.plan_material_sha256).json"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
      $matchedExpected = @($work | Where-Object { $directory.Name -eq "$ArtifactPrefix$([string]$_.safe_test_id)" })
      if ($matchedExpected.Count -eq 1) {
        $preRejected[[string]$matchedExpected[0].test_id].Add("$($directory.Name): missing current-plan receipt")
      } else {
        $ignored.Add([ordered]@{artifact=$directory.Name;reason="irrelevant-or-stale-receipt"})
      }
      continue
    }
    try { $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json }
    catch {
      $matchedExpected = @($work | Where-Object { $directory.Name -eq "$ArtifactPrefix$([string]$_.safe_test_id)" })
      if ($matchedExpected.Count -eq 1) { $preRejected[[string]$matchedExpected[0].test_id].Add("$($directory.Name): invalid receipt JSON") }
      else { $ignored.Add([ordered]@{artifact=$directory.Name;reason="invalid irrelevant receipt"}) }
      continue
    }
    $receiptTestId = [string]$receipt.work.test_id
    if ([string]$receipt.schema -ne "mir-assurance-worker-receipt-v3" -or
        [string]$receipt.plan.material_sha256 -ne [string]$Plan.plan_material_sha256 -or
        -not $expectedRows.ContainsKey($receiptTestId)) {
      $matchedExpected = @($work | Where-Object { $directory.Name -eq "$ArtifactPrefix$([string]$_.safe_test_id)" })
      if ($matchedExpected.Count -eq 1) { $preRejected[[string]$matchedExpected[0].test_id].Add("$($directory.Name): receipt does not bind the active plan row") }
      else { $ignored.Add([ordered]@{artifact=$directory.Name;reason="irrelevant-plan-or-row"}) }
      continue
    }
    $candidates[$receiptTestId].Add($directory)
  }

  $imported = @()
  $failed = @()
  $missing = [Collections.Generic.List[string]]::new()
  $rejected = [Collections.Generic.List[object]]::new()
  $duplicates = [Collections.Generic.List[object]]::new()
  foreach ($row in $work) {
    $tests = @($Plan.tests | Where-Object { [string]$_.id -eq [string]$row.test_id })
    if ($tests.Count -ne 1) { throw "Worker row '$([string]$row.test_id)' does not select exactly one planned test." }
    $test = $tests[0]
    $expectedSafeId = ([string]$test.id) -replace '[^A-Za-z0-9._-]', '_'
    if ([string]$row.safe_test_id -ne $expectedSafeId -or
        [string]$test.safe_test_id -ne $expectedSafeId -or
        [string]$row.fingerprint -ne [string]$test.fingerprint.fingerprint_sha256 -or
        [string]$test.fingerprint.input_key -ne [string]$row.fingerprint) {
      throw "Worker row '$([string]$row.test_id)' does not match its planned safe ID and fingerprint."
    }

    $rowCandidates = @($candidates[[string]$test.id])
    if ($rowCandidates.Count -eq 0) {
      if ($preRejected[[string]$test.id].Count -gt 0) {
        $rejected.Add([ordered]@{test_id=[string]$test.id;reasons=@($preRejected[[string]$test.id])})
      } else {
        $missing.Add([string]$test.id)
      }
      continue
    }
    if ($rowCandidates.Count -gt 1) {
      $duplicates.Add([ordered]@{test_id=[string]$test.id;artifacts=@($rowCandidates.Name | Sort-Object)})
      continue
    }
    $resolvedArtifactRoot = [IO.Path]::GetFullPath([string]$rowCandidates[0].FullName)
    $workerBoundary = [IO.Path]::GetFullPath($resolvedWorkerRoot).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedArtifactRoot.StartsWith($workerBoundary, [StringComparison]::OrdinalIgnoreCase)) {
      $rejected.Add([ordered]@{test_id=[string]$test.id;reasons=@("artifact path escaped worker root")})
      continue
    }
    try {
      $tree = Assert-MIRAssuranceWorkerArtifactTree -ArtifactRoot $resolvedArtifactRoot -Context $Context
      $workerObject = Read-MIRAssuranceWorkerObject -SourceRoot $resolvedArtifactRoot -Plan $Plan -Test $test -Context $Context
    } catch {
      $rejected.Add([ordered]@{test_id=[string]$test.id;reasons=@($_.Exception.Message)})
      continue
    }

    try {
      foreach ($relativePath in @($workerObject.files)) {
        $source = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $resolvedArtifactRoot -DestinationRoot $workerObject.destination_paths.root -RepoRelativePath $relativePath
        $destination = Resolve-MIRAssurancePath -Path $relativePath
        $resolvedDestination = [IO.Path]::GetFullPath($destination)
        $destinationBoundary = [IO.Path]::GetFullPath($workerObject.destination_paths.root).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
        if (-not $resolvedDestination.StartsWith($destinationBoundary, [StringComparison]::OrdinalIgnoreCase)) {
          throw "Refusing to import worker evidence outside its planned fingerprint subtree: $relativePath"
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedDestination) | Out-Null
        if (Test-Path -LiteralPath $resolvedDestination -PathType Leaf) {
          if ((Get-MIRAssuranceSha256 -Path $source) -ne (Get-MIRAssuranceSha256 -Path $resolvedDestination)) {
            throw "Refusing to overwrite a different immutable worker object: $relativePath"
          }
        } else {
          Copy-Item -LiteralPath $source -Destination $resolvedDestination
        }
      }
      if (Test-Path -LiteralPath $workerObject.destination_paths.running -PathType Leaf) {
        Remove-Item -LiteralPath $workerObject.destination_paths.running -Force
      }
      if ([string]$workerObject.outcome -eq "passed") {
        if (Test-Path -LiteralPath $workerObject.destination_paths.blocked -PathType Leaf) {
          Remove-Item -LiteralPath $workerObject.destination_paths.blocked -Force
        }
        Write-MIRAssuranceAtomicJson -Value $workerObject.pointer -Path $workerObject.destination_paths.passed
        $validation = Test-MIRAssuranceCapsule -Capsule $workerObject.capsule -Fingerprint $test.fingerprint -Context $Context
        if (-not [bool]$validation.valid) {
          Remove-Item -LiteralPath $workerObject.destination_paths.passed -Force
          throw "Imported worker evidence failed canonical validation: $([string]$validation.reason)"
        }
      } else {
        Write-MIRAssuranceAtomicJson -Value $workerObject.pointer -Path $workerObject.destination_paths.blocked
      }
    } catch {
      $rejected.Add([ordered]@{test_id=[string]$test.id;reasons=@($_.Exception.Message)})
      continue
    }
    $record = [ordered]@{
      test_id=[string]$test.id
      input_key=[string]$test.fingerprint.input_key
      outcome=[string]$workerObject.outcome
      result_digest=[string]$workerObject.capsule.result_digest
      capsule_sha256=[string]$workerObject.pointer.capsule_sha256
      receipt_sha256=[string]$workerObject.receipt_sha256
      pointer_status=[string]$workerObject.pointer_status
      artifact=[string]$rowCandidates[0].Name
      entries=[int]$tree.entries
      expanded_bytes=[long]$tree.expanded_bytes
    }
    if ([string]$workerObject.outcome -eq "passed") { $imported += $record }
    else { $failed += $record }
  }
  $passed = $failed.Count -eq 0 -and $missing.Count -eq 0 -and $rejected.Count -eq 0 -and $duplicates.Count -eq 0
  return [ordered]@{
    schema=2
    status=if ($passed) { "passed" } else { "failed" }
    worker_root=(Get-MIRAssuranceRepoRelativePath -Path $resolvedWorkerRoot)
    imported=@($imported | Sort-Object test_id)
    failed=@($failed | Sort-Object test_id)
    missing=@($missing | Sort-Object)
    rejected=@($rejected | Sort-Object test_id)
    duplicates=@($duplicates | Sort-Object test_id)
    ignored=@($ignored | Sort-Object artifact)
  }
}
