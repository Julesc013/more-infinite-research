param(
  [Parameter(Mandatory)][string]$CatalogPath,
  [Parameter(Mandatory)][string]$CandidateId,
  [string]$AssessmentPath,
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
$catalog = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $CatalogPath) | ConvertFrom-Json
if ([int]$catalog.schema -ne 3 -or [string]$catalog.phase -ne "final") { throw "Final TechnologyCatalog schema 3 is required." }
$candidate = @($catalog.candidates | Where-Object { [string]$_.candidate_id -eq $CandidateId })
$selection = @($catalog.current_selections | Where-Object { [string]$_.candidate_id -eq $CandidateId })
if ($candidate.Count -ne 1 -or $selection.Count -ne 1) { throw "Review dossier candidate or selection is ambiguous: $CandidateId" }
$assessment = if ($AssessmentPath) { Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $AssessmentPath) | ConvertFrom-Json } else { $null }
if ($assessment -and [string]$assessment.candidate_id -ne $CandidateId) { throw "Review dossier assessment candidate differs." }
$selected = @($candidate[0].alternatives | Where-Object { [string]$_.alternative_id -eq [string]$selection[0].alternative_id })[0]
$dossier = [ordered]@{
  schema=1; kind="mir-technology-review-dossier"; candidate_id=$CandidateId
  catalog_fingerprint=[string]$catalog.catalog_fingerprint
  candidate=$candidate[0]; current_selection=$selection[0]; selected_alternative=$selected
  rejected_alternatives=@($candidate[0].alternatives | Where-Object { [string]$_.alternative_id -ne [string]$selection[0].alternative_id })
  quality_assessment=$assessment
  review_checklist=@(
    "semantic membership and exclusions", "technology-tree placement and prerequisite arrows",
    "science and accepting-lab reachability", "effect magnitude and cost curve",
    "cross-version additions and removals", "identity, migration, and locked fields"
  )
}
$dossier.dossier_sha256 = Get-MIRJsonSha256 $dossier
$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$dossier | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "[ok] wrote technology review dossier $OutputPath"
