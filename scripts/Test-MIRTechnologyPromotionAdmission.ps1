param(
  [Parameter(Mandatory)][string]$CatalogPath,
  [Parameter(Mandatory)][string]$AssessmentPath,
  [Parameter(Mandatory)][string]$ApprovalPath,
  [Parameter(Mandatory)][string]$PromotionPath,
  [Parameter(Mandatory)][string]$ProfilePath,
  [string]$MigrationPath,
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
function Read-MIRJson([string]$Path) { Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $Path) | ConvertFrom-Json }

$catalog = Read-MIRJson $CatalogPath
$assessment = Read-MIRJson $AssessmentPath
$approval = Read-MIRJson $ApprovalPath
$promotion = Read-MIRJson $PromotionPath
$profiles = Read-MIRJson $ProfilePath
$migration = if ($MigrationPath) { Read-MIRJson $MigrationPath } else { $null }
$rejected = @()
$review = @()
if ([int]$catalog.schema -ne 3 -or [string]$catalog.phase -ne "final" -or [bool]$catalog.mutation_authority) { $rejected += "catalog-authority" }
$candidate = @($catalog.candidates | Where-Object { [string]$_.candidate_id -eq [string]$promotion.candidate_id })
$selection = @($catalog.current_selections | Where-Object { [string]$_.candidate_id -eq [string]$promotion.candidate_id })
if ($candidate.Count -ne 1 -or $selection.Count -ne 1) { $rejected += "candidate-selection-cardinality" }
$selected = if ($candidate.Count -eq 1 -and $selection.Count -eq 1) {
  @($candidate[0].alternatives | Where-Object { [string]$_.alternative_id -eq [string]$selection[0].alternative_id })
} else { @() }
if ($selected.Count -ne 1) { $rejected += "selected-alternative" }
if ([string]$assessment.candidate_id -ne [string]$promotion.candidate_id) { $rejected += "assessment-candidate" }
if ($selection.Count -eq 1) {
  if ([string]$assessment.design_fingerprint -ne [string]$selection[0].design_fingerprint) { $rejected += "assessment-design" }
  if ([string]$assessment.qualification_fingerprint -ne [string]$selection[0].qualification_fingerprint) { $rejected += "assessment-qualification" }
}
$profile = @($profiles.profiles | Where-Object { [string]$_.profile_id -eq [string]$assessment.profile_id })
if ([int]$profiles.schema -ne 2 -or [string]$profiles.authority -ne "mir-technology-quality-profiles-v2"
  -or $profile.Count -ne 1) { $rejected += "assessment-profile" }
if ([string]$assessment.status -ne "PASS") { $review += "assessment-not-pass:$($assessment.status)" }
if ([string]$approval.decision -ne "approved") { $rejected += "approval-decision" }
if ([string]$approval.candidate_selector.candidate_id -ne [string]$promotion.candidate_id) { $rejected += "approval-candidate" }
if ($selection.Count -eq 1) {
  if ([string]$approval.selected_alternative -ne [string]$selection[0].alternative_id) { $rejected += "approval-alternative" }
  if ([string]$approval.approved_design_fingerprint -ne [string]$selection[0].design_fingerprint) { $rejected += "approval-design" }
  if ([string]$approval.qualification_fingerprint -ne [string]$selection[0].qualification_fingerprint) { $rejected += "approval-qualification" }
}
if ([string]$promotion.approval_id -ne [string]$approval.approval_id) { $rejected += "promotion-approval" }
if ([string]$promotion.approved_design_fingerprint -ne [string]$approval.approved_design_fingerprint) { $rejected += "promotion-design" }
if (@($approval.locked_fields).Count -eq 0) { $review += "no-locked-fields" }
if (@($approval.applicability.exact_mods).Count -eq 0 -or -not $approval.applicability.structural_envelope.envelope_fingerprint_sha256) { $rejected += "applicability-envelope" }
$missingEvidence = @($approval.required_evidence | Where-Object { [string]$_ -notin @($assessment.evidence_sha256) })
if ($missingEvidence.Count -gt 0) { $review += "missing-evidence:" + ($missingEvidence -join ",") }
$edges = @{"unassigned"="provisional"; "provisional"="reserved"; "reserved"="stable-unreleased"; "stable-unreleased"="released"; "released"="retired"}
if ($edges[[string]$promotion.prior_identity_state] -ne [string]$promotion.identity_state) { $rejected += "identity-edge" }
if ([string]$promotion.identity_state -eq "released" -and $null -eq $migration -and [string]$promotion.migration_policy -ne "in-place-compatible") {
  $review += "migration-record-required"
}
if ($migration -and [string]$migration.approval_id -ne [string]$approval.approval_id) { $rejected += "migration-approval" }

$status = if ($rejected.Count -gt 0) { "REJECTED" } elseif ($review.Count -gt 0) { "REVIEW_REQUIRED" } else { "ADMITTED" }
$record = [ordered]@{
  schema=1; record_type="TechnologyPromotionAdmission"; status=$status
  candidate_id=[string]$promotion.candidate_id; technology_id=[string]$promotion.technology_id
  catalog_fingerprint=[string]$catalog.catalog_fingerprint; assessment_fingerprint=[string]$assessment.assessment_fingerprint
  approval_fingerprint=[string]$approval.approval_fingerprint_sha256; promotion_fingerprint=[string]$promotion.promotion_fingerprint_sha256
  rejected_reasons=@($rejected | Sort-Object -Unique); review_reasons=@($review | Sort-Object -Unique)
}
$record.admission_fingerprint = Get-MIRJsonSha256 $record
$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$record | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "[ok] wrote TechnologyPromotionAdmission $OutputPath status=$status"
