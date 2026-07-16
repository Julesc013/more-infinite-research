function Get-MIRAssurancePatternFingerprint {
  param([Parameter(Mandatory)][string[]]$Patterns)
  if ($null -eq $script:MIRAssurancePatternFingerprintCache) { $script:MIRAssurancePatternFingerprintCache = @{} }
  $cacheKey = @($Patterns | ForEach-Object { ([string]$_).Replace("\", "/") } | Sort-Object -Unique) -join "`n"
  if ($script:MIRAssurancePatternFingerprintCache.ContainsKey($cacheKey)) {
    return $script:MIRAssurancePatternFingerprintCache[$cacheKey]
  }
  $files = @(Resolve-MIRAssurancePatternFiles -Patterns $Patterns)
  $hash = if ($files.Count -gt 0) {
    Get-MIRAssuranceTreeHash -Paths $files
  } else {
    Get-MIRAssuranceTextHash -Text ("NO_MATCH`n" + (($Patterns | Sort-Object -Unique) -join "`n"))
  }
  $fingerprint = [ordered]@{
    kind="repository-patterns"
    patterns=@($Patterns | Sort-Object -Unique)
    file_count=$files.Count
    sha256=$hash
  }
  $script:MIRAssurancePatternFingerprintCache[$cacheKey] = $fingerprint
  return $fingerprint
}

function Get-MIRAssuranceInputFingerprint {
  param(
    [Parameter(Mandatory)][string]$InputName,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$Test
  )
  switch ($InputName) {
    "candidate" { return Get-MIRAssuranceExternalFileFingerprint -Path $Context.candidate -MissingLabel "candidate" }
    "factorio" { return Get-MIRAssuranceExternalFileFingerprint -Path $Context.factorio -MissingLabel "factorio" }
    "prior-release" { return Get-MIRAssuranceExternalFileFingerprint -Path $Context.prior_release -MissingLabel "prior-release" }
    "package-source" {
      $files = @(Get-MIRAssurancePackageFiles)
      return [ordered]@{ kind="package-source"; file_count=$files.Count; sha256=(Get-MIRAssuranceTreeHash -Paths $files) }
    }
    "repository" {
      $files = @(Get-MIRAssuranceRepositoryFiles)
      return [ordered]@{ kind="repository"; file_count=$files.Count; sha256=(Get-MIRAssuranceTreeHash -Paths $files) }
    }
    "test-catalog" { return [ordered]@{ kind="manifest"; path="validation/tests.yml"; sha256=(Get-MIRAssuranceSha256 -Path $catalogPath) } }
    "target-profile" {
      return Get-MIRAssurancePatternFingerprint -Patterns @(".mir/targets.json", "scripts/validation/TargetProfiles.ps1")
    }
    "verification-profile" {
      $path = Get-MIRAssuranceVerificationProfilePath -Target $Context.target
      return [ordered]@{ kind="verification-profile"; path=(Get-MIRAssuranceRepoRelativePath -Path $path); sha256=(Get-MIRAssuranceSha256 -Path $path) }
    }
    "selected-scenarios" {
      $selectionHash = Get-MIRAssuranceJsonHash -Value $Plan.impact_selection
      $registryHash = Get-MIRAssuranceSha256 -Path $scenarioRegistryPath
      return [ordered]@{
        kind="selected-scenarios"
        selection_sha256=$selectionHash
        registry_sha256=$registryHash
        sha256=(Get-MIRAssuranceTextHash -Text "$selectionHash`n$registryHash")
      }
    }
    "exact-dist-scenarios" {
      $registryHash = Get-MIRAssuranceSha256 -Path $scenarioRegistryPath
      return [ordered]@{ kind="exact-dist-scenarios"; registry_sha256=$registryHash; selector="smoke"; sha256=(Get-MIRAssuranceTextHash -Text "$registryHash`nsmoke") }
    }
    "required-scenarios" {
      return [ordered]@{ kind="required-scenarios"; sha256=(Get-MIRAssuranceSha256 -Path $scenarioRegistryPath) }
    }
    "harness" { return Get-MIRAssuranceScenarioHarnessFingerprint }
    "scenario-harness" { return Get-MIRAssuranceScenarioHarnessFingerprint }
    "scenario-record" { return Get-MIRAssuranceScenarioRecordFingerprint -Test $Test }
    "scenario-fixtures" { return Get-MIRAssuranceScenarioFixtureFingerprint -Test $Test }
    "scenario-domains" { return Get-MIRAssuranceScenarioDomainFingerprint -Test $Test -Context $Context }
    "balance-contract" { return Get-MIRAssuranceBalanceContractFingerprint }
    "fixtures" { return Get-MIRAssurancePatternFingerprint -Patterns @("fixtures/**") }
    "settings" {
      return Get-MIRAssurancePatternFingerprint -Patterns @("settings*.lua", "prototypes/mir/settings/**", ".mir/settings.yml")
    }
    "mod-lock" {
      return Get-MIRAssurancePatternFingerprint -Patterns @(".mir/fixtures.yml", "fixtures/compat-matrix/**", "fixtures/local-mod-library/**")
    }
    "ecosystem-profile" {
      return Get-MIRAssurancePatternFingerprint -Patterns @("fixtures/run-profiles/**", "fixtures/compat-matrix/**")
    }
    "upgrade-fixture" {
      $fixture = [string]$Context.verification_profile.upgrade.fixture
      return Get-MIRAssurancePatternFingerprint -Patterns @("fixtures/$fixture/**", "scripts/Test-MIRUpgrade.ps1")
    }
    "candidate-seal" {
      if ($Context.seal) { return Get-MIRAssuranceExternalFileFingerprint -Path $Context.seal -MissingLabel "candidate-seal" }
      return Get-MIRAssurancePatternFingerprint -Patterns @(".mir/evidence/candidate-seals/**")
    }
    "evidence" {
      $paths = @()
      if ($Context.seal -and (Test-Path -LiteralPath $Context.seal -PathType Leaf)) {
        $paths += Get-MIRAssuranceRepoRelativePath -Path $Context.seal
        $seal = Get-Content -Raw -LiteralPath $Context.seal | ConvertFrom-Json
        if ($seal.qualification_summary) { $paths += ([string]$seal.qualification_summary).Replace("\", "/") }
      } else {
        $paths = @(Resolve-MIRAssurancePatternFiles -Patterns @(".mir/evidence/**"))
      }
      return [ordered]@{ kind="evidence"; file_count=$paths.Count; sha256=(Get-MIRAssuranceTreeHash -Paths $paths) }
    }
    "runtime.full" {
      $material = [ordered]@{
        target=[string]$Context.target
        scenario_registry_sha256=(Get-MIRAssuranceSha256 -Path $scenarioRegistryPath)
        domain_manifest_sha256=if ($Plan.domain_manifest) { [string]$Plan.domain_manifest.manifest_sha256 } else { "" }
        harness=(Get-MIRAssuranceScenarioHarnessFingerprint).sha256
      }
      return [ordered]@{ kind="required-runtime-set"; sha256=(Get-MIRAssuranceJsonHash -Value $material) }
    }
    default {
      $looksLikePath = $InputName.Contains("/") -or $InputName.Contains("\") -or $InputName.Contains("*") -or $InputName.Contains(".")
      if (-not $looksLikePath) { throw "Unknown assurance input token '$InputName'. Declare a supported token or repository path pattern." }
      return Get-MIRAssurancePatternFingerprint -Patterns @($InputName)
    }
  }
}

function Get-MIRAssuranceTestFingerprint {
  param(
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context
  )
  $definition = [ordered]@{
    id=[string]$Test.id
    template_id=[string]$Test.template_id
    kind=[string]$Test.kind
    layer=[string]$Test.layer
    command=[string]$Test.command
    requires_factorio=[bool]$Test.requires_factorio
    requires_candidate=[bool]$Test.requires_candidate
    inputs=@($Test.inputs | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    domain_dependencies=@($Test.domain_dependencies | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    scenario_sha256=if ($Test.scenario) { Get-MIRAssuranceJsonHash -Value $Test.scenario } else { "" }
  }
  $definitionHash = Get-MIRAssuranceJsonHash -Value $definition
  $inputFingerprints = [ordered]@{}
  $runnerHash = Get-MIRAssuranceRunnerHash
  $inputFingerprints["assurance-runner"] = [ordered]@{ kind="runner"; version=$assuranceRunnerVersion; sha256=$runnerHash }
  foreach ($inputName in @($definition.inputs)) {
    $inputFingerprints[$inputName] = Get-MIRAssuranceInputFingerprint -InputName $inputName -Plan $Plan -Context $Context -Test $Test
  }
  $material = [ordered]@{
    schema=$evidenceSchema
    test_id=[string]$Test.id
    target=[string]$Context.target
    definition_sha256=$definitionHash
    inputs=$inputFingerprints
  }
  $fingerprintHash = Get-MIRAssuranceJsonHash -Value $material
  return [ordered]@{
    schema=$evidenceSchema
    test_id=[string]$Test.id
    target=[string]$Context.target
    definition=$definition
    definition_sha256=$definitionHash
    inputs=$inputFingerprints
    fingerprint_sha256=$fingerprintHash
    input_key=$fingerprintHash
  }
}

function Get-MIRAssuranceEvidencePaths {
  param([Parameter(Mandatory)][string]$TestId, [Parameter(Mandatory)][string]$InputKey)
  $safeId = $TestId -replace '[^A-Za-z0-9._-]', '_'
  $root = Join-Path $evidenceRoot (Join-Path $safeId $InputKey)
  return [ordered]@{
    root=$root
    attempts=(Join-Path $root "attempts")
    passed=(Join-Path $root "passed.json")
    blocked=(Join-Path $root "blocked.json")
    running=(Join-Path $root "running.json")
  }
}

function Get-MIRAssuranceRepositoryIdentity {
  if (-not [string]::IsNullOrWhiteSpace([string]$env:GITHUB_REPOSITORY)) {
    return [string]$env:GITHUB_REPOSITORY
  }
  $remote = @(& git -C $repo remote get-url origin 2>$null)
  if ($LASTEXITCODE -eq 0 -and $remote.Count -gt 0) {
    $identity = ([string]$remote[0]).Trim()
    $identity = $identity -replace '^git@github\.com:', ''
    $identity = $identity -replace '^https://github\.com/', ''
    $identity = $identity -replace '\.git$', ''
    if ($identity) { return $identity }
  }
  return "local"
}

function Get-MIRAssuranceProducer {
  return [ordered]@{
    repository=(Get-MIRAssuranceRepositoryIdentity)
    workflow=if ($env:GITHUB_WORKFLOW) { [string]$env:GITHUB_WORKFLOW } else { "local" }
    run_id=if ($env:GITHUB_RUN_ID) { [string]$env:GITHUB_RUN_ID } else { "local-$PID" }
    run_attempt=if ($env:GITHUB_RUN_ATTEMPT) { [string]$env:GITHUB_RUN_ATTEMPT } else { "1" }
    job=if ($env:GITHUB_JOB) { [string]$env:GITHUB_JOB } else { "local" }
    actor=if ($env:GITHUB_ACTOR) { [string]$env:GITHUB_ACTOR } else { [Environment]::UserName }
    commit=(& git -C $repo rev-parse HEAD).Trim()
  }
}

function Test-MIRAssuranceTrustedProducer {
  param([Parameter(Mandatory)]$Producer, [Parameter(Mandatory)]$Context)
  if ($null -eq $Producer) { return $false }
  $repository = [string]$Producer.repository
  if ([string]::IsNullOrWhiteSpace($repository)) { return $false }
  $current = Get-MIRAssuranceRepositoryIdentity
  if ($repository -eq $current) { return $true }
  if ($repository -eq "local" -and $current -eq "local") { return $true }
  return $false
}

function Get-MIRAssuranceCapsuleDigest {
  param([Parameter(Mandatory)]$Capsule)
  $material = [ordered]@{
    schema=[int]$Capsule.schema
    test_id=[string]$Capsule.test_id
    conclusion=[string]$Capsule.conclusion
    input_key=[string]$Capsule.input_key
    fingerprint_sha256=[string]$Capsule.fingerprint_sha256
    definition_sha256=[string]$Capsule.definition_sha256
    target=[string]$Capsule.target
    command=[string]$Capsule.command
    resolved_command=[string]$Capsule.resolved_command
    inputs=$Capsule.inputs
    producer=$Capsule.producer
    assertions=$Capsule.assertions
    log_digest=[string]$Capsule.log_digest
    started_at=(ConvertTo-MIRAssuranceTimestampText -Value $Capsule.started_at)
    completed_at=(ConvertTo-MIRAssuranceTimestampText -Value $Capsule.completed_at)
    duration_seconds=[double]$Capsule.duration_seconds
    message=[string]$Capsule.message
  }
  return Get-MIRAssuranceJsonHash -Value $material
}

function Test-MIRAssuranceCapsule {
  param(
    [Parameter(Mandatory)]$Capsule,
    [Parameter(Mandatory)]$Fingerprint,
    [Parameter(Mandatory)]$Context
  )
  if ([int]$Capsule.schema -ne $evidenceSchema) { return [ordered]@{valid=$false; reason="schema-mismatch"} }
  if ([string]$Capsule.conclusion -ne "passed" -or [string]$Capsule.status -ne "passed") { return [ordered]@{valid=$false; reason="not-passing"} }
  if ([string]$Capsule.test_id -ne [string]$Fingerprint.test_id) { return [ordered]@{valid=$false; reason="test-id-mismatch"} }
  if ([string]$Capsule.target -ne [string]$Fingerprint.target) { return [ordered]@{valid=$false; reason="target-mismatch"} }
  if ([string]$Capsule.input_key -ne [string]$Fingerprint.input_key) { return [ordered]@{valid=$false; reason="input-key-mismatch"} }
  if ([string]$Capsule.fingerprint_sha256 -ne [string]$Fingerprint.fingerprint_sha256) { return [ordered]@{valid=$false; reason="fingerprint-mismatch"} }
  if ([string]$Capsule.definition_sha256 -ne [string]$Fingerprint.definition_sha256) { return [ordered]@{valid=$false; reason="definition-mismatch"} }
  if (-not (Test-MIRAssuranceTrustedProducer -Producer $Capsule.producer -Context $Context)) { return [ordered]@{valid=$false; reason="untrusted-producer"} }
  $expectedDigest = Get-MIRAssuranceCapsuleDigest -Capsule $Capsule
  if ([string]$Capsule.result_digest -ne $expectedDigest) { return [ordered]@{valid=$false; reason="result-digest-mismatch"} }
  return [ordered]@{valid=$true; reason="exact-trusted-pass"}
}

function ConvertTo-MIRAssuranceOrderedMap {
  param([Parameter(Mandatory)]$Object)
  $map = [ordered]@{}
  foreach ($property in $Object.PSObject.Properties) { $map[$property.Name] = $property.Value }
  return $map
}

function Get-MIRAssuranceReusableEvidence {
  param([Parameter(Mandatory)]$Fingerprint, [Parameter(Mandatory)]$Context)
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  if (-not (Test-Path -LiteralPath $paths.passed -PathType Leaf)) { return $null }
  if (Test-Path -LiteralPath $paths.blocked -PathType Leaf) { return $null }
  try { $capsule = Get-Content -Raw -LiteralPath $paths.passed | ConvertFrom-Json }
  catch { return $null }
  $validation = Test-MIRAssuranceCapsule -Capsule $capsule -Fingerprint $Fingerprint -Context $Context
  if (-not [bool]$validation.valid) { return $null }
  $result = ConvertTo-MIRAssuranceOrderedMap -Object $capsule
  $result.disposition = "REUSE"
  $result.decision_reason = [string]$validation.reason
  $result.reused_at = (Get-Date).ToUniversalTime().ToString("o")
  $result.source_duration_seconds = [double]$capsule.duration_seconds
  $result.duration_seconds = 0
  $result.evidence_path = Get-MIRAssuranceRepoRelativePath -Path $paths.passed
  return $result
}

function Get-MIRAssuranceRunningEvidence {
  param(
    [Parameter(Mandatory)]$Fingerprint,
    $Context = $null
  )
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  if (-not (Test-Path -LiteralPath $paths.running -PathType Leaf)) { return $null }
  try { $running = Get-Content -Raw -LiteralPath $paths.running | ConvertFrom-Json }
  catch { return $null }
  if ([string]$running.test_id -ne [string]$Fingerprint.test_id -or [string]$running.input_key -ne [string]$Fingerprint.input_key) { return $null }
  if ($null -ne $Context -and -not (Test-MIRAssuranceTrustedProducer -Producer $running.producer -Context $Context)) {
    Remove-Item -LiteralPath $paths.running -Force
    return $null
  }
  try { $expires = ConvertTo-MIRAssuranceDateTimeOffset -Value $running.expires_at }
  catch { return $null }
  if ($expires -le [DateTimeOffset]::UtcNow) {
    Remove-Item -LiteralPath $paths.running -Force
    return $null
  }
  if ([string]$running.producer.workflow -eq "local" -and [int]$running.process_id -gt 0) {
    $process = Get-Process -Id ([int]$running.process_id) -ErrorAction SilentlyContinue
    $startedAtValid = $true
    try { $startedAt = ConvertTo-MIRAssuranceDateTimeOffset -Value $running.started_at }
    catch {
      $startedAt = [DateTimeOffset]::MinValue
      $startedAtValid = $false
    }
    $processIsOwner = [int]$running.process_id -eq $PID -or (
      $null -ne $process -and (
        -not $startedAtValid -or $process.StartTime.ToUniversalTime() -le $startedAt.UtcDateTime.AddSeconds(5)
      )
    )
    if (-not $processIsOwner) {
      Remove-Item -LiteralPath $paths.running -Force
      return $null
    }
  }
  return $running
}

function Get-MIRAssuranceEvidenceDecision {
  param(
    [Parameter(Mandatory)]$Fingerprint,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][string]$TestId
  )
  if (@($Context.rerun_tests | Where-Object { $_ -eq $TestId }).Count -gt 0) {
    return [ordered]@{disposition="RUN"; reason="explicit-rerun"}
  }
  if (-not [bool]$Context.reuse_enabled) {
    return [ordered]@{disposition="RUN"; reason="reuse-disabled"}
  }
  if (Test-MIRAssuranceCanReuseTest -TestId $TestId -Context $Context) {
    $reused = Get-MIRAssuranceReusableEvidence -Fingerprint $Fingerprint -Context $Context
    if ($null -ne $reused) {
      return [ordered]@{disposition="REUSE"; reason="exact-trusted-pass"; evidence=$reused}
    }
    $running = Get-MIRAssuranceRunningEvidence -Fingerprint $Fingerprint -Context $Context
    if ($null -ne $running) {
      return [ordered]@{disposition="WAIT"; reason="matching-worker-in-progress"; running=$running}
    }
  }
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  if ((Test-Path -LiteralPath $paths.passed -PathType Leaf) -or (Test-Path -LiteralPath $paths.blocked -PathType Leaf)) {
    return [ordered]@{disposition="INVALID"; reason="stored-evidence-is-not-a-trusted-exact-pass"}
  }
  return [ordered]@{disposition="RUN"; reason="no-exact-evidence"}
}

function Write-MIRAssuranceRunningEvidence {
  param([Parameter(Mandatory)]$Fingerprint, [Parameter(Mandatory)]$Context)
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  New-Item -ItemType Directory -Force -Path $paths.root | Out-Null
  $ttl = [int]$Context.verification_profile.running_evidence_ttl_minutes
  if ($ttl -le 0) { $ttl = 360 }
  $running = [ordered]@{
    schema=1
    test_id=[string]$Fingerprint.test_id
    input_key=[string]$Fingerprint.input_key
    fingerprint_sha256=[string]$Fingerprint.fingerprint_sha256
    target=[string]$Fingerprint.target
    producer=(Get-MIRAssuranceProducer)
    started_at=[DateTimeOffset]::UtcNow.ToString("o")
    expires_at=[DateTimeOffset]::UtcNow.AddMinutes($ttl).ToString("o")
    process_id=$PID
  }
  [IO.File]::WriteAllText($paths.running, (($running | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
  return $running
}

function Remove-MIRAssuranceRunningEvidence {
  param([Parameter(Mandatory)]$Fingerprint)
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  if (Test-Path -LiteralPath $paths.running -PathType Leaf) { Remove-Item -LiteralPath $paths.running -Force }
}

function Write-MIRAssuranceAttempt {
  param([Parameter(Mandatory)]$Capsule)
  if (-not $Capsule.Contains("conclusion")) { $Capsule["conclusion"] = [string]$Capsule.status }
  if (-not $Capsule.Contains("producer")) { $Capsule["producer"] = Get-MIRAssuranceProducer }
  $roundTripped = ($Capsule | ConvertTo-Json -Depth 40 -Compress) | ConvertFrom-Json
  $Capsule["result_digest"] = Get-MIRAssuranceCapsuleDigest -Capsule $roundTripped
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Capsule.test_id -InputKey $Capsule.input_key
  New-Item -ItemType Directory -Force -Path $paths.attempts | Out-Null
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffffffZ")
  $attemptPath = Join-Path $paths.attempts ("$stamp-$([guid]::NewGuid().ToString('N')).json")
  $Capsule["attempt_path"] = Get-MIRAssuranceRepoRelativePath -Path $attemptPath
  [IO.File]::WriteAllText($attemptPath, (($Capsule | ConvertTo-Json -Depth 40) + "`n"), [Text.UTF8Encoding]::new($false))
  New-Item -ItemType Directory -Force -Path $paths.root | Out-Null
  if ([string]$Capsule.status -eq "passed") {
    [IO.File]::WriteAllText($paths.passed, (($Capsule | ConvertTo-Json -Depth 40) + "`n"), [Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $paths.blocked) { Remove-Item -LiteralPath $paths.blocked -Force }
  } else {
    [IO.File]::WriteAllText($paths.blocked, (($Capsule | ConvertTo-Json -Depth 40) + "`n"), [Text.UTF8Encoding]::new($false))
  }
  if (Test-Path -LiteralPath $paths.running -PathType Leaf) { Remove-Item -LiteralPath $paths.running -Force }
  return $Capsule
}

function Quote-MIRAssuranceCommandArgument {
  param([Parameter(Mandatory)][string]$Value)
  return "'" + $Value.Replace("'", "''") + "'"
}

function Resolve-MIRAssuranceCommandText {
  param(
    [Parameter(Mandatory)][string]$Command,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$Plan
  )
  $values = [ordered]@{
    "<factorio>"=[string]$Context.factorio
    "<candidate>"=[string]$Context.candidate
    "<prior-release>"=[string]$Context.prior_release
    "<baseline>"=[string]$Plan.baseline
    "<seal>"=[string]$Context.seal
    "<target>"=[string]$Context.target
    "<upgrade-from>"=[string]$Context.verification_profile.upgrade.from_version
    "<upgrade-to>"=[string]$Context.verification_profile.upgrade.to_version
    "<upgrade-fixture>"=[string]$Context.verification_profile.upgrade.fixture
  }
  $resolved = $Command
  foreach ($entry in $values.GetEnumerator()) {
    if ($resolved.Contains([string]$entry.Key)) {
      if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) { throw "Command requires $($entry.Key), but no matching option was supplied." }
      $resolved = $resolved.Replace([string]$entry.Key, (Quote-MIRAssuranceCommandArgument -Value ([string]$entry.Value)))
    }
  }
  if ($resolved -match '<[^>]+>') { throw "Unresolved assurance command placeholder: $resolved" }
  return $resolved
}

function Invoke-MIRAssuranceCommandText {
  param(
    [Parameter(Mandatory)][string]$Command,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$Plan
  )
  $resolved = Resolve-MIRAssuranceCommandText -Command $Command -Context $Context -Plan $Plan
  $tokens = [Management.Automation.PSParser]::Tokenize($resolved, [ref]$null) | Where-Object { $_.Type -notin @("Comment", "NewLine") }
  if ($tokens.Count -eq 0) { throw "Empty assurance command." }
  $commandPath = [string]$tokens[0].Content
  if ($commandPath.StartsWith("./")) { $commandPath = Join-Path $repo $commandPath.Substring(2) }
  $argumentTokens = @($tokens | Select-Object -Skip 1)
  $global:LASTEXITCODE = 0
  if ([IO.Path]::GetFileName($commandPath) -eq "mir.ps1") {
    $arguments = @($argumentTokens | ForEach-Object { [string]$_.Content })
    & $commandPath @arguments | Out-Host
  } else {
    $named = @{}
    $positional = @()
    for ($i = 0; $i -lt $argumentTokens.Count; $i++) {
      $token = $argumentTokens[$i]
      if ($token.Type -eq [Management.Automation.PSTokenType]::CommandParameter) {
        $name = ([string]$token.Content).TrimStart("-")
        $value = $true
        if ($i + 1 -lt $argumentTokens.Count -and $argumentTokens[$i + 1].Type -ne [Management.Automation.PSTokenType]::CommandParameter) {
          $i++
          $value = [string]$argumentTokens[$i].Content
        }
        $named[$name] = $value
      } else {
        $positional += [string]$token.Content
      }
    }
    & $commandPath @named @positional | Out-Host
  }
  if ($LASTEXITCODE -ne 0) { throw "Assurance test command failed ($LASTEXITCODE): $resolved" }
  return $resolved
}

function Test-MIRAssuranceCanReuseTest {
  param([Parameter(Mandatory)][string]$TestId, [Parameter(Mandatory)]$Context)
  if (-not [bool]$Context.reuse_enabled) { return $false }
  if (@($Context.rerun_tests | Where-Object { $_ -eq $TestId }).Count -gt 0) { return $false }
  return $true
}

function Add-MIRAssurancePlanDecisions {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Context)
  $decorated = @()
  $work = @()
  foreach ($testValue in @($Plan.tests)) {
    $test = ConvertTo-MIRAssuranceOrderedMap -Object $testValue
    if (-not $test.Contains("safe_test_id") -or [string]::IsNullOrWhiteSpace([string]$test.safe_test_id)) {
      $test["safe_test_id"] = ([string]$test.id -replace '[^A-Za-z0-9._-]', '_')
    }
    $fingerprint = Get-MIRAssuranceTestFingerprint -Test $test -Plan $Plan -Context $Context
    $decision = Get-MIRAssuranceEvidenceDecision -Fingerprint $fingerprint -Context $Context -TestId ([string]$test.id)
    $test["fingerprint"] = $fingerprint
    $test["disposition"] = [string]$decision.disposition
    $test["decision_reason"] = [string]$decision.reason
    $decorated += [pscustomobject]$test
    if ([string]$decision.disposition -ne "REUSE") {
      $work += [pscustomobject][ordered]@{
        test_id=[string]$test.id
        safe_test_id=[string]$test.safe_test_id
        fingerprint=[string]$fingerprint.fingerprint_sha256
        disposition=[string]$decision.disposition
        layer=[string]$test.layer
      }
    }
  }
  $Plan.tests = @($decorated)
  $Plan["work"] = @($work)
  $Plan["counts"] = [ordered]@{
    total=$decorated.Count
    reuse=@($decorated | Where-Object disposition -eq "REUSE").Count
    wait=@($decorated | Where-Object disposition -eq "WAIT").Count
    run=@($decorated | Where-Object disposition -eq "RUN").Count
    invalid=@($decorated | Where-Object disposition -eq "INVALID").Count
  }
  return $Plan
}

function Get-MIRAssurancePlanFromOption {
  param([Parameter(Mandatory)]$Context, [switch]$RequirePlan)
  $planOption = Get-MIRAssuranceOption -Name "--plan"
  if ($planOption) {
    $path = Resolve-MIRAssurancePath -Path $planOption
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Verification plan not found: $path" }
    $plan = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    if ([int]$plan.schema -ne 3) { throw "Verification plan schema must be 3." }
    if ([string]$plan.target -ne [string]$Context.target) { throw "Verification plan target does not match --target." }
    return $plan
  }
  if ($RequirePlan) { throw "This command requires --plan <verification-plan.json>." }
  return Get-MIRAssurancePlan -Context $Context
}

function Get-MIRAssurancePlannedTest {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][string]$TestId)
  if ([string]::IsNullOrWhiteSpace($TestId)) { throw "--test <stable-id> is required." }
  $matches = @($Plan.tests | Where-Object { [string]$_.id -eq $TestId })
  if ($matches.Count -ne 1) { throw "Verification plan does not contain exactly one test '$TestId'." }
  return $matches[0]
}

function Wait-MIRAssuranceEvidence {
  param(
    [Parameter(Mandatory)]$Fingerprint,
    [Parameter(Mandatory)]$Context,
    [int]$PollSeconds = 5
  )
  while ($true) {
    $reused = Get-MIRAssuranceReusableEvidence -Fingerprint $Fingerprint -Context $Context
    if ($null -ne $reused) { return $reused }
    $running = Get-MIRAssuranceRunningEvidence -Fingerprint $Fingerprint -Context $Context
    if ($null -eq $running) { return $null }
    Start-Sleep -Seconds $PollSeconds
  }
}

function Invoke-MIRAssuranceTest {
  param(
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context
  )
  New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
  $id = [string]$Test.id
  if ([bool]$Test.requires_factorio -and (-not $Context.factorio -or -not (Test-Path -LiteralPath $Context.factorio -PathType Leaf))) {
    throw "Test $id requires --factorio with a matching Factorio binary."
  }
  if ($id -eq "runtime.upgrade" -and (-not $Context.prior_release -or -not (Test-Path -LiteralPath $Context.prior_release -PathType Leaf))) {
    throw "Test runtime.upgrade requires --prior with the exact prior-release archive."
  }
  if ([bool]$Test.requires_candidate -or @($Test.inputs | Where-Object { [string]$_ -eq "candidate" }).Count -gt 0) {
    if (-not (Test-Path -LiteralPath $Context.candidate -PathType Leaf)) {
      throw "Test $id requires the exact candidate archive: $($Context.candidate)"
    }
  }

  $fingerprint = if ($Test.fingerprint) { $Test.fingerprint } else { Get-MIRAssuranceTestFingerprint -Test $Test -Plan $Plan -Context $Context }
  $decision = Get-MIRAssuranceEvidenceDecision -Fingerprint $fingerprint -Context $Context -TestId $id
  if ([string]$decision.disposition -eq "REUSE") {
    Write-Host "[REUSE] $id $($fingerprint.input_key)"
    return $decision.evidence
  }
  if ([string]$decision.disposition -eq "WAIT") {
    Write-Host "[WAIT] $id $($fingerprint.input_key)"
    $adopted = Wait-MIRAssuranceEvidence -Fingerprint $fingerprint -Context $Context
    if ($null -ne $adopted) {
      $adopted.disposition = "WAIT"
      $adopted.decision_reason = "adopted-matching-worker-result"
      return $adopted
    }
    Write-Host "[RUN] matching worker expired without reusable evidence; adopting $id"
  } else {
    Write-Host "[$($decision.disposition)] $id $($fingerprint.input_key)"
  }

  $null = Write-MIRAssuranceRunningEvidence -Fingerprint $fingerprint -Context $Context
  $started = Get-Date
  $status = "passed"
  $message = ""
  $resolvedCommand = ""
  try {
    $resolvedCommand = Invoke-MIRAssuranceCommandText -Command ([string]$Test.command) -Context $Context -Plan $Plan | Select-Object -Last 1
  } catch {
    $status = "failed"
    $message = $_.Exception.Message
  }
  $completed = Get-Date
  $duration = [Math]::Round(($completed - $started).TotalSeconds, 3)
  $assertions = @()
  if ($Test.scenario) { $assertions = @($Test.scenario.assertions | ForEach-Object { [string]$_.id }) }
  $capsule = [ordered]@{
    schema=$evidenceSchema
    test_id=$id
    status=$status
    conclusion=$status
    disposition="RUN"
    input_key=[string]$fingerprint.input_key
    fingerprint_sha256=[string]$fingerprint.fingerprint_sha256
    definition_sha256=[string]$fingerprint.definition_sha256
    target=[string]$Context.target
    layer=[string]$Test.layer
    command=[string]$Test.command
    resolved_command=$resolvedCommand
    inputs=$fingerprint.inputs
    producer=(Get-MIRAssuranceProducer)
    assertions=$assertions
    log_digest=(Get-MIRAssuranceTextHash -Text $message)
    started_at=$started.ToUniversalTime().ToString("o")
    completed_at=$completed.ToUniversalTime().ToString("o")
    duration_seconds=$duration
    message=$message
  }
  $capsule = Write-MIRAssuranceAttempt -Capsule $capsule
  if ($status -ne "passed") { throw "Assurance test failed: $id - $message" }
  return $capsule
}

function Invoke-MIRAssurancePlan {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Context)
  $results = @()
  foreach ($test in @($Plan.tests)) {
    try {
      $results += Invoke-MIRAssuranceTest -Test $test -Plan $Plan -Context $Context
    } catch {
      $paths = Get-MIRAssuranceEvidencePaths -TestId ([string]$test.id) -InputKey ([string]$test.fingerprint.input_key)
      if (Test-Path -LiteralPath $paths.blocked -PathType Leaf) {
        try { $results += Get-Content -Raw -LiteralPath $paths.blocked | ConvertFrom-Json } catch {}
      }
      break
    }
  }
  return @($results)
}

function Invoke-MIRAssuranceGate {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Context)
  $checks = @()
  $evidence = @()
  if ($Plan.domain_manifest) {
    $currentManifest = Get-MIRAssuranceDomainManifest -Context $Context -RequireCandidate
    if ([string]$currentManifest.manifest_sha256 -ne [string]$Plan.domain_manifest.manifest_sha256) {
      throw "Candidate domain manifest changed after the verification plan was created."
    }
  }
  foreach ($test in @($Plan.tests)) {
    $fingerprint = $test.fingerprint
    $capsule = Get-MIRAssuranceReusableEvidence -Fingerprint $fingerprint -Context $Context
    $passed = $null -ne $capsule
    if ($passed -and -not [bool]$Plan.reuse_enabled) {
      $planTime = ConvertTo-MIRAssuranceDateTimeOffset -Value $Plan.generated_at
      $evidenceTime = ConvertTo-MIRAssuranceDateTimeOffset -Value $capsule.completed_at
      $sameRun = -not $env:GITHUB_RUN_ID -or [string]$capsule.producer.run_id -eq [string]$env:GITHUB_RUN_ID
      if ($evidenceTime -lt $planTime -or -not $sameRun) { $passed = $false }
    }
    $checks += [ordered]@{
      test_id=[string]$test.id
      fingerprint=[string]$fingerprint.fingerprint_sha256
      status=if ($passed) { "passed" } else { "missing-or-invalid" }
    }
    if ($passed) { $evidence += $capsule }
  }
  $failed = @($checks | Where-Object status -ne "passed")
  $bundle = [ordered]@{
    schema=1
    policy_id=[string]$Plan.policy_id
    status=if ($failed.Count -eq 0) { "passed" } else { "failed" }
    target=[string]$Plan.target
    plan_generated_at=[string]$Plan.generated_at
    plan_sha256=(Get-MIRAssuranceJsonHash -Value $Plan)
    candidate=[string]$Plan.candidate
    domain_manifest=$Plan.domain_manifest
    checks=$checks
    evidence=$evidence
    completed_at=(Get-Date).ToUniversalTime().ToString("o")
  }
  $bundlePath = "artifacts/assurance/evidence-bundle.json"
  Write-MIRAssuranceJsonFile -Value $bundle -Path $bundlePath | Out-Null
  $requestedOutput = Get-MIRAssuranceOption -Name "--output"
  if ($requestedOutput -and (Resolve-MIRAssurancePath -Path $requestedOutput) -ne (Resolve-MIRAssurancePath -Path $bundlePath)) {
    Write-MIRAssuranceJsonFile -Value $bundle -Path $requestedOutput | Out-Null
  }
  if (Test-MIRAssuranceSwitch -Name "--json") {
    $bundle | ConvertTo-Json -Depth 40 | Write-Output
  }
  if ($failed.Count -gt 0) {
    throw "MIR verification gate is missing trusted exact evidence for $($failed.Count) test(s): $(@($failed.test_id) -join ', ')"
  }
  return $bundle
}

function Get-MIRAssuranceBuildFingerprint {
  param([Parameter(Mandatory)]$Context)
  $packageFiles = @(Get-MIRAssurancePackageFiles)
  $material = [ordered]@{
    schema=$buildReceiptSchema
    target=[string]$Context.target
    package_source_sha256=(Get-MIRAssuranceTreeHash -Paths $packageFiles)
    build_script_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo "scripts\Build-MIRPackage.ps1"))
    package_identity_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo "scripts\validation\PackageIdentity.ps1"))
    info_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo "info.json"))
  }
  return [ordered]@{ material=$material; input_key=(Get-MIRAssuranceJsonHash -Value $material) }
}

