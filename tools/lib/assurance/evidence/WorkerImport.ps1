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
  # A worker transport receipt describes one concrete worker execution.  It
  # cannot occupy a plan-only pathname: a GitHub partial rerun legitimately
  # creates a new receipt for the same planned row.  Keep every receipt by its
  # canonical material identity and make the mutable selector an untrusted
  # locator only; import still validates the selected immutable receipt.
  $receiptDirectory = Join-Path $paths.root "worker-receipts\$planMaterialSha256"
  New-Item -ItemType Directory -Force -Path $receiptDirectory | Out-Null
  $stagingReceiptPath = Join-Path $receiptDirectory (".$([guid]::NewGuid().ToString('N')).json")
  Write-MIRAssuranceAtomicJson -Value $receipt -Path $stagingReceiptPath
  $receiptMaterialSha256 = Get-MIRAssuranceSha256 -Path $stagingReceiptPath
  $receiptPath = Join-Path $receiptDirectory "$receiptMaterialSha256.json"
  try {
    if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
      if ((Get-MIRAssuranceSha256 -Path $receiptPath) -ne $receiptMaterialSha256) {
        throw "Refusing to replace a different content-addressed worker receipt."
      }
      Remove-Item -LiteralPath $stagingReceiptPath -Force
    } else {
      Move-Item -LiteralPath $stagingReceiptPath -Destination $receiptPath
    }
  } finally {
    if (Test-Path -LiteralPath $stagingReceiptPath -PathType Leaf) {
      Remove-Item -LiteralPath $stagingReceiptPath -Force
    }
  }
  Write-MIRAssuranceAtomicJson -Value ([ordered]@{
    schema=1
    receipt_material_sha256=$receiptMaterialSha256
  }) -Path (Join-Path $receiptDirectory "current.json")
  return $receipt
}

function Get-MIRAssuranceWorkerReceiptPath {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$PlanMaterialSha256,
    $ExpectedPlan = $null,
    [string]$ExpectedProducerRunId = "",
    [string]$ExpectedProducerRunAttempt = ""
  )

  $receiptDirectory = Join-Path $SourceRoot "worker-receipts\$PlanMaterialSha256"
  $legacyReceiptPath = Join-Path $SourceRoot "worker-receipts\$PlanMaterialSha256.json"
  $expectsTransport = -not [string]::IsNullOrWhiteSpace($ExpectedProducerRunId) -or
    -not [string]::IsNullOrWhiteSpace($ExpectedProducerRunAttempt)

  if (Test-Path -LiteralPath $receiptDirectory -PathType Container) {
    $directoryItem = Get-Item -LiteralPath $receiptDirectory -Force
    if (($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Worker artifact has a reparse-point receipt directory."
    }
    if ($expectsTransport) {
      $receiptMatches = [Collections.Generic.List[string]]::new()
      foreach ($item in @(Get-ChildItem -LiteralPath $receiptDirectory -File -Force | Sort-Object Name)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
          throw "Worker artifact has a reparse-point receipt object."
        }
        if ($item.Name -eq "current.json") { continue }
        if ($item.Name -notmatch '^[A-Fa-f0-9]{64}[.]json$') {
          throw "Worker artifact has a non-content-addressed receipt object: $($item.Name)"
        }
        try { $candidate = Get-Content -Raw -LiteralPath $item.FullName | ConvertFrom-Json }
        catch { throw "Worker artifact has invalid JSON in a content-addressed receipt object: $($item.Name)" }
        if ((Get-MIRAssuranceSha256 -Path $item.FullName) -ne $item.BaseName.ToUpperInvariant()) {
          throw "Worker artifact has a digest-mismatched content-addressed receipt object: $($item.Name)"
        }
        $matchesExpectedPlan = $true
        if ($null -ne $ExpectedPlan) {
          try {
            $matchesExpectedPlan =
              [string]$candidate.schema -eq 'mir-assurance-worker-receipt-v3' -and
              [string]$candidate.plan.material_sha256 -eq [string]$ExpectedPlan.plan_material_sha256 -and
              [string]$candidate.plan.required_test_set_sha256 -eq [string]$ExpectedPlan.required_test_set_sha256 -and
              (ConvertTo-MIRAssuranceDateTimeOffset -Value $candidate.plan.generated_at).UtcDateTime.Ticks -eq
                (ConvertTo-MIRAssuranceDateTimeOffset -Value $ExpectedPlan.generated_at).UtcDateTime.Ticks -and
              [string]$candidate.plan.source_commit -eq [string]$ExpectedPlan.source_commit -and
              [string]$candidate.plan.source_tree -eq [string]$ExpectedPlan.source_tree -and
              [string]$candidate.plan.target -eq [string]$ExpectedPlan.target -and
              [string]$candidate.plan.profile -eq [string]$ExpectedPlan.profile -and
              (Get-MIRAssuranceJsonHash -Value $candidate.plan.producer) -eq (Get-MIRAssuranceJsonHash -Value $ExpectedPlan.producer)
          } catch { $matchesExpectedPlan = $false }
        }
        if ($matchesExpectedPlan -and
            [string]$candidate.producer.run_id -eq $ExpectedProducerRunId -and
            [string]$candidate.producer.run_attempt -eq $ExpectedProducerRunAttempt) {
          $matchPath = [string]$item.FullName
          [void]$receiptMatches.Add($matchPath)
        }
      }
      if ($receiptMatches.Count -ne 1) {
        $availableTransports = @(
          foreach ($item in @(Get-ChildItem -LiteralPath $receiptDirectory -File -Force | Where-Object { $_.Name -match '^[A-Fa-f0-9]{64}[.]json$' })) {
            try {
              $available = Get-Content -Raw -LiteralPath $item.FullName | ConvertFrom-Json
              "$([string]$available.producer.run_id)/$([string]$available.producer.run_attempt)"
            } catch { '<invalid>' }
          }
        )
        throw "Worker artifact does not publish exactly one immutable receipt for the selected transport run and attempt (expected $ExpectedProducerRunId/$ExpectedProducerRunAttempt; found $($availableTransports -join ', '))."
      }
      return [string]$receiptMatches[0]
    }

    $currentPath = Join-Path $receiptDirectory "current.json"
    if (-not (Test-Path -LiteralPath $currentPath -PathType Leaf)) {
      throw "Worker artifact has no current receipt selector."
    }
    try { $current = Get-Content -Raw -LiteralPath $currentPath | ConvertFrom-Json }
    catch { throw "Worker artifact has an invalid current receipt selector." }
    $receiptMaterialSha256 = [string]$current.receipt_material_sha256
    if ([int]$current.schema -ne 1 -or $receiptMaterialSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
      throw "Worker artifact has an invalid current receipt selector."
    }
    $receiptPath = Join-Path $receiptDirectory "$receiptMaterialSha256.json"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
      throw "Worker artifact current receipt selector does not resolve to an immutable receipt."
    }
    return $receiptPath
  }

  # V3 flat receipts are accepted only for historical artifact ingestion. New
  # writes always use the content-addressed directory above, so a retry cannot
  # overwrite a different transport receipt in the local evidence cache.
  if ($expectsTransport) {
    throw "Worker artifact has no content-addressed receipt for the selected transport run and attempt."
  }
  if (Test-Path -LiteralPath $legacyReceiptPath -PathType Leaf) { return $legacyReceiptPath }
  throw "Worker artifact has no immutable worker receipt."
}

