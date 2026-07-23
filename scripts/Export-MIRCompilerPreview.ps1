param(
  [Parameter(Mandatory)][string]$CatalogPath,
  [string]$EvidencePath,
  [Parameter(Mandatory)][string]$OutputDirectory,
  [ValidateRange(1, 500)][int]$Top = 50
)

$ErrorActionPreference = "Stop"

function Get-MIRJsonSha256 {
  param($Value)
  $json = $Value | ConvertTo-Json -Depth 100 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $hash = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return ([BitConverter]::ToString($hash)).Replace("-", "")
}

function ConvertTo-MIRReasonText {
  param($Value)
  if ($null -eq $Value) { return "" }
  if ($Value -is [string]) { return [string]$Value }
  return (@($Value | ForEach-Object { [string]$_ }) -join "; ")
}

function ConvertTo-MIRMarkdownCell {
  param($Value)
  return ([string]$Value).Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
}

$resolvedCatalog = (Resolve-Path -LiteralPath $CatalogPath).Path
$catalog = Get-Content -Raw -LiteralPath $resolvedCatalog | ConvertFrom-Json
if ([int]$catalog.schema -ne 3 -or [string]$catalog.phase -ne "final") {
  throw "Compiler PREVIEW export requires the exact final TechnologyCatalog schema 3 artifact."
}
foreach ($field in @("catalog_fingerprint", "generation_plan_fingerprint", "compilation_plan_fingerprint")) {
  if ([string]::IsNullOrWhiteSpace([string]$catalog.$field)) {
    throw "Compiler PREVIEW catalog field is required: $field"
  }
}

$evidence = $null
if ($EvidencePath) {
  $evidence = Get-Content -Raw -LiteralPath (Resolve-Path -LiteralPath $EvidencePath) | ConvertFrom-Json
}

$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$fullCatalogPath = Join-Path $outputRoot "technology-catalog.full.json"
if (-not [string]::Equals($resolvedCatalog, $fullCatalogPath, [StringComparison]::OrdinalIgnoreCase)) {
  [IO.File]::Copy($resolvedCatalog, $fullCatalogPath, $true)
}

$selected = @($catalog.current_selections | ForEach-Object {
  [pscustomobject][ordered]@{
    candidate_id = [string]$_.candidate_id
    alternative_id = [string]$_.alternative_id
    action = [string]$_.action
    design_fingerprint = [string]$_.design_fingerprint
    qualification_fingerprint = [string]$_.qualification_fingerprint
  }
} | Sort-Object candidate_id, alternative_id | Select-Object -First $Top)

$ambiguous = @()
$rejected = @()
foreach ($qualification in @($catalog.qualifications)) {
  $decision = [string]$(if ($qualification.qualification_decision) { $qualification.qualification_decision } else { $qualification.decision })
  $row = [pscustomobject][ordered]@{
    candidate_id = [string]$qualification.candidate_id
    alternative_id = [string]$qualification.alternative_id
    decision = $decision
    reasons = ConvertTo-MIRReasonText $(if ($qualification.rejection_reasons) { $qualification.rejection_reasons } else { $qualification.reasons })
    design_fingerprint = [string]$qualification.design_fingerprint
    qualification_fingerprint = [string]$qualification.qualification_fingerprint
  }
  if ($decision -in @("proposal", "review-required", "REVIEW_REQUIRED", "ambiguous")) { $ambiguous += $row }
  if ($decision -in @("rejected", "REJECTED", "failed")) { $rejected += $row }
}
$ambiguous = @($ambiguous | Sort-Object candidate_id, alternative_id | Select-Object -First $Top)
$rejected = @($rejected | Sort-Object candidate_id, alternative_id | Select-Object -First $Top)

$providerDecisions = @()
if ($evidence -and $evidence.provider_resolution) { $providerDecisions = @($evidence.provider_resolution.decisions) }
$ecosystem = @($providerDecisions | Where-Object {
  $_.compatibility_pack -or $_.mod_id -or $_.target_support -or $_.provider_id
} | ForEach-Object {
  [pscustomobject][ordered]@{
    provider_id = [string]$_.provider_id
    prototype = ([string]$_.prototype_type + ":" + [string]$_.prototype_name).Trim(":")
    target_stream = [string]$_.target_stream
    compatibility_pack = [string]$_.compatibility_pack
    final_state = [string]$_.final_state
    risk_disposition = [string]$_.risk_disposition
    reason = ConvertTo-MIRReasonText $(if ($_.reason) { $_.reason } else { $_.blocker })
    decision_fingerprint = [string]$_.decision_fingerprint
  }
} | Sort-Object provider_id, prototype, target_stream | Select-Object -First $Top)

$budgetProfilePath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path ".mir\public-artifact-budgets.json"
$budgetProfile = Get-Content -Raw -LiteralPath $budgetProfilePath | ConvertFrom-Json
$counterByKind = @{
  "mir-generation-plan-public" = "generation_plan_public_bytes"
  "mir-technology-catalog-public" = "technology_catalog_public_bytes"
  "mir-coverage-public" = "coverage_public_bytes"
  "mir-compiler-evidence-public" = "compiler_evidence_public_bytes"
}
$telemetryCounters = if ($evidence -and $evidence.telemetry) { $evidence.telemetry.counters } else { $null }
$budgets = @()
foreach ($budget in @($budgetProfile.artifacts | Sort-Object kind)) {
  $kind = [string]$budget.kind
  $counter = [string]$counterByKind[$kind]
  $observed = if ($telemetryCounters -and $null -ne $telemetryCounters.$counter) { [long]$telemetryCounters.$counter } else { $null }
  $status = if ($null -eq $observed) { "not-observed" } elseif ($observed -le [long]$budget.max_canonical_bytes) { "pass" } else { "over-budget" }
  $budgets += [pscustomobject][ordered]@{
    kind = $kind
    counter = $counter
    observed_canonical_bytes = $observed
    maximum_canonical_bytes = [long]$budget.max_canonical_bytes
    status = $status
  }
}

