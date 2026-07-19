param(
  [string]$Path = "approved-delta\3.1.9-to-3.2.0.json",
  [string]$Candidate = "dist\more-infinite-research_3.2.0.zip",
  [string]$ExpectedSourceCommit = "",
  [switch]$ValidateStructureOnly
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
$artifactPath = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
  throw "Approved-delta artifact is absent: $artifactPath"
}
$artifact = Get-Content -Raw -LiteralPath $artifactPath | ConvertFrom-Json
if ($artifact.schema -ne 1 -or $artifact.kind -ne "mir-approved-delta") {
  throw "Approved-delta artifact must use schema 1 and kind mir-approved-delta."
}
$expectedBaseline = "D77B3A78DA40CD4FDD4C829A01B5030E59FB593F3387124EF5C438F6A9E8DFCD"
if ($artifact.baseline.version -ne "3.1.9" -or $artifact.baseline.archive_sha256 -ne $expectedBaseline) {
  throw "Approved-delta baseline does not bind the sealed 3.1.9 archive."
}
if ($artifact.current.version -ne "3.2.0" -or [string]::IsNullOrWhiteSpace([string]$artifact.current.archive_sha256)) {
  throw "Approved-delta current side does not bind an exact 3.2.0 archive."
}
if (-not $ValidateStructureOnly) {
  $candidatePath = if ([IO.Path]::IsPathRooted($Candidate)) { $Candidate } else { Join-Path $repo $Candidate }
  if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
    throw "Approved-delta candidate is absent: $candidatePath"
  }
  if ([string]::IsNullOrWhiteSpace($ExpectedSourceCommit)) {
    throw "Approved-delta exact-candidate validation requires -ExpectedSourceCommit."
  }
  $currentCommit = (Get-MIRGitCommit -RepoRoot $repo)
  if ($currentCommit -ne $ExpectedSourceCommit -or (Test-MIRPackageSourceGitDirty -RepoRoot $repo)) {
    throw "Approved-delta exact-candidate validation requires the clean package source at ExpectedSourceCommit."
  }
  $candidateSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidatePath).Hash
  $candidateContentSha = Get-MIRZipContentFingerprint -Path $candidatePath
  if ($candidateContentSha -ne (Get-MIRPackageSourceFingerprint -RepoRoot $repo)) {
    throw "Approved-delta candidate content does not match the package source authority at ExpectedSourceCommit."
  }
  if ([string]$artifact.current.archive_sha256 -ne $candidateSha -or
      [string]$artifact.current.package_content_sha256 -ne $candidateContentSha -or
      [string]$artifact.current.source_commit -ne $ExpectedSourceCommit) {
    throw "Approved-delta current side does not bind the exact candidate, package content, and source authority."
  }
}
if ([string]::IsNullOrWhiteSpace([string]$artifact.exporter.producer_sha256)) {
  throw "Approved-delta exporter does not bind its exact producer fingerprint."
}

$expectedScenarios = @(
  "approved-delta-automatic-family-controls",
  "approved-delta-base",
  "approved-delta-base-continuations",
  "approved-delta-compat-atan",
  "approved-delta-compat-space-age-galore",
  "approved-delta-native-owner-adoption",
  "approved-delta-space-age"
)
$actualScenarios = @($artifact.scenario_evidence.scenario | Sort-Object -Unique)
if (($actualScenarios -join "`n") -ne (($expectedScenarios | Sort-Object) -join "`n")) {
  throw "Approved-delta scenario coverage differs from the governed seven-scenario matrix."
}
foreach ($scenario in @($artifact.scenario_evidence)) {
  if ([string]::IsNullOrWhiteSpace([string]$scenario.baseline_fingerprint) -or
    [string]::IsNullOrWhiteSpace([string]$scenario.current_fingerprint)) {
    throw "Approved-delta scenario lacks normalized fingerprints: $($scenario.scenario)"
  }
  if ($scenario.baseline_technology_count -ne $scenario.current_technology_count -or
    $scenario.technology_difference_count -ne 0) {
    throw "Approved-delta scenario changes normalized technology output: $($scenario.scenario)"
  }
}

$differences = @($artifact.differences)
foreach ($difference in $differences) {
  $propertyNames = @($difference.PSObject.Properties.Name)
  foreach ($required in @("field", "before", "after", "reason", "intentional", "migration_impact", "required_evidence")) {
    if ($propertyNames -notcontains $required) { throw "Approved-delta row lacks ${required}: $($difference.field)" }
  }
  if ([string]::IsNullOrWhiteSpace([string]$difference.field) -or
    [string]::IsNullOrWhiteSpace([string]$difference.reason) -or
    [string]::IsNullOrWhiteSpace([string]$difference.migration_impact) -or
    $difference.intentional -isnot [bool] -or
    @($difference.required_evidence).Count -eq 0) {
    throw "Approved-delta row has incomplete disposition evidence: $($difference.field)"
  }
}
$unapproved = @($differences | Where-Object intentional -ne $true)
if ($unapproved.Count -ne 0 -or $artifact.summary.unapproved_count -ne 0 -or $artifact.summary.status -ne "approved") {
  throw "Approved-delta contains review-required differences."
}
if ($artifact.summary.difference_count -ne $differences.Count -or
  $artifact.summary.intentional_count -ne $differences.Count) {
  throw "Approved-delta summary counts differ from its rows."
}

$forbiddenBehaviorPaths = @($differences | Where-Object {
  $_.field -match '\.(technologies|technology_ids|generated_registry|settings)\.' -or
  $_.field -match '^package\.(runtime_namespaces|migrations)'
})
if ($forbiddenBehaviorPaths.Count -gt 0) {
  throw "Approved-delta contains unaccepted technology, registry, setting, runtime namespace, or migration changes."
}
foreach ($scenario in $expectedScenarios) {
  $prefix = "scenarios.$scenario.mod_data_contracts."
  if (-not @($differences.field | Where-Object { $_ -like "$prefix*compiler-evidence*" })) {
    throw "Approved-delta scenario lacks the CompilerEvidence schema transition: $scenario"
  }
  if (-not @($differences.field | Where-Object { $_ -like "$prefix*generation-plan*" })) {
    throw "Approved-delta scenario lacks the GenerationPlan authority transition: $scenario"
  }
}

$binding = if ($ValidateStructureOnly) { "governed artifact structure" } else { "the exact active candidate" }
Write-Host "[ok] MIR approved delta binds $binding, seven exact-package scenarios, $($differences.Count) intentional differences, and no technology drift."
