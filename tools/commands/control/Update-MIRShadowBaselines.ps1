param(
  [string]$C24Plan = "artifacts/assurance/plans/verification-plan-c24-full-no-reuse.json",
  [string]$P9Plan = "",
  [switch]$Check,
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Views")) {
  . (Join-Path $repo "tools/lib/control/$module.ps1")
}

function New-MIRV4CompactBaseline {
  param(
    [Parameter(Mandatory)][string]$PlanPath,
    [Parameter(Mandatory)][string]$Release,
    [Parameter(Mandatory)][string]$CandidateId,
    [Parameter(Mandatory)][string]$SourceLabel
  )
  $resolved = (Resolve-Path -LiteralPath $PlanPath).Path
  $plan = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json
  $releaseRecord = Get-MIRCPReleaseByVersion -Release $Release -RepoRoot $repo
  if ([string]$plan.target -ne [string]$releaseRecord.target -or
      [string]$plan.candidate_descriptor.sha256 -ne [string]$releaseRecord.package.archive_sha256 -or
      [string]$plan.candidate_descriptor.content_sha256 -ne [string]$releaseRecord.package.content_sha256 -or
      [int64]$plan.candidate_descriptor.bytes -ne [int64]$releaseRecord.package.bytes) {
    throw "v4 plan $PlanPath is not bound to the governed $Release candidate."
  }
  $scenarioTests = @($plan.tests | Where-Object kind -eq "factorio-scenario" | Sort-Object id)
  $obligations = @($plan.tests | Where-Object kind -ne "factorio-scenario" | Sort-Object id | ForEach-Object {
    [pscustomobject][ordered]@{id=[string]$_.id;kind=[string]$_.kind;requires_factorio=[bool]$_.requires_factorio}
  })
  $environments = @($scenarioTests | ForEach-Object {
    [pscustomobject][ordered]@{
      test_id = [string]$_.id
      definition_sha256 = [string]$_.fingerprint.definition_sha256
      input_key = [string]$_.fingerprint.input_key
      scenario_sha256 = [string]$_.fingerprint.definition.scenario_sha256
      requires_factorio = [bool]$_.requires_factorio
    }
  })
  $body = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-control-plane-v5-compact-v4-plan-baseline"
    release = $Release
    candidate_id = $CandidateId
    target = [string]$plan.target
    source_plan = [pscustomobject][ordered]@{label=$SourceLabel;sha256=(Get-MIRCPSha256File -Path $resolved)}
    candidate = [pscustomobject][ordered]@{
      archive_sha256 = [string]$plan.candidate_descriptor.sha256
      content_sha256 = [string]$plan.candidate_descriptor.content_sha256
      bytes = [int64]$plan.candidate_descriptor.bytes
      entries = [int]$releaseRecord.package.entries
      qualification_source_commit = [string]$plan.source_commit
      plan_package_source_commit = [string]$plan.package_source_commit
      governed_package_source_commit = [string]$releaseRecord.package.source_commit
    }
    plan = [pscustomobject][ordered]@{
      policy_id = [string]$plan.policy_id
      plan_material_sha256 = [string]$plan.plan_material_sha256
      required_test_set_sha256 = [string]$plan.required_test_set_sha256
      test_catalog_sha256 = [string]$plan.test_catalog_sha256
      validation_harness_sha256 = [string]$plan.validation_harness_sha256
      verification_profile_sha256 = [string]$plan.verification_profile_sha256
      rows = @($plan.tests).Count
      run_rows = @($plan.tests | Where-Object disposition -eq "RUN").Count
    }
    obligations = $obligations
    scenarios = @($scenarioTests.id | ForEach-Object { [string]$_ })
    environments = $environments
    measurements = [pscustomobject][ordered]@{
      scenario_rows = $scenarioTests.Count
      non_scenario_rows = $obligations.Count
      factorio_required_rows = @($plan.tests | Where-Object requires_factorio).Count
      projected_factorio_processes = if ($Release -eq "3.2.2") { 129 } else { $null }
      duration_sum_seconds = if ($Release -eq "3.2.2") { 5177.621 } else { $null }
    }
  }
  $record = [ordered]@{}
  foreach ($property in $body.PSObject.Properties) { $record[$property.Name] = $property.Value }
  $record.baseline_sha256 = Get-MIRCPSha256Object -Value $body
  return [pscustomobject]$record
}

$c24 = New-MIRV4CompactBaseline -PlanPath $C24Plan -Release "3.2.2" -CandidateId "C24" `
  -SourceLabel "artifacts/assurance/plans/verification-plan-c24-full-no-reuse.json"
Write-MIRCPJson -Path "validation/baselines/control/3.2.2-v4.json" -Value $c24 -RepoRoot $repo -Check:$Check

if (-not [string]::IsNullOrWhiteSpace($P9Plan)) {
  $p9 = New-MIRV4CompactBaseline -PlanPath $P9Plan -Release "2.5.0" -CandidateId "2.5-P9" `
    -SourceLabel "artifacts/assurance/plans/verification-plan-2.5-p9-full-no-reuse.json"
  Write-MIRCPJson -Path "validation/baselines/control/2.5.0-p9-v4.json" -Value $p9 -RepoRoot $repo -Check:$Check
}

[pscustomobject][ordered]@{status=if($Check){"current"}else{"updated"};c24_sha256=[string]$c24.baseline_sha256;p9_written=(-not [string]::IsNullOrWhiteSpace($P9Plan))} | ConvertTo-Json
