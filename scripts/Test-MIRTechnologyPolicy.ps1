param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")))

$ErrorActionPreference = "Stop"

$corpusPath = Join-Path $RepoRoot ".mir\technology-review-corpus.json"
$lifecyclePath = Join-Path $RepoRoot ".mir\technology-lifecycle.json"
$coveragePath = Join-Path $RepoRoot ".mir\compiler-contract-coverage.yml"
$compatibilityPath = Join-Path $RepoRoot ".mir\compatibility.yml"
$synthesisPath = Join-Path $RepoRoot ".mir\rule-synthesis.json"
$snapshotsPath = Join-Path $RepoRoot ".mir\technology-review-snapshots.json"

$corpus = Get-Content -Raw -LiteralPath $corpusPath | ConvertFrom-Json
if ($corpus.schema -ne 1 -or @($corpus.families).Count -eq 0) {
  throw "Technology review corpus must contain schema 1 family records."
}
$familyIds = @{}
foreach ($family in @($corpus.families)) {
  $familyId = [string]$family.family
  if ([string]::IsNullOrWhiteSpace($familyId) -or $familyIds.ContainsKey($familyId)) {
    throw "Technology review corpus contains a missing or duplicate family id: $familyId"
  }
  $familyIds[$familyId] = $true
  if ([string]::IsNullOrWhiteSpace([string]$family.structural_envelope)) {
    throw "Technology review corpus family $familyId omits its structural envelope id."
  }
  $positive = @($family.positive_examples)
  $negative = @($family.negative_examples)
  if ($positive.Count -eq 0 -or $negative.Count -eq 0) {
    throw "Technology review corpus family $familyId requires positive and negative examples."
  }
  $labels = @{}
  if (@($family.current_predicates).Count -eq 0) {
    throw "Technology review corpus family $familyId omits its current predicate baseline."
  }
  foreach ($entry in @($positive + $negative)) {
    foreach ($field in @("recipe", "fixture", "reason")) {
      if ([string]::IsNullOrWhiteSpace([string]$entry.$field)) {
        throw "Technology review corpus family $familyId contains an example without $field."
      }
    }
    $label = [string]$entry.recipe
    $polarity = if ($positive -contains $entry) { "include" } else { "exclude" }
    if ($labels.ContainsKey($label) -and $labels[$label] -ne $polarity) {
      throw "Technology review corpus family $familyId labels recipe $label both include and exclude."
    }
    $labels[$label] = $polarity
    if (@($entry.predicates).Count -eq 0) {
      throw "Technology review corpus example $familyId/$label omits its predicate vector."
    }
    $fixturePath = Join-Path $RepoRoot ("fixtures\" + [string]$entry.fixture)
    if (-not (Test-Path -LiteralPath $fixturePath -PathType Container)) {
      throw "Technology review corpus references missing fixture directory: $fixturePath"
    }
  }
}

$synthesis = Get-Content -Raw -LiteralPath $synthesisPath | ConvertFrom-Json
$snapshots = Get-Content -Raw -LiteralPath $snapshotsPath | ConvertFrom-Json
if ($synthesis.schema -ne 1 -or $synthesis.kind -ne "mir-offline-rule-synthesis-authority") {
  throw "Offline rule synthesis authority is invalid."
}
if ($snapshots.schema -ne 1 -or @($snapshots.snapshots).Count -eq 0) {
  throw "Reviewed ecosystem predicate snapshots are missing."
}
if (@($synthesis.production_entry_requirements).Count -ne 5 `
    -or "human-approved-rule-diff" -notin @($synthesis.production_entry_requirements)) {
  throw "Offline rule synthesis does not preserve its five review gates."
}

$lifecycle = Get-Content -Raw -LiteralPath $lifecyclePath | ConvertFrom-Json
if ([int]$lifecycle.records.TechnologyApplicabilityEnvelope -ne 1) {
  throw "Technology lifecycle authority omits TechnologyApplicabilityEnvelope schema 1."
}
$requiredPredicates = @(
  "family.semantic-signature", "output.deterministic-single-item", "output.place-result-family",
  "recipe.productivity-eligible", "recipe.visible", "risk.none"
)
if (@(Compare-Object $requiredPredicates @($lifecycle.applicability_predicates)).Count -ne 0) {
  throw "Technology applicability predicate authority differs from the governed finite set."
}

$coverage = Get-Content -Raw -LiteralPath $coveragePath
foreach ($category in @(
  "selectors", "normalizers", "partitioner", "tier_resolver", "effect_model", "science_model",
  "prerequisite_model", "cost_model", "presentation_model", "ownership_policy", "grouping"
)) {
  if (-not $coverage.Contains(('"' + $category + '"'))) {
    throw "Compiler contract coverage omits family operator category: $category"
  }
}

$compatibility = Get-Content -Raw -LiteralPath $compatibilityPath
foreach ($authority in @(
  "generated_policy_authority:",
  "prototypes/mir/compatibility/policy_authority.lua",
  ".mir/technology-review-corpus.json"
)) {
  if (-not $compatibility.Contains($authority)) {
    throw "Compatibility authority omits governed policy material: $authority"
  }
}

Write-Host "[ok] MIR technology policy authority, corpora, applicability envelopes, and operator coverage passed."
