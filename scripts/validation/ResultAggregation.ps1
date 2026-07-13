$script:MIRValidationResultState = $null
$script:MIRValidationSummaryPath = $null

function Get-MIRValidationTimestamp {
  return [DateTime]::UtcNow.ToString("o")
}

function Get-MIRValidationGroupResults {
  $groupNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  foreach ($group in @($script:MIRValidationResultState.required_groups)) {
    $null = $groupNames.Add([string]$group)
  }
  foreach ($scenario in @($script:MIRValidationResultState.scenarios)) {
    $null = $groupNames.Add([string]$scenario.group)
  }

  $results = @()
  foreach ($groupName in @($groupNames | Sort-Object)) {
    $scenarios = @($script:MIRValidationResultState.scenarios | Where-Object { $_.group -eq $groupName })
    $status = "incomplete"
    if ($scenarios.Count -gt 0) {
      if ($scenarios.status -contains "failed") {
        $status = "failed"
      } elseif ($scenarios.status -contains "running" -or $scenarios.status -contains "incomplete") {
        $status = "incomplete"
      } elseif (@($scenarios | Where-Object { $_.status -ne "skipped" }).Count -eq 0) {
        $status = "skipped"
      } else {
        $status = "passed"
      }
    }

    $duration = 0.0
    foreach ($scenario in $scenarios) {
      if ($null -ne $scenario.duration_seconds) {
        $duration += [double]$scenario.duration_seconds
      }
    }

    $results += [ordered]@{
      name = $groupName
      required = @($script:MIRValidationResultState.required_groups) -contains $groupName
      status = $status
      duration_seconds = [Math]::Round($duration, 3)
      scenarios = @($scenarios | ForEach-Object { $_.name })
    }
  }

  return $results
}

function Write-MIRValidationResult {
  if ($null -eq $script:MIRValidationResultState -or [string]::IsNullOrWhiteSpace($script:MIRValidationSummaryPath)) {
    return
  }

  $script:MIRValidationResultState.groups = @(Get-MIRValidationGroupResults)
  $parent = Split-Path -Parent $script:MIRValidationSummaryPath
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }

  $temporaryPath = "$($script:MIRValidationSummaryPath).tmp"
  $script:MIRValidationResultState | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $temporaryPath -Encoding UTF8
  Move-Item -LiteralPath $temporaryPath -Destination $script:MIRValidationSummaryPath -Force
}

function Initialize-MIRValidationResult {
  param(
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$FactorioVersion,
    [string[]]$RequiredGroups = @(),
    [string]$MirVersion = "",
    [string]$GitCommit = "",
    [string]$TargetProfileSha256 = "",
    [string]$RequiredGroupsSha256 = "",
    [string]$PackageSourceSha256 = "",
    [string]$ValidationPackageSha256 = "",
    [string]$ValidationPackageContentSha256 = "",
    [string]$FactorioBinaryVersion = "",
    [bool]$PackageSourceGitDirty = $false,
    [string]$ValidationHarnessSha256 = "",
    [bool]$ValidationHarnessGitDirty = $false,
    [string]$ExpectedScenariosSha256 = "",
    [string[]]$ExpectedScenarios = @()
  )

  $script:MIRValidationSummaryPath = [System.IO.Path]::GetFullPath($OutputPath)
  $script:MIRValidationResultState = [ordered]@{
    schema = 2
    run_id = [Guid]::NewGuid().ToString("D")
    mir_version = $MirVersion
    factorio_version = $FactorioVersion
    factorio_binary_version = $FactorioBinaryVersion
    git_commit = $GitCommit
    package_source_git_dirty = $PackageSourceGitDirty
    validation_harness_sha256 = $ValidationHarnessSha256
    validation_harness_git_dirty = $ValidationHarnessGitDirty
    expected_scenarios_sha256 = $ExpectedScenariosSha256
    expected_scenarios = @($ExpectedScenarios | Sort-Object -Unique)
    target_profile_sha256 = $TargetProfileSha256
    required_groups_sha256 = $RequiredGroupsSha256
    package_source_sha256 = $PackageSourceSha256
    validation_package_sha256 = $ValidationPackageSha256
    validation_package_content_sha256 = $ValidationPackageContentSha256
    status = "incomplete"
    started_at = Get-MIRValidationTimestamp
    completed_at = $null
    duration_seconds = $null
    current_scenario = $null
    required_groups = @($RequiredGroups | Sort-Object -Unique)
    groups = @()
    scenarios = [System.Collections.ArrayList]::new()
    error = $null
    assertions_executed = 0
  }
  Write-MIRValidationResult
  return $script:MIRValidationResultState
}