function Get-MIRAssuranceWorkerTransportReceiptPath {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$ExpectedProducerRunId,
    [Parameter(Mandatory)][string]$ExpectedProducerRunAttempt
  )

  if ([string]::IsNullOrWhiteSpace($ExpectedProducerRunId) -or
      [string]::IsNullOrWhiteSpace($ExpectedProducerRunAttempt)) {
    throw "Retry-aware worker import requires an exact worker transport run and attempt."
  }
  $receiptRoot = Join-Path $SourceRoot "worker-receipts"
  if (-not (Test-Path -LiteralPath $receiptRoot -PathType Container)) {
    throw "Worker artifact has no content-addressed receipt root for the selected transport run and attempt."
  }
  $rootItem = Get-Item -LiteralPath $receiptRoot -Force
  if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Worker artifact has a reparse-point receipt root."
  }

  # A retry has no safe legacy selector: it must account for the immutable
  # receipt emitted by this exact worker transport, even when that receipt
  # belongs to an earlier full-rerun plan. Enumerate all plan-material
  # directories only after the caller's bounded tree admission, and reject
  # rather than guess when transport identity is ambiguous.
  $receiptMatches = [Collections.Generic.List[object]]::new()
  $availableTransports = [Collections.Generic.List[string]]::new()
  foreach ($planDirectory in @(Get-ChildItem -LiteralPath $receiptRoot -Force | Sort-Object Name)) {
    if (($planDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Worker artifact has a reparse-point receipt-root entry."
    }
    if (-not $planDirectory.PSIsContainer -or $planDirectory.Name -notmatch '^[A-Fa-f0-9]{64}$') {
      throw "Retry-aware worker import requires only content-addressed receipt plan directories."
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $planDirectory.FullName -Force | Sort-Object Name)) {
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Worker artifact has a reparse-point receipt object."
      }
      if ($item.PSIsContainer) {
        throw "Worker artifact has a nested directory in a content-addressed receipt plan directory."
      }
      if ($item.Name -eq "current.json") { continue }
      if ($item.Name -notmatch '^[A-Fa-f0-9]{64}[.]json$') {
        throw "Worker artifact has a non-content-addressed receipt object: $($item.Name)"
      }
      try { $candidate = Get-Content -Raw -LiteralPath $item.FullName | ConvertFrom-Json }
      catch { throw "Worker artifact has invalid JSON in a content-addressed receipt object: $($item.Name)" }
      if ((Get-MIRAssuranceSha256 -Path $item.FullName) -ne $item.BaseName.ToUpperInvariant()) {
        throw "Worker artifact has a digest-mismatched content-addressed receipt object: $($item.Name)"
      }
      if ([string]$candidate.plan.material_sha256 -ne [string]$planDirectory.Name) {
        throw "Worker artifact receipt plan material does not match its content-addressed receipt directory: $($item.Name)"
      }
      $availableTransports.Add("$([string]$candidate.producer.run_id)/$([string]$candidate.producer.run_attempt)")
      if ([string]$candidate.producer.run_id -eq $ExpectedProducerRunId -and
          [string]$candidate.producer.run_attempt -eq $ExpectedProducerRunAttempt) {
        $receiptMatches.Add([pscustomobject][ordered]@{
          path=[string]$item.FullName
          plan_material_sha256=[string]$planDirectory.Name
        })
      }
    }
  }
  if ($receiptMatches.Count -ne 1) {
    throw "Worker artifact does not publish exactly one immutable receipt for the selected transport run and attempt (expected $ExpectedProducerRunId/$ExpectedProducerRunAttempt; found $($availableTransports -join ', '))."
  }
  return $receiptMatches[0]
}

