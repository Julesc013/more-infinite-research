function Get-MIRCPObjectPathValue {
  param(
    [Parameter(Mandatory)]$InputObject,
    [Parameter(Mandatory)][string]$Path
  )
  $current = $InputObject
  foreach ($segment in @($Path -split '\.')) {
    if ($null -eq $current) { return [pscustomobject][ordered]@{found=$false; value=$null} }
    if ($current -is [Collections.IDictionary]) {
      if (-not $current.Contains($segment)) { return [pscustomobject][ordered]@{found=$false; value=$null} }
      $current = $current[$segment]
      continue
    }
    $property = $current.PSObject.Properties[$segment]
    if ($null -eq $property) { return [pscustomobject][ordered]@{found=$false; value=$null} }
    $current = $property.Value
  }
  return [pscustomobject][ordered]@{found=$true; value=$current}
}

function New-MIRCPObservation {
  param(
    [ValidateSet("environment-capture", "engine-realization", "legacy-v4-adapter")][string]$Kind,
    [Parameter(Mandatory)][string]$EnvironmentSignature,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$CandidateSha256,
    [Parameter(Mandatory)]$Facts,
    [object[]]$Diagnostics = @(),
    [object[]]$Artifacts = @(),
    $Source = $null,
    [int]$ObservationAbi = 1,
    [int]$CanonicalizationAbi = 1
  )
  foreach ($digest in @($EnvironmentSignature, $CandidateSha256)) {
    if ([string]$digest -notmatch '^[0-9A-Fa-f]{64}$') { throw "Observation identity contains an invalid SHA-256 digest: $digest" }
  }
  $identity = [pscustomobject][ordered]@{
    kind = $Kind
    observation_abi = $ObservationAbi
    canonicalization_abi = $CanonicalizationAbi
    environment_signature = $EnvironmentSignature.ToUpperInvariant()
    target = $Target
    candidate_sha256 = $CandidateSha256.ToUpperInvariant()
    source = $Source
  }
  $record = [ordered]@{
    schema = 1
    kind = $Kind
    observation_abi = $ObservationAbi
    canonicalization_abi = $CanonicalizationAbi
    capture_key = Get-MIRCPSha256Object -Value $identity
    environment_signature = $EnvironmentSignature.ToUpperInvariant()
    target = $Target
    candidate_sha256 = $CandidateSha256.ToUpperInvariant()
  }
  if ($null -ne $Source) { $record.source = $Source }
  $record.facts = $Facts
  $record.diagnostics = @($Diagnostics)
  $record.artifacts = @($Artifacts)
  return [pscustomobject]$record
}

function Assert-MIRCPAssertionRecord {
  param([Parameter(Mandatory)]$Assertion)
  foreach ($field in @("schema", "id", "version", "type", "reads", "proposition", "expected")) {
    if ($null -eq $Assertion.PSObject.Properties[$field]) { throw "Assertion is missing required field '$field'." }
  }
  if ([int]$Assertion.schema -ne 1 -or [int]$Assertion.version -lt 1) { throw "Assertion version identity is invalid." }
  if ([string]$Assertion.type -notin @("status-equals", "field-equals", "captured-proposition")) { throw "Unsupported assertion type: $($Assertion.type)" }
  if (@($Assertion.reads).Count -eq 0) { throw "Assertion $($Assertion.id) has no observation reads." }
  if ([string]$Assertion.type -eq "field-equals" -and [string]::IsNullOrWhiteSpace([string]$Assertion.field)) { throw "field-equals assertion $($Assertion.id) has no field." }
}

function Invoke-MIRCPEvaluation {
  param(
    [Parameter(Mandatory)]$Observation,
    [Parameter(Mandatory)]$Assertion,
    [int]$EvaluationAbi = 1
  )
  Assert-MIRCPAssertionRecord -Assertion $Assertion
  $observationSha = Get-MIRCPSha256Object -Value $Observation
  $path = switch ([string]$Assertion.type) {
    "status-equals" { "facts.status" }
    "field-equals" { [string]$Assertion.field }
    "captured-proposition" { [string]@($Assertion.reads)[0] }
  }
  $read = Get-MIRCPObjectPathValue -InputObject $Observation -Path $path
  $actual = $read.value
  $status = "invalid"
  if ([bool]$read.found) {
    $actualJson = ConvertTo-MIRCPCanonicalJson -Value $actual
    $expectedJson = ConvertTo-MIRCPCanonicalJson -Value $Assertion.expected
    $status = if ($actualJson -ceq $expectedJson) { "passed" } else { "failed" }
  }
  $evaluationIdentity = [pscustomobject][ordered]@{
    evaluation_abi = $EvaluationAbi
    observation_sha256 = $observationSha
    assertion = $Assertion
  }
  $body = [pscustomobject][ordered]@{
    schema = 1
    evaluation_abi = $EvaluationAbi
    evaluation_key = Get-MIRCPSha256Object -Value $evaluationIdentity
    observation_sha256 = $observationSha
    assertion = $Assertion
    status = $status
    actual = $actual
    expected = $Assertion.expected
    proposition = [string]$Assertion.proposition
  }
  $record = [ordered]@{}
  foreach ($property in $body.PSObject.Properties) { $record[$property.Name] = $property.Value }
  $record.evidence_digest = Get-MIRCPSha256Object -Value $body
  return [pscustomobject]$record
}

