param(
  [Parameter(Mandatory)][string]$CatalogPath,
  [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = "Stop"

$resolved = (Resolve-Path -LiteralPath $CatalogPath).Path
$catalog = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json
if ([int]$catalog.schema -ne 3 -or [string]$catalog.phase -ne "final") {
  throw "Export requires the exact final TechnologyCatalog schema 3 artifact."
}
if ([bool]$catalog.mutation_authority -or [string]$catalog.selection_authority -ne "deterministic-policy-v2") {
  throw "TechnologyCatalog authority fields are invalid."
}
foreach ($field in @(
  "candidate_catalog_fingerprint", "qualification_catalog_fingerprint", "preselection_catalog_fingerprint",
  "selection_fingerprint", "catalog_fingerprint", "generation_plan_fingerprint", "compilation_plan_fingerprint"
)) {
  if ([string]::IsNullOrWhiteSpace([string]$catalog.$field)) { throw "TechnologyCatalog field is required: $field" }
}
$candidateIds = @{}
foreach ($candidate in @($catalog.candidates)) {
  $candidateId = [string]$candidate.candidate_id
  if ([string]::IsNullOrWhiteSpace($candidateId) -or $candidateIds.ContainsKey($candidateId)) {
    throw "TechnologyCatalog candidate identity is invalid or duplicated: $candidateId"
  }
  $candidateIds[$candidateId] = $true
  foreach ($alternative in @($candidate.alternatives)) {
    if ($null -eq $alternative.technology_design `
        -or [string]$alternative.technology_design.design_fingerprint -ne [string]$alternative.design_fingerprint) {
      throw "TechnologyCatalog alternative does not preserve its exact TechnologyDesign: $candidateId"
    }
  }
}
foreach ($selection in @($catalog.current_selections)) {
  if (-not $candidateIds.ContainsKey([string]$selection.candidate_id)) {
    throw "TechnologyCatalog selection references an unknown candidate: $($selection.candidate_id)"
  }
}

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$destination = [IO.Path]::GetFullPath($OutputPath)
if (-not [string]::Equals($resolved, $destination, [StringComparison]::OrdinalIgnoreCase)) {
  [IO.File]::Copy($resolved, $destination, $true)
}
Write-Host "[ok] copied exact MIR TechnologyCatalog schema 3 artifact $OutputPath candidates=$(@($catalog.candidates).Count)"
