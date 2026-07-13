function Get-MIRAssurancePatternFingerprint {
  param([Parameter(Mandatory)][string[]]$Patterns)
  $files = @(Resolve-MIRAssurancePatternFiles -Patterns $Patterns)
  $hash = if ($files.Count -gt 0) {
    Get-MIRAssuranceTreeHash -Paths $files
  } else {
    Get-MIRAssuranceTextHash -Text ("NO_MATCH`n" + (($Patterns | Sort-Object -Unique) -join "`n"))
  }
  return [ordered]@{
    kind="repository-patterns"
    patterns=@($Patterns | Sort-Object -Unique)
    file_count=$files.Count
    sha256=$hash
  }
}

function Get-MIRAssuranceInputFingerprint {
  param(
    [Parameter(Mandatory)][string]$InputName,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context
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
    "test-catalog" { return [ordered]@{ kind="manifest"; sha256=(Get-MIRAssuranceSha256 -Path $catalogPath) } }
    "target-profile" {
      return Get-MIRAssurancePatternFingerprint -Patterns @(".mir/targets.json", "scripts/validation/TargetProfiles.ps1")
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
    "harness" {
      return Get-MIRAssurancePatternFingerprint -Patterns @("scripts/**", ".mir/test-impact.yml", ".mir/targets.json")
    }
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
      return Get-MIRAssurancePatternFingerprint -Patterns @("fixtures/**upgrade**", "scripts/Test-MIRUpgrade.ps1")
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
    kind=[string]$Test.kind
    command=[string]$Test.command
    requires_factorio=[bool]$Test.requires_factorio
    inputs=@($Test.inputs | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  }
  $definitionHash = Get-MIRAssuranceJsonHash -Value $definition
  $inputFingerprints = [ordered]@{}
  $runnerHash = Get-MIRAssuranceRunnerHash
  $inputFingerprints["assurance-runner"] = [ordered]@{ kind="runner"; version=$assuranceRunnerVersion; sha256=$runnerHash }
  foreach ($inputName in @($definition.inputs)) {
    $inputFingerprints[$inputName] = Get-MIRAssuranceInputFingerprint -InputName $inputName -Plan $Plan -Context $Context
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
  }
}

function ConvertTo-MIRAssuranceOrderedMap {
  param([Parameter(Mandatory)]$Object)
  $map = [ordered]@{}
  foreach ($property in $Object.PSObject.Properties) { $map[$property.Name] = $property.Value }
  return $map
}

function Get-MIRAssuranceReusableEvidence {
  param([Parameter(Mandatory)]$Fingerprint)
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  if (-not (Test-Path -LiteralPath $paths.passed -PathType Leaf)) { return $null }
  if (Test-Path -LiteralPath $paths.blocked -PathType Leaf) { return $null }
  try { $capsule = Get-Content -Raw -LiteralPath $paths.passed | ConvertFrom-Json }
  catch { return $null }
  if ([int]$capsule.schema -ne $evidenceSchema) { return $null }
  if ([string]$capsule.status -ne "passed") { return $null }
  if ([string]$capsule.test_id -ne [string]$Fingerprint.test_id) { return $null }
  if ([string]$capsule.target -ne [string]$Fingerprint.target) { return $null }
  if ([string]$capsule.input_key -ne [string]$Fingerprint.input_key) { return $null }
  if ([string]$capsule.fingerprint_sha256 -ne [string]$Fingerprint.fingerprint_sha256) { return $null }
  if ([string]$capsule.definition_sha256 -ne [string]$Fingerprint.definition_sha256) { return $null }
  $result = ConvertTo-MIRAssuranceOrderedMap -Object $capsule
  $result.disposition = "reused"
  $result.reused_at = (Get-Date).ToUniversalTime().ToString("o")
  $result.source_duration_seconds = [double]$capsule.duration_seconds
  $result.duration_seconds = 0
  $result.evidence_path = Get-MIRAssuranceRepoRelativePath -Path $paths.passed
  return $result
}

function Write-MIRAssuranceAttempt {
  param([Parameter(Mandatory)]$Capsule)
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

function Invoke-MIRAssurancePlan {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Context)
  New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
  $results = @()
  $runtimeFullCompleted = $false
  foreach ($test in @($Plan.tests)) {
    $id = [string]$test.id
    if ($runtimeFullCompleted -and $id -in @("runtime.affected", "runtime.exact-zip")) {
      Write-Host "[reuse] $id is subsumed by passing runtime.full evidence."
      continue
    }
    if ($test.requires_factorio -and (-not $Context.factorio -or -not (Test-Path -LiteralPath $Context.factorio -PathType Leaf))) {
      throw "Test $id requires --factorio with a matching Factorio binary."
    }
    if ($id -eq "runtime.upgrade" -and (-not $Context.prior_release -or -not (Test-Path -LiteralPath $Context.prior_release -PathType Leaf))) {
      throw "Test runtime.upgrade requires --prior with the exact prior-release archive."
    }
    if ($id -eq "runtime.affected" -and [string]::IsNullOrWhiteSpace([string]$Plan.baseline)) {
      throw "Test runtime.affected requires --baseline with a qualified comparison commit or seal."
    }
    if (@($test.inputs | Where-Object { [string]$_ -eq "candidate" }).Count -gt 0 -and -not (Test-Path -LiteralPath $Context.candidate -PathType Leaf)) {
      throw "Test $id requires the exact candidate archive: $($Context.candidate)"
    }

    $fingerprint = Get-MIRAssuranceTestFingerprint -Test $test -Plan $Plan -Context $Context
    if (Test-MIRAssuranceCanReuseTest -TestId $id -Context $Context) {
      $reused = Get-MIRAssuranceReusableEvidence -Fingerprint $fingerprint
      if ($null -ne $reused) {
        Write-Host "[reuse] $id $($fingerprint.input_key)"
        $results += $reused
        if ($id -eq "runtime.full") { $runtimeFullCompleted = $true }
        continue
      }
    }

    Write-Host "[run] $id $($fingerprint.input_key)"
    $started = Get-Date
    $status = "passed"
    $message = ""
    $resolvedCommand = ""
    try {
      $resolvedCommand = Invoke-MIRAssuranceCommandText -Command ([string]$test.command) -Context $Context -Plan $Plan | Select-Object -Last 1
    } catch {
      $status = "failed"
      $message = $_.Exception.Message
    }
    $completed = Get-Date
    $duration = [Math]::Round(($completed - $started).TotalSeconds, 3)
    $capsule = [ordered]@{
      schema=$evidenceSchema
      test_id=$id
      status=$status
      disposition="executed"
      input_key=[string]$fingerprint.input_key
      fingerprint_sha256=[string]$fingerprint.fingerprint_sha256
      definition_sha256=[string]$fingerprint.definition_sha256
      target=[string]$Context.target
      command=[string]$test.command
      resolved_command=$resolvedCommand
      inputs=$fingerprint.inputs
      started_at=$started.ToUniversalTime().ToString("o")
      completed_at=$completed.ToUniversalTime().ToString("o")
      duration_seconds=$duration
      message=$message
    }
    $capsule = Write-MIRAssuranceAttempt -Capsule $capsule
    $results += $capsule
    if ($status -eq "passed" -and $id -eq "runtime.full") { $runtimeFullCompleted = $true }
    if ($status -ne "passed") { break }
  }
  return @($results)
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
    executed=@($Results | Where-Object { [string]$_.disposition -eq "executed" }).Count
    reused=@($Results | Where-Object { [string]$_.disposition -eq "reused" }).Count
    failed=@($Results | Where-Object { [string]$_.status -ne "passed" }).Count
  }
}