function Start-MIRValidationScenario {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Kind,
    [Parameter(Mandatory)][string]$Group,
    [string[]]$EvidencePaths = @()
  )

  if ($null -eq $script:MIRValidationResultState) {
    throw "Validation result aggregation has not been initialized."
  }

  $record = [ordered]@{
    id = [Guid]::NewGuid().ToString("D")
    name = $Name
    kind = $Kind
    group = $Group
    status = "running"
    started_at = Get-MIRValidationTimestamp
    completed_at = $null
    duration_seconds = $null
    evidence_paths = @($EvidencePaths)
    error = $null
  }
  $null = $script:MIRValidationResultState.scenarios.Add($record)
  $script:MIRValidationResultState.current_scenario = $record.id
  Write-MIRValidationResult
  return $record
}

function Complete-MIRValidationScenario {
  param(
    [Parameter(Mandatory)]$Record,
    [ValidateSet("passed", "failed", "skipped", "incomplete")]
    [string]$Status = "passed",
    [string]$ErrorMessage = "",
    [int]$AssertionsExecuted = 0
  )

  $completedAt = [DateTime]::UtcNow
  $startedAt = [DateTime]::Parse([string]$Record.started_at).ToUniversalTime()
  $Record.status = $Status
  $Record.completed_at = $completedAt.ToString("o")
  $Record.duration_seconds = [Math]::Round(($completedAt - $startedAt).TotalSeconds, 3)
  $Record.error = if ([string]::IsNullOrWhiteSpace($ErrorMessage)) { $null } else { $ErrorMessage }
  $Record.assertions_executed = $AssertionsExecuted
  if ($Status -eq "failed" -and -not [string]::IsNullOrWhiteSpace($script:MIRValidationSummaryPath)) {
    $packetRoot = Join-Path (Split-Path -Parent $script:MIRValidationSummaryPath) "failure-packets"
    New-Item -ItemType Directory -Force -Path $packetRoot | Out-Null
    $safeName = ([string]$Record.name) -replace '[^a-zA-Z0-9._-]', '-'
    $packetPath = Join-Path $packetRoot "$safeName.json"
    [ordered]@{
      schema = 1
      run_id = $script:MIRValidationResultState.run_id
      scenario = $Record.name
      kind = $Record.kind
      group = $Record.group
      error = $Record.error
      started_at = $Record.started_at
      completed_at = $Record.completed_at
      duration_seconds = $Record.duration_seconds
      assertions_executed = $Record.assertions_executed
      evidence_paths = @($Record.evidence_paths)
      package_sha256 = $script:MIRValidationResultState.validation_package_sha256
      source_commit = $script:MIRValidationResultState.git_commit
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $packetPath -Encoding UTF8
    $Record.evidence_paths = @($Record.evidence_paths) + @($packetPath)
  }
  if ($script:MIRValidationResultState.current_scenario -eq $Record.id) {
    $script:MIRValidationResultState.current_scenario = $null
  }
  Write-MIRValidationResult
}

function Add-MIRValidationCompletedScenario {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Group,
    [string]$Kind = "gate",
    [string[]]$EvidencePaths = @()
  )

  $record = Start-MIRValidationScenario -Name $Name -Kind $Kind -Group $Group -EvidencePaths $EvidencePaths
  Complete-MIRValidationScenario -Record $record -Status "passed" -AssertionsExecuted 1
}