$providerBudgetReviews = @($providerDecisions | Where-Object {
  ([string]$_.final_state -match "review") -and
  (([string]$_.reason -match "budget") -or ([string]$_.blocker -match "budget") -or ([string]$_.code -match "budget"))
} | ForEach-Object {
  [pscustomobject][ordered]@{
    provider_id = [string]$_.provider_id
    prototype = ([string]$_.prototype_type + ":" + [string]$_.prototype_name).Trim(":")
    code = [string]$_.code
    reason = ConvertTo-MIRReasonText $(if ($_.reason) { $_.reason } else { $_.blocker })
  }
} | Sort-Object provider_id, prototype | Select-Object -First $Top)

$summary = [ordered]@{
  schema = 1
  kind = "mir-compiler-preview-summary"
  catalog_schema = [int]$catalog.schema
  catalog_fingerprint = [string]$catalog.catalog_fingerprint
  generation_plan_fingerprint = [string]$catalog.generation_plan_fingerprint
  compilation_plan_fingerprint = [string]$catalog.compilation_plan_fingerprint
  counts = [ordered]@{
    candidates = @($catalog.candidates).Count
    qualifications = @($catalog.qualifications).Count
    selections = @($catalog.current_selections).Count
    ambiguous_or_review_required = @($catalog.qualifications | Where-Object {
      ([string]$_.qualification_decision) -in @("proposal", "review-required", "REVIEW_REQUIRED", "ambiguous") -or
      ([string]$_.decision) -in @("proposal", "review-required", "REVIEW_REQUIRED", "ambiguous")
    }).Count
    rejected = @($catalog.qualifications | Where-Object {
      ([string]$_.qualification_decision) -in @("rejected", "REJECTED", "failed") -or
      ([string]$_.decision) -in @("rejected", "REJECTED", "failed")
    }).Count
    provider_decisions = $providerDecisions.Count
  }
  top_limit = $Top
  selected_decisions = $selected
  ambiguous_cases = $ambiguous
  rejected_designs = $rejected
  ecosystem_dependent_decisions = $ecosystem
  public_artifact_budgets = $budgets
  provider_budget_reviews = $providerBudgetReviews
}
$summary.summary_sha256 = Get-MIRJsonSha256 $summary
$summaryPath = Join-Path $outputRoot "compiler-preview-summary.json"
$summary | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$markdown = [Collections.Generic.List[string]]::new()
$markdown.Add("# MIR Compiler PREVIEW Summary")
$markdown.Add("")
$markdown.Add("- Catalog fingerprint: ``$($summary.catalog_fingerprint)``")
$markdown.Add("- Candidates: $($summary.counts.candidates); selections: $($summary.counts.selections); review/ambiguous: $($summary.counts.ambiguous_or_review_required); rejected: $($summary.counts.rejected)")
$markdown.Add("- Summary SHA-256: ``$($summary.summary_sha256)``")
$markdown.Add("")
foreach ($section in @(
  @{Title="Selected decisions"; Rows=$selected; Columns=@("candidate_id", "alternative_id", "action")},
  @{Title="Ambiguous or review-required cases"; Rows=$ambiguous; Columns=@("candidate_id", "alternative_id", "decision", "reasons")},
  @{Title="Rejected designs"; Rows=$rejected; Columns=@("candidate_id", "alternative_id", "decision", "reasons")},
  @{Title="Ecosystem-dependent provider decisions"; Rows=$ecosystem; Columns=@("provider_id", "prototype", "target_stream", "compatibility_pack", "final_state", "reason")},
  @{Title="Public artifact budgets"; Rows=$budgets; Columns=@("kind", "observed_canonical_bytes", "maximum_canonical_bytes", "status")},
  @{Title="Provider budget reviews"; Rows=$providerBudgetReviews; Columns=@("provider_id", "prototype", "code", "reason")}
)) {
  $markdown.Add("## $($section.Title)")
  $markdown.Add("")
  if (@($section.Rows).Count -eq 0) {
    $markdown.Add("None recorded.")
    $markdown.Add("")
    continue
  }
  $markdown.Add("| " + ($section.Columns -join " | ") + " |")
  $markdown.Add("| " + (($section.Columns | ForEach-Object { "---" }) -join " | ") + " |")
  foreach ($row in @($section.Rows)) {
    $values = foreach ($column in $section.Columns) { ConvertTo-MIRMarkdownCell $row.$column }
    $markdown.Add("| " + ($values -join " | ") + " |")
  }
  $markdown.Add("")
}
$markdownPath = Join-Path $outputRoot "compiler-preview-summary.md"
$markdown | Set-Content -LiteralPath $markdownPath -Encoding UTF8

Write-Host "[ok] wrote full compiler PREVIEW catalog and reviewer summaries to $outputRoot"