function Test-MIRAssuranceStalePlanTransportReceipt {
  param(
    [Parameter(Mandatory)]$Receipt,
    [Parameter(Mandatory)]$CurrentPlan,
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][string]$ExpectedProducerRunId,
    [Parameter(Mandatory)][string]$ExpectedProducerRunAttempt
  )

  # A receipt from a previous full rerun cannot establish current-plan proof,
  # but it is still transport input. Admit it as explicitly stale only when
  # its immutable receipt binds a trusted earlier plan and this exact planned
  # row. This deliberately does not publish its capsule or mutate pointers.
  $mismatches = [Collections.Generic.List[string]]::new()
  $expectedSafeId = ([string]$Test.id) -replace '[^A-Za-z0-9._-]', '_'
  $stalePlanMaterial = [string]$Receipt.plan.material_sha256
  if ([string]$Receipt.schema -ne 'mir-assurance-worker-receipt-v3') { $mismatches.Add('schema') }
  if ($stalePlanMaterial -notmatch '^[A-Fa-f0-9]{64}$') { $mismatches.Add('plan-material') }
  elseif ($stalePlanMaterial -eq [string]$CurrentPlan.plan_material_sha256) { $mismatches.Add('not-stale-plan-material') }
  if ([string]$Receipt.plan.required_test_set_sha256 -notmatch '^[A-Fa-f0-9]{64}$') { $mismatches.Add('required-test-set') }
  try { $null = ConvertTo-MIRAssuranceDateTimeOffset -Value $Receipt.plan.generated_at }
  catch { $mismatches.Add('plan-generated-at') }
  foreach ($field in @('source_commit', 'source_tree', 'target', 'profile')) {
    if ([string]::IsNullOrWhiteSpace([string]$Receipt.plan.$field)) { $mismatches.Add("plan-$field") }
  }
  if (-not (Test-MIRAssurancePlanContinuationProducer `
        -Producer $Receipt.plan.producer -Context $Context -SourceCommit ([string]$Receipt.plan.source_commit))) {
    $mismatches.Add('plan-continuation-authority')
  }
  if ([string]$Receipt.work.test_id -ne [string]$Test.id) { $mismatches.Add('test-id') }
  if ([string]$Receipt.work.safe_test_id -ne $expectedSafeId) { $mismatches.Add('safe-test-id') }
  if ([string]$Receipt.work.input_key -ne [string]$Test.fingerprint.input_key) { $mismatches.Add('input-key') }
  if ([string]$Receipt.work.fingerprint_sha256 -ne [string]$Test.fingerprint.fingerprint_sha256) { $mismatches.Add('fingerprint') }
  if ([string]$Receipt.work.definition_sha256 -ne [string]$Test.fingerprint.definition_sha256) { $mismatches.Add('definition') }
  if ([bool]$Receipt.work.force_fresh -ne [bool]$Test.force_fresh) { $mismatches.Add('freshness') }
  if ([string]$Receipt.result.conclusion -notin @('passed', 'failed')) { $mismatches.Add('conclusion') }
  if ([string]$Receipt.result.result_digest -notmatch '^[A-Fa-f0-9]{64}$') { $mismatches.Add('result-digest') }
  if ([string]::IsNullOrWhiteSpace([string]$Receipt.result.capsule_path)) { $mismatches.Add('capsule-path') }
  if ([string]$Receipt.result.capsule_sha256 -notmatch '^[A-Fa-f0-9]{64}$') { $mismatches.Add('capsule-digest') }
  if (-not (Test-MIRAssuranceTrustedProducer -Producer $Receipt.producer -Context $Context)) { $mismatches.Add('receipt-trust-context') }
  if (-not (Test-MIRAssuranceTrustedProducer -Producer $Receipt.evidence_producer -Context $Context)) { $mismatches.Add('evidence-trust-context') }
  if ([string]$Receipt.producer.run_id -ne $ExpectedProducerRunId) { $mismatches.Add('receipt-producer-run-id') }
  if ([string]$Receipt.producer.run_attempt -ne $ExpectedProducerRunAttempt) { $mismatches.Add('receipt-producer-run-attempt') }
  foreach ($field in @('repository', 'workflow', 'run_id', 'run_attempt', 'job', 'commit', 'ref', 'event', 'trust_class')) {
    if ([string]::IsNullOrWhiteSpace([string]$Receipt.producer.$field)) { $mismatches.Add("receipt-producer-$field") }
  }
  $receiptProducerSha256 = Get-MIRAssuranceJsonHash -Value $Receipt.producer
  $evidenceProducerSha256 = Get-MIRAssuranceJsonHash -Value $Receipt.evidence_producer
  $expectedEvidenceDisposition = if ($receiptProducerSha256 -eq $evidenceProducerSha256) {
    'produced-by-worker'
  } else {
    'adopted-exact-trusted-capsule'
  }
  if ([string]$Receipt.evidence_disposition -ne $expectedEvidenceDisposition) { $mismatches.Add('evidence-disposition') }
  try { $null = ConvertTo-MIRAssuranceDateTimeOffset -Value $Receipt.completed_at }
  catch { $mismatches.Add('completed-at') }
  return [pscustomobject][ordered]@{
    valid=($mismatches.Count -eq 0)
    reason=($mismatches -join ', ')
  }
}

function Read-MIRAssuranceWorkerObject {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Context,
    [string]$ExpectedProducerRunId = "",
    [string]$ExpectedProducerRunAttempt = ""
  )

  $fingerprint = $Test.fingerprint
  $paths = Get-MIRAssuranceEvidencePaths -TestId ([string]$Test.id) -InputKey ([string]$fingerprint.input_key)
  $planMaterialSha256 = [string]$Plan.plan_material_sha256
  if ($planMaterialSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
    throw "Worker import for '$([string]$Test.id)' has no exact plan-material digest."
  }
  $receiptPath = Get-MIRAssuranceWorkerReceiptPath `
    -SourceRoot $SourceRoot `
    -PlanMaterialSha256 $planMaterialSha256 `
    -ExpectedPlan $Plan `
    -ExpectedProducerRunId $ExpectedProducerRunId `
    -ExpectedProducerRunAttempt $ExpectedProducerRunAttempt
  try { $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json }
  catch { throw "Worker artifact for '$([string]$Test.id)' has an invalid worker receipt." }
  $receiptDirectory = Join-Path $SourceRoot "worker-receipts\$planMaterialSha256"
  if ([IO.Path]::GetFullPath($receiptPath).StartsWith(([IO.Path]::GetFullPath($receiptDirectory).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase) -and
      (Get-MIRAssuranceSha256 -Path $receiptPath) -ne ([IO.Path]::GetFileNameWithoutExtension($receiptPath).ToUpperInvariant())) {
    throw "Worker artifact for '$([string]$Test.id)' has a digest-mismatched content-addressed receipt."
  }
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
  if (-not [string]::IsNullOrWhiteSpace($ExpectedProducerRunId) -and
      [string]$receipt.producer.run_id -ne $ExpectedProducerRunId) { $receiptMismatches.Add("receipt-producer-run-id") }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedProducerRunAttempt) -and
      [string]$receipt.producer.run_attempt -ne $ExpectedProducerRunAttempt) { $receiptMismatches.Add("receipt-producer-run-attempt") }
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
  # Complete passing-capsule admission against the worker object tree before
  # the aggregate writes a single file into its destination ledger.  The
  # ordinary validator is reused with a source-root resolver so its structured
  # result, artifact, captured-artifact, and capsule-schema checks remain one
  # contract for local execution and imported evidence.
  if ($outcome -eq "passed") {
    $workerValidation = Test-MIRAssuranceCapsule `
      -Capsule $capsule `
      -Fingerprint $fingerprint `
      -Context $Context `
      -Test $Test `
      -SourceRoot $SourceRoot
    if (-not [bool]$workerValidation.valid) {
      throw "Worker artifact for '$([string]$Test.id)' failed complete capsule validation before import: $([string]$workerValidation.reason)"
    }
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
  $contentAddressedReceiptRoot = [IO.Path]::GetFullPath((Join-Path $SourceRoot "worker-receipts\$planMaterialSha256")).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
  $receiptDestination = if ([IO.Path]::GetFullPath($receiptPath).StartsWith($contentAddressedReceiptRoot, [StringComparison]::OrdinalIgnoreCase)) {
    Join-Path $paths.root (Join-Path "worker-receipts\$planMaterialSha256" ([IO.Path]::GetFileName($receiptPath)))
  } else {
    # Preserve a historical flat V3 receipt at its actual legacy location.
    # A retry is rejected before this point, because it requires a transport-
    # bound content-addressed receipt; ordinary historical imports remain
    # reconstructible without fabricating a new receipt identity.
    Join-Path $paths.root "worker-receipts\$planMaterialSha256.json"
  }
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

function Publish-MIRAssuranceWorkerObject {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)]$WorkerObject,
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Context
  )

  $importLock = $null
  try {
    $identity = Get-MIRAssuranceAttemptIdentity -Capsule $WorkerObject.capsule
    $importLock = Enter-MIRAssuranceAttemptStateLock -Identity $identity
    $capsuleCanonical = Get-MIRAssuranceWorkerCanonicalPath -Path ([string]$WorkerObject.capsule.attempt_path)
    # Publish the capsule last. A crashed import can therefore leave only
    # unreferenced immutable support objects; it cannot make a half-imported
    # capsule visible to a trusted-attempt scan. The lock keeps final
    # publication and pointer reconciliation linearizable.
    $publishOrder = [Collections.Generic.List[string]]::new()
    foreach ($relativePath in @($WorkerObject.files | Where-Object {
      (Get-MIRAssuranceWorkerCanonicalPath -Path ([string]$_)).key -ne [string]$capsuleCanonical.key
    } | Sort-Object)) {
      $publishOrder.Add([string]$relativePath)
    }
    $capsuleFiles = @($WorkerObject.files | Where-Object {
      (Get-MIRAssuranceWorkerCanonicalPath -Path ([string]$_)).key -eq [string]$capsuleCanonical.key
    })
    if ($capsuleFiles.Count -ne 1) {
      throw "Worker artifact for '$([string]$Test.id)' does not publish exactly one immutable evidence capsule."
    }
    $publishOrder.Add([string]$capsuleFiles[0])
    foreach ($relativePath in @($publishOrder)) {
      $source = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $SourceRoot -DestinationRoot $WorkerObject.destination_paths.root -RepoRelativePath $relativePath
      $destination = Resolve-MIRAssurancePath -Path $relativePath
      $resolvedDestination = [IO.Path]::GetFullPath($destination)
      $destinationBoundary = [IO.Path]::GetFullPath($WorkerObject.destination_paths.root).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
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
    return Set-MIRAssuranceAttemptPointer `
      -Capsule $WorkerObject.capsule `
      -AttemptPath ([string]$WorkerObject.capsule.attempt_path) `
      -Context $Context `
      -Lock $importLock
  } finally {
    if ($null -ne $importLock) { Exit-MIRAssuranceAttemptStateLock -Lock $importLock }
  }
}

function Import-MIRAssuranceWorkerEvidence {
  param(
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][string]$WorkerRoot,
    [Parameter(Mandatory)][string]$ArtifactPrefix,
    [switch]$RetryAcrossAttempts,
    [string]$CurrentRunAttempt = ""
  )
  if ($ArtifactPrefix -notmatch '^[A-Za-z0-9._-]+$') {
    throw "Worker artifact prefix contains unsafe characters: $ArtifactPrefix"
  }
  [Int64]$currentRunAttemptNumber = 0
  if ($RetryAcrossAttempts) {
    if ($CurrentRunAttempt -notmatch '^[1-9][0-9]*$' -or
        -not [Int64]::TryParse($CurrentRunAttempt, [ref]$currentRunAttemptNumber)) {
      throw "Retry-aware worker import requires a positive current aggregate run attempt."
    }
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
  $expectedTests = @{}
  $expectedRowsByArtifactSuffix = @{}
  $candidates = @{}
  $preRejected = @{}
  foreach ($row in $work) {
    $expectedRows[[string]$row.test_id] = $row
    $test = @($Plan.tests | Where-Object { [string]$_.id -eq [string]$row.test_id })
    if ($test.Count -ne 1) { throw "Worker row '$([string]$row.test_id)' does not select exactly one planned test." }
    $expectedTests[[string]$row.test_id] = $test[0]
    $artifactSuffix = "$([string]$row.safe_test_id)-$([string]$test[0].fingerprint.fingerprint_sha256)"
    if ($expectedRowsByArtifactSuffix.ContainsKey($artifactSuffix)) {
      throw "Verification plan contains ambiguous worker artifact suffixes: $artifactSuffix"
    }
    $expectedRowsByArtifactSuffix[$artifactSuffix] = $row
    $candidates[[string]$row.test_id] = [Collections.Generic.List[object]]::new()
    $preRejected[[string]$row.test_id] = [Collections.Generic.List[string]]::new()
  }
  $ignored = [Collections.Generic.List[object]]::new()
  # Bounds and reparse-point checks precede every receipt lookup.  Receipt
  # directories are attacker-controlled transport input; do not enumerate or
  # parse them before the artifact itself has been admitted within the plan's
  # resource limits.
  $artifactTrees = @{}
  foreach ($directory in $artifactDirectories) {
    if (-not $directory.Name.StartsWith($ArtifactPrefix, [StringComparison]::Ordinal)) {
      $ignored.Add([ordered]@{artifact=$directory.Name;reason="prefix-mismatch"})
      continue
    }

    $artifactRowForTree = $null
    $artifactNameSuffix = $directory.Name.Substring($ArtifactPrefix.Length)
    if ($RetryAcrossAttempts) {
      $artifactNameMatch = [regex]::Match($artifactNameSuffix, '^(?<attempt>[1-9][0-9]*)-(?<row>.+)$')
      if ($artifactNameMatch.Success) {
        $candidateRowSuffix = [string]$artifactNameMatch.Groups['row'].Value
        if ($expectedRowsByArtifactSuffix.ContainsKey($candidateRowSuffix)) {
          $artifactRowForTree = $expectedRowsByArtifactSuffix[$candidateRowSuffix]
        } else {
          $candidateSafeRows = @($work | Where-Object {
            $candidateRowSuffix.StartsWith("$([string]$_.safe_test_id)-", [StringComparison]::Ordinal)
          })
          if ($candidateSafeRows.Count -eq 1) { $artifactRowForTree = $candidateSafeRows[0] }
        }
      }
    } else {
      $candidateSafeRows = @($work | Where-Object {
        $directory.Name -eq "$ArtifactPrefix$([string]$_.safe_test_id)"
      })
      if ($candidateSafeRows.Count -eq 1) { $artifactRowForTree = $candidateSafeRows[0] }
    }
    try {
      $artifactTrees[[string]$directory.FullName] = Assert-MIRAssuranceWorkerArtifactTree -ArtifactRoot $directory.FullName -Context $Context
    } catch {
      if ($null -ne $artifactRowForTree) {
        $preRejected[[string]$artifactRowForTree.test_id].Add("$($directory.Name): $($_.Exception.Message)")
      } else {
        $ignored.Add([ordered]@{artifact=$directory.Name;reason="invalid-artifact-tree"})
      }
      continue
    }

    $transportAttempt = ""
    $expectedTransportRunId = ""
    $expectedTransportRunAttempt = ""
    $retryMatchedRow = $null
    if ($RetryAcrossAttempts) {
      $artifactSuffix = $directory.Name.Substring($ArtifactPrefix.Length)
      $transportMatch = [regex]::Match($artifactSuffix, '^(?<attempt>[1-9][0-9]*)-(?<row>.+)$')
      if ($transportMatch.Success) {
        $transportAttempt = [string]$transportMatch.Groups['attempt'].Value
        $rowSuffix = [string]$transportMatch.Groups['row'].Value
        if ($expectedRowsByArtifactSuffix.ContainsKey($rowSuffix)) {
          $retryMatchedRow = $expectedRowsByArtifactSuffix[$rowSuffix]
          if ([Int64]$transportAttempt -gt $currentRunAttemptNumber) {
            $preRejected[[string]$retryMatchedRow.test_id].Add("$($directory.Name): transport attempt $transportAttempt exceeds current aggregate run attempt $currentRunAttemptNumber")
            continue
          }
          $expectedTransportRunId = [string]$Plan.producer.run_id
          $expectedTransportRunAttempt = $transportAttempt
        } else {
          $matchedSafeRows = @($work | Where-Object { $rowSuffix.StartsWith("$([string]$_.safe_test_id)-", [StringComparison]::Ordinal) })
          if ($matchedSafeRows.Count -eq 1) {
            $preRejected[[string]$matchedSafeRows[0].test_id].Add("$($directory.Name): artifact name does not bind the active planned fingerprint")
          } else {
            $ignored.Add([ordered]@{artifact=$directory.Name;reason="irrelevant-or-stale-retry-artifact"})
          }
          continue
        }
      } else {
        $ignored.Add([ordered]@{artifact=$directory.Name;reason="unrecognized-retry-artifact-name"})
        continue
      }
    }
    try {
      if ($RetryAcrossAttempts) {
        $transportReceipt = Get-MIRAssuranceWorkerTransportReceiptPath `
          -SourceRoot $directory.FullName `
          -ExpectedProducerRunId $expectedTransportRunId `
          -ExpectedProducerRunAttempt $expectedTransportRunAttempt
        $receiptPath = [string]$transportReceipt.path
      } else {
        $receiptPath = Get-MIRAssuranceWorkerReceiptPath `
          -SourceRoot $directory.FullName `
          -PlanMaterialSha256 ([string]$Plan.plan_material_sha256) `
          -ExpectedPlan $Plan `
          -ExpectedProducerRunId $expectedTransportRunId `
          -ExpectedProducerRunAttempt $expectedTransportRunAttempt
      }
      $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json
    } catch {
      $matchedExpected = @()
      if ($null -ne $retryMatchedRow) { $matchedExpected += $retryMatchedRow }
      else { $matchedExpected += @($work | Where-Object { $directory.Name -eq "$ArtifactPrefix$([string]$_.safe_test_id)" }) }
      if ($matchedExpected.Count -eq 1) { $preRejected[[string]$matchedExpected[0].test_id].Add("$($directory.Name): $($_.Exception.Message)") }
      else { $ignored.Add([ordered]@{artifact=$directory.Name;reason="invalid irrelevant receipt"}) }
      continue
    }
    $receiptTestId = [string]$receipt.work.test_id
    if ($RetryAcrossAttempts -and
        [string]$receipt.schema -eq "mir-assurance-worker-receipt-v3" -and
        $null -ne $retryMatchedRow -and
        [string]$receiptTestId -eq [string]$retryMatchedRow.test_id -and
        [string]$receipt.plan.material_sha256 -ne [string]$Plan.plan_material_sha256) {
      $staleTransport = Test-MIRAssuranceStalePlanTransportReceipt `
        -Receipt $receipt -CurrentPlan $Plan -Test $expectedTests[$receiptTestId] -Context $Context `
        -ExpectedProducerRunId $expectedTransportRunId -ExpectedProducerRunAttempt $expectedTransportRunAttempt
      if ([bool]$staleTransport.valid) {
        $ignored.Add([ordered]@{
          artifact=$directory.Name
          reason="stale-plan-transport"
          test_id=$receiptTestId
          plan_material_sha256=[string]$receipt.plan.material_sha256
          current_plan_material_sha256=[string]$Plan.plan_material_sha256
        })
      } else {
        $preRejected[$receiptTestId].Add("$($directory.Name): stale-plan transport receipt is not structurally trusted: $([string]$staleTransport.reason)")
      }
      continue
    }
    if ([string]$receipt.schema -ne "mir-assurance-worker-receipt-v3" -or
        [string]$receipt.plan.material_sha256 -ne [string]$Plan.plan_material_sha256 -or
        -not $expectedRows.ContainsKey($receiptTestId) -or
        ($null -ne $retryMatchedRow -and [string]$receiptTestId -ne [string]$retryMatchedRow.test_id)) {
      $matchedExpected = @()
      if ($null -ne $retryMatchedRow) { $matchedExpected += $retryMatchedRow }
      else { $matchedExpected += @($work | Where-Object { $directory.Name -eq "$ArtifactPrefix$([string]$_.safe_test_id)" }) }
      if ($matchedExpected.Count -eq 1) { $preRejected[[string]$matchedExpected[0].test_id].Add("$($directory.Name): receipt does not bind the active plan row") }
      else { $ignored.Add([ordered]@{artifact=$directory.Name;reason="irrelevant-plan-or-row"}) }
      continue
    }
    $candidateRecord = [pscustomobject][ordered]@{
      directory=$directory
      retry_across_attempts=[bool]$RetryAcrossAttempts
      transport_attempt=$transportAttempt
    }
    [void]$candidates[$receiptTestId].Add([object]$candidateRecord)
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
    $selectedCandidate = $null
    $orderedCandidates = @()
    if ($RetryAcrossAttempts) {
      $sameAttemptGroups = @($rowCandidates | Group-Object transport_attempt | Where-Object Count -gt 1)
      if ($sameAttemptGroups.Count -gt 0) {
        $duplicates.Add([ordered]@{
          test_id=[string]$test.id
          artifacts=@($sameAttemptGroups | ForEach-Object { @($_.Group.directory.Name | Sort-Object) } | Sort-Object -Unique)
        })
        continue
      }
      # Every trustworthy attempt is an immutable observation.  A newer
      # attempt can choose the displayed result only after all retained
      # attempts have passed receipt, capsule, and contradiction handling.
      # Never hide a conflicting predecessor merely because GitHub reran the
      # failed job.
      $orderedCandidates = @($rowCandidates | Sort-Object @{Expression={ [Int64]$_.transport_attempt };Descending=$false}, @{Expression={ [string]$_.directory.Name };Ascending=$true})
      $selectedCandidate = $orderedCandidates[-1]
    } elseif ($rowCandidates.Count -gt 1) {
      $duplicates.Add([ordered]@{test_id=[string]$test.id;artifacts=@($rowCandidates.directory.Name | Sort-Object)})
      continue
    } else {
      $selectedCandidate = $rowCandidates[0]
      $orderedCandidates = @($selectedCandidate)
    }
    $workerBoundary = [IO.Path]::GetFullPath($resolvedWorkerRoot).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
    $rowReasons = [Collections.Generic.List[string]]::new()
    foreach ($priorRejection in @($preRejected[[string]$test.id])) { $rowReasons.Add([string]$priorRejection) }
    # Validate every retained transport before publishing any of them.  Thus a
    # malformed newer attempt cannot leave an older passing pointer as a
    # covert fallback result for this aggregate.
    $validated = [Collections.Generic.List[object]]::new()
    foreach ($candidate in @($orderedCandidates)) {
      $resolvedArtifactRoot = [IO.Path]::GetFullPath([string]$candidate.directory.FullName)
      if (-not $resolvedArtifactRoot.StartsWith($workerBoundary, [StringComparison]::OrdinalIgnoreCase)) {
        $rowReasons.Add("$([string]$candidate.directory.Name): artifact path escaped worker root")
        continue
      }
      try {
        $tree = $artifactTrees[[string]$candidate.directory.FullName]
        if ($null -eq $tree) { throw "Worker artifact was not admitted by the bounded tree scan." }
        $workerObject = Read-MIRAssuranceWorkerObject `
          -SourceRoot $resolvedArtifactRoot `
          -Plan $Plan `
          -Test $test `
          -Context $Context `
          -ExpectedProducerRunId $(if ($RetryAcrossAttempts) { [string]$Plan.producer.run_id } else { "" }) `
          -ExpectedProducerRunAttempt $(if ($RetryAcrossAttempts) { [string]$candidate.transport_attempt } else { "" })
        $validated.Add([pscustomobject][ordered]@{candidate=$candidate;tree=$tree;worker_object=$workerObject})
      } catch {
        # A broken newer object is not permission to fall back to an older
        # result.  Keep any preceding valid attempt observed, but reject this
        # complete planned row.
        $rowReasons.Add("$([string]$candidate.directory.Name): $($_.Exception.Message)")
      }
    }
    if ($rowReasons.Count -gt 0 -or $validated.Count -ne $orderedCandidates.Count) {
      $rejected.Add([ordered]@{test_id=[string]$test.id;reasons=@($rowReasons)})
      continue
    }
    $observed = [Collections.Generic.List[object]]::new()
    foreach ($validatedObject in @($validated)) {
      try {
        $attemptState = Publish-MIRAssuranceWorkerObject `
          -SourceRoot ([string]$validatedObject.candidate.directory.FullName) `
          -WorkerObject $validatedObject.worker_object `
          -Test $test `
          -Context $Context
        $observed.Add([pscustomobject][ordered]@{
          candidate=$validatedObject.candidate
          tree=$validatedObject.tree
          worker_object=$validatedObject.worker_object
          attempt_state=$attemptState
        })
      } catch {
        $rowReasons.Add("$([string]$validatedObject.candidate.directory.Name): $($_.Exception.Message)")
      }
    }
    if ($rowReasons.Count -gt 0 -or $observed.Count -ne $validated.Count) {
      $rejected.Add([ordered]@{test_id=[string]$test.id;reasons=@($rowReasons)})
      continue
    }
    $quarantined = @($observed | Where-Object { [bool]$_.attempt_state.quarantined })
    if ($quarantined.Count -gt 0) {
      $rejected.Add([ordered]@{
        test_id=[string]$test.id
        reasons=@($quarantined | ForEach-Object {
          "trusted exact evidence is quarantined; independent fresh reproduction is required: $([string]$_.attempt_state.incident)"
        })
      })
      continue
    }
    $selected = @($observed | Where-Object {
      [string]$_.candidate.directory.Name -eq [string]$selectedCandidate.directory.Name
    })
    if ($selected.Count -ne 1) {
      $rejected.Add([ordered]@{test_id=[string]$test.id;reasons=@("Worker retry selection was not uniquely observed.")})
      continue
    }
    $selectedObservation = $selected[0]
    if ($RetryAcrossAttempts) {
      foreach ($superseded in @($observed | Where-Object {
        [string]$_.candidate.directory.Name -ne [string]$selectedCandidate.directory.Name
      })) {
        $ignored.Add([ordered]@{
          artifact=[string]$superseded.candidate.directory.Name
          reason="superseded-by-later-run-attempt"
          test_id=[string]$test.id
          selected_artifact=[string]$selectedCandidate.directory.Name
        })
      }
    }
    $record = [ordered]@{
      test_id=[string]$test.id
      input_key=[string]$test.fingerprint.input_key
      outcome=[string]$selectedObservation.worker_object.outcome
      result_digest=[string]$selectedObservation.worker_object.capsule.result_digest
      outcome_digest=(Get-MIRAssuranceOutcomeDigest -Capsule $selectedObservation.worker_object.capsule)
      capsule_sha256=[string]$selectedObservation.worker_object.pointer.capsule_sha256
      receipt_sha256=[string]$selectedObservation.worker_object.receipt_sha256
      pointer_status=[string]$selectedObservation.worker_object.pointer_status
      artifact=[string]$selectedCandidate.directory.Name
      entries=[int]$selectedObservation.tree.entries
      expanded_bytes=[long]$selectedObservation.tree.expanded_bytes
      quarantined=$false
      quarantine_incident=""
    }
    if ([string]$selectedObservation.worker_object.outcome -eq "passed") { $imported += $record }
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