function New-MIRCPV4Observation {
  param(
    [Parameter(Mandatory)]$EvidenceRow,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$CandidateSha256,
    [Parameter(Mandatory)][string]$BundleSha256
  )
  $producer = $EvidenceRow.producer
  $environmentMaterial = [pscustomobject][ordered]@{
    adapter = "mir-control-plane-v5/v4-evidence-adapter-1"
    bundle_sha256 = $BundleSha256
    target = $Target
    test_id = [string]$EvidenceRow.test_id
    input_key = [string]$EvidenceRow.input_key
    definition_sha256 = [string]$EvidenceRow.definition_sha256
    verifier_sha256 = [string]$producer.verifier_sha256
    policy_sha256 = [string]$producer.policy_sha256
  }
  $assertionFacts = [ordered]@{}
  foreach ($assertion in @($EvidenceRow.assertions | Sort-Object id)) {
    $assertionFacts[[string]$assertion.id] = [pscustomobject][ordered]@{status=[string]$assertion.status}
  }
  $facts = [pscustomobject][ordered]@{
    status = [string]$EvidenceRow.status
    conclusion = [string]$EvidenceRow.conclusion
    exit_code = [int]$EvidenceRow.exit_code
    result_status = [string]$EvidenceRow.result.status
    result_digest = [string]$EvidenceRow.result_digest
    assertions = [pscustomobject]$assertionFacts
  }
  $source = [pscustomobject][ordered]@{
    adapter = "v4-evidence-schema-4"
    bundle_sha256 = $BundleSha256
    test_id = [string]$EvidenceRow.test_id
    input_key = [string]$EvidenceRow.input_key
    fingerprint_sha256 = [string]$EvidenceRow.fingerprint_sha256
    definition_sha256 = [string]$EvidenceRow.definition_sha256
    result_digest = [string]$EvidenceRow.result_digest
    trust_class = [string]$producer.trust_class
  }
  return New-MIRCPObservation -Kind legacy-v4-adapter -EnvironmentSignature (Get-MIRCPSha256Object -Value $environmentMaterial) -Target $Target -CandidateSha256 $CandidateSha256 -Facts $facts -Artifacts @() -Source $source
}

function New-MIRCPV4ReplayReport {
  param(
    [string]$BundlePath = ".mir/evidence/3.2.2-local-automated-qualification.json",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $resolved = if ([IO.Path]::IsPathRooted($BundlePath)) { $BundlePath } else { Join-Path $repo $BundlePath }
  $bundle = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json
  $bundleSha = Get-MIRCPSha256File -Path $resolved
  $candidateSha = [string]$bundle.candidate_descriptor.sha256
  $rows = [Collections.Generic.List[object]]::new()
  $passed = 0
  $failed = 0
  $invalid = 0
  foreach ($evidence in @($bundle.evidence | Sort-Object test_id)) {
    $observation = New-MIRCPV4Observation -EvidenceRow $evidence -Target ([string]$bundle.target) -CandidateSha256 $candidateSha -BundleSha256 $bundleSha
    $assertion = [pscustomobject][ordered]@{
      schema = 1
      id = "assertion/v4-replay/$(ConvertTo-MIRCPAssertionIdPart -Value ([string]$evidence.test_id))/status-passed"
      version = 1
      type = "status-equals"
      reads = @("facts.status")
      proposition = "Historical v4 evidence '$([string]$evidence.test_id)' retained passed status."
      expected = "passed"
    }
    $evaluation = Invoke-MIRCPEvaluation -Observation $observation -Assertion $assertion
    switch ([string]$evaluation.status) {
      "passed" { $passed++ }
      "failed" { $failed++ }
      default { $invalid++ }
    }
    $rows.Add([pscustomobject][ordered]@{
      test_id = [string]$evidence.test_id
      source_result_digest = [string]$evidence.result_digest
      observation_sha256 = [string]$evaluation.observation_sha256
      capture_key = [string]$observation.capture_key
      evaluation_key = [string]$evaluation.evaluation_key
      evaluation_status = [string]$evaluation.status
      evidence_digest = [string]$evaluation.evidence_digest
    })
  }
  $expected = @($bundle.evidence).Count
  $body = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-control-plane-v5-historical-replay"
    adapter_abi = 1
    observation_abi = 1
    evaluation_abi = 1
    canonicalization_abi = 1
    source = [pscustomobject][ordered]@{
      path = Get-MIRCPRelativePath -Path $resolved -RepoRoot $repo
      sha256 = $bundleSha
      policy_id = [string]$bundle.policy_id
      bundle_sha256 = [string]$bundle.bundle_sha256
      plan_material_sha256 = [string]$bundle.plan_material_sha256
    }
    candidate = [pscustomobject][ordered]@{
      target = [string]$bundle.target
      archive_sha256 = $candidateSha
      content_sha256 = [string]$bundle.candidate_descriptor.content_sha256
    }
    metrics = [pscustomobject][ordered]@{
      source_evidence = $expected
      observations = $rows.Count
      evaluations = $rows.Count
      passed = $passed
      failed = $failed
      invalid = $invalid
    }
    verdict = if ($rows.Count -eq $expected -and $passed -eq $expected -and $failed -eq 0 -and $invalid -eq 0) { "passed" } else { "failed" }
    rows = @($rows)
  }
  $report = [ordered]@{}
  foreach ($property in $body.PSObject.Properties) { $report[$property.Name] = $property.Value }
  $report.replay_sha256 = Get-MIRCPSha256Object -Value $body
  return [pscustomobject]$report
}

function Update-MIRCPV4ReplayReport {
  param(
    [string]$RepoRoot = "",
    [switch]$Check
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $report = New-MIRCPV4ReplayReport -RepoRoot $repo
  Write-MIRCPJson -Path ".mir/control-plane/baselines/3.2.2-v5-replay.json" -Value $report -RepoRoot $repo -Check:$Check
  return $report
}