function Fail-MIRValidationRun {
  param([Parameter(Mandatory)][string]$ErrorMessage)

  if ($null -eq $script:MIRValidationResultState) {
    return
  }
  $completedAt = [DateTime]::UtcNow
  $startedAt = [DateTime]::Parse([string]$script:MIRValidationResultState.started_at).ToUniversalTime()
  $script:MIRValidationResultState.status = "failed"
  $script:MIRValidationResultState.error = $ErrorMessage
  $script:MIRValidationResultState.completed_at = $completedAt.ToString("o")
  $script:MIRValidationResultState.duration_seconds = [Math]::Round(($completedAt - $startedAt).TotalSeconds, 3)
  Write-MIRValidationResult
}

function Complete-MIRValidationRun {
  if ($null -eq $script:MIRValidationResultState) {
    throw "Validation result aggregation has not been initialized."
  }

  $script:MIRValidationResultState.groups = @(Get-MIRValidationGroupResults)
  $expected = @($script:MIRValidationResultState.expected_scenarios)
  if ($expected.Count -gt 0) {
    $actual = @($script:MIRValidationResultState.scenarios | ForEach-Object { [string]$_.name })
    $duplicates = @($actual | Group-Object | Where-Object Count -ne 1 | ForEach-Object Name)
    $difference = @(Compare-Object -ReferenceObject @($expected | Sort-Object) -DifferenceObject @($actual | Sort-Object))
    $nonPassed = @($script:MIRValidationResultState.scenarios | Where-Object status -ne "passed" | ForEach-Object name)
    $zeroAssertions = @($script:MIRValidationResultState.scenarios | Where-Object { $_.kind -ne "gate" -and $_.assertions_executed -le 0 } | ForEach-Object name)
    if ($duplicates.Count -gt 0 -or $difference.Count -gt 0 -or $nonPassed.Count -gt 0 -or $zeroAssertions.Count -gt 0) {
      $message = "Validation scenario completeness failed."
      if ($duplicates.Count -gt 0) { $message += " Duplicate scenarios: $($duplicates -join ',')." }
      if ($difference.Count -gt 0) { $message += " Manifest/result difference: $($difference.InputObject -join ',')." }
      if ($nonPassed.Count -gt 0) { $message += " Required scenarios not passed: $($nonPassed -join ',')." }
      if ($zeroAssertions.Count -gt 0) { $message += " Scenarios executed zero assertions: $($zeroAssertions -join ',')." }
      Fail-MIRValidationRun -ErrorMessage $message
      throw $message
    }
  }
  $unmet = @(
    $script:MIRValidationResultState.groups |
      Where-Object { $_.required -and $_.status -ne "passed" }
  )
  if ($unmet.Count -gt 0) {
    $message = "Required validation groups did not pass: " + (($unmet | ForEach-Object { "$($_.name)=$($_.status)" }) -join ", ")
    Fail-MIRValidationRun -ErrorMessage $message
    throw $message
  }

  $completedAt = [DateTime]::UtcNow
  $startedAt = [DateTime]::Parse([string]$script:MIRValidationResultState.started_at).ToUniversalTime()
  $script:MIRValidationResultState.status = "passed"
  $script:MIRValidationResultState.completed_at = $completedAt.ToString("o")
  $script:MIRValidationResultState.duration_seconds = [Math]::Round(($completedAt - $startedAt).TotalSeconds, 3)
  $script:MIRValidationResultState.current_scenario = $null
  $script:MIRValidationResultState.error = $null
  Write-MIRValidationResult
  Write-Host "[ok] Structured validation summary: $script:MIRValidationSummaryPath"
}
