param(
  [Parameter(Mandatory)][string]$CatalogPath,
  [Parameter(Mandatory)][string]$CandidateId,
  [Parameter(Mandatory)][string]$ProfilePath,
  [string]$MetricsPath,
  [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Get-MIRJsonSha256 {
  param($Value)
  $json = $Value | ConvertTo-Json -Depth 100 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $hash = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return ([BitConverter]::ToString($hash)).Replace("-", "")
}

function Get-MIRProperty {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

$catalog = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $CatalogPath) | ConvertFrom-Json
if ([int]$catalog.schema -ne 2 -or [bool]$catalog.mutation_authority) { throw "TechnologyCatalog schema 2 shadow artifact is required." }
$candidate = @($catalog.candidates | Where-Object { [string]$_.candidate_id -eq $CandidateId })
if ($candidate.Count -ne 1) { throw "Technology candidate must resolve exactly once: $CandidateId" }
$selection = @($catalog.current_selections | Where-Object { [string]$_.candidate_id -eq $CandidateId })
if ($selection.Count -ne 1) { throw "Technology candidate must have exactly one current selection: $CandidateId" }

$profileAuthority = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $ProfilePath) | ConvertFrom-Json
if ([int]$profileAuthority.schema -ne 1) { throw "Technology quality profile schema is invalid." }
$profile = @($profileAuthority.profiles)[0]
if ($null -eq $profile -or [string]::IsNullOrWhiteSpace([string]$profile.profile_id)) { throw "Technology quality profile is required." }
$metrics = if ($MetricsPath) { Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $MetricsPath) | ConvertFrom-Json } else { $null }
$numberFields = @(
  "member_count", "semantic_cluster_count", "earliest_unlock_depth", "latest_unlock_depth",
  "progression_span", "science_tier_span", "accepting_lab_count", "owner_conflict_count",
  "effect_per_level", "cost_l1", "cost_l5", "cost_l10", "cost_l20", "useful_levels_before_cap",
  "true_positive_count", "false_positive_count", "false_negative_count", "cross_version_add_count",
  "cross_version_remove_count", "provider_phase_time"
)
$values = [ordered]@{}
$missing = @()
foreach ($field in $numberFields) {
  $property = if ($metrics) { $metrics.PSObject.Properties[$field] } else { $null }
  if ($null -eq $property) { $values[$field] = 0; $missing += $field }
  else {
    $value = [double]$property.Value
    if ($value -lt 0) { throw "Technology quality metric cannot be negative: $field" }
    $values[$field] = $value
  }
}
$reasons = @()
$status = "PASS"
if ($missing.Count -gt 0) { $status = "UNMEASURED"; $reasons += "missing-metrics:" + ($missing -join ",") }
if ($missing.Count -eq 0) {
  if ($values.owner_conflict_count -gt [double]$profile.maximum_owner_conflicts) { $status = "FAIL"; $reasons += "owner-conflicts" }
  if ($values.false_positive_count -gt [double]$profile.maximum_false_positives) { $status = "FAIL"; $reasons += "false-positives" }
  if ($values.false_negative_count -gt [double]$profile.maximum_false_negatives) { $status = "FAIL"; $reasons += "false-negatives" }
  if ($values.accepting_lab_count -lt [double]$profile.minimum_accepting_labs) { $status = "REVIEW_REQUIRED"; $reasons += "no-accepting-lab" }
  if ($values.useful_levels_before_cap -lt [double]$profile.minimum_useful_levels_before_cap) { $status = "REVIEW_REQUIRED"; $reasons += "short-useful-progression" }
  if ($values.science_tier_span -gt [double]$profile.maximum_science_tier_span) { $status = "REVIEW_REQUIRED"; $reasons += "wide-science-tier-span" }
  if ($values.cross_version_add_count -gt [double]$profile.maximum_cross_version_additions) { $status = "REVIEW_REQUIRED"; $reasons += "cross-version-expansion" }
  if ($values.cross_version_remove_count -gt [double]$profile.maximum_cross_version_removals) { $status = "FAIL"; $reasons += "cross-version-removal" }
  if ($values.provider_phase_time -gt [double]$profile.maximum_provider_phase_seconds) { $status = "REVIEW_REQUIRED"; $reasons += "provider-budget" }
}

$evidence = @()
if ($metrics) { $evidence = @($metrics.evidence_sha256 | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique) }
$record = [ordered]@{
  schema=1; record_type="TechnologyQualityAssessment"
  candidate_id=$CandidateId
  design_fingerprint=[string]$selection[0].design_fingerprint
  qualification_fingerprint=[string]$selection[0].qualification_fingerprint
  profile_id=[string]$profile.profile_id
}
foreach ($field in $numberFields) { $record[$field] = $values[$field] }
$record.status = $status
$record.review_reasons = @($reasons | Sort-Object -Unique)
$record.evidence_sha256 = $evidence
$record.assessment_fingerprint = Get-MIRJsonSha256 $record

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$record | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "[ok] wrote TechnologyQualityAssessment $OutputPath status=$status"