function Test-MIRAssuranceBuildReceipt {
  param([Parameter(Mandatory)]$Fingerprint, [Parameter(Mandatory)]$Context)
  $path = Join-Path $buildRoot "$($Fingerprint.input_key).json"
  if (-not $Context.reuse_enabled -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or -not (Test-Path -LiteralPath $Context.candidate -PathType Leaf)) { return $null }
  try { $receipt = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json }
  catch { return $null }
  if ([int]$receipt.schema -ne $buildReceiptSchema) { return $null }
  if ([string]$receipt.input_key -ne [string]$Fingerprint.input_key) { return $null }
  if ([string]$receipt.candidate_sha256 -ne (Get-MIRAssuranceSha256 -Path $Context.candidate)) { return $null }
  if ([string]$receipt.candidate_content_sha256 -ne (Get-MIRAssuranceZipContentHash -Path $Context.candidate)) { return $null }
  $result = ConvertTo-MIRAssuranceOrderedMap -Object $receipt
  $result.disposition = "reused"
  $result.receipt = Get-MIRAssuranceRepoRelativePath -Path $path
  return $result
}

function Invoke-MIRAssuranceBuild {
  param([Parameter(Mandatory)]$Context)
  New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
  $fingerprint = Get-MIRAssuranceBuildFingerprint -Context $Context
  $reused = Test-MIRAssuranceBuildReceipt -Fingerprint $fingerprint -Context $Context
  if ($null -ne $reused) {
    Write-Host "[reuse] candidate build $($fingerprint.input_key)"
    return $reused
  }
  Write-Host "[run] candidate build $($fingerprint.input_key)"
  & (Join-Path $repo "scripts\Build-MIRPackage.ps1") | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "Candidate build failed." }
  if (-not (Test-Path -LiteralPath $Context.candidate -PathType Leaf)) { throw "Candidate was not created: $($Context.candidate)" }
  $receipt = [ordered]@{
    schema=$buildReceiptSchema
    status="passed"
    disposition="executed"
    input_key=[string]$fingerprint.input_key
    target=[string]$Context.target
    candidate=$Context.candidate
    candidate_sha256=(Get-MIRAssuranceSha256 -Path $Context.candidate)
    candidate_content_sha256=(Get-MIRAssuranceZipContentHash -Path $Context.candidate)
    package_source_sha256=[string]$fingerprint.material.package_source_sha256
    size_bytes=(Get-Item -LiteralPath $Context.candidate).Length
    completed_at=(Get-Date).ToUniversalTime().ToString("o")
  }
  $path = Join-Path $buildRoot "$($fingerprint.input_key).json"
  [IO.File]::WriteAllText($path, (($receipt | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
  $receipt["receipt"] = Get-MIRAssuranceRepoRelativePath -Path $path
  return $receipt
}

function Get-MIRAssuranceResultCounts {
  param([Parameter(Mandatory)][AllowEmptyCollection()]$Results)
  return [ordered]@{
    total=@($Results).Count
    executed=@($Results | Where-Object { [string]$_.disposition -eq "RUN" }).Count
    reused=@($Results | Where-Object { [string]$_.disposition -in @("REUSE", "WAIT") }).Count
    failed=@($Results | Where-Object { [string]$_.status -ne "passed" }).Count
  }
}
