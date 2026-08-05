param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path,
  [string]$SummaryPath = ".work/artifacts/assurance/c32-candidate-qualification-verify-summary.json",
  [string]$OutputPath = ".mir/evidence/3.2.5-c32-candidate-qualification.json"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")
. (Join-Path $repo "tools/lib/validation/TargetProfiles.ps1")

function Resolve-MIRQualificationPath {
  param([Parameter(Mandatory)][string]$Path)
  if ([IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $repo $Path
}

function ConvertTo-MIRQualificationTimestampText {
  param([Parameter(Mandatory)]$Value)
  return ([DateTimeOffset]$Value).ToUniversalTime().ToString("o", [Globalization.CultureInfo]::InvariantCulture)
}

$summaryFile = Resolve-MIRQualificationPath -Path $SummaryPath
if (-not (Test-Path -LiteralPath $summaryFile -PathType Leaf)) {
  throw "Candidate qualification summary is absent: $SummaryPath"
}
$summary = Get-Content -Raw -LiteralPath $summaryFile | ConvertFrom-Json
$plan = $summary.plan
$rows = @($summary.evidence)
if ([int]$summary.schema -ne 2 -or [string]$summary.status -ne "passed" -or [int]$plan.schema -ne 4 -or
    [string]$plan.profile -ne "development-breadth" -or -not [bool]$plan.requires_factorio -or [bool]$plan.reuse_enabled -or
    [int]$summary.counts.expected -ne 135 -or [int]$summary.counts.total -ne 135 -or
    [int]$summary.counts.executed -ne 135 -or [int]$summary.counts.reused -ne 0 -or
    [int]$summary.counts.failed -ne 0 -or [int]$summary.counts.incomplete -ne 0 -or
    [int]$summary.counts.unexpected -ne 0 -or [int]$plan.counts.run -ne 135 -or
    [int]$plan.counts.reuse -ne 0 -or [int]$plan.counts.wait -ne 0 -or [int]$plan.counts.invalid -ne 0) {
  throw "Candidate qualification summary is not an exact fresh 135-row passing development-breadth run."
}
$expectedIds = @($plan.expected_test_ids | ForEach-Object { [string]$_ })
$rowIds = @($rows | ForEach-Object { [string]$_.test_id })
if ($rows.Count -ne 135 -or @($rowIds | Sort-Object -Unique).Count -ne 135 -or
    @(Compare-Object ($expectedIds | Sort-Object) ($rowIds | Sort-Object)).Count -ne 0 -or
    @($rows | Where-Object {
      [string]$_.status -ne "passed" -or [string]$_.conclusion -ne "passed" -or
      [string]$_.disposition -ne "RUN" -or [string]$_.fingerprint_sha256 -notmatch '^[A-F0-9]{64}$' -or
      [string]$_.result_digest -notmatch '^[A-F0-9]{64}$'
    }).Count -ne 0) {
  throw "Candidate qualification row set is incomplete, duplicated, reused, or non-passing."
}
$producerIds = @($rows | ForEach-Object { [string]$_.producer.run_id } | Sort-Object -Unique)
if ($producerIds.Count -ne 1 -or [string]::IsNullOrWhiteSpace($producerIds[0])) {
  throw "Candidate qualification rows do not share one explicit run identity."
}
$head = (git -C $repo rev-parse HEAD).Trim()
$tree = (git -C $repo rev-parse 'HEAD^{tree}').Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne [string]$plan.source_commit -or $tree -ne [string]$plan.source_tree -or
    (Test-MIRPackageSourceGitDirty -RepoRoot $repo) -or (Test-MIRValidationHarnessGitDirty -RepoRoot $repo)) {
  throw "Candidate qualification projection requires its exact clean committed source and validation harness."
}
$info = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json
$profile = Get-MIRTargetProfile -RepoRoot $repo -FactorioVersion ([string]$info.factorio_version)
$requiredGroups = @($profile.required_validation_groups | ForEach-Object { [string]$_ } | Sort-Object -Unique)
$factorio = @($plan.tests | Where-Object requires_factorio | Select-Object -First 1)[0].fingerprint.inputs.factorio
$candidate = $plan.candidate_descriptor
$compactRows = @($rows | Sort-Object test_id | ForEach-Object {
  [pscustomobject][ordered]@{
    test_id = [string]$_.test_id
    status = [string]$_.status
    disposition = [string]$_.disposition
    fingerprint_sha256 = [string]$_.fingerprint_sha256
    result_digest = [string]$_.result_digest
    completed_at = ConvertTo-MIRQualificationTimestampText -Value $_.completed_at
  }
})
$evidence = [pscustomobject][ordered]@{
  schema = 2
  kind = "mir-assurance-candidate-qualification"
  status = "passed"
  run_id = $producerIds[0]
  mir_version = [string]$info.version
  factorio_version = [string]$info.factorio_version
  git_commit = [string]$plan.source_commit
  git_tree = [string]$plan.source_tree
  package_source_commit = [string]$plan.package_source_commit
  target_profile_sha256 = Get-MIRTargetProfileFingerprint -Profile $profile
  required_groups_sha256 = Get-MIRRequiredGroupsFingerprint -RequiredGroups $requiredGroups
  package_source_sha256 = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  validation_package_sha256 = [string]$candidate.sha256
  validation_package_content_sha256 = [string]$candidate.content_sha256
  validation_harness_sha256 = [string]$plan.validation_harness_sha256
  expected_scenarios_sha256 = Get-MIRFileContentSha256 `
    -Path (Join-Path $repo "validation/scenarios/runtime.json") `
    -RelativePath "validation/scenarios/runtime.json"
  package_source_git_dirty = $false
  validation_harness_git_dirty = $false
  required_groups = $requiredGroups
  groups = @($requiredGroups | ForEach-Object {
    [pscustomobject][ordered]@{name=$_;required=$true;status="passed"}
  })
  candidate = [pscustomobject][ordered]@{
    archive = [string]$candidate.path
    archive_sha256 = [string]$candidate.sha256
    content_sha256 = [string]$candidate.content_sha256
    bytes = [int64]$candidate.bytes
  }
  environment = [pscustomobject][ordered]@{
    factorio_binary = [pscustomobject][ordered]@{
      name = [string]$factorio.binary.name
      bytes = [int64]$factorio.binary.size_bytes
      sha256 = [string]$factorio.binary.sha256
    }
    official_data = [pscustomobject][ordered]@{
      files = [int]$factorio.official_data.file_count
      sha256 = [string]$factorio.official_data.sha256
    }
    installation_sha256 = [string]$factorio.sha256
  }
  qualification = [pscustomobject][ordered]@{
    profile = [string]$plan.profile
    plan_material_sha256 = [string]$plan.plan_material_sha256
    required_test_set_sha256 = [string]$plan.required_test_set_sha256
    test_catalog_sha256 = [string]$plan.test_catalog_sha256
    verification_profile_sha256 = [string]$plan.verification_profile_sha256
    domain_policy_sha256 = [string]$plan.domain_policy_sha256
    trust_policy_sha256 = [string]$plan.trust_policy_sha256
    expected = [int]$summary.counts.expected
    executed = [int]$summary.counts.executed
    reused = [int]$summary.counts.reused
    failed = [int]$summary.counts.failed
    incomplete = [int]$summary.counts.incomplete
    unexpected = [int]$summary.counts.unexpected
    completed_at = ConvertTo-MIRQualificationTimestampText -Value $summary.completed_at
    source_summary_bytes = (Get-Item -LiteralPath $summaryFile).Length
    source_summary_sha256 = Get-MIRFileSha256 -Path $summaryFile
    expected_test_ids = $expectedIds
    rows = $compactRows
  }
}
$outputFile = Resolve-MIRQualificationPath -Path $OutputPath
$parent = Split-Path -Parent $outputFile
if ($parent) { [void](New-Item -ItemType Directory -Force -Path $parent) }
[IO.File]::WriteAllText($outputFile, ($evidence | ConvertTo-Json -Depth 20) + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "[ok] C32 candidate qualification evidence: $outputFile"
